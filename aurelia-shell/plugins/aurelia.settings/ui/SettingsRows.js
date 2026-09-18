// SettingsRows.js — pure row-descriptor builders for the Settings hub.
//
// This module contains NO mutation logic. It only projects the option schema
// (single source of truth: `workstation-hypr-settings schema`) and live
// status onto declarative row descriptors that the QML renderer displays.
// Keeping this logic in one place (instead of scattering rows across pages)
// makes the option set easy to audit and extend.

.pragma library

// Map a schema option to a renderer row descriptor.
function schemaRow(schema, status) {
    var descriptor = {
        id: schema.id,
        kind: controlKind(schema),
        title: schema.label,
        description: schema.description,
        type: schema.type,
        min: schema.min !== "" ? Number(schema.min) : 0,
        max: schema.max !== "" ? Number(schema.max) : 1,
        enumOptions: (status && status.options && status.options.length)
            ? status.options : splitEnum(schema.enum),
        step: stepFor(schema),
        defaultValue: schema.default,
        unit: unitFor(schema.id),
        effective: normalizeStatus(status, schema.type),
        source: status ? status.source : "default",
        override: status ? status.override : ""
    }
    // A few backend options are free-form strings that benefit from a curated
    // picker while still accepting arbitrary values (editable combo).
    if (schema.id === "input.kb_layout") {
        descriptor.kind = "combo"
        descriptor.editable = true
        descriptor.enumOptions = keyboardLayoutOptions(descriptor.effective)
    }
    if (schema.id === "misc.font_family") {
        descriptor.kind = "combo"
        descriptor.editable = true
        descriptor.enumOptions = fontFamilyOptions(descriptor.effective)
    }
    return descriptor
}

// Curated font-family suggestions; the field stays editable for any family.
function fontFamilyOptions(current) {
    var families = ["Sans", "Serif", "Monospace", "Noto Sans", "Cantarell", "Inter",
        "JetBrainsMono Nerd Font", "Hack Nerd Font", "FiraCode Nerd Font", "Ubuntu"]
    var options = []
    for (var i = 0; i < families.length; i++) options.push({ value: families[i], label: families[i] })
    var cur = String(current || "").trim()
    if (cur !== "" && families.indexOf(cur) === -1) options.unshift({ value: cur, label: cur })
    return options
}

// Curated keyboard layouts. The backend still validates kb_layout as a free
// string, so the picker is editable and never blocks a custom layout.
function keyboardLayoutOptions(current) {
    var codes = ["us", "gb", "de", "fr", "es", "it", "pt", "nl", "se", "no",
        "dk", "fi", "pl", "cz", "sk", "hu", "ro", "bg", "gr", "tr",
        "ru", "ua", "il", "jp", "kr", "cn", "in", "br", "ca", "ch",
        "be", "at", "ie", "mx", "vn", "th"]
    var options = []
    for (var i = 0; i < codes.length; i++) {
        options.push({ value: codes[i], label: layoutLabel(codes[i]) })
    }
    var cur = String(current || "").trim()
    if (cur !== "" && !layoutKnown(cur)) options.unshift({ value: cur, label: cur })
    return options
}

function layoutKnown(value) {
    var codes = ["us", "gb", "de", "fr", "es", "it", "pt", "nl", "se", "no",
        "dk", "fi", "pl", "cz", "sk", "hu", "ro", "bg", "gr", "tr",
        "ru", "ua", "il", "jp", "kr", "cn", "in", "br", "ca", "ch",
        "be", "at", "ie", "mx", "vn", "th"]
    for (var i = 0; i < codes.length; i++) {
        if (codes[i] === value) return true
    }
    return false
}

