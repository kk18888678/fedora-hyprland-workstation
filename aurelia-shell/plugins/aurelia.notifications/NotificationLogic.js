// Pure notification policy and serialization helpers. QML owns live
// Notification objects; this module only produces bounded plain data so C++
// QObject lifetimes never leak into ListModel roles or persisted state.

var MAX_APP_LENGTH = 128
var MAX_TEXT_LENGTH = 4096
var MAX_IMAGE_LENGTH = 2048
var MAX_ACTIONS = 8
// The only origin record shape this build understands. A missing, unknown or
// corrupt version never gates loading: it degrades to an empty origin field
// while the notification itself still displays and is retained.
var ORIGIN_VERSION = 1
var ORIGIN_QUALITIES = ["exact", "origin", "identity"]
// A failure reason is shown on the card and the retained Inbox row, so it is
// bounded and collapsed to a single line. It is produced by the helper from
// its own state and never contains raw notification body text.
var MAX_REASON_LENGTH = 512
var UNKNOWN_REASON_MESSAGE = "unknown reason (diagnostic incomplete)"
// The generic glyph the notification persistence mapper used to substitute
// when the shared resolver proved no icon. No code path produces it any more;
// it exists only so the restore path can recognise and clean a legacy row. An
// unresolved icon is persisted as the EMPTY string, which draws nothing.
var LEGACY_GENERIC_ICON = "application-x-executable"
var sharedSourceUrl = null

function loadSourceUrl() {
    if (sharedSourceUrl) return sharedSourceUrl
    try {
        if (typeof require === "function") {
            sharedSourceUrl = require("../../services/SourceUrl.js")
        } else if (typeof Qt !== "undefined" && typeof Qt.include === "function") {
            var includeResult = Qt.include("../../services/SourceUrl.js")
            if (includeResult && includeResult.status === 0 && typeof AureliaSourceUrl !== "undefined")
                sharedSourceUrl = AureliaSourceUrl
        }
    } catch (error) {
        console.error("[NOTIFICATIONS] source_url_load_failed detail=" + String(error || "unknown error"))
    }
    if (!sharedSourceUrl) console.error("[NOTIFICATIONS] source_url_unavailable")
    return sharedSourceUrl
}

function localFileUrl(value) {
    var sourceUrl = loadSourceUrl()
    return sourceUrl && typeof sourceUrl.fileUrl === "function" ? sourceUrl.fileUrl(value) : ""
}

function boundedText(value, limit) {
    var text = String(value === undefined || value === null ? "" : value)
    var max = Number(limit)
    if (!isFinite(max) || max < 1) max = MAX_TEXT_LENGTH
    if (text.length <= max) return text
    return text.slice(0, Math.max(1, max - 1)) + "…"
}

// The outcome vocabulary is a small closed set. Anything else is dropped so a
// corrupt persisted file cannot inject arbitrary text into the card.
function boundedOutcome(value) {
    var text = boundedText(value, 64)
    if (text === "") return ""
    return /^[a-z][a-z0-9_-]*$/.test(text) ? text : ""
}

// A bounded, single-line, sanitized reason. Whitespace is collapsed so a
// multi-line or control-character payload cannot disturb the card layout.
function boundedReason(value) {
    var text = boundedText(value, MAX_REASON_LENGTH)
    return text.replace(/[\r\n\t]+/g, " ").replace(/\s{2,}/g, " ").trim()
}

// The honest, user-visible message for an action outcome. Success is silent; a
// non-success with an empty reason is a diagnostic defect and says so instead
// of pretending the click simply did nothing.
function actionOutcomeMessage(outcome, reason) {
    var value = boundedOutcome(outcome)
    if (value === "" || value === "delivered" || value === "executed") return ""
    var why = boundedReason(reason)
    var label = "Could not open"
    if (value === "routed") label = "Routed to the source window"
    else if (value === "none") label = "No target"
    return label + ": " + (why === "" ? UNKNOWN_REASON_MESSAGE : why)
}

function finiteNumber(value, fallback) {
    var number = Number(value)
    return isFinite(number) ? number : fallback
}

var WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function padTwo(value) {
    var number = Math.floor(Math.abs(Number(value)))
    return (number < 10 ? "0" : "") + String(number)
}

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
}

// Human-readable notification age for the shared card header. Recent items
// read as a relative age; older items fall back to a calendar-aware label so a
// notification stays unambiguous. Kept pure and locale-free so it can be
// unit-tested in isolation and bound from any surface.
function timestampLabel(timestamp, now) {
    var stamp = finiteNumber(timestamp, 0)
    if (stamp <= 0) return ""
    var date = new Date(stamp)
    if (isNaN(date.getTime())) return ""
    var current = new Date(finiteNumber(now, Date.now()))
    var elapsedSeconds = Math.floor(Math.max(0, current.getTime() - stamp) / 1000)
    if (elapsedSeconds < 45) return "Just now"
    var clock = padTwo(date.getHours()) + ":" + padTwo(date.getMinutes())
    var dayDiff = Math.round((startOfDay(current) - startOfDay(date)) / 86400000)
    if (dayDiff <= 0) {
        if (elapsedSeconds < 3600) return Math.max(1, Math.round(elapsedSeconds / 60)) + "m ago"
        return Math.max(1, Math.round(elapsedSeconds / 3600)) + "h ago"
    }
    if (dayDiff === 1) return "Yesterday " + clock
    if (dayDiff < 7) return WEEKDAY_LABELS[date.getDay()] + " " + clock
    if (date.getFullYear() === current.getFullYear())
        return date.getDate() + " " + MONTH_LABELS[date.getMonth()] + " " + clock
    return date.getDate() + " " + MONTH_LABELS[date.getMonth()] + " " + date.getFullYear()
}

function identityKey(originalId, timestamp) {
    var id = Number(originalId)
    var stamp = Number(timestamp)
    if (!isFinite(id) || !isFinite(stamp) || stamp <= 0) return ""
    return String(stamp) + "|" + String(id)
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
    var text = sanitizeBody(body, app, appIcon)
    var formatted = herdrBody(text, app)
    if (formatted !== "") text = formatted
    return stripImageTags(text.replace(/\r\n|\r|\n/g, "<br/>"))
}

// Plain-text projection of a notification for the clipboard. The card's Copy
// action must not leak image markup or Chromium's leading URL chrome.
function copyText(entry) {
    var value = entry || {}
    var app = boundedText(value.app, MAX_APP_LENGTH)
    var summary = boundedText(value.summary, MAX_TEXT_LENGTH)
    var body = sanitizeBody(value.body, app, value.appIcon)
    var parts = []
    if (app !== "") parts.push(app)
    if (summary !== "") parts.push(summary)
    if (body !== "") parts.push(body)
    return parts.join("\n")
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
    var routeSource = route || {}
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

    // Browser web-app windows can deliberately reuse a native application's
    // desktop/app id. Prefer a window title that identifies the sender itself
    // (for example the native ChatGPT window titled "ChatGPT") over an
    // activated Chromium window whose title belongs to another site.
    var senderNames = [normalizedIdentity(routeSource.appName), normalizedIdentity(routeSource.desktopEntry)]
    var candidateTitles = [normalizedIdentity(candidate.title), normalizedIdentity(candidate.initialTitle)]
    var exactSenderTitle = false
    var containsSenderTitle = false
    for (var s = 0; s < senderNames.length; s++) {
        if (senderNames[s].length < 3) continue
        for (var t = 0; t < candidateTitles.length; t++) {
            if (candidateTitles[t] === senderNames[s]) exactSenderTitle = true
            else if (candidateTitles[t].indexOf(senderNames[s]) !== -1) containsSenderTitle = true
        }
    }
    if (exactSenderTitle) score += 70
    else if (containsSenderTitle) score += 35

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
        if (typeof console !== "undefined" && console.info)
            console.info("[NOTIFICATIONS] hint_rejected name=" + String(name || ""))
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
        if (typeof console !== "undefined" && console.info)
            console.info("[NOTIFICATIONS] transient_hint_rejected")
        return false
    }
}

