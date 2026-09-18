// ClockFormat.js — pure clock format builder.
//
// The bar clock layout is an Aurelia preference. Keeping the preset -> format
// mapping here makes every option testable without instantiating the widget.
.pragma library

function timeFormat(hour24, seconds) {
    return (hour24 ? "HH" : "h") + ":mm" + (seconds ? ":ss" : "") + (hour24 ? "" : " AP")
}

function buildFormat(preset, hour24, seconds) {
    var time = timeFormat(hour24, seconds)
    switch (String(preset || "")) {
    case "time_only":
        return time
    case "month_day_only":
        return "MMM d"
    case "month_day_time":
        return "MMM d, " + time
    case "weekday_day_month_time":
        return "ddd d MMM, " + time
    case "full_weekday_month_day_time":
        return "dddd, MMM d, " + time
    case "month_day_weekday_time":
    default:
        return "MMM d, dddd " + time
    }
}
