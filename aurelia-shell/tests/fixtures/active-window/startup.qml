import QtQuick
import Quickshell
import Quickshell.Io

// T-active-window-startup disposable entry-point fixture. It proves the
// earliest possible population: the real widget must recover the focused
// toplevel from the compositor toplevels model (never from the
// activewindowv2 signal, which has not arrived at shell start) and already
// report its final identity when it loads, before any settle timer can run.
// The desktop-entry scan is awaited before the widget is created so the
// deterministic entry resolves synchronously at load time.
ShellRoot {
    id: root

    readonly property string widgetSource: Quickshell.env("AURELIA_ACTIVE_WINDOW_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_ACTIVE_WINDOW_STARTUP_RESULT") || ""
    property bool finished: false
    property bool widgetLoaded: false
    property var snapshot: ({})

    QtObject {
        id: focusedHandle
        // Deliberately empty: the wlr handle is not linked at shell start, so
        // the class fallback must supply the identity.
        property string appId: ""
    }

    QtObject {
        id: focusedToplevel
        property string title: ""
        property QtObject handle: focusedHandle
        property var lastIpcObject: ({class: "fixture-app", focusHistoryID: 0})
    }

    QtObject {
        id: unfocusedNoMarkerToplevel
        property string title: "Unfocused"
        property var lastIpcObject: ({class: "other-app"})
    }

    QtObject {
        id: fakeBar
        property bool vertical: false
        property bool barVisible: true
        property int barSize: 26
        property int barIconCanvas: 16
        property int barIconFont: 13
        property int barTextSize: 12
        property real barTextMargin: 8
        property color barForeground: "#ffffff"
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

    function snapshotWidget(item) {
        return {
            label: String(item.label),
            iconName: String(item.iconName),
            hasIcon: item.hasIcon === true,
            appEntry: item.appEntry !== null && item.appEntry !== undefined,
            appEntryName: item.appEntry && item.appEntry.name ? String(item.appEntry.name) : "",
            visible: item.visible === true,
            implicitWidth: Number(item.implicitWidth),
            labelWidth: Number(item.labelWidth),
            animatedLabelWidth: Number(item.animatedLabelWidth),
            labelWidthInitialized: item.labelWidthInitialized === true,
            animatedMatchesLabel: Math.abs(Number(item.animatedLabelWidth) - Number(item.labelWidth)) < 0.001
        }
    }

    Loader {
        id: startupLoader
        active: false
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            // Publish the focused toplevel as the model, exactly as
            // Hyprland.toplevels would be. activeToplevelOverride stays
            // undefined so the production fallback path runs.
            item.toplevelsOverride = [unfocusedNoMarkerToplevel, focusedToplevel]
            // Snapshot synchronously, inside onLoaded. There is no settle
            // timer: the identity must already be present and the first width
            // must already be final instead of animating up from empty.
            root.snapshot = snapshotWidget(item)
            root.widgetLoaded = true
            root.writeResult()
        }
    }

    // The desktop-entry scan is asynchronous. Wait until the deterministic
    // entry the test installs resolves, then load the widget. Proving the
    // earliest population path means the model must be ready before the
    // widget exists, not compensated for afterwards.
    Timer {
        id: entryReady
        interval: 25
        running: true
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts = attempts + 1
            if ((DesktopEntries.applications.values.length > 0 &&
                    DesktopEntries.heuristicLookup("fixture-app") !== null) || attempts >= 200) {
                running = false
                startupLoader.active = true
            }
        }
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify({
            loaded: root.widgetLoaded,
            snapshot: root.snapshot
        }) + "\n")
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: {
            if (!root.finished) root.writeResult()
        }
    }

    Timer {
        interval: 7800
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
