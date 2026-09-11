#!/usr/bin/env bash

# Test Suite: Desktop environment, Hyprland dotfiles, Noctalia greeter, and PAM keyring integration.

section "Greeter cursor"

if grep -q 'theme = "Adwaita"' "$ROOT/config/noctalia-greeter/greeter.toml" &&
    grep -q 'size = 24' "$ROOT/config/noctalia-greeter/greeter.toml"; then
    pass "managed greeter.toml sets Adwaita 24"
else
    fail "managed greeter.toml cursor block"
fi

greetd_backup_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_HOME="$(mktemp -d)"
source "$SCRIPT_DIR/modules/common.sh"
source "$SCRIPT_DIR/modules/status.sh"
source "$SCRIPT_DIR/modules/desktop.sh"

sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox" "$TARGET_HOME"' EXIT
destination="$sandbox/greetd/config.toml"
mkdir -p "$(dirname -- "$destination")"
printf 'administrator-custom-config\n' > "$destination"

sudo() { "$@"; }
install_root_file_atomically() {
    cp -- "$1" "$2"
}

install_root_file_from_stdin_preserving_existing "$destination" 0644 root root <<'EOF_CONFIG'
managed-config
EOF_CONFIG
backup_file="$(find "$(dirname -- "$destination")" -maxdepth 1 -name 'config.toml.bak.*' -print -quit)"
first_backup_ok=$([[ -f "$backup_file" && "$(<"$backup_file")" == 'administrator-custom-config' ]] && echo 1 || echo 0)
managed_ok=$([[ "$(<"$destination")" == 'managed-config' ]] && echo 1 || echo 0)

install_root_file_from_stdin_preserving_existing "$destination" 0644 root root <<'EOF_CONFIG'
managed-config
EOF_CONFIG
backup_count="$(find "$(dirname -- "$destination")" -maxdepth 1 -name 'config.toml.bak.*' | wc -l | tr -d ' ')"
printf 'backup_preserved=%s managed=%s idempotent_backups=%s\n' \
    "$first_backup_ok" "$managed_ok" "$([[ "$backup_count" -eq 1 ]] && echo 1 || echo 0)"
EOS
)"

if grep -q 'backup_preserved=1 managed=1 idempotent_backups=1' <<< "$greetd_backup_output"; then
    pass "managed greetd configuration preserves changed administrator content and remains idempotent"
else
    fail "managed greetd configuration backup/rollback boundary failed: $greetd_backup_output"
fi

if grep -q 'install_root_file_from_stdin_preserving_existing "\$greeter_toml"' "$ROOT/modules/desktop.sh"; then
    pass "managed Noctalia greeter state preserves changed administrator content"
else
    fail "managed Noctalia greeter state still overwrites existing configuration"
fi

desktop_services_output="$(
    bash -s -- "$ROOT" <<'EOS_SERVICES'
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/status.sh"
source "$ROOT/modules/desktop.sh"
BLUETOOTH=false
systemctl() {
    if [[ "${1:-}" == list-unit-files ]]; then
        printf '%s\n' NetworkManager.service power-profiles-daemon.service
        return 0
    fi
    return 1
}
sudo() { return 1; }
service_status=0
enable_desktop_services || service_status=$?
printf 'status=%s required=%s activation_blocked=%s success=%s\n' \
    "$service_status" "${#INSTALL_REQUIRED_FAILURES[@]}" "$ACTIVATION_BLOCKED" \
    "$(grep -c '^enable_desktop_services$' <(printf '%s\n' "${INSTALL_SUCCEEDED[@]}") || true)"
EOS_SERVICES
)"

if grep -q 'status=1 required=2 activation_blocked=0 success=0' <<< "$desktop_services_output"; then
    pass "desktop service failures propagate without falsely blocking graphical login or recording success"
else
    fail "desktop service failure propagation/classification is incorrect: $desktop_services_output"
fi

if grep -q 'extracted_dir/HackNerdFont-Regular.ttf' "$ROOT/modules/desktop.sh" &&
   grep -q 'extracted_dir/JetBrainsMonoNerdFont-Regular.ttf' "$ROOT/modules/desktop.sh" &&
   grep -q '! -L "\$fonts_dir/HackNerdFont-Regular.ttf"' "$ROOT/modules/desktop.sh" &&
   grep -q 'validate_mutation_path "\$fonts_dir"' "$ROOT/modules/desktop.sh"; then
    pass "font provisioning requires explicit regular-font members and rejects symlink markers"
else
    fail "font provisioning lacks explicit payload validation"
fi

if grep -q 'resolve_packaged_executable noctalia-greeter noctalia-greeter-session' "$ROOT/modules/desktop.sh" &&
   ! grep -q 'command -v noctalia-greeter-session' "$ROOT/modules/desktop.sh" &&
   grep -q 'resolve_packaged_executable noctalia-greeter noctalia-greeter-session' "$ROOT/modules/validation.sh"; then
    pass "greetd resolves the RPM-owned greeter executable instead of trusting PATH"
else
    fail "greetd executable provenance is not package-bound"
fi

if grep -q 'safe_user_config_home "\$themes_dir"' "$ROOT/modules/desktop.sh"; then
    pass "GTK theme provisioning rejects symlinked user theme directories"
else
    fail "GTK theme provisioning lacks a safe user theme directory boundary"
fi

greeter_matrix_test="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
SCRIPT_DIR="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/status.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/desktop.sh"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

