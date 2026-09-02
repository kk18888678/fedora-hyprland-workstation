#!/usr/bin/env bash

# Test Suite: Desktop environment, Hyprland dotfiles, Noctalia greeter, and PAM keyring integration.

section "Greeter cursor"

if grep -q 'theme = "Adwaita"' "$ROOT/config/noctalia-greeter/greeter.toml" &&
    grep -q 'size = 24' "$ROOT/config/noctalia-greeter/greeter.toml"; then
    pass "managed greeter.toml sets Adwaita 24"
else
    fail "managed greeter.toml cursor block"
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

# Test GTK theme idempotent skip when already present
mkdir -p "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/gtk-3.0"
touch "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/index.theme"
touch "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/gtk-3.0/gtk.css"
install_rose_pine_gtk_theme
gtk_skip_ok=1
echo "gtk-skip-ok=$gtk_skip_ok"

rm -rf "$TARGET_HOME" "$FONTS_INSTALL_DIR"
EOS
)"

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'font-skip-ok=1'; then
    pass "install_hack_nerd_font detects existing font installation idempotently"
else
    fail "install_hack_nerd_font idempotency failed: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'gtk-skip-ok=1'; then
    pass "install_rose_pine_gtk_theme detects existing theme installation idempotently"
else
    fail "install_rose_pine_gtk_theme idempotency failed: $desktop_theme_test_output"
fi
