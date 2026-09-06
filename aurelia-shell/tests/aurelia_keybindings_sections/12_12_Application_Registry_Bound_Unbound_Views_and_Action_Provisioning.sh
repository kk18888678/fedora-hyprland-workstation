section "12. Application Registry, Bound/Unbound Views, and Action Provisioning"

# 12.1: application_registry.lua exists and safely parses desktop entries
app_reg_file="$ROOT/dotfiles/hypr/application_registry.lua"
if [[ -f "$app_reg_file" ]]; then
    pass "12.1 application_registry.lua exists"
else
    fail "12.1 application_registry.lua is missing"
fi

app_reg_test_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

local tmp = os.tmpname() .. ".desktop"
local f = io.open(tmp, "w")
f:write("[Desktop Entry]\n")
f:write("Type=Application\n")
f:write("Name=Test Tool\n")
f:write("Exec=test-tool %U --flag 'dangerous; rm -rf /' %F\n")
f:write("Icon=test-tool\n")
f:write("Categories=Utility;\n")
f:close()

local parsed = reg.parse_desktop_file(tmp, "test-tool.desktop")
os.remove(tmp)

assert(parsed ~= nil, "parse_desktop_file returned nil")
assert(parsed.name == "Test Tool", "Name mismatch: " .. tostring(parsed.name))
assert(parsed.desktop_id == "test-tool.desktop", "desktop_id mismatch")
assert(parsed.icon == "test-tool", "Icon mismatch")
assert(parsed.exec == "test-tool %U --flag 'dangerous; rm -rf /' %F", "Exec metadata altered")
assert(parsed.command == "gtk-launch -- test-tool.desktop", "Command mismatch: " .. tostring(parsed.command))
assert(type(parsed.command_argv) == "table" and parsed.command_argv[1] == "gtk-launch" and parsed.command_argv[2] == "--" and parsed.command_argv[3] == "test-tool.desktop", "command_argv mismatch")

print("APP_REG_SAFE")
LUA_CHECK
)"
if grep -q "APP_REG_SAFE" <<< "$app_reg_test_out"; then
    pass "12.2 application_registry separates discovery metadata from launch and delegates execution to gtk-launch"
else
    fail "12.2 application_registry parser check failed: $app_reg_test_out"
fi

# 12.3: workstation-keybindings apps outputs valid JSON array of graphical applications
apps_check_valid="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
local p = io.popen(root .. "/bin/workstation-keybindings apps")
local content = p:read("*a")
p:close()

assert(content:match("^%s*%["), "apps output does not start with JSON array")
assert(content:match('"desktop_id":'), "apps output missing desktop_id field")
assert(content:match('"name":'), "apps output missing name field")
print("APPS_JSON_VALID")
LUA_CHECK
)"
if grep -q "APPS_JSON_VALID" <<< "$apps_check_valid"; then
    pass "12.3 workstation-keybindings apps discovers graphical applications and emits compliant JSON"
else
    fail "12.3 workstation-keybindings apps JSON validation failed: $apps_check_valid"
fi

# 12.4: add-app desktop ID format validation and fail-closed security
(
    sb_add="$(mktemp -d)"
    export XDG_CONFIG_HOME="$sb_add/.config"
    mkdir -p "$XDG_CONFIG_HOME/hypr"

    # Leading dash must fail closed
    dash_rc=0
    "$ROOT/bin/workstation-keybindings" add-app "-rf" >/dev/null 2>&1 || dash_rc=$?
    if [[ "$dash_rc" -eq 0 ]]; then
        fail "12.4 add-app accepted leading dash"
    fi

    # Path traversal must fail closed
    trav_rc=0
    "$ROOT/bin/workstation-keybindings" add-app "../evil.desktop" >/dev/null 2>&1 || trav_rc=$?
    if [[ "$trav_rc" -eq 0 ]]; then
        fail "12.4 add-app accepted path traversal"
    fi

    # Valid desktop ID persists to user_actions.json with 0600 permissions
    "$ROOT/bin/workstation-keybindings" add-app "org.gnome.Nautilus.desktop" >/dev/null 2>&1
    user_actions_file="$XDG_CONFIG_HOME/hypr/user_actions.json"
    if [[ -f "$user_actions_file" ]]; then
        perms="$(stat -c '%a' "$user_actions_file" 2>/dev/null || stat -f '%Lp' "$user_actions_file" 2>/dev/null)"
        if [[ "$perms" == "600" && "$(cat "$user_actions_file")" == *"org.gnome.Nautilus.desktop"* ]]; then
            pass "12.4 add-app validates desktop ID syntax and persists atomically with 0600 permissions"
        else
            fail "12.4 user_actions.json has invalid permissions ($perms) or content"
        fi
    else
        fail "12.4 user_actions.json was not created"
    fi
    rm -rf "$sb_add"
)