function parseExecArgv(value) {
    var text = String(value || "")
    if (text === "") return null
    var parsed
    try {
        parsed = JSON.parse(text)
    } catch (error) {
        if (typeof console !== "undefined" && console.info)
            console.info("[NOTIFICATIONS] exec_argv_rejected reason=invalid_json")
        return null
    }
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
    try {
        source = notification && notification.actions ? notification.actions : []
    } catch (error) {
        if (typeof console !== "undefined" && console.warn)
            console.warn("[NOTIFICATIONS] actions_read_failed")
        source = []
    }
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
    try {
        source = notification && notification.actions ? notification.actions : []
    } catch (error) {
        if (typeof console !== "undefined" && console.warn)
            console.warn("[NOTIFICATIONS] default_action_read_failed")
        source = []
    }
    if (!source || typeof source.length !== "number") return ""

    for (var i = 0; i < source.length; i++) {
        var action = source[i]
        if (!action || boundedText(action.identifier, 256) !== "default") continue
        var text = boundedText(action.text, 256)
        return text === "" ? "Open" : text
    }
    return ""
}

// Herdr, the terminal workspace manager pi runs inside, reports completion as
// `<workspace label> · <workspace number> · <count>`. Parse the workspace so
// the toast can offer a jump back to the chat, and render the body in words
// instead of the raw middot line.
function herdrRoute(notification) {
    var n = notification || {}
    if (boundedText(n.appName, MAX_APP_LENGTH).toLowerCase() !== "herdr") return null
    var parts = String(n.body || "").split("·")
    if (parts.length < 2) return null
    var label = parts[0].trim()
    var number = parseInt(parts[1].trim(), 10)
    if (label === "" || !isFinite(number) || number < 1) return null
    return { label: label, number: number }
}

function herdrBody(body, app) {
    if (String(app || "").toLowerCase() !== "herdr") return ""
    var parts = String(body || "").split("·")
    if (parts.length < 2) return ""
    var label = parts[0].trim()
    var number = parseInt(parts[1].trim(), 10)
    if (label === "" || !isFinite(number)) return ""
    return label + " · workspace " + number
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
    var herdr = herdrRoute(n)
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
        // Herdr's synthesized Open is resolved through the reviewed action
        // registry at click time; it is never built into a shell string here.
        // The visible label stays "Open".
        execArgv: boundedText(execArgvFromHints(n.hints), MAX_TEXT_LENGTH),
        actions: actionsOf(n),
        defaultActionText: defaultActionText(n) || (herdr ? "Open" : ""),
        urgency: urgency,
        expireTimeout: expireTimeout,
        timestamp: stamp,
        deadline: duration > 0 ? stamp + duration : 0,
        transient: transient,
        origin: "",
        actionOutcome: "",
        actionOutcomeReason: ""
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
        // Always a number so a materialized ListModel row can be re-persisted
        // without handing the model an undefined role value.
        deadline: 0,
        timestamp: timestamp,
        transient: entry.transient === true,
        origin: originFieldValue(entry.origin),
        // The outcome and its bounded reason are durable so a retained Inbox
        // row can still explain a failed click after the transient toast has
        // expired or the shell has reloaded. Only the outcome word and a
        // sanitized reason are stored; never raw notification body text.
        actionOutcome: boundedOutcome(entry.actionOutcome),
        actionOutcomeReason: boundedReason(entry.actionOutcomeReason)
    }
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
        if (typeof console !== "undefined" && console.warn)
            console.warn("[NOTIFICATIONS] settings_parse_failed")
        return { ok: false, dnd: null, legacy: false }
    }
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
        body: "The capture is available in Pictures/Screenshots and on the clipboard.",
        image: localFileUrl(source),
        glyph: "",
        execArgv: "",
        actions: [],
        defaultActionText: "",
        urgency: 0,
        expireTimeout: 5000,
        timestamp: stamp,
        deadline: stamp + 5000,
        transient: true,
        origin: "",
        actionOutcome: "",
        actionOutcomeReason: ""
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

