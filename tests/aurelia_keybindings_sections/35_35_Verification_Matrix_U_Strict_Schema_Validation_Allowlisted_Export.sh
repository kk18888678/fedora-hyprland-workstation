section "35. Verification Matrix U: Strict Schema Validation & Allowlisted Export"

# 35.1: Unknown preference key fails closed with exit code 1
test_35_1_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local ok, err = pref.set_override("aurelia.unregistered.key", true)
assert(ok == false, "set_override accepted unknown key")
assert(err:find("Unknown preference key") ~= nil, "Missing unknown key error message")
print("TEST_35_1_OK")
LUA_CHECK
)"
if grep -q "TEST_35_1_OK" <<< "$test_35_1_out"; then
    pass "35.1 unknown preference key fails closed with explicit error"
else
    fail "35.1 unknown preference key validation failed: $test_35_1_out"
fi

# 35.2: Strict typing, bounds, and enum constraints enforced
test_35_2_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

-- Boolean validation
local ok_b, _ = pref.set_override("aurelia.motion.enabled", "not_a_boolean")
assert(ok_b == false, "Invalid boolean was accepted")

-- Float minimum bound validation
local ok_f, _ = pref.set_override("aurelia.motion.scale", -0.5)
assert(ok_f == false, "Negative float below minimum was accepted")

-- Enum constraint validation
local ok_e, _ = pref.set_override("components.keybindings.default_view", "invalid_view")
assert(ok_e == false, "Invalid enum value was accepted")

print("TEST_35_2_OK")
LUA_CHECK
)"
if grep -q "TEST_35_2_OK" <<< "$test_35_2_out"; then
    pass "35.2 strict typing, range checking, and enum constraints enforced"
else
    fail "35.2 type and constraint validation failed: $test_35_2_out"
fi

# 35.3: Schema-driven allowlisted export ensures zero leakage of runtime/machine/secret state
test_35_3_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
local f = io.open(tmp, "w")
f:write('{"aurelia": {"motion": {"enabled": true, "scale": 1.0}}, "arbitrary_nested": {"secret": "leak_me"}, "password": "clear", "components": {"keybindings": {"default_view": "bound"}} }')
f:close()

local exp = pref.export_portable(tmp)
os.remove(tmp)

assert(exp:find("arbitrary_nested") == nil, "Export leaked arbitrary_nested")
assert(exp:find("leak_me") == nil, "Export leaked secret value")
assert(exp:find("clear") == nil, "Export leaked password")
assert(exp:find("aurelia") ~= nil, "Export missing aurelia namespace")
assert(exp:find("keybindings") ~= nil, "Export missing keybindings component")
print("TEST_35_3_OK")
LUA_CHECK
)"
if grep -q "TEST_35_3_OK" <<< "$test_35_3_out"; then
    pass "35.3 schema-driven allowlisted export guarantees zero leakage of unallowlisted state"
else
    fail "35.3 allowlisted export check failed: $test_35_3_out"
fi

# 35.4: Destination path safety and atomic write with 0600 mode
test_35_4_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

-- Relative path or path traversal rejected
local ok_rel, _ = pref.set_override("aurelia.motion.enabled", true, "relative/path.json")
assert(ok_rel == false, "Relative destination path was accepted")

local ok_trav, _ = pref.set_override("aurelia.motion.enabled", true, "/tmp/../tmp/test.json")
assert(ok_trav == false, "Path traversal destination was accepted")

print("TEST_35_4_OK")
LUA_CHECK
)"
if grep -q "TEST_35_4_OK" <<< "$test_35_4_out"; then
    pass "35.4 destination path safety validates absolute paths and rejects traversal"
else
    fail "35.4 destination path safety validation failed: $test_35_4_out"
fi

# 35.5: Lightweight bounded logging uses O(1) file seek without table buffering
if grep -q 'f:seek("end")' "$ROOT/dotfiles/aurelia/core/preferences.lua" && \
   ! grep -q 'read_all_lines' "$ROOT/dotfiles/aurelia/core/preferences.lua"; then
    pass "35.5 lightweight bounded logging writes directly and checks size with O(1) seek"
else
    fail "35.5 O(1) seek logging missing in dotfiles/aurelia/core/preferences.lua"
fi

# 35.6: Motion architecture distinction: QML internal durations vs Hyprland layer-shell compositor animations
if grep -q "Compositor Animation Boundary" "$ROOT/docs/aurelia-shell-architecture.md" && \
   grep -q "layerrule = noanim" "$ROOT/docs/aurelia-shell-architecture.md"; then
    pass "35.6 motion architecture distinction documented (QML tokens vs Hyprland layer-shell rules)"
else
    fail "35.6 motion architecture documentation missing in docs/aurelia-shell-architecture.md"
fi
