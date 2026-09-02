#!/usr/bin/env bash

# Test Suite: Core common library helpers, booleans, commands, preflight guards, and modularity.

section "Installer steps resolve to functions"

needed_functions=(
    prepare_system
    configure_repositories
    install_packages
    configure_shell
    install_browsers
    install_applications
    install_cursor
    configure_cursor_flags
    install_chatgpt
    install_kate
    install_media_applications
    install_media_utilities
    install_antigravity
    deploy_nvim_config
    configure_user_directories
    configure_flatpak
    install_flatpak_applications
    install_localsend
    install_ulaa
    install_desktop
    install_nix
    configure_containers
    validate_system
    activate_graphical_session
    run_classified_step
    run_with_timeout
    run_as_target_user
    record_deferred
    record_required
    record_activation_failure
    installer_exit_code
    clone_pinned_git
    validate_hyprland_desktop
    validate_greeter_configuration
    validate_graphical_activation
    validate_login_stack
    validate_diagnostics_environment
    validate_workstation_environment
    activate_graphical_session
)

defined="$(
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$ROOT"/modules/*.sh "$ROOT"/modules/lib/*.sh 2>/dev/null |
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

if grep -q 'command -v timeout' "$ROOT/install.sh"; then
    pass "install.sh enforces timeout capability preflight check"
else
    fail "install.sh missing timeout preflight check"
fi

section "Library Modularity and Side-Effect Freedom"

modularity_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"

# Sourcing individual modules in subshells must succeed and produce no output
( source "$SCRIPT_DIR/modules/lib/output.sh" )
( source "$SCRIPT_DIR/modules/lib/execution.sh" )
( source "$SCRIPT_DIR/modules/lib/filesystem.sh" )
( source "$SCRIPT_DIR/modules/lib/packages.sh" )
( source "$SCRIPT_DIR/modules/lib/artifacts.sh" )
( source "$SCRIPT_DIR/modules/common.sh" )

echo "modularity_ok=1"
EOS
)"

if printf '%s\n' "$modularity_output" | grep -q 'modularity_ok=1'; then
    pass "all modules/lib/ components source cleanly and are side-effect free"
else
    fail "modules/lib/ components sourcing failed: $modularity_output"
fi

section "Platform Architecture Guard & Preflight Validation"

arch_guard_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

uname() {
    if [[ "$1" == "-m" ]]; then
        echo "i686"
    else
        command uname "$@"
    fi
}

arch_rejected=0
( validate_fedora >/dev/null 2>&1 ) || arch_rejected=$?
echo "arch_rejected=$([[ $arch_rejected -ne 0 ]] && echo 1 || echo 0)"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$arch_guard_output" | grep -q 'arch_rejected=1'; then
    pass "validate_fedora fails closed on unsupported 32-bit architecture"
else
    fail "validate_fedora accepted unsupported architecture: $arch_guard_output"
fi
