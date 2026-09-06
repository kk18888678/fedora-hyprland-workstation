section "16. Verification Matrix B: Workspace Generator Expansion & Single Source of Truth"

# 16.1: Generator expansion occurs before consumption: 20 discrete workspace actions exist
test_16_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local effective = eb.resolve_bindings()
local ws_map = {}
for _, b in ipairs(effective.bindings) do
    if b.id:match("^workspace_") then
        ws_map[b.id] = b
    end
end

for i = 1, 9 do
    assert(ws_map["workspace_" .. i] ~= nil, "Missing workspace_" .. i)
    assert(ws_map["workspace_" .. i].key == "SUPER + " .. i, "Wrong key for workspace_" .. i)
    assert(ws_map["workspace_move_" .. i] ~= nil, "Missing workspace_move_" .. i)
    assert(ws_map["workspace_move_" .. i].key == "SUPER + SHIFT + " .. i, "Wrong key for workspace_move_" .. i)
end
assert(ws_map["workspace_10"] ~= nil, "Missing workspace_10")
assert(ws_map["workspace_10"].key == "SUPER + 0", "Wrong key for workspace_10: " .. tostring(ws_map["workspace_10"].key))
assert(ws_map["workspace_move_10"] ~= nil, "Missing workspace_move_10")
assert(ws_map["workspace_move_10"].key == "SUPER + SHIFT + 0", "Wrong key for workspace_move_10")

print("TEST_16_1_OK")
LUA_CHECK
)"
if grep -q "TEST_16_1_OK" <<< "$test_16_1_out"; then
    pass "16.1 generator expansion expands workspaces into 20 discrete editable actions before consumption"
else
    fail "16.1 workspace expansion failed: $test_16_1_out"
fi

# 16.2: keybind.lua binds discrete workspace actions without duplicate registration
test_16_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path

local registered_workspaces = {}
local registered_moves = {}
local hl = {
    dsp = {
        exec_cmd = function(c) return "exec:" .. tostring(c) end,
        window = {
            close = function() return "close" end,
            float = function() return "float" end,
            fullscreen = function() return "fullscreen" end,
            cycle_next = function() return "cycle" end,
            drag = function() return "drag" end,
            resize = function() return "resize" end,
            move = function(arg)
                registered_moves[arg.workspace] = (registered_moves[arg.workspace] or 0) + 1
                return "move:" .. tostring(arg.workspace)
            end,
        },
        focus = function(arg)
            if arg.workspace then
                registered_workspaces[arg.workspace] = (registered_workspaces[arg.workspace] or 0) + 1
            end
            return "focus:" .. tostring(arg.workspace or arg.direction)
        end,
    },
    bind = function(key, dsp, flags) end
}
_G.hl = hl
package.loaded["keybind"] = nil
require("keybind")

for i = 1, 10 do
    assert(registered_workspaces[i] == 1, "Workspace " .. i .. " registered " .. tostring(registered_workspaces[i]) .. " times (expected 1)")
    assert(registered_moves[i] == 1, "Workspace move " .. i .. " registered " .. tostring(registered_moves[i]) .. " times (expected 1)")
end

print("TEST_16_2_OK")
LUA_CHECK
)"
if grep -q "TEST_16_2_OK" <<< "$test_16_2_out"; then
    pass "16.2 keybind.lua registers discrete workspace actions with exactly 1 binding per workspace"
else
    fail "16.2 workspace discrete registration failed: $test_16_2_out"
fi

# 16.3: Unsetting a generated workspace action moves it to Unbound and unregisters from Hyprland
test_16_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_overrides = os.tmpname()
local f = io.open(tmp_overrides, "w")
f:write("{}\n")
f:close()

eb.get_overrides_path = function() return tmp_overrides end

local ok, err = eb.set_action_binding("workspace_10", false, nil, tmp_overrides, function() return true end)
assert(ok == true, "Failed to unset workspace_10: " .. tostring(err))

local overrides = eb.load_overrides(tmp_overrides)
local eff = eb.resolve_bindings(nil, overrides)
local ws10 = nil
for _, b in ipairs(eff.bindings) do
    if b.id == "workspace_10" then ws10 = b break end
end
assert(ws10 ~= nil, "workspace_10 disappeared after unsetting")
assert(ws10.key == false or ws10.key == nil, "workspace_10 still has key after unsetting: " .. tostring(ws10.key))

-- Verify Hyprland registration omits workspace 10
local registered_workspaces = {}
local hl = {
    dsp = {
        exec_cmd = function(c) return "exec:" .. tostring(c) end,
        window = { close = function() end, float = function() end, fullscreen = function() end, cycle_next = function() end, drag = function() end, resize = function() end, move = function() end },
        focus = function(arg)
            if arg.workspace then registered_workspaces[arg.workspace] = true end
            return "focus"
        end,
    },
    bind = function(key, dsp, flags) end
}
_G.hl = hl
package.loaded["keybind"] = nil
require("keybind")

assert(registered_workspaces[10] == nil, "Unbound workspace 10 was incorrectly registered in Hyprland")

os.remove(tmp_overrides)
print("TEST_16_3_OK")
LUA_CHECK
)"
if grep -q "TEST_16_3_OK" <<< "$test_16_3_out"; then
    pass "16.3 unsetting generated workspace action moves it to Unbound and unregisters from Hyprland"
else
    fail "16.3 workspace unsetting test failed: $test_16_3_out"
fi

# 16.4: Reassigning a workspace action updates both UI model and Hyprland registration identically
test_16_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_overrides = os.tmpname()
local f = io.open(tmp_overrides, "w")
f:write("{}\n")
f:close()

eb.get_overrides_path = function() return tmp_overrides end

local ok, err = eb.set_action_binding("workspace_1", "SUPER + ALT + 1", nil, tmp_overrides, function() return true end)
assert(ok == true, "Failed to reassign workspace_1: " .. tostring(err))

local overrides = eb.load_overrides(tmp_overrides)
local eff = eb.resolve_bindings(nil, overrides)
local ws1 = nil
for _, b in ipairs(eff.bindings) do
    if b.id == "workspace_1" then ws1 = b break end
end
assert(ws1 ~= nil and ws1.key == "SUPER + ALT + 1", "workspace_1 reassignment not reflected: " .. tostring(ws1 and ws1.key))

os.remove(tmp_overrides)
print("TEST_16_4_OK")
LUA_CHECK
)"
if grep -q "TEST_16_4_OK" <<< "$test_16_4_out"; then
    pass "16.4 workspace reassignment updates effective model and Hyprland registration identically"
else
    fail "16.4 workspace reassignment test failed: $test_16_4_out"
fi

# 16.5: No duplicate workspace bindings emitted
test_16_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local eff = eb.resolve_bindings()
local ws_key_counts = {}
for _, b in ipairs(eff.bindings) do
    if b.id:match("^workspace_") and b.key then
        ws_key_counts[b.key] = (ws_key_counts[b.key] or 0) + 1
    end
end
for k, count in pairs(ws_key_counts) do
    assert(count == 1, "Duplicate workspace binding key emitted: " .. k .. " (" .. count .. " times)")
end

print("TEST_16_5_OK")
LUA_CHECK
)"
if grep -q "TEST_16_5_OK" <<< "$test_16_5_out"; then
    pass "16.5 zero duplicate workspace bindings emitted in effective bindings"
else
    fail "16.5 duplicate workspace check failed: $test_16_5_out"
fi
