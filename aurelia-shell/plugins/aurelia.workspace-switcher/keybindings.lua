local source = debug.getinfo(1, "S").source or ""
source = source:gsub("^@", "")
local shell_root = source:gsub("/plugins/aurelia%.workspace%-switcher/keybindings%.lua$", "")
local shell_client = shell_root .. "/bin/aurelia-shell"
local client_file = io.open(shell_client, "rb")
if not client_file then
    shell_client = "/usr/local/bin/aurelia-shell"
else
    client_file:close()
end

return {
    {
        id = "aurelia.workspace_switcher.toggle",
        key = "SUPER + TAB",
        description = "Workspace Overview",
        category = "Workspaces",
        priority = 190,
        editable = true,
        runnable = true,
        keyboard_bindable = true,
        trigger_type = "keyboard",
        action_type = "plugin_ipc",
        target = "aurelia.workspace-switcher",
        method = "toggle",
        command_argv = { shell_client, "shell", "call", "aurelia.workspace-switcher", "toggle", "{}" },
        -- Alt+Tab-style commit-on-release. The keybinding provider observes the
        -- SUPER release with the `input.keyboard.key` event (see keybind.lua
        -- for why a declarative `release = true` bind cannot express this) and
        -- forwards it as this bounded plugin IPC. The plugin stays the single
        -- owner of whether the overview is open and what should activate.
        release_commit = {
            modifier = "SUPER",
            command_argv = { shell_client, "shell", "call", "aurelia.workspace-switcher", "release", "{}" },
        },
    },
}
