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

// Project one model bucket map into sorted rows. Accepts both the full
// `modelUsage` buckets and the compact `todayTokensByModel` buckets, preferring
// the explicit billable/cache/total split the collectors now emit.
function modelRowsFrom(usage, limit) {
    var buckets = usage || {};
    var rows = [];
    for (var id in buckets) {
        if (!Object.prototype.hasOwnProperty.call(buckets, id)) continue;
        var bucket = buckets[id] || {};
        var input = number(bucket.inputTokens);
        var output = number(bucket.outputTokens);
        var cacheRead = number(bucket.cacheReadInputTokens);
        var cacheWrite = number(bucket.cacheCreationInputTokens);
        var billable = number(bucket.billableTokens);
        var cache = number(bucket.cacheTokens);
        if (billable === 0 && cache === 0) {
            billable = input + output;
            cache = cacheRead + cacheWrite;
        }
        var total = number(bucket.totalTokens);
        if (total === 0) total = billable + cache;
        rows.push({
            name: String(id),
            total: total,
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

// All-time model breakdown from the `modelUsage` buckets.
function modelRows(record, limit) {
    return modelRowsFrom((record && record.modelUsage) || {}, limit || 4);
}

// Today-first model breakdown from `todayTokensByModel`.
function todayModels(record, limit) {
    return modelRowsFrom((record && record.todayTokensByModel) || {}, limit || 4);
}

// Per-day token value, preferring the new `tokens` key over the legacy alias.
function dayTokens(day) {
    if (!day) return 0;
    if (day.tokens !== undefined && day.tokens !== null) return number(day.tokens);
    return number(day.messageCount);
}

// Today's billable/cache/count projection. `noun` is the provider-specific
// count noun the collector advertises; `sessions` is reported separately so a
// provider that counts sessions does not present the same number twice. When a
// partial record has only `todayTotalTokens`, that available total is shown as
// billable rather than a fabricated zero, so usable data is never suppressed.
function todayUsage(record) {
    var billableRaw = record ? record.todayBillableTokens : undefined;
    var cacheRaw = record ? record.todayCacheTokens : undefined;
    var billable = (billableRaw === undefined || billableRaw === null || String(billableRaw) === "")
        ? number(record && record.todayTotalTokens)
        : number(billableRaw);
    var cache = (cacheRaw === undefined || cacheRaw === null || String(cacheRaw) === "")
        ? 0 : number(cacheRaw);
    return {
        billable: billable,
        cache: cache,
        count: number(record && record.todayPrompts),
        noun: String((record && record.todayLabel) || "sessions"),
        sessions: number(record && record.todaySessions)
    };
}

// Plan label for the hero: an explicit tier wins, then the user-owned
// subscription plan, then the collector's generic status text. This is the
// ONLY place the generic status is allowed to stand in for a plan, which keeps
// "Local usage only" from being repeated in the state banner.
function planLabel(record) {
    if (!record) return "";
    var tier = String(record.tierLabel || "");
    if (tier !== "") return tier.charAt(0).toUpperCase() + tier.slice(1);
    if (record.subscription && String(record.subscription.plan || "") !== "") {
        var plan = String(record.subscription.plan);
        return plan.charAt(0).toUpperCase() + plan.slice(1);
    }
    return String(record.usageStatusText || "");
}

// Freshness/stale pill derived from `updatedAt`. An unparseable timestamp is
// reported as unknown freshness, never as fresh.
function freshnessPill(record, nowMs, staleMs) {
    var age = recordAgeMs(record, nowMs);
    var stale = isRecordStale(record, nowMs, staleMs);
    if (!isFinite(age)) return { text: stale ? "Stale" : "Freshness unknown", stale: stale, known: false };
    var text = freshnessText(record, nowMs);
    return { text: stale ? "Stale · " + text : text, stale: stale, known: true };
}

// Absolute reset time in deterministic UTC so the panel can show a fixed clock
// time next to the relative countdown without depending on the host timezone.
function formatResetAbsolute(resetsAt) {
    if (!resetsAt) return "";
    var parsed = Date.parse(String(resetsAt));
    if (!isFinite(parsed)) return "";
    var date = new Date(parsed);
    var iso = date.toISOString();
    return iso.slice(0, 10) + " " + iso.slice(11, 16) + " UTC";
}

// Human pace state, including the explicit on-pace case.
function paceLabel(pace) {
    if (!pace) return "";
    if (pace.onPace) return "on pace";
    return pace.behind ? "behind pace" : "ahead of pace";
}

// The worst window for a provider, used to label the provider switch.
function providerWorstLabel(record, nowMs) {
    var limit = bindingLimit(record, nowMs);
    if (!limit) return "";
    var label = String(limit.label || "Limit");
    var percent = Number(limit.percent);
    if (!isFinite(percent)) return label;
    return label + " " + Math.round(percent * 100) + "%";
}

// A collector error is explicit: either an `error` flag, or an auth help
// string, or an unavailable/failed status. The configured-but-unused account
// message is a normal empty state, not an error.
function recordHasError(record) {
    if (!record) return false;
    if (record.error === true) return true;
    if (String(record.authHelpText || "") !== "") return true;
    var status = String(record.usageStatusText || "");
    if (status === "" || status === "Local usage only" ||
        status === "Account configured · no usage yet") return false;
    return /unavailable|failed|failure|error|expired|invalid|denied|unauthor|not found/i.test(status);
}

// Per-provider state for the panel: loading/empty/unknown/ready/warn/critical/
// stale/error/rate-limited. Error and rate-limit take precedence over stale so
// a failure is never hidden behind old data, and a stale number is dimmed
// rather than presented as live.
function providerState(record, nowMs, opts) {
    opts = opts || {};
    if (opts.backendError) {
        return { key: "error", severity: "error", stale: false, dot: true, opacity: 1.0,
            tint: "error", message: String(opts.backendError), help: "", retry: true };
    }
    if (!record) {
        if (opts.loading) {
            return { key: "loading", severity: "unknown", stale: false, dot: false, opacity: 0.5,
                tint: "textMuted", message: "Loading usage…", help: "", retry: false };
        }
        return { key: "empty", severity: "unknown", stale: false, dot: false, opacity: 0.5,
            tint: "textMuted", message: "No provider detected", help: "", retry: false };
    }
    if (record.ready !== true && String(record.usageStatusText || "") === "Account configured · no usage yet") {
        return { key: "empty", severity: "unknown", stale: false, dot: false, opacity: 0.5,
            tint: "textMuted", message: "Account configured · no usage yet", help: "", retry: false };
    }
    if (record.retryAdvised === true) {
        return { key: "rate-limited", severity: "warn", stale: false, dot: false, opacity: 1.0,
            tint: "warning", message: String(record.usageStatusText || "Rate limited"),
            help: String(record.authHelpText || ""), retry: true };
    }
    if (recordHasError(record)) {
        return { key: "error", severity: "error", stale: false, dot: true, opacity: 1.0,
            tint: "error", message: String(record.usageStatusText || "Provider error"),
            help: String(record.authHelpText || ""), retry: true };
    }
    var limit = bindingLimit(record, nowMs);
    var severity = limit ? severityForLimit(limit) : "unknown";
    var stale = isRecordStale(record, nowMs, opts.staleMs);
    if (severity === "unknown") {
        return { key: "unknown", severity: "unknown", stale: stale, dot: false,
            opacity: stale ? 0.6 : 0.5, tint: "textMuted",
            message: "No live limit reported", help: "", retry: false };
    }
    var tint = severity === "critical" ? "error" : (severity === "warn" ? "warning" : "barForeground");
    return {
        key: stale ? "stale" : (severity === "ok" ? "ready" : severity),
        severity: severity,
        stale: stale,
        dot: !stale && severity !== "ok",
        opacity: stale ? 0.6 : 1.0,
        tint: tint,
        message: "",
        help: "",
        retry: false
    };
}

// Whole-bar state: the worst provider state with the same tint+dot+opacity
// encoding the widget renders.
function barState(records, nowMs, opts) {
    opts = opts || {};
    var list = detectedAgents(records);
    if (opts.backendError) {
        return { key: "error", severity: "error", stale: false, dot: true, opacity: 1.0, tint: "error" };
    }
    if (opts.loading && list.length === 0) {
        return { key: "loading", severity: "unknown", stale: false, dot: false, opacity: 0.5, tint: "textMuted" };
    }
    if (list.length === 0) {
        return { key: "empty", severity: "unknown", stale: false, dot: false, opacity: 0.5, tint: "textMuted" };
    }
    var ready = readyAgents(list);
    if (ready.length === 0) {
        return { key: "unknown", severity: "unknown", stale: false, dot: false, opacity: 0.5, tint: "textMuted" };
    }
    for (var i = 0; i < ready.length; i++) {
        if (ready[i].retryAdvised === true) {
            return { key: "rate-limited", severity: "warn", stale: false, dot: false, opacity: 1.0, tint: "warning" };
        }
    }
    for (var j = 0; j < ready.length; j++) {
        if (recordHasError(ready[j])) {
            return { key: "error", severity: "error", stale: false, dot: true, opacity: 1.0, tint: "error" };
        }
    }
    var severity = overallSeverity(list, nowMs);
    if (severity === "unknown") {
        return { key: "unknown", severity: "unknown", stale: false, dot: false, opacity: 0.5, tint: "textMuted" };
    }
    var stale = false;
    for (var k = 0; k < ready.length; k++) {
        if (isRecordStale(ready[k], nowMs, opts.staleMs)) { stale = true; break; }
    }
    var tint = severity === "critical" ? "error" : (severity === "warn" ? "warning" : "barForeground");
    if (stale) {
        return { key: "stale", severity: severity, stale: true, dot: false, opacity: 0.6, tint: tint };
    }
    return {
        key: severity === "ok" ? "ready" : severity,
        severity: severity,
        stale: false,
        dot: severity !== "ok",
        opacity: 1.0,
        tint: tint
    };
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

// Cost/currency/cycle only. The hero shows the plan separately, so this never
// repeats it; renewal is owned by the subscription section.
function billingSummary(record) {
    var sub = record && record.subscription;
    if (!sub) return "";
    var parts = [];
    if (sub.cost !== undefined && sub.cost !== null && String(sub.cost) !== "" &&
        isFinite(Number(sub.cost))) {
        parts.push(String(sub.currency || "USD") + " " + Number(sub.cost).toFixed(2));
    }
    if (String(sub.cycle || "") !== "") parts.push(String(sub.cycle));
    return parts.join(" · ");
}

// Explicit plan/cost/cycle/renewal lines for the subscription section. Returns
// [] when the user has not recorded a subscription, so the section self-hides.
function subscriptionRows(record) {
    var sub = record && record.subscription;
    if (!sub) return [];
    var rows = [];
    if (String(sub.plan || "") !== "") rows.push("Plan · " + String(sub.plan));
    var cost = billingSummary(record);
    if (cost !== "") rows.push("Billing · " + cost);
    if (sub.renew) {
        var days = Number(sub.daysLeft);
        var renewal = "Renews " + String(sub.renew);
        if (isFinite(days)) {
            renewal += days < 0 ? " · passed"
                : (days === 0 ? " · today" : (days === 1 ? " · in 1 day" : " · in " + days + " days"));
        }
        rows.push(renewal);
    }
    return rows;
}

// ---------------------------------------------------------------------------
// Consolidated usage dashboard projection
//
// The dashboard replaces the one-account-at-a-time switch with a pin-stable
// matrix. Rows are accounts in a FIXED deterministic order (name ascending,
// id tiebreak) and never reorder by severity: jumping rows destroy comparison
// and make keyboard selection unpredictable. Columns are the canonical 5h /
// weekly / 30-day rolling windows plus today's billable tokens. Window
// classification is numeric from `windowMinutes` only; a window whose
// duration is missing, zero or non-finite is `unknown` and can never be
// forced into a canonical column. A provider that reports no limits renders
// `—`, never a fabricated `0%`.
// ---------------------------------------------------------------------------

var CANONICAL_WINDOW_ORDER = ["five_hour", "week", "month"];
var CANONICAL_WINDOW_MINUTES = { five_hour: 300, week: 10080, month: 43200 };
var CANONICAL_COLUMN_LABEL = { five_hour: "5H", week: "WEEK", month: "MONTH" };
var CANONICAL_WINDOW_NAME = { five_hour: "5h", week: "Weekly", month: "30-day" };

// Numeric classification from `windowMinutes` alone. 300 -> five_hour,
// 10080 -> week, 43200 -> month, any other present value -> other. A missing,
// zero or NaN duration is `unknown` because the window cannot be placed on the
// time axis at all.
function classifyWindow(limit) {
    if (!limit) return "unknown";
    var raw = limit.windowMinutes;
    if (raw === undefined || raw === null || raw === "") return "unknown";
    var minutes = Number(raw);
    if (!isFinite(minutes) || minutes === 0) return "unknown";
    if (minutes === 300) return "five_hour";
    if (minutes === 10080) return "week";
    if (minutes === 43200) return "month";
    return "other";
}

function canonicalWindowOrder() {
    return CANONICAL_WINDOW_ORDER.slice();
}

function windowColumnLabel(windowClass) {
    return CANONICAL_COLUMN_LABEL[windowClass] || "";
}

function defaultWindowName(windowClass) {
    return CANONICAL_WINDOW_NAME[windowClass] || "Window";
}

// Human description used for the matrix column tooltips. MONTH is a 30-day
// rolling window and is never described as "this month".
function windowDescription(windowClass) {
    if (windowClass === "five_hour") return "5-hour rolling window";
    if (windowClass === "week") return "7-day rolling window";
    if (windowClass === "month") return "30-day rolling window";
    return "";
}

// A limit entry is only renderable when it carries a finite percent. Anything
// else is a duration report without a usable number and must not be coerced
// into 0%.
function limitIsLive(limit) {
    return !!limit && isFinite(Number(limit.percent));
}

function liveLimits(record) {
    return ((record && record.limits) || []).filter(limitIsLive);
}

function hasLiveLimits(record) {
    return liveLimits(record).length > 0;
}

// Worst-in-cell: when a provider reports the same canonical bucket more than
// once, the matrix column compares the highest used percent so the alarm is
// never hidden behind a duplicate. Non-finite percents are ignored.
function worstLimitFor(limits, windowClass) {
    var best = null;
    for (var i = 0; i < (limits || []).length; i++) {
        var limit = limits[i];
        if (classifyWindow(limit) !== windowClass) continue;
        var percent = Number(limit && limit.percent);
        if (!isFinite(percent)) continue;
        if (best === null || percent > Number(best.percent)) best = limit;
    }
    return best;
}

var SEVERITY_GLYPH = { warn: "▲", critical: "●" };

// A non-colour severity glyph for warn and critical only. Warning-gold versus
// error-red is the hardest pair for protan/deuteran vision, so the matrix must
// never rely on colour alone; `ok` carries no glyph.
function severityGlyph(severity) {
    return SEVERITY_GLYPH[severity] || "";
}

// The pace word shown inside a cell, only when BOTH percent and elapsed are
// finite. Deliberately short (`behind`/`ahead`/`on pace`) so it fits beside a
// relative countdown in a narrow numeric column.
function paceWord(limit, nowMs) {
    var pace = paceInfo(limit, nowMs);
    if (!pace) return "";
    if (pace.onPace) return "on pace";
    return pace.behind ? "behind" : "ahead";
}

function cellCountdown(limit, nowMs) {
    var remaining = resetMsFor(limit, nowMs);
    return remaining > 0 ? formatDuration(remaining) : "";
}

// One canonical matrix cell. `percent` is the always-present, colour-
// independent signal; the glyph/meter are secondary. Kept free of the
// absolute reset timestamp so 18 timestamps never clutter the grid; the
// absolute time lives in the per-account tab and the cell tooltip.
function matrixCell(limit, windowClass, nowMs) {
    if (!limit || !isFinite(Number(limit.percent))) return null;
    var percent = Number(limit.percent);
    var severity = severityForLimit(limit);
    var pace = paceInfo(limit, nowMs);
    return {
        windowClass: windowClass,
        label: String(limit.label || defaultWindowName(windowClass)),
        percent: percent,
        percentText: Math.round(percent * 100) + "%",
        severity: severity,
        glyph: severityGlyph(severity),
        elapsed: pace ? pace.elapsed : -1,
        paceWord: paceWord(limit, nowMs),
        countdown: cellCountdown(limit, nowMs),
        resetsAt: String(limit.resetsAt || ""),
        absoluteReset: formatResetAbsolute(limit.resetsAt)
    };
}

// A prepaid balance is only present when the record carries an actual
// `balance` object. `subscription.cost` describes what the user pays and must
// NEVER populate the balance column.
function hasBalance(record) {
    var balance = record && record.balance;
    return !!(balance && typeof balance === "object" && !Array.isArray(balance));
}

function anyBalance(records) {
    return (records || []).some(hasBalance);
}

function balanceText(record) {
    var balance = record && record.balance;
    if (!balance || typeof balance !== "object" || Array.isArray(balance)) return "";
    var currency = String(balance.currency || "");
    var remaining = Number(balance.remaining);
    if (!isFinite(remaining)) remaining = NaN;
    var spent = Number(balance.spent);
    if (!isFinite(spent)) spent = NaN;
    var value = isFinite(remaining) ? remaining : spent;
    if (!isFinite(value)) return "";
    var text = value.toFixed(2);
    return currency !== "" ? currency + " " + text : text;
}

function balanceHeader(records) {
    var anyRemaining = false;
    var anySpent = false;
    (records || []).forEach(function (record) {
        var balance = record && record.balance;
        if (!balance || typeof balance !== "object") return;
        if (isFinite(Number(balance.remaining))) anyRemaining = true;
        if (isFinite(Number(balance.spent))) anySpent = true;
    });
    if (!anyRemaining && anySpent) return "SPEND";
    return "BALANCE";
}

// A single account row for the matrix. `windows` keys are the canonical
// classes; a missing class is `null` and renders `—`. `noLiveLimits` is true
// only when the provider reports no usable limit at all, which is a NORMAL
// state and gets one muted tag rather than fabricated percentages.
function matrixRow(record, nowMs) {
    var limits = (record && record.limits) || [];
    var windows = {};
    CANONICAL_WINDOW_ORDER.forEach(function (windowClass) {
        windows[windowClass] = matrixCell(worstLimitFor(limits, windowClass), windowClass, nowMs);
    });
    return {
        id: String((record && record.id) || ""),
        name: String((record && (record.name || record.id)) || ""),
        record: record || null,
        windows: windows,
        todayTokens: formatTokens(todayUsage(record).billable),
        noLiveLimits: !hasLiveLimits(record),
        hasBalance: hasBalance(record),
        balance: balanceText(record)
    };
}

// Accounts the user actually has, in the fixed deterministic order. The order
// never depends on severity or freshness.
function accountOrder(records) {
    var list = detectedAgents(records).slice();
    list.sort(function (a, b) {
        var an = String((a && (a.name || a.id)) || "");
        var bn = String((b && (b.name || b.id)) || "");
        if (an < bn) return -1;
        if (an > bn) return 1;
        var aid = String((a && a.id) || "");
        var bid = String((b && b.id) || "");
        if (aid < bid) return -1;
        if (aid > bid) return 1;
        return 0;
    });
    return list;
}

function matrixRows(records, nowMs) {
    return accountOrder(records).map(function (record) {
        return matrixRow(record, nowMs);
    });
}

// Selection reconciliation is BY ID, not index: a removed account falls back
// by id first and then to a clamped previous index, so the detail pane never
// blanks and a blunt `selectedIndex = 0` reset never surprises the user.
function reconcileSelection(previousId, previousIndex, rows) {
    if (!rows || rows.length === 0) return -1;
    if (previousId !== null && previousId !== undefined && String(previousId) !== "") {
        for (var i = 0; i < rows.length; i++) {
            if (String(rows[i].id) === String(previousId)) return i;
        }
    }
    var index = Number(previousIndex);
    if (!isFinite(index)) index = 0;
    return Math.max(0, Math.min(Math.round(index), rows.length - 1));
}

// Detail rows for the per-account tab: the FULL limits list, including `other`
// windows and any duplicate bucket. `unknown` durations render as a
// full-width `duration not reported` row. Input order is preserved so the tab
// stays stable and never reshuffles between refreshes.
function limitDetailRows(record, nowMs) {
    return ((record && record.limits) || []).map(function (limit) {
        var windowClass = classifyWindow(limit);
        var live = limitIsLive(limit);
        var percent = Number(limit && limit.percent);
        var severity = live ? severityForLimit(limit) : "unknown";
        return {
            windowClass: windowClass,
            isUnknown: windowClass === "unknown",
            isOther: windowClass === "other",
            title: windowClass === "unknown"
                ? "duration not reported"
                : (String(limit && limit.label || "") || defaultWindowName(windowClass)),
            percent: live ? percent : -1,
            percentText: live ? Math.round(percent * 100) + "%" : "—",
            severity: severity,
            glyph: live ? severityGlyph(severity) : "",
            elapsed: paceInfo(limit, nowMs) ? paceInfo(limit, nowMs).elapsed : -1,
            paceWord: live ? paceWord(limit, nowMs) : "",
            countdown: live ? cellCountdown(limit, nowMs) : "",
            resetsAt: String(limit && limit.resetsAt || ""),
            absoluteReset: formatResetAbsolute(limit && limit.resetsAt)
        };
    });
}

// ---------------------------------------------------------------------------
// Conditional fail-safe diagnostics
//
// The dashboard shows available data whenever it exists and degrades to honest
// user-facing labels (`—`, `no live limits`, `duration not reported`) only for
// the fields that are genuinely absent. Every unmet condition that produces
// such a label also produces an observable diagnostic naming the condition and
// the provider, so a silent `—` is never the only record. The dashboard emits
// these through the shell's standard `console.warn("[AGENTS] ...")` channel,
// which `aurelia logs` reads from the Quickshell runtime log. This function is
// pure so the diagnostic contract is unit-testable.

function trimmedString(value) {
    if (value === undefined || value === null) return "";
    return String(value);
}

function diagnosticProvider(record) {
    return String((record && (record.id || record.name)) || "unknown");
}

function pushDiagnostic(out, record, condition, detail) {
    out.push({
        provider: diagnosticProvider(record),
        condition: condition,
        detail: trimmedString(detail)
    });
}

function limitDiagnosticLabel(limit, index) {
    var label = trimmedString(limit && limit.label);
    return label !== "" ? label : "limit[" + index + "]";
}

function diagnoseRecord(record) {
    var out = [];
    var limits = record ? record.limits : null;
    if (!Array.isArray(limits) || limits.length === 0) {
        pushDiagnostic(out, record, "missing_limits", "");
    } else {
        limits.forEach(function (limit, index) {
            var raw = limit ? limit.windowMinutes : undefined;
            if (raw === undefined || raw === null || String(raw) === "") {
                pushDiagnostic(out, record, "missing_window_minutes", limitDiagnosticLabel(limit, index));
            } else if (!isFinite(Number(raw))) {
                pushDiagnostic(out, record, "unparseable_window_minutes", limitDiagnosticLabel(limit, index));
            } else if (Number(raw) === 0) {
                pushDiagnostic(out, record, "zero_window_minutes", limitDiagnosticLabel(limit, index));
            }
            var resetsAt = limit ? limit.resetsAt : undefined;
            if (resetsAt === undefined || resetsAt === null || String(resetsAt) === "") {
                pushDiagnostic(out, record, "missing_resets_at", limitDiagnosticLabel(limit, index));
            } else if (!isFinite(Date.parse(String(resetsAt)))) {
                pushDiagnostic(out, record, "unparseable_resets_at", limitDiagnosticLabel(limit, index));
            }
        });
    }
    if (!hasBalance(record)) {
        pushDiagnostic(out, record, "absent_balance", "");
    }
    return out;
}

function diagnoseRecords(records) {
    var out = [];
    (records || []).forEach(function (record) {
        out = out.concat(diagnoseRecord(record));
    });
    return out;
}

// A collector run that failed is diagnosable independent of any record.
function collectorDiagnostic(errorText) {
    var message = trimmedString(errorText);
    if (message === "") return [];
    return [{ provider: "backend", condition: "collector_failed", detail: message }];
}

function diagnosticKey(diagnostic) {
    return trimmedString(diagnostic && diagnostic.provider) + "|" +
        trimmedString(diagnostic && diagnostic.condition) + "|" +
        trimmedString(diagnostic && diagnostic.detail);
}

function diagnosticLine(diagnostic) {
    var line = "[AGENTS] unmet_condition provider=" + trimmedString(diagnostic && diagnostic.provider) +
        " condition=" + trimmedString(diagnostic && diagnostic.condition);
    var detail = trimmedString(diagnostic && diagnostic.detail);
    if (detail !== "") line += " detail=" + detail;
    return line;
}
