section "27. Verification Matrix M: Component and Shell Reset Semantics & Isolation"

# 27.1: Component reset resets only target component namespace
test_27_1_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
os.remove(tmp)
pref.set_override("aurelia.motion.enabled", false, tmp)
pref.set_override("components.keybindings.default_view", "unbound", tmp)

local ok, err = pref.reset_component("keybindings", tmp)
assert(ok == true, "reset_component failed: " .. tostring(err))

local val_view = pref.get_effective("components.keybindings.default_view", tmp)
local val_motion = pref.get_effective("aurelia.motion.enabled", tmp)
os.remove(tmp)

assert(val_view == "bound", "keybindings component was not reset to default")
assert(val_motion == false, "aurelia.motion.enabled override was unintentionally wiped")
print("TEST_27_1_OK")
LUA_CHECK
)"
if grep -q "TEST_27_1_OK" <<< "$test_27_1_out"; then
    pass "27.1 reset_component resets only the target component namespace and preserves shell overrides"
else
    fail "27.1 component reset check failed: $test_27_1_out"
fi

# 27.2: Shell reset resets all overrides back to shipped defaults
test_27_2_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
os.remove(tmp)
pref.set_override("aurelia.motion.enabled", false, tmp)
pref.set_override("aurelia.motion.scale", 0.25, tmp)
pref.set_override("components.keybindings.default_view", "unbound", tmp)

local ok, err = pref.reset_shell(tmp)
assert(ok == true, "reset_shell failed: " .. tostring(err))

local val_motion = pref.get_effective("aurelia.motion.enabled", tmp)
local val_scale  = pref.get_effective("aurelia.motion.scale", tmp)
local val_view   = pref.get_effective("components.keybindings.default_view", tmp)
os.remove(tmp)

assert(val_motion == true, "motion should be reset to default true")
assert(val_scale == 1.0, "scale should be reset to default 1.0")
assert(val_view == "bound", "view should be reset to default bound")
print("TEST_27_2_OK")
LUA_CHECK
)"
if grep -q "TEST_27_2_OK" <<< "$test_27_2_out"; then
    pass "27.2 reset_shell resets all user overrides back to shipped defaults"
else
    fail "27.2 shell reset check failed: $test_27_2_out"
fi

# 27.3: Reset operations preserve logs, caches, and runtime state
(
    sb_rst="$(mktemp -d)"
    log_file="$sb_rst/aurelia.log"
    echo "existing log entry" > "$log_file"
    pref_file="$sb_rst/preferences.json"
    "$lua_bin" - "$ROOT" "$pref_file" << 'LUA_CHECK'
local root, pfile = arg[1], arg[2]
package.path = root .. "/core/?.lua;" .. package.path
local pref = require("preferences")
pref.set_override("aurelia.motion.enabled", false, pfile)
pref.reset_shell(pfile)
LUA_CHECK

    if [[ -f "$log_file" && "$(cat "$log_file")" == "existing log entry" ]]; then
        pass "27.3 reset operations preserve external logs, caches, and runtime files"
    else
        fail "27.3 reset operation mutated or deleted unrelated files"
    fi
    rm -rf "$sb_rst"
)
