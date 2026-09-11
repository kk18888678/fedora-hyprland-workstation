local source = debug.getinfo(1, "S").source or ""
source = source:gsub("^@", "")
local shell_root = source:gsub("/plugins/aurelia%.bluetooth/keybindings%.lua$", "")
local shell_client = shell_root .. "/bin/aurelia-shell"
local client_file = io.open(shell_client, "rb")
if not client_file then
    shell_client = "/usr/local/bin/aurelia-shell"
else
    client_file:close()
end

return {
    {
        id = "aurelia.bluetooth.toggle",
        key = "SUPER + CTRL + B",
        description = "Bluetooth",
        category = "System",
        priority = 86,
        editable = true,
        runnable = true,
        keyboard_bindable = true,
        trigger_type = "keyboard",
        action_type = "plugin_ipc",
        target = "aurelia.bluetooth",
        method = "toggle",
        command_argv = { shell_client, "shell", "toggle", "aurelia.bluetooth", "{}" },
    },
}