greetd_out="$sandbox/greetd.toml"
greeter_toml_out="$sandbox/greeter.toml"

install_root_file_from_stdin() {
    cat > "$1"
}

validate_greetd_user() { return 0; }
noctalia_session_bin="/usr/bin/noctalia-greeter-session"

# 1. Bare metal path (GPU="generic", PROFILE_NAME="workstation")
GPU="generic"
PROFILE_NAME="workstation"
INSTALL_GREETER=true
command_exists() {
    if [[ "$1" == "systemd-detect-virt" ]]; then
        return 1
    fi
    return 0
}

configure_greetd_test() {
    local greeter_session="$noctalia_session_bin"
    local greetd_config="$greetd_out"
    local session_cmd="$greeter_session"
    if is_virtio_or_vm_gpu; then
        session_cmd="env WLR_NO_HARDWARE_CURSORS=1 $greeter_session"
    fi
    install_root_file_from_stdin "$greetd_config" 0644 root root <<EOF
[terminal]
vt = 1

[default_session]
command = "$session_cmd"
user = "greetd"
EOF
}

configure_greeter_state_test() {
    local greeter_toml="$greeter_toml_out"
    local managed="$SCRIPT_DIR/config/noctalia-greeter/greeter.toml"
    local content
    content="$(cat "$managed")"
    if is_virtio_or_vm_gpu; then
        if ! grep -q '^\[output\]' <<< "$content"; then
            content="${content}
[output]
scale = 1.0
"
        fi
    fi
    install_root_file_from_stdin "$greeter_toml" 0644 greetd greetd <<< "$content"
}

configure_greetd_test
configure_greeter_state_test

bare_has_wlr_env="$(grep -c 'WLR_NO_HARDWARE_CURSORS' "$greetd_out" || true)"
bare_has_scale_1="$(grep -c 'scale = 1.0' "$greeter_toml_out" || true)"

# 2. VM / virtio path (GPU="virtio")
GPU="virtio"
PROFILE_NAME="vm"
configure_greetd_test
configure_greeter_state_test

vm_has_wlr_env="$(grep -c 'WLR_NO_HARDWARE_CURSORS=1' "$greetd_out" || true)"
vm_has_scale_1="$(grep -c 'scale = 1.0' "$greeter_toml_out" || true)"

# 3. Passed-through non-virtio GPU inside VM (GPU="nvidia", PROFILE_NAME="vm")
GPU="nvidia"
PROFILE_NAME="vm"
configure_greetd_test
configure_greeter_state_test

passthrough_has_wlr_env="$(grep -c 'WLR_NO_HARDWARE_CURSORS' "$greetd_out" || true)"
passthrough_has_scale_1="$(grep -c 'scale = 1.0' "$greeter_toml_out" || true)"

echo "bare_has_wlr_env=$bare_has_wlr_env"
echo "bare_has_scale_1=$bare_has_scale_1"
echo "vm_has_wlr_env=$vm_has_wlr_env"
echo "vm_has_scale_1=$vm_has_scale_1"
echo "passthrough_has_wlr_env=$passthrough_has_wlr_env"
echo "passthrough_has_scale_1=$passthrough_has_scale_1"
EOS
)"

if printf '%s\n' "$greeter_matrix_test" | grep -q 'bare_has_wlr_env=0' &&
   printf '%s\n' "$greeter_matrix_test" | grep -q 'bare_has_scale_1=0'; then
    pass "bare-metal path preserves default hardware cursors and native auto-scaling"
else
    fail "bare-metal path incorrectly mutated: $greeter_matrix_test"
fi

if printf '%s\n' "$greeter_matrix_test" | grep -q 'vm_has_wlr_env=1' &&
   printf '%s\n' "$greeter_matrix_test" | grep -q 'vm_has_scale_1=1'; then
    pass "virtio/VM path safely configures WLR_NO_HARDWARE_CURSORS and integer scale 1.0"
else
    fail "virtio/VM path failed to configure software cursor or scale: $greeter_matrix_test"
fi

if printf '%s\n' "$greeter_matrix_test" | grep -q 'passthrough_has_wlr_env=0' &&
   printf '%s\n' "$greeter_matrix_test" | grep -q 'passthrough_has_scale_1=0'; then
    pass "passed-through physical GPU in VM preserves default hardware cursors and auto-scaling"
else
    fail "passed-through physical GPU in VM incorrectly received workaround: $greeter_matrix_test"
fi

section "GNOME Keyring PAM Auto-Unlock"

if grep -q "pam_gnome_keyring.so" "$ROOT/modules/validation.sh"; then
    pass "validation.sh validates pam_gnome_keyring.so"
else
    fail "validation.sh does not validate pam_gnome_keyring.so"
fi

section "Appearance and Qt Settings"

if grep -q "QT_QPA_PLATFORMTHEME,qt6ct" "$ROOT/dotfiles/hypr/startup.lua"; then
    pass "startup.lua exports QT_QPA_PLATFORMTHEME,qt6ct"
else
    fail "startup.lua missing QT_QPA_PLATFORMTHEME,qt6ct"
fi

if git -C "$ROOT" ls-files | grep -q "dotfiles/hypr/noctalia.lua"; then
    fail "untracked/dynamic noctalia.lua should not be tracked in git"
else
    pass "no dynamic noctalia.lua tracked in git"
fi

section "Greeter and post-login shell separation"

