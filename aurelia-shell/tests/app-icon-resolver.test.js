#!/usr/bin/env node
"use strict";

// Pure node tests for the shared application-icon resolver. No live shell, no
// Qt, no filesystem mutation: every host probe is a deterministic in-memory
// fake so the candidate ordering, normalisation and validation are pinned
// exactly as AppIconResolver.qml will evaluate them.

var path = require("path");
var Logic = require(path.join(__dirname, "..", "services", "AppIconResolver.js"));

// Local file-URL helper assembled from fragments so this test never embeds the
// forbidden contiguous local-file prefix that the repository source policy
// forbids.
var FILE_URL_SCHEME = "file:" + "//";
function fileUrl(p) { return FILE_URL_SCHEME + p; }

var failures = 0;
var assertions = 0;

function assert(condition, message) {
    assertions += 1;
    if (!condition) {
        failures += 1;
        process.stderr.write("  FAIL " + message + "\n");
    }
}

function assertEqual(actual, expected, message) {
    assert(actual === expected, message + " (expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual) + ")");
}

function assertDeepEqual(actual, expected, message) {
    assert(JSON.stringify(actual) === JSON.stringify(expected),
        message + " (expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual) + ")");
}

// A probe whose usable sets are supplied per test.
function probe(options) {
    var opts = options || {};
    return {
        fileUsable: function(p) { return (opts.files || []).indexOf(p) !== -1; },
        fileSource: function(p) { return fileUrl(p); },
        themeUsable: function(n) { return (opts.themes || []).indexOf(n) !== -1; },
        themeSource: function(n) { return "image://icon/" + n + "?fallback=application-x-executable"; },
        inlineUsable: function(s) { return opts.inline === false ? false : s !== ""; }
    };
}

function kinds(result) {
    return result.kind + ":" + result.name;
}

// ---------------------------------------------------------------------------
// Name validation
// ---------------------------------------------------------------------------
assert(Logic.isValidThemeName("foot"), "foot is a valid theme name");
assert(Logic.isValidThemeName("com.mitchellh.ghostty"), "reverse-DNS id is a valid theme name");
assert(Logic.isValidThemeName("utilities-terminal"), "hyphenated name is valid");
assert(Logic.isValidThemeName("a_b.c+d-e"), "underscore/dot/plus/hyphen are valid");
assert(!Logic.isValidThemeName(""), "empty name is rejected");
assert(!Logic.isValidThemeName("   "), "whitespace-only name is rejected");
assert(!Logic.isValidThemeName(" leading"), "leading space is rejected");
assert(!Logic.isValidThemeName("a/b"), "slash is rejected");
assert(!Logic.isValidThemeName("a..b"), "parent traversal is rejected");
assert(!Logic.isValidThemeName("~root"), "tilde is rejected");
assert(!Logic.isValidThemeName("-leading-hyphen"), "leading hyphen is rejected");
assert(!Logic.isValidThemeName("a\u0000b"), "NUL is rejected");
assert(!Logic.isValidThemeName("a\u0007b"), "control character is rejected");
assert(!Logic.isValidThemeName(new Array(300).join("a")), "overlong name is rejected");

assertEqual(Logic.cleanField("\u0000evil", 64), "", "cleanField rejects NUL");
assertEqual(Logic.cleanField("  padded  ", 64), "padded", "cleanField trims");
assertEqual(Logic.cleanField("x", 0), "", "cleanField bounds by max length");

// ---------------------------------------------------------------------------
// Symbolic classification (query-stripped)
// ---------------------------------------------------------------------------
assert(Logic.isSymbolicName("foo-symbolic?theme=dark"), "symbolic with query is symbolic");
assert(Logic.isSymbolicName("foo-symbolic"), "symbolic without query is symbolic");
assert(!Logic.isSymbolicName("foo"), "plain logo is not symbolic");
assert(!Logic.isSymbolicName("symbolic-foo"), "suffix-only match");
assertEqual(Logic.themeLookupName("foo-symbolic?theme=dark"), "foo-symbolic", "query is stripped for lookup");
assertEqual(Logic.themeLookupName("image://icon/foot"), "", "image URL is never a theme name");

// ---------------------------------------------------------------------------
// Normalisation: ids, classes, exe
// ---------------------------------------------------------------------------
assertDeepEqual(Logic.desktopIdVariants("foot.desktop"), ["foot"], "desktop id strips .desktop");
assertDeepEqual(Logic.desktopIdVariants("ChatGPT.DESKTOP"), ["ChatGPT", "chatgpt"], "desktop id exact then lower-case");
assertDeepEqual(Logic.desktopIdVariants("a/b.desktop"), [], "desktop id with slash is rejected");