# 12.5: User actions integration into Action Registry and Effective Bindings lifecycle
(
    sb_cycle="$(mktemp -d)"
    export XDG_CONFIG_HOME="$sb_cycle/.config"
    export XDG_DATA_HOME="$sb_cycle/.local/share"
    # Keep this isolated registry lifecycle test from touching a live Hyprland
    # instance when the suite runs inside a graphical development session.
    export HYPRLAND_INSTANCE_SIGNATURE=""
    mkdir -p "$XDG_CONFIG_HOME/hypr"
    mkdir -p "$XDG_DATA_HOME/applications"
    cat << "EOF" > "$XDG_DATA_HOME/applications/custom.app.desktop"
[Desktop Entry]
Type=Application
Name=Custom App
Exec=custom-app %u
Icon=custom-app
EOF
    export HOTKEYS_OVERRIDES="$XDG_CONFIG_HOME/hypr/keybindings_overrides.json"

    # 1. Add application action
    "$ROOT/bin/workstation-keybindings" add-app "custom.app.desktop" >/dev/null 2>&1

    # 2. Check JSON output: must be present, unbound, with display_key = None (Unbound)
    json_initial="$("$ROOT/bin/workstation-keybindings" json)"
    init_valid="$("$lua_bin" - <<LUA_CHECK
local content = [===[$json_initial]===]
local has_app = content:find('"id": "app:custom.app.desktop"')
local is_unbound = content:find('"unbound": true')
local has_none = content:find('"display_key": "None %(Unbound%)"')
if has_app and is_unbound and has_none then
    print("CYCLE_INITIAL_VALID")
end
LUA_CHECK
)"
    if [[ "$init_valid" != *"CYCLE_INITIAL_VALID"* ]]; then
        fail "12.5 user application action not exposed as unbound in initial json"
    fi

    # 3. Set shortcut on user application action -> moves to bound
    "$ROOT/bin/workstation-keybindings" set "app:custom.app.desktop" "SUPER+ALT+C" >/dev/null 2>&1
    json_bound="$("$ROOT/bin/workstation-keybindings" json)"
    bound_valid="$("$lua_bin" - <<LUA_CHECK
local content = [===[$json_bound]===]
local has_key = content:find('"display_key": "Super %+ Alt %+ C"')
local not_unbound = content:find('"unbound": false')
if has_key and not_unbound then
    print("CYCLE_BOUND_VALID")
end
LUA_CHECK
)"
    if [[ "$bound_valid" != *"CYCLE_BOUND_VALID"* ]]; then
        fail "12.5 user application action failed to bind shortcut"
    fi

    # 4. Unset shortcut -> returns to unbound without deleting action
    "$ROOT/bin/workstation-keybindings" unset "app:custom.app.desktop" >/dev/null 2>&1
    json_unbound="$("$ROOT/bin/workstation-keybindings" json)"
    if [[ "$json_unbound" == *'"id": "app:custom.app.desktop"'* && "$json_unbound" == *'"display_key": "None (Unbound)"'* ]]; then
        # 5. Remove app action -> completely eliminated
        "$ROOT/bin/workstation-keybindings" remove-app "custom.app.desktop" >/dev/null 2>&1
        json_final="$("$ROOT/bin/workstation-keybindings" json)"
        if [[ "$json_final" != *'"id": "app:custom.app.desktop"'* ]]; then
            pass "12.5 full user action lifecycle verified (add -> unbound -> bind -> unbind -> remove)"
        else
            fail "12.5 remove-app failed to delete user action"
        fi
    else
        fail "12.5 unset failed to return user action to unbound"
    fi
    rm -rf "$sb_cycle"
)

# 12.6: KeybindingsModel view partitioning, application discovery, and addApplication methods
if grep -q 'property string activeView: "bound"' "$qml_model" &&
   grep -q 'property var boundItems:' "$qml_model" &&
   grep -q 'property var unboundItems:' "$qml_model" &&
   grep -q 'readonly property int boundCount: boundItems.length' "$qml_model" &&
   grep -q 'readonly property int unboundCount: unboundItems.length' "$qml_model" &&
   grep -q 'function switchView(view)' "$qml_model" &&
   grep -q 'function toggleView()' "$qml_model" &&
   grep -q 'function loadApplications()' "$qml_model" &&
   grep -q 'function addApplication(desktopId)' "$qml_model" &&
   grep -q 'property Process appsProcess:' "$qml_model" &&
   grep -q 'property Process addAppProcess:' "$qml_model"; then
    pass "12.6 KeybindingsModel partitions items into Bound/Unbound views and provides application management"
else
    fail "12.6 KeybindingsModel missing Bound/Unbound properties or methods"
fi

# 12.7: KeybindingsWindow tabs, Tab view toggling, Alt+A, and view navigation
if grep -q 'text: "Bound (" + modelController.boundCount + ")"' "$qml_header" &&
   grep -q 'text: "Unbound (" + modelController.unboundCount + ")"' "$qml_header" &&
   grep -q 'modelController.switchView("bound")' "$qml_header" &&
   grep -q 'modelController.switchView("unbound")' "$qml_header" &&
   grep -q 'cycleTopLevelView' "$qml_window" &&
   grep -q 'openAddAction' "$qml_header" &&
   grep -q 'rowRoot.formattedShortcut()' "$qml_row"; then
    pass "12.7 KeybindingsWindow provides Bound/Unbound tabs, Tab view switching, and Alt+A application picker"
else
    fail "12.7 KeybindingsWindow missing Bound/Unbound tabs or keyboard view switching"
fi
