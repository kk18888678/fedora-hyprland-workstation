import QtQuick

// Pure clone provenance and source-ID routing policy. The registry remains the
// public compatibility owner; this helper only keeps its implementation small.
QtObject {
    id: provenance

    property var registry: null

    function cloneSourceIdForManifest(manifest) {
        if (!manifest || !registry || !registry.isPlainObject(manifest.aurelia) ||
            !registry.hasField(manifest.aurelia, "clonedFrom")) return ""
        var sourceId = String(manifest.aurelia.clonedFrom || "")
        return registry.isValidPluginId(sourceId) ? sourceId : ""
    }

    function validatedCloneSourceId(manifest) {
        if (!manifest || manifest.__isFirstParty === true || !registry) return ""
        if (!registry.isPlainObject(manifest.aurelia) || !registry.hasField(manifest.aurelia, "clonedFrom")) return ""
        var sourceId = provenance.cloneSourceIdForManifest(manifest)
        var source = sourceId ? registry.installedPlugins[sourceId] : null
        if (!sourceId || sourceId === String(manifest.id || "") || !source || source.__isFirstParty !== true)
            return null
        return sourceId
    }

    function resolveEnabledId(id) {
        var requested = String(id || "")
        if (!registry || !registry.isValidPluginId(requested)) return requested
        var resolved = ""
        for (var candidate in registry.installedPlugins) {
            var manifest = registry.installedPlugins[candidate]
            if (manifest.__isFirstParty === true || provenance.cloneSourceIdForManifest(manifest) !== requested) continue
            if (!registry.isEnabled(candidate)) continue
            if (resolved !== "") return requested
            resolved = candidate
        }
        return resolved || requested
    }
}
