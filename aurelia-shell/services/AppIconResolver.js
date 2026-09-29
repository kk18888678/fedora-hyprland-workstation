// Shared application-icon resolution policy for Aurelia.
//
// This file is deliberately a pure JavaScript module: it never imports Qt,
// Quickshell, or any host binding, so the deterministic candidate ordering,
// normalisation and validation can be exercised by the node test runner with
// no live shell. Its QML companion (AppIconResolver.qml) supplies only the
// environment probes (theme lookup, file existence, .desktop/AppStream reads)
// and delegates every ordering decision back here.
//
// The ordered chain is evaluated top to bottom and stops at the first
// candidate that is *provably usable*:
//
//   0 durable   already-durable file:// from rehydration (used as-is)
//   1 inline    image-data/image_data/icon_data (image://qsimage/...)
//   2 file      absolute path or file:// in app_icon or the image-path hint
//   3 theme     bare theme name in app_icon
//   4 theme     theme name extracted from a themed image://icon/<name> value
//   5 desktop   Quickshell-resolved or directly-read .desktop Icon=
//   6 appstream AppStream/SW-Catalog metadata icon
//   7 window    sender window class / app id (terminal ancestor preferred)
//   8 proc      sender /proc exe/comm basename
//   9 default   no icon (nothing resolved; deliberate, logged outcome)
//
// "Provably usable" is enforced by the resolver, not assumed by a caller: a
// file source must exist and be non-empty, and a name source must satisfy the
// host's theme lookup. A durable path that does not back a real file is never
// returned, so a card can never be handed a dangling file:// that later turns
// into a silent Image.Error blank.

"use strict";

// Every field is bounded before it reaches a candidate. A field longer than
// its bound is rejected outright rather than silently truncated, so an
// oversized sender-controlled value can never smuggle a path fragment past
// validation.
var MAX_THEME_NAME = 256;
var MAX_PATH = 4096;
var MAX_FIELD = 512;
var MAX_ID = 256;

var DEFAULT_ICON = "application-x-executable";

// Diagnostic channel. This module never imports Qt or Quickshell, so it records
// its condition-name diagnostics through the shell console, which Quickshell
// forwards to the journal. A diagnostic is a stable condition NAME only: never
// a value, file path, or any user-derived content. `no_icon_resolved` is
// recorded when the ordered chain falls through to the deliberate no-icon
// state, so "no icon" is an observable, intentional outcome rather than a
// silent failure. It is recorded on the informational channel because a
// fall-through is an expected outcome (not a decode/IO failure), and consumers
// such as the notification service deliberately supply their own fallback when
// it happens.
var DIAGNOSTIC_NO_ICON_RESOLVED = "no_icon_resolved";

function logDiagnostic(condition) {
    if (typeof console === "undefined") return;
    var write = console.info || console.log;
    if (write) write("[APP-ICON] " + condition);
}

// The substring-match guard mirrors NotificationLogic.workspaceRouteScore: a
// short generic name such as "chat" or "term" must never be substring-matched
// into an unrelated application id. Both sides must be at least this long.
var SUBSTRING_MATCH_MIN_LENGTH = 5;

// Theme names are freedesktop icon names: an alphanumeric start followed by
// alphanumerics, underscore, dot, plus or hyphen. Directory separators,
// parent traversal and tilde are rejected separately so no name can escape a
// theme root or be mistaken for a path.
var THEME_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9_.+-]*$/;

function text(value) {
    return String(value === undefined || value === null ? "" : value);
}

function hasControlCharacters(value) {
    return /[\u0000-\u001f\u007f]/.test(value);
}

// bound + trim + reject. Returns "" for anything empty, whitespace-only,
// control-laden or longer than the bound.
function cleanField(value, max) {
    var maxLength = max === undefined ? MAX_FIELD : max;
    var raw = text(value);
    if (raw.length > maxLength) return "";
    if (hasControlCharacters(raw)) return "";
    raw = raw.replace(/^\s+|\s+$/g, "");
    return raw;
}

function firstNonEmpty() {
    for (var i = 0; i < arguments.length; i++) {
        var value = arguments[i];
        if (value !== undefined && value !== null && text(value) !== "") return value;
    }
    return "";
}

