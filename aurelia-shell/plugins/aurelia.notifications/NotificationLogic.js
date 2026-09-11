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

function isChromiumDerived(app, appIcon) {
    var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
    return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0 ||
        source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0 ||
        source.indexOf("opera") >= 0
}

function isImageTag(tag) {
    var name = /^<[^A-Za-z0-9]*([A-Za-z0-9]+)/.exec(tag)
    return !!name && name[1].toLowerCase() === "img"
}

function stripImageTags(text) {
    var out = ""
    var i = 0
    while (i < text.length) {
        var open = text.indexOf("<", i)
        if (open === -1) {
            out += text.slice(i)
            break
        }
        out += text.slice(i, open)
        var close = text.indexOf(">", open)
        var tag = close === -1 ? text.slice(open) : text.slice(open, close + 1)
        if (!isImageTag(tag)) out += tag
        i = close === -1 ? text.length : close + 1
    }
    return out
}

function sanitizeBody(body, app, appIcon) {
    var text = stripImageTags(String(body || ""))
    if (!isChromiumDerived(app, appIcon)) return text
    return text
        .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
        .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
}

function styledBody(body, app, appIcon) {
    return stripImageTags(sanitizeBody(body, app, appIcon).replace(/\r\n|\r|\n/g, "<br/>"))
}

function summaryStartsWithGlyph(summary) {
    var text = String(summary || "").replace(/^\s+/, "")
    if (text === "") return false
    var offset = 1
    var first = text.charCodeAt(0)
    if (first >= 0xd800 && first <= 0xdbff && text.length > 1) offset = 2
    var spaces = 0
    while (offset < text.length && text.charAt(offset) === " ") {
        spaces++
        offset++
    }
    return spaces >= 2
}

function normalizedIdentity(value) {
    return String(value === undefined || value === null ? "" : value)
        .toLowerCase()
        .replace(/[^a-z0-9]/g, "")
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
    values.push({ value: normalized, priority: priority })
}

function workspaceRouteData(notification, fallback) {
    var source = notification || {}
    var backup = fallback || {}
    var route = []

    var desktopEntry = boundedText(source.desktopEntry || backup.desktopEntry, MAX_APP_LENGTH)
    var appName = boundedText(source.appName || backup.appName || backup.app, MAX_APP_LENGTH)
    var appIcon = boundedText(source.appIcon || backup.appIcon, MAX_IMAGE_LENGTH)

    // Desktop entry IDs are the most stable identity. App names and icons are
    // fallbacks for senders that omit the desktop-entry notification hint.
    pushIdentity(route, desktopEntry, 3)
    pushIdentity(route, appName, 2)
    if (appIcon !== "" && appIcon !== "application-x-executable" && appIcon !== "applications-system") {
        pushIdentity(route, appIcon, 1)
    }

    return {
        desktopEntry: desktopEntry,
        appName: appName,
        appIcon: appIcon,
        identities: route,
        enabled: route.length > 0
    }
}

function workspaceRouteScore(route, windowInfo) {
    var requested = route && Array.isArray(route.identities) ? route.identities : []
    var candidate = windowInfo || {}
    var candidates = []
    pushIdentity(candidates, candidate.desktopEntry, 3)
    pushIdentity(candidates, candidate.appId, 3)
    pushIdentity(candidates, candidate.className, 3)
    pushIdentity(candidates, candidate.initialClass, 3)
    pushIdentity(candidates, candidate.title, 1)
    pushIdentity(candidates, candidate.initialTitle, 1)

    var score = 0
    for (var i = 0; i < requested.length; i++) {
        for (var j = 0; j < candidates.length; j++) {
            var left = requested[i].value
            var right = candidates[j].value
            if (left === right) {
                score = Math.max(score, 100 + requested[i].priority * 10 + candidates[j].priority)
                continue
            }

            // Permit harmless naming variants such as OpenAI ChatGPT ->
            // chatgpt, but do not let short generic names route unrelated
            // windows (for example "chat" -> "chatgpt").
            if (left.length >= 5 && right.length >= 5 && (left.indexOf(right) !== -1 || right.indexOf(left) !== -1)) {
                score = Math.max(score, 40 + requested[i].priority * 10 + candidates[j].priority)
            }
        }
    }

    if (score > 0 && candidate.activated === true) score += 25
    return score
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

function glyphFromHints(hints) {
    return stringHint(hints, "aurelia-glyph") || stringHint(hints, "omarchy-glyph")
}

function execArgvFromHints(hints) {
    return stringHint(hints, "aurelia-exec-argv") || stringHint(hints, "omarchy-exec-argv")
}

function transientFromNotification(notification) {
    if (!notification) return false
    if (notification.transient === true) return true
    try {
        return !!(notification.hints && notification.hints.transient === true)
    } catch (error) {
        return false
    }
}

function parseExecArgv(value) {
    var text = String(value || "")
    if (text === "") return null
    var parsed
    try { parsed = JSON.parse(text) } catch (error) { return null }
    if (!Array.isArray(parsed) || parsed.length === 0) return null
    for (var i = 0; i < parsed.length; i++) {
        if (typeof parsed[i] !== "string") return null
    }
    if (parsed[0] === "" || parsed[0].charAt(0) === "-") return null
    return parsed
}

function shouldRenderCompactGlyph(glyph, iconSource, singleLineToast) {
    return String(glyph || "").length > 0 && String(iconSource || "").length === 0 && !!singleLineToast
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
        if (identifier === "default") continue
        if (identifier === "" || text === "") {
            continue
        }
        result.push({ identifier: identifier, text: text })
    }
    return result
}

