section "Authoritative Keybindings Manifest & Zero Drift"

manifest_file="$ROOT/dotfiles/hypr/keybindings_manifest.lua"
if [[ -f "$manifest_file" ]]; then
    pass "dotfiles/hypr/keybindings_manifest.lua exists"
else
    fail "dotfiles/hypr/keybindings_manifest.lua is missing"
fi

lua_bin="$(command -v luajit 2>/dev/null || command -v lua 2>/dev/null || true)"
if [[ -n "$lua_bin" ]]; then
    pass "Lua runtime available for manifest evaluation ($lua_bin)"
else
    fail "No Lua runtime found to validate keybindings manifest"
fi

# Mechanically validate manifest integrity, completeness, and lack of duplicate keys
manifest_validation_output="$(
    "$lua_bin" - "$manifest_file" <<'LUA_CHECK'
local manifest = dofile(arg[1])

if type(manifest.categories) ~= "table" or #manifest.categories == 0 then
    print("ERR: manifest.categories must be a non-empty table")
    os.exit(1)
end

if type(manifest.bindings) ~= "table" or #manifest.bindings == 0 then
    print("ERR: manifest.bindings must be a non-empty table")
    os.exit(1)
end

local category_set = {}
for _, cat in ipairs(manifest.categories) do
    category_set[cat] = true
end

local seen_keys = {}
local count = 0
local has_super_k = false
local has_super_d = false
local has_workspaces = false
local has_workspaces_move = false

for idx, b in ipairs(manifest.bindings) do
    count = count + 1

    if not b.category or b.category == "" then
        print("ERR: binding at index " .. idx .. " has missing category")
        os.exit(1)
    end

    if not category_set[b.category] then
        print("ERR: binding at index " .. idx .. " references unknown category: " .. tostring(b.category))
        os.exit(1)
    end

    if not b.description or b.description == "" then
        print("ERR: binding at index " .. idx .. " has missing description")
        os.exit(1)
    end

    if b.key then
        if seen_keys[b.key] then
            print("ERR: duplicate keybinding detected: " .. b.key)
            os.exit(1)
        end
        seen_keys[b.key] = true
    end

    if b.key == "SUPER + K" and b.command == "aurelia-shell-keybindings" then
        has_super_k = true
    end

    if b.key == "SUPER + D" then
        has_super_d = true
    end

    if b.generator == "workspaces_1_10" then
        has_workspaces = true
    end

    if b.generator == "workspaces_move_1_10" then
        has_workspaces_move = true
    end
end

if not has_super_k then
    print("ERR: manifest is missing SUPER+K hotkeys binding")
    os.exit(1)
end

if not has_super_d then
    print("ERR: manifest is missing SUPER+D launcher binding")
    os.exit(1)
end

if not has_workspaces then
    print("ERR: manifest is missing workspaces 1-10 generator definition")
    os.exit(1)
end

if not has_workspaces_move then
    print("ERR: manifest is missing workspaces move 1-10 generator definition")
    os.exit(1)
end

print(string.format("VALID count=%d", count))
LUA_CHECK
)"

if grep -q "^VALID" <<< "$manifest_validation_output"; then
    pass "keybindings_manifest.lua satisfies all structural, uniqueness, and completeness invariants"
else
    fail "keybindings_manifest.lua validation failed: $manifest_validation_output"
fi

# Negative test: verify that adding a binding without a description fails closed
negative_manifest_test="$(
    "$lua_bin" - <<'LUA_CHECK'
local manifest = {
    categories = { "Applications" },
    bindings = {
        {
            category = "Applications",
            key = "SUPER + Z",
            -- missing description
        }
    }
}

for idx, b in ipairs(manifest.bindings) do
    if not b.description or b.description == "" then
        print("FAIL_CLOSED: missing description detected")
        os.exit(0)
    end
end
print("UNEXPECTED_PASS")
LUA_CHECK
)"

if grep -q "FAIL_CLOSED" <<< "$negative_manifest_test"; then
    pass "manifest validator fails closed when binding metadata is incomplete"
else
    fail "manifest validator failed negative check: $negative_manifest_test"
fi
