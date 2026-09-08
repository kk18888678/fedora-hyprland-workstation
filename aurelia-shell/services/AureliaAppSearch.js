// Search and ranking helpers for the shared Aurelia application library.
// Pure JavaScript only: discovery, launch, and configuration stay elsewhere.

function entryName(entry) {
    return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
    return String((entry && entry.genericName) || (entry && entry.comment) || "")
}

function keywordText(entry) {
    try {
        if (entry && entry.keywords && typeof entry.keywords.join === "function") {
            return entry.keywords.join(" ")
        }
    } catch (error) {
        // Malformed optional desktop metadata should not break discovery.
    }
    return ""
}

function wordText(value) {
    return String(value || "")
        .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
        .replace(/[._:/\\-]+/g, " ")
        .toLowerCase()
}

function words(value) {
    var parts = wordText(value).split(/[^a-z0-9]+/)
    var result = []
    for (var i = 0; i < parts.length; i++) {
        if (parts[i]) result.push(parts[i])
    }
    return result
}

function entrySearchText(entry) {
    if (!entry) return ""
    return [entry.name, entrySubtext(entry), entry.comment, keywordText(entry), entry.id]
        .join(" ")
        .toLowerCase()
}

function entryAcronym(entry) {
    var values = words(entrySearchText(entry))
    var result = ""
    for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
    return result
}

function termMatches(entry, term) {
    if (!term) return true
    var name = entryName(entry).toLowerCase()
    var id = String((entry && entry.id) || "").toLowerCase()
    var haystack = entrySearchText(entry)
    if (name.indexOf(term) >= 0 || id.indexOf(term) >= 0 || haystack.indexOf(term) >= 0) return true
    return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

function allTermsMatch(entry, query) {
    var terms = String(query || "").toLowerCase().trim().split(/\s+/)
    for (var i = 0; i < terms.length; i++) {
        if (terms[i] && !termMatches(entry, terms[i])) return false
    }
    return true
}

function fuzzyScore(entry, query) {
    var q = String(query || "").trim().toLowerCase()
    if (!q) return 0
    if (!allTermsMatch(entry, q)) return -1

    var name = entryName(entry).toLowerCase()
    var id = String((entry && entry.id) || "").toLowerCase()
    var haystack = entrySearchText(entry)
    var nameIndex = name.indexOf(q)
    var idIndex = id.indexOf(q)
    if (nameIndex === 0) return 10000 - name.length
    if (idIndex === 0) return 9500 - id.length
    if (nameIndex > 0) return 8000 - nameIndex * 10 - name.length
    if (idIndex > 0) return 7600 - idIndex * 10 - id.length

    var hayIndex = haystack.indexOf(q)
    if (hayIndex >= 0) return 6000 - hayIndex

    var acronym = entryAcronym(entry)
    var acronymIndex = acronym.indexOf(q)
    if (acronymIndex === 0) return 5000 - acronym.length
    if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length
    return 4000 - name.length
}

function sortedEntries(values, query, hiddenCallback) {
    var q = String(query || "").trim()
    var rows = []
    for (var i = 0; i < values.length; i++) {
        var entry = values[i]
        if (!entry || entry.noDisplay) continue
        if (hiddenCallback && hiddenCallback(entry)) continue
        if (!entryName(entry)) continue
        var score = fuzzyScore(entry, q)
        if (score < 0) continue
        rows.push({
            entry: entry,
            score: score,
            key: entryName(entry).toLowerCase(),
            id: String(entry.id || "")
        })
    }

    rows.sort(function(left, right) {
        if (q && left.score !== right.score) return right.score - left.score
        if (left.key !== right.key) return left.key < right.key ? -1 : 1
        return left.id < right.id ? -1 : (left.id > right.id ? 1 : 0)
    })
    return rows
}

function rowSearchText(row) {
    if (!row) return ""
    return [row.label, row.subtitle, row.detail, row.category, row.keywords]
        .join(" ")
        .toLowerCase()
}

function rowScore(row, query) {
    var q = String(query || "").trim().toLowerCase()
    if (!q) return Number(row && row.order || 0)
    var text = rowSearchText(row)
    var terms = q.split(/\s+/)
    for (var i = 0; i < terms.length; i++) {
        if (terms[i] && text.indexOf(terms[i]) < 0) return -1
    }
    var label = String(row && row.label || "").toLowerCase()
    var position = label.indexOf(q)
    var base = Number(row && row.sourceScore)
    if (!isFinite(base)) base = 0
    if (position === 0) return 10000 + base - label.length
    if (position > 0) return 8000 + base - position * 10 - label.length
    var textPosition = text.indexOf(q)
    return (textPosition >= 0 ? 6000 : 4000) + base - Math.max(0, textPosition)
}

function sortRows(rows, query) {
    var q = String(query || "").trim()
    var visible = []
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        var score = rowScore(row, q)
        if (score < 0) continue
        var copy = {}
        for (var key in row) copy[key] = row[key]
        copy.score = score
        visible.push(copy)
    }
    visible.sort(function(left, right) {
        if (q && left.score !== right.score) return right.score - left.score
        var leftOrder = Number(left.order || 0)
        var rightOrder = Number(right.order || 0)
        if (leftOrder !== rightOrder) return leftOrder - rightOrder
        var leftLabel = String(left.label || "").toLowerCase()
        var rightLabel = String(right.label || "").toLowerCase()
        if (leftLabel !== rightLabel) return leftLabel < rightLabel ? -1 : 1
        return String(left.id || "") < String(right.id || "") ? -1 : 1
    })
    return visible
}

if (typeof module !== "undefined") {
    module.exports = {
        entryName: entryName,
        entrySubtext: entrySubtext,
        entrySearchText: entrySearchText,
        entryAcronym: entryAcronym,
        fuzzyScore: fuzzyScore,
        sortedEntries: sortedEntries,
        rowScore: rowScore,
        sortRows: sortRows
    }
}
