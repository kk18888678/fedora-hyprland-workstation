-- Hyprland session environment and startup services.

local environment = {
    "XDG_CURRENT_DESKTOP,Hyprland",
    "XDG_SESSION_TYPE,wayland",
    "QT_AUTO_SCREEN_SCALE_FACTOR,1",
    "QT_WAYLAND_DISABLE_WINDOWDECORATION,1",
    "QT_QPA_PLATFORMTHEME,qt6ct",
    "ELECTRON_OZONE_PLATFORM_HINT,wayland",
}

for _, item in ipairs(environment) do
    local key, value = item:match("^([^,]+),(.+)$")

    if key and value then
        hl.env(key, value)
    end
end

local exec_once = {
    "gnome-keyring-daemon --start --components=secrets",
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP",
    "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP",
}

hl.on("hyprland.start", function()
    -- Initial persistent workspaces (1, 2, 3) available on any connected display
    for _, ws in ipairs({ 1, 2, 3 }) do
        hl.exec_cmd(string.format('hyprctl keyword workspace "%d, persistent:true"', ws))
    end

    for _, command in ipairs(exec_once) do
        hl.exec_cmd(command)
    end

    -- Fedora packages hyprpolkitagent as a systemd/D-Bus user service.
    -- Do not manually launch /usr/libexec/hyprpolkitagent here.

    -- Noctalia is installed and enabled by the workstation profile.
    hl.exec_cmd("noctalia")
end)

return true
