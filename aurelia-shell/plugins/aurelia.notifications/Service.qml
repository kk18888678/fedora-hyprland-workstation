import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "ui"
import "NotificationLogic.js" as Logic
import "NotificationFileLogic.js" as FileLogic
import "NotificationActionRegistry.js" as ActionRegistry

// Resident notification daemon. It keeps live Quickshell Notification objects
// in a private map and exposes only bounded snapshots to UI models and state
// files. The service owns its own popups, Inbox, and Do Not Disturb state.
Item {
    id: service

    property var shell: null
    property var bar: null
    property var aureliaPath: ""
    property var manifest: ({})
    property var pluginRegistry: null
    // Constructor-injected only by isolated fixtures. Production keeps the
    // normal notification bus and desktop surfaces fully enabled.
    property bool testMode: false

    // The validated (stable app id, action id) -> argv/URI action registry. It
    // is built once at load; malformed entries are reported and never used.
    // An isolated fixture may add deterministic entries on top of the reviewed
    // defaults through one test-only environment variable.
    readonly property var actionRegistryBuild: service.buildActionRegistry()
    readonly property var actionRegistry: service.actionRegistryBuild.registry

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateHomeOverride: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string stateHome: stateHomeOverride.charAt(0) === "/" && stateHomeOverride !== "/"
        ? stateHomeOverride
        : (home.charAt(0) === "/" && home !== "/" ? home + "/.local/state" : "")
    readonly property string stateDir: stateHome !== "" ? stateHome + "/aurelia" : ""
    readonly property string settingsPath: stateDir !== "" ? stateDir + "/notifications.json" : ""
    readonly property string popupStateDir: stateDir !== "" ? stateDir + "/notifications/" : ""
    readonly property string imagesDir: popupStateDir !== "" ? popupStateDir + "images/" : ""
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
    property bool stateDirectoryReady: false
    property bool settingsLoaded: false
    property bool settingsDirty: false
    property bool stateSaveQueued: false
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
    // Last text handed to the clipboard path. Production still shells out to
    // wl-copy; isolated fixtures read this without touching a live clipboard.
    property string lastCopiedText: ""

    property alias activeModel: activeNotificationsModel
    // Inbox rows remain until an explicit user action. The popup model is a
    // separate transient presentation queue whose expiry must never remove
    // the corresponding Inbox row.
    property alias popupModel: popupNotificationsModel

    ListModel { id: activeNotificationsModel }
    ListModel { id: popupNotificationsModel }

    property OptionalFileStore settingsFile: OptionalFileStore {
        path: service.settingsPath
        writable: true
        watchChanges: false

        onLoaded: function(loadedValue) { service.loadSettings(loadedValue) }
        onLoadFailed: function(reason) { service.loadSettings("") }
        onSaved: console.info("[NOTIFICATIONS] settings.saved")
        onSaveFailed: function(reason) { console.error("[NOTIFICATIONS] settings_save_failed") }
    }

    property Process ensureStateDirProcess: Process {
        command: service.stateDir !== ""
            ? ["/usr/bin/mkdir", "-p", service.stateDir, service.popupStateDir, service.imagesDir]
            : ["/usr/bin/false"]
        running: false

        onExited: function(code) {
            if (code !== 0) {
                console.error("[NOTIFICATIONS] state_directory_failed code=" + code)
                return
            }
            service.stateDirectoryReady = true
            if (!service.testMode) {
                service.readPopupDirectory()
                service.sweepOrphanImages()
            }
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

    // ------------------------------------------------------------------
    // Notification origin capture and navigation.
    //
    // `workstation-notification-focus` is the single owner of origin capture
    // and focus navigation. Capture runs as a separate bounded queue so a
    // slow capture can never delay a user click, and every helper invocation
    // is wrapped in a hard `/usr/bin/timeout` so neither the notification
    // display nor the click path can hang on it.
    // ------------------------------------------------------------------
    readonly property string originHelperPath: {
        if (service.testMode) {
            // Isolated fixtures must never reach the live helper unless they
            // explicitly inject a deterministic stand-in.
            var override = Quickshell.env("AURELIA_NOTIFICATION_TEST_HELPER") || ""
            return (override.charAt(0) === "/" && override !== "/") ? override : ""
        }
        var root = service.aureliaPath && String(service.aureliaPath).charAt(0) === "/"
            ? String(service.aureliaPath)
            : (Quickshell.env("AURELIA_SHELL_ROOT") || "")
        if (root === "" || root.charAt(0) !== "/") return ""
        return root.replace(/\/$/, "") + "/bin/workstation-notification-focus"
    }
    readonly property int originHelperTimeoutMs: {
        if (service.testMode) {
            var raw = Number(Quickshell.env("AURELIA_NOTIFICATION_TEST_HELPER_TIMEOUT_MS"))
            if (isFinite(raw) && raw >= 500 && raw <= 15000) return Math.round(raw)
        }
        return 5000
    }
    // Resolve the command first, then run it unchanged. The previous guard
    // shifted the command away and exec'd the remaining arguments, so every
    // notification handoff was a silent no-op while the row was still removed.
    readonly property string commandGuardScript: 'cmd="$1"; shift; ' +
        'if [ -z "$cmd" ]; then exit 127; fi; ' +
        'if ! command -v "$cmd" >/dev/null; then ' +
        'logger -t aurelia-notification "notification command unavailable: $cmd"; ' +
        'exit 127; fi; ' +
        'exec "$cmd" "$@"'

    property var captureQueue: []
    property var runningCaptureJob: null
    property Process captureProcess: Process {
        running: false
        stdout: StdioCollector {
            id: captureStdout
            waitForEnd: true
        }
        stderr: StdioCollector { id: captureStderr; waitForEnd: true }
        onExited: function(code) {
            var job = service.runningCaptureJob
            service.runningCaptureJob = null
            if (job) {
                try {
                    if (job.done) job.done(code, captureStdout.text, captureStderr.text)
                } catch (error) {
                    console.warn("[NOTIFICATIONS] capture_job_callback_failed label=" + job.label)
                }
            }
            service.runNextCaptureJob()
        }
    }

    property var actionQueue: []
    property var runningActionJob: null
    property Process actionProcess: Process {
        running: false
        stdout: StdioCollector {
            id: actionStdout
            waitForEnd: true
        }
        stderr: StdioCollector { id: actionStderr; waitForEnd: true }
        onExited: function(code) {
            var job = service.runningActionJob
            service.runningActionJob = null
            if (job) {
                try {
                    if (job.done) job.done(code, actionStdout.text, actionStderr.text)
                } catch (error) {
                    console.warn("[NOTIFICATIONS] action_job_callback_failed label=" + job.label)
                }
            }
            service.runNextActionJob()
        }
    }

    readonly property string helperTimeoutText: (service.originHelperTimeoutMs / 1000).toFixed(1) + "s"

    function enqueueCaptureJob(command, done, label) {
        if (!command || command.length === 0) return
        captureQueue = captureQueue.concat([{ command: command, done: done || null, label: String(label || "capture") }])
        service.runNextCaptureJob()
    }

    function runNextCaptureJob() {
        if (captureProcess.running || captureQueue.length === 0) return
        var job = captureQueue[0]
        captureQueue = captureQueue.slice(1)
        runningCaptureJob = job
        captureProcess.command = job.command
        captureProcess.running = true
    }

    function enqueueActionJob(command, done, label) {
        if (!command || command.length === 0) return
        actionQueue = actionQueue.concat([{ command: command, done: done || null, label: String(label || "action") }])
        service.runNextActionJob()
    }

    function runNextActionJob() {
        if (actionProcess.running || actionQueue.length === 0) return
        var job = actionQueue[0]
        actionQueue = actionQueue.slice(1)
        runningActionJob = job
        actionProcess.command = job.command
        actionProcess.running = true
    }

    function boundedHelperCommand(program, args) {
        return ["/usr/bin/timeout", "--foreground", "--kill-after=1s",
            service.helperTimeoutText, program].concat(args)
    }

    // Capture is deliberately fire-and-forget: the notification is already
    // displayed and persisted, and a failed, timed-out or null capture leaves
    // it completely intact with no origin and no unmet condition.
    function captureOrigin(snapshot) {
        if (!snapshot || service.originHelperPath === "") return
        var args = ["capture", "--id", String(snapshot.originalId)]
        if (String(snapshot.app || "") !== "") args.push("--app", String(snapshot.app))
        if (String(snapshot.summary || "") !== "") args.push("--summary", String(snapshot.summary))
        if (String(snapshot.body || "") !== "") args.push("--body", String(snapshot.body))
        if (String(snapshot.desktopEntry || "") !== "") args.push("--desktop-entry", String(snapshot.desktopEntry))
        args.push("--urgency", String(snapshot.urgency))
        args.push("--timestamp", String(snapshot.timestamp))
        service.enqueueCaptureJob(service.boundedHelperCommand(service.originHelperPath, args),
            function(code, stdout) {
                if (code !== 0) return
                var origin = Logic.parseOriginOutput(stdout)
                if (!origin) return
                service.applyCapturedOrigin(snapshot.originalId, snapshot.timestamp, origin)
            },
            "capture:" + snapshot.originalId)
    }

    function applyCapturedOrigin(originalId, timestamp, origin) {
        if (!origin) return
        var key = service.identityKey(originalId, timestamp)
        if (key === "" || !liveSnapshots[key]) return
        var snapshot = liveSnapshots[key]
        if (!snapshot || !service.hasUsableIdentity(snapshot.originalId, snapshot.timestamp)) return
        if (snapshot.origin) return
        snapshot.origin = Logic.originFieldValue(origin)
        updateModelRows(activeNotificationsModel, snapshot, originalId, timestamp)
        updateModelRows(popupNotificationsModel, snapshot, originalId, timestamp)
        persistPopupFile(snapshot)
        console.info("[NOTIFICATIONS] origin.captured quality=" + origin.captureQuality)
    }

    function originFrom(entry) {
        return entry ? Logic.originFromField(entry.origin) : null
    }

    function applyActionOutcome(originalId, timestamp, outcome, reason) {
        var key = service.identityKey(originalId, timestamp)
        if (key === "") return
        var snapshot = liveSnapshots[key]
        if (snapshot) {
            snapshot.actionOutcome = String(outcome || "")
            snapshot.actionOutcomeReason = String(reason || "")
        }
        service.setModelOutcome(activeNotificationsModel, originalId, timestamp, outcome, reason)
        service.setModelOutcome(popupNotificationsModel, originalId, timestamp, outcome, reason)
    }

    function setModelOutcome(model, originalId, timestamp, outcome, reason) {
        var index = service.modelIndexByIdentity(model, originalId, timestamp)
        if (index < 0) return
        model.setProperty(index, "actionOutcome", String(outcome || ""))
        model.setProperty(index, "actionOutcomeReason", String(reason || ""))
    }

    function navigateToOrigin(origin, originalId, timestamp, label) {
        if (!origin) {
            service.applyActionOutcome(originalId, timestamp, "unavailable", "no origin")
            return
        }
        if (service.originHelperPath === "") {
            service.applyActionOutcome(originalId, timestamp, "unavailable", "origin helper unavailable")
            return
        }
        var command = service.boundedHelperCommand(service.originHelperPath,
            ["navigate", "--origin", JSON.stringify(origin)])
        service.enqueueActionJob(command, function(code, stdout) {
            var parsed = code === 0 ? Logic.parseNavigateOutput(stdout) : null
            service.finishNavigation(originalId, timestamp,
                parsed ? parsed.outcome : "unavailable",
                parsed ? parsed.reason : "navigate unavailable")
        }, label)
    }

    function finishNavigation(originalId, timestamp, helperOutcome, reason) {
        var status = "unavailable"
        if (helperOutcome === "focused") status = "delivered"
        else if (helperOutcome === "routed") status = "routed"
        else if (helperOutcome === "none") status = "none"
        if (status === "delivered") {
            console.info("[NOTIFICATIONS] action.origin_focused id=" + originalId)
            removeByIdentity(originalId, timestamp, "action")
            return
        }
        service.applyActionOutcome(originalId, timestamp, status, reason)
        console.info("[NOTIFICATIONS] action.outcome status=" + status + " id=" + originalId)
    }

    // The action context for the next command dispatch. The exec-argv call
    // sites set it then call `spawnNotificationCommand(argv)` so the guarded
    // command entry point keeps its single-argument shape.
    property var pendingCommandContext: null

    // Run an argv that came from an untrusted notification through a bounded
    // observing Process. A missing command exits 127 and is reported as
    // unavailable instead of a silent success; a command that genuinely ran
    // removes the row. When the notification also carries an origin, a failed
    // command falls back to origin navigation rather than a false failure.
    function spawnNotificationCommand(argv, originalId, timestamp, index, identifier, fallbackOrigin) {
        if (arguments.length === 1) {
            var context = service.pendingCommandContext || {}
            originalId = context.originalId
            timestamp = context.timestamp
            index = context.index
            identifier = context.identifier
            fallbackOrigin = context.fallbackOrigin
        }
        service.pendingCommandContext = null
        if (!argv || argv.length === 0) {
            if (fallbackOrigin) {
                service.navigateToOrigin(fallbackOrigin, originalId, timestamp, "navigate:" + identifier)
                return
            }
            service.applyActionOutcome(originalId, timestamp, "unavailable", "empty command")
            return
        }
        var command = ["/usr/bin/timeout", "--foreground", "--kill-after=1s",
            service.helperTimeoutText, "/usr/bin/bash", "-c",
            service.commandGuardScript, "aurelia-notification"].concat(argv)
        service.enqueueActionJob(command, function(code) {
            if (code === 0) {
                console.info("[NOTIFICATIONS] action.command_executed id=" + originalId)
                removeByIdentity(originalId, timestamp, "action", index)
                return
            }
            if (fallbackOrigin) {
                service.navigateToOrigin(fallbackOrigin, originalId, timestamp, "navigate:fallback:" + originalId)
                return
            }
            console.info("[NOTIFICATIONS] action.outcome status=unavailable id=" + originalId)
            service.applyActionOutcome(originalId, timestamp, "unavailable", "command unavailable")
        }, "command:" + identifier)
    }
    function persistPopupFile(snapshot) {
        if (!snapshot || popupStateDir === "") return
        var fileName = Logic.popupFileName(snapshot)
        if (fileName === "") {
            console.error("[NOTIFICATIONS] popup.persist_skipped reason=invalid_identity id=" +
                String(snapshot.originalId) + " timestamp=" + String(snapshot.timestamp))
            return
        }
        // The shared owner is the single resolution policy. Its result is
        // already durable: our own file:// copy, a theme name, or the honest
        // default. Only an absent copy (job failure) falls back below.
        var resolution = AppIconResolver.resolve(Logic.iconResolutionInput(snapshot, imagesDir))
        var persistable = Logic.persistablePopup(snapshot, imagesDir, resolution)
        service.enqueuePersistJob(snapshot, persistable, fileName, false)
    }

    // Persist one durable entry. The copy script fails closed, so the JSON and
    // the live models are only updated once every declared copy is proven to
    // exist. A failed copy falls through to the honest default name rather
    // than recording a dangling file:// path the card would render as blank.
    function enqueuePersistJob(snapshot, persistable, fileName, retried) {
        persistable.json = Logic.serializePopup(persistable.entry, 1)
        enqueuePopupFileJob(FileLogic.persistPopup(
            persistable, popupStateDir, imagesDir, fileName),
            function(success) {
                if (success) {
                    service.applyDurablePopup(snapshot, persistable.entry)
                    return
                }
                if (!retried) {
                    var fallback = Logic.persistablePopup(snapshot, imagesDir, {
                        source: "", name: Logic.DEFAULT_ICON_NAME, symbolic: false, kind: "default"
                    })
                    service.enqueuePersistJob(snapshot, fallback, fileName, true)
                    return
                }
                console.error("[NOTIFICATIONS] popup.persist_failed label=" + fileName)
            },
            "popup.persist:" + fileName)
    }

    // Apply the durable icon/image paths produced by persistablePopup to the
    // in-memory rows and live snapshots. The on-disk JSON already carries these
    // paths; without this the UI would keep the sender's ephemeral URL and
    // render a broken icon once the sender deletes it.
    function applyDurablePopup(snapshot, durableEntry) {
        if (!snapshot || !durableEntry) return
        var originalId = snapshot.originalId
        var timestamp = snapshot.timestamp
        if (!service.hasUsableIdentity(originalId, timestamp)) return
        var liveKey = service.identityKey(originalId, timestamp)
        if (liveKey !== "" && liveSnapshots[liveKey]) {
            var live = liveSnapshots[liveKey]
            var roles = ["app", "appIcon", "desktopEntry", "summary", "body", "image", "glyph",
                "execArgv", "actions", "defaultActionText", "urgency", "expireTimeout",
                "deadline", "transient"]
            for (var r = 0; r < roles.length; r++) live[roles[r]] = durableEntry[roles[r]]
            // The origin is not one of the icon roles, but the durable entry
            // still carries it. Apply it only when the live snapshot does not
            // already hold one so a stale persist job cannot clear a freshly
            // captured origin.
            if (durableEntry.origin && !live.origin) live.origin = durableEntry.origin
        }
        updateModelRows(activeNotificationsModel, durableEntry, originalId, timestamp)
        updateModelRows(popupNotificationsModel, durableEntry, originalId, timestamp)
    }

    function sweepOrphanImages() {
        if (imagesDir === "") return
        enqueuePopupFileJob(FileLogic.sweepImages(popupStateDir, imagesDir), null, "images.sweep")
    }

    function deletePopupFileFor(snapshot) {
        if (!snapshot || popupStateDir === "") return
        var fileName = Logic.popupFileName(snapshot)
        if (fileName === "") return
        enqueuePopupFileJob(FileLogic.deletePopup(
            popupStateDir, imagesDir, fileName),
            null, "popup.delete:" + fileName)
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

    function loadSettings(raw) {
        if (settingsLoaded) return
        var parsed = Logic.parseSettings(raw)
        if (!parsed.ok) console.info("[NOTIFICATIONS] settings_invalid using_defaults")
        if (!settingsDirty && parsed.dnd !== null) doNotDisturb = parsed.dnd
        settingsLoaded = true
        if (stateSaveQueued && stateDirectoryReady) flushState()
    }

    function modelIndexByIdentity(model, originalId, timestamp) {
        if (!model) return -1
        if (!service.hasUsableIdentity(originalId, timestamp)) return -1
        var wantedId = String(originalId)
        var wantedTimestamp = Number(timestamp)
        if (!isFinite(wantedTimestamp)) return -1
        for (var i = 0; i < model.count; i++) {
            var row = model.get(i)
            if (row && String(row.originalId) === wantedId && Number(row.timestamp) === wantedTimestamp) return i
        }
        return -1
    }

    function identityKey(originalId, timestamp) {
        return Logic.identityKey(originalId, timestamp)
    }

    function hasUsableIdentity(originalId, timestamp) {
        return service.identityKey(originalId, timestamp) !== ""
    }

    function liveKeyForOriginalId(originalId) {
        var wantedId = String(originalId)
        for (var key in liveRefs) {
            var snapshot = liveSnapshots[key]
            if (snapshot && String(snapshot.originalId) === wantedId) return key
        }
        return ""
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

    function insertPopupSnapshot(snapshot) {
        if (!snapshot || !service.hasUsableIdentity(snapshot.originalId, snapshot.timestamp)) return
        if (modelIndexByIdentity(popupNotificationsModel, snapshot.originalId, snapshot.timestamp) >= 0) return
        popupNotificationsModel.insert(0, snapshot)
    }

    function updateModelRows(model, updated, originalId, timestamp) {
        if (!model || !updated) return 0
        var roles = ["app", "appIcon", "desktopEntry", "summary", "body", "image", "glyph", "execArgv", "actions", "defaultActionText", "urgency", "expireTimeout", "deadline", "transient", "origin"]
        var changed = 0
        for (var i = 0; i < model.count; i++) {
            var row = model.get(i)
            if (!row || String(row.originalId) !== String(originalId) ||
                Number(row.timestamp) !== Number(timestamp)) continue
            updated.id = row.id
            updated.originalId = row.originalId
            updated.timestamp = row.timestamp
            for (var r = 0; r < roles.length; r++) {
                // A ListModel array role is materialized as a nested list model.
                // setProperty with a plain JS array leaves that role reading back
                // as undefined, which silently drops every non-default action
                // from the card. Re-seed the row with `set` for `actions` so Qt
                // rematerializes the array role; scalar roles keep setProperty.
                if (roles[r] === "actions") model.set(i, { actions: updated.actions || [] })
                else if (roles[r] === "origin") {
                    // Preserve a newer captured origin against a stale update
                    // that carries none.
                    var nextOrigin = Logic.originFieldValue(updated.origin)
                    var currentOrigin = row.origin === undefined || row.origin === null ? "" : String(row.origin)
                    if (nextOrigin !== "" || currentOrigin === "") model.setProperty(i, "origin", nextOrigin)
                }
                else model.setProperty(i, roles[r], updated[roles[r]])
            }
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
                deletePopupFileFor(entry)
                continue
            }
            if (manualInbox) {
                entry.deadline = 0
                persistPopupFile(entry)
            }
            live.push(entry)
        }
        if (live.length === 0) return

        // A shell reload restores the Inbox silently. Re-inserting restored
        // rows into popupNotificationsModel would replay the whole Inbox as
        // transient toasts; only genuinely new notifications belong there.
        Qt.callLater(function() {
            for (var j = 0; j < live.length; j++) {
                var restored = live[j]
                restoredPopups[Logic.popupFileName(restored)] = true
                if (modelIndexByIdentity(activeNotificationsModel, restored.originalId, restored.timestamp) < 0) {
                    activeNotificationsModel.append(restored)
                }
            }
        })
    }

    function queueStateSave() {
        stateSaveQueued = true
        if (stateDirectoryReady && settingsLoaded) flushState()
    }

    function flushState() {
        if (!stateDirectoryReady || stateDir === "" || !settingsLoaded) return
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

    function removeLiveRowByKey(liveKey, snapshot) {
        if (liveKey === "" || !snapshot ||
            !service.hasUsableIdentity(snapshot.originalId, snapshot.timestamp)) return
        for (var i = activeNotificationsModel.count - 1; i >= 0; i--) {
            var row = activeNotificationsModel.get(i)
            if (row && String(row.originalId) === String(snapshot.originalId) &&
                Number(row.timestamp) === Number(snapshot.timestamp) && !isRestoredPopup(row)) {
                // Materialize the role object before removing it; ListModel
                // invalidates its fields once the row leaves the model.
                var rowSnapshot = Logic.popupEntry(row, 1)
                removePopupByIdentity(rowSnapshot.originalId, rowSnapshot.timestamp)
                activeNotificationsModel.remove(i)
                deletePopupFileFor(rowSnapshot)
            }
        }
        delete liveRefs[liveKey]
        delete liveSnapshots[liveKey]
    }

    function updateActive(notification, liveKey) {
        if (!notification || liveRefs[liveKey] !== notification) return
        var current = liveSnapshots[liveKey]
        if (!current || !service.hasUsableIdentity(current.originalId, current.timestamp)) return
        var updated
        try { updated = Logic.snapshotOf(notification, current.timestamp) }
        catch (error) {
            console.warn("[NOTIFICATIONS] notification.snapshot_refresh_failed")
            return
        }
        var activeChanged = updateModelRows(activeNotificationsModel, updated, current.originalId, current.timestamp)
        var popupChanged = updateModelRows(popupNotificationsModel, updated, current.originalId, current.timestamp)
        if (activeChanged > 0 || popupChanged > 0) {
            liveSnapshots[liveKey] = updated
            persistPopupFile(updated)
        }
    }

    function watchForUpdates(notification, liveKey) {
        var signals = ["summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged", "imageChanged", "actionsChanged", "hintsChanged", "urgencyChanged", "expireTimeoutChanged"]
        function refresh() { service.updateActive(notification, liveKey) }
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
            try { notification.tracked = false } catch (releaseError) {
                console.warn("[NOTIFICATIONS] notification.tracked_release_failed")
            }
            console.error("[NOTIFICATIONS] notification.rejected reason=snapshot_failed")
            return
        }
        var originalId = snapshot.originalId
        var liveKey = service.identityKey(originalId, snapshot.timestamp)
        if (liveKey === "") {
            try { notification.tracked = false } catch (releaseError) {
                console.warn("[NOTIFICATIONS] notification.tracked_release_failed")
            }
            console.error("[NOTIFICATIONS] notification.rejected reason=invalid_identity")
            return
        }
        var previousKey = service.liveKeyForOriginalId(originalId)
        var previous = previousKey !== "" ? liveRefs[previousKey] : null
        var previousSnapshot = previousKey !== "" ? liveSnapshots[previousKey] : null
        if (previousKey !== "" && previousKey !== liveKey) {
            // A sender replacement may reuse its numeric id. Remove only the
            // prior live composite row; restored rows from an earlier shell
            // generation are independent notifications.
            service.removeLiveRowByKey(previousKey, previousSnapshot)
            try {
                if (previous && typeof previous.dismiss === "function") previous.dismiss()
                if (previous) previous.tracked = false
            } catch (replaceError) {
                console.warn("[NOTIFICATIONS] notification.replace_cleanup_failed")
            }
        }
        liveRefs[liveKey] = notification
        liveSnapshots[liveKey] = snapshot
        // Enrich the snapshot with its captured origin asynchronously. This
        // runs before the DND branch and before persistence so neither the
        // visible card nor the retained row is ever gated on the capture.
        service.captureOrigin(snapshot)

        if (notification.closed && typeof notification.closed.connect === "function") {
            notification.closed.connect(function() {
                if (service.liveRefs[liveKey] !== notification) return
                var closedSnapshot = service.liveSnapshots[liveKey]
                if (closedSnapshot && service.isManualInboxEntry(closedSnapshot)) {
                    // Sender-side closure must not mark a normal Inbox row as
                    // read. It only removes the transient popup; the user can
                    // dismiss the retained row later.
                    service.removePopupByIdentity(originalId, closedSnapshot.timestamp)
                    console.info("[NOTIFICATIONS] notification.sender_closed inbox_retained app=" + closedSnapshot.app)
                } else {
                    var removed = false
                    for (var i = service.activeModel.count - 1; i >= 0; i--) {
                        var row = service.activeModel.get(i)
                        if (row && String(row.originalId) === String(originalId) &&
                            Number(row.timestamp) === Number(closedSnapshot ? closedSnapshot.timestamp : 0)) {
                            removed = true
                            if (closedSnapshot) service.removeAt(i, "dismiss", originalId, closedSnapshot.timestamp)
                            else service.removeAt(i, "dismiss")
                        }
                    }
                    if (!removed && closedSnapshot) service.deletePopupFileFor(closedSnapshot)
                }
                delete service.liveRefs[liveKey]
                delete service.liveSnapshots[liveKey]
            })
        }

        if (doNotDisturb && !Logic.shouldBypassDnd(notification, 2)) {
            delete liveRefs[liveKey]
            delete liveSnapshots[liveKey]
            try { notification.tracked = false } catch (releaseError) {
                console.warn("[NOTIFICATIONS] notification.tracked_release_failed")
            }
            console.info("[NOTIFICATIONS] notification.silenced app=" + snapshot.app)
            return
        }

        persistPopupFile(snapshot)
        activeNotificationsModel.insert(0, snapshot)
        insertPopupSnapshot(snapshot)
        watchForUpdates(notification, liveKey)
        console.info("[NOTIFICATIONS] notification.received app=" + snapshot.app + " actions=" + snapshot.actions.length)
    }

    function removeAt(index, reason, expectedOriginalId, expectedTimestamp) {
        if (index < 0 || index >= activeNotificationsModel.count) return
        var entry = activeNotificationsModel.get(index)
        var hasExpectedIdentity = arguments.length >= 4 &&
            service.hasUsableIdentity(expectedOriginalId, expectedTimestamp)
        var lookupId = hasExpectedIdentity
            ? expectedOriginalId
            : (entry && entry.originalId !== undefined ? entry.originalId : -1)
        var lookupTimestamp = hasExpectedIdentity
            ? expectedTimestamp
            : (entry ? entry.timestamp : 0)
        var liveKey = service.identityKey(lookupId, lookupTimestamp)
        var liveSnapshot = liveKey !== "" ? liveSnapshots[liveKey] : null
        var entryHasIdentity = entry && service.hasUsableIdentity(entry.originalId, entry.timestamp)
        // ListModel.get() returns a live role object. Materialize it before
        // removing the model row; otherwise its roles can become undefined
        // before the persisted popup file is cleaned up.
        var entryIdentity = entryHasIdentity ? Logic.popupEntry(entry, 1) : null
        var liveIdentity = liveSnapshot && service.hasUsableIdentity(liveSnapshot.originalId, liveSnapshot.timestamp) ? liveSnapshot : null
        var removalSnapshot = liveIdentity || entryIdentity
        var originalId = removalSnapshot ? removalSnapshot.originalId : lookupId
        var removalKey = removalSnapshot
            ? service.identityKey(removalSnapshot.originalId, removalSnapshot.timestamp)
            : liveKey
        var restored = isRestoredPopup(removalSnapshot)
        var reference = restored ? null : liveRefs[removalKey]
        activeNotificationsModel.remove(index)
        if (removalSnapshot) {
            removePopupByIdentity(originalId, removalSnapshot.timestamp)
            deletePopupFileFor(removalSnapshot)
        }
        if (restored) delete restoredPopups[Logic.popupFileName(removalSnapshot)]
        if (reference) {
            try {
                if (reason === "expire" && typeof reference.expire === "function") reference.expire()
                else if (typeof reference.dismiss === "function") reference.dismiss()
            } catch (error) {
                console.warn("[NOTIFICATIONS] notification.reference_release_failed")
            }
        }
        if (liveRefs[removalKey] === reference) delete liveRefs[removalKey]
        delete liveSnapshots[removalKey]
    }

    function removeByIdentity(originalId, timestamp, reason, indexHint) {
        if (!service.hasUsableIdentity(originalId, timestamp)) return false
        var wantedId = String(originalId)
        var wantedTimestamp = Number(timestamp)
        for (var i = activeNotificationsModel.count - 1; i >= 0; i--) {
            var row = activeNotificationsModel.get(i)
            if (row && String(row.originalId) === wantedId && Number(row.timestamp) === wantedTimestamp) {
                removeAt(i, reason, originalId, timestamp)
                return true
            }
        }
        // Never use a stale delegate index when a valid identity no longer
        // matches. Another notification may now occupy that index; failing
        // closed preserves it for the correct delegate event.
        return false
    }

    function dismissAt(index, originalId, timestamp) {
        console.info("[NOTIFICATIONS] popup.dismiss index=" + index)
        if (arguments.length >= 3 && service.hasUsableIdentity(originalId, timestamp)) {
            return removeByIdentity(originalId, timestamp, "dismiss", index) ? "ok" : "none"
        }
        if (index < 0 || index >= activeNotificationsModel.count) return "none"
        var row = activeNotificationsModel.get(index)
        if (row && service.hasUsableIdentity(row.originalId, row.timestamp)) {
            removeAt(index, "dismiss", row.originalId, row.timestamp)
            console.info("[NOTIFICATIONS] popup.identity_recovered index=" + index)
        } else {
            removeAt(index, "dismiss")
        }
        return "ok"
    }

    function dismissPopupAt(index, originalId, timestamp) {
        console.info("[NOTIFICATIONS] popup.dismiss index=" + index)
        if (arguments.length >= 3 && service.hasUsableIdentity(originalId, timestamp)) {
            return removeByIdentity(originalId, timestamp, "dismiss", index) ? "ok" : "none"
        }
        if (index < 0 || index >= popupNotificationsModel.count) return "none"

        // The index belongs to popupNotificationsModel, not the active Inbox.
        // Recover the authoritative identity from that exact popup row before
        // resolving the corresponding active row. Never reinterpret a popup
        // index as an active-model index after delegate identity loss.
        var popupRow = popupNotificationsModel.get(index)
        if (!popupRow || !service.hasUsableIdentity(popupRow.originalId, popupRow.timestamp)) {
            console.error("[NOTIFICATIONS] popup.dismiss_skipped reason=invalid_identity")
            return "invalid"
        }
        var activeIndex = activeIndexForIdentity(popupRow.originalId, popupRow.timestamp)
        if (activeIndex < 0) {
            popupNotificationsModel.remove(index)
            console.info("[NOTIFICATIONS] popup.dismissed_only reason=active_row_unavailable")
            return "ok"
        }
        removeAt(activeIndex, "dismiss", popupRow.originalId, popupRow.timestamp)
        console.info("[NOTIFICATIONS] popup.identity_recovered source=popup index=" + index)
        return "ok"
    }

    function expireAt(index, originalId, timestamp) {
        console.info("[NOTIFICATIONS] popup.expire index=" + index)
        var identityProvided = arguments.length >= 3 &&
            service.hasUsableIdentity(originalId, timestamp)
        var popupIndex = identityProvided
            ? modelIndexByIdentity(popupNotificationsModel, originalId, timestamp)
            : index
        if (popupIndex < 0 && !identityProvided && index >= 0 && index < popupNotificationsModel.count)
            popupIndex = index
        if (popupIndex < 0 || popupIndex >= popupNotificationsModel.count) return
        var popupEntry = popupNotificationsModel.get(popupIndex)
        var popupId = identityProvided ? originalId : (popupEntry ? popupEntry.originalId : -1)
        var popupTimestamp = identityProvided ? timestamp : (popupEntry ? popupEntry.timestamp : 0)
        var popupKey = service.identityKey(popupId, popupTimestamp)
        var snapshot = (popupKey !== "" ? liveSnapshots[popupKey] : null) || popupEntry
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
            // drop the last popup copy and its persisted file.
            popupNotificationsModel.remove(popupIndex)
            if (snapshot) service.deletePopupFileFor(snapshot)
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
                var rowKey = service.identityKey(row.originalId, row.timestamp)
                var snapshot = rowKey !== "" ? liveSnapshots[rowKey] : null
                if (snapshot) removeAt(i, reason, snapshot.originalId, snapshot.timestamp)
                else if (service.hasUsableIdentity(row.originalId, row.timestamp))
                    removeAt(i, reason, row.originalId, row.timestamp)
                else removeAt(i, reason)
                return true
            }
        }
        return false
    }

    function activeIndexForIdentity(originalId, timestamp) {
        if (!service.hasUsableIdentity(originalId, timestamp)) return -1
        var wantedId = String(originalId)
        var wantedTimestamp = Number(timestamp)
        for (var i = 0; i < activeNotificationsModel.count; i++) {
            var row = activeNotificationsModel.get(i)
            if (row && String(row.originalId) === wantedId && Number(row.timestamp) === wantedTimestamp) return i
        }
        return -1
    }

    // Resolve a notification's authoritative snapshot without depending on the
    // caller's model index. Inbox rows come first, then the live snapshot, then
    // a transient popup row for notifications that never entered the Inbox.
    function snapshotForIdentity(originalId, timestamp) {
        if (!service.hasUsableIdentity(originalId, timestamp)) return null
        var activeIndex = activeIndexForIdentity(originalId, timestamp)
        if (activeIndex >= 0) return activeNotificationsModel.get(activeIndex)
        var key = service.identityKey(originalId, timestamp)
        if (key !== "" && liveSnapshots[key]) return liveSnapshots[key]
        var popupIndex = modelIndexByIdentity(popupNotificationsModel, originalId, timestamp)
        if (popupIndex >= 0) return popupNotificationsModel.get(popupIndex)
        return null
    }

    function objectProperty(object, name) {
        try {
            return object && object[name] !== undefined && object[name] !== null ? object[name] : null
        } catch (error) {
            console.warn("[NOTIFICATIONS] object_property_failed name=" + String(name))
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
        try { values = Hyprland.toplevels.values || [] } catch (error) {
            console.warn("[NOTIFICATIONS] workspace.toplevels_failed")
            return null
        }

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

        try { Hyprland.refreshToplevels() } catch (error) {
            console.warn("[NOTIFICATIONS] workspace.refresh_toplevels_failed")
        }
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
                    try { Hyprland.refreshWorkspaces() } catch (refreshError) {
                        console.warn("[NOTIFICATIONS] workspace.refresh_workspaces_failed")
                    }
                } catch (error) {
                    console.warn("[NOTIFICATIONS] workspace.activate_failed falling_back")
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
                console.warn("[NOTIFICATIONS] workspace.toplevel_activate_failed")
            }

            try { Hyprland.refreshWorkspaces() } catch (refreshError) {
                console.warn("[NOTIFICATIONS] workspace.refresh_workspaces_failed")
            }
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

    // Resolve a non-default action without depending on the sender's live
    // Quickshell object. A retained Inbox row can outlive its sender: Chromium
    // destroys its notification object on send, which deletes the live
    // reference while the Settings button stays rendered, and the destroyed
    // object refuses invoke(). The durable snapshot is the authoritative
    // fallback, exactly as invokeDefault already treats the live object.
    // The returned status is deliberately explicit so a caller cannot mistake a
    // sender-window route for the clicked action:
    //   delivered   - the live action.invoke() ran, or a genuine per-action
    //                 durable command was spawned
    //   executed    - only the notification-level execArgv was spawned
    //                 (fire-and-forget, not the clicked action)
    //   routed      - only the sender window was focused and the row removed
    //   unavailable - nothing could be delivered or routed
    //   none        - index/identity miss
    function invokeAction(index, identifier, originalId, timestamp) {
        if (arguments.length >= 4) {
            index = activeIndexForIdentity(originalId, timestamp)
            if (index < 0) return "none"
        }
        if (index < 0 || index >= activeNotificationsModel.count) return "none"
        var entry = activeNotificationsModel.get(index)
        var resolvedOriginalId = entry && entry.originalId !== undefined ? entry.originalId : originalId
        var resolvedTimestamp = entry && Number(entry.timestamp) > 0 ? entry.timestamp : timestamp
        var actionKey = service.identityKey(resolvedOriginalId, resolvedTimestamp)
        var reference = actionKey !== "" ? liveRefs[actionKey] : null
        if (reference && reference.actions) {
            for (var i = 0; i < reference.actions.length; i++) {
                var action = reference.actions[i]
                if (action && action.identifier === identifier && typeof action.invoke === "function") {
                    var liveRoute = Logic.workspaceRouteData(reference, entry)
                    try {
                        action.invoke()
                    } catch (error) {
                        console.warn("[NOTIFICATIONS] action.invoke_failed falling_back")
                        return service.invokeDurableAction(index, resolvedOriginalId, resolvedTimestamp, entry, identifier)
                    }
                    service.startWorkspaceRoute(liveRoute)
                    removeByIdentity(resolvedOriginalId, resolvedTimestamp, "action", index)
                    return "delivered"
                }
            }
        }
        return service.invokeDurableAction(index, resolvedOriginalId, resolvedTimestamp, entry, identifier)
    }

    // Build the validated action registry. Malformed entries are reported by
    // `reportActionRegistryRejections` and are never inserted into the table.
    function buildActionRegistry() {
        var base = ActionRegistry.buildDefaultRegistry()
        if (!service.testMode) return base
        var raw = Quickshell.env("AURELIA_NOTIFICATION_TEST_REGISTRY") || ""
        if (raw === "") return base
        try {
            var extra = JSON.parse(raw)
            if (!Array.isArray(extra)) return base
            return ActionRegistry.buildRegistry(ActionRegistry.DEFAULT_ENTRIES.concat(extra))
        } catch (error) {
            console.warn("[NOTIFICATIONS] action_registry_test_override_invalid")
            return base
        }
    }

    function reportActionRegistryRejections() {
        var rejected = service.actionRegistryBuild.rejected || []
        for (var i = 0; i < rejected.length; i++) {
            var item = rejected[i]
            console.warn("[NOTIFICATIONS] action_registry_rejected id=" + String(item.id || "") +
                " action=" + String(item.action || "") + " reason=" + String(item.reason || ""))
        }
    }

    // An explicit per-action command already present on the durable row. This
    // is the sender's own typed hint vector, never a shell string.
    function explicitActionCommand(entry, identifier) {
        if (!entry || !entry.actions) return null
        var actions = entry.actions
        var count = typeof actions.count === "number" ? actions.count : actions.length
        if (count === undefined) return null
        for (var i = 0; i < count; i++) {
            var action = typeof actions.get === "function" ? actions.get(i) : actions[i]
            if (!action || String(action.identifier || "") !== String(identifier || "")) continue
            var argv = Logic.parseExecArgv(action.execArgv || "")
            if (argv) return argv
            if (Array.isArray(action.argv) && action.argv.length > 0) return action.argv
            return null
        }
        return null
    }

    // The single registry resolution for a durable row. The context carries the
    // captured origin (the better Herdr identity) and the workspace number
    // parsed by the existing Herdr body owner, used only as a fallback. Nothing
    // sender-controlled reaches the registry as raw text.
    function resolveRegistryAction(entry, identifier) {
        if (!entry) return null
        var herdr = Logic.herdrRoute({ appName: entry.app, body: entry.body })
        return ActionRegistry.resolveForEntry(service.actionRegistry, entry, identifier, {
            origin: service.originFrom(entry),
            herdrNumber: herdr ? herdr.number : null
        })
    }

    // The executable argv for a durable action, or null. The reviewed registry
    // is the single owner of "what does this action actually run"; an explicit
    // per-action vector still wins.
    function durableActionCommand(entry, identifier) {
        var explicit = service.explicitActionCommand(entry, identifier)
        if (explicit) return explicit
        var resolved = service.resolveRegistryAction(entry, identifier)
        if (resolved && resolved.kind === "argv") return resolved.argv
        return null
    }

    // The origin a registry origin-focus entry resolves to, or null. The caller
    // hands it to `navigateToOrigin`, the single navigation owner.
    function durableActionOrigin(entry, identifier) {
        var resolved = service.resolveRegistryAction(entry, identifier)
        if (resolved && resolved.kind === "origin") return resolved.origin
        return null
    }

    // Durable fallback for invokeAction. The live reference may be absent (the
    // sender closed a retained Inbox row) or unusable (the notification object
    // was destroyed). Resolve the durable snapshot, run any explicit per-action
    // vector, then the reviewed registry action, then the notification-level
    // exec argv, then navigate to the captured origin. The row is removed only
    // when a command genuinely ran or the origin was genuinely focused.
    function invokeDurableAction(index, originalId, timestamp, entry, identifier) {
        var actionKey = service.identityKey(originalId, timestamp)
        var durable = service.snapshotForIdentity(originalId, timestamp) ||
            (actionKey !== "" ? service.liveSnapshots[actionKey] : null) || entry
        if (!durable) return "unavailable"
        var fallbackOrigin = service.originFrom(durable)
        var actionArgv = service.durableActionCommand(durable, identifier)
        if (actionArgv) {
            service.pendingCommandContext = {
                originalId: originalId, timestamp: timestamp, index: index,
                identifier: identifier, fallbackOrigin: fallbackOrigin
            }
            service.spawnNotificationCommand(actionArgv)
            return "delivered"
        }
        var registryOrigin = service.durableActionOrigin(durable, identifier)
        if (registryOrigin) {
            service.navigateToOrigin(registryOrigin, originalId, timestamp, "navigate:" + identifier)
            return "routed"
        }
        var argv = Logic.parseExecArgv(durable.execArgv)
        if (argv) {
            service.pendingCommandContext = {
                originalId: originalId, timestamp: timestamp, index: index,
                identifier: identifier, fallbackOrigin: fallbackOrigin
            }
            service.spawnNotificationCommand(argv)
            return "executed"
        }
        if (fallbackOrigin) {
            service.navigateToOrigin(fallbackOrigin, originalId, timestamp, "navigate:" + identifier)
            return "routed"
        }
        service.applyActionOutcome(originalId, timestamp, "unavailable", "no target")
        return "unavailable"
    }

    function isLiveDefaultAction(action) {
        if (!action) return false
        var identifier = String(action.identifier || "").toLowerCase()
        return identifier === "default" || identifier === "activate"
    }

    // Default activation, in resolution order:
    //   1. a live sender `default`/`Activate` action -- the only mechanism that
    //      reaches a browser's exact originating tab, while it is live;
    //   2. the reviewed action registry (for example Herdr's captured-origin
    //      Open), which is the single owner of a synthesized default action;
    //   3. the notification-level exec argv, through a bounded observed process;
    //   4. the captured origin, navigated by the shared helper.
    function invokeDefault(index, originalId, timestamp) {
        if (arguments.length >= 3) {
            index = activeIndexForIdentity(originalId, timestamp)
            if (index < 0) return "none"
        }
        if (index < 0 || index >= activeNotificationsModel.count) return "none"
        var entry = activeNotificationsModel.get(index)
        var resolvedOriginalId = entry && entry.originalId !== undefined ? entry.originalId : originalId
        var resolvedTimestamp = entry && Number(entry.timestamp) > 0 ? entry.timestamp : timestamp
        var actionKey = service.identityKey(resolvedOriginalId, resolvedTimestamp)
        var reference = actionKey !== "" ? liveRefs[actionKey] : null
        if (reference && reference.actions) {
            for (var i = 0; i < reference.actions.length; i++) {
                var action = reference.actions[i]
                if (!action || !service.isLiveDefaultAction(action) || typeof action.invoke !== "function") continue
                var liveRoute = Logic.workspaceRouteData(reference, entry)
                try {
                    action.invoke()
                } catch (error) {
                    console.warn("[NOTIFICATIONS] default.invoke_failed falling_back")
                    break
                }
                service.startWorkspaceRoute(liveRoute)
                removeByIdentity(resolvedOriginalId, resolvedTimestamp, "action", index)
                return "delivered"
            }
        }
        var fallbackEntry = (actionKey !== "" ? liveSnapshots[actionKey] : null) || entry
        var fallbackOrigin = service.originFrom(fallbackEntry)
        var registryArgv = service.durableActionCommand(fallbackEntry, "default")
        if (registryArgv) {
            service.pendingCommandContext = {
                originalId: resolvedOriginalId, timestamp: resolvedTimestamp, index: index,
                identifier: "default", fallbackOrigin: fallbackOrigin
            }
            service.spawnNotificationCommand(registryArgv)
            return "delivered"
        }
        var registryOrigin = service.durableActionOrigin(fallbackEntry, "default")
        if (registryOrigin) {
            service.navigateToOrigin(registryOrigin, resolvedOriginalId, resolvedTimestamp, "navigate:default")
            return "routed"
        }
        var argv = Logic.parseExecArgv(fallbackEntry ? fallbackEntry.execArgv : "")
        if (argv) {
            service.pendingCommandContext = {
                originalId: resolvedOriginalId, timestamp: resolvedTimestamp, index: index,
                identifier: "default", fallbackOrigin: fallbackOrigin
            }
            service.spawnNotificationCommand(argv)
            return "executed"
        }
        if (fallbackOrigin) {
            service.navigateToOrigin(fallbackOrigin, resolvedOriginalId, resolvedTimestamp, "navigate:default")
            return "routed"
        }
        service.applyActionOutcome(resolvedOriginalId, resolvedTimestamp, "unavailable", "no target")
        return "unavailable"
    }

    // Copy is a clipboard mutation, so it stays on the service rather than in
    // the presentational card. The card only emits copyRequested().
    function copyToClipboard(value) {
        var text = String(value === undefined || value === null ? "" : value)
        if (text === "") return "none"
        lastCopiedText = text
        if (!service.testMode) {
            Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy",
                "aurelia-notification-copy", text])
        }
        console.info("[NOTIFICATIONS] copy.performed length=" + text.length)
        return "ok"
    }

    function copyNotificationAt(index, originalId, timestamp) {
        var entry = null
        if (arguments.length >= 3) {
            entry = service.snapshotForIdentity(originalId, timestamp)
        } else if (index >= 0 && index < activeNotificationsModel.count) {
            entry = activeNotificationsModel.get(index)
        }
        if (!entry) return "none"
        return service.copyToClipboard(Logic.copyText(entry))
    }

    function openCenter() {
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
        var screenshotKey = service.identityKey(snapshot.originalId, snapshot.timestamp)
        if (screenshotKey === "") return "invalid-identity"
        liveSnapshots[screenshotKey] = snapshot
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
        active: !service.testMode
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
        service.reportActionRegistryRejections()
        if (!service.testMode) {
            probeNotificationBus()
            notificationBusHealthTimer.start()
        }
        if (stateDir === "") {
            console.error("[NOTIFICATIONS] state_directory_unavailable")
            return
        }
        ensureStateDirProcess.running = true
        Qt.callLater(function() {
            settingsFile.reload()
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
        model: service.testMode ? [] : Quickshell.screens

        Loader {
            required property var modelData
            active: !service.testMode
            source: active ? Qt.resolvedUrl("ui/NotificationPopupSurface.qml") : ""
            onLoaded: {
                if (!item) return
                if ("notificationService" in item) item.notificationService = service
                if ("screenModel" in item) item.screenModel = modelData
            }
            onStatusChanged: {
                if (status === Loader.Error)
                    console.error("[NOTIFICATIONS] popup_surface.load_failed")
            }
        }
    }

    Loader {
        id: centerPanel
        active: service.centerOpen && !service.testMode
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
