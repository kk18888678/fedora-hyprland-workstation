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
    "keybindings_manifest",
    "application_registry",
    "effective_bindings",
    "keybind",
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
require("keybind")
require("windowrules")
require("animations")
require("themes.theme")

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

-- Safely apply Noctalia dynamic theme template when generated
local ok, noctalia = pcall(require, "noctalia")
if ok and type(noctalia) == "table" and type(noctalia.apply_theme) == "function" then
    pcall(noctalia.apply_theme)
end

-- For Noctalia Color templates
require("noctalia").apply_theme()
