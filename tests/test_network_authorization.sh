#!/usr/bin/env bash

# Installer-side deployment contract for the Aurelia Network DNS helper.
# The runtime fixture redirects sudo's target paths into a temporary root; it
# never writes the live /usr/local/bin or /etc/sudoers.d directories.

section "Aurelia Network DNS authorization"

sudoers_file="$ROOT/config/sudoers.d/aurelia-network-dns"
sudoers_policy='%wheel ALL=(root) NOPASSWD: /usr/local/bin/aurelia-network-dns Cloudflare, /usr/local/bin/aurelia-network-dns Google, /usr/local/bin/aurelia-network-dns DHCP'

if [[ -f "$sudoers_file" ]] && grep -Fqx "$sudoers_policy" "$sudoers_file"; then
    pass "managed sudoers policy permits only stock DNS providers"
else
    fail "managed sudoers policy is missing or broader than stock DNS providers"
fi

if ! grep -Fqx "$sudoers_policy" "$sudoers_file" 2>/dev/null ||
    grep -Fqx '%wheel ALL=(root) NOPASSWD: /usr/local/bin/aurelia-network-dns Custom' "$sudoers_file" 2>/dev/null; then
    fail "Custom DNS unexpectedly has a passwordless sudo rule"
else
    pass "Custom DNS is not passwordless"
fi

if command -v visudo >/dev/null 2>&1 && visudo -cf "$sudoers_file" >/dev/null 2>&1; then
    pass "managed sudoers policy passes visudo"
else
    fail "managed sudoers policy does not pass visudo"
fi

if grep -Fq 'install_aurelia_network_dns_authorization' "$ROOT/install.sh" &&
    grep -Fq 'run_classified_step workstation "Installing Aurelia network DNS authorization" install_aurelia_network_dns_authorization' "$ROOT/install.sh" &&
    grep -Fq '[[ "${DESKTOP_SHELL:-}" != "aurelia" ]]' "$ROOT/modules/desktop.sh"; then
    pass "authorization stage is wired and gated to the Aurelia desktop shell"
else
    fail "installer authorization stage is not wired or shell-gated"
fi

authorization_runtime="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail

root="$1"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

fake_root="$sandbox/fake-root"
mkdir -p "$fake_root/usr/local/bin" "$fake_root/etc/sudoers.d" "$sandbox/bin"

cat > "$sandbox/bin/sudo" <<'FAKE_SUDO'
#!/usr/bin/env bash
set -Eeuo pipefail

fake_root="${AURELIA_TEST_ROOT:?}"

rewrite_path() {
    case "$1" in
        /usr/local/bin/*|/etc/sudoers.d/*)
            printf '%s%s' "$fake_root" "$1"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

command_name="${1:-}"
shift || true

case "$command_name" in
    install)
        install_args=()
        skip_next=0
        for arg in "$@"; do
            if (( skip_next == 1 )); then
                skip_next=0
                continue
            fi

            case "$arg" in
                -o|-g)
                    skip_next=1
                    ;;
                /usr/local/bin/*|/etc/sudoers.d/*)
                    install_args+=("$(rewrite_path "$arg")")
                    ;;
                *)
                    install_args+=("$arg")
                    ;;
            esac
        done
        exec /usr/bin/install "${install_args[@]}"
        ;;
    mv)
        mv_args=()
        for arg in "$@"; do
            case "$arg" in
                /usr/local/bin/*|/etc/sudoers.d/*)
                    mv_args+=("$(rewrite_path "$arg")")
                    ;;
                *)
                    mv_args+=("$arg")
                    ;;
            esac
        done
        exec /usr/bin/mv "${mv_args[@]}"
        ;;
    rm)
        rm_args=()
        for arg in "$@"; do
            case "$arg" in
                /usr/local/bin/*|/etc/sudoers.d/*)
                    rm_args+=("$(rewrite_path "$arg")")
                    ;;
                *)
                    rm_args+=("$arg")
                    ;;
            esac
        done
        exec /usr/bin/rm "${rm_args[@]}"
        ;;
    */visudo)
        visudo_args=()
        for arg in "$@"; do
            case "$arg" in
                /usr/local/bin/*|/etc/sudoers.d/*)
                    visudo_args+=("$(rewrite_path "$arg")")
                    ;;
                *)
                    visudo_args+=("$arg")
                    ;;
            esac
        done
        exec /usr/bin/visudo "${visudo_args[@]}"
        ;;
    *)
        printf 'unexpected fake sudo command: %s\n' "$command_name" >&2
        exit 1
        ;;
esac
FAKE_SUDO
chmod 0755 "$sandbox/bin/sudo"

export AURELIA_TEST_ROOT="$fake_root"
export PATH="$sandbox/bin:$PATH"
export SCRIPT_DIR="$root"
export DESKTOP_SHELL=noctalia

# shellcheck source=/dev/null
source "$root/modules/common.sh"
# shellcheck source=/dev/null
source "$root/modules/status.sh"
# shellcheck source=/dev/null
source "$root/modules/desktop.sh"

install_aurelia_network_dns_authorization
[[ ! -e "$fake_root/usr/local/bin/aurelia-network-dns" ]]
[[ ! -e "$fake_root/etc/sudoers.d/aurelia-network-dns" ]]

export DESKTOP_SHELL=aurelia
install_aurelia_network_dns_authorization

[[ -f "$fake_root/usr/local/bin/aurelia-network-dns" ]]
[[ -f "$fake_root/usr/local/bin/aurelia-network-dns-terminal" ]]
[[ -f "$fake_root/etc/sudoers.d/aurelia-network-dns" ]]
[[ "$(stat -c '%a' "$fake_root/usr/local/bin/aurelia-network-dns")" == 755 ]]
[[ "$(stat -c '%a' "$fake_root/usr/local/bin/aurelia-network-dns-terminal")" == 755 ]]
[[ "$(stat -c '%a' "$fake_root/etc/sudoers.d/aurelia-network-dns")" == 440 ]]
/usr/bin/visudo -cf "$fake_root/etc/sudoers.d/aurelia-network-dns" >/dev/null 2>&1
printf 'installed=1\n'
EOS
)"

if printf '%s\n' "$authorization_runtime" | grep -q '^installed=1$'; then
    pass "installer deploys both DNS helpers and validates the installed policy in an isolated root"
else
    fail "isolated installer deployment fixture failed: $authorization_runtime"
fi