function layoutLabel(code) {
    var labels = {
        us: "English (US)", gb: "English (UK)", de: "German", fr: "French",
        es: "Spanish", it: "Italian", pt: "Portuguese", nl: "Dutch",
        se: "Swedish", no: "Norwegian", dk: "Danish", fi: "Finnish",
        pl: "Polish", cz: "Czech", sk: "Slovak", hu: "Hungarian",
        ro: "Romanian", bg: "Bulgarian", gr: "Greek", tr: "Turkish",
        ru: "Russian", ua: "Ukrainian", il: "Hebrew", jp: "Japanese",
        kr: "Korean", cn: "Chinese", in: "Indian", br: "Portuguese (Brazil)",
        ca: "English (Canada)", ch: "German (Switzerland)", be: "Belgian",
        at: "German (Austria)", ie: "English (Ireland)", mx: "Spanish (Mexico)",
        vn: "Vietnamese", th: "Thai"
    }
    return labels[code] || code.toUpperCase()
}

// Application-defaults picker options for one role. An empty value means
// "no explicit default", which the window maps to a reset.
function roleOptions(role, choices, current) {
    var options = [{ value: "", label: "System default" }]
    var list = choices && choices[role] ? choices[role] : []
    var seen = {}
    for (var i = 0; i < list.length; i++) {
        var id = String(list[i])
        if (id === "" || seen[id]) continue
        seen[id] = true
        options.push({ value: id, label: displayAppId(id) })
    }
    var cur = String(current || "")
    if (cur !== "" && !seen[cur]) options.push({ value: cur, label: displayAppId(cur) })
    return options
}

function displayAppId(id) {
    var name = String(id)
    if (name.slice(-8) === ".desktop") name = name.slice(0, -8)
    return name
}

function normalizeStatus(status, type) {
    if (!status) return ""
    switch (type) {
        case "bool": return status.effective === true || status.effective === "true" ? true : false
        case "int":
        case "float": return Number(status.effective)
        default: return String(status.effective || "")
    }
}

function controlKind(schema) {
    switch (schema.type) {
        case "bool": return "toggle"
        case "enum":
        case "denum": return "combo"
        case "color": return "color"
        case "str": return "text"
        case "int":
        case "float":
        default: return "slider"
    }
}

// Slider granularity. Floats need a fractional step; integers step by one.
function stepFor(schema) {
    return schema.type === "float" ? 0.05 : 1
}

function splitEnum(enumValue) {
    var options = []
    if (!enumValue) return options
    var parts = String(enumValue).split(",")
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i]
        if (part !== "") options.push({ value: part, label: displayEnum(part) })
    }
    return options
}

function displayEnum(value) {
    switch (String(value)) {
        case "dwindle": return "Dwindle"
        case "master": return "Master"
        case "flat": return "Flat"
        case "adaptive": return "Adaptive"
        case "0": return "Off"
        case "1": return "On"
        case "2": return "Fullscreen only"
        case "baseline": return "Baseline (default)"
        case "snappy": return "Snappy"
        case "relaxed": return "Relaxed"
        case "off": return "Off"
        case "power-saver": return "Power Saver"
        case "balanced": return "Balanced"
        case "performance": return "Performance"
        case "slave": return "Slave"
        case "inherit": return "Inherit"
        case "default": return "Default"
        case "prefer-dark": return "Prefer Dark"
        case "prefer-light": return "Prefer Light"
        default: return String(value)
    }
}

// User-friendly unit shown next to slider values.
function unitFor(id) {
    switch (String(id || "")) {
        case "general.gaps_in":
        case "general.gaps_out":
        case "general.border_size":
        case "decoration.rounding":
        case "decoration.blur.size":
            return "px"
        case "input.repeat_rate":
            return "cps"
        case "input.repeat_delay":
            return "ms"
        case "decoration.active_opacity":
        case "decoration.inactive_opacity":
        case "decoration.fullscreen_opacity":
            return "%"
        case "system.display.brightness":
        case "system.audio.output_volume":
            return "pct"
        case "system.appearance.cursor_size":
            return "px"
        case "system.appearance.text_scaling":
            return "\u00d7"
        case "cursor.inactive_timeout":
            return "s"
        case "cursor.min_refresh_rate":
            return "Hz"
        case "binds.scroll_event_delay":
            return "ms"
        case "decoration.shadow.range":
            return "px"
        case "input.touchpad.scroll_factor":
        case "cursor.zoom_factor":
            return "\u00d7"
        case "decoration.dim_strength":
            return "%"
        default:
            return ""
    }
}

