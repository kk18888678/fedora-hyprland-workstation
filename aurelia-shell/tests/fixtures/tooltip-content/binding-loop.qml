import QtQuick
import Quickshell
import Quickshell.Io

// Isolated offscreen fixture for the shared tooltip body. It instantiates
// AureliaToolTipContent with a short, a long (wrapping) and a multi-line
// string, plus a structured list body, so the alignment decision is exercised
// in every branch. The test captures this run's log and fails on ANY
// `Binding loop detected` line; the fixture itself asserts nothing.
Window {
    id: root

    readonly property string contentSource: Quickshell.env("TOOLTIP_CONTENT_SOURCE") || ""

    visible: true
    width: 460
    height: 640
    color: "#191724"

    Column {
        anchors.left: parent.left
        anchors.top: parent.top
        spacing: 8

        Loader {
            id: shortLoader
            source: root.contentSource
            onLoaded: item.text = "Short"
        }

        Loader {
            id: longLoader
            source: root.contentSource
            onLoaded: item.text = "The quick brown fox jumps over the lazy dog and keeps " +
                "running far past the right edge of the widest tooltip cap so the " +
                "text has no choice but to wrap onto more than one line."
        }

        Loader {
            id: multilineLoader
            source: root.contentSource
            onLoaded: item.text = "Line one\nLine two\nLine three"
        }

        Loader {
            id: listLoader
            source: root.contentSource
            onLoaded: item.list = [
                { name: "Five hour", value: "42%", tone: "neutral" },
                { name: "Week", value: "88%", tone: "warning" }
            ]
        }
    }

    Timer {
        interval: 1200
        repeat: false
        running: true
        onTriggered: Qt.quit()
    }
}