function pushUnique(list, value) {
    if (text(value) === "") return;
    for (var i = 0; i < list.length; i++) {
        if (list[i] === value) return;
    }
    list.push(value);
}

// ---------------------------------------------------------------------------
// Normalisation
// ---------------------------------------------------------------------------

function isValidThemeName(name) {
    var value = text(name);
    if (value === "" || value.length > MAX_THEME_NAME) return false;
    if (!THEME_NAME_RE.test(value)) return false;
    if (value.indexOf("/") !== -1) return false;
    if (value.indexOf("..") !== -1) return false;
    if (value.indexOf("~") !== -1) return false;
    return true;
}

function queryStripped(value) {
    var raw = text(value);
    var index = raw.indexOf("?");
    if (index >= 0) raw = raw.substring(0, index);
    index = raw.indexOf("#");
    if (index >= 0) raw = raw.substring(0, index);
    return raw;
}

// The canonical theme lookup name for a possibly query-carrying value. Returns
// "" when the value is not a safe theme name; callers must never feed a
// file://, image:// or absolute path into a theme lookup.
function themeLookupName(value) {
    var base = queryStripped(text(value));
    return isValidThemeName(base) ? base : "";
}

// Symbolic masks are the only names that may be tinted. Real application
// logos are full-colour artwork and must be rendered with preserveColors.
function isSymbolicName(value) {
    var base = queryStripped(text(value));
    return base.slice(-9) === "-symbolic";
}

function stripDesktopSuffix(value) {
    var id = text(value);
    return id.toLowerCase().slice(-8) === ".desktop" ? id.slice(0, -8) : id;
}

// Desktop id: strip a trailing .desktop and try exact then lower-case.
function desktopIdVariants(value) {
    var raw = cleanField(value, MAX_ID);
    if (raw === "" || raw.indexOf("/") !== -1) return [];
    var base = stripDesktopSuffix(raw);
    var out = [];
    pushUnique(out, base);
    pushUnique(out, base.toLowerCase());
    return out;
}

// Reverse-DNS/Flatpak id such as com.ulaa.Ulaa: as-is, lower-case, then the
// last dot segment. The .desktop Icon= is resolved by the desktop step.
function reverseDnsVariants(value) {
    var raw = cleanField(value, MAX_ID);
    if (raw === "" || raw.indexOf("/") !== -1) return [];
    var base = stripDesktopSuffix(raw);
    var out = [];
    pushUnique(out, base);
    pushUnique(out, base.toLowerCase());
    var index = base.lastIndexOf(".");
    if (index > 0 && index < base.length - 1) {
        var tail = base.substring(index + 1);
        pushUnique(out, tail);
        pushUnique(out, tail.toLowerCase());
    }
    return out;
}

// Wayland app id / window class: exact then lower-case, with the shared
// substring guard applied to every fuzzy mapping.
function classVariants(value) {
    var raw = cleanField(value, MAX_FIELD);
    if (raw === "") return [];
    var out = [];
    pushUnique(out, raw);
    pushUnique(out, raw.toLowerCase());
    return out;
}

function lowerCaseId(value) {
    var raw = cleanField(value, MAX_FIELD);
    return raw === "" ? "" : raw.toLowerCase();
}

function matchesSubstringGuard(left, right) {
    var a = text(left).toLowerCase();
    var b = text(right).toLowerCase();
    if (a === "" || b === "") return false;
    return a.length >= SUBSTRING_MATCH_MIN_LENGTH && b.length >= SUBSTRING_MATCH_MIN_LENGTH &&
        (a.indexOf(b) !== -1 || b.indexOf(a) !== -1);
}

// Historical active-window class-to-theme-name mapping. These are fuzzy
// fallbacks that only run once exact/lower-case ids have failed, and every
// substring decision honours the shared guard so "term"/"chat" cannot route
// an unrelated window onto a real application logo.
var CLASS_HEURISTICS = [
    { match: "chatgpt", icon: "chatgpt" },
    { match: "chrom", icon: "chromium" },
    { match: "kate", icon: "kate" },
    { match: "foot", icon: "utilities-terminal" }
];