// Sections: id, name, icon, schemaCategories.
function sections() {
    return [
        { id: "hypr-general", name: "General & Appearance", icon: "preferences-desktop",
          categories: ["general", "decoration", "misc"], schema: true },
        { id: "hypr-animations", name: "Animations", icon: "media-playlist-repeat",
          categories: ["animations"], schema: true },
        { id: "hypr-input", name: "Input", icon: "input-keyboard",
          categories: ["input"], schema: true },
        { id: "hypr-layouts", name: "Window Layouts", icon: "preferences-system-windows",
          categories: ["master", "dwindle"], schema: true },
        { id: "hypr-cursor", name: "Cursor", icon: "input-mouse",
          categories: ["cursor"], schema: true },
        { id: "hypr-binds", name: "Keybind Behavior", icon: "input-keyboard-virtual",
          categories: ["binds"], schema: true },
        { id: "hypr-compat", name: "Compatibility", icon: "preferences-system",
          categories: ["xwayland", "ecosystem"], schema: true },
        { id: "hypr-workspaces", name: "Workspaces", icon: "preferences-desktop-wallpaper",
          categories: ["workspaces"], schema: true },
        { id: "power", name: "Power", icon: "battery",
          categories: ["power", "display"], schema: true },
        { id: "appearance", name: "Themes & Fonts", icon: "preferences-desktop-theme",
          categories: ["appearance"], schema: true },
        { id: "audio", name: "Audio", icon: "audio-volume-high",
          categories: ["audio"], schema: true },
        { id: "bluetooth", name: "Bluetooth", icon: "bluetooth",
          categories: ["bluetooth"], schema: true },
        { id: "network", name: "Network", icon: "network-wireless",
          categories: ["network"], schema: true },
        { id: "time", name: "Date & Time", icon: "preferences-system-time",
          categories: ["time"], schema: true },
        { id: "defaults", name: "Defaults", icon: "preferences-desktop-apps",
          categories: [], schema: false, defaults: true },
        { id: "aurelia", name: "Aurelia Shell", icon: "display",
          categories: [], schema: false, aurelia: true },
        { id: "about", name: "About & Reset", icon: "help-about",
          categories: [], schema: false }
    ]
}

