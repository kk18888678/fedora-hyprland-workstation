-- Hyprland keyboard and mouse bindings.

local mainMod = "SUPER"

local TERMINAL = "kitty"
local EXPLORER = "thunar"

local KEY = {
    TERMINAL = ("%s + RETURN"):format(mainMod),
    EXPLORER = ("%s + E"):format(mainMod),

    LAUNCHER = ("%s + D"):format(mainMod),
    LOCK = ("%s + L"):format(mainMod),
    SETTINGS = ("%s + T"):format(mainMod),

    CLOSE = ("%s + Q"):format(mainMod),
    FLOAT = ("%s + W"):format(mainMod),
    FULLSCREEN = ("%s + F"):format(mainMod),

    FOCUS_LEFT = ("%s + left"):format(mainMod),
    FOCUS_RIGHT = ("%s + right"):format(mainMod),
    FOCUS_UP = ("%s + up"):format(mainMod),
    FOCUS_DOWN = ("%s + down"):format(mainMod),

    RESIZE_RIGHT = ("%s + SHIFT + right"):format(mainMod),
    RESIZE_LEFT = ("%s + SHIFT + left"):format(mainMod),
    RESIZE_UP = ("%s + SHIFT + up"):format(mainMod),
    RESIZE_DOWN = ("%s + SHIFT + down"):format(mainMod),

    WORKSPACE_NEXT = ("%s + CTRL + right"):format(mainMod),
    WORKSPACE_PREV = ("%s + CTRL + left"):format(mainMod),

    MOUSE_DRAG = ("%s + mouse:272"):format(mainMod),
    MOUSE_RESIZE = ("%s + mouse:273"):format(mainMod),
}

-- Applications

hl.bind(
    KEY.TERMINAL,
    hl.dsp.exec_cmd(TERMINAL),
    { description = "Terminal" }
)

hl.bind(
    KEY.EXPLORER,
    hl.dsp.exec_cmd(EXPLORER),
    { description = "File manager" }
)

-- Noctalia

hl.bind(
    KEY.LAUNCHER,
    hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"),
    { description = "Application launcher" }
)

hl.bind(
    KEY.LOCK,
    hl.dsp.exec_cmd("noctalia msg screen-lock"),
    { description = "Lock screen" }
)

hl.bind(
    KEY.SETTINGS,
    hl.dsp.exec_cmd("noctalia msg settings-toggle"),
    { description = "Desktop settings" }
)

-- Window management

hl.bind(
    KEY.CLOSE,
    hl.dsp.window.close(),
    { description = "Close window" }
)

hl.bind(
    KEY.FLOAT,
    hl.dsp.window.float({ action = "toggle" }),
    { description = "Toggle floating" }
)

hl.bind(
    KEY.FULLSCREEN,
    hl.dsp.window.fullscreen(),
    { description = "Toggle fullscreen" }
)

-- Window focus

hl.bind(
    KEY.FOCUS_LEFT,
    hl.dsp.focus({ direction = "left" }),
    { description = "Focus left" }
)

hl.bind(
    KEY.FOCUS_RIGHT,
    hl.dsp.focus({ direction = "right" }),
    { description = "Focus right" }
)

hl.bind(
    KEY.FOCUS_UP,
    hl.dsp.focus({ direction = "up" }),
    { description = "Focus up" }
)

hl.bind(
    KEY.FOCUS_DOWN,
    hl.dsp.focus({ direction = "down" }),
    { description = "Focus down" }
)

hl.bind(
    "ALT + tab",
    hl.dsp.window.cycle_next(),
    { description = "Cycle windows" }
)

-- Window resizing

hl.bind(
    KEY.RESIZE_RIGHT,
    function()
        hl.exec_cmd("hyprctl dispatch resizeactive 30 0")
    end,
    { description = "Resize right" }
)

hl.bind(
    KEY.RESIZE_LEFT,
    function()
        hl.exec_cmd("hyprctl dispatch resizeactive -30 0")
    end,
    { description = "Resize left" }
)

hl.bind(
    KEY.RESIZE_UP,
    function()
        hl.exec_cmd("hyprctl dispatch resizeactive 0 -30")
    end,
    { description = "Resize up" }
)

hl.bind(
    KEY.RESIZE_DOWN,
    function()
        hl.exec_cmd("hyprctl dispatch resizeactive 0 30")
    end,
    { description = "Resize down" }
)

-- Workspaces 1-10

for i = 1, 9 do
    local focusKey = ("%s + %d"):format(mainMod, i)
    local moveKey = ("%s + SHIFT + %d"):format(mainMod, i)

    hl.bind(
        focusKey,
        hl.dsp.focus({ workspace = i }),
        { description = "Workspace " .. i }
    )

    hl.bind(
        moveKey,
        hl.dsp.window.move({ workspace = i }),
        { description = "Move to workspace " .. i }
    )
end

hl.bind(
    ("%s + 0"):format(mainMod),
    hl.dsp.focus({ workspace = 10 }),
    { description = "Workspace 10" }
)

hl.bind(
    ("%s + SHIFT + 0"):format(mainMod),
    hl.dsp.window.move({ workspace = 10 }),
    { description = "Move to workspace 10" }
)

-- Workspace navigation

hl.bind(
    KEY.WORKSPACE_NEXT,
    hl.dsp.focus({ workspace = "r+1" }),
    { description = "Next workspace" }
)

hl.bind(
    KEY.WORKSPACE_PREV,
    hl.dsp.focus({ workspace = "r-1" }),
    { description = "Previous workspace" }
)

-- Mouse window management

hl.bind(
    KEY.MOUSE_DRAG,
    hl.dsp.window.drag(),
    {
        mouse = true,
        description = "Drag window",
    }
)

hl.bind(
    KEY.MOUSE_RESIZE,
    hl.dsp.window.resize(),
    {
        mouse = true,
        description = "Resize window",
    }
)

-- Media controls

hl.bind(
    "XF86AudioPlay",
    hl.dsp.exec_cmd("playerctl play-pause"),
    {
        locked = true,
        description = "Play or pause",
    }
)

hl.bind(
    "XF86AudioNext",
    hl.dsp.exec_cmd("playerctl next"),
    {
        locked = true,
        description = "Next track",
    }
)

hl.bind(
    "XF86AudioPrev",
    hl.dsp.exec_cmd("playerctl previous"),
    {
        locked = true,
        description = "Previous track",
    }
)

hl.bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),
    {
        locked = true,
        description = "Volume up",
    }
)

hl.bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
    {
        locked = true,
        description = "Volume down",
    }
)

hl.bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    {
        locked = true,
        description = "Toggle mute",
    }
)

return true