if [[ "$(<"$ROOT/config/session-shell/noctalia")" == "noctalia" ]] &&
    [[ "$(<"$ROOT/config/session-shell/aurelia")" == "aurelia" ]]; then
    pass "managed post-login shell selectors contain only their declared shell IDs"
else
    fail "managed post-login shell selectors are missing or malformed"
fi

session_shell_deploy_test="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
SCRIPT_DIR="$ROOT"
TARGET_USER="$(id -un)"
TARGET_HOME="$(mktemp -d)"
XDG_CONFIG_HOME="$TARGET_HOME/.config"
export XDG_CONFIG_HOME
trap 'rm -rf "$TARGET_HOME"' EXIT

# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/status.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/desktop.sh"

DESKTOP_SHELL="aurelia"
deploy_session_shell_selection
selector="$(desktop_shell_selector_path)"
echo "aurelia_link=$([[ -L "$selector" ]] && echo 1 || echo 0)"
echo "aurelia_value=$(<"$selector")"

DESKTOP_SHELL="noctalia"
deploy_session_shell_selection
echo "noctalia_link=$([[ -L "$selector" ]] && echo 1 || echo 0)"
echo "noctalia_value=$(<"$selector")"
EOS
)"

if printf '%s\n' "$session_shell_deploy_test" | grep -q 'aurelia_link=1' &&
    printf '%s\n' "$session_shell_deploy_test" | grep -q 'aurelia_value=aurelia' &&
    printf '%s\n' "$session_shell_deploy_test" | grep -q 'noctalia_link=1' &&
    printf '%s\n' "$session_shell_deploy_test" | grep -q 'noctalia_value=noctalia'; then
    pass "profile-selected shell selector deployment is atomic-by-symlink and idempotent"
else
    fail "profile-selected shell selector deployment failed: $session_shell_deploy_test"
fi

session_shell_validation_test="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
SCRIPT_DIR="$ROOT"
TARGET_USER="$(id -un)"
TARGET_HOME="$(mktemp -d)"
XDG_CONFIG_HOME="$TARGET_HOME/.config"
export XDG_CONFIG_HOME
trap 'rm -rf "$TARGET_HOME"' EXIT

# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/status.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/desktop.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/validation.sh"

DESKTOP_SHELL="aurelia"
mkdir -p "$(dirname "$(desktop_shell_selector_path)")"
ln -s "$ROOT/config/session-shell/noctalia" "$(desktop_shell_selector_path)"
validate_session_shell_environment
echo "required=${#INSTALL_REQUIRED_FAILURES[@]}"
echo "blocked=$ACTIVATION_BLOCKED"
EOS
)"

if printf '%s\n' "$session_shell_validation_test" | grep -q 'required=1' &&
    printf '%s\n' "$session_shell_validation_test" | grep -q 'blocked=0'; then
    pass "post-login shell selector mismatch is reported without blocking graphical login"
else
    fail "post-login shell selector mismatch classification is incorrect: $session_shell_validation_test"
fi

session_shell_aurelia_line="$(grep -n 'local session_shell = resolve_session_shell()' "$ROOT/dotfiles/hypr/startup.lua" | cut -d: -f1)"
session_shell_aurelia_condition="$(grep -n 'session_shell == "aurelia"' "$ROOT/dotfiles/hypr/startup.lua" | cut -d: -f1)"
session_shell_noctalia_condition="$(grep -n 'session_shell == "noctalia"' "$ROOT/dotfiles/hypr/startup.lua" | cut -d: -f1)"
session_shell_noctalia_exec="$(grep -n 'hl.exec_cmd("noctalia")' "$ROOT/dotfiles/hypr/startup.lua" | cut -d: -f1)"
if [[ -n "$session_shell_aurelia_line" &&
    -n "$session_shell_aurelia_condition" &&
    -n "$session_shell_noctalia_condition" &&
    -n "$session_shell_noctalia_exec" &&
    "$session_shell_aurelia_line" -lt "$session_shell_aurelia_condition" &&
    "$session_shell_noctalia_condition" -lt "$session_shell_noctalia_exec" ]]; then
    pass "Hyprland starts exactly the profile-selected post-login shell"
else
    fail "Hyprland startup does not conditionally select Aurelia or Noctalia"
fi

if grep -q 'pcall(require, "noctalia")' "$ROOT/dotfiles/hypr/hyprland.lua" &&
    ! grep -q 'require("noctalia").apply_theme()' "$ROOT/dotfiles/hypr/hyprland.lua"; then
    pass "Hyprland configuration does not require a generated Noctalia module for Aurelia sessions"
else
    fail "Hyprland configuration still has an unsafe unconditional Noctalia module requirement"
fi

section "Rosé Pine Moon Qt6ct Color Scheme"

qt6ct_scheme="$ROOT/dotfiles/qt6ct/colors/rose-pine-moon.conf"
if [[ -f "$qt6ct_scheme" ]]; then
    pass "dotfiles/qt6ct/colors/rose-pine-moon.conf exists"
else
    fail "dotfiles/qt6ct/colors/rose-pine-moon.conf is missing"
fi

if grep -q "active_colors" "$qt6ct_scheme" &&
   grep -q "disabled_colors" "$qt6ct_scheme" &&
   grep -q "inactive_colors" "$qt6ct_scheme" &&
   grep -q "e0def4" "$qt6ct_scheme" &&
   grep -q "232136" "$qt6ct_scheme"; then
    pass "rose-pine-moon.conf contains valid Qt6ct palette roles and Rosé Pine Moon hex values"