function heuristicIconNames(value) {
    var lower = lowerCaseId(value);
    if (lower === "") return [];
    var out = [];
    for (var i = 0; i < CLASS_HEURISTICS.length; i++) {
        var rule = CLASS_HEURISTICS[i];
        if (lower === rule.match || matchesSubstringGuard(lower, rule.match)) {
            pushUnique(out, rule.icon);
        }
    }
    return out;
}

// /proc exe/comm basename, stripping a trailing .bin/-bin launcher wrapper.
function normalizeExeName(value) {
    var raw = cleanField(value, MAX_PATH);
    if (raw === "") return "";
    if (hasControlCharacters(raw)) return "";
    var normalized = raw.replace(/\s+/g, "");
    var slash = normalized.lastIndexOf("/");
    if (slash >= 0) normalized = normalized.substring(slash + 1);
    if (normalized.slice(-4) === ".bin") normalized = normalized.slice(0, -4);
    else if (normalized.slice(-4) === "-bin") normalized = normalized.slice(0, -4);
    return normalized;
}

// ---------------------------------------------------------------------------
// Path / URL classification
// ---------------------------------------------------------------------------

function pathFromFileUrl(value) {
    var source = text(value);
    if (source.indexOf("file://") !== 0) {
        return source.charAt(0) === "/" ? source : "";
    }
    var encoded = source.substring(7);
    if (encoded.indexOf("/") !== 0) {
        if (encoded.indexOf("localhost/") !== 0) return "";
        encoded = "/" + encoded.substring(10);
    }
    if (hasControlCharacters(encoded)) return "";
    try {
        return decodeURIComponent(encoded);
    } catch (error) {
        if (typeof console !== "undefined" && console.error)
            console.error("[APP-ICON] path_decode_failed");
        return "";
    }
}

// A local file path embedded in a value. Handles:
//   /absolute/path
//   a file:// URL
//   image://icon//absolute/path  (Chromium's embedded-path form)
// A themed image://icon/<name> (single slash) is not a path and returns "".
function localImageFile(value) {
    var source = cleanField(value, MAX_PATH);
    if (source === "") return "";
    if (source.indexOf("image://") === 0) {
        var remainder = source.substring("image://".length);
        var separator = remainder.indexOf("/");
        if (separator < 0) return "";
        source = remainder.substring(separator);
        if (source.indexOf("//") !== 0) return "";
        source = source.substring(1);
    } else if (source.indexOf("file://") === 0) {
        source = pathFromFileUrl(source);
    }
    return source.charAt(0) === "/" ? source : "";
}

function isInlineImageUrl(value) {
    return text(value).indexOf("image://qsimage/") === 0;
}

function isFileValue(value) {
    var source = text(value);
    if (source.indexOf("file://") === 0) return true;
    if (source.charAt(0) === "/") return true;
    if (source.indexOf("image://icon//") === 0) return true;
    return false;
}

// A theme name extracted from a themed image://icon/<name> value. This is
// exactly the form a bare notification image-path becomes, and is the fix for
// foot's missing icon.
function themeNameFromImageUrl(value) {
    var source = text(value);
    if (source.indexOf("image://icon/") !== 0) return "";
    var rest = source.substring("image://icon/".length);
    if (rest.indexOf("/") === 0) return "";
    return themeLookupName(rest);
}

// ---------------------------------------------------------------------------
// Candidate construction
// ---------------------------------------------------------------------------

function candidateKey(candidate) {
    return candidate.probeType + ":" + (candidate.probeType === "file" ? candidate.path : candidate.name);
}

function fileCandidate(value, kind, origin) {
    var path = localImageFile(value);
    if (path === "" || hasControlCharacters(path)) return null;
    return {
        kind: kind,
        probeType: "file",
        path: path,
        source: "",
        name: "",
        origin: origin
    };
}

function inlineCandidate(value, origin) {
    var source = cleanField(value, MAX_PATH);
    if (source === "") return null;
    return {
        kind: "inline",
        probeType: "inline",
        path: "",
        source: source,
        name: "",
        origin: origin
    };
}

