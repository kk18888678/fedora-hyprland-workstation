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
    validate_bluetooth_environment
    validate_workstation_environment
    validate_session_shell_environment
    desktop_shell_selector_path
    deploy_session_shell_selection
    start_installer_logging
    stop_installer_logging
    artifact_provenance_matches
    activate_graphical_session
    install_bluetooth_packages
    wizard_select_desktop_shell
    remove_managed_dnf_package
)

defined="$(
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$ROOT"/modules/*.sh "$ROOT"/modules/lib/*.sh 2>/dev/null |
        sed 's/() {//'
)"

for fn in "${needed_functions[@]}"; do
    # Use a here-string instead of a printf|grep -q pipeline.  With
    # pipefail, grep may exit as soon as it finds a match and make printf
    # report SIGPIPE, turning a valid assertion into a flaky failure.
    if grep -Fxq "$fn" <<< "$defined"; then
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

if grep -q 'validate_component_registry' "$ROOT/modules/common.sh" &&
   grep -q 'Component registry validation failed' "$ROOT/modules/common.sh"; then
    pass "preflight validates the component registry before host mutation"
else
    fail "preflight does not validate the component registry"
fi

log_redirect_line="$(grep -n '^start_installer_logging ' "$ROOT/install.sh" | cut -d: -f1)"
setup_call_line="$(grep -n '^run_setup_mode ' "$ROOT/install.sh" | cut -d: -f1)"
if [[ -n "$log_redirect_line" && -n "$setup_call_line" && "$log_redirect_line" -lt "$setup_call_line" ]]; then
    pass "installer logging begins before setup selection and plan review"
else
    fail "installer logging starts after setup review"
fi

tty_guard_line="$(grep -n '^if ! wizard_is_interactive; then' "$ROOT/install.sh" | cut -d: -f1)"
lock_line="$(grep -n '^acquire_installer_lock$' "$ROOT/install.sh" | cut -d: -f1)"
sudo_line="$(grep -n '^require_sudo$' "$ROOT/install.sh" | cut -d: -f1)"
if [[ -n "$tty_guard_line" && -n "$lock_line" && -n "$sudo_line" &&
      "$tty_guard_line" -lt "$lock_line" && "$tty_guard_line" -lt "$sudo_line" ]]; then
    pass "production non-TTY launches fail before lock, sudo, or state setup"
else
    fail "production non-TTY guard runs too late in installer startup"
fi

prepare_body="$(sed -n '/^prepare_system() {/,/^}/p' "$ROOT/modules/common.sh")"
if [[ "$prepare_body" != *"require_command curl"* &&
      "$prepare_body" != *"require_command tar"* ]]; then
    pass "minimal Fedora Everything preflight allows base package bootstrap for curl and tar"
else
    fail "minimal Fedora Everything preflight still requires bootstrap packages too early"
fi

callback_validation_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
source "$SCRIPT_DIR/modules/common.sh"
source "$SCRIPT_DIR/modules/status.sh"
source "$SCRIPT_DIR/modules/packages.sh"
source "$SCRIPT_DIR/modules/flatpak.sh"
source "$SCRIPT_DIR/modules/containers.sh"
source "$SCRIPT_DIR/modules/browsers.sh"
source "$SCRIPT_DIR/modules/applications.sh"
source "$SCRIPT_DIR/modules/desktop.sh"
source "$SCRIPT_DIR/modules/nix.sh"
INSTALLER_PRODUCTION_MODE=1
validate_component_registry
echo callback_registry_ok=1
EOS
    )"
if grep -q 'callback_registry_ok=1' <<< "$callback_validation_output"; then
    pass "production preflight resolves every registered lifecycle callback"
else
    fail "production callback validation failed: $callback_validation_output"
fi

if grep -Fq 'TARGET_USER="$(id -un)"' "$ROOT/install.sh" &&
   grep -Fq 'TARGET_GID="$(id -g)"' "$ROOT/install.sh" &&
   grep -Fq 'TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"' "$ROOT/install.sh" &&
   grep -Fq 'TARGET_HOME" == "$passwd_home"' "$ROOT/modules/common.sh"; then
    pass "production target identity and home are derived from UID/passwd state"