else
    fail "rose-pine-moon.conf malformed or missing palette roles: $(cat "$qt6ct_scheme" 2>/dev/null)"
fi

section "Terminals: Foot and Kitty Configuration"

if grep -q "^foot$" "$ROOT/packages/desktop.txt"; then
    pass "packages/desktop.txt includes foot package"
else
    fail "packages/desktop.txt missing foot package"
fi

if grep -q "^uwsm$" "$ROOT/packages/desktop.txt"; then
    pass "packages/desktop.txt includes UWSM for managed graphical application launches"
else
    fail "packages/desktop.txt missing UWSM application-launch dependency"
fi

if grep -q "^kitty$" "$ROOT/packages/desktop.txt"; then
    pass "packages/desktop.txt preserves kitty package"
else
    fail "packages/desktop.txt missing kitty package"
fi

if [[ -f "$ROOT/dotfiles/foot/foot.ini" ]]; then
    pass "dotfiles/foot/foot.ini exists"
else
    fail "dotfiles/foot/foot.ini is missing"
fi

# Semantic INI validation of foot.ini
foot_ini_valid="$(
    bash -s -- "$ROOT/dotfiles/foot/foot.ini" <<'EOS'
set -Eeuo pipefail
ini_file="$1"

current_section="<global>"
declare -A section_keys

while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" || "$line" =~ ^# ]] && continue

    if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
        current_section="${BASH_REMATCH[1]}"
        continue
    fi

    if [[ "$line" =~ ^([a-zA-Z0-9_-]+)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"

        case "$current_section" in
            "<global>")
                if [[ "$key" != "include" ]]; then
                    echo "Invalid global key: $key"
                    exit 1
                fi
                ;;
            "main")
                if [[ "$key" != "font" && "$key" != "pad" ]]; then
                    echo "Invalid key under [main]: $key"
                    exit 1
                fi
                ;;
            "scrollback")
                if [[ "$key" != "lines" && "$key" != "multiplier" && "$key" != "indicator-position" && "$key" != "indicator-format" ]]; then
                    echo "Invalid key under [scrollback]: $key"
                    exit 1
                fi
                ;;
            "cursor")
                if [[ "$key" != "style" && "$key" != "blink" && "$key" != "blink-rate" && "$key" != "beam-thickness" && "$key" != "underline-thickness" ]]; then
                    echo "Invalid key under [cursor]: $key"
                    exit 1
                fi
                ;;
            "mouse")
                if [[ "$key" != "hide-when-typing" && "$key" != "alternate-scroll-mode" ]]; then
                    echo "Invalid key under [mouse]: $key"
                    exit 1
                fi
                ;;
            "key-bindings")
                ;;
            *)
                echo "Unrecognized section: $current_section"
                exit 1
                ;;
        esac
    fi
done < "$ini_file"

echo "VALID"
EOS
)"

if [[ "$foot_ini_valid" == "VALID" ]]; then
    pass "foot.ini adheres strictly to official Foot configuration section and option schema"
else
    fail "foot.ini semantic validation failed: $foot_ini_valid"
fi

if grep -q "scrollback-lines" "$ROOT/dotfiles/foot/foot.ini"; then
    fail "foot.ini contains obsolete or unsupported scrollback-lines key"
else
    pass "foot.ini does not use unsupported scrollback-lines in [main]"
fi

if grep -q "show-urls-launch=Control+Shift+u" "$ROOT/dotfiles/foot/foot.ini"; then
    fail "foot.ini overrides show-urls-launch with Control+Shift+u which conflicts with standard unicode-input"
else
    pass "foot.ini avoids keybinding conflict between show-urls-launch and standard unicode-input"
fi

# Opportunistic foot --check-config validation if foot binary is present
if command -v foot >/dev/null 2>&1; then
    foot_chk_tmp="$(mktemp -d)"
    mkdir -p "$foot_chk_tmp/foot/themes"
    cp "$ROOT/dotfiles/foot/foot.ini" "$foot_chk_tmp/foot/foot.ini"
    cp "$ROOT/dotfiles/foot/themes/rose-pine-moon.ini" "$foot_chk_tmp/foot/themes/rose-pine-moon.ini"
    sed -i "s|include=.*|include=$foot_chk_tmp/foot/themes/rose-pine-moon.ini|" "$foot_chk_tmp/foot/foot.ini"
    foot_chk_status=0
    foot_chk_out="$(foot -C -c "$foot_chk_tmp/foot/foot.ini" 2>&1)" || foot_chk_status=$?
    rm -rf "$foot_chk_tmp"
    if (( foot_chk_status == 0 )); then
        pass "foot --check-config validates managed foot.ini with zero errors"
    else
        fail "foot --check-config failed on foot.ini: $foot_chk_out"
    fi
fi

if grep -q "Hack Nerd Font" "$ROOT/dotfiles/foot/foot.ini" &&
   grep -q "rose-pine-moon.ini" "$ROOT/dotfiles/foot/foot.ini"; then
    pass "foot.ini configures Hack Nerd Font and references Rosé Pine Moon theme"
else
    fail "foot.ini font/theme references invalid"
fi

if [[ -f "$ROOT/dotfiles/foot/themes/rose-pine-moon.ini" ]]; then
    pass "dotfiles/foot/themes/rose-pine-moon.ini exists"
else
    fail "dotfiles/foot/themes/rose-pine-moon.ini is missing"
