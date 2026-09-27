#!/usr/bin/env bash

# Agents durable anti-flood notification policy suite.
#
# The policy in AgentUsage.js is pure: these scenarios run under node with no
# QML, no timers, no network and no live workstation mutation. Each scenario is
# deterministic and exercises the exact rules the widget relies on.

set -Eeuo pipefail

section "Aurelia Agents Notification Policy"

if ! command -v node >/dev/null; then
    skip "[unit] agents anti-flood notification policy (node unavailable)"
    return 0
fi

plugin_dir="$ROOT/plugins/aurelia.agents"
notification_test="$(mktemp --suffix=.js)"
scenario_file="$(mktemp --suffix=.scenarios.js)"
scenario_log="$(mktemp --suffix=.log)"
trap 'rm -f -- "$notification_test" "$scenario_file" "$scenario_log" || true' RETURN

sed '/^\.pragma library/d' "$plugin_dir/AgentUsage.js" >"$notification_test"
cat >>"$notification_test" <<'AGENT_NOTIFICATION_EXPORTS'
module.exports = { notificationPlan, serializeNotificationState, deserializeNotificationState, emptyNotificationState, todayDate, severityForLimit };
AGENT_NOTIFICATION_EXPORTS

cat >"$scenario_file" <<'NODE_SCENARIOS'
const A = require(process.argv[2]);
const DND = require(process.argv[3]);

const T0 = 1700000000000;
const R0 = "2030-01-01T00:00:00Z";
const R0MS = Date.parse(R0);
const MIN = 30 * 60 * 1000;
const LIMIT_OPTS = { renewals: false };

const ISO = ms => new Date(ms).toISOString();
function agent(id, percent, resetsAt, daysLeft) {
    const record = {
        id: id,
        name: id,
        ready: true,
        limits: [{ label: "Weekly", percent: percent, resetsAt: resetsAt }]
    };
    if (daysLeft !== undefined) record.subscription = { renew: RENEW, daysLeft: daysLeft, reminderDays: 3 };
    return record;
}
function localDate(ms) {
    const d = new Date(ms);
    const p = n => String(n).padStart(2, "0");
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}
const RENEW = localDate(T0);
function many(count, percent) {
    const out = [];
    for (let i = 0; i < count; i++) out.push(agent("acct" + i, percent, R0));
    return out;
}

const results = [];
function check(name, ok, detail) {
    results.push({ name: name, ok: !!ok, detail: detail === undefined ? "" : String(detail) });
}

// --- baseline and one-threshold transition ---------------------------------
const firstOk = A.notificationPlan([agent("codex", 0.5, R0)], A.emptyNotificationState(), LIMIT_OPTS, T0);
check("first observation is baseline-suppressed", firstOk.notifications.length === 0, firstOk.notifications.length);
const firstCritical = A.notificationPlan([agent("codex", 0.95, R0)], A.emptyNotificationState(), LIMIT_OPTS, T0);
check("first observation suppresses even at critical", firstCritical.notifications.length === 0, firstCritical.notifications.length);
const crossing = A.notificationPlan([agent("codex", 0.8, R0)], firstOk.state, LIMIT_OPTS, T0 + 1000);
check("crossing one threshold notifies once", crossing.notifications.length === 1, crossing.notifications.length);

// --- repeated refreshes while the condition persists ------------------------
let repeatState = crossing.state;
let repeats = 0;
for (let k = 0; k < 20; k++) {
    const step = A.notificationPlan([agent("codex", 0.8, R0)], repeatState, LIMIT_OPTS, T0 + 2000 + k * 1000);
    repeats += step.notifications.length;
    repeatState = step.state;
}
check("20 persisted refreshes notify zero", repeats === 0, repeats);

// --- recovery re-arms; a later re-cross notifies exactly once ---------------
const recovered = A.notificationPlan([agent("codex", 0.5, R0)], repeatState, LIMIT_OPTS, T0 + 25000);
check("recovery is silent", recovered.notifications.length === 0, recovered.notifications.length);
const reCrossed = A.notificationPlan([agent("codex", 0.8, R0)], recovered.state, LIMIT_OPTS, T0 + 1000 + MIN + 1);
check("later re-cross notifies exactly once", reCrossed.notifications.length === 1, reCrossed.notifications.length);
const reCrossAgain = A.notificationPlan([agent("codex", 0.8, R0)], reCrossed.state, LIMIT_OPTS, T0 + 1000 + MIN + 2);
check("re-cross repeat is silent", reCrossAgain.notifications.length === 0, reCrossAgain.notifications.length);

// --- resetsAt jitter versus a genuine forward reset -------------------------
const jitterBase = A.notificationPlan([agent("codex", 0.1, R0)], A.emptyNotificationState(), LIMIT_OPTS, T0);
let jitterState = jitterBase.state;
let jitterCount = 0;
for (let k = 1; k <= 20; k++) {
    const step = A.notificationPlan([agent("codex", 0.1, ISO(R0MS + k * 1000))], jitterState, LIMIT_OPTS, T0 + k * 1000);
    jitterCount += step.notifications.length;
    jitterState = step.state;
}
check("resetsAt jitter emits zero reset notifications", jitterCount === 0, jitterCount);
const genuineReset = A.notificationPlan(
    [agent("codex", 0.1, ISO(R0MS + 6 * 3600 * 1000))], jitterState, LIMIT_OPTS, T0 + 21000);