function defaultActionText(notification) {
    var source = []
    try { source = notification && notification.actions ? notification.actions : [] } catch (error) { source = [] }
    if (!source || typeof source.length !== "number") return ""

    for (var i = 0; i < source.length; i++) {
        var action = source[i]
        if (!action || boundedText(action.identifier, 256) !== "default") continue
        var text = boundedText(action.text, 256)
        return text === "" ? "Open" : text
    }
    return ""
}

function snapshotOf(notification, timestamp) {
    var n = notification || {}
    var id = finiteNumber(n.id, 0)
    var expireTimeout = finiteNumber(n.expireTimeout, 0)
    if (expireTimeout < 0) expireTimeout = 0
    var urgency = urgencyValue(n.urgency)
    var stamp = finiteNumber(timestamp, Date.now())
    var app = boundedText(n.appName, MAX_APP_LENGTH)
    var appIcon = boundedText(n.appIcon, MAX_IMAGE_LENGTH)
    var desktopEntry = boundedText(n.desktopEntry, MAX_APP_LENGTH)
    var duration = durationFor(urgency, expireTimeout, app, desktopEntry, appIcon)
    var transient = transientFromNotification(n)
    return {
        id: id,
        originalId: id,
        app: app,
        appIcon: appIcon,
        desktopEntry: desktopEntry,
        summary: boundedText(n.summary, MAX_TEXT_LENGTH),
        body: boundedText(n.body, MAX_TEXT_LENGTH),
        image: boundedText(n.image, MAX_IMAGE_LENGTH),
        glyph: boundedText(glyphFromHints(n.hints), 256),
        execArgv: boundedText(execArgvFromHints(n.hints), MAX_TEXT_LENGTH),
        actions: actionsOf(n),
        defaultActionText: defaultActionText(n),
        urgency: urgency,
        expireTimeout: expireTimeout,
        timestamp: stamp,
        deadline: duration > 0 ? stamp + duration : 0,
        transient: transient
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
        desktopEntry: boundedText(entry.desktopEntry, MAX_APP_LENGTH),
        summary: boundedText(entry.summary, MAX_TEXT_LENGTH),
        body: boundedText(entry.body, MAX_TEXT_LENGTH),
        image: boundedText(entry.image, MAX_IMAGE_LENGTH),
        glyph: boundedText(entry.glyph, 256),
        execArgv: boundedText(entry.execArgv, MAX_TEXT_LENGTH),
        actions: actionsOf(entry),
        defaultActionText: boundedText(entry.defaultActionText, 256),
        urgency: urgencyValue(entry.urgency),
        expireTimeout: 0,
        timestamp: timestamp,
        transient: entry.transient === true
    }
}

function historyEntry(value) {
    return normalizeHistoryEntry(value)
}

function historyKey(value) {
    var entry = value || {}
    return String(entry.timestamp || 0) + "|" + String(entry.originalId || entry.id || 0)
}