fi

# Foot launcher visibility and desktop entry override tests
if [[ -f "$ROOT/config/desktop-entries/footclient.desktop" ]] &&
   grep -q "NoDisplay=true" "$ROOT/config/desktop-entries/footclient.desktop" &&
   [[ -f "$ROOT/config/desktop-entries/foot-server.desktop" ]] &&
   grep -q "NoDisplay=true" "$ROOT/config/desktop-entries/foot-server.desktop"; then
    pass "managed desktop overrides exist and specify NoDisplay=true for Foot Client and Server"
else
    fail "managed foot desktop entry overrides missing or lack NoDisplay=true"
fi

foot_deploy_test="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="desktest"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/filesystem.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/shell.sh"

deploy_foot_config

client_deployed="$([[ -L "$TARGET_HOME/.local/share/applications/footclient.desktop" ]] && echo 1 || echo 0)"
server_deployed="$([[ -L "$TARGET_HOME/.local/share/applications/foot-server.desktop" ]] && echo 1 || echo 0)"
normal_foot_visible="$([[ ! -f "$TARGET_HOME/.local/share/applications/foot.desktop" ]] && echo 1 || echo 0)"

echo "client_deployed=$client_deployed"
echo "server_deployed=$server_deployed"
echo "normal_foot_visible=$normal_foot_visible"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$foot_deploy_test" | grep -q 'client_deployed=1' &&
   printf '%s\n' "$foot_deploy_test" | grep -q 'server_deployed=1' &&
   printf '%s\n' "$foot_deploy_test" | grep -q 'normal_foot_visible=1'; then
    pass "deploy_foot_config deploys client/server NoDisplay overrides while keeping normal Foot visible"
else
    fail "deploy_foot_config desktop override deployment failed: $foot_deploy_test"
fi

if [[ -f "$ROOT/dotfiles/kitty/themes/rose-pine-moon.conf" ]]; then
    pass "dotfiles/kitty/themes/rose-pine-moon.conf exists"
else
    fail "dotfiles/kitty/themes/rose-pine-moon.conf is missing"
fi

if grep -q "Hack Nerd Font" "$ROOT/dotfiles/kitty/kitty.conf" &&
   grep -q "include themes/rose-pine-moon.conf" "$ROOT/dotfiles/kitty/kitty.conf"; then
    pass "kitty.conf configures Hack Nerd Font and includes static rose-pine-moon theme"
else
    fail "kitty.conf font/theme references invalid"
fi

if grep -q "themes/noctalia.conf" "$ROOT/dotfiles/kitty/kitty.conf"; then
    fail "kitty.conf must not reference nonexistent generated noctalia theme file"
else
    pass "kitty.conf does not reference transient noctalia theme"
fi

section "Desktop Fonts and Theme Provisioning"

desktop_theme_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="desktest"
TARGET_HOME="$(mktemp -d)"
FONTS_INSTALL_DIR="$(mktemp -d)"
export FONTS_INSTALL_DIR
OVERRIDE_TARGET_UID=1000

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

