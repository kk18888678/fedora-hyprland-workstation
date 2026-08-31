-- Default Hyprland animation preset.
--
-- Smooth and responsive without unnecessary continuous animation.

hl.config({
    animations = {
        enabled = true,
    },
})

hl.curve("workstation", {
    type = "bezier",
    points = {
        { 0.05, 0.9 },
        { 0.1, 1.0 },
    },
})

hl.curve("windowIn", {
    type = "bezier",
    points = {
        { 0.1, 1.0 },
        { 0.1, 1.0 },
    },
})

hl.curve("windowOut", {
    type = "bezier",
    points = {
        { 0.3, 0.0 },
        { 0.0, 1.0 },
    },
})

hl.animation({
    leaf = "windows",
    enabled = true,
    speed = 6,
    bezier = "workstation",
    style = "slide",
})

hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 6,
    bezier = "windowIn",
    style = "slide",
})

hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 5,
    bezier = "windowOut",
    style = "slide",
})

hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 5,
    bezier = "workstation",
    style = "slide",
})

hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 8,
    bezier = "default",
})

hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 5,
    bezier = "workstation",
})

return true
