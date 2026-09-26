import QtQuick
import Quickshell
import Quickshell.Io

// T-active-window disposable entry-point fixture. It loads only the real
// Active Window bar widget and drives it with deterministic fake toplevels so
// no live Hyprland socket, bar layout, or compositor state is touched.
ShellRoot {
    id: root

    readonly property string widgetSource: Quickshell.env("AURELIA_ACTIVE_WINDOW_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_ACTIVE_WINDOW_RESULT") || ""
    readonly property string longTitle: "A deliberately long active window title that must be elided by the widget instead of expanding the bar without bound"
    // Touching the applications model at construction starts the asynchronous
    // desktop-entry scan; DesktopEntries.heuristicLookup alone does not trigger
    // it, so an isolated shell that only renders this widget must kick it off.
    readonly property int desktopEntryCount: DesktopEntries.applications.values.length
    property bool finished: false

    QtObject {
        id: clickState
        property int activates: 0
        property int closes: 0
    }

    QtObject {
        id: fakeHandle
        property string appId: "fixture.unknown.app"
    }

    QtObject {
        id: classHandle
        property string appId: ""
    }

    QtObject {
        id: fixtureAppHandle
        property string appId: "fixture-app"
    }

    QtObject {
        id: clickHandle
        property string appId: "fixture.unknown.app"
        function activate() { clickState.activates = clickState.activates + 1 }
        function close() { clickState.closes = clickState.closes + 1 }
    }

    QtObject {
        id: titleToplevel
        property string title: "Fixture title"
        property QtObject handle: fakeHandle
        property var lastIpcObject: ({class: "FixtureClass"})
    }

    QtObject {
        id: appIdToplevel
        property string title: ""
        property QtObject handle: fakeHandle
        property var lastIpcObject: ({})
    }

    QtObject {
        id: classToplevel
        property string title: ""
        property QtObject handle: classHandle
        property var lastIpcObject: ({class: "FixtureClass"})
    }

    QtObject {
        id: fixtureAppToplevel
        property string title: ""
        property QtObject handle: fixtureAppHandle
        property var lastIpcObject: ({})
    }

    QtObject {
        id: longToplevel
        property string title: root.longTitle
        property QtObject handle: fakeHandle
        property var lastIpcObject: ({class: "FixtureClass"})
    }

    QtObject {
        id: shortToplevel
        property string title: "vim"
        property QtObject handle: fakeHandle
        property var lastIpcObject: ({})
    }

    QtObject {
        id: clickToplevel
        property string title: "Clickable window"
        property QtObject handle: clickHandle
        property var lastIpcObject: ({})
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

    QtObject {
        id: verticalBar
        property bool vertical: true
        property bool barVisible: true
        property int barSize: 26
        property int barIconCanvas: 16
        property int barIconFont: 13
        property int barTextSize: 12
        property real barTextMargin: 8
        property color barForeground: "#ffffff"
    }

    Loader {
        id: titleLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.activeToplevelOverride = titleToplevel
        }
    }

    // Explicit legacy identity: the widget must still render the title-first
    // label (title -> appId -> class) when the user selects title mode.
    Loader {
        id: titleModeLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.settings = ({displayMode: "title", maxWidth: 280})
            item.activeToplevelOverride = titleToplevel
        }
    }

    // An unknown mode must fail closed to the app-name default, never to the
    // title and never to an empty label.
    Loader {
        id: invalidModeLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.settings = ({displayMode: "bogus", maxWidth: 280})
            item.activeToplevelOverride = titleToplevel
        }
    }

    Loader {
        id: fixtureAppLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.activeToplevelOverride = fixtureAppToplevel
        }
    }

    Loader {
        id: appIdLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.activeToplevelOverride = appIdToplevel
        }
    }

    Loader {
        id: classLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.activeToplevelOverride = classToplevel
        }
    }

    // The elision contract is exercised through title mode so the long title
    // (rather than a short app id) is the measured label.
    Loader {
        id: longLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.settings = ({displayMode: "title", maxWidth: 280})
            item.activeToplevelOverride = longToplevel
        }
    }

    Loader {
        id: cappedLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.settings = ({displayMode: "title", maxWidth: 100})
            item.activeToplevelOverride = longToplevel
        }
    }

    Loader {
        id: shortLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.activeToplevelOverride = shortToplevel
        }
    }

    Loader {
        id: emptyLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.activeToplevelOverride = null
        }
    }

    Loader {
        id: verticalLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = verticalBar
            item.activeToplevelOverride = titleToplevel
        }
    }

    Loader {
        id: clickLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.activeToplevelOverride = clickToplevel
        }
    }

    Loader {
        id: missingIconLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.iconSourceOverride = ""
            item.activeToplevelOverride = titleToplevel
        }
    }

    Loader {
        id: symbolicIconLoader
        source: root.widgetSource
        onLoaded: {
            item.bar = fakeBar
            item.iconNameOverride = "fixture-app-symbolic?theme=dark"
            item.activeToplevelOverride = titleToplevel
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

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        var title = titleLoader.item
        var titleMode = titleModeLoader.item
        var invalidMode = invalidModeLoader.item
        var fixtureApp = fixtureAppLoader.item
        var appId = appIdLoader.item
        var classItem = classLoader.item
        var longItem = longLoader.item
        var capped = cappedLoader.item
        var shortItem = shortLoader.item
        var empty = emptyLoader.item
        var vertical = verticalLoader.item
        var click = clickLoader.item
        var missing = missingIconLoader.item
        var symbolic = symbolicIconLoader.item
        if (!title || !titleMode || !invalidMode || !fixtureApp || !appId || !classItem ||
                !longItem || !capped || !shortItem || !empty || !vertical || !click ||
                !missing || !symbolic) {
            root.finished = true
            resultFile.setText(JSON.stringify({loaded: false}) + "\n")
            return
        }

        click.activateWindow()
        click.closeWindow()
        var activateResult = click.activateWindow()
        var closeResult = click.closeWindow()

        root.finished = true
        resultFile.setText(JSON.stringify({
            loaded: true,
            labels: {
                app: String(title.label),
                appId: String(appId.label),
                className: String(classItem.label),
                empty: String(empty.label),
                titleMode: String(titleMode.label),
                titleModeTitle: String(titleMode.titleLabel),
                invalidMode: String(invalidMode.label),
                fixtureApp: String(fixtureApp.label)
            },
            icons: {
                fallbackName: String(title.iconName),
                fallbackSource: String(title.iconSource),
                emptyAppIconName: String(classItem.iconName),
                fixtureAppName: String(fixtureApp.iconName),
                fixtureAppSource: String(fixtureApp.iconSource)
            },
            render: {
                iconInk: Number(title.iconInkSize),
                iconSlot: Number(title.iconSlotSize),
                iconSlotVisible: title.iconSlotVisible === true,
                labelOpacity: Number(title.labelOpacity),
                implicitWidth: Number(title.implicitWidth),
                outerLabelWidth: Number(title.labelWidth),
                iconSpacing: Number(title.iconSpacing)
            },
            missingIcon: {
                slotVisible: missing.iconSlotVisible === true,
                visible: missing.visible === true,
                implicitWidth: Number(missing.implicitWidth),
                labelWidth: Number(missing.labelWidth)
            },
            elision: {
                maxWidth: Number(longItem.maxWidth),
                longLabelWidth: Number(longItem.labelWidth),
                longMeasured: Number(longItem.measuredLabelWidth),
                cappedMaxWidth: Number(capped.maxWidth),
                cappedLabelWidth: Number(capped.labelWidth),
                shortLabelWidth: Number(shortItem.labelWidth),
                shortMeasured: Number(shortItem.measuredLabelWidth),
                shortMaxWidth: Number(shortItem.maxWidth),
                longVisibleWidth: Number(longItem.visibleLabelWidth),
                longTextMargin: Number(longItem.textMargin)
            },
            visibility: {
                emptyVisible: empty.visible === true,
                emptyImplicitWidth: Number(empty.implicitWidth),
                verticalVisible: vertical.visible === true,
                verticalImplicitWidth: Number(vertical.implicitWidth),
                titleVisible: title.visible === true,
                titleImplicitWidth: Number(title.implicitWidth)
            },
            clicks: {
                activates: clickState.activates,
                closes: clickState.closes,
                activateResult: activateResult,
                closeResult: closeResult
            },
            policy: {
                symbolicIcon: title.symbolicIcon === true,
                preserveColors: title.iconPreservesColors === true,
                symbolicName: String(symbolic.iconName),
                symbolicIconFlag: symbolic.symbolicIcon === true,
                symbolicPreserveColors: symbolic.iconPreservesColors === true
            }
        }) + "\n")
    }

    // Desktop-entry scanning is asynchronous and can take a moment on a cold
    // cache. Wait until the deterministic fixture entry the test installed
    // under XDG_DATA_DIRS resolves before snapshotting, with a bounded fallback
    // so a broken scan still produces a result instead of hanging the suite.
    Timer {
        id: entryReady
        interval: 150
        running: true
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts = attempts + 1
            if ((root.desktopEntryCount > 0 &&
                    DesktopEntries.heuristicLookup("fixture-app") !== null) || attempts >= 40) {
                running = false
                settleTimer.running = true
            }
        }
    }

    // Let the 180 ms width animation settle before snapshotting so the geometry
    // assertions see final widths instead of an in-flight interpolated value.
    Timer {
        id: settleTimer
        interval: 400
        running: false
        repeat: false
        onTriggered: root.writeResult()
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