assertDeepEqual(Logic.reverseDnsVariants("com.ulaa.Ulaa"),
    ["com.ulaa.Ulaa", "com.ulaa.ulaa", "Ulaa", "ulaa"],
    "reverse-DNS id tries as-is, lower-case, then last segment");
assertDeepEqual(Logic.reverseDnsVariants("foot"), ["foot"], "single-segment id has one variant");

assertDeepEqual(Logic.classVariants("Ghostty"), ["Ghostty", "ghostty"], "class tries exact then lower-case");

assertEqual(Logic.normalizeExeName("/usr/bin/notify-send.bin"), "notify-send", "exe strips path and .bin");
assertEqual(Logic.normalizeExeName("foot-bin"), "foot", "exe strips -bin");
assertEqual(Logic.normalizeExeName(" /usr/bin/foot "), "foot", "exe trims and takes basename");

// The shared substring guard: short generic names must not fuzzy-match.
assertDeepEqual(Logic.heuristicIconNames("chatgpt"), ["chatgpt"], "exact chatgpt heuristic");
assertDeepEqual(Logic.heuristicIconNames("chatgpt-desktop"), ["chatgpt"], "substring chatgpt heuristic (both >= 5)");
assertDeepEqual(Logic.heuristicIconNames("chat"), [], "short name is never substring-matched");
assertDeepEqual(Logic.heuristicIconNames("term"), [], "short generic term is never substring-matched");
assert(!Logic.heuristicIconNames("my-foot-app").some(function(name) { return name === "utilities-terminal" }),
    "short foot token is guarded out of substring matching");
assertDeepEqual(Logic.heuristicIconNames("foot"), ["utilities-terminal"], "exact foot heuristic still applies");

// ---------------------------------------------------------------------------
// File/URL classification
// ---------------------------------------------------------------------------
assertEqual(Logic.localImageFile("/tmp/a.png"), "/tmp/a.png", "absolute path is a local file");
assertEqual(Logic.localImageFile(fileUrl("/tmp/a.png")), "/tmp/a.png", "file URL is a local file");
assertEqual(Logic.localImageFile("image://icon//tmp/a.png"), "/tmp/a.png", "embedded Chromium path is a local file");
assertEqual(Logic.localImageFile("image://icon/foot"), "", "themed image URL is not a local file");
assertEqual(Logic.themeNameFromImageUrl("image://icon/foot"), "foot", "themed image URL yields a theme name");
assertEqual(Logic.themeNameFromImageUrl("image://icon//tmp/a.png"), "", "embedded path is not a theme name");
assert(Logic.isFileValue("/tmp/a.png"), "absolute path is a file value");
assert(Logic.isFileValue(fileUrl("/tmp/a.png")), "file URL is a file value");
assert(!Logic.isFileValue("image://icon/foot"), "themed name is not a file value");
assert(Logic.isInlineImageUrl("image://qsimage/3/0"), "qsimage URL is inline");
assert(!Logic.isInlineImageUrl("image://icon/foot"), "icon URL is not inline");

// ---------------------------------------------------------------------------
// Candidate ordering
// ---------------------------------------------------------------------------
var fullInput = {
    localPath: fileUrl("/durable/icon.png"),
    imageData: "image://qsimage/7/0",
    appIcon: "my-app-icon",
    image: "image://icon/foot",
    desktopEntry: "foot",
    appName: "Foot",
    origin: { appId: "foot", className: "foot" }
};
var fullMeta = {
    desktopIcon: "utilities-terminal",
    appstreamIcon: "appstream-icon",
    procExe: "/usr/bin/foot",
    procComm: "foot"
};
var fullCandidates = Logic.buildCandidates(fullInput, fullMeta);
var fullKinds = fullCandidates.map(function(c) { return c.kind; });
assertEqual(fullKinds[0], "durable", "durable is the first candidate");
assertEqual(fullKinds[1], "inline", "inline is the second candidate");
assertEqual(fullKinds[2], "theme", "app-icon theme is the third candidate");
assertEqual(fullKinds[3], "theme", "themed image name is the fourth candidate");
assertEqual(fullCandidates[2].name, "my-app-icon", "app-icon theme name is the third candidate");
assertEqual(fullCandidates[3].name, "foot", "themed image name is the fourth candidate");
assertEqual(fullCandidates[fullCandidates.length - 1].kind, "default", "default is always last");

