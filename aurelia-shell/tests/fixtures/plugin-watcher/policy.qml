import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string policySource: Quickshell.env("AURELIA_WATCHER_POLICY_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_WATCHER_POLICY_RESULT") || ""
    property var policy: null
    property bool evaluated: false

    QtObject {
        id: fakeRegistry
        property string firstPartyDir: "/tmp/aurelia-first-party"
        property string userPluginsDir: "/tmp/aurelia-user-plugins"
        property var installedPlugins: ({
            "aurelia.clock": {__sourceDir: "/tmp/aurelia-first-party/aurelia.clock"},
            "aurelia.multi": {__sourceDir: "/tmp/aurelia-first-party/group"},
            "aurelia.sibling": {__sourceDir: "/tmp/aurelia-first-party/group"},
            "aurelia.single": {__sourceDir: "/tmp/aurelia-first-party/single"}
        })

        function isValidPluginId(value) {
            return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value) && value.indexOf("..") === -1
        }
    }

    Loader {
        id: policyLoader
        source: root.policySource
        onLoaded: {
            item.registry = fakeRegistry
            root.policy = item
            Qt.callLater(root.evaluate)
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function evaluate() {
        if (root.evaluated || !root.policy || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify({
            directQml: root.policy.pluginIdForPath("/tmp/aurelia-first-party/aurelia.clock/Clock.qml"),
            directJs: root.policy.pluginIdForPath("/tmp/aurelia-first-party/aurelia.clock/Model.js"),
            groupedJson: root.policy.pluginIdForPath("/tmp/aurelia-first-party/group/Widget.json"),
            groupedLua: root.policy.pluginIdForPath("/tmp/aurelia-first-party/group/keybindings.lua"),
            groupedConf: root.policy.pluginIdForPath("/tmp/aurelia-first-party/single/theme.conf"),
            newUser: root.policy.pluginIdForPath("/tmp/aurelia-user-plugins/acme.new/Widget.qml"),
            newFirstParty: root.policy.pluginIdForPath("/tmp/aurelia-first-party/aurelia.new/Widget.qml"),
            newGrouped: root.policy.pluginIdForPath("/tmp/aurelia-first-party/new-group/Widget.qml"),
            hidden: root.policy.isWatchedPath("/tmp/aurelia-user-plugins/.clone.123/Widget.qml"),
            gitMetadata: root.policy.isWatchedPath("/tmp/aurelia-user-plugins/acme.new/.git/config"),
            outside: root.policy.isWatchedPath("/tmp/other/Widget.qml")
        }) + "\n")
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
