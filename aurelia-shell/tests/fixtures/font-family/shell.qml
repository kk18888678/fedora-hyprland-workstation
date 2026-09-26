import QtQuick
import Quickshell
import Quickshell.Io

// Isolated offscreen fixture for the theme-wide font-family resolution.
//
// It renders the REAL bar clock widget (a representative bar text path) and the
// REAL shared AureliaIcon glyph primitive (the icon path). Absolute sources are
// supplied by the caller because Quickshell resolves fixture-relative URLs
// through its blackhole path. It reports, at runtime:
//   - the icon primitive's family property (the theme's single resolved
//     family after the fix; the raw first list entry before it);
//   - what Qt's engine actually used for the bar text (`Text.fontInfo.family`);
//   - what Qt's engine actually used for the icon glyph (`Text.fontInfo.family`).
//
// The sibling test asserts the text and icon resolve to the SAME family so the
// two paths can never silently diverge again. The fixture is parameterized by
// the normal `AURELIA_THEME_CONF` override, so the same shell can exercise the
// shipped list, a single-family theme, and a list whose preferred entry is
// missing.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_FONT_FAMILY_RESULT") || ""
    readonly property string clockSource: Quickshell.env("AURELIA_FONT_FAMILY_CLOCK_SOURCE") || ""
    readonly property string iconSource: Quickshell.env("AURELIA_FONT_FAMILY_ICON_SOURCE") || ""
    property bool finished: false

    QtObject {
        id: fakeBar
        property bool vertical: false
        property bool barVisible: true
        property int barSize: 26
        property int barTextSize: 12
        property real barTextMargin: 8
        property int barIconSlot: 27
        property int barIconFont: 13
        property color barForeground: "#ffffff"
    }

    // A real bar widget text path.
    Loader {
        id: clockLoader
        source: root.clockSource
        onLoaded: clockLoader.item.bar = fakeBar
    }

    // The real shared glyph primitive the bar uses.
    Loader {
        id: iconLoader
        source: root.iconSource
        onLoaded: {
            iconLoader.item.width = 16
            iconLoader.item.height = 16
            iconLoader.item.iconSize = 16
            iconLoader.item.name = "notifications"
        }
    }

    function findChildText(item) {
        if (!item) return null
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (child && child.text !== undefined && child.renderType !== undefined) return child
        }
        return null
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        var clock = clockLoader.item
        var icon = iconLoader.item
        var clockText = findChildText(clock)
        var iconText = findChildText(icon)
        if (!clock || !icon || !clockText || !iconText) {
            root.finished = true
            resultFile.setText(JSON.stringify({loaded: false}) + "\n")
            return
        }
        root.finished = true
        resultFile.setText(JSON.stringify({
            loaded: true,
            iconGlyphFamilyProperty: icon.glyphFontFamily,
            textResolvedFamily: clockText.fontInfo.family,
            iconResolvedFamily: iconText.fontInfo.family
        }) + "\n")
    }

    // The theme override probe is asynchronous. Wait for it to settle before
    // sampling, so the measured family is never a pre-load default.
    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: root.writeResult()
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
