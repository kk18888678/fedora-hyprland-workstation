#!/usr/bin/env bash

# Local static and unit tests for the Fedora Hyprland workstation installer.
# These tests do not provision a VM and do not modify the host desktop.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FAILS=0
PASSES=0

pass() {
    PASSES=$((PASSES + 1))
    printf '  PASS %s\n' "$*"
}

fail() {
    FAILS=$((FAILS + 1))
    printf '  FAIL %s\n' "$*"
}

section() {
    printf '\n== %s ==\n' "$*"
}

###############################################################################
# bash -n / shellcheck
###############################################################################

section "Syntax"

mapfile -t BASH_FILES < <(
    find "$ROOT" -type f -name '*.sh' | sort
)

for file in "${BASH_FILES[@]}"; do
    if bash -n "$file"; then
        pass "bash -n ${file#"$ROOT"/}"
    else
        fail "bash -n ${file#"$ROOT"/}"
    fi
done

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck --shell=bash \
        --exclude=SC1090,SC1091,SC2034,SC2154,SC2329 \
        "${BASH_FILES[@]}"; then
        pass "shellcheck"
    else
        fail "shellcheck"
    fi
else
    printf '  SKIP shellcheck (not installed)\n'
fi

###############################################################################
# Duplicate functions
###############################################################################

section "Duplicate function definitions"

dupes="$(
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$ROOT"/modules/*.sh |
        sed 's/() {//' |
        grep -vx die |
        sort |
        uniq -d || true
)"

if [[ -z "$dupes" ]]; then
    pass "no duplicate function names across modules"
else
    fail "duplicate functions: $dupes"
fi

###############################################################################
# Referenced paths
###############################################################################

section "Repository paths"

required_paths=(
    install.sh
    config/versions.conf
    config/noctalia-greeter/greeter.toml
    packages/base.txt
    packages/desktop.txt
    packages/media.txt
    profiles/vm.conf
    profiles/workstation.conf
    modules/common.sh
    modules/status.sh
    modules/state.sh
    modules/repositories.sh
    modules/packages.sh
    modules/shell.sh
    modules/browsers.sh
    modules/applications.sh
    modules/flatpak.sh
    modules/desktop.sh
    modules/nix.sh
    modules/containers.sh
    modules/validation.sh
    dotfiles/zsh/.zshrc
    dotfiles/starship/starship.toml
    dotfiles/kitty/kitty.conf
    dotfiles/hypr/hyprland.lua
)

for rel in "${required_paths[@]}"; do
    if [[ -e "$ROOT/$rel" ]]; then
        pass "exists $rel"
    else
        fail "missing $rel"
    fi
done

###############################################################################
# Manifests
###############################################################################

section "Package manifests"

