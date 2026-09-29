import QtQuick
import Quickshell

// Disposable entry point for the AppIconResolver fixture. The owner under test
// is loaded through an absolute file:// URL (the same seam the other Aurelia
// runtime fixtures use) so Quickshell resolves its relative services import.
ShellRoot {
    id: root

    readonly property string resolverSource: Quickshell.env("AURELIA_APP_ICON_SOURCE") || ""

    Loader {
        id: resolverLoader
        source: root.resolverSource
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