env() {
    while [[ $# -gt 0 && "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
}

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

# Test font idempotent skip when already present
mkdir -p "$FONTS_INSTALL_DIR"
touch "$FONTS_INSTALL_DIR/HackNerdFont-Regular.ttf"
install_hack_nerd_font
font_skip_ok=1
echo "font-skip-ok=$font_skip_ok"

# Test JetBrainsMono font idempotent skip when already present
JETBRAINS_FONTS_INSTALL_DIR="$TARGET_HOME/share/fonts/JetBrainsMonoNerdFont"
mkdir -p "$JETBRAINS_FONTS_INSTALL_DIR"
touch "$JETBRAINS_FONTS_INSTALL_DIR/JetBrainsMonoNerdFont-Regular.ttf"
install_jetbrains_mono_nerd_font
jetbrains_font_skip_ok=1
echo "jetbrains-font-skip-ok=$jetbrains_font_skip_ok"

# Test GTK theme idempotent skip when already present
mkdir -p "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/gtk-3.0"
touch "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/index.theme"
touch "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/gtk-3.0/gtk.css"
install_rose_pine_gtk_theme
gtk_skip_ok=1
echo "gtk-skip-ok=$gtk_skip_ok"

# Helper to build mock tarball and compute sha512
build_mock_tar() {
    local src_dir="$1"
    local out_tar="$2"
    tar -czf "$out_tar" -C "$src_dir" .
    sha512sum "$out_tar" | awk '{print $1}'
}

# Negative Test 1: Archive with escaping symlink
rm -rf "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk"
mock1="$(mktemp -d)"
mkdir -p "$mock1/gtk3/rose-pine-moon-gtk/gtk-3.0"
touch "$mock1/gtk3/rose-pine-moon-gtk/index.theme"
touch "$mock1/gtk3/rose-pine-moon-gtk/gtk-3.0/gtk.css"
ln -s "../../../../../etc/shadow" "$mock1/gtk3/rose-pine-moon-gtk/escape_link"
tar1="$(mktemp --suffix=.tar.gz)"
hash1="$(build_mock_tar "$mock1" "$tar1")"

download_and_verify_artifact() { cp "$tar1" "$3"; }
ROSE_PINE_GTK_URL="https://example.com/gtk3.tar.gz"
ROSE_PINE_GTK_SHA512="$hash1"
install_rose_pine_gtk_theme
escape_rejected=$([[ ! -d "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk" ]] && echo 1 || echo 0)
echo "symlink-escape-rejected=$escape_rejected"
rm -rf "$mock1" "$tar1"

# Negative Test 2: Archive with hardlink
mock2="$(mktemp -d)"
mkdir -p "$mock2/gtk3/rose-pine-moon-gtk/gtk-3.0"
touch "$mock2/gtk3/rose-pine-moon-gtk/index.theme"
touch "$mock2/gtk3/rose-pine-moon-gtk/gtk-3.0/gtk.css"
ln "$mock2/gtk3/rose-pine-moon-gtk/index.theme" "$mock2/gtk3/rose-pine-moon-gtk/hardlink_file"
tar2="$(mktemp --suffix=.tar.gz)"
hash2="$(build_mock_tar "$mock2" "$tar2")"

ROSE_PINE_GTK_SHA512="$hash2"
download_and_verify_artifact() { cp "$tar2" "$3"; }
install_rose_pine_gtk_theme
hardlink_rejected=$([[ ! -d "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk" ]] && echo 1 || echo 0)
echo "hardlink-rejected=$hardlink_rejected"
rm -rf "$mock2" "$tar2"

# Negative Test 3: Archive missing Moon theme index.theme
mock3="$(mktemp -d)"
mkdir -p "$mock3/gtk3/rose-pine-dawn-gtk/gtk-3.0"
touch "$mock3/gtk3/rose-pine-dawn-gtk/index.theme"
touch "$mock3/gtk3/rose-pine-dawn-gtk/gtk-3.0/gtk.css"
tar3="$(mktemp --suffix=.tar.gz)"
hash3="$(build_mock_tar "$mock3" "$tar3")"

ROSE_PINE_GTK_SHA512="$hash3"
download_and_verify_artifact() { cp "$tar3" "$3"; }
install_rose_pine_gtk_theme
missing_payload_rejected=$([[ ! -d "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk" ]] && echo 1 || echo 0)
echo "missing-payload-rejected=$missing_payload_rejected"
rm -rf "$mock3" "$tar3"

# Positive Test: Valid archive with safe relative symlinks and valid Moon theme
mock4="$(mktemp -d)"
mkdir -p "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.0"
mkdir -p "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.20"
mkdir -p "$mock4/gtk3/rose-pine-moon-gtk/assets"
touch "$mock4/gtk3/rose-pine-moon-gtk/index.theme"
touch "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.0/gtk.css"
touch "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.20/gtk.css"
ln -s "../assets" "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.20/assets"
tar4="$(mktemp --suffix=.tar.gz)"
hash4="$(build_mock_tar "$mock4" "$tar4")"

ROSE_PINE_GTK_SHA512="$hash4"
download_and_verify_artifact() { cp "$tar4" "$3"; }
install_rose_pine_gtk_theme
valid_installed=$([[ -f "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/index.theme" ]] && echo 1 || echo 0)
echo "valid-installed=$valid_installed"
rm -rf "$mock4" "$tar4"

rm -rf "$TARGET_HOME" "$FONTS_INSTALL_DIR"
EOS
)"

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'font-skip-ok=1'; then
    pass "install_hack_nerd_font detects existing font installation idempotently"
else
    fail "install_hack_nerd_font idempotency failed: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'jetbrains-font-skip-ok=1'; then
    pass "install_jetbrains_mono_nerd_font detects existing font installation idempotently"
else
    fail "install_jetbrains_mono_nerd_font idempotency failed: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'gtk-skip-ok=1'; then
    pass "install_rose_pine_gtk_theme detects existing theme installation idempotently"
else
    fail "install_rose_pine_gtk_theme idempotency failed: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'symlink-escape-rejected=1'; then
    pass "install_rose_pine_gtk_theme rejects archives with escaping symlinks before extraction"
else
    fail "install_rose_pine_gtk_theme did not reject escaping symlink: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'hardlink-rejected=1'; then
    pass "install_rose_pine_gtk_theme rejects archives with hardlink entries"
else
    fail "install_rose_pine_gtk_theme did not reject hardlink: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'missing-payload-rejected=1'; then
    pass "install_rose_pine_gtk_theme defers cleanly when required Moon theme payload is missing"
else
    fail "install_rose_pine_gtk_theme did not reject missing Moon payload: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'valid-installed=1'; then
    pass "install_rose_pine_gtk_theme successfully verifies and installs valid GTK theme payload"
else
    fail "install_rose_pine_gtk_theme failed on valid payload: $desktop_theme_test_output"
fi

section "GTK Places Bookmarks Convergence & Safety"

bookmarks_test_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
TARGET_USER="bmtest"
TARGET_HOME="$(mktemp -d)"
OVERRIDE_TARGET_UID=1000

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

env() {
    while [[ $# -gt 0 && "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
}

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

# Test 1: empty/nonexistent file -> initializes exact baseline in both gtk-3.0 and gtk-4.0
converge_gtk_bookmarks "$TARGET_HOME"
gtk3_bm="$TARGET_HOME/.config/gtk-3.0/bookmarks"
gtk4_bm="$TARGET_HOME/.config/gtk-4.0/bookmarks"

empty_init_ok=0
if [[ -f "$gtk3_bm" && -f "$gtk4_bm" ]]; then
    expected_std="$(cat << EOF
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
EOF
)"
    if cmp -s "$gtk3_bm" <(printf '%s\n' "$expected_std") &&
       cmp -s "$gtk4_bm" <(printf '%s\n' "$expected_std"); then
        empty_init_ok=1
    fi
fi
echo "empty-init-ok=$empty_init_ok"

# Test 2: only managed bookmarks out of order -> converges to canonical order
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Videos
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Music
EOF
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
only_managed_ok=$([[ "$(cat "$gtk3_bm")" == "$expected_std" ]] && echo 1 || echo 0)
echo "only-managed-ok=$only_managed_ok"

# Test 3: only personal bookmarks -> preserved in order at top, managed block appended
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Work
file://${TARGET_HOME}/Personal
EOF
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
expected_only_pers="$(cat << EOF
file://${TARGET_HOME}/Work
file://${TARGET_HOME}/Personal
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
EOF
)"
only_pers_ok=$([[ "$(cat "$gtk3_bm")" == "$expected_only_pers" ]] && echo 1 || echo 0)
echo "only-pers-ok=$only_pers_ok"

# Test 4: personal before managed -> preserved before managed block
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Alpha
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
EOF
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
expected_before="$(cat << EOF
file://${TARGET_HOME}/Alpha
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
EOF
)"
pers_before_ok=$([[ "$(cat "$gtk3_bm")" == "$expected_before" ]] && echo 1 || echo 0)
echo "pers-before-ok=$pers_before_ok"

