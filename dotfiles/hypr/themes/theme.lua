-- Default Hyprland workstation theme.
--
-- Keep the initial desktop clean and lightweight.
-- Transparency, blur and custom cursor themes can be introduced
-- after the baseline desktop has been validated.

hl.config({
    general = {
        gaps_in = 3,
        gaps_out = 6,

        border_size = 2,
        resize_on_border = true,

        allow_tearing = false,
        layout = "dwindle",
    },

    decoration = {
        rounding = 8,

        active_opacity = 1.0,
        inactive_opacity = 1.0,
        fullscreen_opacity = 1.0,

        shadow = {
            enabled = true,
        },

        blur = {
            enabled = false,
        },
    },
})

return true
