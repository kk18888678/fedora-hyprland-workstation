-- Hyprland keyboard and mouse bindings.
-- Reads the authoritative declarative keybindings manifest and registers bindings with Hyprland.

local manifest = require("keybindings_manifest")
local effective_mod = require("effective_bindings")
local effective, err = effective_mod.resolve_bindings(manifest)
if not effective then
    error("Failed to resolve effective keybindings: " .. tostring(err))
end
local mainMod = effective.mainMod or manifest.mainMod or "SUPER"

local function resolve_keybindings_bin()
    if os.getenv("AURELIA_DEVELOPMENT_MODE") == "1" then
        local override = os.getenv("AURELIA_SHELL_KEYBINDINGS_BIN") or ""
        if override ~= "" then
            return override
        end
    end
    -- Prefer the reconciler-owned command, but keep upgrades from breaking an
    -- existing session whose older backend is still at the fixed compatibility
    -- path. Do not resolve through PATH or user-local shadowing.
    local canonical = "/usr/local/bin/aurelia-shell-keybindings"
    local compatibility = "/usr/local/bin/workstation-keybindings"
    local handle = io.open(canonical, "rb")
    if handle then
        handle:close()
        return canonical
    end

    -- When the provider is sourced directly from the standalone Aurelia
    -- checkout, use its sibling backend instead of an unrelated compatibility
    -- installation.
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    local source_dir = source:match("(.*/)")
    if source_dir then
        local source_backend = source_dir .. "../../bin/aurelia-shell-keybindings"
        local source_handle = io.open(source_backend, "rb")
        if source_handle then
            source_handle:close()
            return source_backend
        end
    end

    return compatibility
end

local keybindings_bin = resolve_keybindings_bin()

-- Resolve the bounded Aurelia Shell IPC client to an absolute path. PATH
-- resolution is deliberately avoided: Hyprland keybind execution inherits a
-- session environment where the checkout bin/ directory is not on PATH.
local function resolve_shell_ipc()
    if os.getenv("AURELIA_DEVELOPMENT_MODE") == "1" then
        local override = os.getenv("AURELIA_SHELL_IPC_BIN") or ""
        if override:sub(1, 1) == "/" then
            local handle = io.open(override, "rb")
            if handle then
                handle:close()
                return override
            end
        end
    end

    -- When this provider is sourced directly from the standalone Aurelia
    -- checkout, use its sibling IPC client.
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    local source_dir = source:match("(.*/)")
    if source_dir then
        local candidate = source_dir .. "../../bin/aurelia-shell"
        local handle = io.open(candidate, "rb")
        if handle then
            handle:close()
            return candidate
        end
    end

    -- Installed mode: the reconciler-owned fixed path.
    local installed = "/usr/local/bin/aurelia-shell"
    local handle = io.open(installed, "rb")
    if handle then
        handle:close()
        return installed
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Alt+Tab-style commit-on-modifier-release.
--
-- Alt+Tab semantics require the *modifier* release (SUPER) to commit the
-- current selection. Hyprland's declarative release flag (`release = true`, the
-- Lua equivalent of the hyprlang `bindr` keyword) is keyed to the bind's own
-- key: a `SUPER + TAB` release bind fires when TAB is released, not when SUPER
-- is, which would commit in the middle of a multi-TAB cycle. A release bind on
-- the bare SUPER key is layout/keycode specific and cannot be scoped to the
-- interaction that is actually active. The `input.keyboard.key` event reports
-- every raw key event, including modifier release, to Lua before keybind
-- consumption, so the provider can observe the real SUPER release and deliver
-- it to the plugin as a bounded IPC signal. The plugin remains the single owner
-- of whether the overview is open and which workspace is selected.
local MODIFIER_XKB_KEYCODES = {
    SUPER = { [133] = true, [134] = true }, -- XKB SUPER_L / SUPER_R
}

-- Companion command armed by the most recent gated press. Nil means no
-- modifier-release interaction is in flight, so ordinary SUPER shortcuts never
-- pay an IPC cost on release.
local armed_release_commit = nil