# Test 5: personal after managed -> preserved after managed block
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
file://${TARGET_HOME}/Omega
EOF
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
expected_after="$(cat << EOF
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
file://${TARGET_HOME}/Omega
EOF
)"
pers_after_ok=$([[ "$(cat "$gtk3_bm")" == "$expected_after" ]] && echo 1 || echo 0)
echo "pers-after-ok=$pers_after_ok"

# Test 6: personal interleaved with managed -> de-duplicated and converged at first managed position
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/MyProject
file://${TARGET_HOME}/Downloads
EOF
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
expected_interleaved="$(cat << EOF
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
file://${TARGET_HOME}/MyProject
EOF
)"
interleaved_ok=$([[ "$(cat "$gtk3_bm")" == "$expected_interleaved" ]] && echo 1 || echo 0)
echo "interleaved-ok=$interleaved_ok"

# Test 7: duplicate managed entries -> duplicates removed, appears exactly once
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Pictures
EOF
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
dedup_ok=$([[ "$(cat "$gtk3_bm")" == "$expected_std" ]] && echo 1 || echo 0)
echo "dedup-ok=$dedup_ok"

# Test 8: custom labels -> labels preserved intact
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Code Custom Code Folder
file://${TARGET_HOME}/Documents
EOF
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
labels_ok=$(grep -q "file://${TARGET_HOME}/Code Custom Code Folder" "$gtk3_bm" && echo 1 || echo 0)
echo "labels-ok=$labels_ok"

# Test 9: remote/non-file personal URIs -> preserved intact
cat << EOF > "$gtk3_bm"
smb://nas.local/share Network Share
sftp://server.lan/backup Remote Backup
file://${TARGET_HOME}/Documents
EOF
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
remote_ok=0
if grep -q "smb://nas.local/share Network Share" "$gtk3_bm" &&
   grep -q "sftp://server.lan/backup Remote Backup" "$gtk3_bm"; then
    remote_ok=1
fi
echo "remote-ok=$remote_ok"

# Test 10: second-run byte/idempotency behavior -> zero change and unchanged mtime
mtime_c1="$(stat -c %Y "$gtk3_bm")"
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
mtime_c2="$(stat -c %Y "$gtk3_bm")"
idempotent_c_ok=$([[ "$mtime_c1" == "$mtime_c2" ]] && echo 1 || echo 0)
echo "idempotent-c-ok=$idempotent_c_ok"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$bookmarks_test_output" | grep -q 'empty-init-ok=1'; then
    pass "converge_gtk_bookmarks initializes baseline GTK3 and GTK4 bookmarks in exact desired order"
else
    fail "converge_gtk_bookmarks empty init failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'only-managed-ok=1'; then
    pass "converge_gtk_bookmarks reorders out-of-order managed bookmarks into canonical order"
else
    fail "converge_gtk_bookmarks only-managed reordering failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'only-pers-ok=1'; then
    pass "converge_gtk_bookmarks preserves only-personal bookmarks at top and appends managed block"
else
    fail "converge_gtk_bookmarks only-personal preservation failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'pers-before-ok=1'; then
    pass "converge_gtk_bookmarks preserves personal bookmarks situated before managed block"
else
    fail "converge_gtk_bookmarks personal-before preservation failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'pers-after-ok=1'; then
    pass "converge_gtk_bookmarks preserves personal bookmarks situated after managed block"
else
    fail "converge_gtk_bookmarks personal-after preservation failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'interleaved-ok=1'; then
    pass "converge_gtk_bookmarks preserves interleaved personal bookmarks while converging managed block"
else
    fail "converge_gtk_bookmarks interleaved preservation failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'dedup-ok=1'; then
    pass "converge_gtk_bookmarks de-duplicates multiple occurrences of standard bookmarks"
else
    fail "converge_gtk_bookmarks de-duplication failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'labels-ok=1'; then
    pass "converge_gtk_bookmarks preserves custom bookmark labels intact"
else
    fail "converge_gtk_bookmarks label preservation failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'remote-ok=1'; then
    pass "converge_gtk_bookmarks preserves non-file remote protocol URIs intact"
