local config_dir = (os.getenv("HOME") or "") .. "/.config/hypr"

package.path = table.concat({
    config_dir .. "/?.lua",
    config_dir .. "/?/init.lua",
    package.path,
}, ";")

-- QEMU/KVM virtio-gpu hardware cursor planes can render a small square
-- artifact when Chromium hides the pointer during fullscreen video. Detect an
-- attached virtio-gpu device narrowly so bare-metal systems and VMs with a
-- passed-through physical GPU retain the normal hardware-cursor path.
local function has_virtio_gpu_device()
    local handle = io.popen(
        "find /sys/bus/virtio/drivers/virtio_gpu " ..
        "-mindepth 1 -maxdepth 1 -type l -name 'virtio*' " ..
        "-print -quit"
    )
    if not handle then return false end

    local device = handle:read("*l") or ""
    handle:close()
    return device ~= ""
end

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

if has_virtio_gpu_device() then
    -- Keep the workaround in the compositor's desired state so it survives
    -- Hyprland reloads and applies to the logged-in VM session, not just the
    -- greeter. The detection above is intentionally fail-closed.
    hl.config({
        cursor = {
            no_hardware_cursors = 1,
        },
    })
    print("[COMPAT] confirmed virtio-gpu; hardware cursors disabled")
end

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

-- ---------------------------------------------------------------------------
-- Optional user-owned Hyprland settings overlay (workstation-hypr-settings).
--
-- The repository dotfiles above are the reviewed baseline. This section
-- re-applies a user-owned, schema-managed overlay written by
-- `workstation-hypr-settings` under $XDG_CONFIG_HOME/fedora-hyprland-workstation/
-- so `hyprctl reload` and the next session restore the user's tweaks.
-- The overlay is user-owned DATA: it is loaded fail-closed, like the Aurelia
-- provider bridge, and is never part of the repository desired state.
-- ---------------------------------------------------------------------------
local function load_user_settings_overlay()
    local config_home = os.getenv("XDG_CONFIG_HOME")
    if not config_home or config_home == "" then
        config_home = (os.getenv("HOME") or "") .. "/.config"
    end
    if config_home:sub(1, 1) ~= "/" or config_home == "/" then
        print("[SETTINGS] XDG_CONFIG_HOME is invalid; settings overlay skipped")
        return
    end

    local path = config_home .. "/fedora-hyprland-workstation/hypr-settings.lua"
    local handle = io.open(path, "rb")
    if not handle then
        -- No overlay: the reviewed baseline applies unchanged.
        return
    end
    handle:close()

    local ok_overlay, overlay = pcall(dofile, path)
    if not ok_overlay then
        error("[SETTINGS] user settings overlay failed to load; run `workstation-hypr-settings clear` to reset: " .. tostring(overlay))
    end
    if type(overlay) ~= "table" or overlay.schema_version ~= 1 then
        error("[SETTINGS] user settings overlay has an unsupported schema; run `workstation-hypr-settings clear` to reset")
    end

    if type(overlay.config) == "table" then
        for _, category in ipairs({ "general", "decoration", "misc", "input", "animations" }) do
            local values = overlay.config[category]
            if type(values) == "table" and next(values) ~= nil then
                hl.config({ [category] = values })
            end
        end
    end

    if type(overlay.animations) == "table" then
        for _, spec in ipairs(overlay.animations) do
            if type(spec) == "table" and type(spec.leaf) == "string" then
                hl.animation({
                    leaf = spec.leaf,
                    enabled = spec.enabled ~= false,
                    speed = type(spec.speed) == "number" and spec.speed or 1,
                    bezier = type(spec.bezier) == "string" and spec.bezier or "default",
                    style = type(spec.style) == "string" and spec.style or "slide",
                })
            end
        end
    end

    if type(overlay.persistent_workspaces) == "table" then
        for _, ws in ipairs(overlay.persistent_workspaces) do
            if type(ws) == "number" and ws >= 1 and ws <= 10 then
                hl.workspace_rule({
                    workspace = tostring(ws),
                    persistent = true,
                })
            end
        end
    end

    print("[SETTINGS] user settings overlay applied")
end

load_user_settings_overlay()

return true
