import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "ui"
import "NotificationLogic.js" as Logic

// Resident notification daemon. It keeps live Quickshell Notification objects
// in a private map and exposes only bounded snapshots to UI models and state
// files. The service owns its own popups, history, and Do Not Disturb state.
Item {
    id: service

    property var shell: null
    property var bar: null
    property var aureliaPath: ""
    property var manifest: ({})
    property var pluginRegistry: null

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateHomeOverride: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string stateHome: stateHomeOverride.charAt(0) === "/" && stateHomeOverride !== "/"
        ? stateHomeOverride
        : (home.charAt(0) === "/" && home !== "/" ? home + "/.local/state" : "")
    readonly property string stateDir: stateHome !== "" ? stateHome + "/aurelia" : ""
    readonly property string settingsPath: stateDir !== "" ? stateDir + "/notifications.json" : ""
    readonly property string historyPath: stateDir !== "" ? stateDir + "/notification-history.json" : ""
    readonly property int historyLimit: 50
    readonly property int barClearance: bar && bar.position === "top"
        ? Math.max(26, Number(bar.barSize || 26)) + Theme.spacingMd
        : Theme.spacingMd
    readonly property string serverStatus: !notificationBusProbeComplete
        ? "Checking notification service"
        : notificationBusAvailable
            ? "Desktop notifications active"
            : notificationBusOwnerFound
                ? "Another notification service owns desktop delivery"
                : "Notification service unavailable"

    property bool doNotDisturb: false
    property bool centerOpen: false
    property string centerMode: "active"
    property bool stateDirectoryReady: false
    property bool settingsLoaded: false
    property bool historyLoaded: false
    property bool settingsDirty: false
    property bool historyDirty: false
    property bool stateSaveQueued: false
    property var historyEntries: []
    property var liveRefs: ({})
    property bool notificationBusAvailable: false
    property bool notificationBusProbeComplete: false
    property bool notificationBusOwnerFound: false
    property int notificationBusProbeAttempts: 0

    property alias activeModel: activeNotificationsModel
    property alias historyModel: historyEntriesModel

    ListModel { id: activeNotificationsModel }
    ListModel { id: historyEntriesModel }

    property FileView settingsFile: FileView {
        path: service.settingsPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false

        onLoaded: service.loadSettings(text())
        onLoadFailed: service.loadSettings("")
        onSaveFailed: console.error("[NOTIFICATIONS] settings_save_failed")
    }

    property FileView historyFile: FileView {
        path: service.historyPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false

        onLoaded: service.loadHistory(text())
        onLoadFailed: service.loadHistory("")
        onSaveFailed: console.error("[NOTIFICATIONS] history_save_failed")
    }

    property Timer stateSaveTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: service.flushState()
    }

    property Process ensureStateDirProcess: Process {
        command: service.stateDir !== ""
            ? ["/usr/bin/mkdir", "-p", service.stateDir]
            : ["/usr/bin/false"]
        running: false

        onExited: function(code) {
            if (code !== 0) {
                console.error("[NOTIFICATIONS] state_directory_failed code=" + code)
                return
            }
            service.stateDirectoryReady = true
            if (service.stateSaveQueued) service.stateSaveTimer.restart()
        }
    }

    property Timer notificationBusRetryTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: service.probeNotificationBus()
    }

    property Process notificationBusProbe: Process {
        command: [
            "/usr/bin/timeout", "--kill-after=1s", "2s",
            "/usr/bin/busctl", "--user", "list", "--no-legend"
        ]
        running: false
        stdout: StdioCollector {
            id: notificationBusProbeStdout
            waitForEnd: true
        }
        stderr: StdioCollector { id: notificationBusProbeStderr }

        onExited: function(code) {
            var owned = code === 0 && Logic.hasBusName(
                notificationBusProbeStdout.text,
                "org.freedesktop.Notifications"
            )

            // Retry briefly so a just-stopped Aurelia instance can release the
            // bus during a restart; a persistent external owner is reported as
            // state, not as a noisy failed registration attempt.
            if (owned && service.notificationBusProbeAttempts < 3) {
                service.notificationBusRetryTimer.restart()
                return
            }

            service.notificationBusProbeComplete = true
            service.notificationBusOwnerFound = owned
            service.notificationBusAvailable = code === 0 && !owned
            if (service.notificationBusAvailable) {
                console.info("[NOTIFICATIONS] server.bus_available")
                notificationServerLoader.active = true
            } else if (owned) {
                console.info("[NOTIFICATIONS] server.bus_owned external=true")
            } else {
                console.info("[NOTIFICATIONS] server.probe_unavailable code=" + code)
            }
        }
    }

    function rebuildHistoryModel() {
        historyEntriesModel.clear()
        for (var i = 0; i < historyEntries.length; i++) historyEntriesModel.append(historyEntries[i])
    }

    function loadSettings(raw) {
        if (settingsLoaded) return
        var parsed = Logic.parseSettings(raw)
        if (!parsed.ok) console.info("[NOTIFICATIONS] settings_invalid using_defaults")
        if (!settingsDirty && parsed.dnd !== null) doNotDisturb = parsed.dnd
        settingsLoaded = true
        if (stateSaveQueued && stateDirectoryReady && historyLoaded) stateSaveTimer.restart()
    }

    function loadHistory(raw) {
        if (historyLoaded) return
        var diskEntries = Logic.parseHistory(raw, historyLimit)
        if (historyDirty) {
            var merged = historyEntries.concat(diskEntries)
            merged.sort(function(left, right) { return Number(right.timestamp || 0) - Number(left.timestamp || 0) })
            historyEntries = merged.slice(0, historyLimit)
        } else {
            historyEntries = diskEntries
        }
        rebuildHistoryModel()
        historyLoaded = true
        if (stateSaveQueued && stateDirectoryReady && settingsLoaded) stateSaveTimer.restart()
    }

    function queueStateSave() {
        stateSaveQueued = true
        if (stateDirectoryReady) stateSaveTimer.restart()
    }

    function flushState() {
        if (!stateDirectoryReady || stateDir === "" || !settingsLoaded || !historyLoaded) return
        stateSaveQueued = false
        settingsFile.setText(JSON.stringify({ version: 1, dnd: doNotDisturb }, null, 2) + "\n")
        historyFile.setText(JSON.stringify({ version: 1, notifications: historyEntries }, null, 2) + "\n")
    }

    function setDnd(value) {
        var next = !!value
        if (doNotDisturb === next) return
        doNotDisturb = next
        settingsDirty = true
        queueStateSave()
        if (bar && typeof bar.callWidget === "function") {
            bar.callWidget("aurelia.notifications", "refreshDnd", "")
        }
        console.info("[NOTIFICATIONS] dnd.changed state=" + (next ? "on" : "off"))
    }

    function isTransient(notification) {
        try { return !!(notification && notification.hints && notification.hints.transient) }
        catch (error) { return false }
    }

    function recordHistory(snapshot) {
        var entry = Logic.historyEntry(snapshot)
        var next = historyEntries.slice()
        next.unshift(entry)
        historyEntries = next.slice(0, historyLimit)
        historyDirty = true
        rebuildHistoryModel()
        queueStateSave()
    }

    function removeActiveById(originalId) {
        for (var i = activeNotificationsModel.count - 1; i >= 0; i--) {
            var row = activeNotificationsModel.get(i)
            if (row && row.originalId === originalId) activeNotificationsModel.remove(i)
        }
    }

    function updateActive(notification, originalId) {
        if (!notification || liveRefs[originalId] !== notification) return
        var updated
        try { updated = Logic.snapshotOf(notification, 0) }
        catch (error) { return }
        var roles = ["app", "appIcon", "summary", "body", "image", "actions", "urgency", "expireTimeout"]
        for (var i = 0; i < activeNotificationsModel.count; i++) {
            var row = activeNotificationsModel.get(i)
            if (!row || row.originalId !== originalId) continue
            for (var r = 0; r < roles.length; r++) activeNotificationsModel.setProperty(i, roles[r], updated[roles[r]])
            return
        }
    }

    function watchForUpdates(notification, originalId) {
        var signals = ["summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged", "imageChanged", "actionsChanged", "urgencyChanged", "expireTimeoutChanged"]
        function refresh() { service.updateActive(notification, originalId) }
        for (var i = 0; i < signals.length; i++) {
            var signal = notification[signals[i]]
            if (signal && typeof signal.connect === "function") signal.connect(refresh)
        }
    }

    function handleNotification(notification) {
        if (!notification) return
        try { notification.tracked = true } catch (error) { return }

        var snapshot
        try { snapshot = Logic.snapshotOf(notification, Date.now()) }
        catch (error) { notification.tracked = false; return }
        var originalId = snapshot.originalId
        var previous = liveRefs[originalId]
        liveRefs[originalId] = notification
        if (previous && previous !== notification) {
            try {
                if (typeof previous.dismiss === "function") previous.dismiss()
                previous.tracked = false
            } catch (replaceError) {}
        }

        if (notification.closed && typeof notification.closed.connect === "function") {
            notification.closed.connect(function() {
                if (service.liveRefs[originalId] !== notification) return
                delete service.liveRefs[originalId]
                for (var i = service.activeModel.count - 1; i >= 0; i--) {
                    var row = service.activeModel.get(i)
                    if (row && row.originalId === originalId) service.removeAt(i, "dismiss")
                }
            })
        }

        if (doNotDisturb && !Logic.shouldBypassDnd(notification, 2)) {
            if (!Logic.isEphemeralApp(snapshot.app) && !isTransient(notification)) recordHistory(snapshot)
            delete liveRefs[originalId]
            try { notification.tracked = false } catch (releaseError) {}
            console.info("[NOTIFICATIONS] notification.silenced app=" + snapshot.app)
            return
        }

        removeActiveById(originalId)
        activeNotificationsModel.insert(0, snapshot)
        watchForUpdates(notification, originalId)
        console.info("[NOTIFICATIONS] notification.received app=" + snapshot.app)
    }

    function removeAt(index, reason) {
        if (index < 0 || index >= activeNotificationsModel.count) return
        var entry = activeNotificationsModel.get(index)
        var originalId = entry ? entry.originalId : -1
        var reference = liveRefs[originalId]
        activeNotificationsModel.remove(index)
        if (entry) recordHistory(entry)
        if (reference) {
            try {
                if (reason === "expire" && typeof reference.expire === "function") reference.expire()
                else if (typeof reference.dismiss === "function") reference.dismiss()
            } catch (error) {
                // A sender may have already closed the object.
            }
        }
        if (liveRefs[originalId] === reference) delete liveRefs[originalId]
    }

    function dismissAt(index) { removeAt(index, "dismiss") }
    function expireAt(index) { removeAt(index, "expire") }

    function dismissAll() {
        while (activeNotificationsModel.count > 0) removeAt(0, "dismiss")
        return "ok"
    }

    function invokeAction(index, identifier) {
        if (index < 0 || index >= activeNotificationsModel.count) return "none"
        var entry = activeNotificationsModel.get(index)
        var reference = entry ? liveRefs[entry.originalId] : null
        if (!reference || !reference.actions) return "unavailable"
        for (var i = 0; i < reference.actions.length; i++) {
            var action = reference.actions[i]
            if (action && action.identifier === identifier && typeof action.invoke === "function") {
                action.invoke()
                removeAt(index, "action")
                return "ok"
            }
        }
        return "not-found"
    }

    function clearHistory() {
        historyEntries = []
        historyDirty = true
        rebuildHistoryModel()
        queueStateSave()
        return "ok"
    }

    function openCenter() {
        centerMode = "active"
        centerOpen = true
        return "ok"
    }

    function showHistory() {
        centerMode = "history"
        centerOpen = true
        return "ok"
    }

    function closeCenter() {
        centerOpen = false
        return "ok"
    }

    function toggleCenter() {
        if (centerOpen) return closeCenter()
        return openCenter()
    }

    function dndState() { return doNotDisturb ? "on" : "off" }

    function toggleDnd() {
        setDnd(!doNotDisturb)
        return dndState()
    }

    function setDndFromText(value) {
        var text = String(value || "").toLowerCase()
        setDnd(text === "true" || text === "1" || text === "on" || text === "yes")
        return dndState()
    }

    // Stable in-process API for first-party capture previews. It is deliberately
    // a service call rather than a second notification backend; Screenshot
    // publishes only after its capture process exits successfully.
    function publishScreenshot(path) {
        var snapshot = Logic.screenshotSnapshot(path, Date.now())
        if (!snapshot) return "invalid-path"
        activeNotificationsModel.insert(0, snapshot)
        console.info("[NOTIFICATIONS] screenshot.published")
        return "ok"
    }

    function open(payloadJson) { return openCenter() }
    function close() { return closeCenter() }
    function toggle(payloadJson) { return toggleCenter() }
    function isVisible() { return centerOpen }

    IpcHandler {
        target: "aurelia.notifications"

        function ping(): string { return "ok" }
        function open(): void { service.openCenter() }
        function close(): void { service.closeCenter() }
        function toggle(): void { service.toggleCenter() }
        function isVisible(): string { return service.isVisible() ? "true" : "false" }
        function dndState(): string { return service.dndState() }
        function toggleDnd(): string { return service.toggleDnd() }
        function setDnd(value: string): string { return service.setDndFromText(value) }
        function showHistory(): string { return service.showHistory() }
        function clear(): string { return service.clearHistory() }
        function dismissAll(): string { return service.dismissAll() }
        function publishScreenshot(path: string): string { return service.publishScreenshot(path) }
    }

    Loader {
        id: notificationServerLoader
        active: false
        asynchronous: false
        source: Qt.resolvedUrl("NotificationServerHost.qml")

        onLoaded: {
            if (item && "service" in item) item.service = service
            console.info("[NOTIFICATIONS] server.registered")
        }
        onStatusChanged: {
            if (status === Loader.Error) console.error("[NOTIFICATIONS] server.load_failed")
        }
    }

    property bool _startupStarted: false
    Component.onCompleted: {
        if (_startupStarted) return
        _startupStarted = true
        probeNotificationBus()
        if (stateDir === "") {
            console.error("[NOTIFICATIONS] state_directory_unavailable")
            return
        }
        ensureStateDirProcess.running = true
        Qt.callLater(function() {
            settingsFile.reload()
            historyFile.reload()
        })
    }

    function probeNotificationBus() {
        if (notificationBusProbe.running || notificationBusProbeComplete) return
        notificationBusProbeAttempts++
        notificationBusProbe.running = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: popupWindow
            required property var modelData
            screen: modelData
            visible: service.activeModel.count > 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "aurelia-notifications"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: popupColumn }

            ColumnLayout {
                id: popupColumn
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: service.barClearance
                anchors.rightMargin: Theme.spacingMd
                spacing: Theme.spacingSm

                Repeater {
                    model: service.activeModel

                    delegate: Item {
                        id: popupSlot
                        required property int index
                        required property var app
                        required property var appIcon
                        required property var summary
                        required property var body
                        required property var image
                        required property var actions
                        required property int urgency
                        required property double expireTimeout

                        Layout.preferredWidth: notificationToast.implicitWidth
                        Layout.preferredHeight: notificationToast.implicitHeight
                        implicitWidth: notificationToast.implicitWidth
                        implicitHeight: notificationToast.implicitHeight

                        property int remainingLifetime: Math.round(Logic.durationFor(popupSlot.urgency, popupSlot.expireTimeout))
                        property double timerStartedAt: 0

                        function startLifetime() {
                            if (remainingLifetime <= 0 || popupSlot.hovered) return
                            timerStartedAt = Date.now()
                            expiryTimer.interval = remainingLifetime
                            expiryTimer.restart()
                        }

                        function pauseLifetime() {
                            if (!expiryTimer.running || remainingLifetime <= 0) return
                            remainingLifetime = Math.max(1, remainingLifetime - (Date.now() - timerStartedAt))
                            expiryTimer.stop()
                        }

                        function restartLifetime() {
                            remainingLifetime = Math.round(Logic.durationFor(popupSlot.urgency, popupSlot.expireTimeout))
                            startLifetime()
                        }

                        readonly property bool hovered: notificationToast.hovered

                        onHoveredChanged: hovered ? pauseLifetime() : startLifetime()
                        onSummaryChanged: restartLifetime()
                        onBodyChanged: restartLifetime()
                        onImageChanged: restartLifetime()
                        Component.onCompleted: startLifetime()

                        Timer {
                            id: expiryTimer
                            repeat: false
                            onTriggered: service.expireAt(popupSlot.index)
                        }

                        NotificationToast {
                            id: notificationToast
                            anchors.fill: parent
                            app: popupSlot.app
                            appIcon: popupSlot.appIcon
                            summary: popupSlot.summary
                            body: popupSlot.body
                            image: popupSlot.image
                            actions: popupSlot.actions
                            urgency: popupSlot.urgency
                            onDismissed: service.dismissAt(popupSlot.index)
                            onActivated: service.dismissAt(popupSlot.index)
                            onActionInvoked: function(identifier) { service.invokeAction(popupSlot.index, identifier) }
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: centerPanel
        active: service.centerOpen
        asynchronous: false
        source: Qt.resolvedUrl("ui/NotificationCenterPanel.qml")

        onLoaded: {
            if (item && "service" in item) item.service = service
        }
        onStatusChanged: {
            if (status === Loader.Error) console.error("[NOTIFICATIONS] center.load_failed")
        }
    }
}
