import QtQuick

// Owns plugin Loader lifecycle and the small lifecycle contract exposed by
// shell IPC. Registry discovery, enabled state, and loading are separate so a
// malformed or failing plugin cannot become host logic.
Item {
    id: host

    property var registry: null
    property var shellApi: null
    property var loaders: ({})
    property var instances: ({})
    property var requested: ({})
    property var pendingOpens: ({})
    property int loadRevision: 0

    function copyMap(source) {
        var result = {}
        for (var key in (source || {})) result[key] = source[key]
        return result
    }

    function manifestFor(id) {
        return registry && registry.isKnown(id) ? registry.installedPlugins[id] : null
    }

    function shouldLoad(id) {
        var revision = loadRevision
        var manifest = manifestFor(id)
        if (!manifest || !registry.isEnabled(id)) return false
        if (manifest.keepLoaded === true || (manifest.kinds && manifest.kinds.indexOf("service") !== -1)) return true
        return requested[id] === true
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

    function open(id, payloadJson) {
        if (!registry || !registry.isKnown(id)) return "unknown"
        if (!registry.isEnabled(id)) return "disabled"
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
        var target = itemFor(id)
        if (target && typeof target.close === "function") target.close()
        var manifest = manifestFor(id)
        if (!manifest || manifest.keepLoaded !== true) setRequested(id, false)
        return target ? "ok" : "not-loaded"
    }

    function isVisible(id) {
        var target = itemFor(id)
        if (!target) return false
        if (typeof target.isVisible === "function") return target.isVisible()
        return target.visible === true
    }

    function toggle(id, payloadJson) {
        if (isVisible(id)) return close(id)
        return open(id, payloadJson || "{}")
    }

    function call(id, method, argument) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(method || ""))) return "invalid-method"
        var target = itemFor(id)
        if (!target || typeof target[method] !== "function") return "not-loaded"
        if (argument === undefined || argument === null || argument === "") return String(target[method]() || "")
        return String(target[method](argument) || "")
    }

    function summaries() {
        if (!registry) return []
        var result = registry.pluginSummaries()
        for (var i = 0; i < result.length; i++) {
            result[i].loaded = !!itemFor(result[i].id)
            result[i].visible = isVisible(result[i].id)
        }
        return result
    }

    Connections {
        target: host.registry
        function onPluginsChanged() {
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