function themeCandidate(name, kind, origin) {
    var lookup = themeLookupName(name);
    if (lookup === "") return null;
    return {
        kind: kind,
        probeType: "theme",
        path: "",
        source: "",
        name: lookup,
        origin: origin
    };
}

// Expand a single value into the inline/file/theme candidates it may
// represent, in the order the chain expects.
function candidatesFromValue(value, kind, origin) {
    var raw = cleanField(value, MAX_PATH);
    var out = [];
    if (raw === "") return out;

    if (isInlineImageUrl(raw)) {
        var inline = inlineCandidate(raw, origin);
        if (inline) out.push(inline);
        return out;
    }
    if (isFileValue(raw)) {
        var file = fileCandidate(raw, kind, origin);
        if (file) out.push(file);
        return out;
    }
    var themedName = themeNameFromImageUrl(raw);
    if (themedName !== "") {
        var themed = themeCandidate(themedName, kind, origin);
        if (themed) out.push(themed);
        return out;
    }
    var exact = themeCandidate(raw, kind, origin);
    if (exact) out.push(exact);
    var lower = themeLookupName(queryStripped(raw).toLowerCase());
    if (lower !== "") {
        var lowered = themeCandidate(lower, kind, origin);
        if (lowered) out.push(lowered);
    }
    return out;
}

function appendCandidate(out, seen, candidate) {
    if (!candidate) return;
    var key = candidateKey(candidate);
    if (seen[key] === true) return;
    seen[key] = true;
    out.push(candidate);
}

function defaultCandidate() {
    // `kind: "default"` is the semantic marker that NOTHING resolved. It is
    // intentionally an empty candidate: the user wants no icon rather than a
    // generic placeholder glyph, so source and name are blank and no image is
    // drawn. Consumers and their tests still assert on `kind === "default"`;
    // only the visible glyph was removed.
    return {
        kind: "default",
        probeType: "none",
        path: "",
        source: "",
        name: "",
        origin: "default"
    };
}

