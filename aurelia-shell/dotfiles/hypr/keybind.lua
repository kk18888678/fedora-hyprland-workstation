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

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function resolve_aurelia_shell_root()
    local configured = os.getenv("AURELIA_SHELL_ROOT") or ""
    if configured ~= "" then return configured:gsub("/$", "") end
    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    local hypr_dir = source:match("(.*/)") or ""
    return hypr_dir:gsub("/dotfiles/hypr/$", "")
end

local function register_plugin_keybindings()
    local shell_root = resolve_aurelia_shell_root()
    local declaration_path = shell_root .. "/plugins/aurelia.screenshot/keybindings.lua"
    local declaration_file = io.open(declaration_path, "rb")
    if not declaration_file then return end
    declaration_file:close()

    local ok, declarations = pcall(dofile, declaration_path)
    if not ok or type(declarations) ~= "table" then
        io.stderr:write("Aurelia screenshot keybinding declaration was rejected.\n")
        return
    end

    local ipc_client = shell_root .. "/bin/aurelia-shell"
    local executable = io.open(ipc_client, "rb")
    if not executable then
        ipc_client = "/usr/local/bin/aurelia-shell"
    else
        executable:close()
    end

    for _, item in ipairs(declarations) do
        if type(item) == "table" and type(item.key) == "string" and type(item.target) == "string" and type(item.method) == "string" then
            local command = table.concat({
                shell_quote(ipc_client),
                "shell call",
                shell_quote(item.target),
                shell_quote(item.method),
                "'{}'",
            }, " ")
            hl.bind(item.key, hl.dsp.exec_cmd(command), { description = item.description or item.id or "Plugin action" })
        end
    end
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

register_plugin_keybindings()

return true
