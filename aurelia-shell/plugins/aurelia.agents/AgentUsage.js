.pragma library

// Pure helpers for the Agents bar widget/panel. Kept free of QML so the
// record-contract projection can be unit tested under node.

function number(value) {
    var n = Number(value);
    return isFinite(n) ? n : 0;
}

function formatTokens(value) {
    var n = Math.max(0, number(value));
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "k";
    return String(Math.round(n));
}

// Parse `workstation-ai usage` output. Any malformed input yields [] so the
// widget self-hides rather than showing garbage.
function parseRecords(text) {
    var data;
    try {
        data = JSON.parse(String(text || ""));
    } catch (e) {
        return [];
    }
    var agents = data && data.agents;
    if (!Array.isArray(agents)) return [];
    return agents.filter(function (agent) {
        return agent && typeof agent === "object" && !Array.isArray(agent);
    });
}

function readyAgents(records) {
    return (records || []).filter(function (agent) {
        return agent && agent.ready === true;
    });
}

// Agents the user actually has: an installed/used tool is listed even before it
// has any recorded usage, so the panel can explain the empty state.
function detectedAgents(records) {
    return (records || []).filter(function (agent) {
        return agent && (agent.detected === true || agent.ready === true);
    });
}

function todayTotal(records) {
    var total = 0;
    (records || []).forEach(function (agent) {
        total += number(agent && agent.todayTotalTokens);
    });
    return total;
}

function tierLabel(record) {
    var tier = record && record.tierLabel;
    return tier ? String(tier) : "";
}

function modelTotal(bucket) {
    var b = bucket || {};
    return number(b.inputTokens) + number(b.outputTokens) +
        number(b.cacheReadInputTokens) + number(b.cacheCreationInputTokens);
}

function sortedModels(modelUsage) {
    var list = [];
    var usage = modelUsage || {};
    for (var key in usage) {
        if (!Object.prototype.hasOwnProperty.call(usage, key)) continue;
        list.push({ name: String(key), total: modelTotal(usage[key]) });
    }
    list.sort(function (a, b) { return b.total - a.total; });
    return list;
}

// Normalise the 7-day window into bar fractions. `messageCount` is a token
// total despite the legacy field name shared with synced snapshots.
function recentBars(recentDays) {
    var days = Array.isArray(recentDays) ? recentDays : [];
    var values = days.map(function (day) { return number(day && day.messageCount); });
    var max = 1;
    values.forEach(function (value) { if (value > max) max = value; });
    return days.map(function (day, index) {
        return {
            date: String((day && day.date) || ""),
            tokens: values[index],
            fraction: values[index] / max
        };
    });
}

function clamp(value, lo, hi) {
    return Math.max(lo, Math.min(hi, value));
}

// `limits[].percent` is the fraction of the window already used (0..1).
function bindingWindow(record) {
    var windows = (record && record.limits) || [];
    var best = null;
    for (var i = 0; i < windows.length; i++) {
        var percent = Number(windows[i] && windows[i].percent);
        if (!isFinite(percent)) continue;
        if (!best || percent > Number(best.percent)) best = windows[i];
    }
    return best;
}

function resetMsFor(window, nowMs) {
    if (!window || !window.resetsAt) return -1;
    var parsed = Date.parse(String(window.resetsAt));
    if (!isFinite(parsed)) return -1;
    return parsed - nowMs;
}

function formatDuration(ms) {
    if (!(ms > 0)) return "now";
    var minutes = Math.floor(ms / 60000);
    var hours = Math.floor(minutes / 60);
    var days = Math.floor(hours / 24);
    if (days > 0) return days + "d " + (hours % 24) + "h";
    if (hours > 0) return hours + "h " + (minutes % 60) + "m";
    return Math.max(1, minutes) + "m";
}

function heroMeta(record) {
    if (!record) return "";
    if (String(record.usageStatusText || "") !== "") return String(record.usageStatusText);
    var tier = String(record.tierLabel || "");
    if (tier === "") return "Subscription";
    return tier.charAt(0).toUpperCase() + tier.slice(1);
}

function todayDate(nowMs) {
    var now = new Date(nowMs);
    return now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") +
        "-" + String(now.getDate()).padStart(2, "0");
}

function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00");
    if (isNaN(parsed.getTime())) return String(date || "");
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()];
}

function dayLabel(date, today) {
    return today ? "Today" : dayName(date);
}

function weekPeak(record) {
    var days = (record && record.recentDays) || [];
    var peak = 0;
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, number(days[i] && days[i].messageCount));
    return peak;
}

function modelRows(record, limit) {
    var usage = (record && record.modelUsage) || {};
    var rows = [];
    for (var id in usage) {
        if (!Object.prototype.hasOwnProperty.call(usage, id)) continue;
        var bucket = usage[id] || {};
        var input = number(bucket.inputTokens);
        var output = number(bucket.outputTokens);
        var cacheRead = number(bucket.cacheReadInputTokens);
        var cacheWrite = number(bucket.cacheCreationInputTokens);
        rows.push({
            name: String(id),
            total: input + output + cacheRead + cacheWrite,
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite
        });
    }
    rows.sort(function (a, b) { return b.total - a.total; });
    return rows.slice(0, limit || 4);
}

// Compare live rate-limit windows against the previous observation and return
// the notifications the user should see: a window that reset (its resetsAt
// moved) and a window that just crossed the near-exhausted threshold. The
// returned state must be fed back on the next call so transitions, not steady
// states, produce notifications.
function limitTransitions(records, previousState) {
    var state = previousState || {};
    var next = {};
    var notifications = [];
    var ready = readyAgents(records);
    for (var i = 0; i < ready.length; i++) {
        var agent = ready[i];
        var limits = (agent && agent.limits) || [];
        for (var j = 0; j < limits.length; j++) {
            var limit = limits[j] || {};
            var resetsAt = String(limit.resetsAt || "");
            if (resetsAt === "") continue;
            var key = String(agent.id) + "|" + String(limit.label || "");
            var previous = state[key];
            var percent = Number(limit.percent);
            var alertedHigh = previous ? previous.alertedHigh === true : false;
            var name = String(agent.name || agent.id);
            var label = String(limit.label || "Limit");

            if (previous && String(previous.resetsAt || "") !== "" && previous.resetsAt !== resetsAt) {
                notifications.push({
                    title: name + " limit reset",
                    body: label + " reset · " + Math.max(0, Math.round((1 - percent) * 100)) + "% available"
                });
                alertedHigh = false;
            }
            if (previous && !alertedHigh && isFinite(percent) && percent >= 0.9) {
                notifications.push({
                    title: name + " limit nearly exhausted",
                    body: label + " is at " + Math.round(percent * 100) + "% used"
                });
                alertedHigh = true;
            }
            next[key] = { resetsAt: resetsAt, alertedHigh: alertedHigh };
        }
    }
    return { state: next, notifications: notifications };
}
