// Pure decision helpers for the transparent bar. Keeping this logic in a plain
// JavaScript module lets the resident QML host and the runtime test suite
// exercise exactly the same code instead of duplicating a regular expression
// or a binding in a static assertion.

// The helper emits `action=opaque` when the best available foreground cannot
// clear WCAG AA against the scrim-composited bar strip. The resident bar does
// not force an opaque surface in response; it strengthens the legibility scrim
// so the user's transparency choice is preserved.
//
// ECMAScript does not implement POSIX character classes such as `[[:space:]]`;
// `\s` is the supported whitespace token. The token is matched on word
// boundaries so a substring such as `not-action=opaque` cannot trigger it.
function parseForegroundSignal(detail) {
    var text = String(detail === undefined || detail === null ? "" : detail)
    return {
        strengthenAid: /(^|\s)action=opaque(\s|$)/.test(text)
    }
}

// Resolve the rendered surface state from the requested transparency, the
// helper signal, and the theme scrim tokens. A requested transparent bar is
// always transparent: the signal only selects the stronger scrim alpha.
function renderState(requestedTransparent, strengthenAid, scrimAlpha, scrimStrongAlpha) {
    if (requestedTransparent !== true) return {transparent: false, scrimAlpha: 0}
    var alpha = strengthenAid === true ? Number(scrimStrongAlpha) : Number(scrimAlpha)
    if (!isFinite(alpha) || alpha < 0) alpha = 0
    if (alpha > 1) alpha = 1
    return {transparent: true, scrimAlpha: alpha}
}

var AureliaBarTransparencyModel = {
    parseForegroundSignal: parseForegroundSignal,
    renderState: renderState
}

if (typeof module !== "undefined" && module.exports) module.exports = AureliaBarTransparencyModel
