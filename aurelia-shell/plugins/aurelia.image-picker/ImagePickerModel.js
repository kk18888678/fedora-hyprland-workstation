function basename(path) {
    var value = String(path || "")
    var pieces = value.split("/")
    return pieces.length > 0 ? pieces[pieces.length - 1] : ""
}

function nameForPath(path) {
    var name = basename(path)
    return name.replace(/\.[^/.]+$/, "")
}

function labelForPath(path) {
    var value = nameForPath(path).replace(/[-_]+/g, " ")
    return value.replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function safeRowFields(columns) {
    for (var i = 0; i < columns.length; i++) {
        if (String(columns[i] || "").indexOf("\n") !== -1 || String(columns[i] || "").indexOf("\r") !== -1)
            return false
    }
    return true
}

function loadRows(raw, mode) {
    var rows = []
    var seen = {}
    var lines = String(raw || "").split("\n")
    var themeMode = String(mode || "theme") === "theme"

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (!line) continue
        var columns = line.split("\t")
        if (!safeRowFields(columns)) continue

        var entry
        if (themeMode) {
            if (columns.length < 5 || !columns[0]) continue
            if (seen[columns[0]]) continue
            seen[columns[0]] = true
            entry = {
                id: columns[0],
                label: columns[1] || labelForPath(columns[0]),
                filePath: columns[2] || columns[3] || "",
                thumbnailPath: columns[2] || columns[3] || "",
                sourcePath: columns[3] || "",
                current: columns[4] === "1",
                kind: "theme"
            }
        } else {
            if (columns.length < 4 || !columns[0]) continue
            if (seen[columns[0]]) continue
            seen[columns[0]] = true
            entry = {
                id: columns[0],
                label: columns[2] || labelForPath(columns[0]),
                filePath: columns[0],
                thumbnailPath: columns[1] || "",
                sourcePath: columns[0],
                current: columns[3] === "1",
                kind: "background"
            }
        }
        rows.push(entry)
    }
    return rows
}

function itemMatches(entry, filterText) {
    if (!entry) return false
    var needle = String(filterText || "").toLowerCase()
    if (!needle) return true
    var label = String(entry.label || "").toLowerCase()
    var id = String(entry.id || "").toLowerCase()
    var path = String(entry.filePath || "").toLowerCase()
    return label.indexOf(needle) !== -1 || id.indexOf(needle) !== -1 || path.indexOf(needle) !== -1
}

function filteredRows(rows, filterText) {
    var result = []
    var values = Array.isArray(rows) ? rows : []
    for (var i = 0; i < values.length; i++) {
        if (itemMatches(values[i], filterText)) result.push(values[i])
    }
    return result
}

function indexForCurrent(rows) {
    var values = Array.isArray(rows) ? rows : []
    for (var i = 0; i < values.length; i++) {
        if (values[i] && values[i].current === true) return i
    }
    return 0
}

if (typeof module !== "undefined") {
    module.exports = {
        basename: basename,
        nameForPath: nameForPath,
        labelForPath: labelForPath,
        loadRows: loadRows,
        itemMatches: itemMatches,
        filteredRows: filteredRows,
        indexForCurrent: indexForCurrent
    }
}
