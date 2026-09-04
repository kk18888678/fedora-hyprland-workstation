pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: themeRoot

    // Aurelia Design System Foundation
    // Self-contained design token system for Aurelia desktop shell components.
    // Invariant: Completely independent of external desktop environments (Noctalia).
    // Defaults to Rosé Pine Moon palette natively, with optional user configuration adapter.

    // 1. Optional Theme Configuration File (Aurelia native or external adapter)
    property string themePath: {
        var envPath = Quickshell.env("AURELIA_THEME_CONF") || ""
        if (envPath !== "") return envPath
        var home = Quickshell.env("HOME") || ""
        if (home === "") return ""
        // Native Aurelia design system theme configuration
        return home + "/.config/aurelia/theme.conf"
    }

    property FileView themeFile: FileView {
        path: themeRoot.themePath
    }

    readonly property var loadedOverrides: {
        var map = {}
        var txt = ""
        try {
            txt = themeFile.text()
        } catch (e) {
            // Native internal Rosé Pine Moon defaults apply
        }
        if (txt && typeof txt === "string") {
            var lines = txt.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (!line || line.startsWith("#")) continue
                var parts = line.split(/[=\s]+/)
                if (parts.length >= 2) {
                    map[parts[0]] = parts[1]
                }
            }
        }
        return map
    }

    // 2. Canonical Rosé Pine Moon Base Palette (Authored directly in Aurelia)
    readonly property color _base: "#232136"
    readonly property color _surface: "#2a273f"
    readonly property color _overlay: "#393552"
    readonly property color _muted: "#6e6a86"
    readonly property color _subtle: "#908caa"
    readonly property color _text: "#e0def4"
    readonly property color _love: "#eb6f92"
    readonly property color _gold: "#f6c177"
    readonly property color _rose: "#ea9a97"
    readonly property color _pine: "#3e8fb0"
    readonly property color _foam: "#9ccfd8"
    readonly property color _iris: "#c4a7e7"
    readonly property color _highlightLow: "#2a283e"
    readonly property color _highlightMed: "#44415a"
    readonly property color _highlightHigh: "#56526e"

    // 3. Semantic Color Tokens
    readonly property color background: loadedOverrides["background"] || _base
    readonly property color bgBase: background
    readonly property color surface: loadedOverrides["surface"] || _surface
    readonly property color surfaceElevated: loadedOverrides["surfaceElevated"] || _overlay
    readonly property color selection: loadedOverrides["selection"] || _overlay
    readonly property color selectionActive: loadedOverrides["selectionActive"] || _highlightMed
    readonly property color border: loadedOverrides["border"] || "#424659"
    readonly property color borderActive: loadedOverrides["borderActive"] || loadedOverrides["active_border_color"] || _foam
    readonly property color text: loadedOverrides["text"] || loadedOverrides["foreground"] || _text
    readonly property color textSecondary: loadedOverrides["textSecondary"] || _subtle
    readonly property color textMuted: loadedOverrides["textMuted"] || loadedOverrides["color8"] || _subtle
    readonly property color textSubtle: loadedOverrides["textSubtle"] || loadedOverrides["color0"] || _muted
    readonly property color accent: loadedOverrides["accent"] || loadedOverrides["color4"] || _foam
    readonly property color accentAlt: loadedOverrides["accentAlt"] || loadedOverrides["color13"] || _iris
    readonly property color gold: loadedOverrides["gold"] || loadedOverrides["color3"] || _gold
    readonly property color love: loadedOverrides["love"] || loadedOverrides["color1"] || _love
    readonly property color pine: loadedOverrides["pine"] || loadedOverrides["color6"] || _pine
    readonly property color foam: loadedOverrides["foam"] || loadedOverrides["color4"] || _foam
    readonly property color rose: loadedOverrides["rose"] || loadedOverrides["color5"] || _rose
    readonly property color iris: loadedOverrides["iris"] || loadedOverrides["color13"] || _iris
    readonly property color success: loadedOverrides["success"] || _foam
    readonly property color warning: loadedOverrides["warning"] || _gold
    readonly property color error: loadedOverrides["error"] || _love

    // 4. Semantic Typography Tokens
    readonly property string fontFamily: "Hack Nerd Font, monospace"
    readonly property string fontFamilyProse: "sans-serif"
    readonly property int fontSizeXs: 10
    readonly property int fontSizeSm: 12
    readonly property int fontSizeMd: 13
    readonly property int fontSizeLg: 15
    readonly property int fontSizeXl: 18
    readonly property int fontWeightNormal: Font.Normal
    readonly property int fontWeightMedium: Font.Medium
    readonly property int fontWeightBold: Font.Bold

    // 5. Semantic Spacing Scale Tokens
    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 12
    readonly property int spacingLg: 16
    readonly property int spacingXl: 20
    readonly property int spacingXxl: 24

    // 6. Semantic Geometry Tokens
    readonly property int radiusSm: 4
    readonly property int radiusMd: 8
    readonly property int radiusLg: 12
    readonly property int borderWidthDefault: 1
    readonly property int borderWidthFocus: 2

    // Restrained Command Palette Layout Proportions
    readonly property int paletteWidth: 800
    readonly property int paletteHeight: 480
    readonly property int rowHeight: 38
    readonly property int searchHeight: 40
    readonly property int footerHeight: 34
    readonly property int colShortcutWidth: 280
    readonly property int colSeparatorWidth: 28

    // 7. Semantic Motion Tokens
    readonly property int durationFast: 100
    readonly property int durationNormal: 200
}
