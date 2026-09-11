local source = debug.getinfo(1, "S").source or ""
source = source:gsub("^@", "")
local shell_root = source:gsub("/plugins/aurelia%.image%-picker/keybindings%.lua$", "")
local shell_client = shell_root .. "/bin/aurelia-shell"
local client_file = io.open(shell_client, "rb")
if not client_file then
    shell_client = "/usr/local/bin/aurelia-shell"
else
    client_file:close()
end

return {
    {
        id = "aurelia.theme.switcher",
        key = "SUPER + SHIFT + CTRL + SPACE",
        description = "Theme Picker",
        category = "System",
        priority = 84,
        editable = true,
        runnable = true,
        keyboard_bindable = true,
        trigger_type = "keyboard",
        action_type = "plugin_ipc",
        target = "aurelia.image-picker",
        method = "open",
        command_argv = {
            shell_client,
            "shell",
            "call",
            "aurelia.image-picker",
            "open",
            '{"mode":"theme"}',
        },
    },
    {
        id = "aurelia.background.switcher",
        key = "SUPER + CTRL + SPACE",
        description = "Background Picker",
        category = "System",
        priority = 83,
        editable = true,
        runnable = true,
        keyboard_bindable = true,
        trigger_type = "keyboard",
        action_type = "plugin_ipc",
        target = "aurelia.image-picker",
        method = "open",
        command_argv = {
            shell_client,
            "shell",
            "call",
            "aurelia.image-picker",
            "open",
            '{"mode":"background"}',
        },
    },
}
