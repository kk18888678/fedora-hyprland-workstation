section "Hotkeys Presentation Parity"

hotkeys_rendered="$(HOTKEYS_FORCE_STDOUT=1 HOTKEYS_MANIFEST="$manifest_file" "$ROOT/bin/workstation-hotkeys" 2>/dev/null || true)"

# Every single binding and category in keybindings_manifest.lua must appear in the rendered hotkeys text
parity_check_output="$(
    HOTKEYS_TEXT="$hotkeys_rendered" "$lua_bin" - "$manifest_file" <<'LUA_CHECK'
local manifest = dofile(arg[1])
local rendered = os.getenv("HOTKEYS_TEXT") or ""

for _, cat in ipairs(manifest.categories) do
    if not rendered:find(cat, 1, true) then
        print("ERR: Category missing from rendered output: " .. cat)
        os.exit(1)
    end
end

for idx, b in ipairs(manifest.bindings) do
    if not b.generator then
        local key_str = b.display_key or b.key
        if key_str and not rendered:find(key_str, 1, true) then
            print("ERR: Key string missing from rendered output: " .. key_str)
            os.exit(1)
        end

        if b.description and not rendered:find(b.description, 1, true) then
            print("ERR: Description missing from rendered output: " .. b.description)
            os.exit(1)
        end
    end
end

for w = 1, 10 do
    local key_w = (w == 10) and "Super + 0" or ("Super + " .. w)
    if not rendered:find(key_w, 1, true) then
        print("ERR: Expanded workspace key missing: " .. key_w)
        os.exit(1)
    end
end

print("PARITY_VALID")
LUA_CHECK
)"

if grep -q "^PARITY_VALID" <<< "$parity_check_output"; then
    pass "workstation-hotkeys dynamically renders 100% of categories, keys, and descriptions from manifest"
else
    fail "hotkeys rendering parity mismatch: $parity_check_output"
fi
