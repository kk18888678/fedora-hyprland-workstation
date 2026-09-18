// CalendarModel.js — pure calendar week-start helpers.
//
// The calendar layout depends only on which day the week starts on. Keeping
// that arithmetic here (instead of inline in the panel) makes it testable
// without instantiating a popup window.
.pragma library

var ALL_DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

function normalizedWeekStart(weekStart) {
    return Number(weekStart) === 1 ? 1 : 0
}

// Weekday header labels rotated so the configured start day is first.
function weekdayLabels(weekStart) {
    var start = normalizedWeekStart(weekStart)
    var labels = []
    for (var i = 0; i < 7; i++) labels.push(ALL_DAYS[(start + i) % 7])
    return labels
}

// Leading empty cells before the 1st: convert a JavaScript getDay() (0=Sun)
// into an offset from the configured week start.
function firstWeekdayOffset(jsDay, weekStart) {
    var start = normalizedWeekStart(weekStart)
    return ((Number(jsDay) - start) % 7 + 7) % 7
}
