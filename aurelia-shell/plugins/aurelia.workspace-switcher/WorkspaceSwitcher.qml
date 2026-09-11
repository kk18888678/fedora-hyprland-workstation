import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../theme"
import "."

// Mission Control-inspired workspace overview. The overlay is resident but
// hidden, so SUPER+TAB can open it without paying the Loader cost on every
// invocation. It exposes snapshots, not a second workspace implementation.
Item {
    id: root

    property string aureliaPath: ""
    property var shell: null
    property var bar: null
    property var manifest: ({})
    property var pluginRegistry: null
    property bool isOpen: false
    property int selectedWorkspaceId: 1
    property int modelRevision: 0

    readonly property int currentWorkspaceId: {
        var revision = root.modelRevision
        return root.detectedFocusedWorkspaceId()
    }

    readonly property int workspaceCardWidth: {
        var available = workspaceLayout.width - Theme.spacingXxl * 2 - Theme.spacingMd * 3
        return Math.max(250, Math.min(340, Math.floor(available / 4)))
    }
    readonly property int workspaceListSideMargin: Math.max(0, Math.floor((workspaceLayout.width - root.workspaceCardWidth) / 2))

    function workspaceValues() {
        var workspaces = Hyprland.workspaces
        return workspaces ? workspaces.values : []
    }

    function workspaceById(id) {
        var wanted = Number(id)
        var values = root.workspaceValues()
        for (var i = 0; i < values.length; i++) {
            if (Number(values[i].id) === wanted) return values[i]
        }
        return null
    }

    function workspaceIds() {
        var ids = [1, 2, 3, 4, 5]
        var values = root.workspaceValues()
        for (var i = 0; i < values.length; i++) {
            var id = Number(values[i].id)
            if (isFinite(id) && Math.floor(id) === id && id >= 1 && id <= 10 && ids.indexOf(id) === -1)
                ids.push(id)
        }
        ids.sort(function(left, right) { return left - right })
        return ids
    }

    function selectedIndex() {
        var ids = root.workspaceIds()
        var index = ids.indexOf(Number(root.selectedWorkspaceId))
        return index >= 0 ? index : 0
    }

    function detectedFocusedWorkspaceId() {
        var monitor = Hyprland.focusedMonitor
        var activeWorkspace = monitor ? monitor.activeWorkspace : null
        if (activeWorkspace) return Number(activeWorkspace.id)

        var values = root.workspaceValues()
        for (var i = 0; i < values.length; i++) {
            if (values[i] && values[i].focused === true) return Number(values[i].id)
        }

        // Keep the singleton as a bounded fallback while the workspace model
        // is catching up with Hyprland's focus event.
        var focused = Hyprland.focusedWorkspace
        return focused ? Number(focused.id) : 0
    }

    function seedSelection() {
        var focusedId = root.detectedFocusedWorkspaceId()
        var ids = root.workspaceIds()
        root.selectedWorkspaceId = ids.indexOf(focusedId) >= 0
            ? focusedId
            : (ids.length > 0 ? ids[0] : 1)
    }

    function keepSelectionVisible() {
        var index = root.selectedIndex()
        if (index < 0 || workspaceListView.count === 0) return
        workspaceListView.positionViewAtIndex(index, ListView.Center)
        Qt.callLater(function() {
            if (workspaceListView.count === 0) return
            var current = root.selectedIndex()
            if (current >= 0) workspaceListView.positionViewAtIndex(current, ListView.Center)
        })
    }

    function focusSurface() {
        if (!root.isOpen) return
        keyboardScope.forceActiveFocus()
        root.keepSelectionVisible()
    }

    function selectWorkspace(id) {
        var numericId = Number(id)
        if (root.workspaceIds().indexOf(numericId) === -1) return false
        root.selectedWorkspaceId = numericId
        root.keepSelectionVisible()
        return true
    }

    function cycle(delta) {
        var ids = root.workspaceIds()
        if (ids.length === 0) return "empty"

        var index = root.selectedIndex()
        var step = Number(delta) < 0 ? -1 : 1
        var nextIndex = Math.max(0, Math.min(ids.length - 1, index + step))
        if (nextIndex === index) {
            root.keepSelectionVisible()
            return "edge"
        }
        root.selectedWorkspaceId = ids[nextIndex]
        root.keepSelectionVisible()
        return "cycled"
    }

    function validWorkspaceId(id) {
        var numericId = Number(id)
        return isFinite(numericId) && Math.floor(numericId) === numericId && numericId >= 1 && numericId <= 10
    }

    function activateWorkspace(id) {
        if (!root.validWorkspaceId(id)) return "invalid-workspace"

        var workspace = root.workspaceById(id)
        root.isOpen = false

        if (workspace && typeof workspace.activate === "function") {
            workspace.activate()
            return "ok"
        }

        // Empty baseline workspaces do not have a HyprlandWorkspace object to
        // activate. Keep the same native IPC path as the bar widget.
        var workspaceId = String(Number(id))
        if (Hyprland.usingLua)
            Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + workspaceId + "\" })")
        else
            Hyprland.dispatch("workspace " + workspaceId)
        return "ok"
    }

    function open(payloadJson) {
        if (root.isOpen) return root.cycle(1)

        if (typeof Hyprland.refreshMonitors === "function") Hyprland.refreshMonitors()
        if (typeof Hyprland.refreshWorkspaces === "function") Hyprland.refreshWorkspaces()
        if (typeof Hyprland.refreshToplevels === "function") Hyprland.refreshToplevels()
        root.modelRevision++
        root.seedSelection()
        root.isOpen = true
        Qt.callLater(function() {
            if (!root.isOpen) return
            // refreshWorkspaces may publish its model on the next event turn;
            // seed once more so the first visible selection is never stale.
            root.modelRevision++
            root.seedSelection()
            root.focusSurface()
        })
        return "ok"
    }

    function close() {
        root.isOpen = false
        return "closed"
    }

    function toggle(payloadJson) {
        if (root.isOpen) return root.cycle(1)
        return root.open(payloadJson || "{}")
    }

    function isVisible() {
        return root.isOpen
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            root.modelRevision++
        }
        function onFocusedWorkspaceChanged() {
            root.modelRevision++
            if (!root.isOpen) root.seedSelection()
        }
    }

    PanelWindow {
        id: overviewWindow

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "aurelia-workspace-overview"
        WlrLayershell.keyboardFocus: root.isOpen
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.OnDemand
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.isOpen

        Rectangle {
            anchors.fill: parent
            color: Theme.bgBase
            opacity: 0.95
        }

        MouseArea {
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.LeftButton
            onClicked: function(mouse) {
                mouse.accepted = true
                root.close()
            }
        }

        Item {
            id: overviewCard
            z: 1
            anchors.fill: parent

            FocusScope {
                id: keyboardScope
                anchors.fill: parent
                focus: root.isOpen
                Keys.priority: Keys.BeforeItem

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root.close()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        root.cycle(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                        root.cycle(-1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        root.cycle(1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Home) {
                        var first = root.workspaceIds()
                        if (first.length > 0) root.selectWorkspace(first[0])
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_End) {
                        var last = root.workspaceIds()
                        if (last.length > 0) root.selectWorkspace(last[last.length - 1])
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.activateWorkspace(root.selectedWorkspaceId)
                        event.accepted = true
                    }
                }

                // The dimmed backdrop closes only outside this content
                // region. Swallow clicks on the header, footer, and gaps so
                // browsing never dismisses the switcher accidentally.
                MouseArea {
                    id: workspaceInputShield
                    anchors.fill: workspaceLayout
                    z: 0
                    acceptedButtons: Qt.AllButtons
                    onPressed: function(mouse) { mouse.accepted = true }
                    onClicked: function(mouse) { mouse.accepted = true }
                }

                ColumnLayout {
                    id: workspaceLayout
                    z: 1
                    anchors.centerIn: parent
                    width: Math.min(1900, Math.max(0, parent.width - Theme.spacingXxl * 2))
                    height: 270
                    spacing: Theme.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24

                        Text {
                            Layout.fillWidth: true
                            text: "Workspaces"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXl
                            font.weight: Theme.fontWeightMedium
                        }

                        Text {
                            text: "SUPER + TAB"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs - 1
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    ListView {
                        id: workspaceListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 204
                        Layout.preferredHeight: 222
                        orientation: ListView.Horizontal
                        spacing: Theme.spacingMd
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        preferredHighlightBegin: Math.max(0, (width - root.workspaceCardWidth) / 2)
                        preferredHighlightEnd: Math.max(root.workspaceCardWidth, (width + root.workspaceCardWidth) / 2)
                        highlightMoveDuration: Theme.durationNormal
                        leftMargin: root.workspaceListSideMargin
                        rightMargin: root.workspaceListSideMargin
                        currentIndex: root.selectedIndex()
                        model: root.workspaceIds()

                        delegate: WorkspaceCard {
                            required property int modelData
                            property var workspaceEntry: root.workspaceById(modelData)

                            width: root.workspaceCardWidth
                            height: Math.max(204, Math.min(216, workspaceListView.height))
                            workspaceId: modelData
                            workspace: workspaceEntry
                            selected: root.selectedWorkspaceId === modelData
                            focused: root.currentWorkspaceId === modelData
                            previewActive: root.isOpen
                            modelRevision: root.modelRevision
                            onHovered: root.selectWorkspace(workspaceId)
                            onActivated: root.activateWorkspace(workspaceId)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Selected: Workspace " + String(root.selectedWorkspaceId) +
                                "  ·  Tab / arrows to browse  ·  Enter to open  ·  Esc to close"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    onIsOpenChanged: {
        if (root.isOpen) Qt.callLater(function() { root.focusSurface() })
    }
}