// Build the row list for one section.
function buildRows(sectionId, schemas, statuses, aurelia) {
    var section = null
    var allSections = sections()
    for (var s = 0; s < allSections.length; s++) {
        if (allSections[s].id === sectionId) { section = allSections[s]; break }
    }
    if (!section) return []

    var rows = []

    if (section.schema) {
        // categories in a stable display order
        var order = []
        for (var s2 = 0; s2 < allSections.length; s2++) {
            if (allSections[s2].schema) {
                for (var c = 0; c < allSections[s2].categories.length; c++) {
                    if (order.indexOf(allSections[s2].categories[c]) === -1) order.push(allSections[s2].categories[c])
                }
            }
        }
        var categoryOrder = sectionId === "hypr-general"
            ? ["general", "decoration", "misc"] : section.categories
        var seen = {}
        for (var ci = 0; ci < categoryOrder.length; ci++) {
            var category = categoryOrder[ci]
            var first = true
            for (var i = 0; i < schemas.length; i++) {
                if (schemas[i].category !== category) continue
                if (seen[schemas[i].id]) continue
                seen[schemas[i].id] = true
                if (first) {
                    rows.push({
                        kind: "heading",
                        title: headingName(category)
                    })
                    first = false
                }
                rows.push(schemaRow(schemas[i], statuses ? statuses[schemas[i].id] : {}))
            }
        }
        // Network scanning/connecting is owned by the full network panel; the
        // settings hub surfaces it rather than duplicating the password flow.
        if (sectionId === "network") {
            rows.push({
                kind: "action",
                actionId: "openNetworkPanel",
                title: "Scan for networks",
                description: "Discover available Wi-Fi networks and connect (opens the network panel).",
                label: "Scan\u2026"
            })
        }
        // The calendar week start is an Aurelia preference, surfaced beside the
        // other Date & Time options.
        if (sectionId === "time") {
            rows.push({
                kind: "combo",
                id: "aurelia.clock.format",
                title: "Clock Format",
                description: "Layout of the Aurelia bar clock.",
                enumOptions: [
                    { value: "time_only", label: "Time only" },
                    { value: "month_day_time", label: "Month day + time" },
                    { value: "month_day_weekday_time", label: "Month day + weekday + time" },
                    { value: "weekday_day_month_time", label: "Weekday + day month + time" },
                    { value: "full_weekday_month_day_time", label: "Full weekday + month day + time" },
                    { value: "month_day_only", label: "Month day only" }
                ],
                effective: (aurelia && aurelia.clockFormat) ? aurelia.clockFormat : "month_day_weekday_time"
            })
            rows.push({
                kind: "toggle",
                id: "aurelia.clock.hour24",
                title: "24-Hour Clock",
                description: "Use a 24-hour clock in the Aurelia bar clock.",
                effective: aurelia ? aurelia.clockHour24 !== false : true
            })
            rows.push({
                kind: "toggle",
                id: "aurelia.clock.seconds",
                title: "Show Seconds",
                description: "Show seconds in the Aurelia bar clock.",
                effective: aurelia ? aurelia.clockSeconds === true : false
            })
            rows.push({
                kind: "combo",
                id: "aurelia.calendar.weekStart",
                title: "Week Starts On",
                description: "First day of the week in the Aurelia calendar.",
                enumOptions: [
                    { value: "sunday", label: "Sunday" },
                    { value: "monday", label: "Monday" }
                ],
                effective: (aurelia && aurelia.weekStart) ? aurelia.weekStart : "sunday"
            })
        }
        return rows
    }

    if (sectionId === "defaults") {
        rows.push({
            kind: "heading",
            title: "Application Defaults"
        })
        var defRoles = [
            { role: "terminal", name: "Terminal", desc: "Opened by Super+Enter and all terminal workflows." },
            { role: "file-manager", name: "File Manager", desc: "Opened by Super+E and file actions." },
            { role: "browser", name: "Browser", desc: "Default web browser for URLs and https links." },
            { role: "editor", name: "Editor", desc: "Default text editor for editing actions." },
            { role: "email-client", name: "Email Client", desc: "Default mail client for mailto: links." }
        ]
        for (var d = 0; d < defRoles.length; d++) {
            var role = defRoles[d].role
            var currents = aurelia && aurelia.defaults ? aurelia.defaults.currents : null
            var choices = aurelia && aurelia.defaults ? aurelia.defaults.choices : null
            var current = currents ? String(currents[role] || "") : ""
            rows.push({
                kind: "combo",
                id: "defaults." + role,
                title: defRoles[d].name,
                description: defRoles[d].desc,
                enumOptions: roleOptions(role, choices, current),
                effective: current,
                defaultValue: ""
            })
        }
        return rows
    }

    if (sectionId === "aurelia") {
        rows.push({
            kind: "heading",
            title: "Shell"
        })
        rows.push({
            kind: "info",
            title: "Aurelia Shell IPC",
            value: aurelia && aurelia.ipcOnline ? "Online" : "Unavailable",
            description: "The settings hub talks to the resident shell through bounded IPC helpers."
        })
        rows.push({
            kind: "combo",
            id: "aurelia.theme",
            title: "Theme",
            description: "Active Aurelia theme (data-only; no theme code is executed).",
            enumOptions: aurelia ? aurelia.themes : [],
            effective: aurelia ? aurelia.currentTheme : "",
            actionId: "setTheme"
        })
        rows.push({
            kind: "action",
            actionId: "openThemePanel",
            title: "Theme & Wallpaper panel",
            description: "Browse themes, backgrounds and the wallpaper library.",
            label: "Open panel"
        })
        rows.push({
            kind: "toggle",
            id: "aurelia.motion.enabled",
            title: "Shell Motion",
            description: "Master motion switch for Aurelia components.",
            effective: aurelia ? aurelia.motionEnabled : false,
            actionId: "setMotion"
        })
        rows.push({
            kind: "slider",
            id: "aurelia.motion.scale",
            title: "Motion Scale",
            description: "Global animation duration multiplier.",
            min: 0,
            max: 10,
            step: 0.1,
            effective: aurelia ? aurelia.motionScale : 1,
            actionId: "setMotionScale"
        })
        rows.push({
            kind: "slider",
            id: "aurelia.display.textSize",
            title: "Shell Text Size",
            description: "Aurelia-only text size (9..20 px). Terminal and GTK are untouched.",
            min: 9,
            max: 20,
            step: 1,
            effective: aurelia ? aurelia.textSize : 12,
            actionId: "setTextSize"
        })
        rows.push({
            kind: "toggle",
            id: "aurelia.bar",
            title: "Bar Hidden",
            description: "Hide or show the Aurelia bar (persists across re-launches).",
            effective: aurelia ? aurelia.barHidden : false,
            actionId: "setBarHidden"
        })
        rows.push({
            kind: "heading",
            title: "Keybindings"
        })
        rows.push({
            kind: "action",
            actionId: "openKeybindings",
            title: "Keybindings editor",
            description: "Capture and manage Hyprland bindings (Super + K).",
            label: "Open editor"
        })
        rows.push({
            kind: "info",
            title: "Shortcuts",
            value: "Super + K · Super + T",
            description: "Super + K opens Keybindings; Super + T opens this Settings hub."
        })
        return rows
    }

    if (sectionId === "about") {
        rows.push({
            kind: "heading",
            title: "Configuration"
        })
        rows.push({
            kind: "info",
            title: "Settings overlay",
            value: aurelia ? aurelia.settingsPath : "",
            description: "User-owned overlay loaded by hyprland.lua after the reviewed repository baseline."
        })
        rows.push({
            kind: "info",
            title: "Hyprland reachable",
            value: statuses && statuses.hyprctlAvailable ? "Yes — live preview active" : "No — changes apply on reload",
            description: "Hyprland IPC via bounded hyprctl queries."
        })
        rows.push({
            kind: "heading",
            title: "Reset"
        })
        rows.push({
            kind: "action",
            actionId: "resetSection",
            title: "Clear all overrides",
            description: "Remove every user setting and restart the reviewed repository baseline.",
            label: "Clear all"
        })
        rows.push({
            kind: "info",
            title: "Recovery",
            value: "workstation-hypr-settings clear",
            description: "The same reset is available from a terminal in any session."
        })
        return rows
    }

    return rows
}

function headingName(category) {
    switch (category) {
        case "general": return "General"
        case "decoration": return "Appearance"
        case "misc": return "Compositor"
        case "input": return "Input"
        case "animations": return "Animations"
        case "workspaces": return "Workspaces"
        case "cursor": return "Cursor"
        case "binds": return "Keybind Behavior"
        case "master": return "Master Layout"
        case "dwindle": return "Dwindle Layout"
        case "xwayland": return "XWayland"
        case "ecosystem": return "Ecosystem"
        case "power": return "Power"
        case "display": return "Display"
        case "appearance": return "Appearance"
        case "audio": return "Audio"
        case "bluetooth": return "Bluetooth"
        case "network": return "Network"
        case "time": return "Date & Time"
        default: return category
    }
}

// ---------- Aurelia helper state ----------
function emptyAureliaState() {
    return {
        ipcOnline: false,
        themes: [],
        currentTheme: "",
        motionEnabled: true,
        motionScale: 1,
        textSize: 12,
        barHidden: false,
        weekStart: "sunday",
        clockFormat: "month_day_weekday_time",
        clockHour24: true,
        clockSeconds: false,
        settingsPath: ""
    }
}
