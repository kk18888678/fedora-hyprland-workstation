-- Hyprland window rules.
--
-- Keep this file focused on generic workstation behaviour.
-- Application-specific rules can be added when those applications
-- become part of the workstation manifest.

-- Audio control

hl.window_rule({
    match = {
        class = "^org\\.pulseaudio\\.pavucontrol$",
    },
    float = true,
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

-- Workstation hotkeys cheatsheet window
hl.window_rule({
    match = {
        class = "^(workstation-hotkeys)$",
    },
    float = true,
    center = true,
    size = "760 560",
})

-- Aurelia Keybindings Layer Surface:
-- Deterministic derivation from Aurelia effective preferences.
-- When motion is disabled for Keybindings, Hyprland suppresses layer-shell animations (no_anim = true).
local aurelia_pref_path = os.getenv("AURELIA_PREFERENCES_PATH")
if not aurelia_pref_path or aurelia_pref_path == "" then
    local xdg_config = os.getenv("XDG_CONFIG_HOME")
    if not xdg_config or xdg_config == "" then
        xdg_config = (os.getenv("HOME") or "") .. "/.config"
    end
    aurelia_pref_path = xdg_config .. "/aurelia/preferences.json"
end

local aurelia_motion_disabled = false
local pf = io.open(aurelia_pref_path, "r")
if pf then
    local pcontent = pf:read("*a")
    pf:close()
    if pcontent then
        if pcontent:find('"components.keybindings.motion.enabled"%s*:%s*false') or
           pcontent:find('"aurelia.motion.enabled"%s*:%s*false') or
           pcontent:find('"motion"%s*:%s*{[^}]*"enabled"%s*:%s*false') then
            aurelia_motion_disabled = true
        end
    end
end

if aurelia_motion_disabled and hl and type(hl.layer_rule) == "function" then
    hl.layer_rule({
        match = {
            namespace = "^(aurelia-keybindings)$",
        },
        no_anim = true,
    })
end

return true
