local source = debug.getinfo(1, "S").source or ""
source = source:gsub("^@", "")
local shell_root = source:gsub("/plugins/aurelia%.launcher/keybindings%.lua$", "")
local shell_client = shell_root .. "/bin/aurelia-shell"
local client_file = io.open(shell_client, "rb")
if not client_file then
    shell_client = "/usr/local/bin/aurelia-shell"
else
    client_file:close()
end

return {
    {
        -- Keep the historical action id so user-owned launcher overrides
        -- continue to apply while the execution owner moves from Noctalia to
        -- Aurelia.
        id = "launcher",
        key = "SUPER + SPACE",
        description = "Aurelia Command Center",
        category = "Applications & Launchers",
        priority = 10,
        editable = true,
        runnable = true,
        keyboard_bindable = true,
        trigger_type = "keyboard",
        action_type = "plugin_ipc",
        target = "aurelia.launcher",
        method = "toggle",
        command_argv = { shell_client, "shell", "toggle", "aurelia.launcher", "{}" },
    },
}