check("genuine forward reset emits exactly one",
    genuineReset.notifications.length === 1 && genuineReset.notifications[0].kind === "reset",
    genuineReset.notifications.length);

// --- oscillation is absorbed by the minimum interval ------------------------
const oscillationBase = A.notificationPlan([agent("codex", 0.1, R0)], A.emptyNotificationState(), LIMIT_OPTS, T0);
let oscillationState = oscillationBase.state;
let oscillationCount = 0;
for (let k = 0; k < 20; k++) {
    const percent = k % 2 === 0 ? 0.8 : 0.1;
    const step = A.notificationPlan([agent("codex", percent, R0)], oscillationState, LIMIT_OPTS, T0 + 1000 + k * 1000);
    oscillationCount += step.notifications.length;
    oscillationState = step.state;
}
check("severity oscillation stays bounded", oscillationCount <= 1, oscillationCount);

// --- hard bounds ------------------------------------------------------------
const capBase = A.notificationPlan(many(50, 0.1), A.emptyNotificationState(), LIMIT_OPTS, T0);
const capCross = A.notificationPlan(many(50, 0.95), capBase.state, LIMIT_OPTS, T0 + 1000);
const aggregates = capCross.notifications.filter(n => n.kind === "aggregate");
check("50 critical accounts stay within the hourly cap", capCross.notifications.length <= 6, capCross.notifications.length);
check("a capped refresh emits one aggregate line",
    aggregates.length === 1 && /and 45 more/.test(aggregates[0].body),
    aggregates.length ? aggregates[0].body : "none");

const twoWindowBase = A.notificationPlan(
    [{ id: "multi", name: "multi", ready: true, limits: [
        { label: "5h", percent: 0.1, resetsAt: R0 }, { label: "Weekly", percent: 0.1, resetsAt: R0 }] }],
    A.emptyNotificationState(), LIMIT_OPTS, T0);
const twoWindowCross = A.notificationPlan(
    [{ id: "multi", name: "multi", ready: true, limits: [
        { label: "5h", percent: 0.95, resetsAt: R0 }, { label: "Weekly", percent: 0.95, resetsAt: R0 }] }],
    twoWindowBase.state, LIMIT_OPTS, T0 + 1000);
check("one critical per account per evaluation", twoWindowCross.notifications.length === 1, twoWindowCross.notifications.length);

const twoBase = A.notificationPlan([agent("x", 0.1, R0), agent("y", 0.1, R0)], A.emptyNotificationState(), LIMIT_OPTS, T0);
const twoCross = A.notificationPlan([agent("x", 0.95, R0), agent("y", 0.95, R0)], twoBase.state, LIMIT_OPTS, T0 + 1000);
check("two accounts crossing yield two, not four", twoCross.notifications.length === 2, twoCross.notifications.length);

// --- settings actually change behaviour -------------------------------------
const criticalBase = A.notificationPlan([agent("codex", 0.1, R0)], A.emptyNotificationState(),
    { minSeverity: "critical", renewals: false }, T0);
const warnCross = A.notificationPlan([agent("codex", 0.8, R0)], criticalBase.state,
    { minSeverity: "critical", renewals: false }, T0 + 1000);
check("critical-only suppresses a warn crossing", warnCross.notifications.length === 0, warnCross.notifications.length);
const criticalCross = A.notificationPlan([agent("codex", 0.95, R0)], warnCross.state,
    { minSeverity: "critical", renewals: false }, T0 + 2000);
check("critical-only allows a critical crossing", criticalCross.notifications.length === 1, criticalCross.notifications.length);

const enabledBase = A.notificationPlan([agent("codex", 0.1, R0)], A.emptyNotificationState(),
    { enabled: true, renewals: false }, T0);
const disabledCross = A.notificationPlan([agent("codex", 0.8, R0)], enabledBase.state,
    { enabled: false, renewals: false }, T0 + 1000);
const enabledCross = A.notificationPlan([agent("codex", 0.8, R0)], enabledBase.state,
    { enabled: true, renewals: false }, T0 + 1000);
check("disabled yields zero where enabled yields one",
    disabledCross.notifications.length === 0 && enabledCross.notifications.length === 1,
    disabledCross.notifications.length + "/" + enabledCross.notifications.length);

const seededRenewal = { renewals: { "id:codex": { announcedForDate: "2020-01-01", renewValue: RENEW } } };
const renewalOn = A.notificationPlan([agent("codex", 0.1, R0, 2)], seededRenewal, { renewals: true }, T0);
const renewalOff = A.notificationPlan([agent("codex", 0.1, R0, 2)], seededRenewal, { renewals: false }, T0);
check("renewals setting changes behaviour",
    renewalOn.notifications.length === 1 && renewalOff.notifications.length === 0,
    renewalOn.notifications.length + "/" + renewalOff.notifications.length);

