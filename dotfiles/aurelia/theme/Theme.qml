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
    property string themePath: {
        var envPath = Quickshell.env("AURELIA_THEME_CONF") || ""
        if (envPath !== "") return envPath
        var home = Quickshell.env("HOME") || ""
        if (home === "") return ""
        // Native Aurelia design system theme configuration
        return home + "/.config/aurelia/theme.conf"
    }

    property FileView themeFile: FileView {
        path: themeRoot.themePath
    }

    // 1b. Aurelia User Preferences File (XDG layered configuration)
    property string preferencesPath: {
        var envPath = Quickshell.env("AURELIA_PREFERENCES_PATH") || ""
        if (envPath !== "") return envPath
        var configHome = Quickshell.env("XDG_CONFIG_HOME") || ""
        if (configHome === "") {
            var home = Quickshell.env("HOME") || ""
            configHome = home + "/.config"
        }
        return configHome + "/aurelia/preferences.json"
    }

    property int _prefReloadToken: 0
    function reloadPreferences() {
        var p = themeRoot.preferencesPath
        preferencesFile.path = ""
        preferencesFile.path = p
        _prefReloadToken++
    }

    property FileView preferencesFile: FileView {
        path: themeRoot.preferencesPath
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
    readonly property string shortcutSet: getPreference("components.keybindings.shortcuts.set_binding", "S")
    readonly property string shortcutUnset: getPreference("components.keybindings.shortcuts.unset_binding", "U")

    readonly property var loadedOverrides: {
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

    function _getInt(key: string, defaultValue: int): int {
        if (loadedOverrides[key] !== undefined && loadedOverrides[key] !== "") {
            var v = parseInt(loadedOverrides[key], 10)
            if (!isNaN(v)) return v
        }
        return defaultValue
    }

    function _getString(key: string, defaultValue: string): string {
        if (loadedOverrides[key] !== undefined && loadedOverrides[key] !== "") {
            return loadedOverrides[key].replace(/^["']|["']$/g, "")
        }
        return defaultValue
    }

    function _getColor(key: string, altKeys: var, fallbackColor: color): color {
        if (loadedOverrides[key] !== undefined && loadedOverrides[key] !== "") {
            return loadedOverrides[key]
        }
        if (altKeys) {
            if (typeof altKeys === "string") {
                if (loadedOverrides[altKeys] !== undefined && loadedOverrides[altKeys] !== "") {
                    return loadedOverrides[altKeys]
                }
            } else if (Array.isArray(altKeys)) {
                for (var i = 0; i < altKeys.length; i++) {
                    var k = altKeys[i]
                    if (loadedOverrides[k] !== undefined && loadedOverrides[k] !== "") {
                        return loadedOverrides[k]
                    }
                }
            }
        }
        return fallbackColor
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

    // 3. Semantic Color Tokens (Configurable via theme.conf)
    readonly property color background: _getColor("background", "", _base)
    readonly property color bgBase: background
    readonly property color surface: _getColor("surface", "", _surface)
    readonly property color surfaceElevated: _getColor("surfaceElevated", "", _overlay)
    readonly property color selection: _getColor("selection", ["selection_background"], _overlay)
    readonly property color selectionActive: _getColor("selectionActive", ["selection_active"], _highlightMed)
    readonly property color border: _getColor("border", ["inactive_border_color", "inactive_border", "border_inactive"], "#424659")
    readonly property color borderActive: _getColor("borderActive", ["active_border_color", "active_border", "border_active"], _foam)
    readonly property color text: _getColor("text", ["foreground"], _text)
    readonly property color textSecondary: _getColor("textSecondary", "", _subtle)
    readonly property color textMuted: _getColor("textMuted", ["color8"], _subtle)
    readonly property color textSubtle: _getColor("textSubtle", ["color0"], _muted)
    readonly property color accent: _getColor("accent", ["color4"], _foam)
    readonly property color accentAlt: _getColor("accentAlt", ["color13"], _iris)
    readonly property color gold: _getColor("gold", ["color3"], _gold)
    readonly property color love: _getColor("love", ["color1"], _love)
    readonly property color pine: _getColor("pine", ["color6"], _pine)
    readonly property color foam: _getColor("foam", ["color4"], _foam)
    readonly property color rose: _getColor("rose", ["color5"], _rose)
    readonly property color iris: _getColor("iris", ["color13"], _iris)
    readonly property color success: _getColor("success", "", _foam)
    readonly property color warning: _getColor("warning", "", _gold)
    readonly property color error: _getColor("error", "", _love)

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
    readonly property int fontSizeXs: _getInt("fontSizeXs", 10)
    readonly property int fontSizeSm: _getInt("fontSizeSm", 13)
    readonly property int fontSizeMd: _getInt("fontSizeMd", 14)
    readonly property int fontSizeLg: _getInt("fontSizeLg", 15)
    readonly property int fontSizeXl: _getInt("fontSizeXl", 18)
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

    // 6. Semantic Geometry & Layout Proportions (Configurable via theme.conf)
    readonly property int radiusSm: _getInt("radiusSm", 4)
    readonly property int radiusMd: _getInt("radiusMd", 8)
    readonly property int radiusLg: _getInt("radiusLg", 12)
    readonly property int borderWidthDefault: _getInt("borderWidthDefault", 1)
    readonly property int borderWidthFocus: _getInt("borderWidthFocus", 2)

    // Command Palette Layout Proportions (Configurable via theme.conf)
    readonly property int paletteWidth: _getInt("paletteWidth", 800)
    readonly property int paletteHeight: _getInt("paletteHeight", 480)
    readonly property int rowHeight: _getInt("rowHeight", 38)
    readonly property int searchHeight: _getInt("searchHeight", 40)
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
}
