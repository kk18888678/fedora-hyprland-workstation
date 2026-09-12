import QtQuick

// Owns plugin Loader lifecycle and the small lifecycle contract exposed by
// shell IPC. Registry discovery, enabled state, and loading are separate so a
// malformed or failing plugin cannot become host logic.
Item {
    id: host

    property var registry: null
    property var shellApi: null
    property var appLibrary: null
    property var barWidgetRegistry: null
    property var loaders: ({})
    property var instances: ({})
    property var requested: ({})
    property var pendingOpens: ({})
    property int loadRevision: 0
    property bool reloading: false
    // null means a full plugin reload. A map means only the listed plugin
    // ids are being recreated; unrelated resident surfaces stay mounted.
    property var reloadingPluginIds: null
    // One compatibility identity for the built-in fallback. Generic routing
    // uses this seam instead of repeating a plugin id in lifecycle branches.
    property string defaultBarId: "aurelia.bar"

    signal pluginLoaded(string pluginId, string kind)
    signal pluginLoadFailed(string pluginId, string kind, string phase, string detail)
    signal pluginUnloaded(string pluginId, string kind, string reason)
    signal pluginReloaded(string pluginId)
    readonly property string selectedBarId: {
        var config = registry && registry.shellConfig ? registry.shellConfig.config : null
        var bar = config && config.bar ? config.bar : null
        var id = bar && typeof bar.id === "string" ? bar.id : host.defaultBarId
        return /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(id) ? id : host.defaultBarId
    }
    property string failedBarId: ""
    readonly property bool selectedBarAvailable: {
        var selected = selectedBarId
        var selectedManifest = manifestFor(selected)
        var failureRevision = registry ? registry.runtimeFailureRevision : 0
        if (!selectedManifest || !Array.isArray(selectedManifest.kinds) ||
            selectedManifest.kinds.indexOf("bar") === -1 || !selectedManifest.entryPoints ||
            typeof selectedManifest.entryPoints.bar !== "string") return false
        return registry.isEnabled(selected)
    }
    readonly property string activeBarId: selectedBarId !== failedBarId && selectedBarAvailable
        ? selectedBarId
        : host.defaultBarId

    function copyMap(source) {
        var result = {}
        for (var key in (source || {})) result[key] = source[key]
        return result
    }

    function manifestFor(id) {
        return registry && registry.isKnown(id) ? registry.installedPlugins[id] : null
    }

    function failureDetail(error) {
        try {
            if (registry && typeof registry.boundedFailureDetail === "function")
                return registry.boundedFailureDetail(error)
            return String(error || "plugin failure")
        } catch (e) {
            return "plugin failure detail unavailable"
        }
    }

    function hasActiveFailure(id, kind) {
        var failureRevision = registry ? registry.runtimeFailureRevision : 0
        return !!(registry && typeof registry.hasActiveRuntimeFailure === "function" &&
            registry.hasActiveRuntimeFailure(id, kind))
    }

    function sourceFor(id, kind) {
        try {
            return registry && typeof registry.entryPointUrl === "function"
                ? String(registry.entryPointUrl(id, kind) || "")
                : ""
        } catch (e) {
            return ""
        }
    }

    function recordFailure(id, kind, phase, error, sourcePath, entryPoint) {
        var pluginId = String(id || "").trim()
        var pluginKind = String(kind || "").trim() || "plugin"
        var source = String(sourcePath || "")
        var entry = String(entryPoint || pluginKind)
        var detail = host.failureDetail(error)
        if (!source) source = host.sourceFor(pluginId, pluginKind)
        try {
            if (registry && typeof registry.recordRuntimeFailure === "function")
                registry.recordRuntimeFailure(pluginId, pluginKind, phase || "runtime", source, entry, detail)
        } catch (registryError) {
            console.warn("[PLUGIN] aurelia.plugin.failure_recording_failed id=" + pluginId)
        }

        var hadInstance = !!host.instances[pluginId]
        if (pluginId === host.activeBarId && pluginId !== host.defaultBarId) host.failedBarId = pluginId

        var nextInstances = host.copyMap(host.instances)
        delete nextInstances[pluginId]
        host.instances = nextInstances
        var nextRequested = host.copyMap(host.requested)
        delete nextRequested[pluginId]
        host.requested = nextRequested
        var nextPending = host.copyMap(host.pendingOpens)
        delete nextPending[pluginId]
        host.pendingOpens = nextPending
        if (hadInstance) host.pluginUnloaded(pluginId, pluginKind, "failure")
        host.pluginLoadFailed(pluginId, pluginKind, phase || "runtime", detail)
        return false
    }

    function clearFailure(id, kind) {
        try {
            if (registry && typeof registry.clearRuntimeFailure === "function")
                registry.clearRuntimeFailure(id, kind)
        } catch (e) {
            console.warn("[PLUGIN] aurelia.plugin.failure_clear_failed id=" + String(id || ""))
        }
    }

    function scheduleFailure(id, kind, phase, error, sourcePath, entryPoint) {
        Qt.callLater(function() {
            if (!host.hasActiveFailure(id, kind))
                host.recordFailure(id, kind, phase, error, sourcePath, entryPoint)
        })
    }

    function invokeTarget(id, target, method, argument, kind, phase) {
        try {
            if (!target || typeof target[method] !== "function") return { ok: false, value: "not-loaded" }
            var value = argument === undefined || argument === null || argument === ""
                ? target[method]()
                : target[method](argument)
            return { ok: true, value: value }
        } catch (error) {
            host.recordFailure(id, kind || "plugin", phase || "callback", error)
            return { ok: false, value: "error" }
        }
    }

    function activeBar() {
        return itemFor(host.activeBarId)
    }

    function keepsResident(id) {
        var manifest = manifestFor(id)
        return !!(manifest && (manifest.keepLoaded === true ||
            (Array.isArray(manifest.kinds) && manifest.kinds.indexOf("service") !== -1)))
    }

    function shouldLoad(id) {
        var revision = loadRevision
        var manifest = manifestFor(id)
        var isReloadTarget = reloadingPluginIds === null || reloadingPluginIds[id] === true
        // Keep the resident bar host mapped during a generic plugin reload.
        // BarWidgetSlot owns the smaller widget-level reload boundary.
        // The notification service owns a process-wide session-bus name. Keep
        // that owner resident during targeted plugin reloads; its separate bar
        // widget still reloads through BarWidgetSlot. A full shell restart is
        // the explicit boundary for changing the service entry point.
        if (reloading && isReloadTarget && id !== host.defaultBarId &&
            !host.keepsResident(id)) return false
        if (!manifest || !registry.isEnabled(id)) return false
        var failureRevision = registry ? registry.runtimeFailureRevision : 0
        var primaryKind = registry && typeof registry.primaryKind === "function" ? registry.primaryKind(id) : ""
        if (host.hasActiveFailure(id, primaryKind)) return false
        if (Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar") !== -1 &&
            id !== host.activeBarId) return false
        if (manifest.keepLoaded === true || (manifest.kinds && manifest.kinds.indexOf("service") !== -1)) return true
        return requested[id] === true
    }

    function beginReload(pluginIds) {
        reloading = true
        reloadingPluginIds = pluginIds === undefined ? null : pluginIds

        // Reload is an explicit retry boundary. Clear only ephemeral failure
        // state; the registry never changes enabled state or persisted config.
        if (registry && typeof registry.clearRuntimeFailure === "function") {
            if (reloadingPluginIds === null) {
                var reloadIds = registry.pluginIds || []
                for (var reloadIndex = 0; reloadIndex < reloadIds.length; reloadIndex++)
                    registry.clearRuntimeFailure(reloadIds[reloadIndex])
            } else {
                for (var requestedId in reloadingPluginIds)
                    if (reloadingPluginIds[requestedId] === true) registry.clearRuntimeFailure(requestedId)
            }
        }

        var nextRequested = {}
        var nextPendingOpens = {}
        var nextInstances = {}
        for (var id in requested) {
            if (reloadingPluginIds === null || reloadingPluginIds[id] === true) continue
            nextRequested[id] = requested[id]
        }
        for (var pendingId in pendingOpens) {
            nextPendingOpens[pendingId] = pendingOpens[pendingId]
        }
        for (var instanceId in instances) {
            // A full reload preserves the default bar host; a targeted bar
            // change is allowed to recreate that default bar itself.
            var reloadInstance = reloadingPluginIds === null
                ? instanceId !== host.defaultBarId &&
                    !host.keepsResident(instanceId)
                : reloadingPluginIds[instanceId] === true &&
                    (instanceId === host.defaultBarId || !host.keepsResident(instanceId))
            if (!reloadInstance) nextInstances[instanceId] = instances[instanceId]
            else host.pluginUnloaded(instanceId,
                registry && typeof registry.primaryKind === "function"
                    ? registry.primaryKind(instanceId) : "plugin", "reload")
        }
        requested = nextRequested
        pendingOpens = nextPendingOpens
        instances = nextInstances
        loadRevision++
    }

    function finishReload() {
        var reloadedIds = []
        if (registry) {
            if (reloadingPluginIds === null) reloadedIds = registry.pluginIds || []
            else reloadedIds = Object.keys(reloadingPluginIds || {})
        }
        reloading = false
        reloadingPluginIds = null
        loadRevision++
        for (var i = 0; i < reloadedIds.length; i++) host.pluginReloaded(reloadedIds[i])
    }

    function loaderFor(id) {
        return loaders[id] || null
    }

    function itemFor(id) {
        return instances[id] || null
    }

    function removeInstance(id, reason) {
        var pluginId = String(id || "")
        var existing = instances[pluginId]
        if (!existing) return false
        var next = host.copyMap(host.instances)
        delete next[pluginId]
        host.instances = next
        host.pluginUnloaded(pluginId,
            registry && typeof registry.primaryKind === "function" ? registry.primaryKind(pluginId) : "plugin",
            reason || "unload")
        return true
    }

    function configurePlugin(id, target) {
        if (!target || !registry) return
        var manifest = manifestFor(id)
        if (!manifest) return
        // Entry points intentionally do not declare these as required: a URL
        // Loader constructs the object before onLoaded, and a required
        // property would fail before the host could inject it.
        if ("aureliaPath" in target) target.aureliaPath = registry.packageRoot
        if ("shell" in target) target.shell = shellApi
        if ("appLibrary" in target) target.appLibrary = host.appLibrary
        if ("bar" in target) target.bar = host.activeBar()
        if ("shellConfig" in target) target.shellConfig = registry.shellConfig
        if ("manifest" in target) target.manifest = manifest
        if ("pluginRegistry" in target) target.pluginRegistry = registry
        if ("barWidgetRegistry" in target) target.barWidgetRegistry = barWidgetRegistry
    }

    function completePendingOpen(id, target) {
        var pending = pendingOpens[id]
        if (!pending) return true
        var queue = Array.isArray(pending) ? pending.slice() : [pending]
        if (!target || typeof target.open !== "function") {
            host.recordFailure(id, registry.primaryKind(id), "initialization", "plugin has no open method")
            return false
        }
        var next = copyMap(pendingOpens)
        delete next[id]
        pendingOpens = next
        for (var i = 0; i < queue.length; i++) {
            if (!host.invokeTarget(id, target, "open", queue[i].payloadJson || "{}",
                registry.primaryKind(id), "callback").ok) return false
        }
        return true
    }

    function setRequested(id, value) {
        var next = copyMap(requested)
        if (value) next[id] = true
        else delete next[id]
        requested = next
        loadRevision++
    }

    function callBarWidget(id, method, argument) {
        var bar = host.activeBar()
        if (!bar || typeof bar.callWidget !== "function") return "not-loaded"
        try {
            return bar.callWidget(id, method, argument)
        } catch (error) {
            host.recordFailure(id, "bar-widget", "callback", error)
            return "error"
        }
    }

    function open(id, payloadJson) {
        if (!registry || !registry.isKnown(id)) return "unknown"
        if (!registry.isEnabled(id)) return "disabled"
        if (host.hasActiveFailure(id, registry.primaryKind(id))) return "error"
        var barResult = callBarWidget(id, "open", payloadJson || "{}")
        if (barResult !== "not-loaded") return barResult || "ok"
        setRequested(id, true)
        var target = itemFor(id)
        if (!target) {
            var pending = copyMap(pendingOpens)
            var queue = Array.isArray(pending[id]) ? pending[id].slice() : (pending[id] ? [pending[id]] : [])
            queue.push({ payloadJson: payloadJson || "{}" })
            pending[id] = queue
            pendingOpens = pending
            return "pending"
        }
        if (typeof target.open !== "function") return "invalid"
        return host.invokeTarget(id, target, "open", payloadJson || "{}",
            registry.primaryKind(id), "callback").ok ? "ok" : "error"
    }

    function close(id) {
        if (!registry || !registry.isKnown(id)) return "unknown"
        if (host.hasActiveFailure(id, registry.primaryKind(id))) return "error"
        var barResult = callBarWidget(id, "close", "")
        if (barResult !== "not-loaded") return barResult || "ok"
        var target = itemFor(id)
        if (target && typeof target.close === "function" &&
            !host.invokeTarget(id, target, "close", undefined, registry.primaryKind(id), "callback").ok) return "error"
        var manifest = manifestFor(id)
        if (!manifest || manifest.keepLoaded !== true) setRequested(id, false)
        return target ? "ok" : "not-loaded"
    }

    function isVisible(id) {
        if (host.hasActiveFailure(id, registry && typeof registry.primaryKind === "function" ? registry.primaryKind(id) : "")) return false
        var barResult = callBarWidget(id, "isVisible", "")
        if (barResult !== "not-loaded") return barResult === true || barResult === "true"
        var target = itemFor(id)
        if (!target) return false
        if (typeof target.isVisible === "function")
            return host.invokeTarget(id, target, "isVisible", undefined, registry.primaryKind(id), "callback").value === true
        return target.visible === true
    }

    function toggle(id, payloadJson) {
        if (registry && registry.isKnown(id) && host.hasActiveFailure(id, registry.primaryKind(id))) return "error"
        var barResult = callBarWidget(id, "toggle", payloadJson || "{}")
        if (barResult !== "not-loaded") return barResult || "ok"
        var target = itemFor(id)
        if (target && typeof target.toggle === "function")
            return host.invokeTarget(id, target, "toggle", payloadJson || "{}",
                registry.primaryKind(id), "callback").ok ? "ok" : "error"
        if (isVisible(id)) return close(id)
        return open(id, payloadJson || "{}")
    }

    function call(id, method, argument) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(method || ""))) return "invalid-method"
        var barResult = callBarWidget(id, method, argument)
        if (barResult !== "not-loaded") return barResult
        var target = itemFor(id)
        if (!target || typeof target[method] !== "function") return "not-loaded"
        if (registry && registry.isKnown(id) && host.hasActiveFailure(id, registry.primaryKind(id))) return "error"
        var outcome = host.invokeTarget(id, target, method, argument, registry.primaryKind(id), "callback")
        return outcome.ok ? String(outcome.value || "") : "error"
    }

    function catalog() {
        if (!registry) return { plugins: [], rejected: [], scan: {} }
        var catalog = typeof registry.pluginCatalog === "function"
            ? registry.pluginCatalog()
            : { plugins: registry.pluginSummaries(), rejected: [], scan: {} }
        var result = catalog.plugins || []
        var bar = host.activeBar()
        for (var i = 0; i < result.length; i++) {
            result[i].loaded = !!itemFor(result[i].id) || !!(bar && typeof bar.hasWidget === "function" && bar.hasWidget(result[i].id))
            result[i].visible = isVisible(result[i].id)
        }
        catalog.plugins = result
        return catalog
    }

    function summaries() {
        return host.catalog().plugins
    }

    Connections {
        target: host.registry
        function onPluginsChanged() {
            host.failedBarId = ""
            host.loadRevision++
        }

        function onPluginFailureRecorded(pluginId, kind) {
            if (String(pluginId || "") === host.selectedBarId &&
                (String(kind || "") === "bar" || String(kind || "") === "bar-widget") &&
                host.selectedBarId !== host.defaultBarId) host.failedBarId = host.selectedBarId
        }
    }

    Connections {
        target: host.registry ? host.registry.shellConfig : null
        function onConfigChanged() {
            host.failedBarId = ""
            host.loadRevision++
        }
    }

    Repeater {
        id: pluginRepeater
        model: host.registry ? host.registry.pluginIds : []

        delegate: Loader {
            property string pluginId: modelData
            active: host.shouldLoad(pluginId)
            asynchronous: false
            source: active ? host.registry.entryPointUrl(pluginId, host.registry.primaryKind(pluginId)) : ""

            onLoaded: {
                var pluginKind = host.registry.primaryKind(pluginId)
                try {
                    host.configurePlugin(pluginId, item)
                    // This optional namespaced hook gives plugins an explicit
                    // host-controlled initialization boundary. Existing
                    // plugins are unchanged because the hook is opt-in.
                    if (item && typeof item.aureliaInitialize === "function") item.aureliaInitialize()
                    var next = host.copyMap(host.instances)
                    next[pluginId] = item
                    host.instances = next
                    if (!host.completePendingOpen(pluginId, item)) return
                    host.clearFailure(pluginId, pluginKind)
                    host.pluginLoaded(pluginId, pluginKind)
                    console.info("[PLUGIN] aurelia.plugin.loaded id=" + pluginId)
                } catch (error) {
                    host.scheduleFailure(pluginId, pluginKind, "initialization", error, source, pluginKind)
                }
            }

            onStatusChanged: {
                if (status === Loader.Error && !host.hasActiveFailure(pluginId, host.registry.primaryKind(pluginId)))
                    host.scheduleFailure(pluginId, host.registry.primaryKind(pluginId), "load",
                        "Loader.Error", source, host.registry.primaryKind(pluginId))
            }

            onActiveChanged: {
                if (!active) Qt.callLater(function() {
                    if (!active) host.removeInstance(pluginId, "unload")
                })
            }
        }

        onItemRemoved: function(index, item) {
            if (!item) return
            host.removeInstance(item.pluginId, "repeater-removed")
        }
    }
}
