// Row parsing and filtering for the Aurelia wallpaper library surface.
//
// The QML never mutates state: rows come from the aurelia-wallpaper command,
// and applying a row always goes back through that command.

function basename(path) {
    var value = String(path || "")
    var pieces = value.split("/")
    return pieces.length > 0 ? pieces[pieces.length - 1] : ""
}

function safeRowFields(columns) {
    for (var i = 0; i < columns.length; i++) {
        if (String(columns[i] || "").indexOf("\n") !== -1 ||
            String(columns[i] || "").indexOf("\r") !== -1) {
            return false
        }
    }
    return true
}

// Optional metadata row emitted by wallhaven searches with --paging:
//   #meta<TAB>page<TAB>lastPage<TAB>total
function parseMeta(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].indexOf("#meta\t") !== 0) continue
        var cols = lines[i].split("\t")
        if (cols.length < 4) continue
        var page = parseInt(cols[1], 10)
        var lastPage = parseInt(cols[2], 10)
        var total = parseInt(cols[3], 10)
        if (isNaN(page) || isNaN(lastPage)) continue
        return {
            page: page > 0 ? page : 1,
            lastPage: lastPage > 0 ? lastPage : 1,
            total: isNaN(total) ? 0 : total
        }
    }
    return null
}

// Append incoming rows, dropping ids already present so a "load more" pass
// cannot duplicate a result that shifted between page requests.
function mergeRows(existing, incoming) {
    var result = Array.isArray(existing) ? existing.slice() : []
    var seen = {}
    for (var i = 0; i < result.length; i++) {
        if (result[i] && result[i].id) seen[result[i].id] = true
    }
    var values = Array.isArray(incoming) ? incoming : []
    for (var j = 0; j < values.length; j++) {
        var row = values[j]
        if (!row || !row.id || seen[row.id]) continue
        seen[row.id] = true
        result.push(row)
    }
    return result
}

// Local rows: path, thumbnail, label, source, current.
function loadLocalRows(raw) {
    var rows = []
    var seen = {}
    var lines = String(raw || "").split("\n")

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (!line) continue
        var columns = line.split("\t")
        if (columns.length < 5 || !columns[0]) continue
        if (!safeRowFields(columns)) continue
        if (seen[columns[0]]) continue
        seen[columns[0]] = true
        rows.push({
            id: columns[0],
            label: columns[2] || basename(columns[0]),
            thumb: columns[1] || columns[0],
            filePath: columns[0],
            source: columns[3] || "",
            current: columns[4] === "1",
            kind: "local"
        })
    }
    return rows
}

// Wallhaven rows: id, thumbnail, resolution, purity, page URL.
function loadWallhavenRows(raw) {
    var rows = []
    var seen = {}
    var lines = String(raw || "").split("\n")

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (!line || line.charAt(0) === "#") continue
        var columns = line.split("\t")
        if (columns.length < 5 || !columns[0]) continue
        if (!safeRowFields(columns)) continue
        if (seen[columns[0]]) continue
        seen[columns[0]] = true
        rows.push({
            id: columns[0],
            label: columns[0] + "  " + columns[2],
            thumb: columns[1] || "",
            resolution: columns[2] || "",
            purity: columns[3] || "",
            page: columns[4] || "",
            filePath: "",
            source: "wallhaven",
            current: false,
            kind: "wallhaven"
        })
    }
    return rows
}

// Catalog rows: id (storage key), thumbnail, label, resolution, purity, page URL.
function loadCatalogRows(raw) {
    var rows = []
    var seen = {}
    var lines = String(raw || "").split("\n")

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (!line) continue
        var columns = line.split("\t")
        if (columns.length < 6 || !columns[0]) continue
        if (!safeRowFields(columns)) continue
        if (seen[columns[0]]) continue
        seen[columns[0]] = true
        rows.push({
            id: columns[0],
            label: columns[2] || columns[0],
            thumb: columns[1] || "",
            resolution: columns[3] || "",
            purity: columns[4] || "",
            page: columns[5] || "",
            filePath: "",
            source: "catalog",
            current: false,
            kind: "catalog"
        })
    }
    return rows
}

function itemMatches(entry, filterText) {
    if (!entry) return false
    var needle = String(filterText || "").toLowerCase()
    if (!needle) return true
    var label = String(entry.label || "").toLowerCase()
    var id = String(entry.id || "").toLowerCase()
    var source = String(entry.source || "").toLowerCase()
    return label.indexOf(needle) !== -1 || id.indexOf(needle) !== -1 ||
        source.indexOf(needle) !== -1
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
        loadLocalRows: loadLocalRows,
        loadWallhavenRows: loadWallhavenRows,
        itemMatches: itemMatches,
        loadCatalogRows: loadCatalogRows,
        filteredRows: filteredRows,
        indexForCurrent: indexForCurrent,
        parseMeta: parseMeta,
        mergeRows: mergeRows
    }
}
