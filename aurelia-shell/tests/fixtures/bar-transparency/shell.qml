import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// Offscreen OpenGL runtime fixture for the transparent bar's legibility halo.
// It mirrors the real BarPanel content layer (`layer.enabled` plus a
// MultiEffect shadow using the strong halo parameters) and verifies that the
// layered content is still rendered and that the shadow effect was actually
// applied. The suite runs it with QT_QPA_PLATFORM=offscreen and
// QT_QUICK_BACKEND=opengl so the shader effect is exercised; plain software
// offscreen silently drops shader effects and is never used.
Window {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_BAR_TRANSPARENCY_RESULT") || ""
    readonly property string imagePath: Quickshell.env("AURELIA_BAR_TRANSPARENCY_IMAGE") || ""
    property bool evaluated: false
    property bool imageSaved: false

    width: 240
    height: 32
    visible: true
    color: "#000000"

    Item {
        id: layered
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            id: legibilityHalo
            shadowEnabled: true
            shadowColor: "#ffffff"
            shadowOpacity: 0.95
            shadowBlur: 0.55
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            shadowScale: 1.0
            autoPaddingEnabled: false
        }

        Rectangle {
            id: content
            anchors.fill: parent
            color: "transparent"

            Rectangle {
                objectName: "aurelia-bar-transparency-glyph"
                x: 24
                y: 8
                width: 80
                height: 16
                color: "#ff0000"
            }
            Rectangle {
                objectName: "aurelia-bar-transparency-icon"
                x: 140
                y: 8
                width: 16
                height: 16
                color: "#00ff00"
            }
        }
    }

    function writeResult() {
        if (root.evaluated || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify({
            layerEnabled: layered.layer.enabled === true,
            effectPresent: layered.layer.effect !== null && layered.layer.effect !== undefined,
            effectShadowEnabled: layered.layer.effect !== null && layered.layer.effect !== undefined &&
                layered.layer.effect.shadowEnabled === true,
            contentPresent: content !== null && content.width > 0 && content.height > 0,
            imageSaved: root.imageSaved
        }) + "\n")
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

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: {
            layered.grabToImage(function(result) {
                root.imageSaved = result && root.imagePath !== ""
                    ? result.saveToFile(root.imagePath) === true
                    : false
                root.writeResult()
            })
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: {
            root.writeResult()
            Qt.quit()
        }
    }
}
