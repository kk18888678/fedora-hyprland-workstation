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
    },
}
