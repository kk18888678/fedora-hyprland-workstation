// Pure notification policy and serialization helpers. QML owns live
// Notification objects; this module only produces bounded plain data so C++
// QObject lifetimes never leak into ListModel roles or persisted state.

var MAX_APP_LENGTH = 128
var MAX_TEXT_LENGTH = 4096
var MAX_IMAGE_LENGTH = 2048
var MAX_ACTIONS = 8
var MAX_HISTORY = 100

function boundedText(value, limit) {
    var text = String(value === undefined || value === null ? "" : value)
    var max = Number(limit)
    if (!isFinite(max) || max < 1) max = MAX_TEXT_LENGTH
    if (text.length <= max) return text
    return text.slice(0, Math.max(1, max - 1)) + "…"
}

function finiteNumber(value, fallback) {
    var number = Number(value)
    return isFinite(number) ? number : fallback
}

function urgencyValue(value) {
    var urgency = Math.round(finiteNumber(value, 1))
    return Math.max(0, Math.min(2, urgency))
}

function stringHint(hints, name) {
    try {
        if (hints && hints[name] !== undefined && hints[name] !== null) return String(hints[name])
    } catch (error) {
        // Malformed optional hints are ignored by design.
    }
    return ""
}

function shouldBypassDnd(notification, criticalUrgency) {
    var appName = String((notification && notification.appName) || "")
    if (appName === "aurelia-action" || appName === "omarchy-action") return true
    return appName === "notify-send" && notification && notification.urgency === criticalUrgency
}

function isEphemeralApp(appName) {
    var name = String(appName || "")
    return name === "notify-send" || name === "aurelia-action" || name === "omarchy-action"
}

function actionsOf(notification) {
    var result = []
    var source = []
    try { source = notification && notification.actions ? notification.actions : [] } catch (error) { source = [] }
    if (!source || typeof source.length !== "number") return result

    for (var i = 0; i < source.length && result.length < MAX_ACTIONS; i++) {
        var action = source[i]
        if (!action) continue
        var identifier = boundedText(action.identifier, 256)
        var text = boundedText(action.text, 256)
        if (identifier === "" || text === "") continue
        result.push({ identifier: identifier, text: text })
    }
    return result
}

function snapshotOf(notification, timestamp) {
    var n = notification || {}
    var id = finiteNumber(n.id, 0)
    var expireTimeout = finiteNumber(n.expireTimeout, 0)
    if (expireTimeout < 0) expireTimeout = 0
    return {
        id: id,
        originalId: id,
        app: boundedText(n.appName, MAX_APP_LENGTH),
        appIcon: boundedText(n.appIcon, MAX_IMAGE_LENGTH),
        summary: boundedText(n.summary, MAX_TEXT_LENGTH),
        body: boundedText(n.body, MAX_TEXT_LENGTH),
        image: boundedText(n.image, MAX_IMAGE_LENGTH),
        actions: actionsOf(n),
        urgency: urgencyValue(n.urgency),
        expireTimeout: expireTimeout,
        timestamp: finiteNumber(timestamp, Date.now())
    }
}

function normalizeHistoryEntry(value) {
    var entry = value && typeof value === "object" && !Array.isArray(value) ? value : {}
    var id = finiteNumber(entry.id, 0)
    var originalId = finiteNumber(entry.originalId, id)
    var timestamp = finiteNumber(entry.timestamp, 0)
    return {
        id: id,
        originalId: originalId,
        app: boundedText(entry.app, MAX_APP_LENGTH),
        appIcon: boundedText(entry.appIcon, MAX_IMAGE_LENGTH),
        summary: boundedText(entry.summary, MAX_TEXT_LENGTH),
        body: boundedText(entry.body, MAX_TEXT_LENGTH),
        image: boundedText(entry.image, MAX_IMAGE_LENGTH),
        actions: [],
        urgency: urgencyValue(entry.urgency),
        expireTimeout: 0,
        timestamp: timestamp
    }
}

function historyEntry(value) {
    return normalizeHistoryEntry(value)
}

function parseSettings(raw) {
    var text = String(raw || "").trim()
    if (text === "") return { ok: true, dnd: null }
    try {
        var parsed = JSON.parse(text)
        return {
            ok: true,
            dnd: parsed && typeof parsed.dnd === "boolean" ? parsed.dnd : null
        }
    } catch (error) {
        return { ok: false, dnd: null }
    }
}

function parseHistory(raw, limit) {
    var text = String(raw || "").trim()
    if (text === "") return []

    var parsed
    try { parsed = JSON.parse(text) } catch (error) { return [] }
    var source = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.notifications) ? parsed.notifications : [])
    var rows = []
    for (var i = 0; i < source.length && rows.length < MAX_HISTORY; i++) {
        var row = normalizeHistoryEntry(source[i])
        if (row.timestamp > 0 || row.summary !== "" || row.body !== "") rows.push(row)
    }
    rows.sort(function(left, right) { return right.timestamp - left.timestamp })
    var max = Math.max(0, Math.min(MAX_HISTORY, Math.floor(finiteNumber(limit, 50))))
    return rows.slice(0, max)
}

function durationFor(urgency, expireTimeout) {
    var timeout = finiteNumber(expireTimeout, 0)
    if (timeout < 0) timeout = 0
    if (urgency === 2) return 0
    var minimum = urgency === 0 ? 5000 : 8000
    if (timeout <= 0) return minimum
    return Math.min(30000, Math.max(minimum, Math.round(timeout)))
}

function screenshotSnapshot(path, timestamp) {
    var source = String(path === undefined || path === null ? "" : path)
    if (source.length === 0 || source.length > MAX_IMAGE_LENGTH || source.charAt(0) !== "/" || source.indexOf("\u0000") !== -1) return null
    var stamp = Math.max(0, Math.round(finiteNumber(timestamp, Date.now())))
    var notificationId = -Math.max(1, stamp)
    return {
        id: notificationId,
        originalId: notificationId,
        app: "aurelia-action",
        appIcon: "camera-photo",
        summary: "Screenshot saved",
        body: "The capture is available in Pictures and on the clipboard.",
        image: "file://" + source,
        actions: [],
        urgency: 0,
        expireTimeout: 5000,
        timestamp: stamp
    }
}

if (typeof module !== "undefined") {
    module.exports = {
        boundedText: boundedText,
        shouldBypassDnd: shouldBypassDnd,
        isEphemeralApp: isEphemeralApp,
        snapshotOf: snapshotOf,
        historyEntry: historyEntry,
        parseSettings: parseSettings,
        parseHistory: parseHistory,
        durationFor: durationFor,
        screenshotSnapshot: screenshotSnapshot
    }
}
