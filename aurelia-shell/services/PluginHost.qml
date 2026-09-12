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
    property var scopedRegistryApis: ({})
    property var scopedShellApis: ({})
    property var scopedBarApis: ({})
    property var scopedBarApiOwners: ({})
    property var scopedBarWidgetRegistryApis: ({})
    property var scopedAppLibraryApis: ({})
    property var scopedFacadeProfiles: ({})
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

    function cloneJson(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (e) {
            return null
        }
    }

    function publicPluginManifest(manifest) {
        var copy = host.cloneJson(manifest)
        if (!copy) return null
        var keys = Object.keys(copy)
        for (var i = 0; i < keys.length; i++)
            if (keys[i].indexOf("__") === 0) delete copy[keys[i]]
        return copy
    }

    function publicBarConfig() {
        var config = registry && registry.shellConfig ? registry.shellConfig.config : ({})
        return host.cloneJson(config && config.bar ? config.bar : {}) || ({})
    }

    function publicBarWidgetSnapshot() {
        var source = host.barWidgetRegistry ? host.barWidgetRegistry.widgets : ({})
        var snapshot = {}
        for (var id in (source || {})) {
            var entry = source[id]
            if (!entry) continue
            var metadata = host.cloneJson(entry.barWidget) || ({})
            if (metadata.displayName === undefined) metadata.displayName = String(entry.name || id)
            if (metadata.description === undefined) metadata.description = String(entry.description || "")
            if (metadata.category === undefined) metadata.category = "Plugin"
            if (metadata.allowMultiple === undefined) metadata.allowMultiple = false
            if (metadata.defaults === undefined) metadata.defaults = ({})
            if (metadata.settingsForm === undefined) metadata.settingsForm = ""
            if (metadata.schema === undefined) metadata.schema = []
            snapshot[id] = {
                id: id,
                name: String(entry.name || id),
                version: String(entry.version || ""),
                description: String(entry.description || ""),
                metadata: metadata
            }
        }
        return snapshot
    }

    function facadeProfile(manifest) {
        if (!manifest) return ""
        var kinds = Array.isArray(manifest.kinds) ? manifest.kinds.slice() : []
        kinds.sort()
        var cloneSource = registry && typeof registry.cloneSourceIdForManifest === "function"
            ? registry.cloneSourceIdForManifest(manifest) : ""
        return (manifest.__isFirstParty === false ? "third" : "first") + "|" + kinds.join(",") + "|" + cloneSource
    }

    function activeThirdParty(id) {
        var manifest = host.manifestFor(id)
        return !!(manifest && manifest.__isFirstParty === false && registry && registry.isEnabled(id))
    }

    function destroyFacade(value) {
        if (value && typeof value.destroy === "function") value.destroy()
    }

    function updateBarApiState(api) {
        if (!api) return
        var bar = host.activeBar()
        api.barHidden = !!(bar && bar.barHidden === true)
        api.barSize = bar ? Math.max(0, Number(bar.barSize || 0)) : 0
        api.position = bar ? String(bar.position || "top") : "top"
        api.vertical = !!(bar && bar.vertical === true)
        api.activePopoutId = bar ? String(bar.activePopoutId || "") : ""
    }

    function manifestFor(id) {
        return registry && registry.isKnown(id) ? registry.installedPlugins[id] : null
    }

    function scopedRegistryApiFor(pluginId) {
        var id = String(pluginId || "")
        if (!id || !registryApiComponent || !activeThirdParty(id)) return null
        var cached = host.scopedRegistryApis[id]
        if (cached) return cached
        var manifest = host.manifestFor(id)
        var api = registryApiComponent.createObject(null, {
            pluginId: id,
            compatibilityId: registry && typeof registry.cloneSourceIdForManifest === "function"
                ? registry.cloneSourceIdForManifest(manifest) : "",
            manifest: host.publicPluginManifest(manifest),
            enabled: registry.isEnabled(id),
            registryRevision: registry.registryRevision,
            _hasActiveFailure: function(kind) { return host.hasActiveFailure(id, kind) },
            _entryPointUrl: function(kind) {
                var requestedKind = String(kind || "") === "barWidget" ? "bar-widget" : String(kind || "")
                return host.sourceFor(id, requestedKind)
            }
        })
        if (!api) return null
        var next = host.copyMap(host.scopedRegistryApis)
        next[id] = api
        host.scopedRegistryApis = next
        var profiles = host.copyMap(host.scopedFacadeProfiles)
        profiles[id] = host.facadeProfile(manifest)
        host.scopedFacadeProfiles = profiles
        return api
    }

    function scopedBarApiFor(pluginId, instanceId, ownerObject) {
        var id = String(pluginId || "")
        var instance = String(instanceId || id)
        var key = id + "::" + instance
        if (!id || !barApiComponent || !host.activeThirdParty(id)) return null
        var cached = host.scopedBarApis[key]
        if (cached && host.scopedBarApiOwners[key] === ownerObject) {
            host.updateBarApiState(cached)
            return cached
        }
        if (cached) host.destroyFacade(cached)
        var manifest = host.manifestFor(id)
        var api = barApiComponent.createObject(null, {
            ownerPluginId: id,
            instanceId: instance,
            compatibilityId: registry && typeof registry.cloneSourceIdForManifest === "function"
                ? registry.cloneSourceIdForManifest(manifest) : ""
        })
        if (!api) return null
        api._requestPopout = function() {
            var bar = host.activeBar()
            if (!ownerObject || !bar || typeof bar.requestPopout !== "function") return false
            try {
                bar.requestPopout(ownerObject, instance)
                return true
            } catch (e) {
                return false
            }
        }
        api._releasePopout = function() {
            var bar = host.activeBar()
            if (!ownerObject || !bar || typeof bar.releasePopout !== "function") return false
            try {
                bar.releasePopout(ownerObject)
                return true
            } catch (e) {
                return false
            }
        }
        api._invoke = function(method, argument) {
            var bar = host.activeBar()
            if (!bar || typeof bar.callWidget !== "function") return "not-loaded"
            try {
                return bar.callWidget(instance, method, argument)
            } catch (e) {
                return "error"
            }
        }
        api._registerClickTarget = function() {
            var bar = host.activeBar()
            if (!ownerObject || !bar || typeof bar.registerWidgetSlot !== "function") return false
            bar.registerWidgetSlot(ownerObject)
            return true
        }
        api._unregisterClickTarget = function() {
            var bar = host.activeBar()
            if (!ownerObject || !bar || typeof bar.unregisterWidgetSlot !== "function") return false
            bar.unregisterWidgetSlot(ownerObject)
            return true
        }
        host.updateBarApiState(api)
        var next = host.copyMap(host.scopedBarApis)
        next[key] = api
        host.scopedBarApis = next
        var owners = host.copyMap(host.scopedBarApiOwners)
        owners[key] = ownerObject
        host.scopedBarApiOwners = owners
        var profiles = host.copyMap(host.scopedFacadeProfiles)
        profiles[key] = host.facadeProfile(host.manifestFor(id))
        host.scopedFacadeProfiles = profiles
        return api
    }

    function scopedBarWidgetRegistryApiFor(pluginId) {
        var id = String(pluginId || "")
        if (!id || !barWidgetRegistryApiComponent || !activeThirdParty(id)) return null
        var cached = host.scopedBarWidgetRegistryApis[id]
        if (cached) return cached
        var api = barWidgetRegistryApiComponent.createObject(null, {
            widgets: host.publicBarWidgetSnapshot(),
            revision: host.barWidgetRegistry ? host.barWidgetRegistry.revision : 0
        })
        if (!api) return null
        var next = host.copyMap(host.scopedBarWidgetRegistryApis)
        next[id] = api
        host.scopedBarWidgetRegistryApis = next
        var profiles = host.copyMap(host.scopedFacadeProfiles)
        profiles[id] = host.facadeProfile(host.manifestFor(id))
        host.scopedFacadeProfiles = profiles
        return api
    }

    function scopedAppLibraryApiFor(pluginId) {
        var id = String(pluginId || "")
        if (!id || !appLibraryApiComponent || !activeThirdParty(id)) return null
        var cached = host.scopedAppLibraryApis[id]
        if (cached) return cached
        var api = appLibraryApiComponent.createObject(null, {
            ownerPluginId: id,
            _rows: function(query) {
                return host.appLibrary && typeof host.appLibrary.appRows === "function"
                    ? host.appLibrary.appRows(query) : []
            },
            _iconSource: function(icon) {
                return host.appLibrary && typeof host.appLibrary.iconSource === "function"
                    ? host.appLibrary.iconSource(icon) : ""
            }
        })
        if (!api) return null
        var next = host.copyMap(host.scopedAppLibraryApis)
        next[id] = api
        host.scopedAppLibraryApis = next
        var profiles = host.copyMap(host.scopedFacadeProfiles)
        profiles[id] = host.facadeProfile(host.manifestFor(id))
        host.scopedFacadeProfiles = profiles
        return api
    }

    function scopedShellApiFor(pluginId, instanceId, ownerObject) {
        var id = String(pluginId || "")
        var instance = String(instanceId || id)
        var key = id + "::" + instance
        if (!id || !shellApiComponent || !activeThirdParty(id)) return null
        var cached = host.scopedShellApis[key]
        if (cached) return cached
        var manifest = host.manifestFor(id)
        var targetId = instance || id
        var api = shellApiComponent.createObject(null, {
            pluginId: id,
            compatibilityId: registry && typeof registry.cloneSourceIdForManifest === "function"
                ? registry.cloneSourceIdForManifest(manifest) : "",
            bar: host.scopedBarApiFor(id, instance, ownerObject),
            appLibrary: manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("menu") !== -1
                ? host.scopedAppLibraryApiFor(id) : null,
            barConfig: host.publicBarConfig(),
            settings: registry && typeof registry.settingsForEntry === "function"
                ? registry.settingsForEntry(targetId, {}) : ({}),
            _serviceLookup: function() { return host.itemFor(id) },
            _summon: function(payloadJson) {
                var result = host.open(id, payloadJson || "{}")
                return result === "ok" || result === "pending"
            },
            _hide: function() { return host.close(id) === "ok" },
            _toggle: function(payloadJson) {
                var result = host.toggle(id, payloadJson || "{}")
                return result === "ok" || result === "pending" || result === "closed"
            },
            _isOpen: function() { return host.isVisible(id) },
            _settingsFor: function(selector) {
                return registry && typeof registry.settingsForEntry === "function"
                    ? registry.settingsForEntry(targetId, selector || ({})) : ({})
            },
            _updateSettings: function(settings, selector) {
                return !!(registry && typeof registry.updateEntryInline === "function" &&
                    registry.updateEntryInline(targetId, settings, selector || ({})))
            },
            _resetSettings: function(selector) {
                return !!(registry && typeof registry.resetEntryInline === "function" &&
                    registry.resetEntryInline(targetId, selector || ({})))
            }
        })
        if (!api) return null
        var next = host.copyMap(host.scopedShellApis)
        next[key] = api
        host.scopedShellApis = next
        var profiles = host.copyMap(host.scopedFacadeProfiles)
        profiles[key] = host.facadeProfile(manifest)
        host.scopedFacadeProfiles = profiles
        return api
    }

    function facadeOwnerId(cacheKey) {
        var key = String(cacheKey || "")
        var separator = key.indexOf("::")
        return separator === -1 ? key : key.substring(0, separator)
    }

    function facadeInstanceId(cacheKey) {
        var key = String(cacheKey || "")
        var separator = key.indexOf("::")
        return separator === -1 ? key : key.substring(separator + 2)
    }

    function pruneScopedFacades() {
        var profiles = host.scopedFacadeProfiles
        var profilesNext = {}
        var registryNext = {}
        for (var registryId in host.scopedRegistryApis) {
            var registryManifest = host.manifestFor(registryId)
            var registryProfile = host.facadeProfile(registryManifest)
            if (host.activeThirdParty(registryId) && profiles[registryId] === registryProfile) {
                registryNext[registryId] = host.scopedRegistryApis[registryId]
                profilesNext[registryId] = registryProfile
            } else {
                host.destroyFacade(host.scopedRegistryApis[registryId])
            }
        }

        var shellNext = {}
        for (var shellKey in host.scopedShellApis) {
            var shellOwner = host.facadeOwnerId(shellKey)
            var shellManifest = host.manifestFor(shellOwner)
            var shellProfile = host.facadeProfile(shellManifest)
            if (host.activeThirdParty(shellOwner) && profiles[shellKey] === shellProfile) {
                shellNext[shellKey] = host.scopedShellApis[shellKey]
                profilesNext[shellKey] = shellProfile
            } else {
                host.destroyFacade(host.scopedShellApis[shellKey])
            }
        }

        var barNext = {}
        var ownerNext = {}
        for (var barKey in host.scopedBarApis) {
            var barOwner = host.facadeOwnerId(barKey)
            var barProfile = host.facadeProfile(host.manifestFor(barOwner))
            if (host.activeThirdParty(barOwner) && profiles[barKey] === barProfile) {
                barNext[barKey] = host.scopedBarApis[barKey]
                ownerNext[barKey] = host.scopedBarApiOwners[barKey]
                profilesNext[barKey] = barProfile
            } else {
                host.destroyFacade(host.scopedBarApis[barKey])
            }
        }

        var widgetNext = {}
        for (var widgetId in host.scopedBarWidgetRegistryApis) {
            var widgetProfile = host.facadeProfile(host.manifestFor(widgetId))
            if (host.activeThirdParty(widgetId) && profiles[widgetId] === widgetProfile) {
                widgetNext[widgetId] = host.scopedBarWidgetRegistryApis[widgetId]
                profilesNext[widgetId] = widgetProfile
            } else host.destroyFacade(host.scopedBarWidgetRegistryApis[widgetId])
        }

        var appNext = {}
        for (var appId in host.scopedAppLibraryApis) {
            var appProfile = host.facadeProfile(host.manifestFor(appId))
            if (host.activeThirdParty(appId) && profiles[appId] === appProfile) {
                appNext[appId] = host.scopedAppLibraryApis[appId]
                profilesNext[appId] = appProfile
            } else host.destroyFacade(host.scopedAppLibraryApis[appId])
        }

        host.scopedRegistryApis = registryNext
        host.scopedShellApis = shellNext
        host.scopedBarApis = barNext
        host.scopedBarApiOwners = ownerNext
        host.scopedBarWidgetRegistryApis = widgetNext
        host.scopedAppLibraryApis = appNext
        host.scopedFacadeProfiles = profilesNext
    }

    function syncScopedFacades() {
        if (!registry) return
        host.pruneScopedFacades()
        for (var registryId in host.scopedRegistryApis) {
            var registryApi = host.scopedRegistryApis[registryId]
            var manifest = host.manifestFor(registryId)
            registryApi.manifest = host.publicPluginManifest(manifest)
            registryApi.enabled = !!manifest && registry.isEnabled(registryId)
            registryApi.registryRevision = registry.registryRevision
        }
        for (var shellKey in host.scopedShellApis) {
            var shellApi = host.scopedShellApis[shellKey]
            var shellTargetId = host.facadeInstanceId(shellKey)
            shellApi.barConfig = host.publicBarConfig()
            shellApi.settings = typeof registry.settingsForEntry === "function"
                ? registry.settingsForEntry(shellTargetId, {}) : ({})
            host.updateBarApiState(shellApi.bar)
        }
        for (var barKey in host.scopedBarApis) host.updateBarApiState(host.scopedBarApis[barKey])
        for (var widgetId in host.scopedBarWidgetRegistryApis) {
            var widgetApi = host.scopedBarWidgetRegistryApis[widgetId]
            widgetApi.widgets = host.publicBarWidgetSnapshot()
            widgetApi.revision = host.barWidgetRegistry ? host.barWidgetRegistry.revision : 0
        }
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
        var resolvedId = host.resolvePluginId(id)
        var failureRevision = registry ? registry.runtimeFailureRevision : 0
        return !!(registry && typeof registry.hasActiveRuntimeFailure === "function" &&
            registry.hasActiveRuntimeFailure(resolvedId, kind))
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

    function resolvePluginId(id) {
        var requested = String(id || "")
        try {
            if (registry && typeof registry.resolveEnabledId === "function") {
                var resolved = String(registry.resolveEnabledId(requested) || "")
                if (resolved !== "") return resolved
            }
        } catch (e) {}
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
            host.syncScopedFacades()
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
            host.syncScopedFacades()
            Qt.callLater(host.refreshPluginSettings)
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
