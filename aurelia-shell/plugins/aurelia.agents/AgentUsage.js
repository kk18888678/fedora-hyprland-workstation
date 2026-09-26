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

// Parse `workstation-ai usage` output. A single corrupt record must not hide
// every provider: if the payload is not valid JSON as a whole, salvage the
// individually-parseable records from the `agents` array instead of returning
// an empty list. Any fully malformed input still yields [] so the widget
// self-hides rather than showing garbage.
function extractAgentObjects(text) {
    var raw = String(text || "");
    var marker = raw.indexOf('"agents"');
    if (marker < 0) return [];
    var start = raw.indexOf("[", marker);
    if (start < 0) return [];
    var out = [];
    var depth = 0;
    var inString = false;
    var escaped = false;
    var objectStart = -1;
    for (var i = start + 1; i < raw.length; i++) {
        var ch = raw.charAt(i);
        if (inString) {
            if (escaped) escaped = false;
            else if (ch === "\\") escaped = true;
            else if (ch === '"') inString = false;
            continue;
        }
        if (ch === '"') { inString = true; continue; }
        if (ch === "{") {
            if (depth === 0) objectStart = i;
            depth += 1;
            continue;
        }
        if (ch === "}") {
            if (depth > 0) depth -= 1;
            if (depth === 0 && objectStart >= 0) {
                try {
                    var candidate = JSON.parse(raw.slice(objectStart, i + 1));
                    if (candidate && typeof candidate === "object" && !Array.isArray(candidate)) {
                        out.push(candidate);
                    }
                } catch (e) {
                    console.warn("[AGENTS] usage_parse_record_skipped reason=" +
                        String(e && e.message ? e.message : e));
                }
                objectStart = -1;
            }
            continue;
        }
        if (ch === "]" && depth === 0) break;
    }
    return out;
}