// Derived daysLeft: the record omits it, so it must come from `renew`.
const derivedRenewal = A.notificationPlan(
    [{ id: "codex", name: "codex", ready: true, limits: [], subscription: { renew: RENEW, reminderDays: 3 } }],
    { renewals: { "id:codex": { announcedForDate: "2020-01-01", renewValue: RENEW } } },
    { renewals: true }, T0);
check("daysLeft is derived from renew when omitted", derivedRenewal.notifications.length === 1, derivedRenewal.notifications.length);

// --- persistence, restart, renewal date change ------------------------------
const serialized = A.serializeNotificationState(reCrossed.state);
const restored = A.deserializeNotificationState(serialized);
check("state survives a serialize/deserialize round-trip",
    A.serializeNotificationState(restored) === serialized);
const restartLimit = A.notificationPlan([agent("codex", 0.8, R0)], restored, LIMIT_OPTS, T0 + 1000 + MIN + 2);
check("simulated restart re-announces no limit", restartLimit.notifications.length === 0, restartLimit.notifications.length);

const renewalBase = A.notificationPlan([agent("codex", 0.1, R0, 3)], A.emptyNotificationState(), { renewals: true }, T0);
check("renewal first observation is baseline-suppressed", renewalBase.notifications.length === 0, renewalBase.notifications.length);
const nextDay = T0 + 86400000;
const sameRenewNextDay = A.notificationPlan([agent("codex", 0.1, R0, 2)], renewalBase.state, { renewals: true }, nextDay);
check("renewal notifies once when the local date changes", sameRenewNextDay.notifications.length === 1, sameRenewNextDay.notifications.length);
const renewalRestart = A.notificationPlan([agent("codex", 0.1, R0, 2)],
    A.deserializeNotificationState(A.serializeNotificationState(sameRenewNextDay.state)), { renewals: true }, nextDay + 1000);
check("simulated restart re-fires no same-day renewal", renewalRestart.notifications.length === 0, renewalRestart.notifications.length);

// --- fail-safe state parsing ------------------------------------------------
check("missing state deserializes to empty", Object.keys(A.deserializeNotificationState("").windows).length === 0);
check("corrupt state deserializes to empty",
    Object.keys(A.deserializeNotificationState("{not json").windows).length === 0);
const recoveredFromCorrupt = A.notificationPlan([agent("codex", 0.95, R0)],
    A.deserializeNotificationState("{not json"), LIMIT_OPTS, T0);
check("corrupt state baseline-suppresses instead of bursting", recoveredFromCorrupt.notifications.length === 0, recoveredFromCorrupt.notifications.length);

// --- identity fallback ------------------------------------------------------
const anonOne = { name: "", ready: true, limits: [{ label: "W", percent: 0.1, resetsAt: R0 }] };
const anonTwo = { name: "", ready: true, limits: [{ label: "W", percent: 0.1, resetsAt: R0 }] };
const anonBase = A.notificationPlan([anonOne, anonTwo], A.emptyNotificationState(), LIMIT_OPTS, T0);
const anonCross = A.notificationPlan([
    Object.assign({}, anonOne, { limits: [{ label: "W", percent: 0.95, resetsAt: R0 }] }),
    Object.assign({}, anonTwo, { limits: [{ label: "W", percent: 0.95, resetsAt: R0 }] })
], anonBase.state, LIMIT_OPTS, T0 + 1000);
check("id-less records do not collide", anonCross.notifications.length === 2, anonCross.notifications.length);

// --- DND: the chosen app name must remain a non-bypassing one ----------------
// The first-party sender defaults to "aurelia-action", which the notification
// service treats as a DND bypass. "Aurelia Agents" is deliberately normal.
check("Aurelia Agents app name respects DND",
    DND.shouldBypassDnd({ appName: "Aurelia Agents", urgency: 1 }, 2) === false);
check("sender default app name would bypass DND",
    DND.shouldBypassDnd({ appName: "aurelia-action", urgency: 1 }, 2) === true);

for (const result of results) {
    if (result.ok) console.log("PASS\t" + result.name);
    else console.log("FAIL\t" + result.name + "\t" + result.detail);
}
NODE_SCENARIOS

scenario_status=0
scenario_output="$(node "$scenario_file" "$notification_test" "$ROOT/plugins/aurelia.notifications/NotificationLogic.js" 2>"$scenario_log")" || scenario_status=$?
if [[ "$scenario_status" -ne 0 ]]; then
    fail "[unit] agents anti-flood notification policy scenarios crashed"
    sed 's/^/    /' "$scenario_log" >&2 || true
else
    while IFS=$'\t' read -r status name detail; do
        [[ -n "$status" ]] || continue
        if [[ "$status" == "PASS" ]]; then
            pass "[unit] $name"
        else
            fail "[unit] $name (observed: ${detail:-?})"
        fi
    done <<<"$scenario_output"
fi