// A value this build previously produced and can trust as durable: a file://
// path inside our own per-user store. A sender's absolute path, provider URL
// (`image://...`) or transient file:// path is never durable. A bare theme name
// is re-resolved idempotently, which also lets a real content image win over a
// generic app icon (the screenshot case).
function isDurableIconValue(value, imagesDir) {
    var source = String(value || "")
    if (source === "") return false
    if (source.indexOf("file://") !== 0) return false
    var sourceUrl = loadSourceUrl()
    if (!sourceUrl || typeof sourceUrl.pathFromUrl !== "function" ||
        typeof sourceUrl.isDescendant !== "function") return false
    if (String(imagesDir || "") === "") return false
    var path = sourceUrl.pathFromUrl(source)
    return path.charAt(0) === "/" && sourceUrl.isDescendant(path, String(imagesDir))
}

function durableIconValue(entry, imagesDir) {
    var source = entry || {}
    var values = [source.appIcon, source.image]
    for (var i = 0; i < values.length; i++) {
        if (isDurableIconValue(values[i], imagesDir)) return String(values[i])
    }
    return ""
}

// Build the input for the shared AppIconResolver owner. The resolved durable
// value from a reload is passed as `localPath` so it is used as-is and never
// re-resolved. A live inline `image://qsimage/...` provider is not a byte
// stream we can persist, so it is deliberately left out of `imageData`: the
// owner then falls through to the desktop-entry/window/default candidates
// instead of handing the card a transient provider URL.
function iconResolutionInput(entry, imagesDir) {
    var source = entry || {}
    var appIcon = boundedText(source.appIcon, MAX_IMAGE_LENGTH)
    var image = boundedText(source.image, MAX_IMAGE_LENGTH)
    var imageData = ""
    if (image.indexOf("image://qsimage/") !== 0 && source.imageData !== undefined) {
        imageData = boundedText(source.imageData, MAX_IMAGE_LENGTH)
    }
    return {
        localPath: durableIconValue(source, imagesDir),
        imageData: imageData,
        appIcon: appIcon,
        image: image,
        desktopEntry: boundedText(source.desktopEntry, MAX_APP_LENGTH),
        appName: boundedText(source.app, MAX_APP_LENGTH),
        origin: originFromField(source.origin)
    }
}

// Decode the local file backing a resolver result. Only a resolver-produced
// file:// source is accepted; the pure owner already proved the file is real
// before returning it.
function resolverFilePath(resolution) {
    var source = String((resolution && resolution.source) || "")
    if (source.indexOf("file://") !== 0) return ""
    var sourceUrl = loadSourceUrl()
    if (!sourceUrl || typeof sourceUrl.pathFromUrl !== "function") return ""
    var path = sourceUrl.pathFromUrl(source)
    return path.charAt(0) === "/" ? path : ""
}

// Map the shared resolver's result onto the durable persisted entry. A file
// source is copied into our own per-user store under the notification's own
// stem; a theme/default name is retained AS A NAME with no copy. The filename
// the persist job must produce is declared in `copies`; the job fails closed
// (see COPY_IMAGES_SCRIPT) rather than writing a dangling file:// path if the
// copy cannot be verified. An unresolved icon (the resolver's empty default)
// is persisted as the EMPTY string so the card draws nothing and reserves no
// slot, never as a generic glyph.
function persistablePopup(entry, imagesDir, resolution) {
    var source = entry || {}
    var output = {}
    for (var key in source) output[key] = source[key]
    var copies = []
    var stem = imageStem(source)
    var store = String(imagesDir || "")
    var icon = resolution || {}
    var kind = String(icon.kind || "default")
    var name = boundedText(icon.name, MAX_IMAGE_LENGTH)
    var durableValue = ""

    if (kind === "durable") {
        // Already durable from a reload: keep the file:// copy or the theme
        // name exactly as stored. Never re-resolve and never re-copy.
        durableValue = name !== "" ? name : String(icon.source || "")
    } else if (kind === "file" || kind === "inline") {
        var from = resolverFilePath(icon)
        if (from !== "" && stem !== "" && store !== "") {
            var to = store + stem + "-appIcon"
            if (from !== to) copies.push({ from: from, to: to })
            durableValue = localFileUrl(to)
        } else {
            // An inline provider URL cannot be byte-copied. Fall through to a
            // retained name, or the empty string when nothing resolved,
            // instead of a dangling path or a generic glyph.
            durableValue = name !== "" ? name : ""
        }
    } else {
        durableValue = name !== "" ? name : ""
    }
    output.appIcon = durableValue
    // The card has a single icon slot; clearing the image role guarantees the
    // resolved icon wins and no raw provider or sender path is ever persisted.
    output.image = ""
    return { entry: output, copies: copies }
}

