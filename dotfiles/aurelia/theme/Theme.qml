pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: themeRoot

    // Dynamic system theme observation from Noctalia's generated configuration
    property FileView themeFile: FileView {
        path: (Quickshell.env("HOME") || "") + "/.config/kitty/themes/noctalia.conf"
    }

    readonly property var colors: {
        var map = {}
        var txt = ""
        try {
            txt = themeFile.text()
        } catch (e) {}
        if (txt) {
            var lines = txt.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (!line || line.startsWith("#")) continue
                var parts = line.split(/\s+/)
                if (parts.length >= 2) {
                    map[parts[0]] = parts[1]
                }
            }
        }
        return map
    }

    // Active theme colors dynamically derived from system palette with Rosé Pine Moon fallback
    readonly property color background: colors["background"] || "#232136"
    readonly property color surface: colors["selection_background"] || "#2a273f"
    readonly property color overlay: colors["selection_background"] || "#393552"
    readonly property color highlight: colors["selection_background"] || "#44415a"
    readonly property color border: colors["inactive_border_color"] || "#44415a"
    readonly property color borderActive: colors["active_border_color"] || "#9ccfd8"
    readonly property color text: colors["foreground"] || "#e0def4"
    readonly property color textMuted: colors["color8"] || "#908caa"
    readonly property color textSubtle: colors["color0"] || "#6e6a86"
    readonly property color accent: colors["color4"] || colors["active_border_color"] || "#9ccfd8"
    readonly property color accentAlt: colors["color2"] || colors["color12"] || "#c4a7e7"
    readonly property color gold: colors["color3"] || "#f6c177"
    readonly property color love: colors["color1"] || "#eb6f92"
    readonly property color pine: colors["color6"] || "#3e8fb0"
    readonly property color selection: colors["selection_background"] || "#393552"
    readonly property color selectionActive: colors["color0"] || "#44415a"

    // Spacing scale
    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 12
    readonly property int spacingLg: 16
    readonly property int spacingXl: 24

    // Corner radii
    readonly property int radiusSm: 6
    readonly property int radiusMd: 10
    readonly property int radiusLg: 14

    // Typography
    readonly property string fontFamily: "Hack Nerd Font, monospace"
    readonly property string fontFamilyProse: "sans-serif"
    readonly property int fontSizeXs: 10
    readonly property int fontSizeSm: 12
    readonly property int fontSizeMd: 13
    readonly property int fontSizeLg: 15
    readonly property int fontSizeXl: 18
}
