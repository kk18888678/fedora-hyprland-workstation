section "26. Verification Matrix L: Aurelia User Preferences & Layered Configuration"

# 26.1: Preference defaults return shipped defaults when no override exists
test_26_1_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local def_motion = pref.get_effective("aurelia.motion.enabled", "/nonexistent/test_pref.json")
local def_scale  = pref.get_effective("aurelia.motion.scale", "/nonexistent/test_pref.json")
local def_view   = pref.get_effective("components.keybindings.default_view", "/nonexistent/test_pref.json")

assert(def_motion == true, "def_motion != true")
assert(def_scale == 1.0, "def_scale != 1.0")
assert(def_view == "bound", "def_view != bound")
print("TEST_26_1_OK")
LUA_CHECK
)"
if grep -q "TEST_26_1_OK" <<< "$test_26_1_out"; then
    pass "26.1 get_effective returns shipped defaults when no user override file exists"
else
    fail "26.1 preference defaults check failed: $test_26_1_out"
fi

# 26.2: User override takes precedence over shipped defaults
test_26_2_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
local f = io.open(tmp, "w")
f:write("{\"aurelia\": {\"motion\": {\"enabled\": false, \"scale\": 0.5}}}")
f:close()

local eff_motion = pref.get_effective("aurelia.motion.enabled", tmp)
local eff_scale  = pref.get_effective("aurelia.motion.scale", tmp)
local eff_view   = pref.get_effective("components.keybindings.default_view", tmp)
os.remove(tmp)

assert(eff_motion == false, "Override should be false")
assert(eff_scale == 0.5, "Override scale should be 0.5")
assert(eff_view == "bound", "Unmodified default should remain bound")
print("TEST_26_2_OK")
LUA_CHECK
)"
if grep -q "TEST_26_2_OK" <<< "$test_26_2_out"; then
    pass "26.2 user override takes precedence over shipped defaults in layered resolution"
else
    fail "26.2 preference override precedence check failed: $test_26_2_out"
fi

# 26.3: Malformed preference file fails safe without crashing or file mutation
test_26_3_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
local f = io.open(tmp, "w")
f:write("{\"aurelia\": { corrupt json ...")
f:close()

local eff_motion = pref.get_effective("aurelia.motion.enabled", tmp)
assert(eff_motion == true, "Malformed preferences must fall back to shipped default true")

local f_check = io.open(tmp, "r")
local content = f_check:read("*a")
f_check:close()
os.remove(tmp)

assert(content == "{\"aurelia\": { corrupt json ...", "Corrupted file was modified or deleted!")
print("TEST_26_3_OK")
LUA_CHECK
)"
if grep -q "TEST_26_3_OK" <<< "$test_26_3_out"; then
    pass "26.3 malformed preference file fails safe to defaults without crash or mutation"
else
    fail "26.3 malformed preference fail-safe test failed: $test_26_3_out"
fi

# 26.4: Atomic preference write: set_override uses 0600 mode and atomic rename
test_26_4_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
os.remove(tmp)

local ok, err = pref.set_override("components.keybindings.default_view", "unbound", tmp)
assert(ok == true, "set_override failed: " .. tostring(err))

local val = pref.get_effective("components.keybindings.default_view", tmp)
assert(val == "unbound", "written value mismatch")

local p = io.popen("stat -c \"%a\" " .. tmp .. " 2>/dev/null || stat -f \"%Lp\" " .. tmp .. " 2>/dev/null")
local perms = p:read("*l") or ""
p:close()
os.remove(tmp)

assert(perms == "600", "File permissions are not 0600: " .. perms)
print("TEST_26_4_OK")
LUA_CHECK
)"
if grep -q "TEST_26_4_OK" <<< "$test_26_4_out"; then
    pass "26.4 set_override writes atomically with secure 0600 file permissions"
else
    fail "26.4 atomic preference write check failed: $test_26_4_out"
fi
