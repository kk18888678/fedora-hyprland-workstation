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

// ---------------------------------------------------------------------------
// Percentage presentation mode
//
// `limits[].percent` is the fraction USED (0..1), and severity is a RISK
// threshold derived from it (see severityForLimit). That internal meaning is
// never inverted. What the user sees can be either the remaining headroom
// (the default: 100% = fully available, 0% = exhausted) or the consumed
// fraction (100% = exhausted). normalizePercentMode is the SINGLE place that
// decides which mode applies, and displayPercent/displayMarker are the SINGLE
// place that inverts, so the rendered number and its meter can never disagree.
function normalizePercentMode(value) {
    // Fail closed: only an explicit "used" selects the used presentation.
    // undefined/null/empty/numbers/unknown strings all map to "remaining".
    return String(value).toLowerCase() === "used" ? "used" : "remaining";
}

function displayPercent(usedFraction, mode) {
    var used = Number(usedFraction);
    // The -1 sentinel means "no live limit" and must survive unchanged.
    if (!isFinite(used) || used < 0) return used;
    return normalizePercentMode(mode) === "used" ? used : 1 - used;
}

function displayMarker(elapsedFraction, mode) {
    var elapsed = Number(elapsedFraction);
    // The -1 sentinel means "no pace marker" and must survive unchanged.
    if (!isFinite(elapsed) || elapsed < 0) return elapsed;
    return normalizePercentMode(mode) === "used" ? elapsed : 1 - elapsed;
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

// The most recently WRITTEN record's `updatedAt`. This is the last collector
// write, NOT proof that the upstream quota query succeeded: a failed query is
// surfaced separately through the record error state, while a stale write is
// still the best available freshness signal.
function newestRecord(records) {
    var best = null;
    var bestMs = -Infinity;
    (records || []).forEach(function (record) {
        var ms = updatedAtMs(record);
        if (!isFinite(ms)) return;
        if (best === null || ms > bestMs) {
            best = record;
            bestMs = ms;
        }
    });
    return best;
}

// Freshness across every account, independent of which record is expanded, so
// the resting consolidated matrix is never "Freshness unknown". Uses the same
// `updated` wording as the bar tooltip and the same future-timestamp clamp
// (`just now`) via recordAgeMs.
function overallFreshnessPill(records, nowMs, staleMs) {
    var newest = newestRecord(records);
    if (!newest) return { text: "never updated", stale: false, known: false };
    var age = recordAgeMs(newest, nowMs);
    if (!isFinite(age)) return { text: "never updated", stale: false, known: false };
    var stale = isRecordStale(newest, nowMs, staleMs);
    var ageText = age < 60000 ? "just now" : formatDuration(age) + " ago";
    var text = "updated " + ageText;
    return { text: stale ? "stale · " + text : text, stale: stale, known: true, ageText: ageText };
}

// The bar tooltip model: one row per READY account in the panel's pinned
// order (never re-sorted), plus the freshness footer. The value states the
// binding window's headroom, or the blocked/fast/error state, or the day's
// billable tokens for a provider with no live limits. `mode` only changes the
// headroom unit; the row order and grouping are mode-independent. Privacy: the
// only identity used is the provider display name; `record.account` is never
// read.
function barTooltipModel(records, nowMs, mode, staleMs) {
    var ready = readyAgents(records);
    var ordered = accountOrder(ready);
    var list = [];
    for (var i = 0; i < ordered.length; i++) {
        var record = ordered[i];
        var name = providerDisplayName(record);
        var state = providerState(record, nowMs, { staleMs: staleMs });
        var limit = bindingLimit(record, nowMs);
        var value = "";
        var tone = "neutral";
        if (state.key === "error") {
            value = "Error";
            tone = "error";
        } else if (state.key === "rate-limited") {
            value = "Rate limited";
            tone = "warning";
        } else if (state.severity === "critical") {
            var countdown = limit ? cellCountdown(limit, nowMs) : "";
            value = countdown !== "" ? "Blocked · " + countdown : "Blocked";
            tone = "error";
        } else if (limit && isMeaningfullyFast(limit, nowMs)) {
            value = "Faster than pace";
            tone = "warning";
        } else if (limit) {
            var percent = Math.round(displayPercent(Number(limit.percent), mode) * 100);
            value = percent + (normalizePercentMode(mode) === "used" ? "% used" : "% left");
            tone = "success";
        } else {
            value = formatTokens(todayUsage(record).billable) + " tokens today";
            tone = "neutral";
        }
        list.push({ name: name, value: value, tone: tone });
    }
    var freshness = overallFreshnessPill(ready, nowMs, staleMs);
    var footerText = freshness.text;
    if (footerText !== "") {
        footerText = footerText.charAt(0).toUpperCase() + footerText.slice(1);
        // A stale footer already reads "Stale · updated <age> ago"; the click
        // affordance would push that fixed string past one line, so it is
        // dropped when stale. The fresh footer keeps it.
        if (!freshness.stale) footerText += " · click for details";
    }
    return {
        list: list,
        footer: { text: footerText, tone: freshness.stale ? "warning" : "default" }
    };
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

var MONTH_ABBREVIATIONS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
var WEEKDAY_ABBREVIATIONS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// Local reset wording from a fixed timezone offset in minutes EAST of UTC
// (the dashboard passes -new Date().getTimezoneOffset()). Pure: the offset is
// a parameter, so the tests can pin 0, +330 and -420 and never depend on the
// host timezone. Returns "" for invalid input.
function formatResetLocal(resetsAt, nowMs, tzOffsetMin) {
    if (!resetsAt) return "";
    var parsed = Date.parse(String(resetsAt));
    if (!isFinite(parsed)) return "";
    var now = Number(nowMs);
    if (!isFinite(now)) return "";
    var offset = Number(tzOffsetMin);
    if (!isFinite(offset)) offset = 0;
    var target = new Date(parsed + offset * 60000);
    var nowLocal = new Date(now + offset * 60000);
    var time = String(target.getUTCHours()).padStart(2, "0") + ":" +
        String(target.getUTCMinutes()).padStart(2, "0");
    var targetDay = Date.UTC(target.getUTCFullYear(), target.getUTCMonth(), target.getUTCDate());
    var nowDay = Date.UTC(nowLocal.getUTCFullYear(), nowLocal.getUTCMonth(), nowLocal.getUTCDate());
    var dayDiff = Math.round((targetDay - nowDay) / 86400000);
    if (dayDiff === 0) return "today " + time;
    if (dayDiff === 1) return "tomorrow " + time;
    if (dayDiff >= 2 && dayDiff <= 6) {
        return WEEKDAY_ABBREVIATIONS[target.getUTCDay()] + " " + time;
    }
    return target.getUTCDate() + " " + MONTH_ABBREVIATIONS[target.getUTCMonth()];
}

// Human pace state, including the explicit on-pace case.
function paceLabel(pace) {
    if (!pace) return "";
    if (pace.onPace) return "on pace";
    return pace.behind ? "behind pace" : "ahead of pace";
}
// The worst window for a provider, used to label the provider switch.
function providerWorstLabel(record, nowMs, mode) {
    var limit = bindingLimit(record, nowMs);
    if (!limit) return "";
    var label = String(limit.label || "Limit");
    var used = Number(limit.percent);
    if (!isFinite(used)) return label;
    return label + " " + Math.round(displayPercent(used, mode) * 100) + "%";
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

// ---------------------------------------------------------------------------
// Alert presentation policy (P1/P2/P3)
//
// An alert state is a warn or critical severity, or any element whose rendered
// colour is a status colour (Theme.error/Theme.warning), or content that IS the
// alert (the percentage/headline, the severity glyph, the alarming meter fill,
// the bar icon and its dot). Alert content is NEVER dimmed by de-emphasis:
// staleness may add a freshness cue but must never subtract the alert's full
// strength or its non-colour cue. These two functions are the single owner of
// that rule so the bar state, the provider state and the dashboard cannot drift
// apart; the QML views call them instead of re-deriving the condition.
//
// `stale` is part of the signature so callers hand over the whole state, but it
// can only ever affect non-alert content (via the caller's baseOpacity).
// ---------------------------------------------------------------------------

function isAlertSeverity(severity) {
    return severity === "warn" || severity === "critical";
}

// Presentation opacity for a state. An alert always resolves to 1.0 no matter
// how stale it is; only non-alert content may take the de-emphasised base.
function presentationOpacityFor(severity, stale, baseOpacity) {
    if (isAlertSeverity(severity)) return 1.0;
    return baseOpacity;
}

// Per-provider state for the panel: loading/empty/unknown/ready/warn/critical/
// stale/error/rate-limited. Error and rate-limit take precedence over stale so
// a failure is never hidden behind old data. Staleness is ADDITIVE: it adds a
// freshness cue but never dims or removes an alert (P1/P2).
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
        // P3: the non-colour dot survives staleness. It is gated on severity
        // alone, never on freshness.
        dot: severity !== "ok",
        opacity: presentationOpacityFor(severity, stale, stale ? 0.6 : 1.0),
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
        return {
            key: "stale",
            severity: severity,
            stale: true,
            // P3: a stale alert keeps its colour-blind-safe dot.
            dot: severity !== "ok",
            opacity: presentationOpacityFor(severity, true, 0.6),
            tint: tint
        };
    }
    return {
        key: severity === "ok" ? "ready" : severity,
        severity: severity,
        stale: false,
        dot: severity !== "ok",
        opacity: presentationOpacityFor(severity, false, 1.0),
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

// ---------------------------------------------------------------------------
// Pace projection and the meaningful-fast threshold
//
// `projectExhaustion` linearly projects when the window would empty at the
// current burn rate. `isMeaningfullyFast` is the only owner of the "faster
// than pace" decision: it requires the projection to run out before the reset
// AND to beat it by at least 10% of the window, so a 0.01% over-pace reading
// (the raw `paceInfo().behind` epsilon is 1e-6) can never turn the marker amber.
// ---------------------------------------------------------------------------

var PACE_ALERT_MIN_MARGIN_FRACTION = 0.10;

function projectExhaustion(limit, nowMs) {
    var used = Number(limit && limit.percent);
    if (!isFinite(used) || used <= 0 || used >= 1) return null;
    var elapsed = elapsedFraction(limit, nowMs);
    if (!isFinite(elapsed) || elapsed < 0.05) return null;
    var resetMs = resetMsFor(limit, nowMs);
    if (!isFinite(resetMs) || resetMs < 0) return null;
    var windowMs = Number(limit && limit.windowMinutes) * 60000;
    if (!isFinite(windowMs) || windowMs <= 0) return null;
    var elapsedMs = elapsed * windowMs;
    if (!(elapsedMs > 0)) return null;
    var rate = used / elapsedMs;
    var msToEmpty = (1 - used) / rate;
    if (!isFinite(msToEmpty)) return null;
    return {
        msToEmpty: msToEmpty,
        beforeReset: msToEmpty < resetMs,
        marginMs: resetMs - msToEmpty
    };
}

function isMeaningfullyFast(limit, nowMs) {
    var projection = projectExhaustion(limit, nowMs);
    if (!projection || projection.beforeReset !== true) return false;
    var windowMs = Number(limit && limit.windowMinutes) * 60000;
    if (!isFinite(windowMs) || windowMs <= 0) return false;
    return projection.marginMs >= PACE_ALERT_MIN_MARGIN_FRACTION * windowMs;
}

// ---------------------------------------------------------------------------
// Durable anti-flood notification policy
//
// The bar widget re-runs this on every successful refresh. The returned state
// MUST be persisted and fed back on the next call: transition detection is
// useless without durable state, because the widget is recreated on every local
// plugin change and the shell restarts between sessions. Every rule is pure so
// it is unit-testable without QML, timers, or the live workstation.
//
// Rules:
//  * baseline-suppress the first observation of a window so a fresh or missing
//    state can never burst;
//  * notify only on a severity transition away from `ok`, and re-arm when the
//    severity returns to `ok` so a later re-cross emits exactly once;
//  * rate-limit repeat notifications for the same window by a minimum interval
//    (threshold flapping and `resetsAt` representation jitter are absorbed);
//  * treat a reset as real only when the reset instant advances by at least the
//    minimum reset interval, and rate-limit repeat reset announcements;
//  * renew at most once per account per local date, re-arming on a date change
//    or a `renew` change, deriving `daysLeft` from `renew` when it is missing;
//  * bound every evaluation with a per-(account, severity class, label) dedup,
//    one per account per severity class per evaluation, and a rolling hourly
//    cap whose overflow becomes one aggregate line.
// The announced state still advances when DND silences display, so turning DND
// off can never replay a backlog.
// ---------------------------------------------------------------------------

var NOTIFICATION_STATE_VERSION = 1;
var NOTIFICATION_MIN_INTERVAL_MS = 30 * 60 * 1000;
var NOTIFICATION_MIN_RESET_INTERVAL_MS = 30 * 60 * 1000;
var NOTIFICATION_HOURLY_CAP = 6;
var NOTIFICATION_ROLLING_MS = 60 * 60 * 1000;
var NOTIFICATION_RECENT_LIMIT = 256;

function emptyNotificationState() {
    return { version: NOTIFICATION_STATE_VERSION, windows: {}, renewals: {}, recent: [] };
}

function notificationPlainObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

function notificationBoundedString(value, max) {
    var text = value === undefined || value === null ? "" : String(value);
    var limit = isFinite(max) && max > 0 ? Math.floor(max) : 64;
    return text.length > limit ? text.slice(0, limit) : text;
}

// A missing, empty or corrupt payload behaves as empty state (fail safe): the
// next evaluation baseline-suppresses instead of bursting.
function normalizeNotificationState(raw) {
    var out = emptyNotificationState();
    if (!notificationPlainObject(raw)) return out;
    var windows = notificationPlainObject(raw.windows) ? raw.windows : {};
    for (var windowKey in windows) {
        if (!Object.prototype.hasOwnProperty.call(windows, windowKey)) continue;
        var windowRecord = windows[windowKey];
        if (!notificationPlainObject(windowRecord)) continue;
        out.windows[notificationBoundedString(windowKey, 256)] = {
            announcedSeverity: notificationBoundedString(windowRecord.announcedSeverity, 16) || "ok",
            lastNotifiedSeverity: notificationBoundedString(windowRecord.lastNotifiedSeverity, 16) || "ok",
            windowResetsAt: windowRecord.windowResetsAt === undefined || windowRecord.windowResetsAt === null
                ? "" : String(windowRecord.windowResetsAt),
            lastAnnouncedAt: number(windowRecord.lastAnnouncedAt),
            lastResetAnnouncedAt: number(windowRecord.lastResetAnnouncedAt)
        };
    }
    var renewals = notificationPlainObject(raw.renewals) ? raw.renewals : {};
    for (var accountKey in renewals) {
        if (!Object.prototype.hasOwnProperty.call(renewals, accountKey)) continue;
        var renewalRecord = renewals[accountKey];
        if (!notificationPlainObject(renewalRecord)) continue;
        out.renewals[notificationBoundedString(accountKey, 256)] = {
            announcedForDate: notificationBoundedString(renewalRecord.announcedForDate, 16),
            renewValue: notificationBoundedString(renewalRecord.renewValue, 64),
            lastAnnouncedAt: number(renewalRecord.lastAnnouncedAt)
        };
    }
    var recent = Array.isArray(raw.recent) ? raw.recent : [];
    for (var i = 0; i < recent.length && i < NOTIFICATION_RECENT_LIMIT; i++) {
        var emittedAt = number(recent[i]);
        if (emittedAt > 0) out.recent.push(emittedAt);
    }
    return out;
}

function notificationSortedCopy(source) {
    var out = {};
    var keys = Object.keys(source).sort();
    for (var i = 0; i < keys.length; i++) out[keys[i]] = source[keys[i]];
    return out;
}

// Deterministic, bounded serialization: sorted keys keep the bytes stable so
// equal states round-trip to equal files (and tests are reproducible).
function serializeNotificationState(state) {
    var clean = normalizeNotificationState(state);
    return JSON.stringify({
        version: NOTIFICATION_STATE_VERSION,
        windows: notificationSortedCopy(clean.windows),
        renewals: notificationSortedCopy(clean.renewals),
        recent: clean.recent.slice(-NOTIFICATION_RECENT_LIMIT)
    });
}

function deserializeNotificationState(text) {
    var raw = String(text === undefined || text === null ? "" : text).trim();
    if (raw === "") return emptyNotificationState();
    try {
        return normalizeNotificationState(JSON.parse(raw));
    } catch (error) {
        console.warn("[AGENTS] notification_state_parse_failed reason=" +
            String(error && error.message ? error.message : error));
        return emptyNotificationState();
    }
}

// Stable identity: the backend `id` when present, otherwise a deterministic
// fallback. The array index keeps records that have neither id nor name from
// colliding; `parseRecords` does not validate `id` today.
function notificationRecordId(agent, index) {
    var id = agent && agent.id !== undefined && agent.id !== null ? String(agent.id).trim() : "";
    if (id !== "") return "id:" + id;
    var name = agent && agent.name !== undefined && agent.name !== null ? String(agent.name).trim() : "";
    return "anon:" + (name !== "" ? name : "agent") + "#" + Math.max(0, Number(index) || 0);
}

function notificationLimitLabel(limit, index) {
    var label = limit && limit.label !== undefined && limit.label !== null ? String(limit.label) : "";
    if (label !== "") return label;
    return "limit#" + Math.max(0, Number(index) || 0);
}

function notificationResetsMs(limit) {
    if (!limit || !limit.resetsAt) return NaN;
    var parsed = Date.parse(String(limit.resetsAt));
    return isFinite(parsed) ? parsed : NaN;
}

// Derive `daysLeft` from `renew` when the record omits it so a missing field
// cannot flap the reminder window. Local-date arithmetic avoids timezone skew.
function notificationRenewalDaysLeft(subscription, nowMs) {
    if (!subscription) return NaN;
    if (subscription.daysLeft !== undefined && subscription.daysLeft !== null &&
        String(subscription.daysLeft) !== "") {
        var explicit = Number(subscription.daysLeft);
        if (isFinite(explicit)) return explicit;
    }
    if (!subscription.renew) return NaN;
    var renewMs = Date.parse(String(subscription.renew) + "T00:00:00");
    if (!isFinite(renewMs)) return NaN;
    var now = new Date(nowMs);
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    return Math.round((renewMs - startOfToday) / 86400000);
}

function notificationPush(pending, emittedKeys, accountClasses, candidate) {
    var key = candidate.account + "|" + candidate.severityClass + "|" + candidate.label;
    var classKey = candidate.account + "|" + candidate.severityClass;
    if (Object.prototype.hasOwnProperty.call(emittedKeys, key)) return false;
    if (Object.prototype.hasOwnProperty.call(accountClasses, classKey)) return false;
    emittedKeys[key] = true;
    accountClasses[classKey] = true;
    pending.push(candidate);
    return true;
}

function notificationRenewalBody(renewValue, daysLeft) {
    return "Renews " + renewValue +
        (daysLeft === 0 ? " (today)" : " in " + daysLeft + " day" + (daysLeft === 1 ? "" : "s"));
}

function notificationPlan(records, persistedState, options, nowMs) {
    var opts = options || {};
    var now = isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    var state = normalizeNotificationState(persistedState);
    var notifications = [];
    if (opts.enabled === false) return { state: state, notifications: notifications };

    var minSeverity = String(opts.minSeverity || "warn").toLowerCase() === "critical" ? "critical" : "warn";
    var minInterval = isFinite(opts.minIntervalMs)
        ? Math.max(0, Number(opts.minIntervalMs)) : NOTIFICATION_MIN_INTERVAL_MS;
    var minResetInterval = isFinite(opts.minResetIntervalMs)
        ? Math.max(0, Number(opts.minResetIntervalMs)) : NOTIFICATION_MIN_RESET_INTERVAL_MS;
    var hourlyCap = isFinite(opts.hourlyCap)
        ? Math.max(1, Math.floor(Number(opts.hourlyCap))) : NOTIFICATION_HOURLY_CAP;
    var reminderDefault = isFinite(opts.reminderDaysDefault) ? Number(opts.reminderDaysDefault) : 3;
    var warnPct = isFinite(opts.warnPct) ? Number(opts.warnPct) : undefined;
    var criticalPct = isFinite(opts.criticalPct) ? Number(opts.criticalPct) : undefined;

    var recent = [];
    for (var r = 0; r < state.recent.length; r++) {
        var emittedAt = number(state.recent[r]);
        if (emittedAt > 0 && now - emittedAt < NOTIFICATION_ROLLING_MS) recent.push(emittedAt);
    }
    state.recent = recent;
    var budget = Math.max(0, hourlyCap - recent.length);

    var pending = [];
    var emittedKeys = {};
    var accountClasses = {};
    var today = todayDate(now);
    var list = records || [];

    for (var index = 0; index < list.length; index++) {
        var agent = list[index];
        if (!agent || agent.ready !== true) continue;
        var accountKey = notificationRecordId(agent, index);
        var accountName = String(agent.name || agent.id || "AI agent");
        var limits = Array.isArray(agent.limits) ? agent.limits : [];
        for (var limitIndex = 0; limitIndex < limits.length; limitIndex++) {
            var limit = limits[limitIndex];
            if (!limit || typeof limit !== "object") continue;
            var windowKey = accountKey + "|" + notificationLimitLabel(limit, limitIndex);
            var existing = state.windows[windowKey] || null;
            var severity = severityForLimit(limit, warnPct, criticalPct);
            // Below the configured floor a warning is treated as steady `ok`;
            // the state still advances so raising the floor does not replay.
            var effectiveSeverity = (minSeverity === "critical" && severity === "warn") ? "ok" : severity;
            var label = notificationLimitLabel(limit, limitIndex);
            var rawResets = limit.resetsAt === undefined || limit.resetsAt === null ? "" : String(limit.resetsAt);
            var resetsMs = notificationResetsMs(limit);

            if (!existing) {
                // Baseline: record the observation, emit nothing.
                state.windows[windowKey] = {
                    announcedSeverity: effectiveSeverity,
                    lastNotifiedSeverity: "ok",
                    windowResetsAt: rawResets,
                    lastAnnouncedAt: 0,
                    lastResetAnnouncedAt: 0
                };
                continue;
            }

            var nextRecord = {
                announcedSeverity: existing.announcedSeverity,
                lastNotifiedSeverity: existing.lastNotifiedSeverity,
                windowResetsAt: existing.windowResetsAt,
                lastAnnouncedAt: existing.lastAnnouncedAt,
                lastResetAnnouncedAt: existing.lastResetAnnouncedAt
            };

            var resetAnnounced = false;
            var previousResetsMs = Date.parse(String(existing.windowResetsAt || ""));
            if (isFinite(resetsMs) && isFinite(previousResetsMs) &&
                resetsMs > previousResetsMs && (resetsMs - previousResetsMs) >= minResetInterval &&
                (existing.lastResetAnnouncedAt <= 0 || (now - existing.lastResetAnnouncedAt) >= minResetInterval)) {
                resetAnnounced = true;
                nextRecord.lastResetAnnouncedAt = now;
                // Consume the severity in the same call so one reset never
                // produces a second severity notification (the old bug).
                nextRecord.announcedSeverity = effectiveSeverity;
                var resetPercent = Number(limit.percent);
                var resetBody = isFinite(resetPercent)
                    ? label + " reset · " + Math.max(0, Math.round((1 - resetPercent) * 100)) + "% available"
                    : label + " reset";
                notificationPush(pending, emittedKeys, accountClasses, {
                    kind: "reset",
                    severityClass: "reset",
                    account: accountKey,
                    label: label,
                    title: accountName + " limit reset",
                    body: resetBody
                });
            }

            // Always advance the stored reset instant (forward only) so a slow
            // representation drift cannot accumulate into a false reset.
            if (isFinite(resetsMs) && (!isFinite(previousResetsMs) || resetsMs > previousResetsMs)) {
                nextRecord.windowResetsAt = rawResets;
            } else if (!isFinite(previousResetsMs) && rawResets !== "") {
                nextRecord.windowResetsAt = rawResets;
            }

            if (!resetAnnounced) {
                if (effectiveSeverity === "ok") {
                    nextRecord.announcedSeverity = "ok";
                } else if (effectiveSeverity !== existing.announcedSeverity) {
                    // Suppress a repeat inside the minimum interval but leave
                    // `announcedSeverity` untouched so the same crossing is
                    // retried once the interval lapses.
                    if ((now - number(existing.lastAnnouncedAt)) >= minInterval) {
                        nextRecord.announcedSeverity = effectiveSeverity;
                        nextRecord.lastNotifiedSeverity = effectiveSeverity;
                        nextRecord.lastAnnouncedAt = now;
                        notificationPush(pending, emittedKeys, accountClasses, {
                            kind: "severity",
                            severityClass: effectiveSeverity,
                            account: accountKey,
                            label: label,
                            title: accountName + " limit " +
                                (effectiveSeverity === "critical" ? "critical" : "warning"),
                            body: label + " is at " + Math.round(Number(limit.percent) * 100) + "% used"
                        });
                    }
                }
            }
            state.windows[windowKey] = nextRecord;
        }

        if (opts.renewals === false) continue;
        var subscription = agent.subscription;
        if (!subscription || !subscription.renew) continue;
        var daysLeft = notificationRenewalDaysLeft(subscription, now);
        if (!isFinite(daysLeft)) continue;
        var reminderDays = Number(subscription.reminderDays);
        if (!isFinite(reminderDays)) reminderDays = reminderDefault;
        var renewValue = String(subscription.renew);
        var previousRenewal = state.renewals[accountKey] || null;
        var inWindow = daysLeft >= 0 && daysLeft <= reminderDays;
        var nextRenewal;
        if (!previousRenewal) {
            // Baseline: remember today so a fresh state cannot burst.
            nextRenewal = { announcedForDate: inWindow ? today : "", renewValue: renewValue, lastAnnouncedAt: 0 };
        } else if (previousRenewal.renewValue !== renewValue) {
            // A changed renewal date is a genuine new cycle: re-arm and notify.
            nextRenewal = {
                announcedForDate: inWindow ? today : "",
                renewValue: renewValue,
                lastAnnouncedAt: inWindow ? now : previousRenewal.lastAnnouncedAt
            };
            if (inWindow) {
                notificationPush(pending, emittedKeys, accountClasses, {
                    kind: "renewal",
                    severityClass: "renewal",
                    account: accountKey,
                    label: "renewal",
                    title: accountName + " renewal",
                    body: notificationRenewalBody(renewValue, daysLeft)
                });
            }
        } else if (!inWindow) {
            nextRenewal = { announcedForDate: "", renewValue: renewValue, lastAnnouncedAt: previousRenewal.lastAnnouncedAt };
        } else if (previousRenewal.announcedForDate !== today) {
            nextRenewal = { announcedForDate: today, renewValue: renewValue, lastAnnouncedAt: now };
            notificationPush(pending, emittedKeys, accountClasses, {
                kind: "renewal",
                severityClass: "renewal",
                account: accountKey,
                label: "renewal",
                title: accountName + " renewal",
                body: notificationRenewalBody(renewValue, daysLeft)
            });
        } else {
            nextRenewal = {
                announcedForDate: previousRenewal.announcedForDate,
                renewValue: previousRenewal.renewValue,
                lastAnnouncedAt: previousRenewal.lastAnnouncedAt
            };
        }
        state.renewals[accountKey] = nextRenewal;
    }

    // Rolling hourly cap: emit at most the remaining budget, turning the
    // overflow into ONE aggregate line. The state above already advanced for
    // every candidate, so dropped alerts are consumed rather than replayed.
    var output = [];
    var dropped = 0;
    if (pending.length <= budget) {
        output = pending;
    } else if (budget > 0) {
        var keep = budget - 1;
        for (var p = 0; p < keep; p++) output.push(pending[p]);
        dropped = pending.length - keep;
        output.push({
            kind: "aggregate",
            severityClass: "aggregate",
            account: "",
            label: "",
            title: "AI usage alerts",
            body: "… and " + dropped + " more"
        });
    } else {
        dropped = pending.length;
    }
    for (var o = 0; o < output.length; o++) state.recent.push(now);
    if (state.recent.length > NOTIFICATION_RECENT_LIMIT) {
        state.recent = state.recent.slice(-NOTIFICATION_RECENT_LIMIT);
    }
    if (dropped > 0) {
        console.warn("[AGENTS] notification_cap_dropped count=" + dropped + " cap=" + hourlyCap);
    }
    return { state: state, notifications: output };
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
// Account details (identity + subscription billing surface)
//
// The record may carry an optional `account` object populated by a collector
// from a LOCAL identity source only (Cline providers.json, Codex id_token
// claims, Claude oauthAccount). It is display-only and private: it is never
// written to the runtime log, a diagnostic, a tooltip or a notification.
//
// PRECEDENCE: this is the BILLING surface, so the user-owned `ai.conf`
// subscription (record.subscription) is AUTHORITATIVE for plan and billing
// date over any provider-reported value. The account HERO deliberately uses
// the OPPOSITE precedence (it prefers the provider `tierLabel`); do not
// "consistency-fix" one into the other.
//
// This projection is pure so the four normative cases are unit-testable:
//   1. no account data             -> rows []
//   2. subscription with a date    -> Email/Name/Subscription/Next billing
//   3. subscription without a date -> Email/Name/Subscription/Next billing "—"
//   4. API-billed, no subscription -> Email/Name only
// A missing field is never rendered as "Unknown", and a quota reset is never
// used as a billing date: a quota window is not a bill.
function accountDetails(record) {
    // Every identity/billing field must be a genuine non-empty string. A
    // number, object, array or boolean is treated as absent (never coerced),
    // so a changed provider shape cannot fabricate a displayed value.
    function field(value) {
        return typeof value === "string" ? value.trim() : "";
    }
    var rawAccount = record && record.account;
    var account = (rawAccount && typeof rawAccount === "object" && !Array.isArray(rawAccount))
        ? rawAccount : {};
    var sub = (record && record.subscription &&
        typeof record.subscription === "object" && !Array.isArray(record.subscription))
        ? record.subscription : null;
    var email = field(account.email);
    var name = field(account.name);
    var providerPlan = field(account.plan);
    var providerDate = field(account.billingDate);
    var userPlan = sub ? field(sub.plan) : "";
    var userDate = sub ? field(sub.renew) : "";
    var apiBilled = field(record && record.billingKind).toLowerCase() === "api";
    // `ai.conf` wins for plan and date; the provider value is only a fallback.
    var plan = userPlan !== "" ? userPlan : providerPlan;
    var date = userDate !== "" ? userDate : providerDate;
    // Fail closed: a subscription is only claimed when one is genuinely known
    // (a user-owned subscription record or a provider-reported plan). A bare
    // provider tier label is deliberately NOT enough on its own, so an account
    // with no identity and no subscription renders the honest empty message.
    var isSubscription = !apiBilled && (sub !== null || providerPlan !== "");
    var rows = [];
    if (email !== "") rows.push({ label: "Email", value: email, elide: "middle" });
    if (name !== "") rows.push({ label: "Name", value: name, elide: "right" });
    if (isSubscription && plan !== "") {
        rows.push({ label: "Subscription", value: plan, elide: "right" });
    }
    // The established "not reported" marker, never a fabricated date and never
    // a quota reset backfilled as a bill.
    if (isSubscription || date !== "") {
        rows.push({ label: "Next billing", value: date !== "" ? date : "—", elide: "right" });
    }
    return { rows: rows, isSubscription: isSubscription, knownCount: rows.length };
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

// Collector-declared capability: the canonical window lengths (in minutes) the
// provider can actually report. Returns an array of canonical classes, or null
// when the record declares nothing (legacy/unknown capability). A declared
// non-canonical duration is ignored because it cannot map to a column.
function supportedWindowClasses(record) {
    var raw = record ? record.supportedWindowMinutes : undefined;
    if (!Array.isArray(raw) || raw.length === 0) return null;
    var out = [];
    for (var i = 0; i < raw.length; i++) {
        var windowClass = windowClassForMinutes(raw[i]);
        if (windowClass !== "" && out.indexOf(windowClass) === -1) out.push(windowClass);
    }
    return out.length > 0 ? out : null;
}

function windowClassForMinutes(minutes) {
    var value = Number(minutes);
    if (!isFinite(value)) return "";
    if (value === 300) return "five_hour";
    if (value === 10080) return "week";
    if (value === 43200) return "month";
    return "";
}

// Tri-state capability for one canonical column: true (offered), false (not
// offered by this provider) or null (capability unknown because the record
// predates the field). A null capability must never be treated as "not
// offered", so legacy records keep their existing behaviour.
function windowIsOffered(record, windowClass) {
    var supported = supportedWindowClasses(record);
    if (supported === null) return null;
    return supported.indexOf(windowClass) !== -1;
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
    if (windowClass === "five_hour") return "Usage limit over a 5-hour window";
    if (windowClass === "week") return "Usage limit over a 7-day window";
    if (windowClass === "month") return "Usage limit over a rolling 30-day window";
    return "";
}

// Short window name for a cell tooltip's first line.
function windowTooltipName(windowClass) {
    if (windowClass === "five_hour") return "5-hour";
    if (windowClass === "week") return "Weekly";
    if (windowClass === "month") return "Monthly";
    return defaultWindowName(windowClass);
}

// Lower-case window name for the not-offered / not-reported sentences.
function windowLowerName(windowClass) {
    if (windowClass === "five_hour") return "5-hour";
    if (windowClass === "week") return "weekly";
    if (windowClass === "month") return "monthly";
    return String(defaultWindowName(windowClass)).toLowerCase();
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

// The pace word shown inside a cell's detail pane. It speaks about the user's
// rate, not about a direction: "faster than pace" is the alarming case, while
// "within pace" is the healthy one. It is deliberately short so it fits beside
// a relative countdown. The matrix itself no longer prints pace words.
function paceWord(limit, nowMs) {
    var pace = paceInfo(limit, nowMs);
    if (!pace) return "";
    if (pace.onPace) return "on pace";
    return pace.behind ? "faster than pace" : "within pace";
}

function cellCountdown(limit, nowMs) {
    var remaining = resetMsFor(limit, nowMs);
    return remaining > 0 ? formatDuration(remaining) : "";
}

// One canonical matrix cell. `percent` is the always-present, colour-
// independent signal; the glyph/meter are secondary. Kept free of the
// absolute reset timestamp so 18 timestamps never clutter the grid; the
// absolute time lives in the per-account tab and the cell tooltip.
function matrixCell(limit, windowClass, nowMs, mode) {
    if (!limit || !isFinite(Number(limit.percent))) return null;
    var used = Number(limit.percent);
    // SEVERITY IS DERIVED FROM USED, NOT FROM THE DISPLAYED NUMBER. The warn /
    // critical thresholds are risk thresholds about consumed headroom, so a
    // cell reading "10% remaining" is MORE dangerous than one reading "10%
    // used". Keeping severity used-based means the critical `●` glyph agrees
    // with the red tint and a real alarm is never hidden by the mode
    // inversion. Do NOT invert severity to match the displayed percentage.
    var severity = severityForLimit(limit);
    var pace = paceInfo(limit, nowMs);
    var projection = projectExhaustion(limit, nowMs);
    return {
        windowClass: windowClass,
        label: String(limit.label || defaultWindowName(windowClass)),
        // `usedPercent` is the raw risk fraction for non-visual consumers;
        // `percent` is the mode-aware meter fill the dashboard renders.
        usedPercent: used,
        percent: displayPercent(used, mode),
        percentText: Math.round(displayPercent(used, mode) * 100) + "%",
        severity: severity,
        glyph: severityGlyph(severity),
        elapsed: pace ? displayMarker(pace.elapsed, mode) : -1,
        paceWord: paceWord(limit, nowMs),
        countdown: cellCountdown(limit, nowMs),
        resetsAt: String(limit.resetsAt || ""),
        absoluteReset: formatResetAbsolute(limit.resetsAt),
        // Projection-derived signals for the cell tooltip. They are computed
        // once here so the tooltip and the amber marker agree by construction.
        meaningfullyFast: isMeaningfullyFast(limit, nowMs),
        msToEmpty: projection ? projection.msToEmpty : -1
    };
}

// Exact marker glyph for one matrix column. Three visibly distinct states:
//   * a reported window renders its mode-aware percentage;
//   * a supported-but-unreported window renders the em dash `—` (a real gap);
//   * a window the provider does not offer renders the en dash `–` (muted,
//     never a diagnostic). The two dashes are deliberately different code
//     points so the states are distinguishable without relying on colour.
function matrixCellMarker(cell, notOffered) {
    if (cell) return String(cell.percentText || "—");
    return notOffered ? "–" : "—";
}

// The provider display name used by every tooltip and status line. This is the
// SAME `record.name || record.id` the bar tooltip uses. It deliberately never
// reads `record.account`: identity (email, name, billing) is a private detail
// shown only in the collapsed-by-default ACCOUNT DETAILS section.
function providerDisplayName(record) {
    var name = String((record && (record.name || record.id)) || "");
    return name !== "" ? name : "This provider";
}

// Structured cell tooltip. It says only what the cell does not already show,
// in at most three lines, per the state table. Line 2 always states USED,
// because the cell already shows the mode-aware number.
function cellTooltipLines(cell, windowClass, notOffered, mode, record, nowMs, tzOffsetMin) {
    var provider = providerDisplayName(record);
    var lines = [];
    if (!cell) {
        lines.push({
            text: notOffered
                ? provider + " has no " + windowLowerName(windowClass) + " limit"
                : provider + " didn't report its " + windowLowerName(windowClass) + " limit",
            tone: "default",
            strong: true
        });
        return lines;
    }
    var usedPct = Math.round(Number(cell.usedPercent) * 100);
    var resetText = formatResetLocal(cell.resetsAt, nowMs, tzOffsetMin);
    var detail = usedPct + "% used";
    if (resetText !== "") detail += " · resets " + resetText;
    lines.push({ text: provider + " · " + windowTooltipName(windowClass), tone: "default", strong: true });
    lines.push({ text: detail, tone: "default", strong: false });
    if (cell.severity === "critical" && cell.isBinding === true) {
        lines.push({ text: "Blocking " + provider + " until then", tone: "error", strong: false });
    } else if (cell.muted === true) {
        lines.push({ text: "Not the limit blocking " + provider, tone: "default", strong: false });
    } else if (cell.meaningfullyFast === true && Number(cell.msToEmpty) > 0) {
        lines.push({
            text: "Runs out in ~" + formatDuration(cell.msToEmpty) + " at this rate",
            tone: "warning",
            strong: false
        });
    }
    return lines;
}

// Exact plain-text tooltip for one matrix column. It is the "\n" join of the
// structured cell tooltip, so the visual and plain contracts can never drift.
// `accountName` is optional and falls back to "This provider".
function matrixCellTooltip(cell, windowClass, notOffered, mode, accountName) {
    var record = accountName === undefined || accountName === null || String(accountName) === ""
        ? null : { name: String(accountName) };
    return cellTooltipLines(cell, windowClass, notOffered, mode, record, NaN, 0)
        .map(function (line) { return line.text; })
        .join("\n");
}

// Screen-reader text for one matrix column: the same lines joined with ", ",
// so the visual and non-visual wording can never diverge.
function matrixCellAccessibility(cell, windowClass, notOffered, mode, record, nowMs, tzOffsetMin) {
    return cellTooltipLines(cell, windowClass, notOffered, mode, record, nowMs, tzOffsetMin)
        .map(function (line) { return line.text; })
        .join(", ");
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
// Severity-derived headline for an account row. The word is deliberately
// mode-INDEPENDENT: "Blocked" states the account's risk, not how the binding
// window's percentage is displayed. It must never say "available" or
// "usable", which would contradict "Blocked" when another window is exhausted.
function headlineFor(severity, hasLimits) {
    if (!hasLimits) return "no live limits";
    if (severity === "critical") return "Blocked";
    if (severity === "warn") return "Near limit";
    return "";
}

// Number of accounts whose headline severity is critical. The dashboard header
// shows this only when it is greater than zero.
function blockedCount(rows) {
    return (rows || []).filter(function (row) {
        return row && row.headlineSeverity === "critical";
    }).length;
}

// Per-account status line for the matrix ACCOUNT cell. `tone` selects the text
// colour and `dotTone` the 8 px dot; both are role names the view maps to
// Theme tokens. "no live limits" is a normal state with a neutral dot, never
// a fabricated percentage.
function accountStatus(row, nowMs) {
    if (!row) return { text: "No live limits", tone: "neutral", dotTone: "neutral" };
    if (row.noLiveLimits === true) {
        return { text: "No live limits", tone: "neutral", dotTone: "neutral" };
    }
    var severity = String(row.headlineSeverity || "unknown");
    if (severity === "critical") {
        var binding = row.bindingWindowClass && row.windows
            ? row.windows[row.bindingWindowClass] : null;
        var countdown = binding && binding.countdown ? String(binding.countdown) : "";
        return {
            text: countdown !== "" ? "Blocked · " + countdown : "Blocked",
            tone: "error",
            dotTone: "error"
        };
    }
    if (severity === "warn") {
        return { text: "Near limit", tone: "warning", dotTone: "warning" };
    }
    var windows = row.windows || {};
    for (var key in windows) {
        if (!Object.prototype.hasOwnProperty.call(windows, key)) continue;
        if (windows[key] && windows[key].meaningfullyFast === true) {
            return { text: "Faster than pace", tone: "warning", dotTone: "warning" };
        }
    }
    return { text: "Healthy", tone: "neutral", dotTone: "success" };
}

// The dashboard footer hint. It is the single owner of the priority order, so
// the view only renders what this returns. `kind` selects the renderer:
// "text" (a plain hint), "legend" (the two mini pace meters) or "keys" (the
// key-cap row). The stale hint wins over everything and is the only warning
// tone; the idle rotation cycles the last three entries by `idleIndex`.
function footerHint(ctx) {
    var c = ctx || {};
    if (c.stale === true) {
        var age = String(c.ageText || "").trim();
        return {
            priority: 1,
            kind: "text",
            text: "Usage data is " + (age !== "" ? age : "old") + " old · press R to refresh",
            tone: "warning"
        };
    }
    if (c.keyboard === true) {
        return {
            priority: 2,
            kind: "keys",
            text: "↑↓ select   ↵ details   R refresh   Esc close",
            tone: "default"
        };
    }
    if (String(c.hoverColumn || "") !== "") {
        return { priority: 3, kind: "legend", text: "", tone: "default" };
    }
    if (Number(c.hoverRow) >= 0) {
        var account = String(c.hoverAccount || "account");
        return {
            priority: 4,
            kind: "text",
            text: c.rowSelected === true
                ? "Click again to collapse"
                : "Click for " + account + " limits, models and history",
            tone: "default"
        };
    }
    var rotation = [
        { kind: "text", text: "Click an account for limits, models and history" },
        { kind: "legend", text: "" },
        { kind: "keys", text: "↑↓ select   ↵ details   R refresh   Esc close" }
    ];
    var index = Number(c.idleIndex);
    if (!isFinite(index)) index = 0;
    var chosen = rotation[((Math.round(index) % rotation.length) + rotation.length) % rotation.length];
    return { priority: 5, kind: chosen.kind, text: chosen.text, tone: "default" };
}

function matrixRow(record, nowMs, mode) {
    var limits = (record && record.limits) || [];
    var binding = bindingLimit(record, nowMs);
    var bindingClass = binding ? classifyWindow(binding) : "";
    var bindingLabel = binding ? String(binding.label || "") : "";
    var severity = binding ? severityForLimit(binding) : "unknown";
    var hasLimits = hasLiveLimits(record);
    var supported = supportedWindowClasses(record);
    var windows = {};
    var notOffered = {};
    CANONICAL_WINDOW_ORDER.forEach(function (windowClass) {
        var worst = worstLimitFor(limits, windowClass);
        var cell = matrixCell(worst, windowClass, nowMs, mode);
        if (cell) {
            // Pin to the binding limit's class AND label so a duplicate bucket
            // in the same class cannot mis-mark the window that is actually
            // limiting the account.
            cell.isBinding = binding !== null && windowClass === bindingClass &&
                String(worst.label || "") === bindingLabel;
            // When the account is blocked, de-emphasise only the non-binding
            // windows that are NOT themselves alerts so the eye goes to the
            // window that is doing the blocking. P1: a cell whose own severity
            // is warn/critical is never dimmed merely because another window
            // is the current binding constraint -- that would erase a second
            // simultaneous alarm.
            cell.muted = severity === "critical" && cell.isBinding !== true &&
                !isAlertSeverity(cell.severity);
        }
        windows[windowClass] = cell;
        // Only a declared capability can mark a column "not offered". A column
        // outside the provider's set is a non-problem (a distinct muted marker
        // and no unmet-condition diagnostic); a declared column with no report
        // is a real gap. A record that declares nothing stays legacy-unknown.
        notOffered[windowClass] = cell === null && supported !== null &&
            supported.indexOf(windowClass) === -1;
    });
    return {
        id: String((record && record.id) || ""),
        name: String((record && (record.name || record.id)) || ""),
        record: record || null,
        windows: windows,
        notOffered: notOffered,
        bindingWindowClass: bindingClass,
        headlineText: headlineFor(severity, hasLimits),
        headlineSeverity: severity,
        todayTokens: formatTokens(todayUsage(record).billable),
        noLiveLimits: !hasLimits,
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

function matrixRows(records, nowMs, mode) {
    return accountOrder(records).map(function (record) {
        return matrixRow(record, nowMs, mode);
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
function limitDetailRows(record, nowMs, mode) {
    var binding = bindingLimit(record, nowMs);
    var bindingClass = binding ? classifyWindow(binding) : "";
    var bindingLabel = binding ? String(binding.label || "") : "";
    return ((record && record.limits) || []).map(function (limit) {
        var windowClass = classifyWindow(limit);
        var live = limitIsLive(limit);
        var used = Number(limit && limit.percent);
        var severity = live ? severityForLimit(limit) : "unknown";
        var pace = paceInfo(limit, nowMs);
        return {
            windowClass: windowClass,
            isUnknown: windowClass === "unknown",
            isOther: windowClass === "other",
            isBinding: binding !== null && windowClass === bindingClass &&
                String(limit && limit.label || "") === bindingLabel,
            title: windowClass === "unknown"
                ? "duration not reported"
                : (String(limit && limit.label || "") || defaultWindowName(windowClass)),
            percent: live ? displayPercent(used, mode) : -1,
            percentText: live ? Math.round(displayPercent(used, mode) * 100) + "%" : "—",
            severity: severity,
            glyph: live ? severityGlyph(severity) : "",
            elapsed: pace ? displayMarker(pace.elapsed, mode) : -1,
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
    // "Not reported" versus "not offered". A canonical column the provider
    // declares as supported but does not include is a REAL unmet condition and
    // keeps its diagnostic; a column the provider does not offer is a
    // non-problem and must never be logged (logging a non-problem trains the
    // user and the log to ignore real ones). A record with no declared
    // capability keeps the legacy behaviour and logs neither.
    var supported = supportedWindowClasses(record);
    if (supported !== null) {
        supported.forEach(function (windowClass) {
            var reported = (limits || []).some(function (limit) {
                return classifyWindow(limit) === windowClass;
            });
            if (!reported) {
                pushDiagnostic(out, record, "missing_window", defaultWindowName(windowClass));
            }
        });
        (limits || []).forEach(function (limit, index) {
            var windowClass = classifyWindow(limit);
            if (windowClass !== "five_hour" && windowClass !== "week" && windowClass !== "month") return;
            if (supported.indexOf(windowClass) === -1) {
                // The server reported a window the collector did not declare:
                // keep rendering the real data, but make the inconsistency
                // observable instead of hiding it.
                pushDiagnostic(out, record, "undeclared_window", limitDiagnosticLabel(limit, index));
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