function parseRecords(text) {
    var raw = String(text || "");
    var data;
    try {
        data = JSON.parse(raw);
    } catch (e) {
        var salvaged = extractAgentObjects(raw);
        if (salvaged.length > 0) {
            console.warn("[AGENTS] usage_parse_salvaged count=" + salvaged.length);
            return salvaged;
        }
        console.warn("[AGENTS] usage_parse_failed reason=" + String(e && e.message ? e.message : e));
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

// Normalise the 7-day window into bar fractions. `tokens` is the
// cache-inclusive total; `messageCount` is the deprecated alias emitted by the
// collectors for the current panel. Zero-usage days report `hasUsage: false`
// so the chart can emit no bar rather than a minimum-height stub.
function recentBars(recentDays) {
    var days = Array.isArray(recentDays) ? recentDays : [];
    var values = days.map(function (day) {
        if (!day) return 0;
        if (day.tokens !== undefined && day.tokens !== null) return number(day.tokens);
        return number(day.messageCount);
    });
    var max = 1;
    values.forEach(function (value) { if (value > max) max = value; });
    return days.map(function (day, index) {
        return {
            date: String((day && day.date) || ""),
            tokens: values[index],
            fraction: values[index] / max,
            hasUsage: values[index] > 0
        };
    });
}

// Bar geometry for the 7-day chart. Zero-usage days emit no bar at all
// (`barHeight` 0) instead of the legacy `Math.max(2, ...)` 2px stub.
function dayChartBars(recentDays, maxBarHeight) {
    var bars = recentBars(recentDays);
    var height = number(maxBarHeight);
    if (!(height > 0)) height = 0;
    return bars.map(function (bar) {
        return {
            date: bar.date,
            tokens: bar.tokens,
            fraction: bar.fraction,
            hasUsage: bar.hasUsage,
            barHeight: bar.hasUsage ? Math.max(1, height * bar.fraction) : 0
        };
    });
}

function clamp(value, lo, hi) {
    return Math.max(lo, Math.min(hi, value));
}

// `limits[].percent` is the fraction of the window already used (0..1). The
// binding limit is the one most likely to stop the next account, which is not
// simply the highest percent: a window that is nearly drained is about to
// reset, while a long window that is off-pace will lock the account out
// longer. Score by `percent - elapsedFraction` and, on a tie, prefer the
// longer window. Fall back to the raw percent when the window duration or
// reset time is missing.
var PACE_EPSILON = 1e-6;

function limitScore(limit, nowMs) {
    var percent = Number(limit && limit.percent);
    if (!isFinite(percent)) return NaN;
    var elapsed = elapsedFraction(limit, nowMs);
    if (!isFinite(elapsed)) return percent;
    return percent - elapsed;
}

function bindingLimit(record, nowMs) {
    var windows = (record && record.limits) || [];
    var best = null;
    var bestScore = -Infinity;
    var bestMinutes = -Infinity;
    for (var i = 0; i < windows.length; i++) {
        var window = windows[i];
        var percent = Number(window && window.percent);
        if (!isFinite(percent)) continue;
        var score = limitScore(window, nowMs);
        var minutes = Number(window && window.windowMinutes);
        if (!isFinite(minutes)) minutes = -1;
        if (best === null || score > bestScore + PACE_EPSILON) {
            best = window;
            bestScore = score;
            bestMinutes = minutes;
        } else if (Math.abs(score - bestScore) <= PACE_EPSILON && minutes > bestMinutes) {
            // Tie on pace: the longer window locks the account out longest.
            best = window;
            bestMinutes = minutes;
        }
    }
    return best;
}

// Backwards-compatible alias: the current widget still calls bindingWindow.
function bindingWindow(record, nowMs) {
    return bindingLimit(record, nowMs);
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

// Freshness is derived from the `updatedAt` timestamp every collector emits.
// A record without a parseable timestamp has unknown age, not zero age.
function updatedAtMs(record) {
    if (!record || !record.updatedAt) return NaN;
    var parsed = Date.parse(String(record.updatedAt));
    return isFinite(parsed) ? parsed : NaN;
}

function recordAgeMs(record, nowMs) {
    var updated = updatedAtMs(record);
    if (!isFinite(updated) || !isFinite(nowMs)) return NaN;
    return Math.max(0, nowMs - updated);
}

// Unknown freshness is not treated as stale; callers decide a max age.
function isRecordStale(record, nowMs, maxAgeMs) {
    var age = recordAgeMs(record, nowMs);
    if (!isFinite(age)) return false;
    var maxAge = Number(maxAgeMs);
    if (!isFinite(maxAge) || maxAge <= 0) return false;
    return age > maxAge;
}

function freshnessText(record, nowMs) {
    var age = recordAgeMs(record, nowMs);
    if (!isFinite(age)) return "";
    if (age < 60000) return "just now";
    return formatDuration(age) + " ago";
}

function heroMeta(record) {
    if (!record) return "";
    var plan = String(record.tierLabel || "");
    if (plan === "" && record.subscription) plan = String(record.subscription.plan || "");
    if (plan !== "") return plan.charAt(0).toUpperCase() + plan.slice(1);
    if (String(record.usageStatusText || "") !== "") return String(record.usageStatusText);
    return "Subscription";
}

// "Max · USD 20.00 · monthly · Renews 2026-10-18 · in 29 days" from the
// user-owned subscription metadata. Targets cost, currency and cycle as well
// as the renewal date; empty parts are omitted.
function billingText(record) {
    var sub = record && record.subscription;
    if (!sub) return "";
    var parts = [];
    if (String(sub.plan || "") !== "") parts.push(String(sub.plan));
    if (sub.cost !== undefined && sub.cost !== null && String(sub.cost) !== "" && isFinite(Number(sub.cost))) {
        parts.push(String(sub.currency || "USD") + " " + Number(sub.cost).toFixed(2));
    }
    if (String(sub.cycle || "") !== "") parts.push(String(sub.cycle));
    if (sub.renew) {
        var days = Number(sub.daysLeft);
        if (!isFinite(days)) {
            parts.push("Renews " + String(sub.renew));
        } else if (days < 0) {
            parts.push("Renewal date passed · " + String(sub.renew));
        } else {
            var when = days === 0 ? "today" : (days === 1 ? "in 1 day" : "in " + days + " days");
            parts.push("Renews " + String(sub.renew) + " · " + when);
        }
    }
    return parts.join(" · ");
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
    for (var i = 0; i < days.length; i++) {
        var day = days[i] || {};
        var value = (day.tokens !== undefined && day.tokens !== null)
            ? number(day.tokens) : number(day.messageCount);
        peak = Math.max(peak, value);
    }
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
        var billable = input + output;
        var cache = cacheRead + cacheWrite;
        rows.push({
            name: String(id),
            total: billable + cache,
            billableTokens: billable,
            cacheTokens: cache,
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

// Bar-wide status: the worst severity across the binding limit of every ready
// agent, or "unknown" when no ready agent reports a limit.
function overallSeverity(records, nowMs) {
    var ready = readyAgents(records);
    var severity = "unknown";
    for (var i = 0; i < ready.length; i++) {
        var limit = bindingLimit(ready[i], nowMs);
        if (!limit) continue;
        var current = severityForLimit(limit);
        if (current === "critical") return "critical";
        if (current === "warn") severity = "warn";
        else if (severity !== "warn") severity = "ok";
    }
    return severity;
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
// means the account is burning faster than the window is draining. Exactly on
// pace is reported as `onPace` rather than as "ahead".
function paceInfo(limit, nowMs) {
    var percent = Number(limit && limit.percent);
    var elapsed = elapsedFraction(limit, nowMs);
    if (!isFinite(percent) || !isFinite(elapsed)) return null;
    var delta = percent - elapsed;
    var onPace = Math.abs(delta) <= PACE_EPSILON;
    return {
        used: percent,
        elapsed: elapsed,
        delta: delta,
        onPace: onPace,
        behind: !onPace && delta > 0,
        ahead: !onPace && delta < 0,
        state: onPace ? "on-pace" : (delta > 0 ? "behind" : "ahead"),
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
