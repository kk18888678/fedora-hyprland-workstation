section "Hyprland Registration & Window Integration"

keybind_lua="$ROOT/dotfiles/hypr/keybind.lua"
if grep -q 'require("keybindings_manifest")' "$keybind_lua" &&
   grep -q 'hl.bind' "$keybind_lua"; then
    pass "keybind.lua registers bindings dynamically from keybindings_manifest.lua"
else
    fail "keybind.lua does not load or register keybindings_manifest.lua"
fi

if grep -q "workstation-hotkeys" "$ROOT/dotfiles/hypr/windowrules.lua"; then
    pass "windowrules.lua includes floating window rule for workstation-hotkeys"
else
    fail "windowrules.lua missing workstation-hotkeys floating rule"
fi

hotkeys_desktop="$ROOT/config/desktop-entries/workstation-hotkeys.desktop"
if [[ -f "$hotkeys_desktop" ]]; then
    pass "config/desktop-entries/workstation-hotkeys.desktop exists"
else
    fail "config/desktop-entries/workstation-hotkeys.desktop is missing"
fi

if (grep -q "^Name=Keybindings$" "$hotkeys_desktop" || grep -q "^Name=Hotkeys$" "$hotkeys_desktop") &&
   grep -q "^Exec=workstation-hotkeys$" "$hotkeys_desktop"; then
    pass "workstation-hotkeys.desktop has valid Name and Exec properties"
else
    fail "workstation-hotkeys.desktop properties invalid"
fi
