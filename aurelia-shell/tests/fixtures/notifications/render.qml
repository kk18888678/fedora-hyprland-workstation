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
    property var toastComponent: null
    property var toast: null
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
    property bool copyVisibleDefault: false
    property bool copyVisibleWhenFocused: false
    property bool copyHiddenAfterBlur: false
    property int actionButtonCount: 0
    property bool actionButtonsSameRow: false
    property int actionFlowWidth: 0
    property int actionFlowImplicitHeight: 0
    property int actionOneRowHeight: 0
    property int actionWrappedHeight: 0
    property int actionButtonCountInitial: 0
    property bool actionButtonsSameRowInitial: false
    property int actionFlowWidthInitial: 0
    property int actionWrappedButtonCount: 0
    property string copyIcon: ""
    property bool copyIsIconControl: false
    property bool copySameRowAsTitle: false
    property bool copyAfterTitleInRow: false
    property bool summaryLeftAligned: false
    property bool bodyLeftAligned: false
    property string fallbackSourcePath: ""
    property string fallbackName: ""
    property bool emptyAppHidden: false
    property bool emptyTimestampHidden: false

    // The production Service stores snapshots in a ListModel. Qt materializes
    // an array role as a nested list model exposing `.count` (and no `.length`),
    // so the fixture must drive the toast from that representation rather than
    // a plain JS array, or it cannot catch the action-undercount regression.
    ListModel { id: actionsModel }

    // Instantiate the real card with its properties set at creation time, the
    // way the production delegate does. Setting `actions` after construction
    // would let the Flow settle around a missing Repeater delegate and mask
    // the action-undercount regression.
    function ensureToast() {
        if (root.toast || root.toastSource === "") return
        if (!root.toastComponent) {
            root.toastComponent = Qt.createComponent(root.toastSource)
            if (root.toastComponent.status === Component.Loading) {
                root.toastComponent.statusChanged.connect(root.materializeToast)
                return
            }
        }
        root.materializeToast()
    }

    function materializeToast() {
        if (root.toast || !root.toastComponent) return
        if (root.toastComponent.status !== Component.Ready) return
        if (actionsModel.count === 0)
            actionsModel.append({ actions: [{ identifier: "reply", text: "Reply" }] })
        root.toast = root.toastComponent.createObject(root, {
            app: root.longAppName,
            appIcon: root.iconSource,
            summary: "Build complete",
            body: "The render fixture body",
            glyph: "",
            image: "",
            timestampLabel: "Yesterday 14:30",
            showDismiss: false,
            defaultActionText: "Open",
            actions: actionsModel.get(0).actions
        })
        root.loaded = root.toast !== null
        pollTimer.start()
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

    function nodesNamed(name, nodes) {
        var matches = []
        for (var i = 0; i < nodes.length; i++) {
            if (String(nodes[i].objectName) === name && nodes[i].visible === true)
                matches.push(nodes[i])
        }
        return matches
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
        var nodes = nodesUnder(root.toast, [])
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
        root.summaryLeftAligned = summaryNode
            ? summaryNode.horizontalAlignment === Text.AlignLeft
            : false
        root.bodyLeftAligned = bodyNode
            ? bodyNode.horizontalAlignment === Text.AlignLeft
            : false
        root.fallbackSourcePath = fallbackNode ? String(fallbackNode.sourcePath || "") : ""
        root.fallbackName = fallbackNode ? String(fallbackNode.name || "") : ""
        return iconNode
    }

    function captureActionLayout() {
        var nodes = nodesUnder(root.toast, [])
        var buttons = nodesNamed("notificationActionButton", nodes)
        root.actionButtonCount = buttons.length
        root.actionButtonsSameRow = buttons.length >= 2 &&
            Math.abs(Number(buttons[0].y) - Number(buttons[1].y)) < 1
        var flow = nodeNamed("notificationActionFlow", nodes)
        root.actionFlowWidth = flow ? Number(flow.width) : 0
        root.actionFlowImplicitHeight = flow ? Number(flow.implicitHeight) : 0
    }

    function step() {
        if (root.phase !== 0) return
        if (!root.toast) { root.ensureToast(); return }
        var iconNode = captureVisibleState()
        if (!iconNode || Number(iconNode.status) !== root.imageReadyStatus) return
        root.iconReady = true
        captureVisibleState()
        // The card is not hovered or focused yet, so Copy must stay hidden.
        root.copyVisibleDefault = root.copyVisible
        root.phase = 1
        // Let the Flow settle one event-loop turn so the Repeater delegate is
        // laid out before measuring the production-path action row.
        Qt.callLater(root.captureInitial)
    }

    function captureInitial() {
        if (root.phase !== 1) return
        captureActionLayout()
        root.actionOneRowHeight = root.actionFlowImplicitHeight
        root.actionButtonCountInitial = root.actionButtonCount
        root.actionButtonsSameRowInitial = root.actionButtonsSameRow
        root.actionFlowWidthInitial = root.actionFlowWidth
        root.phase = 2
        // Add enough options to exceed the card width and confirm the Flow
        // still wraps instead of overflowing. This phase uses a plain JS array
        // because it exercises Flow geometry, not the ListModel round-trip.
        root.toast.actions = [
            { identifier: "a1", text: "One" },
            { identifier: "a2", text: "Two" },
            { identifier: "a3", text: "Three" },
            { identifier: "a4", text: "Four" },
            { identifier: "a5", text: "Five" },
            { identifier: "a6", text: "Six" }
        ]
        Qt.callLater(root.afterWrap)
    }

    function afterWrap() {
        if (root.phase !== 2) return
        captureActionLayout()
        root.actionWrappedHeight = root.actionFlowImplicitHeight
        root.actionWrappedButtonCount = root.actionButtonCount
        root.phase = 3
        root.toast.forceActiveFocus()
        Qt.callLater(root.afterFocus)
    }

    function afterFocus() {
        if (root.phase !== 3) return
        captureVisibleState()
        root.copyVisibleWhenFocused = root.copyVisible
        root.toast.focus = false
        root.phase = 4
        Qt.callLater(root.afterBlur)
    }

    function afterBlur() {
        if (root.phase !== 4) return
        captureVisibleState()
        root.copyHiddenAfterBlur = root.copyVisible === false
        root.phase = 5
        // Clear both attribution fields and prove the card stops rendering
        // them, so the visible result above is not a static always-on label.
        root.toast.app = ""
        root.toast.timestampLabel = ""
        Qt.callLater(root.finish)
    }

    function finish() {
        var nodes = nodesUnder(root.toast, [])
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
        running: true
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
            copyVisibleDefault: root.copyVisibleDefault,
            copyVisibleWhenFocused: root.copyVisibleWhenFocused,
            copyHiddenAfterBlur: root.copyHiddenAfterBlur,
            copyIcon: root.copyIcon,
            actionButtonCount: root.actionButtonCount,
            actionButtonsSameRow: root.actionButtonsSameRow,
            actionButtonCountInitial: root.actionButtonCountInitial,
            actionButtonsSameRowInitial: root.actionButtonsSameRowInitial,
            actionFlowWidth: root.actionFlowWidth,
            actionFlowWidthInitial: root.actionFlowWidthInitial,
            actionFlowImplicitHeight: root.actionFlowImplicitHeight,
            actionOneRowHeight: root.actionOneRowHeight,
            actionWrappedHeight: root.actionWrappedHeight,
            actionWrappedButtonCount: root.actionWrappedButtonCount,
            copyIsIconControl: root.copyIsIconControl,
            copySameRowAsTitle: root.copySameRowAsTitle,
            copyAfterTitleInRow: root.copyAfterTitleInRow,
            summaryLeftAligned: root.summaryLeftAligned,
            bodyLeftAligned: root.bodyLeftAligned,
            fallbackSourcePath: root.fallbackSourcePath,
            fallbackName: root.fallbackName,
            emptyAppHidden: root.emptyAppHidden,
            emptyTimestampHidden: root.emptyTimestampHidden
        }) + "\n")
    }
}
