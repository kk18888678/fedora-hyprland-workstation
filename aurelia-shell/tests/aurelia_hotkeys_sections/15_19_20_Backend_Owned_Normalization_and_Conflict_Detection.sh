section "19-20. Backend-Owned Normalization and Conflict Detection"

# Test 19: Canonical normalization remains backend-owned
norm_test="$(
"$lua_bin" - "$ROOT/dotfiles/hypr" <<'LUA'
local dir = arg[1]
package.path = dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local k1 = eff.canonical_key("ctrl + alt + super + k")
local k2 = eff.canonical_key("super + ctrl + alt + k")
if k1 == k2 and k1 == "super+ctrl+alt+k" then
    print("NORM_OK")
else
    print("NORM_FAIL:" .. tostring(k1) .. " vs " .. tostring(k2))
end
LUA
)"
if [[ "$norm_test" == "NORM_OK" ]]; then
    pass "19. canonical normalization remains backend-owned"
else
    fail "19. canonical normalization failed: $norm_test"
fi

# Test 20: Conflict detection remains backend-owned
conflict_test="$(
"$lua_bin" - "$ROOT/dotfiles/hypr" <<'LUA'
local dir = arg[1]
package.path = dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local m = dofile(dir .. "/keybindings_manifest.lua")
local conflict = eff.find_conflict("browser", "SUPER + RETURN", m)
if conflict and conflict.id == "terminal" then
    print("CONFLICT_DETECTED")
else
    print("CONFLICT_MISSED")
end
LUA
)"
if [[ "$conflict_test" == "CONFLICT_DETECTED" ]]; then
    pass "20. conflict detection remains backend-owned"
else
    fail "20. conflict detection failed: $conflict_test"
fi
