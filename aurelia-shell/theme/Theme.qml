pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: themeRoot

    // Aurelia Design System Foundation
    // Self-contained design token system for Aurelia desktop shell components.
    // Invariant: Completely independent of external desktop environments (Noctalia).
    // Defaults to Rosé Pine Moon palette natively, with optional user configuration adapter.

    // 1. Optional Theme Configuration File (Aurelia native or external adapter)
    readonly property string themePath: {
        var envPath = Quickshell.env("AURELIA_THEME_CONF") || ""
        if (envPath !== "") return envPath
        var home = Quickshell.env("HOME") || ""
        if (home === "") return ""
        // Native Aurelia design system theme configuration
        return home + "/.config/aurelia/theme.conf"
    }

    readonly property string shippedThemePath: String(Qt.resolvedUrl("../theme.conf")).replace(/^file:\/\//, "")
    property bool themeOverrideAvailable: false
    readonly property string stateHomeOverride: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string stateHome: stateHomeOverride.charAt(0) === "/"
        ? stateHomeOverride
        : (Quickshell.env("HOME") || "") + "/.local/state"
    readonly property string activeThemePath: stateHome + "/aurelia/current/theme.conf"
    property bool activeThemeAvailable: false
    property int _themeReloadToken: 0
    readonly property string activeShellPath: stateHome + "/aurelia/current/shell.toml"
    readonly property string shippedShellPath: String(Qt.resolvedUrl("shell.toml")).replace(/^file:\/\//, "")
    property bool activeShellAvailable: false
    property int _shellReloadToken: 0

    property Process themeOverrideProbe: Process {
        command: themeRoot.themePath !== "" ? ["/usr/bin/test", "-f", themeRoot.themePath] : ["/usr/bin/false"]
        running: true
        onExited: function(code) {
            themeRoot.themeOverrideAvailable = code === 0
            console.info("[THEME] override_probe code=" + code + " path=" + themeRoot.themePath)
            themeRoot._themeReloadToken++
        }
    }

    property Process activeThemeProbe: Process {
        command: ["/usr/bin/test", "-f", themeRoot.activeThemePath]
        running: true
        onExited: function(code) {
            themeRoot.activeThemeAvailable = code === 0
            console.info("[THEME] active_probe code=" + code + " path=" + themeRoot.activeThemePath)
            themeRoot._themeReloadToken++
        }
    }

    property Process activeShellProbe: Process {
        command: ["/usr/bin/test", "-f", themeRoot.activeShellPath]
        running: true
        onExited: function(code) {
            themeRoot.activeShellAvailable = code === 0
            themeRoot._shellReloadToken++
        }
    }

    readonly property string effectiveThemePath: {
        // Reading the Process state here is deliberate: Process-valued
        // properties on a singleton are lazy, so the path binding must anchor
        // both initial existence probes before choosing the palette file.
        var probeState = themeOverrideProbe.running + ":" + activeThemeProbe.running
        return themeOverrideAvailable
            ? themePath
            : (activeThemeAvailable ? activeThemePath : shippedThemePath)
    }

    readonly property string effectiveShellPath: {
        var probeState = activeShellProbe.running
        // A pre-token-generation installation may already have an active
        // theme.conf but no shell.toml. Point the parser at that flat palette
        // file so it yields no section overrides and the semantic tokens fall
        // back to the active palette, rather than accidentally using the
        // shipped Rosé Pine shell surface values.
        return activeShellAvailable
            ? activeShellPath
            : (activeThemeAvailable ? activeThemePath : shippedShellPath)
    }

    property FileView themeFile: FileView {
        path: themeRoot.effectiveThemePath
        watchChanges: true
        onLoaded: {
            themeRoot._themeReloadToken++
            console.info("[THEME] loaded path=" + themeRoot.effectiveThemePath)
        }
        onFileChanged: {
            reload()
            themeRoot._themeReloadToken++
        }
    }

    property FileView shellFile: FileView {
        path: themeRoot.effectiveShellPath
        watchChanges: true
        onLoaded: themeRoot._shellReloadToken++
        onFileChanged: {
            reload()
            themeRoot._shellReloadToken++
        }
    }

    function reloadTheme() {
        themeRoot.themeOverrideAvailable = false
        themeRoot.activeThemeAvailable = false
        themeRoot.activeShellAvailable = false
        themeOverrideProbe.running = false
        activeThemeProbe.running = false
        activeShellProbe.running = false
        themeOverrideProbe.running = true
        activeThemeProbe.running = true
        activeShellProbe.running = true
        // Atomic replacement of the state file can leave a FileView watching
        // the old inode, and the probe assignments above may be coalesced by
        // QML when the effective path does not change. Explicitly re-read the
        // current path so a successful IPC reload always consumes fresh data.
        themeRoot.themeFile.reload()
        themeRoot.shellFile.reload()
        Qt.callLater(function() {
            themeRoot.themeFile.reload()
            themeRoot.shellFile.reload()
            themeRoot._themeReloadToken++
            themeRoot._shellReloadToken++
        })
        themeRoot._themeReloadToken++
        themeRoot._shellReloadToken++
    }

    Component.onCompleted: {
        // Process-valued properties are lazy in a QtObject singleton. Start
        // both probes explicitly so a fresh shell resolves active user state
        // instead of remaining on the shipped palette until an IPC reload.
        themeRoot.themeOverrideProbe.running = true
        themeRoot.activeThemeProbe.running = true
        themeRoot.activeShellProbe.running = true
    }

    // 1b. Aurelia User Preferences File (XDG layered configuration)
    readonly property string preferencesPath: {
        var envPath = Quickshell.env("AURELIA_PREFERENCES_PATH") || ""
        if (envPath !== "") return envPath
        var configHome = Quickshell.env("XDG_CONFIG_HOME") || ""
        if (configHome === "") {
            var home = Quickshell.env("HOME") || ""
            configHome = home + "/.config"
        }
        return configHome + "/aurelia/preferences.json"
    }

    readonly property string shippedPreferencesPath: String(Qt.resolvedUrl("../config/preferences.defaults.json")).replace(/^file:\/\//, "")
    property bool preferencesOverrideAvailable: false

    property Process preferencesOverrideProbe: Process {
        command: themeRoot.preferencesPath !== "" ? ["/usr/bin/test", "-f", themeRoot.preferencesPath] : ["/usr/bin/false"]
        running: true
        onExited: function(code) {
            themeRoot.preferencesOverrideAvailable = code === 0
        }
    }

    property int _prefReloadToken: 0
    function reloadPreferences() {
        themeRoot.preferencesOverrideAvailable = false
        preferencesOverrideProbe.running = false
        preferencesOverrideProbe.running = true
        _prefReloadToken++
    }

    property FileView preferencesFile: FileView {
        path: themeRoot.preferencesOverrideAvailable ? themeRoot.preferencesPath : themeRoot.shippedPreferencesPath
    }

    // Display text-size overrides are user-owned and intentionally separate
    // from the project-owned theme.conf. The Display plugin writes this small
    // file atomically; the singleton watches it so the shell reflows without
    // restarting the resident Quickshell process.
    readonly property string displaySettingsPath: {
        var envPath = Quickshell.env("AURELIA_DISPLAY_SETTINGS_PATH") || ""
        if (envPath.charAt(0) === "/") return envPath
        var configHome = Quickshell.env("XDG_CONFIG_HOME") || ""
        if (configHome.charAt(0) !== "/") configHome = (Quickshell.env("HOME") || "") + "/.config"
        return configHome + "/aurelia/display.conf"
    }
    property bool displaySettingsAvailable: false
    property int _displaySettingsReloadToken: 0
    property Process displaySettingsProbe: Process {
        command: ["/usr/bin/test", "-f", themeRoot.displaySettingsPath]
        running: true
        onExited: function(code) {
            themeRoot.displaySettingsAvailable = code === 0
            themeRoot._displaySettingsReloadToken++
        }
    }
    property FileView displaySettingsFile: FileView {
        path: themeRoot.displaySettingsAvailable
            ? themeRoot.displaySettingsPath
            : themeRoot.shippedThemePath
        watchChanges: themeRoot.displaySettingsAvailable
        onFileChanged: {
            reload()
            themeRoot._displaySettingsReloadToken++
        }
    }

    function reloadDisplaySettings() {
        displaySettingsAvailable = false
        displaySettingsProbe.running = false
        displaySettingsProbe.running = true
        _displaySettingsReloadToken++
    }

    readonly property int fontBaseSize: {
        var reloadToken = _displaySettingsReloadToken
        var value = 12
        var text = ""
        try { text = displaySettingsFile.text() } catch (e) { text = "" }
        var match = text.match(/^\s*fontBaseSize\s*=\s*([0-9]+)\s*$/m)
        if (match && Number(match[1]) >= 9 && Number(match[1]) <= 20)
            value = Number(match[1])
        return value
    }

    readonly property real fontScale: fontBaseSize / 12.0

    // Omarchy keeps bar geometry in a separate structural namespace. The
    // scale is independent of the palette and lets a larger shell font grow
    // the bar and its fixed slots together instead of clipping text/icons.
    function _getBool(key, defaultValue) {
        var value = _getOverride(key).toLowerCase()
        if (value === "true" || value === "1" || value === "yes" || value === "on") return true
        if (value === "false" || value === "0" || value === "no" || value === "off") return false
        return defaultValue
    }

    readonly property bool barScaleWithFont: _getBool("barScaleWithFont", true)
    readonly property real barScale: barScaleWithFont ? Math.max(1 / 12, fontScale) : 1.0

    function scaleGeometry(value) {
        var n = Number(value)
        if (!isFinite(n) || n <= 0) return 1
        return Math.max(1, Math.round(n * barScale))
    }

    function _getScaledInt(key, defaultValue) {
        var override = _getOverride(key)
        var base = Number(defaultValue)
        if (override !== "") {
            var parsed = parseInt(override, 10)
            if (!isNaN(parsed)) base = parsed
        }
        return Math.max(1, Math.round(base * barScale))
    }

    function _getScaledReal(key, defaultValue) {
        var override = _getOverride(key)
        var base = Number(defaultValue)
        if (override !== "") {
            var parsed = parseFloat(override)
            if (!isNaN(parsed)) base = parsed
        }
        return Math.max(0, base * barScale)
    }

    readonly property QtObject bar: QtObject {
        readonly property bool scaleWithFont: themeRoot.barScaleWithFont
        readonly property color background: themeRoot._withAlpha(
            themeRoot._getShellColor("bar.background", themeRoot.bgBase),
            themeRoot._getShellAlpha("bar.background-alpha", 1.0))
        readonly property color foreground: themeRoot._getShellColor("bar.text", themeRoot.text)
        readonly property color active: themeRoot._getShellColor("bar.active", themeRoot.accent)
        readonly property color border: themeRoot._getShellColor("bar.border", themeRoot.border)
        readonly property int sizeHorizontal: themeRoot._getScaledInt("barSizeHorizontal", 26)
        readonly property int sizeVertical: themeRoot._getScaledInt("barSizeVertical", 28)
        readonly property int iconSlot: themeRoot._getScaledInt("barIconSlot", 27)
        readonly property int iconCanvas: themeRoot._getScaledInt("barIconCanvas", 16)
        readonly property int iconFont: themeRoot._getScaledInt("barIconFont", 13)
        readonly property int statusSlot: themeRoot._getScaledInt("barStatusSlot", 21)
        readonly property int outerMargin: themeRoot._getScaledInt("barOuterMargin", 8)
        readonly property int trayIcon: themeRoot._getScaledInt("barTrayIcon", 12)
        readonly property int workspaceWidth: themeRoot._getScaledInt("barWorkspaceWidth", 20)
        readonly property real textMargin: themeRoot._getScaledReal("barTextMargin", 8.75)
        readonly property int text: themeRoot._getScaledInt("barTextSize", 12)
        readonly property int caption: themeRoot._getScaledInt("barCaptionSize", 10)
    }

    readonly property var loadedPreferences: {
        var _ = _prefReloadToken
        var txt = ""
        try {
            txt = preferencesFile.text()
        } catch (e) {
            return {}
        }
        if (!txt || typeof txt !== "string" || txt.trim() === "") return {}
        try {
            var parsed = JSON.parse(txt)
            return (parsed && typeof parsed === "object") ? parsed : {}
        } catch (err) {
            console.warn("[WARN] Theme.qml: Failed to parse preferences.json; using shipped defaults")
            return {}
        }
    }

    function getPreference(key: string, fallback: var): var {
        var parts = key.split(".")
        var curr = loadedPreferences
        for (var i = 0; i < parts.length; i++) {
            if (curr && typeof curr === "object" && curr[parts[i]] !== undefined) {
                curr = curr[parts[i]]
            } else {
                return fallback
            }
        }
        return (curr !== undefined && curr !== null) ? curr : fallback
    }

    // Keybindings Component UI Control Shortcuts (configurable via preferences.json)
    readonly property string shortcutAddAction: getPreference("components.keybindings.shortcuts.add_action", "ALT + A")
    readonly property string shortcutBack: getPreference("components.keybindings.shortcuts.back", "ALT + B")
    readonly property string shortcutSet: getPreference("components.keybindings.shortcuts.set_binding", "ALT + S")
    readonly property string shortcutUnset: getPreference("components.keybindings.shortcuts.unset_binding", "ALT + U")

    readonly property var loadedOverrides: {
        var reloadToken = _themeReloadToken
        var map = {}
        var txt = ""
        try {
            txt = themeFile.text()
        } catch (e) {
            // Configuration file missing or unreadable; defaults apply safely
        }
        if (txt && typeof txt === "string") {
            var lines = txt.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (!line || line.startsWith("#") || line.startsWith("//")) continue
                var sepIdx = line.indexOf("=")
                if (sepIdx !== -1) {
                    var k = line.substring(0, sepIdx).trim()
                    var v = line.substring(sepIdx + 1).trim()
                    if (k && v) {
                        map[k] = v
                    }
                } else {
                    // Fallback for space-separated format (e.g. "background #232136")
                    var spaceIdx = line.indexOf(" ")
                    if (spaceIdx === -1) spaceIdx = line.indexOf("\t")
                    if (spaceIdx !== -1) {
                        var sk = line.substring(0, spaceIdx).trim()
                        var sv = line.substring(spaceIdx + 1).trim()
                        if (sk && sv) {
                            map[sk] = sv
                        }
                    }
                }
            }
        }
        return map
    }

    function _getOverride(key: string): string {
        if (loadedOverrides[key] === undefined || loadedOverrides[key] === null) return ""
        return String(loadedOverrides[key]).replace(/^["']|["']$/g, "")
    }

    function _getInt(key: string, defaultValue: int): int {
        var override = _getOverride(key)
        if (override !== "") {
            var v = parseInt(override, 10)
            if (!isNaN(v)) return v
        }
        return defaultValue
    }

    function _getString(key: string, defaultValue: string): string {
        var override = _getOverride(key)
        return override !== "" ? override : defaultValue
    }

    function _getColor(key: string, altKeys: var, fallbackColor: color): color {
        var override = _getOverride(key)
        if (override !== "") return override
        if (altKeys) {
            if (typeof altKeys === "string") {
                override = _getOverride(altKeys)
                if (override !== "") return override
            } else if (Array.isArray(altKeys)) {
                for (var i = 0; i < altKeys.length; i++) {
                    var k = altKeys[i]
                    override = _getOverride(k)
                    if (override !== "") return override
                }
            }
        }
        return fallbackColor
    }

    // Omarchy's generated shell.toml is a data-only surface-token document.
    // Parse only simple TOML sections and scalar values; unsupported syntax is
    // ignored and all QML consumers retain their safe fallback token.
    readonly property var loadedShellOverrides: {
        var reloadToken = _shellReloadToken
        var map = {}
        var text = ""
        try { text = shellFile.text() } catch (e) { text = "" }
        if (!text || typeof text !== "string") return map

        var section = ""
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].replace(/^\s+|\s+$/g, "")
            if (!line || line.charAt(0) === "#") continue
            var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]$/)
            if (sectionMatch) {
                section = sectionMatch[1]
                continue
            }
            var valueMatch = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(.*)$/)
            if (!valueMatch || !section) continue

            var value = valueMatch[2].replace(/^\s+|\s+$/g, "")
            if ((value.charAt(0) === '"' && value.charAt(value.length - 1) === '"') ||
                (value.charAt(0) === "'" && value.charAt(value.length - 1) === "'")) {
                value = value.substring(1, value.length - 1)
            }
            if (value.indexOf("\n") !== -1 || value.indexOf("\r") !== -1 || value.length > 256) continue
            map[section + "." + valueMatch[1]] = value
        }
        return map
    }

    function _getShell(key, fallback) {
        var value = loadedShellOverrides[key]
        return value === undefined || value === null || value === "" ? fallback : String(value)
    }

    function _getShellColor(key: string, fallback: color): color {
        var value = _getShell(key, "")
        if (/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(value)) return value
        if (/^rgba?\([0-9.,% ]+\)$/.test(value)) return value
        return fallback
    }

    function _getShellAlpha(key: string, fallback: real): real {
        var value = Number(_getShell(key, fallback))
        return isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback
    }

    function _withAlpha(value: color, alpha: real): color {
        var resolved = value
        return Qt.rgba(resolved.r, resolved.g, resolved.b, Math.max(0, Math.min(1, Number(alpha))))
    }

    // 2. Canonical Rosé Pine Moon Base Palette (Authored directly in Aurelia)
    readonly property color _base: "#232136"
    readonly property color _surface: "#2a273f"
    readonly property color _overlay: "#393552"
    readonly property color _muted: "#6e6a86"
    readonly property color _subtle: "#908caa"
    readonly property color _text: "#e0def4"
    readonly property color _love: "#eb6f92"
    readonly property color _gold: "#f6c177"
    readonly property color _rose: "#ea9a97"
    readonly property color _pine: "#3e8fb0"
    readonly property color _foam: "#9ccfd8"
    readonly property color _iris: "#c4a7e7"
    readonly property color _highlightLow: "#2a283e"
    readonly property color _highlightMed: "#44415a"
    readonly property color _highlightHigh: "#56526e"

    // 3. Semantic Color Tokens (Configurable via theme.conf or an
    // Omarchy-compatible colors.toml). The fallback names mirror Omarchy's
    // canonical palette so every bundled stock theme keeps its exact colors
    // when it is consumed by Aurelia's richer semantic token set.
    readonly property string themeMode: _getString("mode", _getString("theme_type", "dark"))
    readonly property color background: _getColor("background", "", _base)
    readonly property color bgBase: background
    readonly property color surface: _getColor("surface", ["lighter_background"], _surface)
    readonly property color surfaceElevated: _getColor("surfaceElevated", ["selection", "lighter_background"], _overlay)
    readonly property color selection: _getColor("selection", ["selection_background"], _overlay)
    readonly property color selectionHover: _getColor("selectionHover", ["selection_hover", "selection"], selection)
    readonly property color selectionActive: _getColor("selectionActive", ["selection_active", "selection"], _highlightMed)
    readonly property color border: _getColor("border", ["border_inactive", "muted", "inactive_border_color", "inactive_border"], "#424659")
    readonly property color borderActive: _getColor("borderActive", ["active_border_color", "accent", "active_border", "border_active"], _foam)
    readonly property color text: _getColor("text", ["foreground"], _text)
    readonly property color textSecondary: _getColor("textSecondary", ["light_foreground"], _subtle)
    readonly property color textMuted: _getColor("textMuted", ["muted", "dark_foreground", "color8"], _subtle)
    readonly property color textSubtle: _getColor("textSubtle", ["dark_foreground", "muted", "color0"], _muted)
    readonly property color accent: _getColor("accent", ["color4"], _foam)
    readonly property color accentAlt: _getColor("accentAlt", ["magenta", "purple", "color13"], _iris)
    readonly property color gold: _getColor("gold", ["yellow", "color3"], _gold)
    readonly property color love: _getColor("love", ["red", "color1"], _love)
    readonly property color pine: _getColor("pine", ["green", "color6"], _pine)
    readonly property color foam: _getColor("foam", ["cyan", "color4"], _foam)
    readonly property color rose: _getColor("rose", ["orange", "color5"], _rose)
    readonly property color iris: _getColor("iris", ["magenta", "purple", "color13"], _iris)
    readonly property color success: _getColor("success", ["green"], _foam)
    readonly property color warning: _getColor("warning", ["yellow"], _gold)
    readonly property color error: _getColor("error", ["red"], _love)

    // Surface roles are loaded from the generated shell.toml state. They keep
    // the existing Aurelia token names as fallbacks, so older user themes and
    // first-run installations remain valid while Omarchy-compatible themes
    // progressively gain per-surface colors and alpha values.
    readonly property QtObject controls: QtObject {
        readonly property color normalColor: themeRoot._getShellColor("controls.normal-color", themeRoot.text)
        readonly property real normalFillAlpha: themeRoot._getShellAlpha("controls.normal-fill-alpha", 0.04)
        readonly property color normalFill: themeRoot._withAlpha(themeRoot.surface, normalFillAlpha)
        readonly property color normalBorder: themeRoot._getShellColor("controls.normal-border", themeRoot.border)
        readonly property color hoverColor: themeRoot._getShellColor("controls.hover-cursor-color", themeRoot.text)
        readonly property color hoverFill: themeRoot._withAlpha(themeRoot.surface, themeRoot._getShellAlpha("controls.hover-cursor-fill-alpha", 0.08))
        readonly property color hoverBorder: themeRoot._getShellColor("controls.hover-cursor-border", themeRoot.borderActive)
        readonly property color focusColor: themeRoot._getShellColor("controls.focus-color", themeRoot.text)
        readonly property color focusFill: themeRoot._withAlpha(themeRoot.surface, themeRoot._getShellAlpha("controls.focus-fill-alpha", 0.08))
        readonly property color focusBorder: themeRoot._getShellColor("controls.focus-border", themeRoot.borderActive)
        readonly property color selectedColor: themeRoot._getShellColor("controls.selected-color", themeRoot.text)
        readonly property color selectedFill: themeRoot._withAlpha(themeRoot.surface, themeRoot._getShellAlpha("controls.selected-fill-alpha", 0.18))
        readonly property color selectedBorder: themeRoot._getShellColor("controls.selected-border", themeRoot.borderActive)
        readonly property color pressedFill: themeRoot._withAlpha(themeRoot.surface, themeRoot._getShellAlpha("controls.pressed-fill-alpha", 0.22))
    }

    readonly property QtObject popups: QtObject {
        readonly property color background: themeRoot._withAlpha(
            themeRoot._getShellColor("popups.background", themeRoot.bgBase),
            themeRoot._getShellAlpha("popups.background-alpha", 1.0))
        readonly property color text: themeRoot._getShellColor("popups.text", themeRoot.text)
        readonly property color border: themeRoot._withAlpha(
            themeRoot._getShellColor("popups.border", themeRoot.borderActive),
            themeRoot._getShellAlpha("popups.border-alpha", 1.0))
    }

    readonly property QtObject tooltip: QtObject {
        readonly property color background: themeRoot._withAlpha(
            themeRoot._getShellColor("tooltip.background", themeRoot.surfaceElevated),
            themeRoot._getShellAlpha("tooltip.background-alpha", 0.97))
        readonly property color text: themeRoot._getShellColor("tooltip.text", themeRoot.text)
        readonly property color border: themeRoot._withAlpha(
            themeRoot._getShellColor("tooltip.border", themeRoot.borderActive),
            themeRoot._getShellAlpha("tooltip.border-alpha", 1.0))
    }

    readonly property QtObject notifications: QtObject {
        readonly property color background: themeRoot._withAlpha(
            themeRoot._getShellColor("notifications.background", themeRoot.surfaceElevated),
            themeRoot._getShellAlpha("notifications.background-alpha", 1.0))
        readonly property color text: themeRoot._getShellColor("notifications.text", themeRoot.text)
        readonly property color border: themeRoot._withAlpha(
            themeRoot._getShellColor("notifications.border", themeRoot.borderActive),
            themeRoot._getShellAlpha("notifications.border-alpha", 1.0))
        readonly property color countdown: themeRoot._getShellColor("notifications.countdown", themeRoot.accent)
    }

    readonly property QtObject launcher: QtObject {
        readonly property color background: themeRoot._withAlpha(
            themeRoot._getShellColor("launcher.background", themeRoot.bgBase),
            themeRoot._getShellAlpha("launcher.background-alpha", 0.95))
        readonly property color text: themeRoot._getShellColor("launcher.text", themeRoot.text)
        readonly property color border: themeRoot._getShellColor("launcher.border", themeRoot.borderActive)
        readonly property color scrim: themeRoot._withAlpha(
            themeRoot._getShellColor("launcher.scrim", themeRoot.bgBase),
            themeRoot._getShellAlpha("launcher.scrim-alpha", 0.5))
        readonly property color selectedBackground: themeRoot._withAlpha(
            themeRoot._getShellColor("launcher.selected-background", themeRoot.text),
            themeRoot._getShellAlpha("launcher.selected-background-alpha", 0.08))
        readonly property color selectedText: themeRoot._getShellColor("launcher.selected-text", themeRoot.accent)
        readonly property color selectedBorder: themeRoot._withAlpha(
            themeRoot._getShellColor("launcher.selected-border", themeRoot.borderActive),
            themeRoot._getShellAlpha("launcher.selected-border-alpha", 0.25))
    }

    readonly property QtObject menu: QtObject {
        readonly property color background: themeRoot._withAlpha(
            themeRoot._getShellColor("menu.background", themeRoot.bgBase),
            themeRoot._getShellAlpha("menu.background-alpha", 1.0))
        readonly property color text: themeRoot._getShellColor("menu.text", themeRoot.text)
        readonly property color border: themeRoot._getShellColor("menu.border", themeRoot.borderActive)
        readonly property color scrim: themeRoot._withAlpha(
            themeRoot._getShellColor("menu.scrim", themeRoot.bgBase),
            themeRoot._getShellAlpha("menu.scrim-alpha", 0.5))
        readonly property color selectedBackground: themeRoot._withAlpha(
            themeRoot._getShellColor("menu.selected-background", themeRoot.text),
            themeRoot._getShellAlpha("menu.selected-background-alpha", 0.08))
        readonly property color selectedText: themeRoot._getShellColor("menu.selected-text", themeRoot.accent)
        readonly property color selectedBorder: themeRoot._withAlpha(
            themeRoot._getShellColor("menu.selected-border", themeRoot.borderActive),
            themeRoot._getShellAlpha("menu.selected-border-alpha", 0.25))
    }

    readonly property QtObject imagePicker: QtObject {
        readonly property color scrim: themeRoot._withAlpha(
            themeRoot._getShellColor("image-picker.scrim", themeRoot.bgBase),
            themeRoot._getShellAlpha("image-picker.scrim-alpha", 0.5))
        readonly property color text: themeRoot._getShellColor("image-picker.text", themeRoot.text)
        readonly property color selectedBorder: themeRoot._withAlpha(
            themeRoot._getShellColor("image-picker.selected-border", themeRoot.accent),
            themeRoot._getShellAlpha("image-picker.selected-border-alpha", 1.0))
        readonly property color unselectedBorder: themeRoot._withAlpha(
            themeRoot._getShellColor("image-picker.unselected-border", themeRoot.text),
            themeRoot._getShellAlpha("image-picker.unselected-border-alpha", 0.28))
    }

    // Calendar surface tokens. They intentionally sit beside the shared
    // semantic palette so the small popup can be tuned without editing QML.
    readonly property color calendarAccent: _getColor("calendarAccent", "", accent)
    readonly property color calendarHover: _getColor("calendarHover", "", selection)
    readonly property color calendarWeekend: _getColor("calendarWeekend", "", textSecondary)
    readonly property color calendarAdjacent: _getColor("calendarAdjacent", "", textSubtle)
    readonly property color calendarRule: _getColor("calendarRule", "", border)

    // 3b. Semantic Input Tokens (Shared across all Aurelia text fields)
    readonly property color inputBg: surface
    readonly property color bgCard: surface
    readonly property color inputBorder: border
    readonly property color inputBorderFocused: borderActive
    readonly property color inputText: text
    readonly property color inputPlaceholder: textSubtle
    readonly property color inputSelection: selection
    readonly property color inputSelectionText: text
    readonly property color inputCursor: accent

    // 4. Semantic Typography Tokens (Configurable via theme.conf)
    readonly property string fontFamily: _getString("fontFamily", "JetBrainsMono Nerd Font, Hack Nerd Font, monospace")
    readonly property string fontFamilyProse: _getString("fontFamilyProse", "sans-serif")
    readonly property int fontSizeXs: Math.max(1, Math.round(_getInt("fontSizeXs", 10) * fontScale))
    readonly property int fontSizeSm: Math.max(1, Math.round(_getInt("fontSizeSm", 13) * fontScale))
    readonly property int fontSizeMd: Math.max(1, Math.round(_getInt("fontSizeMd", 14) * fontScale))
    readonly property int fontSizeLg: Math.max(1, Math.round(_getInt("fontSizeLg", 15) * fontScale))
    readonly property int fontSizeXl: Math.max(1, Math.round(_getInt("fontSizeXl", 18) * fontScale))
    readonly property int fontWeightNormal: Font.Normal
    readonly property int fontWeightMedium: Font.Medium
    readonly property int fontWeightBold: Font.Bold

    // 5. Semantic Spacing Scale Tokens (Configurable via theme.conf)
    readonly property int spacingXs: _getInt("spacingXs", 4)
    readonly property int spacingSm: _getInt("spacingSm", 8)
    readonly property int spacingMd: _getInt("spacingMd", 12)
    readonly property int spacingLg: _getInt("spacingLg", 16)
    readonly property int spacingXl: _getInt("spacingXl", 20)
    readonly property int spacingXxl: _getInt("spacingXxl", 24)
    // Popup geometry follows Omarchy's structural defaults: a small gap from
    // the bar edge and a separate, slightly larger card inset.
    readonly property int popupMargin: _getScaledInt("popupMargin", 5)
    readonly property int popupPadding: _getScaledInt("popupPadding", 10)
    readonly property int popupRowGap: _getScaledInt("popupRowGap", 2)
    readonly property int popupSeparatorHeight: _getScaledInt("popupSeparatorHeight", 6)
    readonly property int trayMenuPadding: _getScaledInt("trayMenuPadding", 8)
    readonly property int trayMenuRowHeight: _getScaledInt("trayMenuRowHeight", 30)
    readonly property int trayMenuGap: _getScaledInt("trayMenuGap", 1)
    readonly property int trayMenuSeparatorHeight: _getScaledInt("trayMenuSeparatorHeight", 4)
    readonly property int trayMenuSectionHeight: _getScaledInt("trayMenuSectionHeight", 22)
    readonly property int trayMenuTextSize: _getInt("trayMenuTextSize", 12)
    readonly property int trayMenuSectionTextSize: _getInt("trayMenuSectionTextSize", 10)
    readonly property int trayMenuTextInset: _getInt("trayMenuTextInset", 28)

    // Minimal calendar geometry. These values are deliberately independent
    // from the command palette so the popup can be tuned as a compact surface.
    readonly property int calendarPopupWidth: _getInt("calendarPopupWidth", 320)
    readonly property int calendarPopupHeight: _getInt("calendarPopupHeight", 386)
    readonly property int calendarPadding: _getInt("calendarPadding", 12)
    readonly property int calendarCellSize: _getInt("calendarCellSize", 36)
    readonly property int calendarCellGap: _getInt("calendarCellGap", 2)
    readonly property int calendarHeaderHeight: _getInt("calendarHeaderHeight", 26)
    readonly property int calendarToolbarHeight: _getInt("calendarToolbarHeight", 30)
    readonly property int calendarWeekdayHeight: _getInt("calendarWeekdayHeight", 16)
    readonly property int calendarFooterHeight: _getInt("calendarFooterHeight", 12)

    // 6. Semantic Geometry & Layout Proportions (Configurable via theme.conf)
    readonly property int radiusSm: _getInt("radiusSm", 4)
    readonly property int radiusMd: _getInt("radiusMd", 8)
    readonly property int radiusLg: _getInt("radiusLg", 12)
    readonly property int borderWidthDefault: _getInt("borderWidthDefault", 1)
    readonly property int borderWidthFocus: _getInt("borderWidthFocus", 2)

    // Command Palette Layout Proportions (Configurable via theme.conf)
    readonly property int paletteWidth: _getInt("paletteWidth", 560)
    readonly property int paletteHeight: _getInt("paletteHeight", 420)
    readonly property int rowHeight: _getInt("rowHeight", 34)
    readonly property int searchHeight: _getInt("searchHeight", 36)
    readonly property int footerHeight: _getInt("footerHeight", 34)
    readonly property int colShortcutWidth: _getInt("colShortcutWidth", 350)
    readonly property int colSeparatorWidth: _getInt("colSeparatorWidth", 28)
    readonly property int rowSpacing: _getInt("rowSpacing", 3)
    readonly property int scrollBarWidth: _getInt("scrollBarWidth", 4)

    // 7. Semantic Motion Tokens & Layered Preferences (Authoritative Schema Adapter)
    readonly property int durationFast: _getInt("durationFast", 100)
    readonly property int durationNormal: _getInt("durationNormal", 200)

    // Effective Motion: Shipped Defaults + User Overrides from canonical preferences.json
    readonly property bool motionEnabled: {
        var p = getPreference("aurelia.motion.enabled", true)
        return p === true || p === "true"
    }

    readonly property real motionScale: {
        var p = getPreference("aurelia.motion.scale", 1.0)
        var num = parseFloat(p)
        return (!isNaN(num) && num >= 0) ? num : 1.0
    }

    function componentMotionEnabled(componentId: string): bool {
        var compPref = getPreference("components." + componentId + ".motion.enabled", undefined)
        if (compPref !== undefined) {
            return compPref === true || compPref === "true"
        }
        return motionEnabled
    }

    function componentMotionScale(componentId: string): real {
        var compScale = getPreference("components." + componentId + ".motion.scale", undefined)
        if (compScale !== undefined) {
            var s = parseFloat(compScale)
            if (!isNaN(s) && s >= 0) return s
        }
        return motionScale
    }

    // Effective transformed durations consumed across Aurelia components:
    // motionEnabled = false immediately produces 0ms duration without QML editing.
    readonly property int effectiveDurationFast: motionEnabled ? Math.round(durationFast * motionScale) : 0
    readonly property int effectiveDurationNormal: motionEnabled ? Math.round(durationNormal * motionScale) : 0

    function getComponentDuration(componentId: string, baseDuration: int): int {
        if (!componentMotionEnabled(componentId)) return 0
        return Math.round(baseDuration * componentMotionScale(componentId))
    }

    readonly property int keybindingsDurationFast: getComponentDuration("keybindings", durationFast)
    readonly property int keybindingsDurationNormal: getComponentDuration("keybindings", durationNormal)
}