local function quote_argv(argv)
    local parts = {}
    for _, value in ipairs(argv) do
        table.insert(parts, "'" .. tostring(value):gsub("'", "'\\''") .. "'")
    end
    return table.concat(parts, " ")
end

local function release_commit_for(item)
    local companion = item.release_commit
    if type(companion) ~= "table" then return nil, nil end

    local keycodes = MODIFIER_XKB_KEYCODES[tostring(companion.modifier or "")]
    if not keycodes then
        print("[BIND] release_commit has an unsupported modifier for " .. tostring(item.id))
        return nil, nil
    end

    if type(companion.command_argv) ~= "table" or #companion.command_argv == 0 then
        print("[BIND] release_commit has no command_argv for " .. tostring(item.id))
        return nil, nil
    end

    return keycodes, quote_argv(companion.command_argv)
end

local function register_release_commit()
    hl.on("input.keyboard.key", function(keycode, _time, state)
        if state ~= 0 then return end -- release events only
        local armed = armed_release_commit
        if not armed or not armed.keycodes[keycode] then return end
        armed_release_commit = nil
        hl.exec_cmd(armed.command)
    end)
end

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

    if item.unbound or item.action_type == "gesture" then
        -- Touchpad gesture or user-unbound entry: skip registration
        return
    end

    if not item.key or item.key == "" or item.key == "None" then
        return
    end

    local desc = item.description or "Unlabeled binding"
    local flags = { description = desc }

    if item.action_type == "exec" then
        if not item.command or item.command == "" or item.runnable == false then
            -- Action has no runnable command available: do not register broken binding
            return
        end
        -- Single action execution authority:
        -- Keybindings dispatch via the authoritative workstation runner:
        -- aurelia-shell-keybindings run <action_id>
        -- This guarantees identical execution authority and semantics between UI Run and physical keybinding.
        local cmd = item.command
        if item.id and (item.id:match("^[a-zA-Z0-9][%w%-%._]*$") or item.id:match("^[a-zA-Z0-9][%w%-%._]*:[a-zA-Z0-9][%w%-%._]*$")) then
            if item.id == "keybindings" or item.id == "hotkeys" then
                cmd = keybindings_bin .. " toggle"
            elseif item.id == "desktop_settings" then
                -- Settings hub toggle must not depend on PATH: resolve the
                -- Aurelia Shell IPC client absolutely (checkout or installed).
                -- The shell `toggle(pluginId, payloadJson)` IPC requires both
                -- arguments; the payload defaults to the empty settings object.
                local ipc = resolve_shell_ipc()
                if not ipc then
                    print("[BIND] desktop_settings: aurelia-shell IPC client not found; binding skipped")
                    return
                end
                cmd = ipc .. " shell toggle aurelia.settings '{}'"
            else
                cmd = keybindings_bin .. " run " .. item.id
            end
        end
        hl.bind(item.key, hl.dsp.exec_cmd(cmd), flags)
    elseif item.action_type == "exec_locked" then
        flags.locked = true
        if not item.command or item.command == "" or item.runnable == false then
            return
        end
        hl.bind(item.key, hl.dsp.exec_cmd(item.command), flags)
    elseif item.action_type == "plugin_ipc" then
        if type(item.command_argv) ~= "table" or #item.command_argv == 0 then return end
        local command = quote_argv(item.command_argv)
        local release_keycodes, release_command = release_commit_for(item)
        if release_command then
            -- Arm the companion before dispatching the press so a fast
            -- SUPER+TAB tap still lets the release commit once the plugin is
            -- open. The plugin ignores the signal when it is closed.
            hl.bind(item.key, function()
                armed_release_commit = { keycodes = release_keycodes, command = release_command }
                hl.exec_cmd(command)
            end, flags)
        else
            hl.bind(item.key, hl.dsp.exec_cmd(command), flags)
        end
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
    elseif item.action_type == "focus_workspace" then
        hl.bind(item.key, hl.dsp.focus({ workspace = item.workspace }), flags)
    elseif item.action_type == "move_to_workspace" then
        hl.bind(item.key, hl.dsp.window.move({ workspace = item.workspace }), flags)
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

register_release_commit()

return true
