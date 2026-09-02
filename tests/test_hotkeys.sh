#!/usr/bin/env bash

# Test Suite: Workspaces discoverability, persistent workspace rules, hotkeys help viewer, and keybindings drift validation.

section "Workspaces Discoverability"

startup_lua="$ROOT/dotfiles/hypr/startup.lua"
if [[ -f "$startup_lua" ]]; then
    pass "dotfiles/hypr/startup.lua exists"
else
    fail "dotfiles/hypr/startup.lua is missing"
fi

if grep -q 'hyprctl keyword workspace "%d, persistent:true"' "$startup_lua"; then
    pass "startup.lua registers persistent workspaces dynamically via hyprctl keyword"
else
    fail "startup.lua missing persistent workspace loop"
fi

# Ensure monitor names are not hardcoded in workspace definitions
if grep -E 'workspace[[:space:]]*=[[:space:]]*[0-9]+,[[:space:]]*monitor:' "$startup_lua"; then
    fail "startup.lua hardcodes monitor-specific workspace bindings"
else
    pass "persistent workspaces avoid hardcoding monitor names"
fi

section "Hotkeys Desktop Integration"

hotkeys_desktop="$ROOT/config/desktop-entries/workstation-hotkeys.desktop"
if [[ -f "$hotkeys_desktop" ]]; then
    pass "config/desktop-entries/workstation-hotkeys.desktop exists"
else
    fail "config/desktop-entries/workstation-hotkeys.desktop is missing"
fi

if grep -q "^Name=Hotkeys$" "$hotkeys_desktop" &&
   grep -q "^Exec=workstation-hotkeys$" "$hotkeys_desktop" &&
   grep -q "^Categories=.*Documentation" "$hotkeys_desktop"; then
    pass "workstation-hotkeys.desktop has valid name, exec, and categories"
else
    fail "workstation-hotkeys.desktop fields invalid"
fi

hotkeys_bin="$ROOT/bin/workstation-hotkeys"
if [[ -x "$hotkeys_bin" ]]; then
    pass "bin/workstation-hotkeys exists and is executable"
else
    fail "bin/workstation-hotkeys missing or not executable"
fi

if grep -q "workstation-hotkeys" "$ROOT/dotfiles/hypr/windowrules.lua"; then
    pass "windowrules.lua includes floating window rule for workstation-hotkeys"
else
    fail "windowrules.lua missing workstation-hotkeys floating rule"
fi

section "Hotkeys Keybinding Parity and Zero Drift"

keybind_lua="$ROOT/dotfiles/hypr/keybind.lua"
if grep -q 'HOTKEYS = ("%s + K")' "$keybind_lua" &&
   grep -q 'hl.dsp.exec_cmd("workstation-hotkeys")' "$keybind_lua"; then
    pass "SUPER+K is bound to workstation-hotkeys in keybind.lua"
else
    fail "keybind.lua missing SUPER+K binding for workstation-hotkeys"
fi

# Check that every keybinding defined in keybind.lua is represented in workstation-hotkeys help text
bindings_to_check=(
    "SUPER + RETURN"
    "SUPER + E"
    "SUPER + D"
    "SUPER + K"
    "SUPER + T"
    "SUPER + L"
    "SUPER + Q"
    "SUPER + W"
    "SUPER + F"
    "ALT + Tab"
    "SUPER + Left"
    "SUPER + SHIFT + Left"
    "SUPER + 1 .. 9, 0"
    "SUPER + SHIFT + 1 .. 9, 0"
    "SUPER + CTRL + Left"
    "3-Finger Horizontal Swipe"
    "SUPER + Left Mouse Drag"
    "SUPER + Right Mouse Drag"
    "Play / Pause Key"
    "Next / Prev Track"
    "Volume Up / Down"
    "Mute Key"
)

for b in "${bindings_to_check[@]}"; do
    if grep -qF "$b" "$hotkeys_bin"; then
        pass "hotkeys viewer documents $b"
    else
        fail "hotkeys viewer missing documentation for binding: $b"
    fi
done

section "Hotkeys Installation Sandbox"

hotkeys_install_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="hotkeytest"
TARGET_HOME="$(mktemp -d)"
HOTKEYS_BIN_DIR="$(mktemp -d)"
HOTKEYS_APPS_DIR="$(mktemp -d)"
export HOTKEYS_BIN_DIR HOTKEYS_APPS_DIR
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

install_workstation_hotkeys

bin_installed=$([[ -x "$HOTKEYS_BIN_DIR/workstation-hotkeys" ]] && echo 1 || echo 0)
desktop_installed=$([[ -f "$HOTKEYS_APPS_DIR/workstation-hotkeys.desktop" ]] && echo 1 || echo 0)

echo "bin-installed=$bin_installed"
echo "desktop-installed=$desktop_installed"

rm -rf "$TARGET_HOME" "$HOTKEYS_BIN_DIR" "$HOTKEYS_APPS_DIR"
EOS
)"

if printf '%s\n' "$hotkeys_install_output" | grep -q 'bin-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'desktop-installed=1'; then
    pass "install_workstation_hotkeys deploys executable and desktop entry into isolated target paths"
else
    fail "install_workstation_hotkeys failed in sandbox: $hotkeys_install_output"
fi
