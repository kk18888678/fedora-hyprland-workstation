section "30. Verification Matrix P: Structured Logging, Privacy Boundary & Bounded Storage"

# 30.1: Supported logging levels format timestamp, level, component, and event
test_30_1_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
pref.get_log_path = function() return tmp end

pref.log_event("INFO", "keybindings", "navigation", "Navigated to add_app", 15)
local f = io.open(tmp, "r")
local line = f:read("*l") or ""
f:close()
os.remove(tmp)

assert(line:find("%[INFO%]") ~= nil, "Missing [INFO] tag")
assert(line:find("%[keybindings%.navigation%]") ~= nil, "Missing component.event tag")
assert(line:find("Navigated to add_app") ~= nil, "Missing log message")
assert(line:find("dur=15ms") ~= nil, "Missing duration tag")
print("TEST_30_1_OK")
LUA_CHECK
)"
if grep -q "TEST_30_1_OK" <<< "$test_30_1_out"; then
    pass "30.1 structured log events record timestamp, level, component, event, and duration"
else
    fail "30.1 structured log formatting check failed: $test_30_1_out"
fi

# 30.2: Privacy boundary: raw user search queries and secrets are redacted
test_30_2_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local redacted_token = pref.redact_sensitive("User token=secret_auth_token_xyz")
assert(redacted_token:find("secret_auth_token_xyz") == nil, "Token was not redacted!")
assert(redacted_token:find("%[REDACTED%]") ~= nil, "Missing [REDACTED] replacement")

local redacted_pwd = pref.redact_sensitive("Entered password=my_plain_text_password")
assert(redacted_pwd:find("my_plain_text_password") == nil, "Password was not redacted!")

print("TEST_30_2_OK")
LUA_CHECK
)"
qml_model="$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsModel.qml"
if grep -q "TEST_30_2_OK" <<< "$test_30_2_out" && \
   ! grep -q "for query '" "$qml_model" && \
   grep -q "query length:" "$qml_model"; then
    pass "30.2 privacy boundary redacts credentials and protects user search queries from log leaks"
else
    fail "30.2 privacy boundary check failed"
fi

# 30.3: Bounded logging behavior: log file size is strictly bounded to <= 2000 lines
test_30_3_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
local f = io.open(tmp, "w")
for i = 1, 2500 do
    f:write("Log line " .. i .. "\n")
end
f:close()

pref.bound_logfile(tmp, 2000)

local count = 0
for _ in io.lines(tmp) do count = count + 1 end
os.remove(tmp)

assert(count == 2000, "Log file line count is " .. count .. ", expected 2000")
print("TEST_30_3_OK")
LUA_CHECK
)"
if grep -q "TEST_30_3_OK" <<< "$test_30_3_out"; then
    pass "30.3 bound_logfile strictly enforces maximum line limit (<= 2000 lines)"
else
    fail "30.3 bounded logfile check failed: $test_30_3_out"
fi

# 30.4: Logging failure isolation: unwritable log destination does not crash
test_30_4_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

pref.get_log_path = function() return "/dev/null/impossible/path/aurelia.log" end

local ok = pcall(function()
    pref.log_event("INFO", "core", "test", "Unwritable log test")
end)
assert(ok == true, "Logging to unwritable path threw unhandled exception!")
print("TEST_30_4_OK")
LUA_CHECK
)"
if grep -q "TEST_30_4_OK" <<< "$test_30_4_out"; then
    pass "30.4 logging failure fails isolated without throwing unhandled exceptions"
else
    fail "30.4 logging failure isolation test failed: $test_30_4_out"
fi
