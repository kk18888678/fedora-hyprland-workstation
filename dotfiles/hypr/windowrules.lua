-- Hyprland window rules.
--
-- Keep this file focused on generic workstation behaviour plus small,
-- manifest-backed rules for applications that need compositor integration.

-- Audio control

-- Aurelia Updates, Package Manager, and About follow Omarchy's dedicated terminal surfaces:
-- centered floating windows whose terminal content owns the presentation.
hl.window_rule({
    match = {
        class = "^org\\.aurelia\\.updates$",
    },
    float = true,
    center = true,
    size = "1100 720",
})

hl.window_rule({
    match = {
        class = "^org\\.aurelia\\.packages$",
    },
    float = true,
    center = true,
    size = "1100 720",
})

hl.window_rule({
    match = {
        class = "^org\\.aurelia\\.about$",
    },
    float = true,
    center = true,
    -- workstation-about owns the terminal's measured cell geometry. Avoid a
    -- competing pixel-size rule here: Kitty/Foot open at the compact 130x32
    -- cell envelope and the renderer refines it after the terminal maps.
})

hl.window_rule({
    match = {
        class = "^org\\.pulseaudio\\.pavucontrol$",
    },
    float = true,
})

-- Electron's native ChatGPT quit confirmation is a separate XWayland
-- toplevel. It uses a different class from the main window (`ChatGPT` vs
-- `Chatgpt`) and can otherwise be mapped at the monitor's top-left corner.
-- Match both identity fields so the main ChatGPT window keeps its normal
-- layout and only this confirmation is centered.
hl.window_rule({
    match = {
        class = "^ChatGPT$",
        title = "^Quit ChatGPT[?]$",
    },
    float = true,
    center = true,
})

-- Prevent the display from sleeping while fullscreen media is playing.

hl.window_rule({
    match = {
        class = "^(.*mpv.*|.*vlc.*)$",
    },
    idle_inhibit = "fullscreen",
})

-- Prevent idle while supported browsers are fullscreen.

hl.window_rule({
    match = {
        class = "^(.*chromium.*|.*firefox.*|.*brave.*|.*ulaa.*)$",
    },
    idle_inhibit = "fullscreen",
})

-- Picture-in-picture windows.

hl.window_rule({
    match = {
        title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture).*$",
    },
    tag = "picture-in-picture",
})

hl.window_rule({
    match = {
        tag = "picture-in-picture",
    },
    float = true,
    pin = true,
    keep_aspect_ratio = true,
    move = "73% 72%",
    size = "25% 25%",
})

-- Some JetBrains IDE helper windows should not steal initial focus.

hl.window_rule({
    match = {
        class = "^.*jetbrains.*$",
        title = "^win[0-9]+$",
    },
    no_initial_focus = true,
})

return true
