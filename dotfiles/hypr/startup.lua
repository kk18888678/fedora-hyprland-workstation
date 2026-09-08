-- Hyprland session environment and startup services.

local environment = {
    "XDG_CURRENT_DESKTOP,Hyprland",
    "XDG_SESSION_DESKTOP,Hyprland",
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
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE DISPLAY HYPRLAND_INSTANCE_SIGNATURE",
    "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE DISPLAY HYPRLAND_INSTANCE_SIGNATURE",
}

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function read_realpath(path)
    local handle = io.popen("readlink -f -- " .. shell_quote(path) .. " 2>/dev/null")
    if not handle then return nil end
    local resolved = handle:read("*l")
    handle:close()
    return resolved
end

local function is_readable_file(path)
    if not path or path == "" then return false end
    local handle = io.open(path, "rb")
    if not handle then return false end
    handle:close()
    return true
end

local function resolve_aurelia_launcher()
    local override = os.getenv("AURELIA_SHELL_LAUNCHER") or ""
    if override:sub(1, 1) == "/" and is_readable_file(override) then
        return override
    end

    local source = debug.getinfo(1, "S").source or ""
    source = source:gsub("^@", "")
    source = read_realpath(source) or source
    local checkout_launcher = source:gsub(
        "/dotfiles/hypr/startup%.lua$",
        "/aurelia-shell/bin/aurelia-launch-shell"
    )
    if is_readable_file(checkout_launcher) then
        return checkout_launcher
    end

    if is_readable_file("/usr/local/bin/aurelia-launch-shell") then
        return "/usr/local/bin/aurelia-launch-shell"
    end

    return nil
end

hl.on("hyprland.start", function()
    for _, command in ipairs(exec_once) do
        hl.exec_cmd(command)
    end

    -- Fedora packages hyprpolkitagent as a systemd/D-Bus user service.
    -- Do not manually launch /usr/libexec/hyprpolkitagent here.

    local aurelia_launcher = resolve_aurelia_launcher()
    if aurelia_launcher then
        -- aurelia-launch-shell owns --no-duplicate and selects the source
        -- checkout or installed shell root. Hyprland only owns session start.
        hl.exec_cmd(shell_quote(aurelia_launcher))
    else
        print("[AURELIA] launcher not found; resident shell autostart skipped")
    end

    -- Noctalia is installed and enabled by the workstation profile.
    hl.exec_cmd("noctalia")

end)

return true
