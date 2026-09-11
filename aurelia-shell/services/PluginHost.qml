import QtQuick

// Owns plugin Loader lifecycle and the small lifecycle contract exposed by
// shell IPC. Registry discovery, enabled state, and loading are separate so a
// malformed or failing plugin cannot become host logic.
Item {
    id: host

    property var registry: null
    property var shellApi: null
    property var appLibrary: null
    property var loaders: ({})
    property var instances: ({})
    property var requested: ({})
    property var pendingOpens: ({})
    property int loadRevision: 0
    property bool reloading: false
    // null means a full plugin reload. A map means only the listed plugin
    // ids are being recreated; unrelated resident surfaces stay mounted.
    property var reloadingPluginIds: null
    readonly property string selectedBarId: {
        var config = registry && registry.shellConfig ? registry.shellConfig.config : null
        var bar = config && config.bar ? config.bar : null
        var id = bar && typeof bar.id === "string" ? bar.id : "aurelia.bar"
        return /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(id) ? id : "aurelia.bar"
    }
    property string failedBarId: ""
    readonly property bool selectedBarAvailable: {
        var selected = selectedBarId
        var selectedManifest = manifestFor(selected)
        if (!selectedManifest || !Array.isArray(selectedManifest.kinds) ||
            selectedManifest.kinds.indexOf("bar") === -1 || !selectedManifest.entryPoints ||
            typeof selectedManifest.entryPoints.bar !== "string") return false
        return registry.isEnabled(selected)
    }
    readonly property string activeBarId: selectedBarId !== failedBarId && selectedBarAvailable
        ? selectedBarId
        : "aurelia.bar"

    function copyMap(source) {
        var result = {}
        for (var key in (source || {})) result[key] = source[key]
        return result
    }

    function manifestFor(id) {
        return registry && registry.isKnown(id) ? registry.installedPlugins[id] : null
    }

    function activeBar() {
        return itemFor(host.activeBarId)
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
        if (reloading && isReloadTarget && id !== "aurelia.bar" && id !== "aurelia.notifications") return false
        if (!manifest || !registry.isEnabled(id)) return false
        if (Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar") !== -1 &&
            id !== host.activeBarId) return false
        if (manifest.keepLoaded === true || (manifest.kinds && manifest.kinds.indexOf("service") !== -1)) return true
        return requested[id] === true
    }

    function beginReload(pluginIds) {
        reloading = true
        reloadingPluginIds = pluginIds === undefined ? null : pluginIds

        var nextRequested = {}
        var nextPendingOpens = {}
        var nextInstances = {}
        for (var id in requested) {
            if (reloadingPluginIds === null || reloadingPluginIds[id] === true) continue
            nextRequested[id] = requested[id]
        }
        for (var pendingId in pendingOpens) {
            if (reloadingPluginIds === null || reloadingPluginIds[pendingId] === true) continue
            nextPendingOpens[pendingId] = pendingOpens[pendingId]
        }
        for (var instanceId in instances) {
            // A full reload preserves the bar host; a targeted Bar.qml change
            // is allowed to recreate aurelia.bar itself.
            var reloadInstance = reloadingPluginIds === null
                ? instanceId !== "aurelia.bar" && instanceId !== "aurelia.notifications"
                : reloadingPluginIds[instanceId] === true && instanceId !== "aurelia.notifications"
            if (!reloadInstance) nextInstances[instanceId] = instances[instanceId]
        }
        requested = nextRequested
        pendingOpens = nextPendingOpens
        instances = nextInstances
        loadRevision++
    }

    function finishReload() {
        reloading = false
        reloadingPluginIds = null
        loadRevision++
    }

    function loaderFor(id) {
        return loaders[id] || null
    }

    function itemFor(id) {
        return instances[id] || null
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
    }

    function completePendingOpen(id, target) {
        var pending = pendingOpens[id]
        if (!pending || !target || typeof target.open !== "function") return
        var next = copyMap(pendingOpens)
        delete next[id]
        pendingOpens = next
        target.open(pending.payloadJson || "{}")
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
        return bar.callWidget(id, method, argument)
    }

    function open(id, payloadJson) {
        if (!registry || !registry.isKnown(id)) return "unknown"
        if (!registry.isEnabled(id)) return "disabled"
        var barResult = callBarWidget(id, "open", payloadJson || "{}")
        if (barResult !== "not-loaded") return barResult || "ok"
        setRequested(id, true)
        var target = itemFor(id)
        if (!target) {
            var pending = copyMap(pendingOpens)
            pending[id] = { payloadJson: payloadJson || "{}" }
            pendingOpens = pending
            return "pending"
        }
        if (typeof target.open !== "function") return "invalid"
        target.open(payloadJson || "{}")
        return "ok"
    }

    function close(id) {
        if (!registry || !registry.isKnown(id)) return "unknown"
        var barResult = callBarWidget(id, "close", "")
        if (barResult !== "not-loaded") return barResult || "ok"
        var target = itemFor(id)
        if (target && typeof target.close === "function") target.close()
        var manifest = manifestFor(id)
        if (!manifest || manifest.keepLoaded !== true) setRequested(id, false)
        return target ? "ok" : "not-loaded"
    }

    function isVisible(id) {
        var barResult = callBarWidget(id, "isVisible", "")
        if (barResult !== "not-loaded") return barResult === true || barResult === "true"
        var target = itemFor(id)
        if (!target) return false
        if (typeof target.isVisible === "function") return target.isVisible()
        return target.visible === true
    }

    function toggle(id, payloadJson) {
        var barResult = callBarWidget(id, "toggle", payloadJson || "{}")
        if (barResult !== "not-loaded") return barResult || "ok"
        if (isVisible(id)) return close(id)
        return open(id, payloadJson || "{}")
    }

    function call(id, method, argument) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(method || ""))) return "invalid-method"
        var barResult = callBarWidget(id, method, argument)
        if (barResult !== "not-loaded") return barResult
        var target = itemFor(id)
        if (!target || typeof target[method] !== "function") return "not-loaded"
        if (argument === undefined || argument === null || argument === "") return String(target[method]() || "")
        return String(target[method](argument) || "")
    }

    function summaries() {
        if (!registry) return []
        var result = registry.pluginSummaries()
        var bar = host.activeBar()
        for (var i = 0; i < result.length; i++) {
            result[i].loaded = !!itemFor(result[i].id) || !!(bar && typeof bar.hasWidget === "function" && bar.hasWidget(result[i].id))
            result[i].visible = isVisible(result[i].id)
        }
        return result
    }

    Connections {
        target: host.registry
        function onPluginsChanged() {
            host.failedBarId = ""
            host.loadRevision++
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
                host.configurePlugin(pluginId, item)
                var next = host.copyMap(host.instances)
                next[pluginId] = item
                host.instances = next
                host.completePendingOpen(pluginId, item)
                console.info("[PLUGIN] aurelia.plugin.loaded id=" + pluginId)
            }

            onStatusChanged: {
                if (status === Loader.Error) {
                    console.warn("[PLUGIN] aurelia.plugin.load_failed id=" + pluginId)
                    if (pluginId === host.activeBarId && pluginId !== "aurelia.bar")
                        host.failedBarId = pluginId
                    var removed = host.copyMap(host.instances)
                    delete removed[pluginId]
                    host.instances = removed
                }
            }
        }

        onItemRemoved: function(index, item) {
            if (!item) return
            var removed = host.copyMap(host.instances)
            delete removed[item.pluginId]
            host.instances = removed
        }
    }
}
