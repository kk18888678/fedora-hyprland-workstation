// Per-application cooperation registry for notification actions.
//
// A retained Inbox row can outlive its sender: the freedesktop Notify object is
// gone, so the sender's own live `default`/`Activate` action can no longer be
// invoked, and a non-default action such as Chromium's `Settings` has nothing
// left to run. The generic answer for that case is to focus the sender window
// and report `routed`, which is honest but not a real action.
//
// This module is the documented, narrow exception layer that makes a small,
// reviewed set of those actions real. It is keyed by a STABLE application id
// (a desktop-entry id or Flatpak application id, never a display name) plus
// the action identifier the sender advertised. Each value is an argv vector or
// a URI. A value is NEVER a shell command string and is NEVER assembled by
// interpolation, so no notification body, summary, sender path, or other
// sender-controlled text can become part of a command.
//
// The registry is not a general mechanism and must not grow into one. Every
// entry is a per-application exception with a stated reason. An unknown
// application, an unknown action identifier, or a malformed entry fails closed
// (the service reports `unavailable` or `routed`), never a silent no-op.

var MAX_IDENTIFIER_LENGTH = 128
var MAX_ARGV_LENGTH = 32
// The one platform opener a URI entry resolves through. `gtk-launch` launches
// the exact application named by the stable id and passes the URI as an
// argument, so a URI entry can never open a different application's handler.
var URI_LAUNCHER = "/usr/bin/gtk-launch"

// A stable application id is an opaque identifier: a desktop-entry id such as
// `chromium-browser` or a Flatpak application id such as `com.ulaa.Ulaa`.
// Display names ("Google Chrome", "Visual Studio Code") contain whitespace or
// other characters that never appear in an identifier, so they are rejected.
function isStableApplicationId(value) {
    if (typeof value !== "string") return false
    if (value === "" || value.length > MAX_IDENTIFIER_LENGTH) return false
    if (/\s/.test(value)) return false
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)
}

function isActionIdentifier(value) {
    if (typeof value !== "string") return false
    if (value === "" || value.length > MAX_IDENTIFIER_LENGTH) return false
    if (/\s/.test(value)) return false
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)
}

function isNonEmptyString(value) {
    return typeof value === "string" && value.length > 0
}

function isPositiveInteger(value) {
    return typeof value === "number" && isFinite(value) &&
        Math.floor(value) === value && value >= 1
}

function isStringArray(value) {
    if (!Array.isArray(value) || value.length === 0 || value.length > MAX_ARGV_LENGTH) return false
    for (var i = 0; i < value.length; i++) {
        if (typeof value[i] !== "string" || value[i] === "" || value[i].indexOf("\u0000") >= 0) return false
    }
    return true
}

function isUri(value) {
    if (!isNonEmptyString(value)) return false
    if (value.length > 2048) return false
    if (/\s/.test(value)) return false
    return /^[A-Za-z][A-Za-z0-9+.-]*:/.test(value)
}

// The explicit table. Exactly three entries, each a documented exception:
//
// 1. Chromium and the Chromium-derived Ulaa `Settings` action. Chromium
//    destroys its notification object the instant the notification is sent, so
//    a retained row has no live action to invoke and focusing the window is
//    otherwise the only option. Reopening the browser's own
//    notification-settings page makes the button real again.
//
//    These entries open the settings PAGE, never a tab. The originating browser
//    tab is reachable only through the browser's own live `default`/`Activate`
//    action while the Notification object still exists. Chromium's raw body
//    carries the page origin but never the page/tab identity, and there is no
//    post-hoc enumeration of the real profile's tabs. A URI that claimed to
//    select the originating tab would open a NEW tab and lie. This is a
//    permanent protocol limit, so the post-hoc browser case stays
//    window-focused with outcome `routed`; do not "fix" it by adding a tab URI.
//
// 2. Herdr's synthesized default `Open` action. Herdr's raw body carries only
//    a workspace number. The origin monitor reads HERDR_WORKSPACE_ID,
//    HERDR_TAB_ID and HERDR_PANE_ID from the notifying process, which identify
//    the exact workspace/tab/pane and are strictly more precise than the body
//    number. The captured origin is preferred; the body number is used only
//    when capture produced nothing. Navigation is delegated to the single
//    origin owner (`workstation-notification-focus`); the `originFocus` marker
//    exists because the origin is runtime data that must be passed as its own
//    argv element rather than interpolated into a command string.
var DEFAULT_ENTRIES = [
    {
        id: "chromium-browser",
        action: "settings",
        uri: "chrome://settings/content/notifications"
    },
    {
        id: "com.ulaa.Ulaa",
        action: "settings",
        argv: ["/usr/bin/flatpak", "run", "com.ulaa.Ulaa", "chrome://settings/content/notifications"]
    },
    {
        id: "Herdr",
        action: "default",
        originFocus: true
    }
]

// Validate one raw entry. The entry must name a stable id and action and must
// carry exactly one command form: a non-empty argv of strings, a URI with a
// scheme, or the Herdr origin-focus marker. Anything else is rejected.
function validateEntry(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return { ok: false, reason: "entry_not_object" }
    if (!isStableApplicationId(raw.id))
        return { ok: false, reason: "id_not_stable_application_id" }
    if (!isActionIdentifier(raw.action))
        return { ok: false, reason: "invalid_action_identifier" }

    var forms = 0
    if (raw.argv !== undefined) forms++
    if (raw.uri !== undefined) forms++
    if (raw.originFocus !== undefined) forms++
    if (forms !== 1) return { ok: false, reason: "entry_must_have_exactly_one_command_form" }

    if (raw.argv !== undefined && !isStringArray(raw.argv))
        return { ok: false, reason: "argv_must_be_nonempty_string_array" }
    if (raw.uri !== undefined && !isUri(raw.uri))
        return { ok: false, reason: "uri_must_be_nonempty_scheme_uri" }
    if (raw.originFocus !== undefined && raw.originFocus !== true)
        return { ok: false, reason: "originFocus_must_be_true" }

    return { ok: true, entry: raw }
}