else
    fail "converge_gtk_bookmarks remote URI preservation failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'idempotent-c-ok=1'; then
    pass "converge_gtk_bookmarks satisfies strict byte idempotency on subsequent runs"
else
    fail "converge_gtk_bookmarks byte idempotency failed: $bookmarks_test_output"
fi


activation_failure_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

INSTALL_GREETER=true
ENABLE_GRAPHICAL_TARGET=true
ACTIVATION_BLOCKED=0
GRAPHICAL_ACTIVATION_STATE="not-attempted"
validate_hyprland_desktop() { return 0; }
validate_greeter_configuration() { return 0; }
enable_greetd() { return 77; }
configure_graphical_target() { return 0; }
validate_graphical_activation() { return 0; }
systemctl() {
    case "${1:-}" in
        is-enabled)
            printf 'disabled\n'
            return 1
            ;;
        get-default)
            printf 'multi-user.target\n'
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}
sudo() { return 0; }

activate_graphical_session >/dev/null 2>&1
printf 'activation_blocked=%s\n' "$ACTIVATION_BLOCKED"
printf 'activation_state=%s\n' "$GRAPHICAL_ACTIVATION_STATE"
printf 'success_recorded=%s\n' "$(printf '%s\n' "${INSTALL_SUCCEEDED[@]}" | grep -cx 'activate_graphical_session' || true)"
EOS
)"

if grep -q '^activation_blocked=1$' <<< "$activation_failure_output" &&
   grep -q '^activation_state=skipped$' <<< "$activation_failure_output" &&
   grep -q '^success_recorded=0$' <<< "$activation_failure_output"; then
    pass "greetd activation failure blocks success and preserves safe activation state"
else
    fail "greetd activation failure was not surfaced safely: $activation_failure_output"
fi

activation_rollback_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
source "$SCRIPT_DIR/modules/common.sh"
source "$SCRIPT_DIR/modules/status.sh"
source "$SCRIPT_DIR/modules/desktop.sh"

INSTALL_GREETER=true
ENABLE_GRAPHICAL_TARGET=true
validate_hyprland_desktop() { return 0; }
validate_greeter_configuration() { return 0; }
enable_greetd() { return 0; }
configure_graphical_target() { return 1; }
validate_graphical_activation() { return 0; }

systemctl() {
    case "${1:-}" in
        is-enabled)
            printf 'disabled\n'
            return 1
            ;;
        get-default)
            printf 'multi-user.target\n'
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

restored_greetd=0
restored_target=0
sudo() {
    [[ "$*" == *"disable greetd.service"* ]] && restored_greetd=1
    [[ "$*" == *"set-default multi-user.target"* ]] && restored_target=1
    return 0
}

activate_graphical_session >/dev/null 2>&1
printf 'blocked=%s state=%s restored_greetd=%s restored_target=%s successes=%s\n' \
    "$ACTIVATION_BLOCKED" "$GRAPHICAL_ACTIVATION_STATE" \
    "$restored_greetd" "$restored_target" \
    "$(printf '%s\n' "${INSTALL_SUCCEEDED[@]}" | grep -cx 'activate_graphical_session' || true)"
EOS
)"

if grep -q 'blocked=1 state=skipped restored_greetd=1 restored_target=1 successes=0' <<< "$activation_rollback_output"; then
    pass "graphical activation rolls back prior greetd/target state after partial activation failure"
else
    fail "graphical activation rollback failed: $activation_rollback_output"
fi

section "Monitor Configuration"

monitor_conf="$ROOT/dotfiles/hypr/monitors.lua"
if [[ -f "$monitor_conf" ]]; then
    if command -v luajit >/dev/null 2>&1; then
        if luajit -e 'assert(loadfile("'"$monitor_conf"'"))' >/dev/null 2>&1; then
            pass "monitors.lua has valid Lua syntax"
        else
            fail "monitors.lua has invalid Lua syntax"
        fi
    else
        pass "monitors.lua syntax check skipped (luajit not installed)"
    fi

    # Ensure no hardcoded machine-specific dimensions or output names
    if grep -Eq '[0-9]{3,4}x[0-9]{3,4}' "$monitor_conf"; then
        fail "monitors.lua must not hardcode fixed pixel resolutions"
    else
        pass "monitors.lua contains no hardcoded pixel resolutions"
    fi

    if grep -Fq 'Virtual-1' "$monitor_conf"; then
        fail "monitors.lua must not hardcode output name Virtual-1"
    else
        pass "monitors.lua does not hardcode Virtual-1"
    fi

    if grep -Fq 'output = ""' "$monitor_conf" && grep -Fq 'mode = "preferred"' "$monitor_conf"; then
        pass "monitors.lua contains generic fallback rule with preferred mode"
    else
        fail "monitors.lua missing generic fallback rule with preferred mode"
    fi

    if grep -Fq 'desc:Red Hat Inc. QEMU Monitor' "$monitor_conf"; then
        fail "monitors.lua contains misleading/placebo VM-specific rule"
    else
        pass "monitors.lua avoids dead or misleading VM-specific monitor rules"
    fi

    if grep -iq 'seamless resolution adaptation' "$monitor_conf"; then
        fail "monitors.lua makes unwarranted claims of dynamic post-enumeration adaptation"
    else
        pass "monitors.lua accurately documents VM dynamic resize capabilities without unwarranted claims"
    fi
else
    fail "monitors.lua file not found at $monitor_conf"
fi