else
    fail "production target identity still trusts environment-controlled USER/HOME"
fi

target_home_guard_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

TARGET_USER="$(id -un)"
TARGET_HOME="$(mktemp -d)"
guard_status=0
( validate_target_user >/dev/null 2>&1 ) || guard_status=$?
printf 'arbitrary_home_rejected=%s\n' "$([[ $guard_status -ne 0 ]] && echo 1 || echo 0)"
rm -rf -- "$TARGET_HOME"
EOS
)"

if grep -q 'arbitrary_home_rejected=1' <<< "$target_home_guard_output"; then
    pass "target-user validation rejects an arbitrary writable home path"
else
    fail "target-user validation accepted an arbitrary writable home path: $target_home_guard_output"
fi

invalid_profile_boolean_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/status.sh"
source "$ROOT/profiles/vm.conf"
CHATGPT=maybe
invalid_status=0
( validate_profile >/dev/null 2>&1 ) || invalid_status=$?
printf 'invalid_chatgpt_rejected=%s\n' "$([[ $invalid_status -ne 0 ]] && echo 1 || echo 0)"
EOS
)"

if grep -q 'invalid_chatgpt_rejected=1' <<< "$invalid_profile_boolean_output"; then
    pass "profile validation rejects malformed CHATGPT boolean values"
else
    fail "profile validation accepted a malformed CHATGPT boolean value: $invalid_profile_boolean_output"
fi

zsh_custom_path_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
TARGET_USER="$(id -un)"
TARGET_HOME="$(mktemp -d)"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/status.sh"
source "$ROOT/modules/shell.sh"
trap 'rm -rf -- "$TARGET_HOME"' EXIT

clone_pinned_git() { return 0; }
ZSH_CUSTOM="/tmp/unsafe-zsh-custom"
required_before=${#INSTALL_REQUIRED_FAILURES[@]}
install_zsh_plugin https://example.com/plugin.git plugin 1111111111111111111111111111111111111111
required_after=${#INSTALL_REQUIRED_FAILURES[@]}
printf 'unsafe_custom_rejected=%s\n' "$([[ "$required_after" -gt "$required_before" ]] && echo 1 || echo 0)"
EOS
)"

if grep -q 'unsafe_custom_rejected=1' <<< "$zsh_custom_path_output"; then
    pass "shell plugin installation rejects ZSH_CUSTOM paths outside the target home"
else
    fail "shell plugin installation followed an unsafe ZSH_CUSTOM path: $zsh_custom_path_output"
fi

xdg_config_guard_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
source "$SCRIPT_DIR/modules/common.sh"
source "$SCRIPT_DIR/modules/status.sh"

TARGET_USER="$(id -un)"
TARGET_UID="$(id -u)"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
custom_config_home="$(mktemp -d)"
symlink_parent="$(mktemp -d)"
ln -s "$custom_config_home" "$symlink_parent/config"

custom_selector="$(INSTALLER_PRODUCTION_MODE=1 XDG_CONFIG_HOME="$custom_config_home" desktop_shell_selector_path)"
symlink_selector_status=0
INSTALLER_PRODUCTION_MODE=1 XDG_CONFIG_HOME="$symlink_parent/config" \
    desktop_shell_selector_path >/dev/null 2>&1 || symlink_selector_status=$?

printf 'custom_selector_ok=%s symlink_config_rejected=%s\n' \
    "$([[ "$custom_selector" == "$custom_config_home/fedora-hyprland-workstation/session-shell" ]] && echo 1 || echo 0)" \
    "$([[ $symlink_selector_status -ne 0 ]] && echo 1 || echo 0)"
rm -rf -- "$custom_config_home" "$symlink_parent"
EOS
    )"
if grep -q 'custom_selector_ok=1' <<< "$xdg_config_guard_output" &&
   grep -q 'symlink_config_rejected=1' <<< "$xdg_config_guard_output"; then
    pass "production XDG_CONFIG_HOME is preserved only when owned and symlink-safe"
else
    fail "production XDG_CONFIG_HOME safety boundary failed: $xdg_config_guard_output"
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
