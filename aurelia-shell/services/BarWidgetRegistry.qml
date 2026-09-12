import QtQuick

// Component catalogue and registration boundary for manifest-backed bar
// widgets. PluginRegistry owns discovery and identity; this object owns only
// the bar-widget projection consumed by the active bar and its slots.
QtObject {
    id: root

    property var pluginRegistry: null
    property var widgets: ({})
    property int revision: 0

    signal widgetCatalogChanged()
    signal widgetRegistered(string pluginId)
    signal widgetRemoved(string pluginId)

    function copyMap(source) {
        var result = {}
        for (var key in (source || {})) result[key] = source[key]
        return result
    }

    function sync() {
        var next = {}
        if (root.pluginRegistry) {
            var ids = root.pluginRegistry.pluginIds || []
            for (var i = 0; i < ids.length; i++) {
                var id = ids[i]
                var manifest = root.pluginRegistry.installedPlugins[id]
                if (!manifest || !Array.isArray(manifest.kinds) || manifest.kinds.indexOf("bar-widget") === -1) continue
                next[id] = {
                    id: id,
                    name: String(manifest.name || id),
                    version: String(manifest.version || ""),
                    description: String(manifest.description || ""),
                    barWidget: manifest.barWidget || null,
                    firstParty: manifest.__isFirstParty === true
                }
            }
        }

        var previous = root.widgets
        root.widgets = next
        root.revision++
        var nextIds = Object.keys(next)
        var previousIds = Object.keys(previous || {})
        for (var added = 0; added < nextIds.length; added++)
            if (!previous[nextIds[added]]) root.widgetRegistered(nextIds[added])
        for (var removed = 0; removed < previousIds.length; removed++)
            if (!next[previousIds[removed]]) root.widgetRemoved(previousIds[removed])
        root.widgetCatalogChanged()
    }

    readonly property var widgetIds: {
        var currentRevision = root.revision
        var ids = Object.keys(root.widgets || {})
        ids.sort()
        return ids
    }

    function hasWidget(id) {
        var currentRevision = root.revision
        return !!root.widgets[String(id || "")]
    }

    function widgetFor(id) {
        var currentRevision = root.revision
        return root.widgets[String(id || "")] || null
    }

    function manifestFor(id) {
        var widget = root.widgetFor(id)
        if (!widget || !root.pluginRegistry) return null
        return root.pluginRegistry.installedPlugins[String(id || "")] || null
    }

    function metadataFor(id) {
        var widget = root.widgetFor(id)
        return widget && widget.barWidget ? widget.barWidget : null
    }

    function displayNameFor(id) {
        var widget = root.widgetFor(id)
        var metadata = root.metadataFor(id)
        return metadata && typeof metadata.displayName === "string"
            ? metadata.displayName : (widget ? widget.name : String(id || ""))
    }

    function descriptionFor(id) {
        var widget = root.widgetFor(id)
        var metadata = root.metadataFor(id)
        return metadata && typeof metadata.description === "string"
            ? metadata.description : (widget ? widget.description : "")
    }

    function categoryFor(id) {
        var metadata = root.metadataFor(id)
        return metadata && typeof metadata.category === "string" ? metadata.category : ""
    }

    function cloneJson(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (e) {
            return null
        }
    }

    function defaultsFor(id) {
        var metadata = root.metadataFor(id)
        return metadata && metadata.defaults && typeof metadata.defaults === "object" &&
            !Array.isArray(metadata.defaults) ? root.cloneJson(metadata.defaults) || ({}) : ({})
    }

    function defaultSectionFor(id) {
        var metadata = root.metadataFor(id)
        var section = metadata && typeof metadata.defaultSection === "string"
            ? metadata.defaultSection : "center"
        return ["left", "center", "right"].indexOf(section) !== -1 ? section : "center"
    }

    function allowMultipleFor(id) {
        var metadata = root.metadataFor(id)
        return metadata && typeof metadata.allowMultiple === "boolean" ? metadata.allowMultiple : null
    }

    function schemaFor(id) {
        var metadata = root.metadataFor(id)
        return metadata && Array.isArray(metadata.schema) ? root.cloneJson(metadata.schema) || [] : []
    }

    function settingsFormFor(id) {
        var metadata = root.metadataFor(id)
        return metadata && typeof metadata.settingsForm === "string" ? metadata.settingsForm : ""
    }

    function settingsFor(id, entry) {
        var result = root.defaultsFor(id)
        if (!entry || typeof entry !== "object" || Array.isArray(entry)) return result
        var explicit = {}
        for (var key in entry) {
            if (key !== "id" && key !== "settings" && key !== "instanceId") {
                result[key] = entry[key]
                explicit[key] = true
            }
        }
        if (entry.settings && typeof entry.settings === "object" && !Array.isArray(entry.settings)) {
            for (var nestedKey in entry.settings) {
                if (!explicit[nestedKey]) result[nestedKey] = entry.settings[nestedKey]
            }
        }
        return result
    }

    function instanceIdFor(id, entry) {
        var configured = entry && typeof entry === "object" && !Array.isArray(entry)
            ? entry.instanceId : ""
        return typeof configured === "string" &&
            /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(configured) ? configured : String(id || "")
    }

    function entryPointUrl(id) {
        var currentRevision = root.revision
        return root.pluginRegistry && typeof root.pluginRegistry.entryPointUrl === "function"
            ? root.pluginRegistry.entryPointUrl(String(id || ""), "bar-widget")
            : ""
    }

    function isEnabled(id) {
        return !!(root.pluginRegistry && typeof root.pluginRegistry.isEnabled === "function" &&
            root.pluginRegistry.isEnabled(String(id || "")))
    }

    function hasActiveFailure(id) {
        return !!(root.pluginRegistry && typeof root.pluginRegistry.hasActiveRuntimeFailure === "function" &&
            root.pluginRegistry.hasActiveRuntimeFailure(String(id || ""), "bar-widget"))
    }

    function summaries() {
        var result = []
        var ids = root.widgetIds
        for (var i = 0; i < ids.length; i++) {
            var widget = root.widgets[ids[i]]
            result.push({
                id: widget.id,
                name: widget.name,
                version: widget.version,
                description: widget.description,
                barWidget: widget.barWidget,
                firstParty: widget.firstParty,
                enabled: root.isEnabled(widget.id),
                failed: root.hasActiveFailure(widget.id),
                entryPoint: root.entryPointUrl(widget.id)
            })
        }
        return result
    }

    property Connections pluginRegistryConnection: Connections {
        target: root.pluginRegistry
        function onPluginsChanged() {
            root.sync()
        }
    }

    Component.onCompleted: root.sync()
}