function isRenderableHistoryEntry(value) {
    var entry = value || {}
    return String(entry.app || "") !== "" ||
        String(entry.summary || "") !== "" ||
        String(entry.body || "") !== "" ||
        String(entry.image || "") !== ""
}

function hasPopupIdentity(value) {
    return imageStem(value) !== ""
}

function parseSettings(raw) {
    var text = String(raw || "").trim()
    if (text === "") return { ok: true, dnd: null, legacy: false }
    try {
        var parsed = JSON.parse(text)
        return {
            ok: true,
            dnd: parsed && typeof parsed.dnd === "boolean" ? parsed.dnd : null,
            legacy: !!(parsed && (parsed.pending || parsed.past || parsed.entries))
        }
    } catch (error) {
        return { ok: false, dnd: null, legacy: false }
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
        if (isRenderableHistoryEntry(row)) rows.push(row)
    }
    rows.sort(function(left, right) { return right.timestamp - left.timestamp })
    var max = Math.max(0, Math.min(MAX_HISTORY, Math.floor(finiteNumber(limit, 50))))
    return rows.slice(0, max)
}

function isInboxPersistent(app, desktopEntry, appIcon) {
    // ChatGPT completion notices are actionable work results. Keep them in
    // Active until the user explicitly opens or dismisses them; ordinary apps
    // retain the Omarchy-compatible urgency/expiry policy below.
    return normalizedIdentity(app) === "chatgpt" ||
        normalizedIdentity(desktopEntry) === "chatgpt" ||
        normalizedIdentity(appIcon) === "chatgpt"
}

function durationFor(urgency, expireTimeout, app, desktopEntry, appIcon) {
    if (isInboxPersistent(app, desktopEntry, appIcon)) return 0
    var timeout = finiteNumber(expireTimeout, 0)
    if (timeout < 0) timeout = 0
    if (urgency === 2) return 0
    var minimum = urgency === 0 ? 5000 : 8000
    if (timeout <= 0) return minimum
    return Math.min(30000, Math.max(minimum, Math.round(timeout)))
}

function hasBusName(output, expectedName) {
    var name = String(expectedName || "")
    if (name === "") return false
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var firstColumn = lines[i].trim().split(/\s+/)[0]
        if (firstColumn === name) return true
    }
    return false
}

function busOwnerPid(output) {
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var match = /^\s*PID\s*=\s*([0-9]+)\s*$/.exec(lines[i])
        if (!match) continue
        var pid = Number(match[1])
        if (isFinite(pid) && pid > 0 && Math.floor(pid) === pid) return pid
    }
    return 0
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
        desktopEntry: "",
        summary: "Screenshot saved",
        body: "The capture is available in Pictures and on the clipboard.",
        image: "file://" + source,
        glyph: "",
        execArgv: "",
        actions: [],
        defaultActionText: "",
        urgency: 0,
        expireTimeout: 5000,
        timestamp: stamp,
        deadline: stamp + 5000,
        transient: true
    }
}

function popupEntry(value, normalUrgency) {
    var entry = normalizeHistoryEntry(value)
    var expireTimeout = finiteNumber((value || {}).expireTimeout, 0)
    entry.expireTimeout = expireTimeout < 0 ? 0 : expireTimeout
    var deadline = finiteNumber((value || {}).deadline, 0)
    if (deadline > 0) entry.deadline = deadline
    if (normalUrgency !== undefined && (value || {}).urgency === undefined) entry.urgency = urgencyValue(normalUrgency)
    return entry
}

function imageStem(entry) {
    var value = entry || {}
    var timestamp = finiteNumber(value.timestamp, 0)
    var originalId = finiteNumber(value.originalId, finiteNumber(value.id, 0))
    if (timestamp <= 0 || !isFinite(originalId)) return ""
    return String(timestamp) + "-" + String(originalId)
}

function popupFileName(entry) {
    var stem = imageStem(entry)
    return stem === "" ? "" : stem + ".json"
}

function localImageFile(value) {
    var source = String(value || "")
    if (source.indexOf("file://") === 0) {
        source = source.slice(7)
        try { source = decodeURIComponent(source) } catch (error) { return "" }
    }
    return source.charAt(0) === "/" ? source : ""
}

