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

    if grep -vE '^\s*#' "$ROOT"/packages/*.txt | grep -qw "$name"; then
        fail "forbidden package present: $name"
    else
        pass "forbidden package absent: $name"
    fi
}

assert_in_manifest() {
    local file="$1"
    local name="$2"

    if grep -vE '^\s*#' "$ROOT/$file" | grep -qw "$name"; then
        pass "$name in $file"
    else
        fail "$name missing from $file"
    fi
}

assert_not_in_manifest mesa-vdpau-drivers
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
    run_with_retry
    record_deferred
    record_critical
    installer_exit_code
    clone_pinned_git
    validate_hyprland_desktop
    validate_greeter_configuration
    validate_graphical_activation
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

record_critical "desktop" "hyprland" "missing" 1
echo "exit-critical=$(installer_exit_code)"
echo "activation-blocked=$ACTIVATION_BLOCKED"

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

if printf '%s\n' "$helper_output" | grep -q 'exit-critical=1'; then
    pass "exit code 1 for critical"
else
    fail "critical exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'activation-blocked=1'; then
    pass "critical failure blocks activation"
else
    fail "activation blocking"
fi

if printf '%s\n' "$helper_output" | grep -q 'manifest-cursor-ok'; then
    pass "desktop manifest parsing"
else
    fail "desktop manifest parsing: $helper_output"
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