// An empty hints object is the absence of hint-derived application identity.
// Anything else is treated as evidence and leaves the row untouched.
function emptyHints(hints) {
    if (!hints || typeof hints !== "object" || Array.isArray(hints)) return true
    for (var key in hints) {
        if (Object.prototype.hasOwnProperty.call(hints, key)) return false
    }
    return true
}

// True only for a persisted row that stores the legacy generic glyph but
// carries no real icon evidence: no copied durable image, no separate image
// value, no desktop entry (top-level or in the captured origin), and no
// notification hint that could have identified a real application. The name
// alone is not enough, because an application may legitimately resolve that
// exact theme icon; the absence of supporting evidence is what makes the
// stored value stale.
function isUnprovenLegacyIcon(entry, imagesDir) {
    var value = entry || {}
    if (boundedText(value.appIcon, MAX_IMAGE_LENGTH) !== LEGACY_GENERIC_ICON) return false
    if (durableIconValue(value, imagesDir) !== "") return false
    if (boundedText(value.image, MAX_IMAGE_LENGTH) !== "") return false
    if (boundedText(value.desktopEntry, MAX_APP_LENGTH) !== "") return false
    if (!emptyHints(value.hints)) return false
    var origin = originFromField(value.origin)
    if (origin && origin.notify && typeof origin.notify === "object") {
        if (boundedText(origin.notify.desktopEntry, MAX_APP_LENGTH) !== "") return false
        if (!emptyHints(origin.notify.hints)) return false
    }
    return true
}

// Clear the stale legacy glyph on a restored row in place. Returns true when
// the row changed; a row that is not proven stale is never modified. Callers
// that persist the row back to disk can use the return value.
function normalizeRestoredIcon(entry, imagesDir) {
    if (!isUnprovenLegacyIcon(entry, imagesDir)) return false
    entry.appIcon = ""
    return true
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
            var entry = value && typeof value === "object" ? popupEntry(value, normalUrgency) : null
            if (entry && hasPopupIdentity(entry)) entries.push(entry)
        } catch (error) {
            if (typeof console !== "undefined" && console.warn)
                console.warn("[NOTIFICATIONS] popup_file_line_rejected line=" + String(i + 1))
        }
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

// Validate and detach an origin record. Only the shipped origin version and
// the three known capture qualities are accepted; anything else is dropped to
// null so a corrupt file cannot crash the click path. Round-tripping through
// JSON also detaches the record from any ListModel/QObject wrapper.
function normalizeOrigin(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null
    var version = finiteNumber(value.originVersion, -1)
    if (version !== ORIGIN_VERSION) return null
    var quality = String(value.captureQuality || "")
    if (ORIGIN_QUALITIES.indexOf(quality) === -1) return null
    var copy
    try {
        copy = JSON.parse(JSON.stringify(value))
    } catch (error) {
        if (typeof console !== "undefined" && console.warn)
            console.warn("[NOTIFICATIONS] origin_rejected reason=unserializable")
        return null
    }
    if (!copy || typeof copy !== "object" || Array.isArray(copy)) return null
    return copy
}

