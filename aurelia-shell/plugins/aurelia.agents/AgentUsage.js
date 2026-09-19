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

// "Renews 2026-10-18 · in 29 days" from the user-owned subscription metadata.
function billingText(record) {
    var sub = record && record.subscription;
    if (!sub || !sub.renew) return "";
    var days = Number(sub.daysLeft);
    if (!isFinite(days)) return "Renews " + String(sub.renew);
    if (days < 0) return "Renewal date passed · " + String(sub.renew);
    var when = days === 0 ? "today" : (days === 1 ? "in 1 day" : "in " + days + " days");
    return "Renews " + String(sub.renew) + " · " + when;
}

// Notify once per day while a subscription is within its reminder window.
function renewalReminders(records, previousState, todayText) {
    var state = previousState || {};
    var next = {};
    var notifications = [];
    var ready = readyAgents(records);
    for (var i = 0; i < ready.length; i++) {
        var agent = ready[i];
        var sub = agent && agent.subscription;
        if (!sub || !sub.renew) continue;
        var days = Number(sub.daysLeft);
        if (!isFinite(days)) continue;
        var reminderDays = Number(sub.reminderDays);
        if (!isFinite(reminderDays)) reminderDays = 3;
        var key = "renew|" + String(agent.id);
        var previous = state[key];
        if (days >= 0 && days <= reminderDays && previous !== todayText) {
            notifications.push({
                title: String(agent.name || agent.id) + " renewal",
                body: "Renews " + String(sub.renew) +
                    (days === 0 ? " (today)" : " in " + days + " day" + (days === 1 ? "" : "s"))
            });
            next[key] = todayText;
        } else {
            next[key] = previous;
        }
    }
    return { state: next, notifications: notifications };
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
// moved) and a window that crossed into warn or critical severity. The
// returned state must be fed back on the next call so transitions, not steady
// states, produce notifications; the first observation only establishes a
// baseline.
var DEFAULT_WARN_PCT = 75
var DEFAULT_CRITICAL_PCT = 90

function severityFor(pct, warn, critical) {
    var w = isFinite(warn) ? Number(warn) : DEFAULT_WARN_PCT;
    var c = isFinite(critical) ? Number(critical) : DEFAULT_CRITICAL_PCT;
    if (w >= c) w = c;
    if (!isFinite(pct)) return "ok";
    if (pct >= c) return "critical";
    if (pct >= w) return "warn";
    return "ok";
}

function severityForLimit(limit, warn, critical) {
    var percent = Number(limit && limit.percent);
    return severityFor(isFinite(percent) ? percent * 100 : NaN, warn, critical);
}

// Fraction of the limit window that has already elapsed, from its reset time
// and duration. NaN when the collector did not report a window duration.
function elapsedFraction(limit, nowMs) {
    var windowMinutes = Number(limit && limit.windowMinutes);
    var resetsAt = Date.parse(String((limit && limit.resetsAt) || ""));
    if (!isFinite(resetsAt) || !isFinite(nowMs)) return NaN;
    if (!isFinite(windowMinutes) || windowMinutes <= 0) return NaN;
    var windowMs = windowMinutes * 60000;
    var remaining = Math.max(0, resetsAt - nowMs);
    return clamp(1 - remaining / windowMs, 0, 1);
}

// Pace compares the used fraction against the elapsed fraction: positive delta
// means the account is burning faster than the window is draining.
function paceInfo(limit, nowMs) {
    var percent = Number(limit && limit.percent);
    var elapsed = elapsedFraction(limit, nowMs);
    if (!isFinite(percent) || !isFinite(elapsed)) return null;
    return {
        used: percent,
        elapsed: elapsed,
        delta: percent - elapsed,
        behind: percent > elapsed,
        expectedUsed: elapsed
    };
}

function limitTransitions(records, previousState, thresholds) {
    var state = previousState || {};
    var opts = thresholds || {};
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
            var severity = severityForLimit(limit, opts.warn, opts.critical);
            var previousSeverity = previous ? String(previous.severity || "ok") : "ok";
            var name = String(agent.name || agent.id);
            var label = String(limit.label || "Limit");

            if (previous && String(previous.resetsAt || "") !== "" && previous.resetsAt !== resetsAt) {
                notifications.push({
                    title: name + " limit reset",
                    body: label + " reset · " + Math.max(0, Math.round((1 - percent) * 100)) + "% available"
                });
                previousSeverity = "ok";
            }
            if (previous && severity !== "ok" && severity !== previousSeverity) {
                notifications.push({
                    title: name + " limit " + (severity === "critical" ? "critical" : "warning"),
                    body: label + " is at " + Math.round(percent * 100) + "% used"
                });
            }
            next[key] = { resetsAt: resetsAt, severity: severity };
        }
    }
    return { state: next, notifications: notifications };
}
