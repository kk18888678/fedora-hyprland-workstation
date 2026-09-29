import QtQuick
import Quickshell

// Disposable entry point for the Tasklist icon-resolution fixture. The probe
// body is loaded through an absolute file:// URL (the same seam the other
// Aurelia runtime fixtures use) so Quickshell resolves its relative services
// import; the body drives the real TasklistBarWidget through its documented
// toplevelsOverride seam.
ShellRoot {
    id: root

    readonly property string probeSource: Quickshell.env("AURELIA_TASKLIST_ICON_PROBE_SOURCE") || ""

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
