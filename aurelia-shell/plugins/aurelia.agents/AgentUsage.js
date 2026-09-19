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