// Build the validated lookup table. Rejected entries are returned separately so
// the caller can report them; they are never inserted into the table.
function buildRegistry(rawEntries) {
    var registry = {}
    var rejected = []
    var entries = Array.isArray(rawEntries) ? rawEntries : []
    for (var i = 0; i < entries.length; i++) {
        var raw = entries[i]
        var result = validateEntry(raw)
        var reportedId = raw && typeof raw.id === "string" ? raw.id : ""
        var reportedAction = raw && typeof raw.action === "string" ? raw.action : ""
        if (!result.ok) {
            rejected.push({ id: reportedId, action: reportedAction, reason: result.reason, index: i })
            continue
        }
        if (!registry[result.entry.id]) registry[result.entry.id] = {}
        if (registry[result.entry.id][result.entry.action]) {
            rejected.push({ id: result.entry.id, action: result.entry.action, reason: "duplicate_entry", index: i })
            continue
        }
        registry[result.entry.id][result.entry.action] = result.entry
    }
    return { registry: registry, rejected: rejected }
}

function buildDefaultRegistry() {
    return buildRegistry(DEFAULT_ENTRIES)
}

function lookup(registry, appId, actionId) {
    if (!registry || typeof appId !== "string" || typeof actionId !== "string") return null
    var actions = registry[appId]
    if (!actions) return null
    return actions[actionId] || null
}

// The stable id for a durable row: the desktop-entry hint when it is a real
// identifier, otherwise the app name only when that is itself identifier-shaped
// (Herdr), never an arbitrary display name.
function stableApplicationId(entry) {
    var desktopEntry = entry && entry.desktopEntry
    if (isStableApplicationId(desktopEntry)) return desktopEntry
    var app = entry && entry.app
    if (isStableApplicationId(app)) return app
    return ""
}

// gtk-launch names the exact desktop application and passes the URI to it.
function uriLaunchArgv(appId, uri) {
    if (!isStableApplicationId(appId) || !isUri(uri)) return null
    return [URI_LAUNCHER, appId, uri]
}

// Herdr's identity-only fallback, matching the shape the single origin owner
// understands. The workspace number is a validated integer, never raw body
// text.
function herdrIdentityOrigin(number) {
    return {
        originVersion: 1,
        captureQuality: "identity",
        captureSource: "identity",
        notify: { appName: "Herdr", desktopEntry: "Herdr" },
        sender: { ancestry: [], focusEnv: {} },
        compositor: { matched: false, matchConfidence: "none", candidates: [] },
        tab: { kind: "herdr", workspaceId: String(number), tabId: null, paneId: null }
    }
}

// Resolve to an executable form without ever touching the OS. Returns exactly
// one of:
//   { kind: "argv", argv: [...] }       a concrete argv vector
//   { kind: "origin", origin: {...} }   an origin for the navigation owner
// or null when the (app, action) pair is unknown, malformed, or lacks the
// runtime data it needs. Nothing here can return a shell string.
function resolveAction(registry, appId, actionId, context) {
    var spec = lookup(registry, appId, actionId)
    if (!spec) return null

    if (spec.uri !== undefined) {
        var uriArgv = uriLaunchArgv(appId, spec.uri)
        return uriArgv ? { kind: "argv", argv: uriArgv } : null
    }
    if (spec.originFocus === true) {
        var origin = resolveOrigin(context)
        return origin ? { kind: "origin", origin: origin } : null
    }
    if (isStringArray(spec.argv)) return { kind: "argv", argv: spec.argv.slice() }
    return null
}

function resolveOrigin(context) {
    var source = context || {}
    var captured = source.origin
    if (captured && typeof captured === "object" && !Array.isArray(captured)) return captured
    if (isPositiveInteger(source.herdrNumber)) return herdrIdentityOrigin(source.herdrNumber)
    return null
}

function resolveForEntry(registry, entry, actionId, context) {
    var appId = stableApplicationId(entry)
    if (appId === "") return null
    return resolveAction(registry, appId, actionId, context)
}

if (typeof module !== "undefined") {
    module.exports = {
        MAX_IDENTIFIER_LENGTH: MAX_IDENTIFIER_LENGTH,
        URI_LAUNCHER: URI_LAUNCHER,
        DEFAULT_ENTRIES: DEFAULT_ENTRIES,
        isStableApplicationId: isStableApplicationId,
        isActionIdentifier: isActionIdentifier,
        isStringArray: isStringArray,
        isUri: isUri,
        validateEntry: validateEntry,
        buildRegistry: buildRegistry,
        buildDefaultRegistry: buildDefaultRegistry,
        lookup: lookup,
        stableApplicationId: stableApplicationId,
        uriLaunchArgv: uriLaunchArgv,
        herdrIdentityOrigin: herdrIdentityOrigin,
        resolveAction: resolveAction,
        resolveOrigin: resolveOrigin,
        resolveForEntry: resolveForEntry
    }
}
