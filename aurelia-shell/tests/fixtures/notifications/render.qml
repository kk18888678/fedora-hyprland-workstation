import QtQuick
import Quickshell
import Quickshell.Io

// Isolated render fixture for the shared notification card. It loads the real
// NotificationToast, drives it with a deliberately long source app name, a
// timestamp label, and an icon, then records the Text/Image values actually
// present in the rendered tree. This proves the card renders the attribution
// rather than merely accepting the properties. It also proves the Copy
// affordance is an icon control placed after the app name in the same title
// row, so a text button or a toolbar-only Copy cannot silently return.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_RENDER_RESULT") || ""
    readonly property string toastSource: Quickshell.env("AURELIA_NOTIFICATION_RENDER_TOAST_SOURCE") || ""
    readonly property string iconSource: Quickshell.env("AURELIA_NOTIFICATION_RENDER_ICON") || ""
    readonly property string longAppName: "Aurelia Render Fixture With An Extremely Long Application Name"
    // Image.Ready is enum value 1; compare numerically so the fixture stays
    // independent of how the QML type is imported into script scope.
    readonly property int imageReadyStatus: 1
    property bool finished: false
    property bool loaded: false
    property bool iconReady: false
    property int phase: 0
    property string appText: ""
    property bool appVisible: false
    property bool appElideRight: false
    property int appMaxLines: 0
    property string timestampText: ""
    property bool timestampVisible: false
    property string renderedIconSource: ""
    property bool renderedIconVisible: false
    property bool copyVisible: false
    property string copyIcon: ""
    property bool copyIsIconControl: false
    property bool copySameRowAsTitle: false
    property bool copyAfterTitleInRow: false
    property bool summaryCentered: false
    property bool bodyCentered: false
    property string fallbackSourcePath: ""
    property string fallbackName: ""
    property bool emptyAppHidden: false
    property bool emptyTimestampHidden: false

    Loader {
        id: toastLoader
        active: root.toastSource !== ""
        source: root.toastSource
        onLoaded: {
            if (!item) return
            root.loaded = true
            item.app = root.longAppName
            item.appIcon = root.iconSource
            item.summary = "Build complete"
            item.body = "The render fixture body"
            item.glyph = ""
            item.image = ""
            item.timestampLabel = "Yesterday 14:30"
            item.showDismiss = false
            pollTimer.start()
        }
    }

    function nodesUnder(node, output) {
        if (!node) return output
        if (typeof node.objectName === "string" && node.objectName !== "") output.push(node)
        var children = node.children
        if (children) {
            for (var i = 0; i < children.length; i++) nodesUnder(children[i], output)
        }
        return output
    }

    function nodeNamed(name, nodes) {
        for (var i = 0; i < nodes.length; i++) {
            if (String(nodes[i].objectName) === name) return nodes[i]
        }
        return null
    }

    function childIndex(node, parent) {
        var children = parent ? parent.children : null
        if (!children) return -1
        for (var i = 0; i < children.length; i++) {
            if (children[i] === node) return i
        }
        return -1
    }

    function captureVisibleState() {
        var nodes = nodesUnder(toastLoader.item, [])
        var appNode = nodeNamed("notificationSourceApp", nodes)
        var timestampNode = nodeNamed("notificationTimestamp", nodes)
        var iconNode = nodeNamed("notificationSourceIcon", nodes)
        var copyNode = nodeNamed("notificationCopyAction", nodes)
        var summaryNode = nodeNamed("notificationSummary", nodes)
        var bodyNode = nodeNamed("notificationBody", nodes)
        var fallbackNode = nodeNamed("notificationSourceIconFallback", nodes)
        root.appText = appNode ? String(appNode.text) : ""
        root.appVisible = appNode ? appNode.visible === true : false
        root.appElideRight = appNode ? appNode.elide === Text.ElideRight : false
        root.appMaxLines = appNode ? Number(appNode.maximumLineCount) : 0
        root.timestampText = timestampNode ? String(timestampNode.text) : ""
        root.timestampVisible = timestampNode ? timestampNode.visible === true : false
        root.renderedIconSource = iconNode ? String(iconNode.source) : ""
        // The image's own visible binding is true for any decoded image, so
        // also require its icon slot parent to be visible: this is what proves
        // the source app icon actually reaches the rendered card.
        root.renderedIconVisible = iconNode
            ? (iconNode.visible === true && iconNode.parent && iconNode.parent.visible === true)
            : false
        // Copy must be an icon control (non-empty icon glyph, no text label)
        // that shares the title row with the app name and follows it.
        root.copyVisible = copyNode ? copyNode.visible === true : false
        root.copyIcon = copyNode ? String(copyNode.icon || "") : ""
        root.copyIsIconControl = copyNode
            ? (String(copyNode.icon || "").length > 0 &&
               (copyNode.label === undefined || String(copyNode.label || "").length === 0))
            : false
        root.copySameRowAsTitle = !!(copyNode && appNode &&
            copyNode.parent === appNode.parent)
        root.copyAfterTitleInRow = !!(copyNode && appNode &&
            childIndex(copyNode, copyNode.parent) > childIndex(appNode, appNode.parent))
        root.summaryCentered = summaryNode
            ? summaryNode.horizontalAlignment === Text.AlignHCenter
            : false
        root.bodyCentered = bodyNode
            ? bodyNode.horizontalAlignment === Text.AlignHCenter
            : false
        root.fallbackSourcePath = fallbackNode ? String(fallbackNode.sourcePath || "") : ""
        root.fallbackName = fallbackNode ? String(fallbackNode.name || "") : ""
        return iconNode
    }

    function step() {
        if (root.phase !== 0) return
        var iconNode = captureVisibleState()
        if (!iconNode || Number(iconNode.status) !== root.imageReadyStatus) return
        root.iconReady = true
        captureVisibleState()
        root.phase = 1
        // Clear both attribution fields and prove the card stops rendering
        // them, so the visible result above is not a static always-on label.
        toastLoader.item.app = ""
        toastLoader.item.timestampLabel = ""
        Qt.callLater(root.finish)
    }

    function finish() {
        var nodes = nodesUnder(toastLoader.item, [])
        var appNode = nodeNamed("notificationSourceApp", nodes)
        var timestampNode = nodeNamed("notificationTimestamp", nodes)
        root.emptyAppHidden = !appNode || appNode.visible !== true
        root.emptyTimestampHidden = !timestampNode || timestampNode.visible !== true
        pollTimer.stop()
        root.writeResult()
    }

    Timer {
        id: pollTimer
        interval: 50
        repeat: true
        onTriggered: root.step()
    }

    Timer {
        id: timeoutTimer
        interval: 5000
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult()
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
        root.finished = true
        resultFile.setText(JSON.stringify({
            loaded: root.loaded,
            iconReady: root.iconReady,
            appText: root.appText,
            appVisible: root.appVisible,
            appElideRight: root.appElideRight,
            appMaxLines: root.appMaxLines,
            timestampText: root.timestampText,
            timestampVisible: root.timestampVisible,
            iconSource: root.renderedIconSource,
            iconVisible: root.renderedIconVisible,
            copyVisible: root.copyVisible,
            copyIcon: root.copyIcon,
            copyIsIconControl: root.copyIsIconControl,
            copySameRowAsTitle: root.copySameRowAsTitle,
            copyAfterTitleInRow: root.copyAfterTitleInRow,
            summaryCentered: root.summaryCentered,
            bodyCentered: root.bodyCentered,
            fallbackSourcePath: root.fallbackSourcePath,
            fallbackName: root.fallbackName,
            emptyAppHidden: root.emptyAppHidden,
            emptyTimestampHidden: root.emptyTimestampHidden
        }) + "\n")
    }
}
