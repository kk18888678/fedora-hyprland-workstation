pragma Singleton
import QtQuick

QtObject {
    // Rosé Pine Moon Color Palette
    readonly property color background: "#232136"
    readonly property color surface: "#2a273f"
    readonly property color overlay: "#393552"
    readonly property color highlight: "#44415a"
    readonly property color border: "#44415a"
    readonly property color borderActive: "#9ccfd8"
    readonly property color text: "#e0def4"
    readonly property color textMuted: "#908caa"
    readonly property color textSubtle: "#6e6a86"
    readonly property color accent: "#9ccfd8"       // Foam (Cyan)
    readonly property color accentAlt: "#c4a7e7"    // Iris (Purple)
    readonly property color gold: "#f6c177"         // Gold (Yellow)
    readonly property color love: "#eb6f92"         // Love (Red/Rose)
    readonly property color pine: "#3e8fb0"         // Pine (Teal)
    readonly property color selection: "#393552"
    readonly property color selectionActive: "#44415a"

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