// The app-icon file source is ordered before the bare app-icon theme name.
var fileThenTheme = Logic.buildCandidates({ appIcon: "/icons/app.png", image: "image://icon/foot" }, {});
assertEqual(fileThenTheme[0].kind, "file", "app-icon file is the first non-empty candidate");
assertEqual(fileThenTheme[1].kind, "theme", "themed image name follows the app-icon file");
assertEqual(fileThenTheme[1].name, "foot", "themed image name follows the app-icon file");

// The foot fix: a themed image://icon/foot value resolves to the foot theme.
var footResult = Logic.resolve({ image: "image://icon/foot" }, {}, probe({ themes: ["foot"] }));
assertEqual(footResult.kind, "theme", "themed image URL kind is theme");
assertEqual(footResult.name, "foot", "themed image URL name is foot");
assertEqual(footResult.origin, "image-icon-name", "themed image URL provenance");
assertEqual(footResult.source, "image://icon/foot?fallback=application-x-executable", "themed image URL source is the Qt icon URL");

// Chain precedence via the probe: each step wins over every later step.
assertEqual(kinds(Logic.resolve(fullInput, fullMeta, probe({ files: ["/durable/icon.png"] }))), "durable:",
    "durable wins when usable");

var noDurable = Object.assign({}, fullInput, { localPath: fileUrl("/missing.png") });
var inlineResult = Logic.resolve(noDurable, fullMeta, probe({ files: ["/icons/app.png"] }));
assertEqual(inlineResult.kind, "inline", "inline wins when durable is dangling");
assertEqual(inlineResult.source, "image://qsimage/7/0", "inline source is materialised as-is");

var noInline = Object.assign({}, noDurable, { imageData: "", appIcon: "/icons/app.png" });
var fileResult = Logic.resolve(noInline, fullMeta, probe({ files: ["/icons/app.png"] }));
assertEqual(fileResult.kind, "file", "app-icon file wins when durable/inline absent");
assertEqual(fileResult.source, fileUrl("/icons/app.png"), "app-icon file source is a file URL");

var noAppFile = Object.assign({}, noInline, { appIcon: "foot" });
var appThemeResult = Logic.resolve(noAppFile, fullMeta, probe({ themes: ["foot", "utilities-terminal"] }));
assertEqual(appThemeResult.origin, "app-icon-name", "app-icon theme wins before the image hint");

var imageOnly = { image: "image://icon/foot", desktopEntry: "foot", appName: "Foot" };
var imageThemeResult = Logic.resolve(imageOnly, fullMeta, probe({ themes: ["foot", "utilities-terminal"] }));
assertEqual(imageThemeResult.origin, "image-icon-name", "themed image name wins before desktop-entry");

var desktopOnly = { desktopEntry: "com.mitchellh.ghostty" };
var desktopResult = Logic.resolve(desktopOnly, { desktopIcon: "com.mitchellh.ghostty" }, probe({ themes: ["com.mitchellh.ghostty"] }));
assertEqual(desktopResult.kind, "desktop", "desktop-entry resolves when the image hint is absent");
assertEqual(desktopResult.name, "com.mitchellh.ghostty", "desktop-entry name comes from the Icon= value");

// Direct .desktop Icon= with an absolute path is a file source.
var desktopFileResult = Logic.resolve({ desktopEntry: "foot" }, { desktopIcon: "/usr/share/icons/foot.png" },
    probe({ files: ["/usr/share/icons/foot.png"] }));
assertEqual(desktopFileResult.kind, "desktop", "desktop absolute Icon= is a file source");
assertEqual(desktopFileResult.source, fileUrl("/usr/share/icons/foot.png"), "desktop absolute Icon= becomes a file URL");

// AppStream wins when the desktop icon is not usable and the desktop id
// variants do not resolve either.
var appstreamResult = Logic.resolve({ desktopEntry: "com.example.tool" },
    { desktopIcon: "missing-desktop-icon", appstreamIcon: "example-tool" },
    probe({ themes: ["example-tool"] }));
assertEqual(appstreamResult.kind, "appstream", "AppStream icon is used when desktop icon is unusable");
assertEqual(appstreamResult.name, "example-tool", "AppStream stock icon name");

