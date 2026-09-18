// ColorUtils.js — pure color parsing/formatting for the Settings hub.
//
// Hyprland color options use the canonical `rgba(RRGGBBAA)` form and also
// accept `#RRGGBB[AA]`. Keeping parse/format/normalize in one pure module
// means the inline color row, the picker, and their tests share one contract.
// No mutation logic and no QML object construction belongs here.
.pragma library

function clampByte(value) {
    var n = Math.round(Number(value))
    if (isNaN(n)) return 0
    if (n < 0) return 0
    if (n > 255) return 255
    return n
}

function byteToHex(value) {
    var s = clampByte(value).toString(16)
    return s.length === 1 ? "0" + s : s
}

// Parse any supported color string into 0..255 channels. Unparseable input
// fails closed to transparent black so callers can rely on a total function;
// use isValid() to distinguish malformed input.
function parseColor(text) {
    var s = String(text === undefined || text === null ? "" : text).trim()
    var m
    if ((m = /^#([0-9a-fA-F]{6})$/.exec(s)) !== null)
        return { r: parseInt(m[1].substr(0, 2), 16), g: parseInt(m[1].substr(2, 2), 16), b: parseInt(m[1].substr(4, 2), 16), a: 255 }
    if ((m = /^#([0-9a-fA-F]{8})$/.exec(s)) !== null)
        return { r: parseInt(m[1].substr(0, 2), 16), g: parseInt(m[1].substr(2, 2), 16), b: parseInt(m[1].substr(4, 2), 16), a: parseInt(m[1].substr(6, 2), 16) }
    if ((m = /^rgba\(([0-9a-fA-F]{8})\)$/.exec(s)) !== null)
        return { r: parseInt(m[1].substr(0, 2), 16), g: parseInt(m[1].substr(2, 2), 16), b: parseInt(m[1].substr(4, 2), 16), a: parseInt(m[1].substr(6, 2), 16) }
    if ((m = /^rgb\(([0-9a-fA-F]{6})\)$/.exec(s)) !== null)
        return { r: parseInt(m[1].substr(0, 2), 16), g: parseInt(m[1].substr(2, 2), 16), b: parseInt(m[1].substr(4, 2), 16), a: 255 }
    return { r: 0, g: 0, b: 0, a: 0 }
}

function isValid(text) {
    var s = String(text === undefined || text === null ? "" : text).trim()
    return /^#[0-9a-fA-F]{6}$/.test(s) ||
        /^#[0-9a-fA-F]{8}$/.test(s) ||
        /^rgb\([0-9a-fA-F]{6}\)$/.test(s) ||
        /^rgba\([0-9a-fA-F]{8}\)$/.test(s)
}

// Canonical backend form.
function toRgba(r, g, b, a) {
    return "rgba(" + byteToHex(r) + byteToHex(g) + byteToHex(b) + byteToHex(a) + ")"
}

function toHex(r, g, b) {
    return "#" + byteToHex(r) + byteToHex(g) + byteToHex(b)
}

// Compare only the RGB channels: the effective value may carry alpha that a
// curated preset does not.
function sameRgb(r1, g1, b1, r2, g2, b2) {
    return clampByte(r1) === clampByte(r2) &&
        clampByte(g1) === clampByte(g2) &&
        clampByte(b1) === clampByte(b2)
}
