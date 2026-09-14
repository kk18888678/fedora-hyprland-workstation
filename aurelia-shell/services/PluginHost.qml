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
    property Component registryApiComponent: null
    property Component shellApiComponent: null
    property Component barApiComponent: null
    property Component barWidgetRegistryApiComponent: null
    property Component appLibraryApiComponent: null
    property var loaders: ({})
    property var instances: ({})
    property var requested: ({})
    property var pendingOpens: ({})
    property alias scopedRegistryApis: facadeManager.scopedRegistryApis
    property alias scopedShellApis: facadeManager.scopedShellApis
    property alias scopedBarApis: facadeManager.scopedBarApis
    property alias scopedBarApiOwners: facadeManager.scopedBarApiOwners
    property alias scopedBarWidgetRegistryApis: facadeManager.scopedBarWidgetRegistryApis
    property alias scopedAppLibraryApis: facadeManager.scopedAppLibraryApis
    property alias scopedFacadeProfiles: facadeManager.scopedFacadeProfiles
    property int loadRevision: 0
    property bool reloading: false
    property bool reloadDrainPending: false
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
    property bool selectedBarAvailable: false
    readonly property string activeBarId: selectedBarId !== failedBarId && selectedBarAvailable
        ? selectedBarId
        : host.defaultBarId

    function synchronizeBarSelection() {
        var selected = host.selectedBarId
        var selectedManifest = host.manifestFor(selected)
        var available = !!(selectedManifest && Array.isArray(selectedManifest.kinds) &&
            selectedManifest.kinds.indexOf("bar") !== -1 && selectedManifest.entryPoints &&
            typeof selectedManifest.entryPoints.bar === "string" &&
            host.registry && host.registry.isEnabled(selected))
        if (host.selectedBarAvailable !== available) host.selectedBarAvailable = available
    }

    onRegistryChanged: host.synchronizeBarSelection()
    onSelectedBarIdChanged: host.synchronizeBarSelection()

    function copyMap(source) {
        var result = {}
        for (var key in (source || {})) result[key] = source[key]
        return result
    }

    function cloneJson(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (e) {
            console.error("[PLUGIN] json_clone_failed")
            return null
        }
    }

    function publicPluginManifest(manifest) { return facadeManager.publicPluginManifest(manifest) }
    function publicBarConfig() { return facadeManager.publicBarConfig() }
    function publicBarWidgetSnapshot() { return facadeManager.publicBarWidgetSnapshot() }
    function facadeProfile(manifest) { return facadeManager.facadeProfile(manifest) }
    function activeThirdParty(id) { return facadeManager.activeThirdParty(id) }
    function scopedRegistryApiFor(pluginId) { return facadeManager.scopedRegistryApiFor(pluginId) }
    function scopedBarApiFor(pluginId, instanceId, ownerObject) {
        return facadeManager.scopedBarApiFor(pluginId, instanceId, ownerObject)
    }
    function scopedBarWidgetRegistryApiFor(pluginId) {
        return facadeManager.scopedBarWidgetRegistryApiFor(pluginId)
    }
    function scopedAppLibraryApiFor(pluginId) { return facadeManager.scopedAppLibraryApiFor(pluginId) }
    function scopedShellApiFor(pluginId, instanceId, ownerObject) {
        return facadeManager.scopedShellApiFor(pluginId, instanceId, ownerObject)
    }
    function pruneScopedFacades() { return facadeManager.pruneScopedFacades() }
    function syncScopedFacades() { return facadeManager.syncScopedFacades() }

    function manifestFor(id) {
        return registry && registry.isKnown(id) ? registry.installedPlugins[id] : null
    }

    function failureDetail(error) {
        try {
            if (registry && typeof registry.boundedFailureDetail === "function")
                return registry.boundedFailureDetail(error)
            return String(error || "plugin failure")
        } catch (e) {
            console.error("[PLUGIN] failure_detail_unavailable")
            return "plugin failure detail unavailable"
        }
    }

    function hasActiveFailure(id, kind) {
        var resolvedId = host.resolvePluginId(id)
        var failureRevision = registry ? registry.runtimeFailureRevision : 0
        return !!(registry && typeof registry.hasActiveRuntimeFailure === "function" &&
            registry.hasActiveRuntimeFailure(resolvedId, kind))
    }

    function sourceDescriptor(id, kind) {
        try {
            if (registry && typeof registry.sourceDescriptor === "function")
                return registry.sourceDescriptor(id, kind)
            var legacyUrl = registry && typeof registry.entryPointUrl === "function"
                ? String(registry.entryPointUrl(id, kind) || "") : ""
            return {
                valid: legacyUrl !== "",
                id: String(id || ""),
                kind: String(kind || ""),
                sourceRoot: "",
                relativeEntryPoint: "",
                sourcePath: "",
                url: legacyUrl,
                manifestPath: "",
                error: legacyUrl === "" ? "plugin source is unavailable" : ""
            }
        } catch (error) {
            console.warn("[PLUGIN] aurelia.plugin.source_descriptor_failed id=" + String(id || "") +
                " kind=" + String(kind || "") + " detail=" + host.failureDetail(error))
            return {
                valid: false,
                id: String(id || ""),
                kind: String(kind || ""),
                sourceRoot: "",
                relativeEntryPoint: "",
                sourcePath: "",
                url: "",
                manifestPath: "",
                error: "source descriptor resolution failed"
            }
        }
    }

    function sourceFor(id, kind) {
        var descriptor = host.sourceDescriptor(id, kind)
        return descriptor && descriptor.valid === true ? String(descriptor.url || "") : ""
    }

    function resolvePluginId(id) {
        var requested = String(id || "")
        try {
            if (registry && typeof registry.resolveEnabledId === "function") {
                var resolved = String(registry.resolveEnabledId(requested) || "")
                if (resolved !== "") return resolved
            }
        } catch (error) {
            console.warn("[PLUGIN] aurelia.plugin.resolve_id_failed id=" + requested +
                " detail=" + host.failureDetail(error))
        }
        return requested
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
        reloadDrainPending = false
        reloadDrainTimer.stop()
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
        if (!reloading || reloadDrainPending) return
        // Loader.active=false destroys the old plugin object asynchronously.
        // Keep the host in its reloading generation for one event-loop turn so
        // an entry point's IpcHandler is released before its replacement is
        // allowed to register the same target.
        reloadDrainPending = true
        reloadDrainTimer.restart()
    }

    function commitReload() {
        if (!reloading) {
            reloadDrainPending = false
            return
        }
        reloadDrainPending = false
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

    Timer {
        id: reloadDrainTimer
        interval: 0
        repeat: false
        onTriggered: host.commitReload()
    }

    function loaderFor(id) {
        return loaders[id] || null
    }

    function itemFor(id) {
        return instances[host.resolvePluginId(id)] || null
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

    function configurePluginTarget(id, target, context) {
        if (!target || !registry) return
        var manifest = manifestFor(id)
        if (!manifest) return
        var firstParty = manifest.__isFirstParty !== false
        var current = context || ({})
        var instanceId = String(current.instanceId || id)
        var configuredSettings = current.settings !== undefined ? current.settings :
            (registry.shellConfig && typeof registry.shellConfig.settingsForEntry === "function"
                ? registry.shellConfig.settingsForEntry(instanceId, {}) : ({}))

        // Entry points intentionally do not declare these as required: a URL
        // Loader constructs the object before onLoaded, and a required
        // property would fail before the host could inject it.
        if ("aureliaPath" in target) target.aureliaPath = registry.packageRoot
        if (firstParty) {
            if ("shell" in target) target.shell = shellApi
            if ("appLibrary" in target) target.appLibrary = host.appLibrary
            if ("bar" in target) target.bar = current.bar !== undefined ? current.bar : host.activeBar()
            if ("barAnchorItem" in target && current.barAnchorItem !== undefined)
                target.barAnchorItem = current.barAnchorItem
            if ("moduleName" in target) target.moduleName = id
            if ("shellConfig" in target) target.shellConfig = registry.shellConfig
            if ("settings" in target) target.settings = configuredSettings
            if ("manifest" in target) target.manifest = manifest
            if ("pluginRegistry" in target) target.pluginRegistry = registry
            if ("barWidgetRegistry" in target) target.barWidgetRegistry = barWidgetRegistry
            if ("pluginHost" in target) target.pluginHost = host
            return
        }

        if ("shell" in target) target.shell = host.scopedShellApiFor(id, instanceId, current.ownerObject || null)
        if ("appLibrary" in target) {
            target.appLibrary = manifest.kinds && manifest.kinds.indexOf("menu") !== -1
                ? host.scopedAppLibraryApiFor(id) : null
        }
        if ("bar" in target) target.bar = host.scopedBarApiFor(id, instanceId, current.ownerObject || null)
        if ("moduleName" in target) target.moduleName = instanceId
        if ("settings" in target) target.settings = configuredSettings
        if ("manifest" in target) target.manifest = host.publicPluginManifest(manifest)
        if ("pluginRegistry" in target) target.pluginRegistry = host.scopedRegistryApiFor(id)
        if ("barWidgetRegistry" in target)
            target.barWidgetRegistry = host.scopedBarWidgetRegistryApiFor(id)
    }

    function configurePlugin(id, target) {
        host.configurePluginTarget(id, target, {})
    }

    function refreshPluginSettings() {
        var currentInstances = host.copyMap(host.instances)
        for (var id in currentInstances) {
            var target = currentInstances[id]
            try {
                host.configurePlugin(id, target)
                if (target && typeof target.aureliaSettingsChanged === "function")
                    target.aureliaSettingsChanged()
            } catch (error) {
                host.recordFailure(id, registry.primaryKind(id), "settings", error)
            }
        }
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
        var resolvedId = host.resolvePluginId(id)
        var bar = host.activeBar()
        if (!bar || typeof bar.callWidget !== "function") return "not-loaded"
        try {
            return bar.callWidget(resolvedId, method, argument)
        } catch (error) {
            host.recordFailure(resolvedId, "bar-widget", "callback", error)
            return "error"
        }
    }

    function open(id, payloadJson) {
        var pluginId = host.resolvePluginId(id)
        if (!registry || !registry.isKnown(pluginId)) return "unknown"
        if (!registry.isEnabled(pluginId)) return "disabled"
        if (host.hasActiveFailure(pluginId, registry.primaryKind(pluginId))) return "error"
        var barResult = callBarWidget(pluginId, "open", payloadJson || "{}")
        if (barResult !== "not-loaded") return barResult || "ok"
        setRequested(pluginId, true)
        var target = itemFor(pluginId)
        if (!target) {
            var pending = copyMap(pendingOpens)
            var queue = Array.isArray(pending[pluginId]) ? pending[pluginId].slice() : (pending[pluginId] ? [pending[pluginId]] : [])
            queue.push({ payloadJson: payloadJson || "{}" })
            pending[pluginId] = queue
            pendingOpens = pending
            return "pending"
        }
        if (typeof target.open !== "function") return "invalid"
        return host.invokeTarget(pluginId, target, "open", payloadJson || "{}",
            registry.primaryKind(pluginId), "callback").ok ? "ok" : "error"
    }

    function close(id) {
        var pluginId = host.resolvePluginId(id)
        if (!registry || !registry.isKnown(pluginId)) return "unknown"
        if (host.hasActiveFailure(pluginId, registry.primaryKind(pluginId))) return "error"
        var barResult = callBarWidget(pluginId, "close", "")
        if (barResult !== "not-loaded") return barResult || "ok"
        var target = itemFor(pluginId)
        if (target && typeof target.close === "function" &&
            !host.invokeTarget(pluginId, target, "close", undefined, registry.primaryKind(pluginId), "callback").ok) return "error"
        var manifest = manifestFor(pluginId)
        if (!manifest || manifest.keepLoaded !== true) setRequested(pluginId, false)
        return target ? "ok" : "not-loaded"
    }

    function isVisible(id) {
        var pluginId = host.resolvePluginId(id)
        if (host.hasActiveFailure(pluginId, registry && typeof registry.primaryKind === "function" ? registry.primaryKind(pluginId) : "")) return false
        var barResult = callBarWidget(pluginId, "isVisible", "")
        if (barResult !== "not-loaded") return barResult === true || barResult === "true"
        var target = itemFor(pluginId)
        if (!target) return false
        if (typeof target.isVisible === "function")
            return host.invokeTarget(pluginId, target, "isVisible", undefined, registry.primaryKind(pluginId), "callback").value === true
        return target.visible === true
    }

    function toggle(id, payloadJson) {
        var pluginId = host.resolvePluginId(id)
        if (registry && registry.isKnown(pluginId) && host.hasActiveFailure(pluginId, registry.primaryKind(pluginId))) return "error"
        var barResult = callBarWidget(pluginId, "toggle", payloadJson || "{}")
        if (barResult !== "not-loaded") return barResult || "ok"
        var target = itemFor(pluginId)
        if (target && typeof target.toggle === "function")
            return host.invokeTarget(pluginId, target, "toggle", payloadJson || "{}",
                registry.primaryKind(pluginId), "callback").ok ? "ok" : "error"
        if (isVisible(pluginId)) return close(pluginId)
        return open(pluginId, payloadJson || "{}")
    }

    function call(id, method, argument) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(method || ""))) return "invalid-method"
        var pluginId = host.resolvePluginId(id)
        var barResult = callBarWidget(pluginId, method, argument)
        if (barResult !== "not-loaded") return barResult
        var target = itemFor(pluginId)
        if (!target || typeof target[method] !== "function") return "not-loaded"
        if (registry && registry.isKnown(pluginId) && host.hasActiveFailure(pluginId, registry.primaryKind(pluginId))) return "error"
        var outcome = host.invokeTarget(pluginId, target, method, argument, registry.primaryKind(pluginId), "callback")
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
            result[i].active = result[i].active === true || result[i].id === host.activeBarId
        }
        catalog.plugins = result
        return catalog
    }

    function summaries() {
        return host.catalog().plugins
    }

    PluginFacadeManager {
        id: facadeManager
        host: host
        registryApiComponent: host.registryApiComponent
        shellApiComponent: host.shellApiComponent
        barApiComponent: host.barApiComponent
        barWidgetRegistryApiComponent: host.barWidgetRegistryApiComponent
        appLibraryApiComponent: host.appLibraryApiComponent
    }

    Connections {
        target: host.registry
        function onPluginsChanged() {
            host.synchronizeBarSelection()
            host.failedBarId = ""
            host.loadRevision++
            host.syncScopedFacades()
        }

        function onPluginFailureRecorded(pluginId, kind) {
            if (String(pluginId || "") === host.selectedBarId &&
                (String(kind || "") === "bar" || String(kind || "") === "bar-widget") &&
                host.selectedBarId !== host.defaultBarId) {
                host.failedBarId = host.selectedBarId
                host.loadRevision++
            }
        }
    }

    Connections {
        target: host.registry ? host.registry.shellConfig : null
        function onConfigChanged() {
            host.synchronizeBarSelection()
            host.failedBarId = ""
            host.loadRevision++
            host.syncScopedFacades()
            Qt.callLater(host.refreshPluginSettings)
        }
    }

    Repeater {
        id: pluginRepeater
        model: host.registry ? host.registry.pluginIds : []

        delegate: Loader {
            id: pluginLoader
            property string pluginId: modelData
            readonly property string pluginKind: host.registry.primaryKind(pluginId)
            asynchronous: false
            readonly property var pluginSource: host.sourceDescriptor(pluginId, pluginKind)
            source: pluginSource && pluginSource.valid === true
                ? String(pluginSource.url || "") : ""

            // Do not bind Loader.active to a function that reads the host's
            // active-bar state. The Loader's own source/item lifecycle feeds
            // that state back through failure reporting, which creates a QML
            // binding loop during replacement-bar transitions. The host's
            // monotonic loadRevision is the explicit synchronization edge.
            function synchronizeActive() {
                var wanted = host.shouldLoad(pluginId)
                if (pluginLoader.active !== wanted) pluginLoader.active = wanted
            }

            Component.onCompleted: pluginLoader.synchronizeActive()

            Connections {
                target: host
                function onLoadRevisionChanged() { pluginLoader.synchronizeActive() }
                function onActiveBarIdChanged() { pluginLoader.synchronizeActive() }
                function onSelectedBarIdChanged() { pluginLoader.synchronizeActive() }
                function onSelectedBarAvailableChanged() { pluginLoader.synchronizeActive() }
                function onFailedBarIdChanged() { pluginLoader.synchronizeActive() }
            }

            Connections {
                target: host.registry
                function onRuntimeFailureRevisionChanged() { pluginLoader.synchronizeActive() }
            }

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
                    console.warn("[PLUGIN] aurelia.plugin.initialization_failed id=" + pluginId +
                        " kind=" + pluginKind)
                    host.scheduleFailure(pluginId, pluginKind, "initialization", error, source, pluginKind)
                }
            }

            onStatusChanged: {
                if (status === Loader.Error && !host.hasActiveFailure(pluginId, pluginKind))
                    host.scheduleFailure(pluginId, pluginKind, "load",
                        "Loader.Error", source, pluginKind)
            }

            onActiveChanged: {
                // The delegate itself owns this Loader lifecycle. Removing
                // the instance synchronously keeps an unloaded delegate from
                // leaving a callback behind in a destroyed QML context.
                if (!active) host.removeInstance(pluginId, "unload")
            }
        }

        onItemRemoved: function(index, item) {
            if (!item) return
            host.removeInstance(item.pluginId, "repeater-removed")
        }
    }
}
