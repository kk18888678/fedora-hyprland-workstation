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
    // Qt's font engine expects a single real family name. Theme.fontFamily is a
    // comma-separated preference list ("A, B, monospace"); passing it verbatim
    // makes Qt fail to resolve the family and renders semantic Nerd Font glyphs
    // as garbled fallback boxes. Use the theme's single shared resolution so the
    // glyph path and every text path agree by construction.
    property string glyphFontFamily: Theme.fontFamilyResolved
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
        if (n === "view-refresh") return "󰑐"
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
    // `hasSource` is the raw intent to draw something: a glyph, a source path,
    // or a theme name. It stays true even when the image later fails to decode,
    // so it must not be used to reserve screen space.
    readonly property bool hasSource: root.sourcePath !== "" || root.name !== "" || root.usingGlyph
    // A caller-provided theme name is drawable only when the icon theme really
    // provides it. Quickshell's image provider hands back a decodeable
    // placeholder for an unknown name (so Image.status cannot be trusted on
    // that path), so the primitive asks the host once. This is an availability
    // probe for the single name the caller supplied, not candidate ordering or
    // fallback policy: choosing among candidates stays the shared resolver's job.
    readonly property bool nameUsable: root.name !== "" && !root.usingGlyph
        && Quickshell.hasThemeIcon(root.name) === true
    // Rendering outcome, not resolution: a glyph is always drawable because Qt
    // lays it out directly, while an image is drawable only once Qt has decoded
    // it to Image.Ready and there is a real source behind it. A missing file,
    // an empty source, or a theme name the icon theme does not provide
    // therefore reports `iconReady === false`.
    readonly property bool iconReady: root.usingGlyph
        || ((root.sourcePath !== "" || root.nameUsable) && iconSource.status === Image.Ready)
    // The property callers use to collapse an icon slot. It is true only when
    // there is something to draw; no source means no space reserved, and a
    // failed decode collapses the slot instead of painting Qt's built-in
    // missing-image placeholder.
    readonly property bool hasIcon: root.hasSource && root.iconReady

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
        // Never visible until the artwork is actually decoded. When it is not
        // ready (missing file, empty source, unresolvable theme name) nothing
        // is drawn, so Qt cannot paint its missing-image placeholder.
        visible: !root.usingGlyph && root.preserveColors && root.iconReady
        layer.enabled: !root.usingGlyph && !root.preserveColors
        source: root.usingGlyph ? "" : (root.sourcePath !== ""
            ? root.sourcePath
            : (root.nameUsable ? Quickshell.iconPath(root.name, root.fallbackName) : ""))
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
        visible: !root.usingGlyph && root.iconReady && !root.preserveColors
        colorization: 1.0
        colorizationColor: root.tint
    }
}