// The full ordered candidate list. `meta` is host-supplied metadata that the
// pure layer cannot read itself: directly-resolved desktop/AppStream icons,
// per-app Flatpak icon paths, and /proc basenames. Callers that omit it still
// receive a well-formed chain.
function buildCandidates(input, meta) {
    var source = input || {};
    var metadata = meta || {};
    var out = [];
    var seen = {};

    // 0. Already-durable value from rehydration. It is used as-is and is never
    //    re-resolved; the probe still proves it backs a real, non-empty file so
    //    a stale durable path can never be adopted.
    var durable = cleanField(source.localPath, MAX_PATH);
    if (durable !== "") {
        var durableCandidates = candidatesFromValue(durable, "durable", "durable-rehydrated");
        for (var d = 0; d < durableCandidates.length; d++) appendCandidate(out, seen, durableCandidates[d]);
    }

    // 1. Inline image-data (image://qsimage/...) which must be materialised at
    //    arrival. It may arrive as the dedicated field or as a value in the
    //    app-icon/image hint. A file path here means it was already
    //    materialised and is still treated as inline provenance.
    var inlineValue = cleanField(source.imageData, MAX_PATH);
    if (inlineValue !== "") {
        var inlineCandidates = candidatesFromValue(inlineValue, "inline", "inline-image-data");
        for (var i = 0; i < inlineCandidates.length; i++) appendCandidate(out, seen, inlineCandidates[i]);
    }

    // 2. Absolute path or file:// in app_icon or the image-path hint.
    var appIcon = cleanField(source.appIcon, MAX_PATH);
    var image = cleanField(source.image, MAX_PATH);
    var fileSources = [
        { value: appIcon, origin: "app-icon-path" },
        { value: image, origin: "image-path" }
    ];
    for (var f = 0; f < fileSources.length; f++) {
        var value = fileSources[f].value;
        if (value === "" || !isFileValue(value)) continue;
        appendCandidate(out, seen, fileCandidate(value, "file", fileSources[f].origin));
    }

    // 3. Bare theme name in app_icon.
    if (appIcon !== "" && !isFileValue(appIcon) && !isInlineImageUrl(appIcon)) {
        var appIconName = themeNameFromImageUrl(appIcon) || themeLookupName(appIcon);
        appendCandidate(out, seen, themeCandidate(appIconName, "theme", "app-icon-name"));
        var appIconLower = themeLookupName(queryStripped(appIcon).toLowerCase());
        appendCandidate(out, seen, themeCandidate(appIconLower, "theme", "app-icon-name-lower"));
    }

    // 4. Theme name extracted from a themed image://icon/<name> value.
    if (image !== "" && !isFileValue(image) && !isInlineImageUrl(image)) {
        var imageName = themeNameFromImageUrl(image) || themeLookupName(image);
        appendCandidate(out, seen, themeCandidate(imageName, "theme", "image-icon-name"));
        var imageLower = themeLookupName(queryStripped(image).toLowerCase());
        appendCandidate(out, seen, themeCandidate(imageLower, "theme", "image-icon-name-lower"));
    }

    // 5. desktop-entry. Prefer the host-resolved desktop icon (supplied by the
    //    caller as the app_icon hint or by DirectDesktopIcon metadata) and
    //    otherwise resolve the .desktop file directly. The direct lookup
    //    matters because Quickshell resolves desktop-entry asynchronously at
    //    startup, so a notification arriving before the scan leaves appIcon
    //    empty; the direct read closes that gap.
    var desktopEntry = cleanField(source.desktopEntry, MAX_ID);
    if (desktopEntry !== "" && desktopEntry.indexOf("/") === -1) {
        var idVariants = desktopThemeIds(source);
        for (var v = 0; v < idVariants.length; v++) {
            appendCandidate(out, seen, themeCandidate(idVariants[v], "desktop", "desktop-entry-id"));
        }
    }
    var directDesktopIcon = cleanField(metadata.desktopIcon, MAX_PATH);
    if (directDesktopIcon !== "") {
        var desktopValue = candidatesFromValue(directDesktopIcon, "desktop", "desktop-entry-icon");
        for (var c = 0; c < desktopValue.length; c++) appendCandidate(out, seen, desktopValue[c]);
    }

    // 5b. Per-app Flatpak export fallback for an icon not present in the
    //     merged exports. File candidates sit after the theme candidate so a
    //     provably-usable theme icon still wins.
    var flatpakIcons = metadata.flatpakIcons;
    if (flatpakIcons && flatpakIcons.length) {
        for (var p = 0; p < flatpakIcons.length; p++) {
            var flatpakPath = cleanField(flatpakIcons[p], MAX_PATH);
            if (flatpakPath.charAt(0) !== "/") continue;
            appendCandidate(out, seen, fileCandidate(flatpakPath, "desktop", "desktop-entry-flatpak"));
        }
    }

    // 6. AppStream / SW-Catalog metadata.
    var appstreamIcon = cleanField(metadata.appstreamIcon, MAX_PATH);
    if (appstreamIcon !== "") {
        var appstreamValue = candidatesFromValue(appstreamIcon, "appstream", "appstream-icon");
        for (var a = 0; a < appstreamValue.length; a++) appendCandidate(out, seen, appstreamValue[a]);
    }

    // 7. Sender window class / app id from the in-flight origin record. When
    //    the sender is a child of a terminal the terminal ancestor is tried
    //    before the child program (for example notify-send).
    var windowNames = windowIdentityCandidates(source, metadata);
    for (var w = 0; w < windowNames.length; w++) {
        var windowName = cleanField(windowNames[w].value, MAX_FIELD);
        appendCandidate(out, seen, themeCandidate(windowName, "window", windowNames[w].origin));
        appendCandidate(out, seen, themeCandidate(windowName.toLowerCase(), "window", windowNames[w].origin));
        var heuristicNames = heuristicIconNames(windowName);
        for (var h = 0; h < heuristicNames.length; h++) {
            appendCandidate(out, seen, themeCandidate(heuristicNames[h], "window", "window-class-heuristic"));
        }
    }

    // 8. /proc exe/comm basename as a last resort.
    var procNames = [metadata.procExe, metadata.procComm];
    for (var n = 0; n < procNames.length; n++) {
        var procName = normalizeExeName(procNames[n]);
        if (procName === "") continue;
        appendCandidate(out, seen, themeCandidate(procName, "proc", n === 0 ? "proc-exe" : "proc-comm"));
        appendCandidate(out, seen, themeCandidate(procName.toLowerCase(), "proc", n === 0 ? "proc-exe" : "proc-comm"));
    }

    // 9. Honest default. Always present, always visible.
    appendCandidate(out, seen, defaultCandidate());

    return out;
}

