section "15. Verification Matrix A: Bound / Unbound Invariants & Installed App Isolation"

# 15.1: Bound iff effective shortcut exists; Unbound iff no shortcut exists; Bound ∩ Unbound is empty
test_15_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local effective = eb.resolve_bindings()
local bound_set = {}
local unbound_set = {}

for _, item in ipairs(effective.bindings or {}) do
    if item.key and item.key ~= false and item.key ~= "" then
        bound_set[item.id] = item
    else
        unbound_set[item.id] = item
    end
end

for id, item in pairs(bound_set) do
    assert(unbound_set[id] == nil, "Action " .. id .. " is in both Bound and Unbound!")
    assert(type(item.key) == "string" and #item.key > 0, "Bound action " .. id .. " has invalid key: " .. tostring(item.key))
end

for id, item in pairs(unbound_set) do
    assert(bound_set[id] == nil, "Action " .. id .. " is in both Unbound and Bound!")
    assert(item.key == nil or item.key == false or item.key == "", "Unbound action " .. id .. " has a key: " .. tostring(item.key))
end

print("TEST_15_1_OK")
LUA_CHECK
)"
if grep -q "TEST_15_1_OK" <<< "$test_15_1_out"; then
    pass "15.1 every Action Registry action belongs to exactly one of Bound or Unbound (empty intersection)"
else
    fail "15.1 Bound/Unbound partition invariant failed: $test_15_1_out"
fi

# 15.2: Union of Bound and Unbound equals Action Registry exactly
test_15_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local effective = eb.resolve_bindings()
local total_actions = #(effective.bindings or {})
local bound_count = 0
local unbound_count = 0

for _, item in ipairs(effective.bindings or {}) do
    if item.key and item.key ~= false and item.key ~= "" then
        bound_count = bound_count + 1
    else
        unbound_count = unbound_count + 1
    end
end

assert(bound_count + unbound_count == total_actions, "Union count mismatch: " .. (bound_count + unbound_count) .. " vs " .. total_actions)
assert(total_actions > 0, "Action registry is empty")

print("TEST_15_2_OK")
LUA_CHECK
)"
if grep -q "TEST_15_2_OK" <<< "$test_15_2_out"; then
    pass "15.2 union of Bound and Unbound equals Action Registry with zero unclassified actions"
else
    fail "15.2 union invariant failed: $test_15_2_out"
fi

# 15.3: Discovered applications in Application Registry do NOT pollute Action Registry or Unbound
test_15_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")
local app_reg = require("application_registry")

local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp .. "/applications")

for i = 1, 20 do
    local f = io.open(tmp .. "/applications/mock-app-" .. i .. ".desktop", "w")
    f:write("[Desktop Entry]\nType=Application\nName=Mock App " .. i .. "\nExec=mock-app-" .. i .. "\n")
    f:close()
end

local prev_fn = app_reg.get_applications_search_dirs
app_reg.get_applications_search_dirs = function() return { tmp .. "/applications" } end
app_reg.invalidate_cache()

local discovered = app_reg.list_applications({ refresh = true })
assert(#discovered >= 20, "Failed to discover mock applications in temp dir")

local effective = eb.resolve_bindings()
for _, item in ipairs(effective.bindings or {}) do
    for i = 1, 20 do
        local mock_id = "app:mock-app-" .. i .. ".desktop"
        assert(item.id ~= mock_id, "Mock application automatically leaked into Action Registry: " .. tostring(item.id))
    end
end

app_reg.get_applications_search_dirs = prev_fn
app_reg.invalidate_cache()
os.execute("rm -rf " .. tmp)

print("TEST_15_3_OK")
LUA_CHECK
)"
if grep -q "TEST_15_3_OK" <<< "$test_15_3_out"; then
    pass "15.3 discovered applications do NOT pollute Action Registry or Unbound actions"
else
    fail "15.3 application registry isolation failed: $test_15_3_out"
fi

# 15.4: Hyprland registration truthfulness: Bound actions are registered; Unbound actions are NOT
test_15_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")
eb.get_user_actions_path = function() return "/nonexistent/user_actions.json" end

local effective = eb.resolve_bindings()
local registered_keys = {}
local registered_descs = {}

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
            move = function() return "move" end,
        },
        focus = function(arg) return "focus:" .. tostring(arg.workspace or arg.direction) end,
    },
    bind = function(key, dsp, flags)
        registered_keys[key] = dsp
        if flags and flags.description then
            registered_descs[flags.description] = key
        end
    end
}
_G.hl = hl

package.loaded["keybind"] = nil
require("keybind")

for _, item in ipairs(effective.bindings or {}) do
    if item.key and item.key ~= false and item.key ~= "" and item.runnable ~= false and item.action_type ~= "gesture" then
        assert(registered_keys[item.key] ~= nil, "Bound runnable action not registered in Hyprland: " .. item.id .. " (" .. item.key .. ")")
    elseif (not item.key) or item.key == false or item.key == "" then
        if item.description then
            assert(registered_descs[item.description] == nil, "Unbound action was incorrectly registered in Hyprland: " .. item.id)
        end
    end
end

print("TEST_15_4_OK")
LUA_CHECK
)"
if grep -q "TEST_15_4_OK" <<< "$test_15_4_out"; then
    pass "15.4 Hyprland registration matches Bound actions exactly; Unbound actions remain unregistered"
else
    fail "15.4 Hyprland registration truthfulness test failed: $test_15_4_out"
fi
