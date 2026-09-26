import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../theme"
import "."
import "WorkspaceSelection.js" as WorkspaceSelection

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
    // Focused-workspace pair used by the quick-tap toggle. `activeWorkspaceId`
    // follows the focused workspace; `previousWorkspaceId` is the workspace it
    // came from. They are updated by recordFocusedWorkspace() (idempotently)
    // and flipped before a quick-tap activation to avoid racing the async
    // Hyprland focus signal.
    property int activeWorkspaceId: 0
    property int previousWorkspaceId: 0
    // Interaction state for the quick-tap vs hold decision. `interactionRevealed`
    // becomes true only once the overlay is actually rendered; `interactionNavigated`
    // becomes true when any explicit navigation occurs. A fast tap leaves both
    // false, which is what keeps the overlay from flashing on screen.
    property bool interactionRevealed: false
    property bool interactionNavigated: false
    // When true (the default), the overview shows and cycles only workspaces
    // that are actually in use. Users can switch back to the historical
    // "cycle all workspaces" behaviour from Settings.
    readonly property bool onlyWorkspacesInUse: Theme.getPreference("aurelia.workspaces.only_in_use", true)
    // Accumulated wheel delta so one physical notch (120) is exactly one
    // cycle, instead of one cycle per high-resolution wheel event.
    property real wheelAccumulator: 0

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
        return WorkspaceSelection.workspaceIds(
            root.onlyWorkspacesInUse,
            root.workspaceValues(),
            root.detectedFocusedWorkspaceId(),
            [1, 2, 3, 4, 5])
    }

    // Real workspace object ids, irrespective of the only_in_use display policy.
    // A persistent workspace that is currently empty still exists as a Hyprland
    // workspace object and must remain a valid quick-tap target; `only_in_use`
    // continues to govern only which workspaces are displayed and cycled.
    function knownWorkspaceIds() {
        var ids = []
        var values = root.workspaceValues()
        for (var i = 0; i < values.length; i++) {
            var id = WorkspaceSelection.workspaceId(values[i] && values[i].id)
            if (id !== 0 && ids.indexOf(id) === -1) ids.push(id)
        }
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

    // Track the focused workspace so a quick tap can return to it. Idempotent:
    // repeated calls with the same focus leave the pair untouched. Out-of-range
    // focus values (for example while the Hyprland model is still catching up)
    // are ignored rather than clobbering the previous workspace.
    function recordFocusedWorkspace() {
        var next = root.detectedFocusedWorkspaceId()
        if (!root.validWorkspaceId(next)) return
        if (next === root.activeWorkspaceId) return
        root.previousWorkspaceId = root.activeWorkspaceId
        root.activeWorkspaceId = next
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
        if (workspaceListView.currentIndex !== index) workspaceListView.currentIndex = index
        workspaceListView.positionViewAtIndex(index, ListView.Center)
        Qt.callLater(function() {
            if (workspaceListView.count === 0) return
            var current = root.selectedIndex()
            if (current >= 0) {
                if (workspaceListView.currentIndex !== current) workspaceListView.currentIndex = current
                workspaceListView.positionViewAtIndex(current, ListView.Center)
            }
        })
    }

    function focusSurface() {
        if (!root.isOpen) return
        // A tap interaction must never take keyboard focus: the overlay is not
        // rendered until interactionRevealed flips true.
        if (!root.interactionRevealed) return
        keyboardScope.forceActiveFocus()
        root.keepSelectionVisible()
    }

    function selectWorkspace(id, recenter) {
        var numericId = Number(id)
        if (root.workspaceIds().indexOf(numericId) === -1) return false
        root.noteInteraction()
        root.selectedWorkspaceId = numericId
        // Hover selection must not scroll the list: re-centering moves the
        // cards under a stationary pointer, which re-triggers hover on a new
        // card and makes the selection jump. Only explicit navigation
        // re-centers the view.
        if (recenter !== false) root.keepSelectionVisible()
        return true
    }

    function cycle(delta) {
        var ids = root.workspaceIds()
        if (ids.length === 0) return "empty"

        root.noteInteraction()
        var index = root.selectedIndex()
        // Wrap around so SUPER+TAB from the last workspace returns to the
        // first (and SUPER+SHIFT+TAB from the first goes to the last). The
        // pure wrap policy is shared with the unit tests via WorkspaceSelection.
        var nextIndex = WorkspaceSelection.nextIndex(index, delta, ids.length)
        if (nextIndex < 0) return "empty"
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

    // Alt+Tab-style commit-on-release. The keybinding provider observes the
    // SUPER release (a declarative Hyprland release bind cannot target the
    // modifier; see dotfiles/hypr/keybind.lua) and invokes this method through
    // the bounded plugin IPC. Activation stays in this plugin controller and
    // shares the same path as Enter, so both routes converge on
    // activateWorkspace(). A release while the overview is closed, or one whose
    // selection is stale, is ignored.
    function release() {
        if (WorkspaceSelection.isQuickTap(root.isOpen, root.interactionRevealed, root.interactionNavigated)) {
            // Fast ALT+TAB-style tap: the overlay was never revealed, so flip
            // straight to the previously focused workspace. close() also stops
            // the reveal timer so it cannot fire after release.
            revealTimer.stop()
            root.close()
            return root.toggleToPrevious()
        }
        var id = WorkspaceSelection.releaseCommitWorkspace(
            root.isOpen,
            root.selectedWorkspaceId,
            root.workspaceIds())
        if (id === 0) return "ignored"
        return root.activateWorkspace(id)
    }

    function open(payloadJson) {
        if (root.isOpen) return root.cycle(1)

        if (typeof Hyprland.refreshMonitors === "function") Hyprland.refreshMonitors()
        if (typeof Hyprland.refreshWorkspaces === "function") Hyprland.refreshWorkspaces()
        if (typeof Hyprland.refreshToplevels === "function") Hyprland.refreshToplevels()
        root.modelRevision++
        root.seedSelection()
        // Do NOT re-seed the focus pair here. A rapid second tap depends on the
        // optimistic swap in toggleToPrevious(); re-reading a focus signal that
        // has not arrived yet would clobber that swap. The pair is maintained
        // only by recordFocusedWorkspace() from focus events and startup.
        root.interactionRevealed = false
        root.interactionNavigated = false
        root.isOpen = true
        // Deferred reveal: the overlay stays invisible until the hold threshold
        // elapses. A second press or any navigation reveals immediately through
        // noteInteraction().
        revealTimer.restart()
        Qt.callLater(function() {
            if (!root.isOpen) return
            // refreshWorkspaces may publish its model on the next event turn;
            // seed once more so the first visible selection is never stale.
            root.modelRevision++
            root.seedSelection()
            if (root.interactionRevealed) root.focusSurface()
        })
        return "ok"
    }

    // Second half of the deferred reveal: the overlay becomes visible and takes
    // keyboard focus only after the hold threshold elapses or as soon as the
    // user navigates. Separating reveal from open() is what makes a fast tap
    // invisible.
    function revealInteraction() {
        if (!root.isOpen || root.interactionRevealed) return
        root.interactionRevealed = true
        // Defer focus one event turn, matching the original open() path: the
        // visible binding has to map the surface before it can hold keyboard
        // focus.
        Qt.callLater(function() { root.focusSurface() })
    }

    // Called for every explicit navigation during an interaction. Navigation
    // always reveals immediately and marks the interaction as navigated so the
    // eventual SUPER release commits (multi-tab cycling) instead of being
    // mistaken for a quick tap.
    function noteInteraction() {
        root.interactionNavigated = true
        root.revealInteraction()
    }

    // Quick-tap toggle. The pair is updated BEFORE activation because the focus
    // change arrives asynchronously: flipping first keeps a rapid second tap
    // aimed at the workspace we just left.
    function toggleToPrevious() {
        var target = WorkspaceSelection.toggleTarget(
            root.previousWorkspaceId,
            root.activeWorkspaceId,
            root.knownWorkspaceIds())
        if (target === 0) return "ignored"
        root.previousWorkspaceId = root.activeWorkspaceId
        root.activeWorkspaceId = target
        return root.activateWorkspace(target)
    }

    function close() {
        root.isOpen = false
        root.wheelAccumulator = 0
        revealTimer.stop()
        root.interactionRevealed = false
        root.interactionNavigated = false
        return "closed"
    }

    function toggle(payloadJson) {
        if (root.isOpen) return root.cycle(1)
        return root.open(payloadJson || "{}")
    }

    function isVisible() {
        return root.isOpen
    }

    // Deferred-reveal timer. open() starts it; a quick tap stops it before it
    // fires. The interval is the pinned pure-JS threshold so the policy and the
    // timer cannot drift apart.
    Timer {
        id: revealTimer
        interval: WorkspaceSelection.TAP_HOLD_THRESHOLD_MS
        repeat: false
        onTriggered: root.revealInteraction()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            root.modelRevision++
        }
        function onFocusedWorkspaceChanged() {
            root.modelRevision++
            root.recordFocusedWorkspace()
            if (!root.isOpen) root.seedSelection()
        }
    }

    Component.onCompleted: root.recordFocusedWorkspace()

    PanelWindow {
        id: overviewWindow

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "aurelia-workspace-overview"
        WlrLayershell.keyboardFocus: (root.isOpen && root.interactionRevealed)
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.OnDemand
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // A tap never renders the overlay; only a held or navigated interaction
        // makes the resident surface visible and focusable.
        visible: root.isOpen && root.interactionRevealed

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

            // Mouse wheel / trackpad scroll cycles the workspace selection.
            // Accumulate the delta so a single notch (120) advances one
            // workspace even when the device reports several small events.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) {
                    root.wheelAccumulator += event.angleDelta.y
                    while (Math.abs(root.wheelAccumulator) >= 120) {
                        root.cycle(root.wheelAccumulator > 0 ? -1 : 1)
                        root.wheelAccumulator -= root.wheelAccumulator > 0 ? 120 : -120
                    }
                    event.accepted = true
                }
            }

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
                            font.family: Theme.fontFamilyResolved
                            font.pixelSize: Theme.fontSizeXl
                            font.weight: Theme.fontWeightMedium
                        }

                        Text {
                            text: "SUPER + TAB"
                            color: Theme.textMuted
                            font.family: Theme.fontFamilyResolved
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
                        interactive: false
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        preferredHighlightBegin: Math.max(0, (width - root.workspaceCardWidth) / 2)
                        preferredHighlightEnd: Math.max(root.workspaceCardWidth, (width + root.workspaceCardWidth) / 2)
                        highlightMoveDuration: Theme.durationNormal
                        leftMargin: root.workspaceListSideMargin
                        rightMargin: root.workspaceListSideMargin
                        // Root owns selection. Keeping the view's initial
                        // index unset prevents ListView startup from choosing
                        // workspace 1 before the focus seed is applied.
                        currentIndex: -1
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
                            onActivated: root.activateWorkspace(workspaceId)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Selected: Workspace " + String(root.selectedWorkspaceId) +
                                "  ·  Tab / arrows to browse  ·  Enter or release Super to open  ·  Esc to close"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamilyResolved
                            font.pixelSize: Theme.fontSizeXs
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    onIsOpenChanged: {
        if (root.isOpen && root.interactionRevealed)
            Qt.callLater(function() { root.focusSurface() })
    }
}