// Theme-name ids owned by the desktop-entry step. Only the desktop entry (and
// an explicit origin desktop entry) participate here; window-class/app-id
// identities are resolved later by the window step so the chain order is not
// collapsed. The last dot segment of a reverse-DNS/Flatpak id is included.
function desktopThemeIds(input) {
    input = input || {};
    var origin = input.origin || {};
    var out = [];
    var seeds = [
        cleanField(input.desktopEntry, MAX_ID),
        stripDesktopSuffix(cleanField(origin.desktopEntry, MAX_ID))
    ];
    for (var i = 0; i < seeds.length; i++) {
        var seed = seeds[i];
        if (seed === "") continue;
        var variants = reverseDnsVariants(seed);
        for (var j = 0; j < variants.length; j++) pushUnique(out, variants[j]);
    }
    return out.slice(0, 8);
}

// Ordered ids to search under <data>/applications. Only the desktop-entry
// identity and the application name seed this lookup: window class / app id
// belong to the later window step so the chain order is not collapsed. The
// reverse-DNS/Flatpak fallback ids are still included for a vendor-prefixed
// desktop entry.
function desktopSearchIds(input, meta) {
    input = input || {};
    meta = meta || {};
    var origin = input.origin || {};
    var out = [];
    var seeds = [
        cleanField(input.desktopEntry, MAX_ID),
        stripDesktopSuffix(cleanField(origin.desktopEntry, MAX_ID))
    ];
    for (var i = 0; i < seeds.length; i++) {
        var seed = seeds[i];
        if (seed === "") continue;
        var variants = reverseDnsVariants(seed);
        var plain = desktopIdVariants(seed);
        for (var j = 0; j < plain.length; j++) pushUnique(out, plain[j]);
        for (var k = 0; k < variants.length; k++) pushUnique(out, variants[k]);
    }
    var appName = cleanField(input.appName, MAX_FIELD);
    if (appName !== "") {
        var compact = appName.replace(/\s+/g, "").toLowerCase();
        pushUnique(out, compact);
    }
    return out.slice(0, 16);
}

// Window identity candidate order. A terminal ancestor, when present, is
// preferred over the child program so a shell notification is attributed to
// the terminal rather than to notify-send.
function windowIdentityCandidates(input, meta) {
    input = input || {};
    meta = meta || {};
    var origin = input.origin || {};
    var out = [];
    var terminal = origin.terminal === true || origin.terminalAncestor !== undefined && origin.terminalAncestor !== null;
    if (terminal) {
        var ancestor = origin.terminalAncestor || {};
        pushWindowSeed(out, firstNonEmpty(ancestor.appId, origin.terminalAppId), "window-terminal-app-id");
        pushWindowSeed(out, firstNonEmpty(ancestor.className, ancestor.class, origin.terminalClass), "window-terminal-class");
    }
    pushWindowSeed(out, firstNonEmpty(origin.desktopEntry), "window-desktop-entry");
    pushWindowSeed(out, firstNonEmpty(origin.appId), "window-app-id");
    pushWindowSeed(out, firstNonEmpty(origin.className, origin.class), "window-class");
    pushWindowSeed(out, firstNonEmpty(origin.initialClass), "window-initial-class");
    pushWindowSeed(out, cleanField(meta.startupWMClass, MAX_FIELD), "window-startup-wm-class");
    pushWindowSeed(out, firstNonEmpty(input.desktopEntry), "window-desktop-entry");
    return out;
}

