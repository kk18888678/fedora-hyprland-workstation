// Pure geometry for the Omarchy-compatible Aurelia bar gestures. Keeping the
// math outside Bar.qml lets tests exercise it without a compositor or pointer
// device and keeps coordinate handling deterministic.

function finiteNumber(value) {
    var number = Number(value)
    return isFinite(number) ? number : null
}

function exceedsDragThreshold(dx, dy, threshold) {
    var x = finiteNumber(dx)
    var y = finiteNumber(dy)
    var limit = finiteNumber(threshold)
    if (x === null || y === null || limit === null || limit < 0) return false
    return Math.abs(x) + Math.abs(y) >= limit
}

function nearestScreenEdge(point, width, height) {
    var x = finiteNumber(point && point.x)
    var y = finiteNumber(point && point.y)
    var screenWidth = finiteNumber(width)
    var screenHeight = finiteNumber(height)
    if (x === null || y === null || screenWidth === null || screenHeight === null ||
        screenWidth <= 0 || screenHeight <= 0) return "top"

    var nx = Math.max(0, Math.min(1, x / screenWidth))
    var ny = Math.max(0, Math.min(1, y / screenHeight))
    var edge = "top"
    var best = ny
    if (1 - ny < best) {
        edge = "bottom"
        best = 1 - ny
    }
    if (nx < best) {
        edge = "left"
        best = nx
    }
    if (1 - nx < best) edge = "right"
    return edge
}

// Resolve the closest insertion edge of any visible slot. `candidates` rows
// contain `{slot, x, y, width, height}` in one shared scene coordinate space.
// Ties retain the existing row order so repeated pointer updates are stable.
function nearestDropTarget(candidates, point, vertical) {
    var rows = Array.isArray(candidates) ? candidates : []
    var axis = finiteNumber(point && (vertical ? point.y : point.x))
    if (axis === null) return null

    var best = null
    var bestDistance = Infinity
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        if (!row || !row.slot) continue
        var start = finiteNumber(vertical ? row.y : row.x)
        var size = finiteNumber(vertical ? row.height : row.width)
        if (start === null || size === null || size <= 0) continue

        var beforeDistance = Math.abs(axis - start)
        var afterDistance = Math.abs(axis - (start + size))
        var after = afterDistance < beforeDistance
        var distance = after ? afterDistance : beforeDistance
        if (distance < bestDistance) {
            best = {slot: row.slot, after: after}
            bestDistance = distance
        }
    }
    return best
}

function placementForDrop(sourceId, targetId, section, after) {
    var source = String(sourceId || "")
    var target = String(targetId || "")
    var region = String(section || "")
    if (source === "" || target === "" || source === target ||
        !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(source) ||
        !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(target) ||
        ["left", "center", "right"].indexOf(region) === -1) return null
    var placement = {section: region}
    placement[after === true ? "after" : "before"] = target
    return placement
}

var AureliaBarInteractionModel = {
    exceedsDragThreshold: exceedsDragThreshold,
    nearestScreenEdge: nearestScreenEdge,
    nearestDropTarget: nearestDropTarget,
    placementForDrop: placementForDrop
}

if (typeof module !== "undefined" && module.exports) module.exports = AureliaBarInteractionModel
