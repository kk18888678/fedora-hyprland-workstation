import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "ui"
import "NotificationLogic.js" as Logic
import "NotificationFileLogic.js" as FileLogic

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
    readonly property string popupStateDir: stateDir !== "" ? stateDir + "/notifications/" : ""
    readonly property string historyDir: popupStateDir !== "" ? popupStateDir + "history/" : ""
    readonly property string imagesDir: popupStateDir !== "" ? popupStateDir + "images/" : ""
    // Kept as a read-only migration source for the pre-reference JSON history.
    readonly property string historyPath: stateDir !== "" ? stateDir + "/notification-history.json" : ""
    readonly property int historyLimit: 10
    readonly property int barClearance: bar && bar.position === "top"
        ? Math.max(26, Number(bar.barSize || 26)) + Theme.spacingMd
        : Theme.spacingMd
    readonly property string serverStatus: !notificationBusProbeComplete
        && !notificationBusOwnerFound
        ? "Checking notification service"
        : notificationBusAvailable
            ? "System notifications active"
            : notificationBusOwnerFound
                ? "System alerts handled by another service"
                : "System notification service unavailable"

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
    property var liveSnapshots: ({})
    property bool notificationBusAvailable: false
    property bool notificationBusProbeComplete: false
    property bool notificationBusOwnerFound: false
    property int notificationBusProbeAttempts: 0
    property bool notificationServerLoaded: false
    property bool notificationServerRestartQueued: false
    property var restoredPopups: ({})
    property var popupFileQueue: []
    property var runningPopupFileJob: null
    readonly property int popupFileMaxAttempts: 3
    property bool historyDirectoryLoaded: false
    property bool legacyHistoryMigrationQueued: false

    property alias activeModel: activeNotificationsModel
    // Inbox rows remain until an explicit user action. The popup model is a
    // separate transient presentation queue whose expiry must never archive
    // the corresponding Inbox row.
    property alias popupModel: popupNotificationsModel
    property alias historyModel: historyEntriesModel

    ListModel { id: activeNotificationsModel }
    ListModel { id: popupNotificationsModel }
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
        onSaved: console.info("[NOTIFICATIONS] settings.saved")
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
        onSaved: console.info("[NOTIFICATIONS] history.saved count=" + service.historyEntries.length)
        onSaveFailed: console.error("[NOTIFICATIONS] history_save_failed")
    }

    property Process ensureStateDirProcess: Process {
        command: service.stateDir !== ""
            ? ["/usr/bin/mkdir", "-p", service.stateDir, service.popupStateDir, service.historyDir, service.imagesDir]
            : ["/usr/bin/false"]
        running: false

        onExited: function(code) {
            if (code !== 0) {
                console.error("[NOTIFICATIONS] state_directory_failed code=" + code)
                return
            }
            service.stateDirectoryReady = true
            service.readHistoryDirectory()
            service.readPopupDirectory()
            service.sweepOrphanImages()
            if (service.stateSaveQueued) service.flushState()
        }
    }
    function enqueuePopupFileJob(command, done, label) {
        popupFileQueue = popupFileQueue.concat([{
            command: command,
            done: done || null,
            label: String(label || "notification-state"),
            attempts: 0
        }])
        runNextPopupFileJob()
    }
    function runNextPopupFileJob() {
        if (popupFileProcess.running || popupFileRetryTimer.running || popupFileQueue.length === 0) return
        var job = popupFileQueue[0]
        popupFileQueue = popupFileQueue.slice(1)
        runningPopupFileJob = job
        popupFileProcess.command = job.command
        popupFileProcess.running = true
    }
    property Timer popupFileRetryTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: service.runNextPopupFileJob()
    }
    property Process popupFileProcess: Process {
        running: false
        onExited: function(code) {
            var job = service.runningPopupFileJob
            service.runningPopupFileJob = null
            if (!job) {
                service.runNextPopupFileJob()
                return
            }
            if (code !== 0 && job.attempts < service.popupFileMaxAttempts) {
                job.attempts++
                service.popupFileQueue = [job].concat(service.popupFileQueue)
                console.warn("[NOTIFICATIONS] file_job_retry label=" + job.label +
                    " attempt=" + job.attempts + " code=" + code)
                service.popupFileRetryTimer.interval = Math.min(2000, 250 * job.attempts)
                service.popupFileRetryTimer.restart()
                return
            }
            if (code !== 0) {
                console.error("[NOTIFICATIONS] file_job_failed label=" + job.label + " code=" + code)
            }
            if (job.done) {
                try { job.done(code === 0) }
                catch (error) { console.warn("[NOTIFICATIONS] file_job_callback_failed label=" + job.label) }
            }
            service.runNextPopupFileJob()
        }
    }
    property Process historyDirectoryReadProcess: Process {
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: service.loadHistoryDirectory(historyDirectoryReadProcess.stdout.text)
        }
        onExited: function(code) {
            if (code !== 0) console.error("[NOTIFICATIONS] history_directory_read_failed code=" + code)
        }
    }
    property Process restorePopupsProcess: Process {
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: service.restorePopups(restorePopupsProcess.stdout.text)
        }
        onExited: function(code) {
            if (code !== 0) console.error("[NOTIFICATIONS] popup_directory_read_failed code=" + code)
        }
    }
    function persistPopupFile(snapshot) {
        if (!snapshot || popupStateDir === "") return
        var fileName = Logic.popupFileName(snapshot)
        if (fileName === "") {
            console.error("[NOTIFICATIONS] popup.persist_skipped reason=invalid_identity")
            return
        }
        var persistable = Logic.persistablePopup(snapshot, imagesDir)
        persistable.json = Logic.serializePopup(persistable.entry, 1)
        enqueuePopupFileJob(FileLogic.persistPopup(
            persistable, popupStateDir, imagesDir, fileName),
            null, "popup.persist:" + fileName)
    }

    function archivePopupFileFor(snapshot) {
        if (!snapshot || historyDir === "") return
        var fileName = Logic.popupFileName(snapshot)
        if (fileName === "") {
            console.error("[NOTIFICATIONS] popup.archive_skipped reason=invalid_identity")
            return
        }
        enqueuePopupFileJob(FileLogic.archivePopup(
            historyDir, popupStateDir, imagesDir, fileName, historyLimit),
            null, "popup.archive:" + fileName)
    }

    function writeHistoryFile(snapshot) {
        if (!snapshot || historyDir === "") return
        var fileName = Logic.popupFileName(snapshot)
        if (fileName === "") {
            console.error("[NOTIFICATIONS] history.write_skipped reason=invalid_identity")
            return
        }
        var persistable = Logic.persistablePopup(snapshot, imagesDir)
        persistable.json = Logic.serializePopup(persistable.entry, 1)
        enqueuePopupFileJob(FileLogic.writeHistory(
            persistable, historyDir, imagesDir, fileName, historyLimit),
            null, "history.write:" + fileName)
    }

    function clearHistoryFiles() {
        if (historyDir === "") return
        enqueuePopupFileJob(FileLogic.clearHistory(historyDir, imagesDir), null, "history.clear")
    }

    function sweepOrphanImages() {
        if (imagesDir === "") return
        enqueuePopupFileJob(FileLogic.sweepImages(popupStateDir, historyDir, imagesDir), null, "images.sweep")
    }

    function deletePopupFileFor(snapshot) {
        if (!snapshot || popupStateDir === "") return
        var fileName = Logic.popupFileName(snapshot)
        if (fileName === "") return
        enqueuePopupFileJob(FileLogic.deletePopup(
            popupStateDir, imagesDir, fileName),
            null, "popup.delete:" + fileName)
    }

    function readHistoryDirectory() {
        if (historyDir === "") return
        historyDirectoryReadProcess.command = FileLogic.readDirectory(historyDir)
        historyDirectoryReadProcess.running = true
    }

    function readPopupDirectory() {
        if (popupStateDir === "") return
        restorePopupsProcess.command = FileLogic.readDirectory(popupStateDir)
        restorePopupsProcess.running = true
    }

    property Timer notificationBusRetryTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: service.probeNotificationBus()
    }
    property Timer notificationBusHealthTimer: Timer {
        interval: 2000
        repeat: true
        onTriggered: service.probeNotificationBus()
    }
    property Timer notificationServerRestartTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: {
            service.notificationServerRestartQueued = false
            service.notificationServerLoaded = false
            service.notificationServerLoader.active = false
            Qt.callLater(function() {
                if (service._startupStarted && !service.notificationBusOwnerFound) {
                    service.notificationServerLoader.active = true
                }
            })
        }
    }

    // Notification actions may focus an existing application window or create
    // one asynchronously. Keep workspace routing bounded and independent from
    // the sender's D-Bus action so an uncooperative application cannot keep the
    // resident shell waiting indefinitely.
    readonly property int workspaceRouteMaxAttempts: 30
    property var pendingWorkspaceRoute: null
    property int workspaceRouteAttempts: 0
    property Timer workspaceRouteTimer: Timer {
        interval: 80
        repeat: false
        onTriggered: service.resolvePendingWorkspaceRoute()
    }

    property Process notificationBusProbe: Process {
        command: [
            "/usr/bin/timeout", "--kill-after=1s", "2s",
            "/usr/bin/busctl", "--user", "status", "org.freedesktop.Notifications"
        ]
        running: false
        stdout: StdioCollector {
            id: notificationBusProbeStdout
            waitForEnd: true
        }
        stderr: StdioCollector { id: notificationBusProbeStderr }

        onExited: function(code) {
            var ownerPid = code === 0 ? Logic.busOwnerPid(notificationBusProbeStdout.text) : 0
            var shellPid = Number(Quickshell.processId)
            var wasAvailable = service.notificationBusAvailable
            var wasExternal = service.notificationBusOwnerFound
            var wasProbeComplete = service.notificationBusProbeComplete
            var ownedByAurelia = ownerPid > 0 && shellPid > 0 && ownerPid === shellPid
            var externalOwner = ownerPid > 0 && !ownedByAurelia
            service.notificationBusProbeComplete = true
            service.notificationBusOwnerFound = externalOwner
            service.notificationBusAvailable = ownedByAurelia

            if (ownedByAurelia) {
                service.notificationBusRetryTimer.interval = 250
                service.notificationBusRetryTimer.stop()
                service.notificationServerRestartTimer.stop()
                service.notificationServerRestartQueued = false
                if (!wasAvailable) {
                    console.info("[NOTIFICATIONS] server.bus_available owner_pid=" + ownerPid)
                    console.info("[NOTIFICATIONS] server.registered")
                }
                return
            }

            if (externalOwner) {
                service.notificationServerRestartTimer.stop()
                service.notificationServerRestartQueued = false
                if (!wasExternal || wasAvailable) {
                    console.warn("[NOTIFICATIONS] server.bus_owned external=true owner_pid=" + ownerPid)
                }
                service.notificationServerLoaded = false
                service.notificationServerLoader.active = false
                service.notificationBusRetryTimer.interval = 2000
                service.notificationBusRetryTimer.restart()
            } else {
                if (wasAvailable || wasExternal || !wasProbeComplete) {
                    console.warn("[NOTIFICATIONS] server.bus_unavailable code=" + code)
                }
                service.notificationBusRetryTimer.interval = 1000
                service.notificationBusRetryTimer.restart()
                service.scheduleNotificationServerRestart()
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
        if (stateSaveQueued && stateDirectoryReady && historyLoaded) flushState()
    }

    function loadHistory(raw) {
        if (historyLoaded) return
        var diskEntries = Logic.parseHistory(raw, historyLimit)
        var needsRewrite = String(raw || "").trim() !== "" && diskEntries.length === 0
        if (historyDirectoryLoaded || historyDirty) {
            mergeHistoryRows(diskEntries)
        } else {
            historyEntries = diskEntries
        }
        if (!legacyHistoryMigrationQueued && diskEntries.length > 0 && String(raw || "").trim() !== "") {
            legacyHistoryMigrationQueued = true
            for (var i = 0; i < diskEntries.length; i++) writeHistoryFile(diskEntries[i])
        }
        rebuildHistoryModel()
        historyLoaded = true
        if (needsRewrite) stateSaveQueued = true
        if (stateSaveQueued && stateDirectoryReady && settingsLoaded) flushState()
    }

    function mergeHistoryRows(rows) {
        var merged = historyEntries.slice()
        for (var i = 0; i < (rows || []).length; i++) {
            var candidate = rows[i]
            var exists = false
            for (var j = 0; j < merged.length; j++) {
                if (Logic.historyKey(merged[j]) === Logic.historyKey(candidate)) {
                    exists = true
                    break
                }
            }
            if (!exists) merged.push(candidate)
        }
        merged.sort(function(left, right) { return Number(right.timestamp || 0) - Number(left.timestamp || 0) })
        historyEntries = merged.slice(0, historyLimit)
        rebuildHistoryModel()
    }

    function loadHistoryDirectory(raw) {
        historyDirectoryLoaded = true
        mergeHistoryRows(Logic.historyRows(raw, [], 1, historyLimit))
    }

    function modelIndexByIdentity(model, originalId, timestamp) {
        if (!model) return -1
        var wantedId = String(originalId)
        var wantedTimestamp = Number(timestamp)
        if (!isFinite(wantedTimestamp)) return -1
        for (var i = 0; i < model.count; i++) {
            var row = model.get(i)
            if (row && String(row.originalId) === wantedId && Number(row.timestamp) === wantedTimestamp) return i
        }
        return -1
    }

    function removePopupByIdentity(originalId, timestamp) {
        for (var i = popupNotificationsModel.count - 1; i >= 0; i--) {
            var row = popupNotificationsModel.get(i)
            if (row && String(row.originalId) === String(originalId) && Number(row.timestamp) === Number(timestamp)) {
                popupNotificationsModel.remove(i)
                return true
            }
        }
        return false
    }

    function removePopupByOriginalId(originalId) {
        var removed = false
        for (var i = popupNotificationsModel.count - 1; i >= 0; i--) {
            var row = popupNotificationsModel.get(i)
            if (!row || row.originalId !== originalId) continue
            popupNotificationsModel.remove(i)
            removed = true
        }
        return removed
    }

    function insertPopupSnapshot(snapshot) {
        if (!snapshot || !Logic.hasPopupIdentity(snapshot)) return
        if (modelIndexByIdentity(popupNotificationsModel, snapshot.originalId, snapshot.timestamp) >= 0) return
        popupNotificationsModel.insert(0, snapshot)
    }

    function updateModelRows(model, updated, originalId) {
        if (!model || !updated) return 0
        var roles = ["app", "appIcon", "desktopEntry", "summary", "body", "image", "glyph", "execArgv", "actions", "defaultActionText", "urgency", "expireTimeout", "deadline", "transient"]
        var changed = 0
        for (var i = 0; i < model.count; i++) {
            var row = model.get(i)
            if (!row || row.originalId !== originalId) continue
            updated.id = row.id
            updated.originalId = row.originalId
            updated.timestamp = row.timestamp
            for (var r = 0; r < roles.length; r++) model.setProperty(i, roles[r], updated[roles[r]])
            changed++
        }
        return changed
    }

    function isRestoredPopup(entry) {
        var fileName = entry ? Logic.popupFileName(entry) : ""
        return fileName !== "" && !!restoredPopups[fileName]
    }

    function restorePopups(raw) {
        var entries = Logic.parsePopupFiles(raw, 1)
        var now = Date.now()
        var live = []
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i]
            var duration = Logic.durationFor(entry.urgency, entry.expireTimeout, entry.app, entry.desktopEntry, entry.appIcon)
            var manualInbox = isManualInboxEntry(entry)
            if (!manualInbox && Logic.popupExpired(entry, duration, now)) {
                archivePopupFileFor(entry)
                continue
            }
            if (manualInbox) {
                entry.deadline = 0
            }
            // Restored Inbox rows survive a restart. Only their passive popup
            // gets a fresh bounded lifetime; the Inbox row remains user-owned.
            if (duration > 0) entry.expireTimeout = duration
            if (manualInbox) persistPopupFile(entry)
            live.push(entry)
        }
        if (live.length === 0) return

        Qt.callLater(function() {
            for (var j = 0; j < live.length; j++) {
                var restored = live[j]
                restoredPopups[Logic.popupFileName(restored)] = true
                if (modelIndexByIdentity(activeNotificationsModel, restored.originalId, restored.timestamp) < 0) {
                    activeNotificationsModel.append(restored)
                }
                insertPopupSnapshot(restored)
            }
        })
    }

    function queueStateSave() {
        stateSaveQueued = true
        if (stateDirectoryReady && settingsLoaded && historyLoaded) flushState()
    }

    function flushState() {
        if (!stateDirectoryReady || stateDir === "" || !settingsLoaded || !historyLoaded) return
        stateSaveQueued = false
        settingsFile.setText(JSON.stringify({ version: 3, dnd: doNotDisturb }, null, 2) + "\n")
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
        return Logic.transientFromNotification(notification)
    }

    function isManualInboxEntry(entry) {
        if (!entry) return false
        return Logic.isInboxPersistent(entry.app, entry.desktopEntry, entry.appIcon) ||
            (!entry.transient && !Logic.isEphemeralApp(entry.app))
    }

    function recordHistory(snapshot, persist) {
        var entry = Logic.historyEntry(snapshot)
        if (!Logic.isRenderableHistoryEntry(entry)) return
        var key = Logic.historyKey(entry)
        for (var i = 0; i < historyEntries.length; i++) {
            if (Logic.historyKey(historyEntries[i]) === key) return
        }
        var next = historyEntries.slice()
        next.unshift(entry)
        historyEntries = next.slice(0, historyLimit)
        historyDirty = true
        rebuildHistoryModel()
        if (persist !== false) writeHistoryFile(entry)
        queueStateSave()
        console.info("[NOTIFICATIONS] history.recorded key=" + key + " count=" + historyEntries.length)
    }

    function removeActiveById(originalId) {
        for (var i = activeNotificationsModel.count - 1; i >= 0; i--) {
            var row = activeNotificationsModel.get(i)
            if (row && row.originalId === originalId && !isRestoredPopup(row)) {
                if (!removePopupByIdentity(row.originalId, row.timestamp)) removePopupByOriginalId(originalId)
                activeNotificationsModel.remove(i)
                deletePopupFileFor(row)
            }
        }
    }

    function updateActive(notification, originalId) {
        if (!notification || liveRefs[originalId] !== notification) return
        var updated
        try { updated = Logic.snapshotOf(notification, Date.now()) }
        catch (error) { return }
        var activeChanged = updateModelRows(activeNotificationsModel, updated, originalId)
        var popupChanged = updateModelRows(popupNotificationsModel, updated, originalId)
        if (activeChanged > 0 || popupChanged > 0) {
            liveSnapshots[originalId] = updated
            persistPopupFile(updated)
        }
    }

    function watchForUpdates(notification, originalId) {
        var signals = ["summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged", "imageChanged", "actionsChanged", "hintsChanged", "urgencyChanged", "expireTimeoutChanged"]
        function refresh() { service.updateActive(notification, originalId) }
        for (var i = 0; i < signals.length; i++) {
            var signal = notification[signals[i]]
            if (signal && typeof signal.connect === "function") signal.connect(refresh)
        }
    }

    function handleNotification(notification) {
        if (!notification) return
        try { notification.tracked = true }
        catch (error) {
            console.error("[NOTIFICATIONS] notification.rejected reason=tracking_failed")
            return
        }

        var snapshot
        try { snapshot = Logic.snapshotOf(notification, Date.now()) }
        catch (error) {
            try { notification.tracked = false } catch (releaseError) {}
            console.error("[NOTIFICATIONS] notification.rejected reason=snapshot_failed")
            return
        }
        var originalId = snapshot.originalId
        var previous = liveRefs[originalId]
        liveRefs[originalId] = notification
        liveSnapshots[originalId] = snapshot
        if (previous && previous !== notification) {
            try {
                if (typeof previous.dismiss === "function") previous.dismiss()
                previous.tracked = false
            } catch (replaceError) {}
        }

        if (notification.closed && typeof notification.closed.connect === "function") {
            notification.closed.connect(function() {
                if (service.liveRefs[originalId] !== notification) return
                var closedSnapshot = service.liveSnapshots[originalId]
                if (closedSnapshot && service.isManualInboxEntry(closedSnapshot)) {
                    // Sender-side closure must not mark a normal Inbox row as
                    // read. It only removes the transient popup; the user can
                    // archive the retained row later.
                    service.removePopupByIdentity(originalId, closedSnapshot.timestamp)
                    console.info("[NOTIFICATIONS] notification.sender_closed inbox_retained app=" + closedSnapshot.app)
                } else {
                    var removed = false
                    for (var i = service.activeModel.count - 1; i >= 0; i--) {
                        var row = service.activeModel.get(i)
                        if (row && row.originalId === originalId) {
                            removed = true
                            if (closedSnapshot) service.removeAt(i, "dismiss", originalId, closedSnapshot.timestamp)
                            else service.removeAt(i, "dismiss")
                        }
                    }
                    if (!removed && closedSnapshot) service.recordHistory(closedSnapshot)
                }
                delete service.liveRefs[originalId]
            })
        }

        if (doNotDisturb && !Logic.shouldBypassDnd(notification, 2)) {
            if (!Logic.isEphemeralApp(snapshot.app) && !isTransient(notification)) recordHistory(snapshot)
            delete liveRefs[originalId]
            delete liveSnapshots[originalId]
            try { notification.tracked = false } catch (releaseError) {}
            console.info("[NOTIFICATIONS] notification.silenced app=" + snapshot.app)
            return
        }

        persistPopupFile(snapshot)
        removeActiveById(originalId)
        activeNotificationsModel.insert(0, snapshot)
        insertPopupSnapshot(snapshot)
        watchForUpdates(notification, originalId)
        console.info("[NOTIFICATIONS] notification.received app=" + snapshot.app + " actions=" + snapshot.actions.length)
    }

    function removeAt(index, reason, expectedOriginalId, expectedTimestamp) {
        if (index < 0 || index >= activeNotificationsModel.count) return
        var entry = activeNotificationsModel.get(index)
        var hasExpectedIdentity = arguments.length >= 4 && expectedOriginalId !== undefined && expectedTimestamp !== undefined
        var lookupId = hasExpectedIdentity
            ? expectedOriginalId
            : (entry && entry.originalId !== undefined ? entry.originalId : -1)
        var liveSnapshot = liveSnapshots[lookupId]
        var entryIdentity = entry && Logic.hasPopupIdentity(entry) ? entry : null
        var historySnapshot = liveSnapshot || (entry && Logic.isRenderableHistoryEntry(entry)
            ? entry
            : liveSnapshots[lookupId])
        var archiveSnapshot = liveSnapshot || entryIdentity || (historySnapshot && Logic.hasPopupIdentity(historySnapshot)
            ? historySnapshot
            : null)
        var originalId = archiveSnapshot ? archiveSnapshot.originalId : lookupId
        var restored = isRestoredPopup(archiveSnapshot)
        var reference = restored ? null : liveRefs[originalId]
        activeNotificationsModel.remove(index)
        if (archiveSnapshot) removePopupByIdentity(originalId, archiveSnapshot.timestamp)
        if (historySnapshot) {
            recordHistory(historySnapshot, false)
            // Always enqueue a complete history write before moving the live
            // file. This is the fallback when the original persistence job
            // failed or the popup was dismissed before it completed.
            writeHistoryFile(historySnapshot)
        }
        if (archiveSnapshot) archivePopupFileFor(archiveSnapshot)
        if (restored) delete restoredPopups[Logic.popupFileName(archiveSnapshot)]
        if (reference) {
            try {
                if (reason === "expire" && typeof reference.expire === "function") reference.expire()
                else if (typeof reference.dismiss === "function") reference.dismiss()
            } catch (error) {
                // A sender may have already closed the object.
            }
        }
        if (liveRefs[originalId] === reference) delete liveRefs[originalId]
        delete liveSnapshots[originalId]
    }

    function removeByIdentity(originalId, timestamp, reason, indexHint) {
        var wantedId = String(originalId)
        var wantedTimestamp = Number(timestamp)
        if (!isFinite(wantedTimestamp)) return false
        for (var i = activeNotificationsModel.count - 1; i >= 0; i--) {
            var row = activeNotificationsModel.get(i)
            if (row && String(row.originalId) === wantedId && Number(row.timestamp) === wantedTimestamp) {
                removeAt(i, reason, originalId, timestamp)
                return true
            }
        }
        // A delegate can still hold the authoritative identity while a
        // dynamic ListModel role update is in flight. Trust that identity at
        // its current index and use liveSnapshots for persistence, rather than
        // manufacturing an invalid 0-0 archive key from an incomplete row.
        if (indexHint !== undefined && indexHint >= 0 && indexHint < activeNotificationsModel.count) {
            removeAt(indexHint, reason, originalId, timestamp)
            return true
        }
        return false
    }

    function archiveByIdentity(originalId, timestamp) {
        var index = activeIndexForIdentity(originalId, timestamp)
        if (index < 0) return "none"
        removeAt(index, "archive", originalId, timestamp)
        console.info("[NOTIFICATIONS] inbox.archived id=" + originalId)
        return "ok"
    }

    function dismissAt(index, originalId, timestamp) {
        console.info("[NOTIFICATIONS] popup.dismiss index=" + index)
        if (arguments.length >= 3) {
            removeByIdentity(originalId, timestamp, "dismiss", index)
            return
        }
        removeAt(index, "dismiss")
    }
    function expireAt(index, originalId, timestamp) {
        console.info("[NOTIFICATIONS] popup.expire index=" + index)
        var popupIndex = arguments.length >= 3
            ? modelIndexByIdentity(popupNotificationsModel, originalId, timestamp)
            : index
        if (popupIndex < 0 && arguments.length >= 3 && index >= 0 && index < popupNotificationsModel.count) popupIndex = index
        if (popupIndex < 0 || popupIndex >= popupNotificationsModel.count) return
        var popupEntry = popupNotificationsModel.get(popupIndex)
        var popupId = arguments.length >= 3 ? originalId : (popupEntry ? popupEntry.originalId : -1)
        var popupTimestamp = arguments.length >= 3 ? timestamp : (popupEntry ? popupEntry.timestamp : 0)
        var snapshot = liveSnapshots[popupId] || popupEntry
        if (isManualInboxEntry(snapshot)) {
            // Expiry is only for the passive toast. Inbox ownership remains
            // with the user until an explicit per-notification action.
            popupNotificationsModel.remove(popupIndex)
            console.info("[NOTIFICATIONS] popup.expired inbox_retained id=" + popupId)
            return
        }
        var activeIndex = activeIndexForIdentity(popupId, popupTimestamp)
        if (!removeByIdentity(popupId, popupTimestamp, "expire", activeIndex)) {
            // Ephemeral entries such as screenshot confirmations can have
            // already lost their active delegate during a model transition;
            // persist their snapshot before removing the last popup copy.
            popupNotificationsModel.remove(popupIndex)
            if (snapshot) {
                recordHistory(snapshot)
                writeHistoryFile(snapshot)
                archivePopupFileFor(snapshot)
            }
        }
    }

    function dismissAll() {
        while (activeNotificationsModel.count > 0) removeAt(0, "dismiss")
        return "ok"
    }

    function dismissOne() {
        if (activeNotificationsModel.count === 0) return "none"
        removeAt(0, "dismiss")
        return "ok"
    }

    function invokeLast() {
        if (activeNotificationsModel.count === 0) return "none"
        return invokeDefault(0)
    }

    function dismissBySummary(value) {
        var needle = String(value || "")
        if (needle === "") return "none"
        var dismissed = false
        for (var i = activeNotificationsModel.count - 1; i >= 0; i--) {
            var row = activeNotificationsModel.get(i)
            if (row && String(row.summary || "").indexOf(needle) !== -1) {
                removeAt(i, "dismiss")
                dismissed = true
            }
        }
        return dismissed ? "ok" : "none"
    }

    function removeByOriginalId(originalId, reason) {
        for (var i = activeNotificationsModel.count - 1; i >= 0; i--) {
            var row = activeNotificationsModel.get(i)
            if (row && row.originalId === originalId) {
                var snapshot = liveSnapshots[originalId]
                if (snapshot) removeAt(i, reason, originalId, snapshot.timestamp)
                else removeAt(i, reason)
                return true
            }
        }
        return false
    }

    function activeIndexForIdentity(originalId, timestamp, indexHint) {
        var wantedId = String(originalId)
        var wantedTimestamp = Number(timestamp)
        if (!isFinite(wantedTimestamp)) return -1
        for (var i = 0; i < activeNotificationsModel.count; i++) {
            var row = activeNotificationsModel.get(i)
            if (row && String(row.originalId) === wantedId && Number(row.timestamp) === wantedTimestamp) return i
        }
        if (indexHint !== undefined && indexHint >= 0 && indexHint < activeNotificationsModel.count) return indexHint
        return -1
    }

    function objectProperty(object, name) {
        try {
            return object && object[name] !== undefined && object[name] !== null ? object[name] : null
        } catch (error) {
            return null
        }
    }

    function textProperty(object, name) {
        var value = objectProperty(object, name)
        return value === null ? "" : String(value)
    }

    function workspaceIdForToplevel(toplevel) {
        var workspace = objectProperty(toplevel, "workspace")
        var id = Number(textProperty(workspace, "id"))
        if (!isFinite(id) || Math.floor(id) !== id || id === 0) return 0
        return id
    }

    function toplevelWorkspaceInfo(toplevel) {
        var wayland = objectProperty(toplevel, "wayland")
        var handle = objectProperty(toplevel, "handle")
        var ipc = objectProperty(toplevel, "lastIpcObject") || {}
        var appId = textProperty(wayland, "appId") || textProperty(handle, "appId") || textProperty(toplevel, "appId")
        var title = textProperty(toplevel, "title") || textProperty(wayland, "title")
        return {
            appId: appId,
            desktopEntry: textProperty(ipc, "desktopEntry"),
            className: textProperty(ipc, "class") || textProperty(ipc, "className"),
            initialClass: textProperty(ipc, "initialClass"),
            title: title || textProperty(ipc, "title"),
            initialTitle: textProperty(ipc, "initialTitle"),
            activated: objectProperty(toplevel, "activated") === true || objectProperty(handle, "activated") === true
        }
    }

    function matchingWorkspaceToplevel(route) {
        if (!route || !route.enabled || !Hyprland.toplevels) return null

        var values = []
        try { values = Hyprland.toplevels.values || [] } catch (error) { return null }

        var best = null
        for (var i = 0; i < values.length; i++) {
            var candidate = values[i]
            var workspace = objectProperty(candidate, "workspace")
            var workspaceId = workspaceIdForToplevel(candidate)
            if (workspaceId === 0) continue
            var info = service.toplevelWorkspaceInfo(candidate)
            var score = Logic.workspaceRouteScore(route, info)
            if (score <= 0) continue
            if (!best || score > best.score || (score === best.score && info.activated && !best.info.activated)) {
                best = { toplevel: candidate, workspace: workspace, workspaceId: workspaceId, info: info, score: score }
            }
        }
        return best
    }

    function focusWorkspace(workspaceId) {
        var id = Number(workspaceId)
        if (!isFinite(id) || Math.floor(id) !== id || id === 0) return false
        var normalized = String(id)
        try {
            if (Hyprland.usingLua) Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + normalized + "\" })")
            else Hyprland.dispatch("workspace " + normalized)
            return true
        } catch (error) {
            console.warn("[NOTIFICATIONS] workspace.route_failed id=" + normalized)
            return false
        }
    }

    function resolvePendingWorkspaceRoute() {
        var route = service.pendingWorkspaceRoute
        if (!route) return

        try { Hyprland.refreshToplevels() } catch (error) {}
        var match = service.matchingWorkspaceToplevel(route)
        if (match) {
            if (service.workspaceRouteAttempts >= service.workspaceRouteMaxAttempts) {
                console.info("[NOTIFICATIONS] workspace.route_unavailable")
                service.pendingWorkspaceRoute = null
                return
            }
            var focusedWorkspace = Hyprland.focusedWorkspace
            var workspaceFocused = match.workspace && typeof match.workspace.focused === "boolean"
                ? match.workspace.focused
                : (!!focusedWorkspace && Number(focusedWorkspace.id) === match.workspaceId)
            if (!workspaceFocused) {
                console.info("[NOTIFICATIONS] workspace.switch_requested id=" + match.workspaceId)
                try {
                    if (match.workspace && typeof match.workspace.activate === "function") match.workspace.activate()
                    else service.focusWorkspace(match.workspaceId)
                    try { Hyprland.refreshWorkspaces() } catch (refreshError) {}
                } catch (error) {
                    service.focusWorkspace(match.workspaceId)
                }
                service.workspaceRouteAttempts++
                service.workspaceRouteTimer.interval = 80
                service.workspaceRouteTimer.restart()
                return
            }

            try {
                var handle = match.toplevel && match.toplevel.handle
                if (handle && typeof handle.activate === "function") handle.activate()
            } catch (error) {
                // The sender's action remains successful even if activation is
                // withdrawn before the matching toplevel can be activated.
            }

            try { Hyprland.refreshWorkspaces() } catch (refreshError) {}
            var focusedAfterActivation = Hyprland.focusedWorkspace
            if (!focusedAfterActivation || Number(focusedAfterActivation.id) !== match.workspaceId) {
                service.workspaceRouteAttempts++
                service.workspaceRouteTimer.interval = 80
                service.workspaceRouteTimer.restart()
                return
            }

            console.info("[NOTIFICATIONS] workspace.routed id=" + match.workspaceId + " score=" + match.score)
            service.pendingWorkspaceRoute = null
            service.workspaceRouteTimer.stop()
            return
        }

        if (service.workspaceRouteAttempts >= service.workspaceRouteMaxAttempts) {
            console.info("[NOTIFICATIONS] workspace.route_unavailable")
            service.pendingWorkspaceRoute = null
            return
        }

        service.workspaceRouteAttempts++
        service.workspaceRouteTimer.restart()
    }

    function startWorkspaceRoute(route) {
        if (!route || !route.enabled) return
        service.workspaceRouteTimer.stop()
        service.pendingWorkspaceRoute = route
        service.workspaceRouteAttempts = 0
        service.resolvePendingWorkspaceRoute()
    }

    function invokeAction(index, identifier, originalId, timestamp) {
        if (arguments.length >= 4) {
            index = activeIndexForIdentity(originalId, timestamp, index)
            if (index < 0) return "none"
        }
        if (index < 0 || index >= activeNotificationsModel.count) return "none"
        var entry = activeNotificationsModel.get(index)
        var resolvedOriginalId = entry && entry.originalId !== undefined ? entry.originalId : originalId
        var reference = liveRefs[resolvedOriginalId]
        if (!reference || !reference.actions) return "unavailable"
        for (var i = 0; i < reference.actions.length; i++) {
            var action = reference.actions[i]
            if (action && action.identifier === identifier && typeof action.invoke === "function") {
                var route = Logic.workspaceRouteData(reference, entry)
                action.invoke()
                service.startWorkspaceRoute(route)
                removeByIdentity(resolvedOriginalId, entry && Number(entry.timestamp) > 0 ? entry.timestamp : timestamp, "action", index)
                return "ok"
            }
        }
        return "not-found"
    }

    function invokeDefault(index, originalId, timestamp) {
        if (arguments.length >= 3) {
            index = activeIndexForIdentity(originalId, timestamp, index)
            if (index < 0) return "none"
        }
        if (index < 0 || index >= activeNotificationsModel.count) return "none"
        var entry = activeNotificationsModel.get(index)
        var resolvedOriginalId = entry && entry.originalId !== undefined ? entry.originalId : originalId
        var fallbackEntry = service.liveSnapshots[resolvedOriginalId] || entry
        var resolvedTimestamp = entry && Number(entry.timestamp) > 0 ? entry.timestamp : timestamp
        var argv = Logic.parseExecArgv(fallbackEntry ? fallbackEntry.execArgv : "")
        if (argv) {
            var execRoute = Logic.workspaceRouteData(fallbackEntry, entry)
            if (execRoute.enabled) service.startWorkspaceRoute(execRoute)
            Quickshell.execDetached(["bash", "-lc", "exec \"$@\"", "aurelia-notification"].concat(argv))
            removeByIdentity(resolvedOriginalId, resolvedTimestamp, "action", index)
            return "ok"
        }
        var reference = liveRefs[resolvedOriginalId]
        if (reference && reference.actions) {
            for (var i = 0; i < reference.actions.length; i++) {
                var action = reference.actions[i]
                if (action && action.identifier === "default" && typeof action.invoke === "function") {
                    var route = Logic.workspaceRouteData(reference, entry)
                    action.invoke()
                    service.startWorkspaceRoute(route)
                    removeByIdentity(resolvedOriginalId, resolvedTimestamp, "action", index)
                    return "ok"
                }
            }
        }
        var route = Logic.workspaceRouteData(reference || fallbackEntry, entry)
        if (route.enabled) service.startWorkspaceRoute(route)
        removeByIdentity(resolvedOriginalId, resolvedTimestamp, "action", index)
        return route.enabled ? "ok" : "unavailable"
    }

    // Historical rows no longer own the sender's live action object. Keep the
    // same action layout, but route an historical action to the sender window
    // when possible instead of attempting to invoke a stale object.
    function invokeHistoryAction(index, identifier) {
        if (index < 0 || index >= historyEntriesModel.count) return "none"
        var entry = historyEntriesModel.get(index)
        var argv = Logic.parseExecArgv(entry ? entry.execArgv : "")
        if (argv) {
            Quickshell.execDetached(["bash", "-lc", "exec \"$@\"", "aurelia-notification"].concat(argv))
            console.info("[NOTIFICATIONS] history.action id=" + String(identifier || ""))
            return "ok"
        }
        var route = Logic.workspaceRouteData(entry, entry)
        if (!route.enabled) return "unavailable"
        service.startWorkspaceRoute(route)
        console.info("[NOTIFICATIONS] history.action id=" + String(identifier || ""))
        return "ok"
    }
    function invokeHistoryDefault(index) {
        return invokeHistoryAction(index, "default")
    }

    function clearHistory() {
        historyEntries = []
        historyDirty = true
        rebuildHistoryModel()
        clearHistoryFiles()
        if (historyPath !== "") historyFile.setText("")
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
        // The center panel is loader-owned and may be destroyed as soon as
        // centerOpen changes. Release the bar popout while the panel object is
        // still available so a closed notification center cannot leave the
        // bar's active underline behind.
        releaseCenterPopout()
        centerOpen = false
        return "ok"
    }

    function releaseCenterPopout() {
        var panel = centerPanel.item
        if (panel && bar && typeof bar.releasePopout === "function") {
            bar.releasePopout(panel)
        }
    }

    onCenterOpenChanged: {
        if (!centerOpen) releaseCenterPopout()
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
        liveSnapshots[snapshot.originalId] = snapshot
        persistPopupFile(snapshot)
        activeNotificationsModel.insert(0, snapshot)
        insertPopupSnapshot(snapshot)
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
        function isDnd(): string { return service.dndState() }
        function toggleDnd(): string { return service.toggleDnd() }
        function setDnd(value: string): string { return service.setDndFromText(value) }
        function showHistory(): string { return service.showHistory() }
        function clear(): string { return service.clearHistory() }
        function dismissAll(): string { return service.dismissAll() }
        function dismissOne(): string { return service.dismissOne() }
        function invokeLast(): string { return service.invokeLast() }
        function dismiss(summary: string): string { return service.dismissBySummary(summary) }
        function publishScreenshot(path: string): string { return service.publishScreenshot(path) }
    }

    Loader {
        id: notificationServerLoader
        // Register immediately. A readiness probe must describe/recover the
        // server, never create a startup window in which Notify has no owner.
        active: true
        asynchronous: false
        source: Qt.resolvedUrl("NotificationServerHost.qml")

        onLoaded: {
            if (item && "service" in item) item.service = service
            service.notificationServerLoaded = true
            console.info("[NOTIFICATIONS] server.loaded")
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                service.notificationServerLoaded = false
                console.error("[NOTIFICATIONS] server.load_failed")
                service.scheduleNotificationServerRestart()
            }
        }
    }

    property bool _startupStarted: false
    Component.onCompleted: {
        if (_startupStarted) return
        _startupStarted = true
        probeNotificationBus()
        notificationBusHealthTimer.start()
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

    Component.onDestruction: {
        notificationBusRetryTimer.stop()
        notificationBusHealthTimer.stop()
        notificationServerRestartTimer.stop()
        popupFileRetryTimer.stop()
        notificationBusProbe.running = false
        notificationServerLoader.active = false
    }

    function scheduleNotificationServerRestart() {
        if (notificationServerRestartQueued) return
        notificationServerRestartQueued = true
        notificationServerRestartTimer.restart()
    }

    function probeNotificationBus() {
        if (notificationBusProbe.running) return
        notificationBusProbeAttempts++
        notificationBusProbe.running = true
    }

    Variants {
        model: Quickshell.screens

        NotificationPopupSurface {
            required property var modelData
            notificationService: service
            screenModel: modelData
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
