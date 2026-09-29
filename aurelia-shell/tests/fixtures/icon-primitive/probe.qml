import QtQuick
import Quickshell
import Quickshell.Io

// Isolated probe body for the shared AureliaIcon rendering primitive.
//
// It instantiates the REAL primitive once per unavailable/available case and
// reports, for each, whether the primitive has drawable artwork and whether
// either render element (the Image and its MultiEffect) is visible. For an
// unavailable icon BOTH render elements must be invisible and the primitive
// must report `hasIcon === false`, so Qt can never paint its built-in
// missing-image placeholder. For a real theme icon and a real logo path the
// image must be visible and preserve its colours.
//
// Pixel grabbing is not available under the offscreen backend (`grabToImage`
// rejects an item that is not attached to a window), so the fixture asserts
// the render-path state that decides whether any pixels are drawn: the Image
// and MultiEffect visibility coupled to the primitive's own drawable outcome.
Item {
    id: probe

    readonly property string iconSource: Quickshell.env("AURELIA_ICON_PRIMITIVE_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_ICON_PRIMITIVE_RESULT") || ""
    readonly property string samplePng: Quickshell.env("AURELIA_ICON_PRIMITIVE_PNG") || ""
    readonly property string missingPng: Quickshell.env("AURELIA_ICON_PRIMITIVE_MISSING") || ""
    property bool finished: false

    function fileUrl(path) {
        return "file:" + "//" + path
    }

    function setUp(item, sourcePath, name, preserveColors) {
        item.width = 16
        item.height = 16
        item.iconSize = 16
        item.sourcePath = sourcePath
        item.name = name
        item.preserveColors = preserveColors
    }

    // A path that does not exist.
    Loader {
        id: missingPath
        source: probe.iconSource
        onLoaded: probe.setUp(item, probe.fileUrl(probe.missingPng), "", true)
    }

    // No source at all.
    Loader {
        id: emptySource
        source: probe.iconSource
        onLoaded: probe.setUp(item, "", "", true)
    }

    // A theme name that the icon theme does not provide.
    Loader {
        id: missingName
        source: probe.iconSource
        onLoaded: probe.setUp(item, "", "definitely-not-in-theme-xyz", true)
    }

    // A genuinely resolvable theme icon (supplied by the disposable XDG theme).
    Loader {
        id: validTheme
        source: probe.iconSource
        onLoaded: probe.setUp(item, "", "fixture-app", true)
    }

    // A real logo file path.
    Loader {
        id: logoPath
        source: probe.iconSource
        onLoaded: probe.setUp(item, probe.fileUrl(probe.samplePng), "", true)
    }

    // A symbolic mask: resolvable, tinted through the MultiEffect path.
    Loader {
        id: symbolicMask
        source: probe.iconSource
        onLoaded: probe.setUp(item, "", "fixture-app-symbolic", false)
    }

    function childImage(icon) {
        if (!icon) return null
        for (var i = 0; i < icon.children.length; i++) {
            var child = icon.children[i]
            if (child && child.fillMode !== undefined) return child
        }
        return null
    }

    function childEffect(icon) {
        if (!icon) return null
        for (var i = 0; i < icon.children.length; i++) {
            var child = icon.children[i]
            if (child && child.colorizationColor !== undefined) return child
        }
        return null
    }

    function snapshot(icon) {
        var image = probe.childImage(icon)
        var effect = probe.childEffect(icon)
        return {
            hasIcon: icon ? icon.hasIcon === true : false,
            iconReady: icon ? icon.iconReady === true : false,
            hasSource: icon ? icon.hasSource === true : false,
            nameUsable: icon ? icon.nameUsable === true : false,
            usingGlyph: icon ? icon.usingGlyph === true : false,
            preserveColors: icon ? icon.preserveColors === true : false,
            imageVisible: image ? image.visible === true : false,
            imageStatus: image ? image.status : -1,
            effectVisible: effect ? effect.visible === true : false
        }
    }

    FileView {
        id: resultFile
        path: probe.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
    }

    function writeResult() {
        if (probe.finished || probe.resultPath === "") return
        probe.finished = true
        resultFile.setText(JSON.stringify({
            readyStatus: Image.Ready,
            errorStatus: Image.Error,
            nullStatus: Image.Null,
            cases: {
                missingPath: probe.snapshot(missingPath.item),
                emptySource: probe.snapshot(emptySource.item),
                missingName: probe.snapshot(missingName.item),
                validTheme: probe.snapshot(validTheme.item),
                logoPath: probe.snapshot(logoPath.item),
                symbolicMask: probe.snapshot(symbolicMask.item)
            }
        }) + "\n")
    }

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: probe.writeResult()
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: { if (!probe.finished) probe.writeResult() }
    }

    Connections {
        target: resultFile
        function onSaved() { Qt.quit() }
        function onSaveFailed() { Qt.quit() }
    }
}
