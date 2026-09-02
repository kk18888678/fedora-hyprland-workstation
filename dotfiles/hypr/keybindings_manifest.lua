-- Single source of truth for all workstation keybindings and shortcuts.
-- Both Hyprland session registration (keybind.lua) and user-facing Hotkeys help
-- (workstation-hotkeys) are dynamically derived from this manifest.

local M = {}

M.mainMod = "SUPER"
M.terminal = "kitty"
M.explorer = "thunar"

M.categories = {
    "Applications & Launchers",
    "Window Management",
    "Window Focus & Resizing",
    "Workspaces",
    "Mouse Controls",
    "Audio & Media Controls",
}

M.bindings = {
    -- Applications & Launchers
    {
        category = "Applications & Launchers",
        key = "SUPER + RETURN",
        action_type = "exec",
        command = M.terminal,
        desktop_id = "kitty.desktop",
        display_key = "SUPER + RETURN",
        description = "Open Terminal (" .. M.terminal .. ")",
    },
    {
        category = "Applications & Launchers",
        key = "SUPER + E",
        action_type = "exec",
        command = M.explorer,
        desktop_id = "thunar.desktop",
        display_key = "SUPER + E",
        description = "Open File Manager (" .. M.explorer .. ")",
    },
    {
        category = "Applications & Launchers",
        key = "SUPER + D",
        action_type = "exec",
        command = "noctalia msg panel-toggle launcher",
        desktop_id = "dev.noctalia.Noctalia.desktop",
        display_key = "SUPER + D",
        description = "Open Application Launcher",
    },
    {
        category = "Applications & Launchers",
        key = "SUPER + K",
        action_type = "exec",
        command = "workstation-hotkeys",
        desktop_id = "workstation-hotkeys.desktop",
        display_key = "SUPER + K",
        description = "Open this Hotkeys Reference",
    },
    {
        category = "Applications & Launchers",
        key = "SUPER + T",
        action_type = "exec",
        command = "noctalia msg settings-toggle",
        desktop_id = "dev.noctalia.Noctalia.desktop",
        display_key = "SUPER + T",
        description = "Open Desktop Settings",
    },
    {
        category = "Applications & Launchers",
        key = "SUPER + L",
        action_type = "exec",
        command = "noctalia msg screen-lock",
        display_key = "SUPER + L",
        description = "Lock Screen",
    },

    -- Window Management
    {
        category = "Window Management",
        key = "SUPER + Q",
        action_type = "dispatch_close",
        display_key = "SUPER + Q",
        description = "Close Active Window",
    },
    {
        category = "Window Management",
        key = "SUPER + W",
        action_type = "dispatch_float",
        display_key = "SUPER + W",
        description = "Toggle Floating Window",
    },
    {
        category = "Window Management",
        key = "SUPER + F",
        action_type = "dispatch_fullscreen",
        display_key = "SUPER + F",
        description = "Toggle Fullscreen Window",
    },
    {
        category = "Window Management",
        key = "ALT + tab",
        action_type = "dispatch_cycle",
        display_key = "ALT + Tab",
        description = "Cycle Window Focus",
    },

    -- Window Focus & Resizing
    {
        category = "Window Focus & Resizing",
        key = "SUPER + left",
        action_type = "focus",
        direction = "left",
        display_key = "SUPER + Left",
        description = "Focus Left Window",
    },
    {
        category = "Window Focus & Resizing",
        key = "SUPER + right",
        action_type = "focus",
        direction = "right",
        display_key = "SUPER + Right",
        description = "Focus Right Window",
    },
    {
        category = "Window Focus & Resizing",
        key = "SUPER + up",
        action_type = "focus",
        direction = "up",
        display_key = "SUPER + Up",
        description = "Focus Up Window",
    },
    {
        category = "Window Focus & Resizing",
        key = "SUPER + down",
        action_type = "focus",
        direction = "down",
        display_key = "SUPER + Down",
        description = "Focus Down Window",
    },
    {
        category = "Window Focus & Resizing",
        key = "SUPER + SHIFT + left",
        action_type = "exec_resize",
        resize_args = "-30 0",
        display_key = "SUPER + SHIFT + Left",
        description = "Resize Active Window Left (-30px)",
    },
    {
        category = "Window Focus & Resizing",
        key = "SUPER + SHIFT + right",
        action_type = "exec_resize",
        resize_args = "30 0",
        display_key = "SUPER + SHIFT + Right",
        description = "Resize Active Window Right (+30px)",
    },
    {
        category = "Window Focus & Resizing",
        key = "SUPER + SHIFT + up",
        action_type = "exec_resize",
        resize_args = "0 -30",
        display_key = "SUPER + SHIFT + Up",
        description = "Resize Active Window Up (-30px)",
    },
    {
        category = "Window Focus & Resizing",
        key = "SUPER + SHIFT + down",
        action_type = "exec_resize",
        resize_args = "0 30",
        display_key = "SUPER + SHIFT + Down",
        description = "Resize Active Window Down (+30px)",
    },

    -- Workspaces
    {
        category = "Workspaces",
        generator = "workspaces_1_10",
        display_key = "SUPER + 1 .. 9, 0",
        description = "Switch to Workspace 1–10",
    },
    {
        category = "Workspaces",
        generator = "workspaces_move_1_10",
        display_key = "SUPER + SHIFT + 1 .. 9, 0",
        description = "Move Window to Workspace 1–10",
    },
    {
        category = "Workspaces",
        key = "SUPER + CTRL + left",
        action_type = "focus_workspace_relative",
        workspace = "r-1",
        display_key = "SUPER + CTRL + Left",
        description = "Previous Workspace",
    },
    {
        category = "Workspaces",
        key = "SUPER + CTRL + right",
        action_type = "focus_workspace_relative",
        workspace = "r+1",
        display_key = "SUPER + CTRL + Right",
        description = "Next Workspace",
    },
    {
        category = "Workspaces",
        action_type = "gesture",
        display_key = "3-Finger Horizontal Swipe",
        description = "Switch Workspaces (Touchpad)",
    },

    -- Mouse Controls
    {
        category = "Mouse Controls",
        key = "SUPER + mouse:272",
        action_type = "mouse_drag",
        mouse = true,
        display_key = "SUPER + Left Mouse Drag",
        description = "Move Floating Window",
    },
    {
        category = "Mouse Controls",
        key = "SUPER + mouse:273",
        action_type = "mouse_resize",
        mouse = true,
        display_key = "SUPER + Right Mouse Drag",
        description = "Resize Floating Window",
    },

    -- Audio & Media Controls
    {
        category = "Audio & Media Controls",
        key = "XF86AudioPlay",
        action_type = "exec_locked",
        command = "playerctl play-pause",
        display_key = "Play / Pause Key",
        description = "Toggle Play / Pause (playerctl)",
    },
    {
        category = "Audio & Media Controls",
        key = "XF86AudioNext",
        action_type = "exec_locked",
        command = "playerctl next",
        display_key = "Next Track Key",
        description = "Next Track (playerctl)",
    },
    {
        category = "Audio & Media Controls",
        key = "XF86AudioPrev",
        action_type = "exec_locked",
        command = "playerctl previous",
        display_key = "Previous Track Key",
        description = "Previous Track (playerctl)",
    },
    {
        category = "Audio & Media Controls",
        key = "XF86AudioRaiseVolume",
        action_type = "exec_locked",
        command = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+",
        display_key = "Volume Up Key",
        description = "Adjust Volume Up 5% (wpctl)",
    },
    {
        category = "Audio & Media Controls",
        key = "XF86AudioLowerVolume",
        action_type = "exec_locked",
        command = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
        display_key = "Volume Down Key",
        description = "Adjust Volume Down 5% (wpctl)",
    },
    {
        category = "Audio & Media Controls",
        key = "XF86AudioMute",
        action_type = "exec_locked",
        command = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
        display_key = "Mute Key",
        description = "Toggle Audio Mute (wpctl)",
    },
}

return M
