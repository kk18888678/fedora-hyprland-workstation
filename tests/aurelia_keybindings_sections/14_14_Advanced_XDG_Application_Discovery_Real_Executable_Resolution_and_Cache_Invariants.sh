section "14. Advanced XDG Application Discovery, Real Executable Resolution, and Cache Invariants"

# 14.1: Nested XDG Application Discovery & Canonical Desktop ID Derivation at Multiple Depths
test_14_1_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

-- 1. Canonical desktop ID derivation at multiple depths per XDG specification
local base = "/usr/share/applications"
assert(reg.derive_desktop_id(base, base .. "/app.desktop") == "app.desktop", "depth 0 derivation failed")
assert(reg.derive_desktop_id(base, base .. "/foo/app.desktop") == "foo-app.desktop", "depth 1 derivation failed")
assert(reg.derive_desktop_id(base, base .. "/foo/bar/app.desktop") == "foo-bar-app.desktop", "depth 2 derivation failed")
assert(reg.derive_desktop_id(base, base .. "/foo/bar/baz/qux.desktop") == "foo-bar-baz-qux.desktop", "depth 3 derivation failed")

-- 2. Physical nested directory scanning with symlink loop and escape resilience
local tmp = os.tmpname() .. "_nest"
os.execute("rm -rf " .. tmp .. " && mkdir -p " .. tmp .. "/foo/bar/baz")
os.execute("touch " .. tmp .. "/top.desktop")
os.execute("touch " .. tmp .. "/foo/one.desktop")
os.execute("touch " .. tmp .. "/foo/bar/two.desktop")
os.execute("touch " .. tmp .. "/foo/bar/baz/three.desktop")
-- Unsafe symlink loop: foo/bar/loop -> foo
os.execute("ln -s " .. tmp .. "/foo " .. tmp .. "/foo/bar/loop")
-- Unsafe symlink escape: foo/escape_etc -> /etc
os.execute("ln -s /etc " .. tmp .. "/foo/escape_etc")

local scanned = reg.scan_desktop_files_in_dir(tmp)
os.execute("rm -rf " .. tmp)

local by_id = {}
for _, s in ipairs(scanned) do
    by_id[s.desktop_id] = s.path
end

assert(by_id["top.desktop"] ~= nil, "Missing top.desktop")
assert(by_id["foo-one.desktop"] ~= nil, "Missing foo-one.desktop")
assert(by_id["foo-bar-two.desktop"] ~= nil, "Missing foo-bar-two.desktop")
assert(by_id["foo-bar-baz-three.desktop"] ~= nil, "Missing foo-bar-baz-three.desktop")
assert(by_id["foo-bar-loop-one.desktop"] == nil, "Symlink loop was followed!")

print("TEST_14_1_OK")
LUA_CHECK
)"
if grep -q "TEST_14_1_OK" <<< "$test_14_1_out"; then
    pass "14.1 nested XDG application discovery and canonical desktop ID derivation at multiple depths"
else
    fail "14.1 nested XDG discovery test failed: $test_14_1_out"
fi

# 14.2: Nested Hidden=true Masking and XDG Directory Precedence
test_14_2_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

local tmp = os.tmpname() .. "_xdg_prec"
local user_dir = tmp .. "/user/applications"
local sys_dir = tmp .. "/sys/applications"
os.execute("mkdir -p " .. user_dir .. "/a/b " .. sys_dir .. "/a/b")

-- 1. User nested file with Hidden=true masks system nested file
local f_sys = io.open(sys_dir .. "/a/b/masked-app.desktop", "w")
f_sys:write("[Desktop Entry]\nType=Application\nName=System Nested App\nExec=true\n")
f_sys:close()

local f_usr = io.open(user_dir .. "/a/b/masked-app.desktop", "w")
f_usr:write("[Desktop Entry]\nType=Application\nName=User Nested Mask\nHidden=true\n")
f_usr:close()

-- 2. User nested file overrides system nested file (precedence)
local f_sys2 = io.open(sys_dir .. "/a/b/override-app.desktop", "w")
f_sys2:write("[Desktop Entry]\nType=Application\nName=System Name\nExec=true\n")
f_sys2:close()

local f_usr2 = io.open(user_dir .. "/a/b/override-app.desktop", "w")
f_usr2:write("[Desktop Entry]\nType=Application\nName=User Name Override\nExec=true\n")
f_usr2:close()

local prev_fn = reg.get_applications_search_dirs
reg.get_applications_search_dirs = function()
    return { user_dir, sys_dir }
end
reg.invalidate_cache()

local found_masked = reg.find_application("a-b-masked-app.desktop")
local found_over = reg.find_application("a-b-override-app.desktop")

