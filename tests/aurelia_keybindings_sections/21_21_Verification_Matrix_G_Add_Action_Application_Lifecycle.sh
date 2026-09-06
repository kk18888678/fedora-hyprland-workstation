section "21. Verification Matrix G: Add Action — Application Lifecycle"

# 21.1: Lazy application discovery: resolve_bindings does not scan applications
test_21_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")
local app_reg = require("application_registry")

local scanned = false
local prev_fn = app_reg.list_applications
app_reg.list_applications = function(...)
    scanned = true
    return prev_fn(...)
end

eb.resolve_bindings()
app_reg.list_applications = prev_fn

assert(scanned == false, "resolve_bindings eagerly scanned applications!")
print("TEST_21_1_OK")
LUA_CHECK
)"
if grep -q "TEST_21_1_OK" <<< "$test_21_1_out"; then
    pass "21.1 effective binding resolution does not eagerly enumerate installed applications"
else
    fail "21.1 lazy application discovery test failed: $test_21_1_out"
fi

# 21.2: Add application action via API and verify Unbound state
test_21_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_acts = os.tmpname()
local tmp_ov = os.tmpname()

local f = io.open(tmp_acts, "w")
f:write('{"version":2,"actions":[]}\n')
f:close()
local f2 = io.open(tmp_ov, "w")
f2:write('{}\n')
f2:close()

eb.get_user_actions_path = function() return tmp_acts end
eb.get_overrides_path = function() return tmp_ov end

local ok_add, err_add = eb.add_user_application_action("org.gnome.Calculator.desktop", tmp_acts, tmp_ov, function() return true end)
assert(ok_add == true, "Failed to add application: " .. tostring(err_add))

local uacts = eb.load_user_actions(tmp_acts)
assert(#uacts.actions == 1, "Action count should be 1")
assert(uacts.actions[1].type == "application", "Type should be application")
assert(uacts.actions[1].desktop_id == "org.gnome.Calculator.desktop", "desktop_id mismatch")

local overrides = eb.load_overrides(tmp_ov)
local eff = eb.resolve_bindings(nil, overrides)
local found = nil
for _, b in ipairs(eff.bindings) do
    if b.id == "app:org.gnome.Calculator.desktop" then found = b break end
end
assert(found ~= nil, "Action not found in effective bindings")
assert(found.key == nil or found.key == false or found.key == "", "New action should be Unbound")

os.remove(tmp_acts)
os.remove(tmp_ov)
print("TEST_21_2_OK")
LUA_CHECK
)"
if grep -q "TEST_21_2_OK" <<< "$test_21_2_out"; then
    pass "21.2 added application action persists to user_actions.json and begins in Unbound state"
else
    fail "21.2 add application test failed: $test_21_2_out"
fi

# 21.3: Duplicate application prevention is idempotent
test_21_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_acts = os.tmpname()
local tmp_ov = os.tmpname()

local f = io.open(tmp_acts, "w")
f:write('{"version":2,"actions":[]}\n')
f:close()
local f2 = io.open(tmp_ov, "w")
f2:write('{}\n')
f2:close()

eb.get_user_actions_path = function() return tmp_acts end
eb.get_overrides_path = function() return tmp_ov end

eb.add_user_application_action("org.gnome.Calculator.desktop", tmp_acts, tmp_ov, function() return true end)
eb.add_user_application_action("org.gnome.Calculator.desktop", tmp_acts, tmp_ov, function() return true end)

local uacts = eb.load_user_actions(tmp_acts)
assert(#uacts.actions == 1, "Duplicate action created! Count should be 1, got " .. #uacts.actions)

os.remove(tmp_acts)
os.remove(tmp_ov)
print("TEST_21_3_OK")
LUA_CHECK
)"
if grep -q "TEST_21_3_OK" <<< "$test_21_3_out"; then
    pass "21.3 duplicate application action registration is prevented idempotently"
else
    fail "21.3 duplicate application prevention failed: $test_21_3_out"
fi

# 21.4: Assigning shortcut moves from Unbound to Bound and registers with Hyprland
test_21_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_acts = os.tmpname()
local tmp_ov = os.tmpname()

local f = io.open(tmp_acts, "w")
f:write('{"version":2,"actions":[]}\n')
f:close()
local f2 = io.open(tmp_ov, "w")
f2:write('{}\n')
f2:close()

eb.get_user_actions_path = function() return tmp_acts end
eb.get_overrides_path = function() return tmp_ov end

eb.add_user_application_action("org.gnome.Calculator.desktop", tmp_acts, tmp_ov, function() return true end)
local ok_set, err_set = eb.set_action_binding("app:org.gnome.Calculator.desktop", "SUPER + ALT + C", nil, tmp_ov, function() return true end)
assert(ok_set == true, "Failed to set shortcut: " .. tostring(err_set))

local overrides_after = eb.load_overrides(tmp_ov)
local eff_after = eb.resolve_bindings(nil, overrides_after)
local found_after = nil
for _, b in ipairs(eff_after.bindings) do
    if b.id == "app:org.gnome.Calculator.desktop" then found_after = b break end
end
assert(found_after ~= nil and found_after.key == "SUPER + ALT + C", "Action not Bound to new key")

os.remove(tmp_acts)
os.remove(tmp_ov)
print("TEST_21_4_OK")
LUA_CHECK
)"
if grep -q "TEST_21_4_OK" <<< "$test_21_4_out"; then
    pass "21.4 assigning shortcut transitions user application action from Unbound to Bound"
else
    fail "21.4 assign shortcut transition failed: $test_21_4_out"
fi

# 21.5: Removing user application action cleans up registry and overrides
test_21_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_acts = os.tmpname()
local tmp_ov = os.tmpname()

local f = io.open(tmp_acts, "w")
f:write('{"version":2,"actions":[]}\n')
f:close()
local f2 = io.open(tmp_ov, "w")
f2:write('{}\n')
f2:close()

eb.get_user_actions_path = function() return tmp_acts end
eb.get_overrides_path = function() return tmp_ov end

eb.add_user_application_action("org.gnome.Calculator.desktop", tmp_acts, tmp_ov, function() return true end)
eb.set_action_binding("app:org.gnome.Calculator.desktop", "SUPER + ALT + C", nil, tmp_ov, function() return true end)

local ok_rem, err_rem = eb.remove_user_action("app:org.gnome.Calculator.desktop", tmp_acts, tmp_ov, function() return true end)
assert(ok_rem == true, "Failed to remove action: " .. tostring(err_rem))

local uacts_after = eb.load_user_actions(tmp_acts)
assert(#uacts_after.actions == 0, "Action still present after remove")
local ov_after = eb.load_overrides(tmp_ov)
assert(ov_after["app:org.gnome.Calculator.desktop"] == nil, "Override still present after remove")

os.remove(tmp_acts)
os.remove(tmp_ov)
print("TEST_21_5_OK")
LUA_CHECK
)"
if grep -q "TEST_21_5_OK" <<< "$test_21_5_out"; then
    pass "21.5 removing user application action cleans up Action Registry and removes associated overrides"
else
    fail "21.5 remove user application failed: $test_21_5_out"
fi
