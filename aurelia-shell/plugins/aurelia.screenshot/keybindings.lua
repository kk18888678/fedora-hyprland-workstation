local source = debug.getinfo(1, "S").source or ""
source = source:gsub("^@", "")
local shell_root = source:gsub("/plugins/aurelia%.screenshot/keybindings%.lua$", "")
local shell_client = shell_root .. "/bin/aurelia-shell"
local client_file = io.open(shell_client, "rb")
if not client_file then
    shell_client = "/usr/local/bin/aurelia-shell"
else
    client_file:close()
end

return {
    {
        id = "aurelia.screenshot.quick_region",
        key = "SUPER + SHIFT + S",
        description = "Quick Screenshot Region",
        category = "Applications & Launchers",
        priority = 75,
        editable = true,
        runnable = true,
        keyboard_bindable = true,
        trigger_type = "keyboard",
        action_type = "plugin_ipc",
        target = "aurelia.screenshot",
        method = "quickRegion",
        command_argv = { shell_client, "shell", "call", "aurelia.screenshot", "quickRegion", "{}" },
    },
}
