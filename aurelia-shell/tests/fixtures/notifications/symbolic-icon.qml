import QtQuick
import Quickshell
import Quickshell.Io

// Isolated render fixture for the notification card's symbolic-versus-logo
// rule. It loads the real NotificationToast with a symbolic icon name and
// records which rendered node is visible and whether the tinted path or the
// preserve-colour path is active. The symbolic decision is owned by the shared
// AppIconResolver; this fixture only observes the card. It never touches a live
// shell, bus, or user configuration.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_NOTIFICATION_SYMBOLIC_RESULT") || ""
    readonly property string toastSource: Quickshell.env("AURELIA_NOTIFICATION_SYMBOLIC_TOAST_SOURCE") || ""
    readonly property string iconName: Quickshell.env("AURELIA_NOTIFICATION_SYMBOLIC_ICON") || "testfixture-symbolic"

    property bool finished: false
    property var toast: null
    property bool loaded: false
    property bool symbolicNodeVisible: false
    property bool symbolicPreservesColors: true
    property bool symbolicUsesTint: false
    property bool logoNodeVisible: true
    property bool slotVisible: false

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
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.writeResult()
    }

    Timer {
        interval: 60
        repeat: true
        running: true
        onTriggered: root.step()
    }

    function step() {
        if (root.finished) return
        if (!root.toast) {
            if (root.toastSource === "") { root.writeResult(); return }
            var component = Qt.createComponent(root.toastSource)
            if (component.status !== Component.Ready) return
            root.toast = component.createObject(root, {
                app: "Symbolic",
                appIcon: root.iconName,
                image: "",
                summary: "Symbolic icon",
                body: "",
                glyph: "",
                showDismiss: false,
                showCopy: false,
                actions: []
            })
            root.loaded = root.toast !== null
            return
        }
        var nodes = nodesUnder(root.toast, [])
        var symbolicNode = nodeNamed("notificationSymbolicIcon", nodes)
        var logoNode = nodeNamed("notificationSourceIcon", nodes)
        var slotNode = nodeNamed("notificationIconSlot", nodes)
        if (!symbolicNode || !logoNode || !slotNode) return
        root.symbolicNodeVisible = symbolicNode.visible === true
        root.symbolicPreservesColors = symbolicNode.preserveColors === true
        root.symbolicUsesTint = String(symbolicNode.tint).length > 0
        root.logoNodeVisible = logoNode.visible === true
        root.slotVisible = slotNode.visible === true
        root.writeResult()
    }

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify({
            loaded: root.loaded,
            slotVisible: root.slotVisible,
            symbolicNodeVisible: root.symbolicNodeVisible,
            symbolicPreservesColors: root.symbolicPreservesColors,
            symbolicUsesTint: root.symbolicUsesTint,
            logoNodeVisible: root.logoNodeVisible
        }) + "\n")
    }
}
