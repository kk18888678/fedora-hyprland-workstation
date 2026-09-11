# Aurelia themes

This directory contains the 22 stock Omarchy themes from the inspected
reference snapshot (`b5589faaf80c6f87c07d4560fca37c4a81722f28`):

    catppuccin       catppuccin-latte  ethereal       everforest
    flexoki-light    gruvbox           hackerman      kanagawa
    last-horizon     lumon             lupine         matte-black
    miasma           nord              osaka-jade     retro-82
    ristretto        rose-pine         solitude       tokyo-night
    vantablack       white

Each stock directory is copied from the reference without changing its
`colors.toml`, `icons.theme`, previews, unlock artwork, backgrounds, or other
inert theme metadata. `colors.toml` is the canonical palette input; the
resolver is byte-compatible with the reference palette alias and mix rules.

Theme selection remains deliberately data-only in Aurelia. It consumes the
palette and supported media, while Lua, terminal launch configuration, shell
hooks, and editor-extension descriptors remain inert files and are never
executed or installed by Aurelia.

## Theme commands

    aurelia-theme list
    aurelia-theme current
    aurelia-theme set "Tokyo Night"
    aurelia-theme catalog --json
    aurelia-theme-preview themes
    aurelia-theme-preview backgrounds
    aurelia-theme-bg list --json
    aurelia-theme-bg next
    aurelia-theme-bg set ~/Pictures/Wallpapers/example.png
    aurelia-theme-color --all

Theme selection resolves a user directory over the matching stock directory,
preserves the selected background by filename when possible, otherwise chooses
the first sorted supported media path, generates surface tokens, and reloads
the resident Aurelia shell through one apply boundary. The image-picker uses
the generated preview cache for theme links and media thumbnails.
The active palette, theme name, and background path are stored under
`${XDG_STATE_HOME:-~/.local/state}/aurelia/current/`. User themes belong under
`~/.config/aurelia/themes/<theme-name>/`; additional backgrounds belong under
`~/.config/aurelia/backgrounds/<theme-name>/`.

When the Aurelia Hyprland provider is enabled, the selector shortcuts are:

    Super + Ctrl + Space          Background Picker
    Super + Shift + Ctrl + Space  Theme Picker

The reference's Plymouth unlock integration, Omarchy shell templates, and
Arch-specific application retint commands are not silently mapped to Fedora;
the corresponding stock files are retained for source fidelity but remain
outside Aurelia's mutation boundary.
