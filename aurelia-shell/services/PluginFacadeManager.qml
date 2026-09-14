import QtQuick

// Owns detached third-party facade construction, refresh, and revocation.
// PluginHost remains the lifecycle owner; this service keeps the facade
// capability boundary from becoming part of the host's Loader state machine.
Item {
    id: manager

    property var host: null
    property var registryApiComponent: null
    property var shellApiComponent: null
    property var barApiComponent: null
    property var barWidgetRegistryApiComponent: null
    property var appLibraryApiComponent: null
    property var scopedRegistryApis: ({})
    property var scopedShellApis: ({})
    property var scopedBarApis: ({})
    property var scopedBarApiOwners: ({})
    property var scopedBarWidgetRegistryApis: ({})
    property var scopedAppLibraryApis: ({})
    property var scopedFacadeProfiles: ({})

    function publicPluginManifest(manifest) {
        if (!manager.host) return null
        var copy = manager.host.cloneJson(manifest)
        if (!copy) return null
        var keys = Object.keys(copy)
        for (var i = 0; i < keys.length; i++)
            if (keys[i].indexOf("__") === 0) delete copy[keys[i]]
        return copy
    }

    function publicBarConfig() {
        var registry = manager.host ? manager.host.registry : null
        var config = registry && registry.shellConfig ? registry.shellConfig.config : ({})
        return manager.host ? manager.host.cloneJson(config && config.bar ? config.bar : {}) || ({}) : ({})
    }

    function publicBarWidgetSnapshot() {
        var host = manager.host
        var source = host && host.barWidgetRegistry ? host.barWidgetRegistry.widgets : ({})
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
        var registry = manager.host ? manager.host.registry : null
        var cloneSource = registry && typeof registry.cloneSourceIdForManifest === "function"
            ? registry.cloneSourceIdForManifest(manifest) : ""
        return (manifest.__isFirstParty === false ? "third" : "first") + "|" + kinds.join(",") + "|" + cloneSource
    }

    function activeThirdParty(id) {
        var host = manager.host
        var registry = host ? host.registry : null
        var manifest = host ? host.manifestFor(id) : null
        return !!(manifest && manifest.__isFirstParty === false && registry && registry.isEnabled(id))
    }

    function destroyFacade(value) {
        if (value && typeof value.destroy === "function") value.destroy()
    }

    function updateBarApiState(api) {
        if (!api || !manager.host) return
        var bar = manager.host.activeBar()
        api.barHidden = !!(bar && bar.barHidden === true)
        api.barSize = bar ? Math.max(0, Number(bar.barSize || 0)) : 0
        api.position = bar ? String(bar.position || "top") : "top"
        api.vertical = !!(bar && bar.vertical === true)
        api.foreground = bar && bar.foreground !== undefined ? bar.foreground : "transparent"
        api.barForeground = bar && bar.barForeground !== undefined ? bar.barForeground : api.foreground
        api.background = bar && bar.background !== undefined ? bar.background : "transparent"
        api.urgent = bar && bar.urgent !== undefined ? bar.urgent : "transparent"
        api.transparent = !!(bar && bar.transparent === true)
        api.foregroundAnimationEnabled = !(bar && bar.foregroundAnimationEnabled === false)
        api.activePopoutId = bar ? String(bar.activePopoutId || "") : ""
    }

    function scopedRegistryApiFor(pluginId) {
        var host = manager.host
        var registry = host ? host.registry : null
        var id = String(pluginId || "")
        if (!id || !manager.registryApiComponent || !manager.activeThirdParty(id)) return null
        var cached = manager.scopedRegistryApis[id]
        if (cached) return cached
        var manifest = host.manifestFor(id)
        var api = manager.registryApiComponent.createObject(null, {
            pluginId: id,
            compatibilityId: registry && typeof registry.cloneSourceIdForManifest === "function"
                ? registry.cloneSourceIdForManifest(manifest) : "",
            manifest: manager.publicPluginManifest(manifest),
            enabled: registry.isEnabled(id),
            registryRevision: registry.registryRevision,
            _hasActiveFailure: function(kind) { return host.hasActiveFailure(id, kind) },
            _entryPointUrl: function(kind) {
                var requestedKind = String(kind || "") === "barWidget" ? "bar-widget" : String(kind || "")
                return host.sourceFor(id, requestedKind)
            }
        })
        if (!api) return null
        var next = host.copyMap(manager.scopedRegistryApis)
        next[id] = api
        manager.scopedRegistryApis = next
        var profiles = host.copyMap(manager.scopedFacadeProfiles)
        profiles[id] = manager.facadeProfile(manifest)
        manager.scopedFacadeProfiles = profiles
        return api
    }

    function scopedBarApiFor(pluginId, instanceId, ownerObject) {
        var host = manager.host
        var registry = host ? host.registry : null
        var id = String(pluginId || "")
        var instance = String(instanceId || id)
        var key = id + "::" + instance
        if (!id || !manager.barApiComponent || !manager.activeThirdParty(id)) return null
        var cached = manager.scopedBarApis[key]
        if (cached && manager.scopedBarApiOwners[key] === ownerObject) {
            manager.updateBarApiState(cached)
            return cached
        }
        if (cached) manager.destroyFacade(cached)
        var manifest = host.manifestFor(id)
        var api = manager.barApiComponent.createObject(null, {
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
                console.warn("[PLUGIN] scoped_popout_request_failed id=" + id)
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
                console.warn("[PLUGIN] scoped_popout_release_failed id=" + id)
                return false
            }
        }
        api._invoke = function(method, argument) {
            var bar = host.activeBar()
            if (!bar || typeof bar.callWidget !== "function") return "not-loaded"
            try {
                return bar.callWidget(instance, method, argument)
            } catch (e) {
                console.warn("[PLUGIN] scoped_widget_call_failed id=" + id +
                    " method=" + String(method || ""))
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
        manager.updateBarApiState(api)
        var next = host.copyMap(manager.scopedBarApis)
        next[key] = api
        manager.scopedBarApis = next
        var owners = host.copyMap(manager.scopedBarApiOwners)
        owners[key] = ownerObject
        manager.scopedBarApiOwners = owners
        var profiles = host.copyMap(manager.scopedFacadeProfiles)
        profiles[key] = manager.facadeProfile(host.manifestFor(id))
        manager.scopedFacadeProfiles = profiles
        return api
    }

    function scopedBarWidgetRegistryApiFor(pluginId) {
        var host = manager.host
        var id = String(pluginId || "")
        if (!id || !manager.barWidgetRegistryApiComponent || !manager.activeThirdParty(id)) return null
        var cached = manager.scopedBarWidgetRegistryApis[id]
        if (cached) return cached
        var api = manager.barWidgetRegistryApiComponent.createObject(null, {
            widgets: manager.publicBarWidgetSnapshot(),
            revision: host.barWidgetRegistry ? host.barWidgetRegistry.revision : 0
        })
        if (!api) return null
        var next = host.copyMap(manager.scopedBarWidgetRegistryApis)
        next[id] = api
        manager.scopedBarWidgetRegistryApis = next
        var profiles = host.copyMap(manager.scopedFacadeProfiles)
        profiles[id] = manager.facadeProfile(host.manifestFor(id))
        manager.scopedFacadeProfiles = profiles
        return api
    }

    function scopedAppLibraryApiFor(pluginId) {
        var host = manager.host
        var id = String(pluginId || "")
        if (!id || !manager.appLibraryApiComponent || !manager.activeThirdParty(id)) return null
        var cached = manager.scopedAppLibraryApis[id]
        if (cached) return cached
        var api = manager.appLibraryApiComponent.createObject(null, {
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
        var next = host.copyMap(manager.scopedAppLibraryApis)
        next[id] = api
        manager.scopedAppLibraryApis = next
        var profiles = host.copyMap(manager.scopedFacadeProfiles)
        profiles[id] = manager.facadeProfile(host.manifestFor(id))
        manager.scopedFacadeProfiles = profiles
        return api
    }

    function scopedShellApiFor(pluginId, instanceId, ownerObject) {
        var host = manager.host
        var registry = host ? host.registry : null
        var id = String(pluginId || "")
        var instance = String(instanceId || id)
        var key = id + "::" + instance
        if (!id || !manager.shellApiComponent || !manager.activeThirdParty(id)) return null
        var cached = manager.scopedShellApis[key]
        if (cached) return cached
        var manifest = host.manifestFor(id)
        var targetId = instance || id
        var api = manager.shellApiComponent.createObject(null, {
            pluginId: id,
            compatibilityId: registry && typeof registry.cloneSourceIdForManifest === "function"
                ? registry.cloneSourceIdForManifest(manifest) : "",
            bar: manager.scopedBarApiFor(id, instance, ownerObject),
            appLibrary: manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("menu") !== -1
                ? manager.scopedAppLibraryApiFor(id) : null,
            barConfig: manager.publicBarConfig(),
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
        var next = host.copyMap(manager.scopedShellApis)
        next[key] = api
        manager.scopedShellApis = next
        var profiles = host.copyMap(manager.scopedFacadeProfiles)
        profiles[key] = manager.facadeProfile(manifest)
        manager.scopedFacadeProfiles = profiles
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
        var host = manager.host
        var profiles = manager.scopedFacadeProfiles
        var profilesNext = {}
        var registryNext = {}
        for (var registryId in manager.scopedRegistryApis) {
            var registryManifest = host.manifestFor(registryId)
            var registryProfile = manager.facadeProfile(registryManifest)
            if (manager.activeThirdParty(registryId) && profiles[registryId] === registryProfile) {
                registryNext[registryId] = manager.scopedRegistryApis[registryId]
                profilesNext[registryId] = registryProfile
            } else {
                manager.destroyFacade(manager.scopedRegistryApis[registryId])
            }
        }

        var shellNext = {}
        for (var shellKey in manager.scopedShellApis) {
            var shellOwner = manager.facadeOwnerId(shellKey)
            var shellManifest = host.manifestFor(shellOwner)
            var shellProfile = manager.facadeProfile(shellManifest)
            if (manager.activeThirdParty(shellOwner) && profiles[shellKey] === shellProfile) {
                shellNext[shellKey] = manager.scopedShellApis[shellKey]
                profilesNext[shellKey] = shellProfile
            } else {
                manager.destroyFacade(manager.scopedShellApis[shellKey])
            }
        }

        var barNext = {}
        var ownerNext = {}
        for (var barKey in manager.scopedBarApis) {
            var barOwner = manager.facadeOwnerId(barKey)
            var barProfile = manager.facadeProfile(host.manifestFor(barOwner))
            if (manager.activeThirdParty(barOwner) && profiles[barKey] === barProfile) {
                barNext[barKey] = manager.scopedBarApis[barKey]
                ownerNext[barKey] = manager.scopedBarApiOwners[barKey]
                profilesNext[barKey] = barProfile
            } else {
                manager.destroyFacade(manager.scopedBarApis[barKey])
            }
        }

        var widgetNext = {}
        for (var widgetId in manager.scopedBarWidgetRegistryApis) {
            var widgetProfile = manager.facadeProfile(host.manifestFor(widgetId))
            if (manager.activeThirdParty(widgetId) && profiles[widgetId] === widgetProfile) {
                widgetNext[widgetId] = manager.scopedBarWidgetRegistryApis[widgetId]
                profilesNext[widgetId] = widgetProfile
            } else manager.destroyFacade(manager.scopedBarWidgetRegistryApis[widgetId])
        }

        var appNext = {}
        for (var appId in manager.scopedAppLibraryApis) {
            var appProfile = manager.facadeProfile(host.manifestFor(appId))
            if (manager.activeThirdParty(appId) && profiles[appId] === appProfile) {
                appNext[appId] = manager.scopedAppLibraryApis[appId]
                profilesNext[appId] = appProfile
            } else manager.destroyFacade(manager.scopedAppLibraryApis[appId])
        }

        manager.scopedRegistryApis = registryNext
        manager.scopedShellApis = shellNext
        manager.scopedBarApis = barNext
        manager.scopedBarApiOwners = ownerNext
        manager.scopedBarWidgetRegistryApis = widgetNext
        manager.scopedAppLibraryApis = appNext
        manager.scopedFacadeProfiles = profilesNext
    }

    function syncScopedFacades() {
        var host = manager.host
        var registry = host ? host.registry : null
        if (!registry) return
        manager.pruneScopedFacades()
        for (var registryId in manager.scopedRegistryApis) {
            var registryApi = manager.scopedRegistryApis[registryId]
            var manifest = host.manifestFor(registryId)
            registryApi.manifest = manager.publicPluginManifest(manifest)
            registryApi.enabled = !!manifest && registry.isEnabled(registryId)
            registryApi.registryRevision = registry.registryRevision
        }
        for (var shellKey in manager.scopedShellApis) {
            var shellApi = manager.scopedShellApis[shellKey]
            var shellTargetId = manager.facadeInstanceId(shellKey)
            shellApi.barConfig = manager.publicBarConfig()
            shellApi.settings = typeof registry.settingsForEntry === "function"
                ? registry.settingsForEntry(shellTargetId, {}) : ({})
            manager.updateBarApiState(shellApi.bar)
        }
        for (var barKey in manager.scopedBarApis) manager.updateBarApiState(manager.scopedBarApis[barKey])
        for (var widgetId in manager.scopedBarWidgetRegistryApis) {
            var widgetApi = manager.scopedBarWidgetRegistryApis[widgetId]
            widgetApi.widgets = manager.publicBarWidgetSnapshot()
            widgetApi.revision = host.barWidgetRegistry ? host.barWidgetRegistry.revision : 0
        }
    }
}