assert_not_in_manifest() {
    local name="$1"

    if grep -h -vE '^\s*#' "$ROOT"/packages/*.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qx "$name"; then
        fail "forbidden package present: $name"
    else
        pass "forbidden package absent: $name"
    fi
}

assert_in_manifest() {
    local file="$1"
    local name="$2"

    if grep -h -vE '^\s*#' "$ROOT/$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qx "$name"; then
        pass "$name in $file"
    else
        fail "$name missing from $file"
    fi
}

assert_not_in_manifest mesa-vdpau-drivers
assert_not_in_manifest p7zip
assert_not_in_manifest p7zip-plugins
assert_not_in_manifest wget
assert_in_manifest packages/base.txt wget2-wget
assert_in_manifest packages/base.txt 7zip
assert_in_manifest packages/base.txt 7zip-standalone
assert_in_manifest packages/desktop.txt hyprland
assert_in_manifest packages/desktop.txt noctalia
assert_in_manifest packages/desktop.txt greetd
assert_in_manifest packages/desktop.txt hyprpolkitagent
assert_in_manifest packages/desktop.txt xdg-desktop-portal-hyprland
assert_in_manifest packages/desktop.txt adwaita-cursor-theme
assert_in_manifest packages/base.txt zsh
assert_in_manifest packages/base.txt starship

if grep -vE '^\s*#' "$ROOT"/packages/base.txt | grep -qw chromium; then
    fail "chromium belongs in the browser module, not base.txt"
else
    pass "chromium is not in base.txt"
fi

###############################################################################
# Profile variables
###############################################################################

section "Profiles"

check_profile() {
    local file="$1"

    # shellcheck source=/dev/null
    source "$file"

    local required=(
        PROFILE_NAME GPU DESKTOP DESKTOP_SHELL SHELL PROMPT
        OH_MY_ZSH BROWSER_CHROMIUM BROWSER_ULAA BROWSER_BRAVE_ORIGIN
        BROWSER_FIREFOX CURSOR BLUETOOTH GAMING FLATPAK NIX PODMAN
        NVIDIA ROCM ENABLE_GRAPHICAL_TARGET INSTALL_GREETER INSTALL_NOCTALIA
    )

    local var
    for var in "${required[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            fail "$file missing $var"
        else
            pass "$file has $var"
        fi
    done

    if [[ "$DESKTOP" != "hyprland" ]]; then
        fail "$file DESKTOP is not hyprland"
    else
        pass "$file DESKTOP=hyprland"
    fi

    if [[ "$DESKTOP_SHELL" != "noctalia" ]]; then
        fail "$file DESKTOP_SHELL is not noctalia"
    else
        pass "$file DESKTOP_SHELL=noctalia"
    fi

    if [[ "$BROWSER_ULAA" != "false" ]]; then
        fail "$file should keep Ulaa disabled on Fedora"
    else
        pass "$file Ulaa disabled"
    fi
}

check_profile "$ROOT/profiles/vm.conf"
check_profile "$ROOT/profiles/workstation.conf"

###############################################################################
# Function coverage
###############################################################################

section "Installer steps resolve to functions"

needed_functions=(
    prepare_system
    configure_repositories
    install_packages
    configure_shell
    install_browsers
    install_applications
    configure_flatpak
    install_desktop
    install_nix
    configure_containers
    validate_system
    activate_graphical_session
    run_classified_step
    record_deferred
    record_required
    record_activation_failure
    installer_exit_code
    clone_pinned_git
    validate_hyprland_desktop
    validate_greeter_configuration
    validate_graphical_activation
    validate_login_stack
    validate_workstation_environment
    activate_graphical_session
)

defined="$(
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$ROOT"/modules/*.sh |
        sed 's/() {//'
)"

for fn in "${needed_functions[@]}"; do
    if printf '%s\n' "$defined" | grep -Fxq "$fn"; then
        pass "function $fn"
    else
        fail "missing function $fn"
    fi
done

if grep -R "command -v hyprpolkitagent" "$ROOT"/modules >/dev/null; then
    fail "bogus hyprpolkitagent PATH check is present"
else
    pass "no PATH check for hyprpolkitagent"
fi

if grep -R "systemctl enable --now greetd" "$ROOT"/modules "$ROOT"/install.sh >/dev/null; then
    fail "greetd must not be enable --now"
else
    pass "greetd is not enable --now"
fi

if grep -R "user = \"greeter\"" "$ROOT" >/dev/null; then
    fail "greeter user must not be used"
else
    pass "greetd user is used, not greeter"
fi

###############################################################################
# Helpers: retry / status / manifests
###############################################################################

section "Helper behaviour"

HELPER_ROOT="$ROOT"
export HELPER_ROOT

helper_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/packages.sh"

RETRY_BACKOFF_SECONDS=(0 0)
attempts=0
flaky() {
    attempts=$((attempts + 1))
    if (( attempts < 3 )); then
        return 1
    fi
    return 0
}

if ! run_with_retry "flaky helper" flaky; then
    echo "retry-fail"
    exit 1
fi
echo "retry-ok attempts=$attempts"

never() { return 1; }
if run_with_retry "never" never; then
    echo "retry-should-fail"
    exit 1
fi
echo "retry-gave-up"

record_success "alpha"
echo "exit-success=$(installer_exit_code)"

record_deferred "browsers" "ulaa" "unsupported"
echo "exit-deferred=$(installer_exit_code)"
echo "deferred-blocked=$ACTIVATION_BLOCKED"

record_required "browsers" "chromium" "missing"
echo "exit-required=$(installer_exit_code)"
echo "required-blocked=$ACTIVATION_BLOCKED"

record_required "nix" "devenv" "missing"
echo "nix-blocked=$ACTIVATION_BLOCKED"

record_required "containers" "podman" "missing"
echo "podman-blocked=$ACTIVATION_BLOCKED"

record_activation_failure "desktop" "hyprland" "missing"
echo "exit-login=$(installer_exit_code)"
echo "login-blocked=$ACTIVATION_BLOCKED"

packages=()
while IFS= read -r package; do
    packages+=("$package")
done < <(read_package_manifest "$SCRIPT_DIR/packages/desktop.txt")

if [[ ${#packages[@]} -lt 5 ]]; then
    echo "manifest-too-small"
    exit 1
fi
echo "manifest-count=${#packages[@]}"

if printf '%s\n' "${packages[@]}" | grep -qx "adwaita-cursor-theme"; then
    echo "manifest-cursor-ok"
else
    echo "manifest-cursor-missing"
    exit 1
fi

# Package helpers and manifest validation
if package_installed wget2-wget; then
    echo "pkg-installed-wget2-ok"
fi

if package_installed 7zip; then
    echo "pkg-installed-7zip-ok"
fi

if package_installed 7zip-standalone; then
    echo "pkg-installed-7zip-sa-ok"
fi

if package_installed wget; then
    echo "pkg-installed-wget-cap-ok"
fi

if ! package_installed nonexistent-pkg-fake; then
    echo "pkg-installed-nonexistent-fail-ok"
fi

if package_available wget2-wget; then
    echo "pkg-avail-wget2-ok"
fi

if package_available 7zip; then
    echo "pkg-avail-7zip-ok"
fi

if package_available 7zip-standalone; then
    echo "pkg-avail-7zip-sa-ok"
fi

if package_available wget; then
    echo "pkg-avail-wget-cap-ok"
fi

if ! package_available nonexistent-pkg-fake; then
    echo "pkg-avail-nonexistent-fail-ok"
fi

if validate_manifest_packages "$SCRIPT_DIR/packages/base.txt"; then
    echo "validate-base-manifest-ok"
fi

tmp_manifest="$(mktemp)"
echo "nonexistent-pkg-fake" > "$tmp_manifest"
if ! validate_manifest_packages "$tmp_manifest" 2>/dev/null; then
    echo "validate-invalid-manifest-rejected-ok"
fi
if ! install_manifest "$tmp_manifest" 2>/dev/null; then
    echo "install-invalid-manifest-rejected-ok"
fi
rm -f "$tmp_manifest"
EOS
)"

if printf '%s\n' "$helper_output" | grep -q 'retry-ok attempts=3'; then
    pass "retry succeeds on third attempt"
else
    fail "retry helper: $helper_output"
fi

if printf '%s\n' "$helper_output" | grep -q 'retry-gave-up'; then
    pass "retry classifies permanent failure"
else
    fail "retry did not give up as expected"
fi

if printf '%s\n' "$helper_output" | grep -q 'exit-success=0'; then
    pass "exit code 0 for success"
else
    fail "success exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'exit-deferred=2'; then
    pass "exit code 2 for deferred"
else
    fail "deferred exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'deferred-blocked=0'; then
    pass "deferred failure does not block activation"
else
    fail "deferred activation blocking"
fi

if printf '%s\n' "$helper_output" | grep -q 'exit-required=1'; then
    pass "exit code 1 for required non-login failure"
else
    fail "required exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'required-blocked=0'; then
    pass "missing Chromium does not set ACTIVATION_BLOCKED"
else
    fail "Chromium must not block activation"
fi

if printf '%s\n' "$helper_output" | grep -q 'nix-blocked=0'; then
    pass "missing Nix/devenv does not set ACTIVATION_BLOCKED"
else
    fail "Nix must not block activation"
fi

if printf '%s\n' "$helper_output" | grep -q 'podman-blocked=0'; then
    pass "missing Podman does not set ACTIVATION_BLOCKED"
else
    fail "Podman must not block activation"
fi

if printf '%s\n' "$helper_output" | grep -q 'exit-login=1'; then
    pass "exit code 1 for login-critical failure"
else
    fail "login-critical exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'login-blocked=1'; then
    pass "Hyprland validation failure sets ACTIVATION_BLOCKED=1"
else
    fail "Hyprland must block activation"
fi

if printf '%s\n' "$helper_output" | grep -q 'manifest-cursor-ok'; then
    pass "desktop manifest parsing"
else
    fail "desktop manifest parsing: $helper_output"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-wget2-ok'; then
    pass "package_installed wget2-wget"
else
    fail "package_installed wget2-wget"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-7zip-ok'; then
    pass "package_installed 7zip"
else
    fail "package_installed 7zip"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-7zip-sa-ok'; then
    pass "package_installed 7zip-standalone"
else
    fail "package_installed 7zip-standalone"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-wget-cap-ok'; then
    pass "package_installed resolves wget capability"
else
    fail "package_installed resolves wget capability"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-nonexistent-fail-ok'; then
    pass "package_installed rejects nonexistent package"
else
    fail "package_installed rejects nonexistent package"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-wget2-ok'; then
    pass "package_available wget2-wget"
else
    fail "package_available wget2-wget"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-7zip-ok'; then
    pass "package_available 7zip"
else
    fail "package_available 7zip"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-7zip-sa-ok'; then
    pass "package_available 7zip-standalone"
else
    fail "package_available 7zip-standalone"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-wget-cap-ok'; then
    pass "package_available resolves wget capability"
else
    fail "package_available resolves wget capability"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-nonexistent-fail-ok'; then
    pass "package_available rejects nonexistent package"
else
    fail "package_available rejects nonexistent package"
fi

if printf '%s\n' "$helper_output" | grep -q 'validate-base-manifest-ok'; then
    pass "validate_manifest_packages succeeds on base.txt"
else
    fail "validate_manifest_packages fails on base.txt"
fi

if printf '%s\n' "$helper_output" | grep -q 'validate-invalid-manifest-rejected-ok'; then
    pass "validate_manifest_packages rejects nonexistent package"
else
    fail "validate_manifest_packages does not reject nonexistent package"
fi

if printf '%s\n' "$helper_output" | grep -q 'install-invalid-manifest-rejected-ok'; then
    pass "install_manifest rejects invalid manifest"
else
    fail "install_manifest does not reject invalid manifest"
fi

###############################################################################
# Orchestration: non-login failures cannot skip safe activation
###############################################################################

section "Activation orchestration"

orch_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

validate_hyprland_desktop() { return 0; }
validate_greeter_configuration() { return 0; }
enable_greetd() { :; }
configure_graphical_target() { :; }
validate_graphical_activation() { return 0; }

unexpected_podman() { return 9; }

run_classified_step workstation "podman" unexpected_podman
echo "after-unexpected-blocked=$ACTIVATION_BLOCKED"
echo "after-unexpected-exit=$(installer_exit_code)"

run_classified_step login "activate" activate_graphical_session
echo "after-podman-activation=$GRAPHICAL_ACTIVATION_STATE"
echo "after-podman-blocked=$ACTIVATION_BLOCKED"
echo "after-podman-exit=$(installer_exit_code)"
EOS
)"

if printf '%s\n' "$orch_output" | grep -q 'after-unexpected-blocked=0'; then
    pass "uncaught Podman failure does not set ACTIVATION_BLOCKED"
else
    fail "uncaught Podman blocked activation: $orch_output"
fi

if printf '%s\n' "$orch_output" | grep -q 'after-unexpected-exit=1'; then
    pass "uncaught required non-login failure produces exit code 1"
else
    fail "uncaught non-login exit code: $orch_output"
fi

if printf '%s\n' "$orch_output" | grep -q 'after-podman-activation=completed'; then
    pass "required non-login failure still permits activate_graphical_session"
else
    fail "activation skipped after Podman failure: $orch_output"
fi

greeter_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

INSTALL_GREETER=true
ENABLE_GRAPHICAL_TARGET=true

validate_hyprland_desktop() { return 0; }
validate_greeter_configuration() { return 1; }

activate_graphical_session
echo "greeter-blocked=$ACTIVATION_BLOCKED"
echo "greeter-activation=$GRAPHICAL_ACTIVATION_STATE"
echo "greeter-exit=$(installer_exit_code)"
EOS
)"

if printf '%s\n' "$greeter_output" | grep -q 'greeter-blocked=1'; then
    pass "greetd/Noctalia greeter validation failure sets ACTIVATION_BLOCKED=1"
else
    fail "greeter must block activation: $greeter_output"
fi

if printf '%s\n' "$greeter_output" | grep -q 'greeter-activation=skipped'; then
    pass "activation is skipped when ACTIVATION_BLOCKED=1"
else
    fail "activation not skipped: $greeter_output"
fi

skip_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

enabled=0
enable_greetd() { enabled=1; }
configure_graphical_target() { enabled=1; }

ACTIVATION_BLOCKED=1
activate_graphical_session
echo "skip-enable=$enabled"
echo "skip-state=$GRAPHICAL_ACTIVATION_STATE"
EOS
)"

if printf '%s\n' "$skip_output" | grep -q 'skip-enable=0' &&
    printf '%s\n' "$skip_output" | grep -q 'skip-state=skipped'; then
    pass "blocked activation does not enable greetd"
else
    fail "blocked activation still enabled greetd: $skip_output"
fi

###############################################################################
# Greeter cursor config
###############################################################################

section "Greeter cursor"

if grep -q 'theme = "Adwaita"' "$ROOT/config/noctalia-greeter/greeter.toml" &&
    grep -q 'size = 24' "$ROOT/config/noctalia-greeter/greeter.toml"; then
    pass "managed greeter.toml sets Adwaita 24"
else
    fail "managed greeter.toml cursor block"
fi

###############################################################################
# Pinned versions
###############################################################################

section "Pins"

# shellcheck source=/dev/null
source "$ROOT/config/versions.conf"

for var in OH_MY_ZSH_COMMIT ZSH_AUTOSUGGESTIONS_COMMIT \
    ZSH_SYNTAX_HIGHLIGHTING_COMMIT NIXPKGS_REV DEVENV_NIX_INSTALL_SPEC; do
    if [[ -n "${!var:-}" ]]; then
        pass "pin $var"
    else
        fail "pin missing $var"
    fi
done

if [[ "$DEVENV_NIX_INSTALL_SPEC" == *nixpkgs#devenv && "$DEVENV_NIX_INSTALL_SPEC" != *"github:NixOS/nixpkgs/"* ]]; then
    fail "devenv install spec is unpinned nixpkgs#devenv"
else
    pass "devenv install spec is pinned"
fi

###############################################################################
# Summary
###############################################################################

printf '\n%s\n' "------------------------------------------------------------"
printf 'Passed: %s  Failed: %s\n' "$PASSES" "$FAILS"

if (( FAILS > 0 )); then
    exit 1
fi

exit 0
