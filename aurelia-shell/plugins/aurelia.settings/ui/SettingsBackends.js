// SettingsBackends.js — pure merge/routing helpers for the Settings hub.
//
// The hub talks to two bounded backends: the Hyprland settings backend and
// the system settings backend (power/audio/network/time). This module owns the
// one piece of logic that decides how their schemas/status are combined and
// which backend a given option id is routed to, so that decision is testable
// without instantiating the window.
.pragma library

function mergeSchemas(hypr, system) {
    return (hypr || []).concat(system || [])
}

function schemaMap(schemas) {
    var map = {}
    var list = schemas || []
    for (var i = 0; i < list.length; i++) map[list[i].id] = list[i]
    return map
}

function mergeStatusMaps(hypr, system) {
    var merged = {}
    var key
    var a = hypr || {}
    var b = system || {}
    for (key in a) merged[key] = a[key]
    for (key in b) merged[key] = b[key]
    return merged
}

// System options are namespaced with the "system." prefix; everything else is
// owned by the Hyprland backend.
function isSystemOption(optionId) {
    return String(optionId || "").indexOf("system.") === 0
}

function backendFor(optionId, hyprBin, systemBin) {
    return isSystemOption(optionId) ? systemBin : hyprBin
}