function persistablePopup(entry, imagesDir) {
    var source = entry || {}
    var output = {}
    for (var key in source) output[key] = source[key]
    var copies = []
    var roles = ["appIcon", "image"]
    for (var i = 0; i < roles.length; i++) {
        var role = roles[i]
        var value = String(output[role] || "")
        if (value === "") continue
        var localPath = localImageFile(value)
        if (localPath !== "") {
            var copyPath = String(imagesDir || "") + imageStem(source) + "-" + role
            if (localPath !== copyPath) copies.push({ from: localPath, to: copyPath })
            output[role] = "file://" + copyPath
        } else if (value.indexOf("image://") === 0) {
            output[role] = ""
        }
    }
    return { entry: output, copies: copies }
}

function serializePopup(entry, normalUrgency) {
    return JSON.stringify(popupEntry(entry, normalUrgency))
}

function parsePopupFiles(raw, normalUrgency) {
    var entries = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line === "") continue
        try {
            var value = JSON.parse(line)
            if (value && typeof value === "object") entries.push(popupEntry(value, normalUrgency))
        } catch (error) {}
    }
    entries.sort(function(left, right) { return Number(right.timestamp || 0) - Number(left.timestamp || 0) })
    return entries
}

function popupExpired(entry, duration, now) {
    var deadline = finiteNumber((entry || {}).deadline, 0)
    if (deadline > 0) return Number(now) >= deadline
    var lifetime = finiteNumber(duration, 0)
    return lifetime > 0 && Number(now) - finiteNumber((entry || {}).timestamp, 0) >= lifetime
}

function popupPlacement(barPosition, barClearance, gapsOut) {
    var position = String(barPosition || "top")
    var clearance = finiteNumber(barClearance, 0)
    var gap = finiteNumber(gapsOut, 0)
    return {
        anchors: { top: true, bottom: false, left: false, right: true },
        margins: {
            top: position === "top" ? clearance : gap,
            bottom: gap,
            left: gap,
            right: position === "right" ? clearance : gap
        }
    }
}

function historyRows(raw, liveRows, normalUrgency, limit) {
    var max = Math.max(0, Math.floor(finiteNumber(limit, 10)))
    var result = []
    var seen = {}
    function collect(rows) {
        if (!Array.isArray(rows)) return
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            if (!row) continue
            var key = popupFileName(row)
            if (seen[key]) continue
            seen[key] = true
            result.push(normalizeHistoryEntry(row))
        }
    }
    collect(liveRows)
    collect(parsePopupFiles(raw, normalUrgency))
    result.sort(function(left, right) { return Number(right.timestamp || 0) - Number(left.timestamp || 0) })
    return result.slice(0, max)
}

if (typeof module !== "undefined") {
    module.exports = {
        boundedText: boundedText,
        isChromiumDerived: isChromiumDerived,
        sanitizeBody: sanitizeBody,
        styledBody: styledBody,
        stripImageTags: stripImageTags,
        summaryStartsWithGlyph: summaryStartsWithGlyph,
        normalizedIdentity: normalizedIdentity,
        workspaceRouteData: workspaceRouteData,
        workspaceRouteScore: workspaceRouteScore,
        shouldBypassDnd: shouldBypassDnd,
        isEphemeralApp: isEphemeralApp,
        stringHint: stringHint,
        glyphFromHints: glyphFromHints,
        execArgvFromHints: execArgvFromHints,
        parseExecArgv: parseExecArgv,
        shouldRenderCompactGlyph: shouldRenderCompactGlyph,
        snapshotOf: snapshotOf,
        popupEntry: popupEntry,
        popupFileName: popupFileName,
        imageStem: imageStem,
        hasPopupIdentity: hasPopupIdentity,
        localImageFile: localImageFile,
        persistablePopup: persistablePopup,
        serializePopup: serializePopup,
        parsePopupFiles: parsePopupFiles,
        popupExpired: popupExpired,
        popupPlacement: popupPlacement,
        historyRows: historyRows,
        historyEntry: historyEntry,
        historyKey: historyKey,
        isRenderableHistoryEntry: isRenderableHistoryEntry,
        parseSettings: parseSettings,
        parseHistory: parseHistory,
        durationFor: durationFor,
        isInboxPersistent: isInboxPersistent,
        transientFromNotification: transientFromNotification,
        hasBusName: hasBusName,
        busOwnerPid: busOwnerPid,
        defaultActionText: defaultActionText,
        screenshotSnapshot: screenshotSnapshot
    }
}
