section "Keybind Manifest Generator & Action Dispatch Execution"

keybind_dispatch_output="$(
    "$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
local bound_keys = {}
local hl = {
    bind = function(key, action, flags)
        bound_keys[key] = { action = action, flags = flags }
    end,
    dsp = {
        focus = function(t) return function() end end,
        exec_cmd = function(cmd) return function() end end,
        window = {
            close = function() return function() end end,
            float = function(t) return function() end end,
            fullscreen = function() return function() end end,
            cycle_next = function() return function() end end,
            move = function(t) return function() end end,
            drag = function() return function() end end,
            resize = function() return function() end end,
        },
    },
    exec_cmd = function(cmd) end,
}
_G.hl = hl

package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
package.loaded["keybindings_manifest"] = nil
package.loaded["keybind"] = nil
require("keybind")

-- Verify workspace 1-10 focus generated from manifest
for i = 1, 9 do
    assert(bound_keys["SUPER + " .. i], "Missing focus workspace " .. i)
    assert(bound_keys["SUPER + SHIFT + " .. i], "Missing move workspace " .. i)
end
assert(bound_keys["SUPER + 0"], "Missing focus workspace 10 (SUPER + 0)")
assert(bound_keys["SUPER + SHIFT + 0"], "Missing move workspace 10 (SUPER + SHIFT + 0)")
assert(bound_keys["SUPER + K"], "Missing SUPER + K")
assert(bound_keys["SUPER + D"], "Missing SUPER + D")

-- Negative test: unknown generator must fail closed
package.loaded["keybindings_manifest"] = {
    mainMod = "SUPER",
    bindings = {
        {
            category = "Workspaces",
            generator = "unknown_generator_xyz",
            description = "Unknown generator",
        }
    }
}
package.loaded["keybind"] = nil
local ok_gen, err_gen = pcall(function() require("keybind") end)
assert(not ok_gen and tostring(err_gen):find("Unsupported keybinding generator"), "Failed to reject unknown generator: " .. tostring(err_gen))

-- Negative test: unknown action_type must fail closed
package.loaded["keybindings_manifest"] = {
    mainMod = "SUPER",
    bindings = {
        {
            category = "Window Management",
            key = "SUPER + Z",
            action_type = "unknown_action_xyz",
            description = "Unknown action",
        }
    }
}
package.loaded["keybind"] = nil
local ok_act, err_act = pcall(function() require("keybind") end)
assert(not ok_act and tostring(err_act):find("Unsupported keybinding action_type"), "Failed to reject unknown action_type: " .. tostring(err_act))

print("DISPATCH_VALID")
LUA_CHECK
)"

if grep -q "^DISPATCH_VALID" <<< "$keybind_dispatch_output"; then
    pass "keybind.lua accurately dispatches generated workspace bindings and rejects unknown generators/actions"
else
    fail "keybind.lua generator dispatch failed: $keybind_dispatch_output"
fi
