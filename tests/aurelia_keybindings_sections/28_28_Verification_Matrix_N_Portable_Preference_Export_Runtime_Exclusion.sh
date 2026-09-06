section "28. Verification Matrix N: Portable Preference Export & Runtime Exclusion"

# 28.1: export_portable strictly excludes machine/runtime keys and secrets
test_28_1_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
local f = io.open(tmp, "w")
f:write('{"aurelia": {"motion": {"enabled": false}}, "runtime": {"pid": 9999, "socket": "/tmp/aurelia.sock"}, "secrets": {"token": "secret-12345"}, "machine_id": "fedora-vm-host", "components": {"keybindings": {"default_view": "unbound"}} }')
f:close()

-- Strict schema validation: arbitrary unknown keys fail closed
local ok_bad, err_bad = pref.set_override("runtime", { pid = 9999 }, tmp)
assert(ok_bad == false, "set_override on unallowlisted key 'runtime' should fail closed")

local exp = pref.export_portable(tmp)
os.remove(tmp)

assert(exp:find("motion") ~= nil, "portable export missing motion")
assert(exp:find("keybindings") ~= nil, "portable export missing keybindings")
assert(exp:find("9999") == nil, "portable export leaked runtime pid")
assert(exp:find("secret%-12345") == nil, "portable export leaked secret token")
assert(exp:find("fedora%-vm%-host") == nil, "portable export leaked machine_id")
print("TEST_28_1_OK")
LUA_CHECK
)"
if grep -q "TEST_28_1_OK" <<< "$test_28_1_out"; then
    pass "28.1 export_portable exports user preferences while strictly excluding runtime state and secrets"
else
    fail "28.1 portable export check failed: $test_28_1_out"
fi
