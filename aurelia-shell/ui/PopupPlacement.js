.pragma library

// Global popup placement rule.
//
// Every bar-widget popup opens directly beneath (or beside) the widget that
// owns it. No panel chooses its own direction. `align` is the per-widget user
// override:
//
//   "follow" (default) -> centered on the owning widget
//   "left"             -> aligned to the owning widget's leading edge
//   "right"            -> aligned to the owning widget's trailing edge
//   "center"           -> centered on the screen
//
// The cross axis always sits against the bar edge, and the result is clamped
// into the screen with a uniform margin. If the owning widget's position could
// not be resolved, the popup centers on the bar rather than collapsing into a
// corner.

function number(value) {
    var n = Number(value)
    return isFinite(n) ? n : 0
}

function normalizeAlign(value) {
    var align = String(value || "follow")
    return (align === "left" || align === "right" || align === "center") ? align : "follow"
}

function computeOrigin(input) {
    var cfg = input || {}
    var barPosition = String(cfg.barPosition || "top")
    var barSize = number(cfg.barSize)
    var popupWidth = Math.max(1, number(cfg.popupWidth))
    var popupHeight = Math.max(1, number(cfg.popupHeight))
    var screenW = Math.max(1, number(cfg.screenW))
    var screenH = Math.max(1, number(cfg.screenH))
    var margin = number(cfg.margin)
    var align = normalizeAlign(cfg.align)
    var anchored = cfg.anchored !== false

    var anchorX = number(cfg.anchorX)
    var anchorY = number(cfg.anchorY)
    var anchorWidth = number(cfg.anchorWidth)
    var anchorHeight = number(cfg.anchorHeight)

    var vertical = barPosition === "left" || barPosition === "right"
    var x = margin
    var y = margin

    // Cross axis: sit against the bar edge.
    if (barPosition === "bottom") y = screenH - barSize - popupHeight - margin
    else if (barPosition === "left") x = barSize + margin
    else if (barPosition === "right") x = screenW - barSize - popupWidth - margin
    else y = barSize + margin

    // Along axis: follow the owning widget unless the user chose otherwise.
    if (align === "center" || !anchored) {
        if (vertical) y = screenH / 2 - popupHeight / 2
        else x = screenW / 2 - popupWidth / 2
    } else if (vertical) {
        var top = anchorY
        var bottom = anchorY + anchorHeight - popupHeight
        var middle = anchorY + anchorHeight / 2 - popupHeight / 2
        y = align === "left" ? top : (align === "right" ? bottom : middle)
    } else {
        var left = anchorX
        var right = anchorX + anchorWidth - popupWidth
        var centered = anchorX + anchorWidth / 2 - popupWidth / 2
        x = align === "left" ? left : (align === "right" ? right : centered)
    }

    x = Math.max(margin, Math.min(x, screenW - popupWidth - margin))
    y = Math.max(margin, Math.min(y, screenH - popupHeight - margin))
    return { x: Math.round(x), y: Math.round(y) }
}
