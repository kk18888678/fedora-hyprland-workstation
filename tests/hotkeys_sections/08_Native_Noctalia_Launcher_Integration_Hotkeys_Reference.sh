section "Native Noctalia Launcher Integration & Hotkeys Reference"

# Validate SUPER+D maps strictly to the native Noctalia launcher
manifest_launcher_cmd="$(
    "$lua_bin" - "$ROOT/dotfiles/hypr/keybindings_manifest.lua" <<'LUA_CHECK'
local manifest = dofile(arg[1])
for _, b in ipairs(manifest.bindings or {}) do
    if b.key == "SUPER + D" then
        print(b.command or "")
        os.exit(0)
    end
end
print("NOT_FOUND")
LUA_CHECK
)"

if [[ "$manifest_launcher_cmd" == "noctalia msg panel-toggle launcher" ]]; then
    pass "keybindings_manifest.lua binds SUPER+D to native Noctalia launcher (noctalia msg panel-toggle launcher)"
else
    fail "SUPER+D does not bind to native Noctalia launcher: $manifest_launcher_cmd"
fi

manifest_hotkeys_cmd="$(
    "$lua_bin" - "$ROOT/dotfiles/hypr/keybindings_manifest.lua" <<'LUA_CHECK'
local manifest = dofile(arg[1])
for _, b in ipairs(manifest.bindings or {}) do
    if b.key == "SUPER + K" then
        print(b.command or "")
        os.exit(0)
    end
end
print("NOT_FOUND")
LUA_CHECK
)"

if [[ "$manifest_hotkeys_cmd" == "aurelia-shell-keybindings" ]]; then
    pass "keybindings_manifest.lua binds SUPER+K to the canonical aurelia-shell-keybindings command"
else
    fail "SUPER+K does not bind to aurelia-shell-keybindings: $manifest_hotkeys_cmd"
fi

# Ensure no dead standalone workstation-launcher architecture remains
if [[ ! -f "$ROOT/bin/workstation-launcher" ]]; then
    pass "no dead bin/workstation-launcher script present in repository"
else
    fail "bin/workstation-launcher should be removed"
fi

if [[ ! -f "$ROOT/config/desktop-entries/workstation-launcher.desktop" ]]; then
    pass "no dead workstation-launcher.desktop present in repository"
else
    fail "config/desktop-entries/workstation-launcher.desktop should be removed"
fi

if ! grep -q "workstation-launcher" "$ROOT/dotfiles/hypr/windowrules.lua" &&
   ! grep -q "workstation-launcher" "$ROOT/modules/desktop.sh" &&
   ! grep -q "workstation-launcher" "$ROOT/modules/validation.sh"; then
    pass "workstation-launcher references cleanly removed from window rules, modules, and validation"
else
    fail "dead workstation-launcher references remain in code"
fi
