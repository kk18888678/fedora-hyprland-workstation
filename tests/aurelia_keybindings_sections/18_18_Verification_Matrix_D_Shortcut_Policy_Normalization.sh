section "18. Verification Matrix D: Shortcut Policy & Normalization"

# 18.1: Naked printable characters rejected
test_18_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local naked = { "S", "U", "A", "b", "1", "9", "space" }
for _, k in ipairs(naked) do
    local ok, reason = eb.validate_shortcut_policy(k)
    assert(ok == false, "Naked key " .. k .. " should be rejected")
    assert(reason == "printable-key-requires-global-modifier", "Wrong reason for " .. k .. ": " .. tostring(reason))
end
print("TEST_18_1_OK")
LUA_CHECK
)"
if grep -q "TEST_18_1_OK" <<< "$test_18_1_out"; then
    pass "18.1 naked printable characters rejected with printable-key-requires-global-modifier"
else
    fail "18.1 naked printable rejection failed: $test_18_1_out"
fi

# 18.2: Shift+printable character rejected
test_18_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local shift_printable = { "SHIFT + S", "Shift + a", "SHIFT + 1" }
for _, k in ipairs(shift_printable) do
    local ok, reason = eb.validate_shortcut_policy(k)
    assert(ok == false, "Shift+printable " .. k .. " should be rejected")
    assert(reason == "printable-key-requires-global-modifier", "Wrong reason for " .. k .. ": " .. tostring(reason))
end
print("TEST_18_2_OK")
LUA_CHECK
)"
if grep -q "TEST_18_2_OK" <<< "$test_18_2_out"; then
    pass "18.2 Shift+printable character rejected with printable-key-requires-global-modifier"
else
    fail "18.2 Shift+printable rejection failed: $test_18_2_out"
fi

# 18.3: Bare Escape rejected
test_18_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local bare_esc = { "Escape", "ESC", "escape" }
for _, k in ipairs(bare_esc) do
    local ok, reason = eb.validate_shortcut_policy(k)
    assert(ok == false, "Bare escape " .. k .. " should be rejected")
    assert(reason == "reserved-capture-control", "Wrong reason for " .. k .. ": " .. tostring(reason))
end
print("TEST_18_3_OK")
LUA_CHECK
)"
if grep -q "TEST_18_3_OK" <<< "$test_18_3_out"; then
    pass "18.3 bare Escape rejected with reserved-capture-control"
else
    fail "18.3 bare Escape rejection failed: $test_18_3_out"
fi

# 18.4: Legitimate global modifier combinations accepted
test_18_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local valid_globals = { "SUPER + B", "CTRL + ALT + T", "SUPER + SHIFT + Q", "SUPER + 1" }
for _, k in ipairs(valid_globals) do
    local ok, norm = eb.validate_shortcut_policy(k)
    assert(ok == true, "Global shortcut " .. k .. " should be accepted: " .. tostring(norm))
end
print("TEST_18_4_OK")
LUA_CHECK
)"
if grep -q "TEST_18_4_OK" <<< "$test_18_4_out"; then
    pass "18.4 legitimate global modifier combinations accepted"
else
    fail "18.4 global modifier acceptance failed: $test_18_4_out"
fi

# 18.5: Function and media keys accepted without global modifiers
test_18_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local special_keys = { "F1", "F12", "F24", "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute", "XF86MonBrightnessUp" }
for _, k in ipairs(special_keys) do
    local ok, norm = eb.validate_shortcut_policy(k)
    assert(ok == true, "Special key " .. k .. " should be accepted: " .. tostring(norm))
end
print("TEST_18_5_OK")
LUA_CHECK
)"
if grep -q "TEST_18_5_OK" <<< "$test_18_5_out"; then
    pass "18.5 function and media keys accepted without global modifiers"
else
    fail "18.5 function/media keys acceptance failed: $test_18_5_out"
fi

# 18.6: Canonical normalization reorders modifiers
test_18_6_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eb = require("effective_bindings")

local norm1 = eb.normalize_key("shift + super + x")
local norm2 = eb.normalize_key("super + shift + x")
assert(norm1 == "SUPER + SHIFT + X", "Wrong canonical: " .. tostring(norm1))
assert(norm1 == norm2, "Normalization mismatch: " .. norm1 .. " vs " .. norm2)

local norm3 = eb.normalize_key("alt + ctrl + super + t")
assert(norm3 == "SUPER + CTRL + ALT + T", "Wrong canonical: " .. tostring(norm3))

print("TEST_18_6_OK")
LUA_CHECK
)"
if grep -q "TEST_18_6_OK" <<< "$test_18_6_out"; then
    pass "18.6 canonical normalization reorders modifiers deterministically"
else
    fail "18.6 normalization test failed: $test_18_6_out"
fi