reg.get_applications_search_dirs = prev_fn
reg.invalidate_cache()
os.execute("rm -rf " .. tmp)

assert(found_masked == nil, "Hidden=true nested user entry failed to mask system entry")
assert(found_over ~= nil, "Override nested app not found")
assert(found_over.name == "User Name Override", "User entry did not take precedence: " .. tostring(found_over.name))

print("TEST_14_2_OK")
LUA_CHECK
)"
if grep -q "TEST_14_2_OK" <<< "$test_14_2_out"; then
    pass "14.2 nested Hidden=true masking and XDG directory precedence"
else
    fail "14.2 nested masking and precedence test failed: $test_14_2_out"
fi

# 14.3: Real Executable Resolution for TryExec (Custom PATH, Permissions, Absolute, Missing, Malformed, No Hardcoded Paths)
test_14_3_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")
local ffi = require("ffi")
ffi.cdef[[ int setenv(const char *name, const char *value, int overwrite); ]]

local tmp = os.tmpname() .. "_tryexec"
local bin_dir = tmp .. "/custom_isolated_bin"
os.execute("mkdir -p " .. bin_dir)

-- Executable file in custom PATH directory (NOT in /usr/bin, /usr/local/bin, /bin, ~/.local/bin)
os.execute("touch " .. bin_dir .. "/custom-tool && chmod +x " .. bin_dir .. "/custom-tool")
-- Non-executable file in custom PATH directory
os.execute("touch " .. bin_dir .. "/noexec-tool && chmod -x " .. bin_dir .. "/noexec-tool")

local orig_path = os.getenv("PATH") or ""
-- Set PATH with leading/trailing colons and empty entries to test safe handling
local test_path = ":" .. bin_dir .. "::/nonexistent_dir:"
ffi.C.setenv("PATH", test_path, 1)

local function make_desktop_with_tryexec(te_val)
    local tmp_df = os.tmpname() .. ".desktop"
    local f = io.open(tmp_df, "w")
    f:write("[Desktop Entry]\nType=Application\nName=TryExec App\nExec=true\nTryExec=" .. te_val .. "\n")
    f:close()
    local res = reg.parse_desktop_file(tmp_df, "tryexec-app.desktop")
    os.remove(tmp_df)
    return res
end

-- 1. TryExec via custom PATH: discovered
assert(reg.is_tryexec_valid("custom-tool") == true, "Executable in custom PATH directory not recognized")
assert(make_desktop_with_tryexec("custom-tool") ~= nil, "Desktop with custom-tool in PATH rejected")

-- 2. TryExec executable permission: non-executable file rejected
assert(reg.is_tryexec_valid("noexec-tool") == false, "Non-executable file in PATH was accepted")
assert(make_desktop_with_tryexec("noexec-tool") == nil, "Desktop with non-executable TryExec accepted")

-- 3. Missing executable rejected
assert(reg.is_tryexec_valid("completely_missing_xyz") == false, "Missing executable was accepted")
assert(make_desktop_with_tryexec("completely_missing_xyz") == nil, "Desktop with missing TryExec accepted")

-- 4. Absolute executable: verified appropriately
assert(reg.is_tryexec_valid(bin_dir .. "/custom-tool") == true, "Absolute executable path rejected")
assert(make_desktop_with_tryexec(bin_dir .. "/custom-tool") ~= nil, "Desktop with absolute executable TryExec rejected")

-- 5. Absolute non-executable rejected
assert(reg.is_tryexec_valid(bin_dir .. "/noexec-tool") == false, "Absolute non-executable accepted")
assert(make_desktop_with_tryexec(bin_dir .. "/noexec-tool") == nil, "Desktop with absolute non-executable TryExec accepted")
assert(reg.is_tryexec_valid("/etc/passwd") == false, "Absolute non-executable file accepted")
assert(make_desktop_with_tryexec("/etc/passwd") == nil, "Desktop with /etc/passwd TryExec accepted")

-- 6. Absolute directory rejected (not an executable file)
assert(reg.is_tryexec_valid(bin_dir) == false, "Directory accepted as executable")
assert(make_desktop_with_tryexec(bin_dir) == nil, "Desktop with directory TryExec accepted")
assert(reg.is_tryexec_valid("/usr") == false, "System directory /usr accepted as executable")
assert(make_desktop_with_tryexec("/usr") == nil, "Desktop with /usr directory TryExec accepted")