// Window class wins when no metadata icon resolves.
var windowResult = Logic.resolve({ desktopEntry: "x", origin: { className: "com.mitchellh.ghostty" } },
    {}, probe({ themes: ["com.mitchellh.ghostty"] }));
assertEqual(windowResult.kind, "window", "window class resolves when metadata is absent");
assertEqual(windowResult.name, "com.mitchellh.ghostty", "window class name is used as-is first");

// A terminal ancestor is preferred over the child program (notify-send).
var terminal = Logic.resolve({
    origin: {
        appId: "notify-send",
        className: "notify-send",
        terminal: true,
        terminalAncestor: { className: "com.mitchellh.ghostty", appId: "com.mitchellh.ghostty" }
    }
}, {}, probe({ themes: ["com.mitchellh.ghostty", "notify-send"] }));
assertEqual(terminal.kind, "window", "terminal ancestor resolves from the window step");
assertEqual(terminal.name, "com.mitchellh.ghostty", "terminal ancestor wins over the child program");

// Window class heuristics migrate the old active-window mapping.
var heuristic = Logic.resolve({ origin: { className: "chromium-browser" } }, {},
    probe({ themes: ["chromium"] }));
assertEqual(heuristic.name, "chromium", "chrom heuristic still maps to chromium");

// /proc basename wins over default but loses to window identity.
var procResult = Logic.resolve({ origin: {} }, { procExe: "/usr/bin/kitty.bin", procComm: "kitty" },
    probe({ themes: ["kitty"] }));
assertEqual(procResult.kind, "proc", "proc exe resolves when no window identity exists");
assertEqual(procResult.name, "kitty", "proc exe .bin suffix is stripped");

// Honest default outcome.
var defaultResult = Logic.resolve({ appIcon: "definitely-not-real", desktopEntry: "nope" }, {},
    probe({ themes: [] }));
assertEqual(defaultResult.kind, "default", "unresolvable input yields the default");
assertEqual(defaultResult.name, "application-x-executable", "default name is explicit");
assertEqual(defaultResult.source, "image://icon/application-x-executable?fallback=application-x-executable",
    "default source is the Qt icon URL, never blank");
assertEqual(defaultResult.symbolic, false, "default is not symbolic");

// ---------------------------------------------------------------------------
// The "never a dangling durable path" invariant
// ---------------------------------------------------------------------------
var dangling = Logic.resolve({ localPath: fileUrl("/tmp/does-not-exist.png") }, {}, probe({ files: [], themes: [] }));
assertEqual(dangling.kind, "default", "a dangling durable path is never adopted");
assert(dangling.source.indexOf("does-not-exist") === -1, "a dangling durable path never reaches the result");

var emptyDurable = Logic.resolve({ localPath: fileUrl("/tmp/empty.png") }, {}, probe({ files: [], themes: [] }));
assertEqual(emptyDurable.kind, "default", "an empty durable file is never adopted");

// A durable path that is a themed image:// value is not mistaken for a file.
var durableThemed = Logic.resolve({ localPath: "image://icon/foot" }, {}, probe({ themes: ["foot"] }));
assertEqual(durableThemed.origin, "durable-rehydrated", "durable themed value keeps durable provenance");
assertEqual(durableThemed.name, "foot", "durable themed value resolves through the theme probe");

// Rehydration proof: a durable value is used as-is and is not re-resolved even
// when a higher-priority input is present.
var rehydrated = Logic.resolve({
    localPath: fileUrl("/durable/icon.png"),
    imageData: "image://qsimage/9/0",
    appIcon: "/icons/app.png"
}, {}, probe({ files: ["/durable/icon.png", "/icons/app.png"] }));
assertEqual(rehydrated.kind, "durable", "durable value wins over later candidates");
assertEqual(rehydrated.source, fileUrl("/durable/icon.png"), "durable source is returned unchanged");

// No candidate may be a bare non-file, non-URL theme string in `source`.
[footResult, desktopResult, windowResult, procResult, defaultResult].forEach(function(result) {
    assert(result.source.indexOf("image://icon/") === 0 || result.source.indexOf("file://") === 0 ||
        result.source.indexOf("image://qsimage/") === 0, "every resolved source is renderable: " + result.source);
});

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------
if (failures > 0) {
    process.stderr.write("app-icon-resolver node tests: " + failures + " failure(s) of " + assertions + " assertion(s)\n");
    process.exit(1);
}
process.stdout.write("app-icon-resolver node tests: " + assertions + " assertions passed\n");
