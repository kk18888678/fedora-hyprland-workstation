import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell._Window

// Isolated ticks fixture for the bar tooltip host (`AureliaToolTip`).
//
// The agents bar widget hands the host a brand-new `list`/`footer` (and a new
// `text`) on every `nowMs` tick. This fixture pins `hovered` and `revealed`
// true and drives that model shape through three ticks, asserting the host's
// `visible` never drops and its intrinsic size never reaches zero. It also
// exercises the opt-in `AURELIA_TOOLTIP_DEBUG=1` observability; without the
// variable the run must contain no `[TOOLTIP]` line.
//
// A FloatingWindow is required: a plain QtQuick Window has no Quickshell
// window, so the PopupWindow's `anchorWindow` would be null and `visible`
// could never be observed.
FloatingWindow {
    id: root

    readonly property string tooltipSource: Quickshell.env("TT_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("TT_RESULT") || ""

    visible: true
    implicitWidth: 500
    implicitHeight: 320
    color: "#191724"

    property var samples: []
    property int step: 0

    Item {
        id: trigger
        objectName: "trigger"
        width: 26
        height: 26
        x: 200
        y: 16
        Rectangle { anchors.fill: parent; color: "#333333" }
    }

    Loader {
        id: ttLoader
        source: root.tooltipSource
        onLoaded: {
            item.objectName = "barToolTip"
            item.triggerItem = trigger
            item.hovered = true
            item.revealed = true
            item.text = "Codex · 42% left\nClaude · 9% left"
            item.list = [ { name: "Codex", value: "42% left", tone: "success" },
                          { name: "Claude", value: "9% left", tone: "warning" } ]
            item.footer = { text: "Updated just now · click for details", tone: "default" }
            startTimer.restart()
        }
        onStatusChanged: {
            if (status === Loader.Error) console.error("[TOOLTIP-FIXTURE] load_error")
        }
    }

    function snapshot(label) {
        var it = ttLoader.item
        if (!it) return { label: label, present: false }
        return {
            label: label,
            present: true,
            hovered: it.hovered === true,
            revealed: it.revealed === true,
            visible: it.visible === true,
            backingWindowVisible: it.backingWindowVisible === true,
            width: it.implicitWidth,
            height: it.implicitHeight,
            contentWidth: it.implicitWidth - it.horizontalPadding * 2,
            contentHeight: it.implicitHeight - it.verticalPadding * 2,
            kind: String(it.contentKind),
            length: it.contentLength
        }
    }

    Timer {
        id: startTimer
        interval: 700
        repeat: false
        onTriggered: {
            root.samples.push(root.snapshot("open"))
            tickTimer.restart()
        }
    }

    Timer {
        id: tickTimer
        interval: 220
        repeat: true
        onTriggered: {
            var it = ttLoader.item
            root.step += 1
            if (root.step <= 3) {
                // A fresh object graph every tick, exactly like the widget's
                // nowMs-driven barTooltipModel rebuild.
                it.text = "Codex · " + (40 + root.step) + "% left\nClaude · 9% left"
                it.list = [
                    { name: "Codex", value: (40 + root.step) + "% left", tone: "success" },
                    { name: "Claude", value: "9% left", tone: "warning" }
                ]
                it.footer = {
                    text: "Updated " + root.step + "m ago · click for details",
                    tone: "default"
                }
                root.samples.push(root.snapshot("tick" + root.step))
            } else {
                tickTimer.stop()
                writeTimer.restart()
            }
        }
    }

    Timer {
        id: writeTimer
        interval: 150
        repeat: false
        onTriggered: root.writeResult()
    }

    function writeResult() {
        if (resultFile.path === "") return
        resultFile.setText(JSON.stringify({ samples: root.samples }) + "\n")
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
        interval: 8000
        running: true
        repeat: false
        onTriggered: {
            root.writeResult()
            Qt.quit()
        }
    }
}