// ListModel roles cannot carry a null or object member, so the origin travels
// as a validated JSON string in the model and popup file. Both directions are
// fail-closed: anything unrecognised becomes the empty string.
function originFieldValue(value) {
    var origin
    if (typeof value === "string") {
        if (value === "") return ""
        try {
            origin = normalizeOrigin(JSON.parse(value))
        } catch (error) {
            if (typeof console !== "undefined" && console.info)
                console.info("[NOTIFICATIONS] origin_rejected reason=field_unparseable")
            return ""
        }
    } else {
        origin = normalizeOrigin(value)
    }
    return origin ? JSON.stringify(origin) : ""
}

function originFromField(value) {
    if (!value) return null
    if (typeof value === "string") {
        if (value === "") return null
        try {
            return normalizeOrigin(JSON.parse(value))
        } catch (error) {
            if (typeof console !== "undefined" && console.info)
                console.info("[NOTIFICATIONS] origin_rejected reason=field_unparseable")
            return null
        }
    }
    return normalizeOrigin(value)
}

// Read the final JSON line printed by `capture`. `null` (or any unparseable
// payload) means there is no origin, never an error condition.
function parseOriginOutput(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
        var line = lines[i].trim()
        if (line === "") continue
        if (line === "null") return null
        try {
            return normalizeOrigin(JSON.parse(line))
        } catch (error) {
            if (typeof console !== "undefined" && console.info)
                console.info("[NOTIFICATIONS] origin_rejected reason=capture_payload_unparseable")
            return null
        }
    }
    return null
}

// Read the single JSON outcome object printed by `navigate`. A malformed or
// unknown payload is treated as an unavailable navigation, never as success.
function parseNavigateOutput(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
        var line = lines[i].trim()
        if (line === "") continue
        try {
            var parsed = JSON.parse(line)
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
            var outcome = String(parsed.outcome || "")
            if (["focused", "routed", "unavailable", "none"].indexOf(outcome) === -1) return null
            return {
                outcome: outcome,
                confidence: String(parsed.confidence || "none"),
                reason: String(parsed.reason || "")
            }
        } catch (error) {
            if (typeof console !== "undefined" && console.info)
                console.info("[NOTIFICATIONS] navigate_outcome_rejected reason=unparseable")
            return null
        }
    }
    return null
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

if (typeof module !== "undefined") {
    module.exports = {
        boundedText: boundedText,
        boundedOutcome: boundedOutcome,
        boundedReason: boundedReason,
        actionOutcomeMessage: actionOutcomeMessage,
        UNKNOWN_REASON_MESSAGE: UNKNOWN_REASON_MESSAGE,
        timestampLabel: timestampLabel,
        isChromiumDerived: isChromiumDerived,
        sanitizeBody: sanitizeBody,
        styledBody: styledBody,
        copyText: copyText,
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
        identityKey: identityKey,
        popupEntry: popupEntry,
        popupFileName: popupFileName,
        imageStem: imageStem,
        hasPopupIdentity: hasPopupIdentity,
        isDurableIconValue: isDurableIconValue,
        durableIconValue: durableIconValue,
        iconResolutionInput: iconResolutionInput,
        resolverFilePath: resolverFilePath,
        persistablePopup: persistablePopup,
        isUnprovenLegacyIcon: isUnprovenLegacyIcon,
        normalizeRestoredIcon: normalizeRestoredIcon,
        serializePopup: serializePopup,
        parsePopupFiles: parsePopupFiles,
        popupExpired: popupExpired,
        popupPlacement: popupPlacement,
        parseSettings: parseSettings,
        durationFor: durationFor,
        isInboxPersistent: isInboxPersistent,
        transientFromNotification: transientFromNotification,
        ORIGIN_VERSION: ORIGIN_VERSION,
        normalizeOrigin: normalizeOrigin,
        originFieldValue: originFieldValue,
        originFromField: originFromField,
        parseOriginOutput: parseOriginOutput,
        parseNavigateOutput: parseNavigateOutput,
        hasBusName: hasBusName,
        busOwnerPid: busOwnerPid,
        defaultActionText: defaultActionText,
        screenshotSnapshot: screenshotSnapshot
    }
}
