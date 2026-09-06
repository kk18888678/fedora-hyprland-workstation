section "19. Verification Matrix E: Authoritative Conflict Detection & Force Reassignment"

# 19.1: Conflict detection against core action
test_19_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local conflict1 = eb.find_conflict("browser", "SUPER + RETURN")
assert(conflict1 ~= nil and conflict1.id == "terminal", "Expected conflict with terminal")

local conflict2 = eb.find_conflict("browser", "RETURN + SUPER")
assert(conflict2 ~= nil and conflict2.id == "terminal", "Normalized conflict check failed")

print("TEST_19_1_OK")
LUA_CHECK
)"
if grep -q "TEST_19_1_OK" <<< "$test_19_1_out"; then
    pass "19.1 conflict detection against core action correctly identifies existing action"
else
    fail "19.1 core conflict detection failed: $test_19_1_out"
fi

# 19.2: Conflict detection against workspace action
test_19_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local conflict = eb.find_conflict("browser", "SUPER + 1")
assert(conflict ~= nil and conflict.id == "workspace_1", "Expected conflict with workspace_1")

print("TEST_19_2_OK")
LUA_CHECK
)"
if grep -q "TEST_19_2_OK" <<< "$test_19_2_out"; then
    pass "19.2 conflict detection against workspace actions correctly identifies workspace"
else
    fail "19.2 workspace conflict detection failed: $test_19_2_out"
fi

# 19.3: Self-reassignment idempotency
test_19_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local self_conflict = eb.find_conflict("terminal", "SUPER + RETURN")
assert(self_conflict == nil, "Self-reassignment incorrectly flagged as conflict")

local tmp_overrides = os.tmpname()
local f = io.open(tmp_overrides, "w")
f:write("{}\n")
f:close()

local ok_self, msg_self = eb.set_action_binding("terminal", "SUPER + RETURN", nil, tmp_overrides, function() return true end)
assert(ok_self == true, "Self-reassignment failed: " .. tostring(msg_self))

os.remove(tmp_overrides)
print("TEST_19_3_OK")
LUA_CHECK
)"
if grep -q "TEST_19_3_OK" <<< "$test_19_3_out"; then
    pass "19.3 self-reassignment to existing shortcut succeeds idempotently without conflict"
else
    fail "19.3 self-reassignment failed: $test_19_3_out"
fi

# 19.4: Zero persistence mutation on conflict
test_19_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_overrides = os.tmpname()
local f = io.open(tmp_overrides, "w")
f:write("{}\n")
f:close()

local orig_content = io.open(tmp_overrides):read("*a")
local reload_called = false
local ok_conf, err_conf = eb.set_action_binding("file_manager", "SUPER + RETURN", nil, tmp_overrides, function() reload_called = true; return true end, false)
assert(ok_conf == false, "Conflict should fail when force=false")
assert(reload_called == false, "Reload was called on conflict")
local after_content = io.open(tmp_overrides):read("*a")
assert(orig_content == after_content, "Overrides file was mutated despite conflict")

os.remove(tmp_overrides)
print("TEST_19_4_OK")
LUA_CHECK
)"
if grep -q "TEST_19_4_OK" <<< "$test_19_4_out"; then
    pass "19.4 conflict performs zero persistence mutation and does not invoke reload"
else
    fail "19.4 zero mutation on conflict failed: $test_19_4_out"
fi

# 19.5: Atomic reassignment with force = true
test_19_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local tmp_overrides = os.tmpname()
local f = io.open(tmp_overrides, "w")
f:write("{}\n")
f:close()

local reload_called = false
local ok_force, msg_force = eb.set_action_binding("browser", "SUPER + E", nil, tmp_overrides, function() reload_called = true; return true end, true)
assert(ok_force == true, "Force reassignment failed: " .. tostring(msg_force))
assert(reload_called == true, "Reload not called on successful force reassignment")

local ov_data = eb.load_overrides(tmp_overrides)
assert(ov_data["browser"] == "SUPER + E", "browser not bound in overrides")
assert(ov_data["file_manager"] == false, "conflicting file_manager action not unbound in overrides")

os.remove(tmp_overrides)
print("TEST_19_5_OK")
LUA_CHECK
)"
if grep -q "TEST_19_5_OK" <<< "$test_19_5_out"; then
    pass "19.5 atomic reassignment with --force unbinds conflicting action and binds new action in single write"
else
    fail "19.5 force reassignment failed: $test_19_5_out"
fi

# 19.6: Refusal to reassign immutable actions even with force = true
test_19_6_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")
local manifest = require("keybindings_manifest")

local tmp_overrides = os.tmpname()
local f = io.open(tmp_overrides, "w")
f:write("{}\n")
f:close()

local imm_id = nil
local imm_key = nil
for _, b in ipairs(manifest.bindings) do
    if b.editable == false and b.key then
        imm_id = b.id
        imm_key = b.key
        break
    end
end
if imm_id then
    local ok_imm, err_imm = eb.set_action_binding("browser", imm_key, nil, tmp_overrides, function() return true end, true)
    assert(ok_imm == false, "Force reassignment should fail on immutable conflict")
    assert(err_imm:match("immutable") or err_imm:match("cannot be reassigned"), "Unexpected error on immutable: " .. tostring(err_imm))
end

os.remove(tmp_overrides)
print("TEST_19_6_OK")
LUA_CHECK
)"
if grep -q "TEST_19_6_OK" <<< "$test_19_6_out"; then
    pass "19.6 immutable actions cannot be reassigned even with --force (fails closed)"
else
    fail "19.6 immutable refusal failed: $test_19_6_out"
fi
