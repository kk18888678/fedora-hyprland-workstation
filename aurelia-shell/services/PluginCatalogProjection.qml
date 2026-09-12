import QtQuick

// Detached management/catalog rows. The registry owns identity and scan
// state; this projection owns the stable read model consumed by CLI and UI.
QtObject {
    id: projection

    property var registry: null

    function activeFor(manifest, id) {
        var config = projection.registry && projection.registry.shellConfig
            ? projection.registry.shellConfig.config : null
        return !!(manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar") !== -1 &&
            config && config.bar && config.bar.id === id)
    }

    function inBar(id) {
        var config = projection.registry && projection.registry.shellConfig
            ? projection.registry.shellConfig.config : null
        var owner = projection.registry && projection.registry.shellConfig
            ? projection.registry.shellConfig : null
        return !!(owner && typeof owner.findBarLocation === "function" &&
            owner.findBarLocation(config, id, "").found)
    }

    function build() {
        var owner = projection.registry
        if (!owner) return {plugins: [], rejected: [], scan: {}}
        var plugins = []
        var ids = Object.keys(owner.installedPlugins)
        ids.sort(function(left, right) {
            var leftName = String(owner.installedPlugins[left].name || left).toLowerCase()
            var rightName = String(owner.installedPlugins[right].name || right).toLowerCase()
            return leftName === rightName ? left.localeCompare(right) : leftName.localeCompare(rightName)
        })
        for (var i = 0; i < ids.length; i++) {
            var id = ids[i]
            var manifest = owner.installedPlugins[id]
            var sourceRoot = owner.boundedDiagnosticPath(manifest.__sourceDir || "")
            var manifestPath = owner.boundedDiagnosticPath(manifest.__manifestPath ||
                (sourceRoot ? sourceRoot + "/manifest.json" : ""))
            var failures = owner.runtimeFailuresFor(id)
            plugins.push({
                id: id,
                name: manifest.name,
                version: manifest.version,
                author: manifest.author || "",
                license: manifest.license || "",
                description: manifest.description || "",
                icon: owner.iconForManifest(manifest),
                kinds: manifest.kinds.slice(),
                kind: owner.primaryKind(id),
                entryPoints: owner.catalogEntryPoints(manifest),
                barWidget: owner.hasField(manifest, "barWidget") ? owner.cloneManifest(manifest.barWidget) : null,
                source: manifest.__isFirstParty === true ? "first-party" : "user",
                sourceRoot: sourceRoot,
                manifestPath: manifestPath,
                firstParty: manifest.__isFirstParty === true,
                clonedFrom: owner.cloneSourceIdForManifest(manifest),
                enabled: owner.isEnabled(id),
                active: projection.activeFor(manifest, id),
                loaded: false,
                visible: false,
                inBar: projection.inBar(id),
                canDisable: true,
                keepLoaded: manifest.keepLoaded === true,
                failures: failures,
                errorState: failures.length > 0 ? failures[failures.length - 1] : null
            })
        }
        var rejected = []
        for (var rejectedIndex = 0; rejectedIndex < owner.rejectedPlugins.length; rejectedIndex++)
            rejected.push(owner.cloneManifest(owner.rejectedPlugins[rejectedIndex]))
        return {
            plugins: plugins,
            rejected: rejected,
            scan: {
                state: owner.scanState,
                failureClass: owner.scanFailureClass,
                error: owner.lastError,
                rejectedCount: owner.rejectedCount
            }
        }
    }
}
