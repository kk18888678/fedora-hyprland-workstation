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
