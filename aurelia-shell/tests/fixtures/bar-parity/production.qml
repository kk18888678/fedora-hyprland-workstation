import QtQuick
import Quickshell
import Quickshell.Io

// T54 production-entrypoint fixture. It loads the real Bar.qml entry point,
// not a substitute surface. A compositor-less run records the host and lets
// the suite classify the mapped-panel backend limitation separately.
ShellRoot {
    id: root

    readonly property string barSource: Quickshell.env("AURELIA_BAR_PRODUCTION_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_PRODUCTION_RESULT") || ""
    readonly property string statePath: Quickshell.env("AURELIA_BAR_PRODUCTION_STATE") || ""
    property var bar: null
    property bool evaluated: false

    QtObject {
        id: fakeConfig
        property var config: ({
            version: 1,
            bar: {
                id: "aurelia.bar",
                position: "top",
                transparent: false,
                centerAnchor: "",
                layout: {left: [], center: [], right: []}
            }
        })

        function defaultBarConfig() { return config.bar }
    }

    QtObject {
        id: fakeRegistry
        property int registryRevision: 1
        property int runtimeFailureRevision: 0

        function isKnown() { return false }
        function isEnabled() { return false }
        function primaryKind() { return "" }
        function hasActiveRuntimeFailure() { return false }
    }

    QtObject {
        id: fakeHost
        function syncScopedFacades() {}
    }

    QtObject {
        id: fakeShell

        function setBarPosition() { return "ok" }
        function setBarTransparent() { return "ok" }
        function moveBarWidget() { return "ok" }
    }

    Loader {
        id: barLoader
        source: root.barSource

        onLoaded: {
            item.shell = fakeShell
            item.shellConfig = fakeConfig
            item.pluginRegistry = fakeRegistry
            item.pluginHost = fakeHost
            item.hiddenStatePathOverride = root.statePath
            root.bar = item
            evaluateTimer.restart()
        }
    }

    function writeResult(value) {
        if (root.evaluated || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    Timer {
        id: evaluateTimer
        interval: 900
        repeat: false
        onTriggered: {
            var panel = root.bar && Array.isArray(root.bar.barPanels) && root.bar.barPanels.length > 0
                ? root.bar.barPanels[0] : null
            root.writeResult({
                hostLoaded: root.bar !== null,
                hostIsPanelWindow: root.bar !== null && root.bar.exclusionMode !== undefined,
                panelCount: root.bar && Array.isArray(root.bar.barPanels) ? root.bar.barPanels.length : 0,
                panelLoaded: panel !== null,
                panelHasScreen: !!(panel && panel.screen),
                panelNonOpaque: !!(panel && panel.surfaceFormat.opaque === false),
                panelHasHorizontalVerticalLoader: !!(panel && panel.contentAnchorItem)
            })
        }
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
        interval: 6000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