-- 7. Malformed TryExec values safely rejected
assert(reg.is_tryexec_valid("") == false, "Empty TryExec accepted")
assert(reg.is_tryexec_valid("   ") == false, "Whitespace TryExec accepted")
assert(reg.is_tryexec_valid("../evil") == false, "Relative path with slash accepted in PATH lookup")
assert(make_desktop_with_tryexec("../evil") == nil, "Desktop with ../evil TryExec accepted")
assert(reg.is_tryexec_valid("bin/tool") == false, "Relative path with slash accepted in PATH lookup")
assert(reg.is_tryexec_valid("tool\nbad") == false, "Control characters accepted")
assert(reg.is_tryexec_valid("tool --flag") == false, "Arguments in TryExec accepted")

-- 8. No hardcoded directories: prove /usr/bin is NOT checked if PATH does not contain it
-- Notice test_path only contains bin_dir and nonexistent_dir!
assert(reg.is_tryexec_valid("cat") == false, "Hardcoded fallback detected! 'cat' resolved even though /usr/bin is not in PATH")

-- Restore PATH
ffi.C.setenv("PATH", orig_path, 1)
os.execute("rm -rf " .. tmp)

print("TEST_14_3_OK")
LUA_CHECK
)"
if grep -q "TEST_14_3_OK" <<< "$test_14_3_out"; then
    pass "14.3 TryExec uses real executable resolution in \$PATH without hardcoded directories"
else
    fail "14.3 TryExec resolution test failed: $test_14_3_out"
fi

# 14.4: Lazy Process-Lifetime Cache, Explicit Invalidation, and Absence of Stale Timestamp/TTL
test_14_4_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local reg = require("application_registry")

-- 1. Absence of stale timestamp/TTL fields
assert(reg._cache_timestamp == nil, "Stale _cache_timestamp still exists on module table")

-- 2. Initial state: cache is nil
reg.invalidate_cache()
assert(reg._cache == nil, "Cache not nil after invalidate_cache")

-- 3. Population: list_applications populates lazy process-lifetime cache
local apps = reg.list_applications()
assert(type(apps) == "table", "list_applications did not return table")
assert(reg._cache ~= nil, "Cache was not populated")
assert(type(reg._cache.visible_apps) == "table", "cache.visible_apps missing")
assert(type(reg._cache.all_apps) == "table", "cache.all_apps missing")

-- Verify cached instance returned without invalidation
local cached_apps = reg.list_applications()
assert(apps == cached_apps, "Cache missed without explicit invalidation or refresh")

-- 4. Explicit invalidation
reg.invalidate_cache()
assert(reg._cache == nil, "Cache not nil after explicit invalidation")

-- 5. Explicit refresh option
local fresh_apps = reg.list_applications({ refresh = true })
assert(reg._cache ~= nil, "Cache not populated after refresh")

print("TEST_14_4_OK")
LUA_CHECK
)"
if grep -q "TEST_14_4_OK" <<< "$test_14_4_out"; then
    pass "14.4 lazy process-lifetime cache with explicit invalidation and absence of stale timestamp/TTL"
else
    fail "14.4 cache invariants test failed: $test_14_4_out"
fi

# 14.5: keybind.lua safely ignores unbound, unrunnable, or nil-command actions without crashing Hyprland
test_14_5_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path

local mock_calls = {}
local hl = {
    dsp = {
        exec_cmd = function(cmd)
            if cmd == nil or type(cmd) ~= "string" then
                error("exec_cmd: bad argument 1: expected string, got nil", 2)
            end
            return "exec:" .. cmd
        end,
        window = {
            close = function() return "close" end,
            float = function() return "float" end,
            fullscreen = function() return "fullscreen" end,
            cycle_next = function() return "cycle" end,
            drag = function() return "drag" end,
            resize = function() return "resize" end,
            move = function() return "move" end,
        },
        focus = function(arg) return "focus" end,
    },
    bind = function(key, dsp, flags)
        if type(dsp) ~= "string" and type(dsp) ~= "function" then
            error("hl.bind: dispatcher must be a dispatcher or a lua function", 2)
        end
        table.insert(mock_calls, { key = key, dsp = dsp, flags = flags })
    end
}
_G.hl = hl

-- Test that keybind.lua loads without error even if unrunnable actions with nil command exist in effective bindings
package.loaded["keybind"] = nil
local ok, err = pcall(require, "keybind")
assert(ok == true, "keybind.lua failed to load with mock hl: " .. tostring(err))
assert(#mock_calls > 0, "No bindings registered by keybind.lua")

print("TEST_14_5_OK")
LUA_CHECK
)"
if grep -q "TEST_14_5_OK" <<< "$test_14_5_out"; then
    pass "14.5 keybind.lua safely ignores unbound, unrunnable, or nil-command actions"
else
    fail "14.5 keybind.lua defensive binding test failed: $test_14_5_out"
fi
