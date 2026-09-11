import QtQuick
import QtQuick.Effects
import Quickshell
import "../theme"

// Theme-aware icon primitive. Semantic shell icons use the same native-rendered
// Nerd Font glyph path as Omarchy's OpticalGlyph; application/tray artwork
// remains an image and is decoded at physical pixels before any recoloring.
Item {
    id: root

    property string name: "application-x-executable"
    property string sourcePath: ""
    property string fallbackName: "application-x-executable"
    property color tint: Theme.text
    property real iconSize: 18
    property bool preserveColors: false
    property real sourcePixelRatio: Math.max(1, Screen.devicePixelRatio)
    property bool smooth: true
    property string glyph: ""
    property string glyphFontFamily: Theme.fontFamily
    property real glyphPixelSize: 0
    property bool glyphOpticallyCenter: true

    function glyphForName(value) {
        var n = String(value || "")
        if (n === "network-wireless") return "󰤨"
        if (n === "network-wired") return "󰈀"
        if (n === "network-offline") return "󰤮"
        if (n === "network-limited") return "󰤩"
        if (n === "ethernet-limited") return "󰈂"
        if (n === "bluetooth" || n === "bluetooth-disabled") return n === "bluetooth-disabled" ? "󰂲" : "󰂯"
        if (n === "bluetooth-active") return "󰂱"
        if (n === "video-display" || n === "computer") return "󰍹"
        if (n === "monitors") return "󰍺"
        if (n === "notifications") return "󰂚"
        if (n === "notifications-disabled") return "󰂛"
        if (n === "camera" || n === "camera-photo") return "󰄀"
        if (n === "system-shutdown" || n === "system-power-off" || n === "poweroff") return "󰐥"
        if (n === "window-close") return "󰅖"
        if (n === "weather-clear" || n === "weather-clear-wind") return ""
        if (n === "weather-clear-wind-night") return ""
        if (n === "weather-few-clouds-wind") return ""
        if (n === "weather-few-clouds-wind-night") return ""
        if (n === "weather-clouds") return ""
        if (n === "weather-mist") return "\ue313"
        if (n === "weather-showers-day") return ""
        if (n === "weather-showers-night") return ""
        if (n === "weather-snow-day") return ""
        if (n === "weather-snow-night") return ""
        if (n === "weather-storm-day" || n === "weather-storm-night") return ""
        return ""
    }

    readonly property string resolvedGlyph: root.glyph !== "" ? root.glyph : root.glyphForName(root.name)
    readonly property bool usingGlyph: root.resolvedGlyph !== ""
    readonly property real resolvedGlyphPixelSize: root.glyphPixelSize > 0
        ? root.glyphPixelSize
        : Math.max(1, Math.round(root.iconSize * 0.9))
    readonly property bool hasSource: root.sourcePath !== "" || root.name !== "" || root.usingGlyph

    implicitWidth: iconSize
    implicitHeight: iconSize

    TextMetrics {
        id: glyphMetrics
        font.family: root.glyphFontFamily
        font.pixelSize: root.resolvedGlyphPixelSize
        text: root.resolvedGlyph
    }

    Text {
        id: glyphText
        visible: root.usingGlyph
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.glyphOpticallyCenter
            ? glyphText.implicitWidth / 2 - (glyphMetrics.tightBoundingRect.x + glyphMetrics.tightBoundingRect.width / 2)
            : 0
        textFormat: Text.PlainText
        text: root.resolvedGlyph
        color: root.tint
        font.family: root.glyphFontFamily
        font.pixelSize: root.resolvedGlyphPixelSize
        renderType: Text.NativeRendering
    }

    Image {
        id: iconSource
        anchors.fill: parent
        visible: !root.usingGlyph && root.preserveColors
        layer.enabled: !root.usingGlyph && !root.preserveColors
        source: root.usingGlyph ? "" : (root.sourcePath !== ""
            ? root.sourcePath
            : (root.name !== "" ? Quickshell.iconPath(root.name, root.fallbackName) : ""))
        sourceSize: Qt.size(
            Math.max(1, Math.round(root.width * root.sourcePixelRatio)),
            Math.max(1, Math.round(root.height * root.sourcePixelRatio)))
        fillMode: Image.PreserveAspectFit
        // These are small, theme-resolved UI icons. Synchronous loading keeps
        // MultiEffect on the GUI thread and avoids Qt pixmap-reader thread
        // warnings while the resident bar is constructed.
        asynchronous: false
        smooth: root.smooth
    }

    MultiEffect {
        anchors.fill: iconSource
        source: iconSource
        visible: !root.usingGlyph && root.hasSource && !root.preserveColors
        colorization: 1.0
        colorizationColor: root.tint
    }
}
