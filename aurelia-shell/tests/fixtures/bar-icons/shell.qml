import QtQuick
import Quickshell
import Quickshell.Io

// Isolated bar-icon contract fixture. It loads the real notification bar
// widget with a detached bar facade (no barIconCanvas override, so the widget
// falls back to the scaled Theme canvas) plus two bare icon primitive
// instances. It proves glyph font size, optical ink centring, and the
// symbolic/multi-colour tint split without touching a live bar, compositor,
// tray, or PipeWire graph. The scaling matrix is exercised by the caller
// running this same fixture at fontBaseSize 9, 12, and 16.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_BAR_ICONS_RESULT") || ""
    readonly property string widgetSource: Quickshell.env("AURELIA_BAR_ICONS_WIDGET_SOURCE") || ""
    readonly property string iconSource: Quickshell.env("AURELIA_BAR_ICONS_ICON_SOURCE") || ""
    property bool finished: false

    QtObject {
        id: fakeBar
        property bool vertical: false
        property bool barVisible: true
        property int barSize: 26
        property int barTextSize: 12
        property real barTextMargin: 8
        property color barForeground: "#ffffff"
    }

    Loader {
        id: widgetLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.doNotDisturb = false
        }
    }

    // Symbolic tray artwork: tinted to the bar foreground.
    Loader {
        id: symbolicLoader
        source: root.iconSource
        onLoaded: {
            item.width = 16
            item.height = 16
            item.iconSize = 16
            item.name = "application-x-executable"
            item.preserveColors = false
        }
    }

    // Multi-colour brand/tray artwork: the documented preserveColors exception.
    Loader {
        id: brandLoader
        source: root.iconSource
        onLoaded: {
            item.width = 16
            item.height = 16
            item.iconSize = 16
            item.name = "application-x-executable"
            item.preserveColors = true
        }
    }

    Component {
        id: metricsComponent
        TextMetrics {}
    }

    function findIcon(item) {
        if (!item) return null
        if (item.resolvedGlyphPixelSize !== undefined && item.resolvedGlyph !== undefined) return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var found = findIcon(kids[i])
            if (found) return found
        }
        return null
    }

    function childText(item) {
        if (!item) return null
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (child && child.text !== undefined && child.renderType !== undefined) return child
        }
        return null
    }

    function childImage(item) {
        if (!item) return null
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (child && child.fillMode !== undefined) return child
        }
        return null
    }

    function childEffect(item) {
        if (!item) return null
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (child && child.colorizationColor !== undefined) return child
        }
        return null
    }

    function inkCenterOffset(icon, glyphText) {
        var metrics = metricsComponent.createObject(root)
        metrics.font.family = glyphText.font.family
        metrics.font.pixelSize = glyphText.font.pixelSize
        metrics.text = glyphText.text
        var tightCenter = metrics.tightBoundingRect.x + metrics.tightBoundingRect.width / 2
        var center = glyphText.x + tightCenter
        metrics.destroy()
        return center
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
        var widget = widgetLoader.item
        var icon = findIcon(widget)
        var glyphText = childText(icon)
        var symbolic = symbolicLoader.item
        var brand = brandLoader.item
        var symbolicImage = childImage(symbolic)
        var symbolicEffect = childEffect(symbolic)
        var brandImage = childImage(brand)
        var brandEffect = childEffect(brand)
        if (!widget || !icon || !glyphText || !symbolic || !brand ||
            !symbolicImage || !symbolicEffect || !brandImage || !brandEffect) {
            root.finished = true
            resultFile.setText(JSON.stringify({loaded: false}) + "\n")
            return
        }
        root.finished = true
        resultFile.setText(JSON.stringify({
            loaded: true,
            theme: {
                iconCanvas: widget.iconCanvas
            },
            glyph: {
                usingGlyph: icon.usingGlyph === true,
                opticallyCentered: icon.glyphOpticallyCenter === true,
                pixelSize: icon.resolvedGlyphPixelSize,
                canvasWidth: icon.width,
                canvasHeight: icon.height,
                iconSize: icon.iconSize,
                tint: String(icon.tint),
                inkCenterX: inkCenterOffset(icon, glyphText),
                canvasCenterX: icon.width / 2
            },
            symbolic: {
                preserveColors: symbolic.preserveColors === true,
                imageVisible: symbolicImage.visible === true,
                effectVisible: symbolicEffect.visible === true,
                preserveAspectFit: symbolicImage.fillMode === Image.PreserveAspectFit,
                imageWidth: symbolicImage.width,
                imageHeight: symbolicImage.height
            },
            brand: {
                preserveColors: brand.preserveColors === true,
                imageVisible: brandImage.visible === true,
                effectVisible: brandEffect.visible === true
            }
        }) + "\n")
    }

    Timer {
        interval: 700
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
