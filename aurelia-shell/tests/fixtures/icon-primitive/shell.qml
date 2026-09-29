import QtQuick
import Quickshell

// Disposable entry point for the shared AureliaIcon primitive contract. The
// body is loaded through an absolute file:// URL (the seam the other Aurelia
// runtime fixtures use) so Quickshell resolves its relative imports. No live
// shell, compositor, theme, or user configuration is touched.
ShellRoot {
    id: root

    readonly property string probeSource: Quickshell.env("AURELIA_ICON_PRIMITIVE_PROBE_SOURCE") || ""

    Loader {
        id: probeLoader
        source: root.probeSource
    }

    // Backstop only. The child writes the result and asks the engine to quit;
    // this guarantees the isolated process cannot hang if the offscreen
    // backend starves the child's timers.
    Timer {
        interval: 6000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
