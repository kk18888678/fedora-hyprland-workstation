import QtQuick

// Clone state is kept outside ShellConfig so the shared state owner remains a
// small persistence boundary. The owner supplies only its canonical JSON,
// layout, and validation primitives; this object owns clone transitions.
QtObject {
    id: cloneState

    property var owner: null

    function normalizeCloneSourceRestores(value) {
        var result = []
        var seen = {}
        if (!Array.isArray(value) || !cloneState.owner) return result
        for (var i = 0; i < value.length; i++) {
            var record = value[i]
            if (!cloneState.owner.isPlainObject(record) || !cloneState.owner.isValidPluginId(record.cloneId) ||
                !cloneState.owner.isValidPluginId(record.sourceId) || seen[record.cloneId]) continue
            seen[record.cloneId] = true
            result.push({
                cloneId: record.cloneId,
                sourceId: record.sourceId,
                cloneIsBarOption: record.cloneIsBarOption === true,
                cloneIsBarWidget: record.cloneIsBarWidget === true,
                sourceBarPresent: record.sourceBarPresent === true,
                sourcePluginPresent: record.sourcePluginPresent === true,
                sourceWasDisabled: record.sourceWasDisabled === true,
                previousBarId: cloneState.owner.isValidPluginId(record.previousBarId) ? record.previousBarId : ""
            })
        }
        return result
    }

    function cloneSourceRestoreFor(config, cloneId) {
        var restores = cloneState.normalizeCloneSourceRestores(config && config.cloneSourceRestores)
        for (var i = 0; i < restores.length; i++)
            if (restores[i].cloneId === String(cloneId || "")) return restores[i]
        return null
    }

    function cloneSourceRestoreForSource(config, sourceId) {
        var requested = String(sourceId || "")
        var restores = cloneState.normalizeCloneSourceRestores(config && config.cloneSourceRestores)
        for (var i = 0; i < restores.length; i++) {
            var record = restores[i]
            if (record.sourceId !== requested) continue
            if (record.cloneIsBarOption && config.bar && config.bar.id === record.cloneId) return record
            var barLocation = cloneState.owner.findBarLocation(config, record.cloneId, "")
            if (barLocation.error || barLocation.found) return record
            if (cloneState.owner.findPluginEntryLocation(config, record.cloneId).found) return record
        }
        return null
    }

    function setCloneSourceRestore(config, record) {
        var restores = cloneState.normalizeCloneSourceRestores(config && config.cloneSourceRestores)
        var next = []
        for (var i = 0; i < restores.length; i++)
            if (!record || restores[i].cloneId !== record.cloneId) next.push(restores[i])
        if (record) next.push(cloneState.owner.cloneJson(record))
        if (next.length > 0) config.cloneSourceRestores = next
        else delete config.cloneSourceRestores
    }

    function removeCloneSourceRestore(config, cloneId) {
        var requested = String(cloneId || "")
        var restores = cloneState.normalizeCloneSourceRestores(config && config.cloneSourceRestores)
        var next = []
        for (var i = 0; i < restores.length; i++)
            if (restores[i].cloneId !== requested) next.push(restores[i])
        if (next.length > 0) config.cloneSourceRestores = next
        else delete config.cloneSourceRestores
    }

    function restoreCloneInConfig(config, cloneId, sourceId) {
        var requestedClone = String(cloneId || "")
        var requestedSource = String(sourceId || "")
        if (!cloneState.owner.isValidPluginId(requestedClone) || !cloneState.owner.isValidPluginId(requestedSource))
            return "Invalid clone restoration ids"
        var record = cloneState.cloneSourceRestoreFor(config, requestedClone)
        if (record && record.sourceId !== requestedSource) return "clone source does not match its restoration record"

        var cloneIsBarOption = record ? record.cloneIsBarOption === true : false
        if (cloneIsBarOption) {
            if (config.bar && config.bar.id === requestedClone)
                config.bar.id = record && cloneState.owner.isValidPluginId(record.previousBarId)
                    ? record.previousBarId : requestedSource
        } else {
            var barLocation = cloneState.owner.findBarLocation(config, requestedClone, "")
            if (barLocation.error) return barLocation.error
            if (barLocation.found) {
                var cloneEntry = config.bar.layout[barLocation.section][barLocation.index]
                if (record && record.sourceBarPresent) {
                    var restoredEntry = cloneState.owner.cloneJson(cloneEntry)
                    if (!cloneState.owner.isPlainObject(restoredEntry)) return "clone widget entry must be an object"
                    restoredEntry.id = requestedSource
                    config.bar.layout[barLocation.section][barLocation.index] = restoredEntry
                } else {
                    config.bar.layout[barLocation.section].splice(barLocation.index, 1)
                }
            }
        }

        var pluginLocation = cloneState.owner.findPluginEntryLocation(config, requestedClone)
        if (pluginLocation.error) return pluginLocation.error
        if (pluginLocation.found) config.plugins.splice(pluginLocation.index, 1)
        if (record && record.sourceWasDisabled !== true)
            config.disabledPlugins = cloneState.owner.removeDisabledId(config.disabledPlugins, requestedSource)
        cloneState.removeCloneSourceRestore(config, requestedClone)
        return ""
    }

    function enableClonePluginInConfig(config, id, sourceId, isBarWidget, hasNonWidgetKind,
                                        defaultSection, placement, putOnly, isBarOption) {
        var cloneId = String(id || "")
        var originId = String(sourceId || "")
        if (!cloneState.owner.isValidPluginId(originId) || originId === cloneId)
            return "Invalid clone source: " + originId

        var previousClone = cloneState.cloneSourceRestoreForSource(config, originId)
        if (previousClone && previousClone.cloneId !== cloneId) {
            var restorePreviousError = cloneState.restoreCloneInConfig(config, previousClone.cloneId, originId)
            if (restorePreviousError) return restorePreviousError
        }

        var record = cloneState.cloneSourceRestoreFor(config, cloneId)
        if (record && record.sourceId !== originId)
            return "clone source does not match its restoration record"
        var sourceLocation = {found: false}
        if (!record && isBarWidget) {
            sourceLocation = cloneState.owner.findBarLocation(config, originId, "")
            if (sourceLocation.error) return sourceLocation.error
        }
        if (!record) {
            record = {
                cloneId: cloneId,
                sourceId: originId,
                cloneIsBarOption: isBarOption === true,
                cloneIsBarWidget: isBarWidget === true,
                sourceBarPresent: sourceLocation.found === true,
                sourcePluginPresent: cloneState.owner.containsPluginEntry(config.plugins, originId),
                sourceWasDisabled: cloneState.owner.contains(config.disabledPlugins, originId),
                previousBarId: config.bar && cloneState.owner.isValidPluginId(config.bar.id) ? config.bar.id : ""
            }
        }

        config.disabledPlugins = cloneState.owner.removeDisabledId(config.disabledPlugins, cloneId)
        if (isBarOption) {
            if (Object.keys(placement || ({})).length > 0) return "bar options do not accept widget placement"
            config.bar.id = cloneId
            cloneState.setCloneSourceRestore(config, record)
            if (hasNonWidgetKind && !record.sourceWasDisabled) {
                config.disabledPlugins = cloneState.owner.uniqueIds(config.disabledPlugins)
                if (!cloneState.owner.contains(config.disabledPlugins, originId)) config.disabledPlugins.push(originId)
            }
            return ""
        }

        var cloneLocation = isBarWidget ? cloneState.owner.findBarLocation(config, cloneId, "") : {found: false}
        if (cloneLocation.error) return cloneLocation.error
        if (isBarWidget && !cloneLocation.found) {
            if (sourceLocation.found) {
                var sourceEntry = cloneState.owner.cloneJson(config.bar.layout[sourceLocation.section][sourceLocation.index])
                if (!cloneState.owner.isPlainObject(sourceEntry)) return "source widget entry must be an object"
                sourceEntry.id = cloneId
                config.bar.layout[sourceLocation.section][sourceLocation.index] = sourceEntry
            } else {
                var target = cloneState.owner.barTarget(config, placement || ({}),
                    cloneState.owner.isBarSection(defaultSection) ? defaultSection : "center")
                if (target.error && putOnly && target.error.indexOf("could not find target widget ") === 0) {
                    var fallbackPlacement = cloneState.owner.cloneJson(placement) || ({})
                    delete fallbackPlacement.before
                    delete fallbackPlacement.after
                    target = cloneState.owner.barTarget(config, fallbackPlacement,
                        cloneState.owner.isBarSection(defaultSection) ? defaultSection : "center")
                }
                if (target.error) return target.error
                config.bar.layout[target.section].splice(target.index, 0, {id: cloneId})
            }
        } else if (isBarWidget && !putOnly && Object.keys(placement || ({})).length > 0) {
            var moveError = cloneState.owner.moveBarEntry(config, cloneId, placement)
            if (moveError) return moveError
        }

        if (hasNonWidgetKind && !cloneState.owner.containsPluginEntry(config.plugins, cloneId))
            config.plugins.push({id: cloneId})
        if (hasNonWidgetKind && !record.sourceWasDisabled) {
            config.disabledPlugins = cloneState.owner.uniqueIds(config.disabledPlugins)
            if (!cloneState.owner.contains(config.disabledPlugins, originId)) config.disabledPlugins.push(originId)
        }
        cloneState.setCloneSourceRestore(config, record)
        return ""
    }

    function setPluginEnabled(id, firstParty, enabled, isBarWidget, cloneSourceId) {
        if (!cloneState.owner.isValidPluginId(id)) {
            cloneState.owner.lastError = "Invalid plugin id."
            return false
        }
        var originId = String(cloneSourceId || "")
        if (originId !== "" && (firstParty === true || !cloneState.owner.isValidPluginId(originId) ||
            originId === String(id))) {
            cloneState.owner.lastError = "Invalid clone source."
            return false
        }

        var next = cloneState.owner.prepareMutationConfig()
        if (enabled && firstParty === true) {
            var activeClone = cloneState.cloneSourceRestoreForSource(next, id)
            if (activeClone) {
                var restoreError = cloneState.restoreCloneInConfig(next, activeClone.cloneId, id)
                if (restoreError) {
                    cloneState.owner.lastError = restoreError
                    return false
                }
            }
        }
        if (!enabled && originId !== "") {
            var cloneRestoreError = cloneState.restoreCloneInConfig(next, id, originId)
            if (cloneRestoreError) {
                cloneState.owner.lastError = cloneRestoreError
                return false
            }
            return cloneState.owner.persistConfig(next)
        }

        var list = firstParty ? next.disabledPlugins : next.plugins
        var index = firstParty ? list.indexOf(id) : cloneState.owner.findPluginEntryIndex(list, id)
        if (enabled) {
            next.disabledPlugins = cloneState.owner.removeDisabledId(next.disabledPlugins, id)
            if (!firstParty && index === -1) list.push({id: id})
        } else if (firstParty) {
            if (index === -1) list.push(id)
        } else {
            if (index !== -1) list.splice(index, 1)
            if (isBarWidget === true && !cloneState.owner.contains(next.disabledPlugins, id))
                next.disabledPlugins.push(id)
        }
        next.disabledPlugins.sort()
        return cloneState.owner.persistConfig(next)
    }
}
