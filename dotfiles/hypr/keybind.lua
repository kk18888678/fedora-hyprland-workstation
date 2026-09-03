-- Hyprland keyboard and mouse bindings.
-- Reads the authoritative declarative keybindings manifest and registers bindings with Hyprland.

local manifest = require("keybindings_manifest")
local effective_mod = require("effective_bindings")
local effective = effective_mod.resolve_bindings(manifest)
local mainMod = effective.mainMod or manifest.mainMod or "SUPER"

local function register_binding(item)
    if item.generator then
        if item.generator == "workspaces_1_10" then
            for i = 1, 9 do
                local focusKey = ("%s + %d"):format(mainMod, i)
                hl.bind(focusKey, hl.dsp.focus({ workspace = i }), { description = "Workspace " .. i })
            end
            hl.bind(("%s + 0"):format(mainMod), hl.dsp.focus({ workspace = 10 }), { description = "Workspace 10" })
        elseif item.generator == "workspaces_move_1_10" then
            for i = 1, 9 do
                local moveKey = ("%s + SHIFT + %d"):format(mainMod, i)
                hl.bind(moveKey, hl.dsp.window.move({ workspace = i }), { description = "Move to workspace " .. i })
            end
            hl.bind(("%s + SHIFT + 0"):format(mainMod), hl.dsp.window.move({ workspace = 10 }), { description = "Move to workspace 10" })
        else
            error("Unsupported keybinding generator: " .. tostring(item.generator))
        end
        return
    end

    if not item.key and (item.action_type == "gesture" or item.unbound) then
        -- Touchpad gesture or user-unbound entry: skip registration
        return
    end

    if not item.key then
        error("Keybinding entry missing key definition: " .. tostring(item.description or "unlabeled"))
    end

    local desc = item.description or "Unlabeled binding"
    local flags = { description = desc }

    if item.action_type == "exec" then
        hl.bind(item.key, hl.dsp.exec_cmd(item.command), flags)
    elseif item.action_type == "exec_locked" then
        flags.locked = true
        hl.bind(item.key, hl.dsp.exec_cmd(item.command), flags)
    elseif item.action_type == "dispatch_close" then
        hl.bind(item.key, hl.dsp.window.close(), flags)
    elseif item.action_type == "dispatch_float" then
        hl.bind(item.key, hl.dsp.window.float({ action = "toggle" }), flags)
    elseif item.action_type == "dispatch_fullscreen" then
        hl.bind(item.key, hl.dsp.window.fullscreen(), flags)
    elseif item.action_type == "dispatch_cycle" then
        hl.bind(item.key, hl.dsp.window.cycle_next(), flags)
    elseif item.action_type == "focus" then
        hl.bind(item.key, hl.dsp.focus({ direction = item.direction }), flags)
    elseif item.action_type == "exec_resize" then
        local args = item.resize_args
        hl.bind(item.key, function()
            hl.exec_cmd("hyprctl dispatch resizeactive " .. args)
        end, flags)
    elseif item.action_type == "focus_workspace_relative" then
        hl.bind(item.key, hl.dsp.focus({ workspace = item.workspace }), flags)
    elseif item.action_type == "mouse_drag" then
        flags.mouse = true
        hl.bind(item.key, hl.dsp.window.drag(), flags)
    elseif item.action_type == "mouse_resize" then
        flags.mouse = true
        hl.bind(item.key, hl.dsp.window.resize(), flags)
    else
        error("Unsupported keybinding action_type: " .. tostring(item.action_type))
    end
end

for _, item in ipairs(effective.bindings or {}) do
    register_binding(item)
end

return true
