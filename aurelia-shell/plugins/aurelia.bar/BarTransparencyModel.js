// Pure decision helpers for the transparent bar. Keeping this logic in a plain
// JavaScript module lets the resident QML host and the runtime test suite
// exercise exactly the same code instead of duplicating a regular expression
// or a binding in a static assertion.

// The helper emits `action=halo` when the best available foreground cannot
// clear WCAG AA against the sampled wallpaper. The resident bar never forces
// an opaque surface and never draws a scrim: it strengthens the non-surface
// legibility halo behind the text and icons so the user's transparency choice
// is preserved.
//
// ECMAScript does not implement POSIX character classes such as `[[:space:]]`;
// `\s` is the supported whitespace token. The token is matched on word
// boundaries so a substring such as `not-action=halo` cannot trigger it.
function parseForegroundSignal(detail) {
    var text = String(detail === undefined || detail === null ? "" : detail)
    return {
        strengthenAid: /(^|\s)action=halo(\s|$)/.test(text)
    }
}

// Resolve the rendered transparent-bar state from the requested transparency
// and the helper signal. A requested transparent bar always draws no surface
// and no scrim; it only enables the non-surface legibility halo. The signal
// selects the stronger halo. An opaque bar draws the themed surface, never a
// scrim, and no halo.
function renderState(requestedTransparent, strengthenAid) {
    if (requestedTransparent !== true) {
        return {transparent: false, drawsSurface: true, drawsScrim: false,
            halo: false, haloStrong: false}
    }
    return {transparent: true, drawsSurface: false, drawsScrim: false,
        halo: true, haloStrong: strengthenAid === true}
}

var AureliaBarTransparencyModel = {
    parseForegroundSignal: parseForegroundSignal,
    renderState: renderState
}

if (typeof module !== "undefined" && module.exports) module.exports = AureliaBarTransparencyModel
