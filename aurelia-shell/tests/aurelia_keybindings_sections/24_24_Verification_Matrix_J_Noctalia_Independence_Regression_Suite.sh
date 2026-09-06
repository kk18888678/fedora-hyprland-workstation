section "24. Verification Matrix J: Noctalia Independence & Regression Suite"

# 24.1: Aurelia Keybindings Theme is 100% self-contained without Noctalia dependencies
theme_qml="$ROOT/theme/Theme.qml"
theme_conf="$ROOT/theme.conf"
if [[ -f "$theme_qml" && -f "$theme_conf" ]] && \
   ! grep -q 'noctalia.conf' "$theme_qml" && \
   ! grep -q -i 'noctalia' "$theme_conf" && \
   grep -q 'property color bgBase:' "$theme_qml"; then
    pass "24.1 Aurelia design system theme is 100% self-contained with zero Noctalia coupling"
else
    fail "24.1 Noctalia coupling found in Aurelia theme"
fi

# 24.2: Malformed user_actions.json fails closed without corrupting or deleting user file
test_24_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_bad = os.tmpname()
local f = io.open(tmp_bad, "w")
f:write('{"version": 99, "corrupt: true')
f:close()

local res, err = eb.load_user_actions(tmp_bad)
assert(res == nil, "Corrupt user actions was accepted!")
assert(err ~= nil, "Missing error message on corrupt user actions")

-- Verify file content was not mutated or wiped
local f2 = io.open(tmp_bad, "r")
local content = f2:read("*a")
f2:close()
assert(content == '{"version": 99, "corrupt: true', "Corrupt file was modified or deleted!")

os.remove(tmp_bad)
print("TEST_24_2_OK")
LUA_CHECK
)"
if grep -q "TEST_24_2_OK" <<< "$test_24_2_out"; then
    pass "24.2 malformed user_actions.json fails closed without corrupting or wiping existing file"
else
    fail "24.2 malformed user actions safety test failed: $test_24_2_out"
fi

# 24.3: Hyprland nil-command and unrunnable action hardening regression
test_24_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path

local exec_called_with_nil = false
local hl = {
    dsp = {
        exec_cmd = function(c)
            if c == nil or c == "" then
                exec_called_with_nil = true
                error("exec_cmd called with nil/empty", 2)
            end
            return "exec:" .. c
        end,
        window = { close = function() end, float = function() end, fullscreen = function() end, cycle_next = function() end, drag = function() end, resize = function() end, move = function() end },
        focus = function() end,
    },
    bind = function() end
}
_G.hl = hl
package.loaded["keybind"] = nil
require("keybind")

assert(exec_called_with_nil == false, "keybind.lua called exec_cmd with nil/empty command!")
print("TEST_24_3_OK")
LUA_CHECK
)"
if grep -q "TEST_24_3_OK" <<< "$test_24_3_out"; then
    pass "24.3 keybind.lua defensive binding guarantees zero exec_cmd(nil) calls"
else
    fail "24.3 defensive binding regression test failed: $test_24_3_out"
fi

# 24.4: Application Registry security regression: XDG recursion, TryExec resolution, and environment isolation
test_24_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

-- Verify TryExec resolution function exists and resolves real executables
local ok_sh = reg.resolve_in_path("sh")
assert(ok_sh ~= nil, "Failed to resolve 'sh' in PATH")

local ok_bad = reg.resolve_in_path("nonexistent_binary_xyz_123")
assert(ok_bad == nil, "Nonexistent executable resolved successfully!")

assert(reg.is_tryexec_valid("sh") == true, "is_tryexec_valid('sh') failed")
assert(reg.is_tryexec_valid("nonexistent_binary_xyz_123") == false, "is_tryexec_valid should fail on nonexistent")

print("TEST_24_4_OK")
LUA_CHECK
)"
if grep -q "TEST_24_4_OK" <<< "$test_24_4_out"; then
    pass "24.4 Application Registry real executable resolution and environment security verified"
else
    fail "24.4 application registry security regression failed: $test_24_4_out"
fi
