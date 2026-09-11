local config_dir = (os.getenv("HOME") or "") .. "/.config/hypr"

package.path = table.concat({
    config_dir .. "/?.lua",
    config_dir .. "/?/init.lua",
    package.path,
}, ";")

-- Clear locally managed modules when Hyprland reloads.
-- This ensures bindings, rules and other configuration are re-registered.
for _, module in ipairs({
    "monitors",
    "workspaces",
    "startup",
    "inputs",
    "windowrules",
    "animations",
    "themes.theme",
    "noctalia",
}) do
    package.loaded[module] = nil
end

require("monitors")
require("workspaces")
require("startup")
require("inputs")
require("windowrules")
require("animations")
require("themes.theme")

-- Optional Aurelia provider integration. The provider is user-owned and is
-- created only by aurelia-enable-hyprland-provider; the default Noctalia
-- session remains unchanged when the file is absent.
local aurelia_config_home = os.getenv("XDG_CONFIG_HOME")
if not aurelia_config_home or aurelia_config_home == "" then
    aurelia_config_home = (os.getenv("HOME") or "") .. "/.config"
end
local aurelia_provider_path = aurelia_config_home .. "/aurelia/hyprland-provider.lua"
local aurelia_provider_file = io.open(aurelia_provider_path, "rb")
if aurelia_provider_file then
    aurelia_provider_file:close()
    local provider_ok, provider_error = pcall(dofile, aurelia_provider_path)
    if not provider_ok then
        error("Aurelia Hyprland provider failed: " .. tostring(provider_error))
    end
end

local colors = require("noctalia.noctalia-colors")

hl.config({
    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        vrr = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        anr_missed_pings = 5,
        allow_session_lock_restore = true,
    },

    xwayland = {
        force_zero_scaling = true,
    },

    general = {
        col = colors.general.col,

        snap = {
            enabled = true,
        },
    },

    group = colors.group,
})

-- Safely apply the optional Noctalia-generated dynamic theme when present.
-- The Aurelia session must also work from a clean checkout where this ignored
-- generated module does not exist yet.
local ok, noctalia = pcall(require, "noctalia")
if ok and type(noctalia) == "table" and type(noctalia.apply_theme) == "function" then
    pcall(noctalia.apply_theme)
end
