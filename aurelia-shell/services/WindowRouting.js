// Pure identity and matching helpers for application/tray toplevel routing.
// Activation and retry timing stay in WindowActivation.qml so this module is
// safe to exercise without a live Wayland session.

var MAX_APP_LENGTH = 128
var MAX_IMAGE_LENGTH = 2048

function objectProperty(object, name) {
    try {
        return object && object[name] !== undefined && object[name] !== null ? object[name] : null
    } catch (error) {
        if (typeof console !== "undefined" && console.warn)
            console.warn("[WINDOWS] property_read_failed name=" + String(name || ""))
        return null
    }
}

function normalizedIdentity(value) {
    return String(value === undefined || value === null ? "" : value)
        .toLowerCase()
        .replace(/[^a-z0-9]/g, "")
}

function boundedText(value, limit) {
    var text = String(value === undefined || value === null ? "" : value)
    var max = Number(limit)
    if (!isFinite(max) || max < 1) max = MAX_APP_LENGTH
    return text.length <= max ? text : text.slice(0, Math.max(1, max - 1)) + "…"
}

function pushIdentity(values, value, priority) {
    var normalized = normalizedIdentity(value)
    if (normalized.length < 3) return
    for (var i = 0; i < values.length; i++) {
        if (values[i].value === normalized) {
            if (priority > values[i].priority) values[i].priority = priority
            return
        }
    }
    values.push({value: normalized, priority: priority})
}

function workspaceRouteData(source, fallback) {
    var primary = source || {}
    var backup = fallback || {}
    var route = []

    var desktopEntry = boundedText(
        objectProperty(primary, "desktopEntry") || objectProperty(primary, "id") ||
        objectProperty(backup, "desktopEntry") || objectProperty(backup, "id"),
        MAX_APP_LENGTH)
    var appName = boundedText(
        objectProperty(primary, "appName") || objectProperty(primary, "app") ||
        objectProperty(primary, "title") || objectProperty(primary, "tooltipTitle") ||
        objectProperty(backup, "appName") || objectProperty(backup, "app") ||
        objectProperty(backup, "title") || objectProperty(backup, "tooltipTitle"),
        MAX_APP_LENGTH)
    var appIcon = boundedText(
        objectProperty(primary, "appIcon") || objectProperty(primary, "icon") ||
        objectProperty(backup, "appIcon") || objectProperty(backup, "icon"),
        MAX_IMAGE_LENGTH)

    pushIdentity(route, desktopEntry, 3)
    pushIdentity(route, appName, 2)
    if (appIcon !== "" && appIcon !== "application-x-executable" && appIcon !== "applications-system")
        pushIdentity(route, appIcon, 1)

    return {
        desktopEntry: desktopEntry,
        appName: appName,
        appIcon: appIcon,
        identities: route,
        enabled: route.length > 0
    }
}

function workspaceRouteDataForTrayItem(item) {
    var route = workspaceRouteData({
        desktopEntry: objectProperty(item, "id"),
        appName: objectProperty(item, "title"),
        appIcon: objectProperty(item, "icon")
    }, {})
    pushIdentity(route.identities, objectProperty(item, "tooltipTitle"), 2)
    pushIdentity(route.identities, objectProperty(item, "tooltipDescription"), 1)
    route.enabled = route.identities.length > 0
    return route
}

function workspaceRouteDataForTrayIdentity(identity) {
    var parts = String(identity === undefined || identity === null ? "" : identity).split("|")
    var route = workspaceRouteData({
        id: parts[0] || "",
        title: parts[1] || "",
        tooltipTitle: "",
        tooltipDescription: ""
    }, {})
    pushIdentity(route.identities, parts[2] || "", 2)
    pushIdentity(route.identities, parts[3] || "", 1)
    route.enabled = route.identities.length > 0
    return route
}

function workspaceRouteInfo(toplevel) {
    var wayland = objectProperty(toplevel, "wayland")
    var handle = objectProperty(toplevel, "handle")
    var ipc = objectProperty(toplevel, "lastIpcObject") || {}
    var appId = String(objectProperty(wayland, "appId") ||
        objectProperty(handle, "appId") || objectProperty(toplevel, "appId") || "")
    var title = String(objectProperty(toplevel, "title") || objectProperty(wayland, "title") || "")
    return {
        appId: appId,
        desktopEntry: String(objectProperty(ipc, "desktopEntry") ||
            objectProperty(toplevel, "desktopEntry") || ""),
        className: String(objectProperty(ipc, "class") || objectProperty(ipc, "className") ||
            objectProperty(toplevel, "class") || objectProperty(toplevel, "className") || ""),
        initialClass: String(objectProperty(ipc, "initialClass") ||
            objectProperty(toplevel, "initialClass") || ""),
        title: title || String(objectProperty(ipc, "title") || ""),
        initialTitle: String(objectProperty(ipc, "initialTitle") ||
            objectProperty(toplevel, "initialTitle") || ""),
        activated: objectProperty(toplevel, "activated") === true ||
            objectProperty(handle, "activated") === true
    }
}

function workspaceIdForToplevel(toplevel) {
    var workspace = objectProperty(toplevel, "workspace")
    var id = Number(objectProperty(workspace, "id"))
    return isFinite(id) && Math.floor(id) === id && id !== 0 ? id : 0
}