function pushWindowSeed(out, value, origin) {
    var clean = cleanField(value, MAX_FIELD);
    if (clean === "" || clean.indexOf("/") !== -1) return;
    pushUnique(out, { value: clean, origin: origin });
}

// ---------------------------------------------------------------------------
// Probing and finalisation
// ---------------------------------------------------------------------------

// Evaluate the ordered candidate list against host probes. The probe contract:
//   fileUsable(path)   -> true when the file exists and is non-empty
//   themeUsable(name)  -> true when the theme provides the name
//   themeSource(name)  -> renderable source for a usable theme name
//   inlineUsable(src)  -> true when the inline source can be displayed
function resolveCandidates(candidates, probe) {
    var list = candidates || [];
    for (var i = 0; i < list.length; i++) {
        var candidate = list[i];
        if (candidate.kind === "default") return noIcon(candidate, probe);
        if (candidate.probeType === "file" && probe.fileUsable(candidate.path)) {
            return finalize(candidate, probe);
        }
        if (candidate.probeType === "theme" && probe.themeUsable(candidate.name)) {
            return finalize(candidate, probe);
        }
        if (candidate.probeType === "inline" && probe.inlineUsable(candidate.source)) {
            return finalize(candidate, probe);
        }
    }
    return noIcon(defaultCandidate(), probe);
}

// The deliberate, logged no-icon outcome. The candidate is finalized without
// probing because the no-icon state carries no source or name by construction.
function noIcon(candidate, probe) {
    logDiagnostic(DIAGNOSTIC_NO_ICON_RESOLVED);
    return finalize(candidate, probe);
}

function finalize(candidate, probe) {
    var result = {
        source: text(candidate.source),
        name: text(candidate.name),
        symbolic: false,
        kind: text(candidate.kind) || "default",
        origin: text(candidate.origin)
    };
    if (candidate.probeType === "theme") {
        result.symbolic = isSymbolicName(candidate.name);
        result.source = text(probe.themeSource(candidate.name));
    } else if (candidate.probeType === "file") {
        // File-URL construction is owned by SourceUrl in the QML layer; the
        // pure policy only decides which path wins.
        result.source = text(probe.fileSource(candidate.path));
    } else if (candidate.probeType === "inline" && result.source.charAt(0) === "/") {
        result.source = text(probe.fileSource(result.source));
    }
    return result;
}

// Convenience: build the ordered candidates and evaluate them in one call.
// Node tests and the QML companion both use this entry point so there is a
// single reference implementation.
function resolve(input, meta, probe) {
    return resolveCandidates(buildCandidates(input, meta), probe);
}

var AppIconResolverLogic = {
    DEFAULT_ICON: DEFAULT_ICON,
    DIAGNOSTIC_NO_ICON_RESOLVED: DIAGNOSTIC_NO_ICON_RESOLVED,
    MAX_THEME_NAME: MAX_THEME_NAME,
    MAX_PATH: MAX_PATH,
    SUBSTRING_MATCH_MIN_LENGTH: SUBSTRING_MATCH_MIN_LENGTH,
    cleanField: cleanField,
    isValidThemeName: isValidThemeName,
    queryStripped: queryStripped,
    themeLookupName: themeLookupName,
    isSymbolicName: isSymbolicName,
    stripDesktopSuffix: stripDesktopSuffix,
    desktopIdVariants: desktopIdVariants,
    reverseDnsVariants: reverseDnsVariants,
    classVariants: classVariants,
    heuristicIconNames: heuristicIconNames,
    normalizeExeName: normalizeExeName,
    pathFromFileUrl: pathFromFileUrl,
    localImageFile: localImageFile,
    isInlineImageUrl: isInlineImageUrl,
    isFileValue: isFileValue,
    themeNameFromImageUrl: themeNameFromImageUrl,
    desktopSearchIds: desktopSearchIds,
    desktopThemeIds: desktopThemeIds,
    windowIdentityCandidates: windowIdentityCandidates,
    buildCandidates: buildCandidates,
    resolveCandidates: resolveCandidates,
    resolve: resolve
};

if (typeof module !== "undefined" && module.exports) module.exports = AppIconResolverLogic;