// Derive the currently-focused toplevel from the compositor's toplevel model.
// Quickshell 0.3.1 only assigns Hyprland.activeToplevel inside its
// activewindowv2 event handler: refreshToplevels() parses j/clients but never
// assigns the active toplevel, Hyprland does not replay the focused window to
// a newly connected client, and creating a bar layer surface emits no such
// event. A shell started or reloaded while a window is already focused
// therefore has Hyprland.activeToplevel === null until some later focus or
// title change. Hyprland marks the focused window as the entry whose
// lastIpcObject.focusHistoryID is numerically 0, so this helper recovers it
// from the model itself. It fails closed (returns null) whenever the marker
// is absent, malformed, or ambiguous, so a wrong window is never chosen and
// the widget stays hidden instead of showing the wrong application.
//
// Multi-monitor limitation: this helper only had a single-monitor runtime to
// exercise against. It therefore makes no assumption about per-monitor focus
// and fails closed if more than one entry ever reports focusHistoryID 0. A
// future multi-monitor investigation must confirm Hyprland's focus-history
// semantics before relaxing that guard.
function focusedToplevel(values) {
    if (!values) return null
    var count = Number(objectProperty(values, "length"))
    if (!isFinite(count) || count < 0 || Math.floor(count) !== count) return null
    var found = null
    for (var i = 0; i < count; i++) {
        var candidate = values[i]
        if (!candidate) continue
        var ipc = objectProperty(candidate, "lastIpcObject")
        if (!ipc) continue
        var marker = objectProperty(ipc, "focusHistoryID")
        if (marker === null) continue
        var focusId = Number(marker)
        if (!isFinite(focusId) || Math.floor(focusId) !== focusId) continue
        if (focusId !== 0) continue
        // A second entry claiming focus is ambiguous; return null rather than
        // guess which window the user is interacting with.
        if (found !== null) return null
        found = candidate
    }
    return found
}

function workspaceRouteScore(route, windowInfo) {
    var requested = route && Array.isArray(route.identities) ? route.identities : []
    var routeSource = route || {}
    var candidate = windowInfo || {}
    var candidates = []
    pushIdentity(candidates, candidate.desktopEntry, 3)
    pushIdentity(candidates, candidate.appId, 3)
    pushIdentity(candidates, candidate.className, 3)
    pushIdentity(candidates, candidate.initialClass, 3)
    pushIdentity(candidates, candidate.title, 1)
    pushIdentity(candidates, candidate.initialTitle, 1)

    var best = 0
    for (var i = 0; i < requested.length; i++) {
        for (var j = 0; j < candidates.length; j++) {
            var left = requested[i].value
            var right = candidates[j].value
            if (left === right) {
                best = Math.max(best, 100 + requested[i].priority * 10 + candidates[j].priority)
                continue
            }
            if (left.length >= 5 && right.length >= 5 &&
                (left.indexOf(right) !== -1 || right.indexOf(left) !== -1)) {
                best = Math.max(best, 40 + requested[i].priority * 10 + candidates[j].priority)
            }
        }
    }

    // Prefer a title that identifies the sender itself over a browser window
    // that happens to reuse the same application id.
    var senderNames = [normalizedIdentity(routeSource.appName), normalizedIdentity(routeSource.desktopEntry)]
    var candidateTitles = [normalizedIdentity(candidate.title), normalizedIdentity(candidate.initialTitle)]
    var exactSenderTitle = false
    var containsSenderTitle = false
    for (var senderIndex = 0; senderIndex < senderNames.length; senderIndex++) {
        if (senderNames[senderIndex].length < 3) continue
        for (var titleIndex = 0; titleIndex < candidateTitles.length; titleIndex++) {
            if (candidateTitles[titleIndex] === senderNames[senderIndex]) exactSenderTitle = true
            else if (candidateTitles[titleIndex].indexOf(senderNames[senderIndex]) !== -1)
                containsSenderTitle = true
        }
    }
    if (best > 0) {
        if (exactSenderTitle) best += 70
        else if (containsSenderTitle) best += 35
    }
    if (best > 0 && candidate.activated === true) best += 25
    return best
}

function matchingWorkspaceToplevel(route, values) {
    if (!route || !route.enabled || !values) return null
    var count = Number(objectProperty(values, "length"))
    if (!isFinite(count) || count < 0 || Math.floor(count) !== count) return null
    var best = null
    for (var i = 0; i < count; i++) {
        var candidate = values[i]
        var workspace = objectProperty(candidate, "workspace")
        var workspaceId = workspaceIdForToplevel(candidate)
        if (!candidate || workspaceId === 0) continue
        var info = workspaceRouteInfo(candidate)
        var candidateScore = workspaceRouteScore(route, info)
        if (candidateScore <= 0) continue
        if (!best || candidateScore > best.score ||
            (candidateScore === best.score && info.activated && !best.info.activated)) {
            best = {
                toplevel: candidate,
                workspace: workspace,
                workspaceId: workspaceId,
                info: info,
                score: candidateScore
            }
        }
    }
    return best
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        objectProperty: objectProperty,
        normalizedIdentity: normalizedIdentity,
        workspaceRouteData: workspaceRouteData,
        workspaceRouteDataForTrayItem: workspaceRouteDataForTrayItem,
        workspaceRouteDataForTrayIdentity: workspaceRouteDataForTrayIdentity,
        workspaceRouteInfo: workspaceRouteInfo,
        workspaceIdForToplevel: workspaceIdForToplevel,
        focusedToplevel: focusedToplevel,
        workspaceRouteScore: workspaceRouteScore,
        matchingWorkspaceToplevel: matchingWorkspaceToplevel
    }
}
