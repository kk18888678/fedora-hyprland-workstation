#!/usr/bin/env bash

# Agents plugin test suite: the AI usage collector, the `workstation-ai usage`
# backend contract, the pure record projection, and the aurelia.agents plugin
# wiring. All behavior runs against disposable sandboxes; nothing here touches
# the live workstation.

set -Eeuo pipefail

section "Aurelia Agents Plugin"

repo_root="$(cd -- "$ROOT/.." && pwd -P)"
plugin_dir="$ROOT/plugins/aurelia.agents"
backend="$repo_root/bin/workstation-ai"
collector="$repo_root/bin/ai-usage-claude"

# ---------------------------------------------------------------------------
# Static invariants
# ---------------------------------------------------------------------------
if [[ -f "$plugin_dir/manifest.json" && -f "$plugin_dir/AgentsBarWidget.qml" &&
      -f "$plugin_dir/AgentsPanel.qml" && -f "$plugin_dir/AgentUsage.js" ]]; then
    pass "[static] agents plugin ships manifest, widget, panel, and record projection"
else
    fail "[static] agents plugin files are incomplete"
fi

if jq -e '.id == "aurelia.agents" and .name == "AI Usage" and .kinds == ["bar-widget"] and
          .entryPoints.barWidget == "AgentsBarWidget.qml" and
          .barWidget.defaultSection == "right" and
          .barWidget.displayName == "AI Usage" and
          .barWidget.defaults.percentMode == "remaining" and
          (.barWidget.schema | length == 1) and
          .barWidget.schema[0].key == "percentMode" and
          .barWidget.schema[0].type == "enum" and
          .barWidget.schema[0].defaultValue == "remaining" and
          .barWidget.schema[0].options[0].value == "remaining" and
          .barWidget.schema[0].options[1].value == "used"' \
       "$plugin_dir/manifest.json" >/dev/null; then
    pass "[static] agents manifest is the AI Usage bar widget with a remaining-default percentage setting"
else
    fail "[static] agents manifest contract is invalid"
fi

# Percentage presentation is normalized in exactly one place so the number and
# the meter fill can never disagree, and the setting is overlaid from manifest
# defaults (which reach an existing shell.json with an explicit bar).
if grep -q 'function normalizePercentMode(value)' "$plugin_dir/AgentUsage.js" &&
   grep -q 'normalizePercentMode(mode) === "used" ? used : 1 - used' "$plugin_dir/AgentUsage.js" &&
   grep -q 'normalizePercentMode(mode) === "used" ? elapsed : 1 - elapsed' "$plugin_dir/AgentUsage.js" &&
   grep -q 'percentMode: AgentUsage.normalizePercentMode' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'percentMode: AgentUsage.normalizePercentMode' "$plugin_dir/AgentsDashboard.qml" &&
   grep -q 'AgentUsage.overallFreshnessPill' "$plugin_dir/AgentsBarWidget.qml" &&
   ! grep -q '"Updated " + freshness.text' "$plugin_dir/AgentsBarWidget.qml"; then
    pass "[static] agents percentage mode has one normalization/inversion point and a truthful unit-aware tooltip"
else
    fail "[static] agents percentage-mode normalization or freshness wiring is incomplete"
fi

if grep -q 'text: "AI Usage"' "$plugin_dir/AgentsDashboard.qml" &&
   ! grep -qE 'text: "Usage"' "$plugin_dir/AgentsDashboard.qml" &&
   grep -q 'agentsModeChip' "$plugin_dir/AgentsDashboard.qml" &&
   grep -q '· % remaining' "$plugin_dir/AgentsDashboard.qml" &&
   grep -q 'bindingWindowClass' "$plugin_dir/AgentUsage.js" &&
   grep -q 'headlineText' "$plugin_dir/AgentsDashboard.qml" &&
   grep -q 'headlineSeverity' "$plugin_dir/AgentsDashboard.qml" &&
   grep -q 'AgentUsage.overallFreshnessPill' "$plugin_dir/AgentsDashboard.qml" &&
   grep -q 'actionTargets: hasSelection ? \["refresh", "close"\] : \["refresh"\]' "$plugin_dir/AgentsDashboard.qml" &&
   grep -q 'id: headerRefreshButton' "$plugin_dir/AgentsDashboard.qml" &&
   ! grep -q 'id: refreshButton' "$plugin_dir/AgentsDashboard.qml"; then
    pass "[static] AI Usage dashboard titles the panel, legends the mode, communicates the binding window and pins refresh above the matrix"
else
    fail "[static] AI Usage dashboard title/mode/binding/refresh contract is incomplete"
fi

if grep -q 'visible: root.hasAgents' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q '"usage-update"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q '"usage"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AgentUsage.parseRecords' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'applyLimitNotifications' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'notify-send' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AgentUsage.bindingLimit' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AgentUsage.barState' "$plugin_dir/AgentsBarWidget.qml"; then
    pass "[static] agents widget refreshes through workstation-ai and derives state from the record contract"
else
    fail "[static] agents widget backend wiring is incomplete"
fi

# Icon-only bar affordance: a square slot with one shared-primitive glyph and a
# 4 px warn/critical/error dot. No text label, percentage, provider label or
# countdown may survive, and there is no wheel handler.
if grep -q 'glyph: "󰚩"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AureliaIcon {' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'width: root.iconCanvas' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'height: root.iconCanvas' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'iconSize: root.iconCanvas' "$plugin_dir/AgentsBarWidget.qml" &&
   ! grep -q 'id: agentLabel' "$plugin_dir/AgentsBarWidget.qml" &&
   ! grep -q 'statusText' "$plugin_dir/AgentsBarWidget.qml" &&
   ! grep -q 'agentLabel' "$plugin_dir/AgentsBarWidget.qml" &&
   ! grep -q 'Text {' "$plugin_dir/AgentsBarWidget.qml" &&
   ! grep -q 'onWheel' "$plugin_dir/AgentsBarWidget.qml" &&
   ! grep -q 'todayTokens' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'radius: Theme.radiusSm' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'width: 4' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'visible: root.stateDot' "$plugin_dir/AgentsBarWidget.qml"; then
    pass "[static] agents bar affordance is an icon-only square slot with a 4 px warn/critical/error dot"
else
    fail "[static] agents bar affordance is not icon-only or still carries text state"
fi

# The hover fill must never replace the severity tint (the old containsMouse
# accent bug erased the alarm exactly when the user hovered to inspect it).
if grep -q 'root.isVisible() || pointerHover.hovered ? Theme.selection : "transparent"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'tint: root.stateTint === "barForeground" ? root.barForeground : root.statusColor' "$plugin_dir/AgentsBarWidget.qml" &&
   ! grep -q 'containsMouse ? Theme.accent' "$plugin_dir/AgentsBarWidget.qml"; then
    pass "[static] hover paints only the selection fill and never overrides the agents severity tint"
else
    fail "[static] hover still overrides the agents severity tint"
fi

if grep -q 'function open(payloadJson)' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'function close()' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'function toggle(payloadJson)' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'function isVisible()' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'readonly property bool ipcOwner' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'property bool ipcReady' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'active: root.ipcOwner && root.ipcReady' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'target: "aurelia.agents"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AureliaToolTip {' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'function tooltipText()' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'mouse.button === Qt.RightButton' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'mouse.button === Qt.MiddleButton' "$plugin_dir/AgentsBarWidget.qml"; then
    pass "[static] agents widget exposes the peer open/close/toggle/isVisible IPC contract and truthful tooltip"
else
    fail "[static] agents widget peer API, IPC ownership, or click contract is incomplete"
fi

if grep -q 'aurelia.agents' "$ROOT/config/bar-default.json" &&
   grep -q 'aurelia.agents' "$ROOT/services/BarDefaultConfig.qml"; then
    pass "[static] agents widget is present in the canonical default bar and its recovery fallback"
else
    fail "[static] agents widget is missing from the default bar sources"
fi

if [[ -x "$collector" ]] &&
   grep -q 'usage-update' "$backend" &&
   grep -q 'cmd_usage_update' "$backend" &&
   grep -q 'cmd_usage()' "$backend" &&
   for agent in claude codex cline opencode; do
       [[ -x "$repo_root/bin/ai-usage-$agent" ]] || false
   done &&
   grep -q 'zen/go/v1/usage' "$repo_root/bin/ai-usage-opencode" &&
   grep -q 'User-Agent' "$repo_root/bin/ai-usage-opencode"; then
    pass "[static] usage collectors are executable and the backend exposes usage/usage-update"
else
    fail "[static] usage backend or collector wiring is missing"
fi

dashboard="$plugin_dir/AgentsDashboard.qml"

if [[ -f "$dashboard" ]]; then
    pass "[static] agents dashboard ships as a dedicated panel body surface"
else
    fail "[static] agents dashboard surface is missing"
fi

if grep -q 'popupWidth: 460' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'contentSizingItem: dashboardLoader.item' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'focusTarget: dashboardLoader.item ? dashboardLoader.item.keyTarget : null' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'source: Qt.resolvedUrl("AgentsDashboard.qml")' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'ownerId: "aurelia.agents"' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'minPopupHeight: 220' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'maxPopupHeight: 640' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'Math.max(30, Math.min(3600, raw))' "$plugin_dir/AgentsBarWidget.qml"; then
    pass "[static] agents popup becomes the 460-unit dashboard and keeps the shared keyboard/placement policy"
else
    fail "[static] agents panel container contract is incomplete"
fi

if grep -q 'AgentUsage.matrixRows' "$dashboard" &&
   grep -q 'AgentUsage.canonicalWindowOrder' "$dashboard" &&
   grep -q 'AgentUsage.limitDetailRows' "$dashboard" &&
   grep -q 'AgentUsage.windowColumnLabel' "$dashboard" &&
   grep -q 'AgentUsage.balanceHeader' "$dashboard" &&
   grep -q 'AgentUsage.anyBalance' "$dashboard" &&
   grep -q 'ACCOUNT' "$dashboard" &&
   grep -q 'TODAY' "$dashboard" &&
   grep -q 'BALANCE' "$dashboard" &&
   grep -q 'no live limits' "$plugin_dir/AgentUsage.js" &&
   grep -q 'duration not reported' "$dashboard" &&
   grep -q 'LAST 7 DAYS' "$dashboard" &&
   grep -q 'MODELS · TODAY' "$dashboard" &&
   grep -q 'MODELS · ALL TIME' "$dashboard" &&
   grep -q 'AureliaActionButton' "$dashboard" &&
   grep -q 'AureliaIconButton' "$dashboard" &&
   grep -q 'matrixWindowColumnWidth' "$dashboard" &&
   grep -q 'Layout.fillWidth: false' "$dashboard" &&
   grep -q 'window-close' "$dashboard" &&
   grep -q 'view-refresh' "$dashboard" &&
   grep -q 'clearSelection' "$dashboard" &&
   grep -q 'Select an account for details' "$dashboard" &&
   ! grep -q 'tabStrip' "$dashboard" &&
   ! grep -q '"tabs"' "$dashboard" &&
   ! grep -q 'PROVIDERS' "$plugin_dir/AgentsPanel.qml" "$dashboard" &&
   ! grep -q 'ALL ACCOUNTS' "$plugin_dir/AgentsPanel.qml" "$dashboard" &&
   ! grep -q 'tokens today · ' "$dashboard"; then
    pass "[static] agents dashboard renders the pinned matrix, a shared column width, per-account detail and an icon-only action cluster"
else
    fail "[static] agents dashboard section redesign is incomplete"
fi

if grep -q 'stateInfo.key === "unknown"' "$dashboard" &&
   grep -q 'stateInfo.key === "rate-limited"' "$dashboard" &&
   grep -q 'stateInfo.retry' "$dashboard" &&
   grep -q 'stateInfo.help' "$dashboard"; then
    pass "[static] agents dashboard shows the state banner only for unknown/error/rate-limited with auth help and Retry"
else
    fail "[static] agents dashboard state banner contract is incomplete"
fi

# Every unmet condition logs a diagnostic through the shell's standard
# console.warn channel (read by `aurelia logs`); the visible labels stay too.
if grep -q 'AgentUsage.diagnoseRecords' "$dashboard" &&
   grep -q 'AgentUsage.collectorDiagnostic' "$dashboard" &&
   grep -q 'console.warn(AgentUsage.diagnosticLine' "$dashboard" &&
   grep -q 'function emitDiagnostics()' "$dashboard" &&
   grep -q 'absent_balance' "$plugin_dir/AgentUsage.js" &&
   grep -q 'collector_failed' "$plugin_dir/AgentUsage.js"; then
    pass "[static] agents dashboard logs every unmet condition while keeping the user-facing honesty labels"
else
    fail "[static] agents dashboard diagnostics contract is incomplete"
fi

# Every text node derives from the local Label primitive (which sets
# font.family); numeric cells derive from NumericLabel; no node uses the
# deprecated font.bold flag; the meter uses the shared control fill at
# max(3, spacingXs) px.
raw_text_count="$(grep -cE '(^|[[:space:]])Text \{' "$dashboard" || true)"
if grep -q 'component Label: Text {' "$dashboard" &&
   grep -q 'component NumericLabel: Label {' "$dashboard" &&
   grep -q 'font.family: Theme.fontFamilyResolved' "$dashboard" &&
   ! grep -q 'font.bold' "$dashboard" &&
   grep -q 'Theme.fontWeightBold' "$dashboard" &&
   grep -q 'Theme.controls.normalFill' "$dashboard" &&
   grep -q 'Math.max(3, Theme.spacingXs)' "$dashboard" &&
   (( raw_text_count <= 1 )); then
    pass "[static] agents dashboard inherits the bar font through one Label primitive and uses the weight/track tokens"
else
    fail "[static] agents dashboard typography contract is incomplete (rawText=$raw_text_count)"
fi

if grep -q 'Qt.Key_Escape' "$dashboard" &&
   grep -q 'Qt.Key_Tab' "$dashboard" &&
   grep -q 'Qt.Key_J' "$dashboard" &&
   grep -q 'Qt.Key_K' "$dashboard" &&
   grep -q 'Qt.Key_H' "$dashboard" &&
   grep -q 'Qt.Key_L' "$dashboard" &&
   grep -q 'Qt.Key_Return' "$dashboard" &&
   grep -q 'text === "r"' "$dashboard" &&
   grep -q 'function moveRegion(delta)' "$dashboard" &&
   grep -q 'function moveRow(delta)' "$dashboard" &&
   grep -q 'function switchAccount(delta)' "$dashboard" &&
   grep -q 'function clearSelection()' "$dashboard" &&
   grep -q 'function actionFocus(name)' "$dashboard" &&
   grep -q 'readonly property var actionTargets' "$dashboard" &&
   grep -q 'function ensureFocusVisible()' "$dashboard" &&
   grep -q 'function reconcileSelection' "$plugin_dir/AgentUsage.js"; then
    pass "[static] agents dashboard adopts the peer focus regions, Tab/Shift+Tab, j/k/h/l motion, id-based selection and r refresh"
else
    fail "[static] agents dashboard keyboard model is incomplete"
fi

# PanelWindow's default property only accepts QQuickItem children, so a
# non-visual Timer/QtObject declared at panel top level fails to load at
# runtime (and stays invisible to the offscreen type-unavailable fixture).
if ! grep -qE '^    (Timer|QtObject|Connections|NumberAnimation|PropertyAnimation|SequentialAnimation|ScriptAction) \{' \
       "$plugin_dir/AgentsPanel.qml"; then
    pass "[static] agents panel keeps non-visual children inside the content item"
else
    fail "[static] agents panel declares a non-visual child on the PanelWindow"
fi

# ---------------------------------------------------------------------------
# Pure record projection (node)
# ---------------------------------------------------------------------------
if command -v node >/dev/null; then
    projection_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_dir/AgentUsage.js" >"$projection_test"
    cat >>"$projection_test" <<'AGENT_USAGE_EXPORTS'
module.exports = { number, formatTokens, parseRecords, readyAgents, detectedAgents, todayTotal, tierLabel, sortedModels, recentBars, dayChartBars, bindingLimit, resetMsFor, formatDuration, updatedAtMs, recordAgeMs, isRecordStale, freshnessText, heroMeta, dayLabel, weekPeak, modelRows, todayModels, modelRowsFrom, dayTokens, todayUsage, planLabel, freshnessPill, formatResetAbsolute, paceLabel, providerWorstLabel, recordHasError, providerState, barState, billingSummary, subscriptionRows, clamp, todayDate, limitTransitions, severityFor, severityForLimit, overallSeverity, paceInfo, elapsedFraction, billingText, renewalReminders, classifyWindow, canonicalWindowOrder, windowColumnLabel, windowDescription, defaultWindowName, limitIsLive, liveLimits, hasLiveLimits, worstLimitFor, severityGlyph, paceWord, cellCountdown, matrixCell, matrixRow, matrixRows, accountOrder, reconcileSelection, limitDetailRows, hasBalance, anyBalance, balanceText, balanceHeader, diagnoseRecord, diagnoseRecords, collectorDiagnostic, diagnosticKey, diagnosticLine, normalizePercentMode, displayPercent, displayMarker, newestRecord, overallFreshnessPill, headlineFor };
AGENT_USAGE_EXPORTS
    if node -e '
const A = require(process.argv[1]);
const records = A.parseRecords(JSON.stringify({agents: [
    {id: "claude", ready: true, todayTotalTokens: 1500, tierLabel: "Max"},
    {id: "codex", ready: false, detected: true}
]}));
const bars = A.recentBars([
    {date: "2026-09-18", messageCount: 0},
    {date: "2026-09-19", messageCount: 10}
]);
const models = A.sortedModels({small: {inputTokens: 1}, big: {inputTokens: 10, outputTokens: 5}});
const limits = [{percent: 0.2, resetsAt: "2030-01-01T00:00:00Z"}, {percent: 0.8, resetsAt: "2030-01-01T00:00:00Z"}];
const rec = (percent, resetsAt) => [{id: "codex", name: "Codex", ready: true, limits: [{label: "Monthly", percent: percent, resetsAt: resetsAt}]}];
const first = A.limitTransitions(rec(0.5, "2030-01-01"), {});
const reset = A.limitTransitions(rec(0.4, "2030-02-01"), first.state);
const exhausted = A.limitTransitions(rec(0.95, "2030-02-01"), reset.state);
const steady = A.limitTransitions(rec(0.95, "2030-02-01"), exhausted.state);
const nowMs = 1700000000000;
const future = new Date(nowMs + 3.5 * 86400000).toISOString();
const paceEven = A.paceInfo({percent: 0.5, resetsAt: future, windowMinutes: 10080}, nowMs);
const paceBehind = A.paceInfo({percent: 0.7, resetsAt: future, windowMinutes: 10080}, nowMs);
// A nearly-drained 5h window that is about to reset must not outrank a weekly
// window that is off-pace and will lock the account out far longer.
const fiveHourWin = {label: "5h", percent: 0.88, windowMinutes: 300, resetsAt: new Date(nowMs + 5 * 60000).toISOString()};
const weeklyWin = {label: "weekly", percent: 0.70, windowMinutes: 10080, resetsAt: new Date(nowMs + 4 * 86400000).toISOString()};
const tieShort = {label: "short", percent: 0.5, windowMinutes: 300};
const tieLong = {label: "long", percent: 0.5, windowMinutes: 10080};
const noDuration = {label: "nodur", percent: 0.9};
const durated = {label: "durated", percent: 0.2, windowMinutes: 300, resetsAt: new Date(nowMs + 60000).toISOString()};
const chartBars = A.dayChartBars([{date: "d0", tokens: 0}, {date: "d1", tokens: 10}], 100);
const countdownIso = "2040-01-01T00:00:00+00:00";
const ok =
    A.billingText({subscription: {renew: "2030-01-01", daysLeft: 5}}) === "Renews 2030-01-01 · in 5 days" &&
    A.billingText({}) === "" &&
    A.renewalReminders([{id: "codex", name: "Codex", ready: true,
        subscription: {renew: "2030-01-01", daysLeft: 2, reminderDays: 3}}], {}, "2026-09-19").notifications.length === 1 &&
    A.renewalReminders([{id: "codex", name: "Codex", ready: true,
        subscription: {renew: "2030-01-01", daysLeft: 2, reminderDays: 3}}],
        {"renew|codex": "2026-09-19"}, "2026-09-19").notifications.length === 0 &&
    A.severityFor(50) === "ok" && A.severityFor(80) === "warn" && A.severityFor(95) === "critical" &&
    A.severityForLimit({percent: 0.95}) === "critical" &&
    paceEven && Math.abs(paceEven.elapsed - 0.5) < 0.01 && paceEven.behind === false &&
    paceEven.onPace === true && paceEven.state === "on-pace" &&
    paceBehind && paceBehind.behind === true &&
    A.bindingLimit({limits: [fiveHourWin, weeklyWin]}, nowMs).label === "weekly" &&
    A.bindingLimit({limits: [tieShort, tieLong]}, nowMs).label === "long" &&
    A.bindingLimit({limits: [noDuration, durated]}, nowMs).label === "nodur" &&
    A.overallSeverity([{id: "a", ready: true, limits: [durated]}], nowMs) === "ok" &&
    A.overallSeverity([{id: "a", ready: true, limits: [{percent: 0.8, windowMinutes: 300, resetsAt: new Date(nowMs + 60000).toISOString()}]}], nowMs) === "warn" &&
    A.overallSeverity([{id: "a", ready: true, limits: [{percent: 0.95, windowMinutes: 300, resetsAt: new Date(nowMs + 60000).toISOString()}]}], nowMs) === "critical" &&
    A.overallSeverity([], nowMs) === "unknown" &&
    A.overallSeverity([{id: "a", ready: true, limits: []}], nowMs) === "unknown" &&
    chartBars[0].barHeight === 0 && chartBars[0].hasUsage === false && chartBars[1].barHeight === 100 &&
    A.parseRecords("{\"agents\":[{\"id\":\"good\",\"ready\":true}, BAD_RECORD, {\"id\":\"good2\"}]}").length === 2 &&
    A.resetMsFor({resetsAt: countdownIso}, nowMs) > 0 &&
    A.formatDuration(A.resetMsFor({resetsAt: countdownIso}, nowMs)) !== "now" &&
    A.recordAgeMs({updatedAt: new Date(nowMs - 5 * 60000).toISOString()}, nowMs) === 5 * 60000 &&
    A.isRecordStale({updatedAt: new Date(nowMs - 10 * 60000).toISOString()}, nowMs, 5 * 60000) === true &&
    A.isRecordStale({updatedAt: new Date(nowMs).toISOString()}, nowMs, 5 * 60000) === false &&
    A.freshnessText({updatedAt: new Date(nowMs - 5 * 60000).toISOString()}, nowMs) === "5m ago" &&
    first.notifications.length === 0 &&
    reset.notifications.length === 1 && reset.notifications[0].title.indexOf("reset") >= 0 &&
    exhausted.notifications.length === 1 && exhausted.notifications[0].title.indexOf("critical") >= 0 &&
    steady.notifications.length === 0 &&
    A.bindingLimit({limits: limits}).percent === 0.8 &&
    A.formatDuration(90 * 60000) === "1h 30m" &&
    A.formatDuration(-1) === "now" &&
    A.heroMeta({tierLabel: "plus"}) === "Plus" &&
    A.heroMeta({usageStatusText: "Codex limits unavailable"}) === "Codex limits unavailable" &&
    A.modelRows({modelUsage: {b: {inputTokens: 1}, a: {outputTokens: 5}}})[0].name === "a" &&
    A.dayLabel("2026-09-19", true) === "Today" &&
    A.weekPeak({recentDays: [{messageCount: 3}, {messageCount: 9}]}) === 9 &&
    A.clamp(5, 0, 1) === 1 &&
    A.resetMsFor({resetsAt: ""}, 0) === -1 &&
    A.todayDate(Date.UTC(2026, 8, 19, 12)) === "2026-09-19" &&
    A.parseRecords("not json").length === 0 &&
    A.parseRecords("{}").length === 0 &&
    records.length === 2 &&
    A.readyAgents(records).length === 1 &&
    A.detectedAgents(records).length === 2 &&
    A.detectedAgents([{detected: true}, {ready: true}, {detected: false, ready: false}]).length === 2 &&
    A.todayTotal(records) === 1500 &&
    A.tierLabel(records[0]) === "Max" &&
    A.formatTokens(0) === "0" &&
    A.formatTokens(999) === "999" &&
    A.formatTokens(1500) === "1.5k" &&
    A.formatTokens(2000000) === "2.0M" &&
    A.formatTokens(3000000000) === "3.0B" &&
    models.length === 2 && models[0].name === "big" && models[0].total === 15 &&
    bars[0].fraction === 0 && bars[1].fraction === 1;
process.exit(ok ? 0 : 1);
' "$projection_test" >/dev/null; then
        pass "[unit] agents record projection parses, filters, sorts, and formats usage"
    else
        fail "[unit] agents record projection contract failed"
    fi
    rm -f -- "$projection_test"

    # Redesigned UI contract: billable/cache split, per-day `tokens`, the
    # pace-aware binding limit, unknown/stale/error/rate-limited states, the
    # icon-only bar encoding and the provider-aware labels.
    ui_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_dir/AgentUsage.js" >"$ui_test"
    cat >>"$ui_test" <<'AGENT_UI_EXPORTS'
module.exports = { dayTokens, todayUsage, todayModels, modelRowsFrom, planLabel, freshnessPill, formatResetAbsolute, paceLabel, providerWorstLabel, recordHasError, providerState, barState, billingSummary, subscriptionRows, bindingLimit, severityForLimit, overallSeverity, paceInfo, normalizePercentMode, displayPercent, displayMarker, newestRecord, overallFreshnessPill };
AGENT_UI_EXPORTS
    if node -e '
const A = require(process.argv[1]);
const assert = (c, m) => { if (!c) throw new Error(m) };
const now = 1700000000000;
const soon = new Date(now + 4 * 86400000).toISOString();
const warnLimit = { label: "Weekly", percent: 0.82, windowMinutes: 10080, resetsAt: soon };
const okLimit = { label: "Weekly", percent: 0.10, windowMinutes: 10080, resetsAt: soon };
const base = { id: "claude", name: "Claude Code", ready: true, detected: true,
    updatedAt: new Date(now - 5 * 60000).toISOString(), tierLabel: "Max", todayLabel: "turns",
    todayBillableTokens: 1200, todayCacheTokens: 300, todayPrompts: 4, todaySessions: 2,
    limits: [warnLimit], recentDays: [{ date: "d0", tokens: 0 }, { date: "d1", tokens: 10 }],
    todayTokensByModel: { a: { billableTokens: 5, cacheTokens: 1, totalTokens: 6 } },
    modelUsage: { b: { inputTokens: 1, outputTokens: 2, cacheReadInputTokens: 3, cacheCreationInputTokens: 4 } },
    subscription: { plan: "Max", cost: "20", currency: "USD", cycle: "monthly", renew: "2030-01-01", daysLeft: 5 } };
const okRec = Object.assign({}, base, { limits: [okLimit] });
const ok =
    A.dayTokens({ tokens: 0, messageCount: 9 }) === 0 &&
    A.dayTokens({ messageCount: 9 }) === 9 &&
    A.todayUsage(base).billable === 1200 && A.todayUsage(base).cache === 300 &&
    A.todayUsage(base).count === 4 && A.todayUsage(base).noun === "turns" &&
    A.todayUsage(base).sessions === 2 &&
    A.todayModels(base, 4)[0].name === "a" && A.todayModels(base, 4)[0].total === 6 &&
    A.modelRowsFrom({ b: { inputTokens: 1, outputTokens: 2, cacheReadInputTokens: 3, cacheCreationInputTokens: 4 } }, 4)[0].total === 10 &&
    A.planLabel(base) === "Max" &&
    A.planLabel({ tierLabel: "", usageStatusText: "Local usage only" }) === "Local usage only" &&
    A.billingSummary(base) === "USD 20.00 · monthly" &&
    A.subscriptionRows(base).length === 3 && A.subscriptionRows({}).length === 0 &&
    A.formatResetAbsolute(soon).endsWith("UTC") && A.formatResetAbsolute("nonsense") === "" &&
    A.paceLabel({ onPace: true }) === "on pace" &&
    A.paceLabel({ behind: true }) === "behind pace" &&
    A.providerWorstLabel(base, now) === "Weekly 18%" &&
    A.providerWorstLabel(base, now, "used") === "Weekly 82%" &&
    A.recordHasError({ authHelpText: "codex not found" }) === true &&
    A.recordHasError({ usageStatusText: "Local usage only" }) === false &&
    A.recordHasError({ usageStatusText: "Account configured · no usage yet" }) === false &&
    A.freshnessPill(base, now, 1800000).text === "5m ago" &&
    A.freshnessPill(base, now, 60000).stale === true &&
    // Bar encoding: tint + dot + opacity per state.
    A.barState([okRec], now, { staleMs: 1800000 }).key === "ready" &&
    A.barState([okRec], now, { staleMs: 1800000 }).tint === "barForeground" &&
    A.barState([okRec], now, { staleMs: 1800000 }).dot === false &&
    A.barState([base], now, { staleMs: 1800000 }).key === "warn" &&
    A.barState([base], now, { staleMs: 1800000 }).tint === "warning" &&
    A.barState([base], now, { staleMs: 1800000 }).dot === true &&
    A.barState([base], now, { staleMs: 60000 }).key === "stale" &&
    A.barState([base], now, { staleMs: 60000 }).opacity === 0.6 &&
    A.barState([base], now, { staleMs: 60000 }).dot === false &&
    A.barState([Object.assign({}, base, { retryAdvised: true })], now, {}).key === "rate-limited" &&
    A.barState([Object.assign({}, base, { authHelpText: "x", usageStatusText: "Codex unavailable" })], now, {}).key === "error" &&
    A.barState([Object.assign({}, base, { authHelpText: "x", usageStatusText: "Codex unavailable" })], now, {}).dot === true &&
    A.barState([{ id: "x", ready: true, limits: [] }], now, {}).key === "unknown" &&
    A.barState([{ id: "x", ready: true, limits: [] }], now, {}).tint === "textMuted" &&
    A.barState([{ id: "x", ready: true, limits: [] }], now, {}).opacity === 0.5 &&
    A.barState([], now, { loading: true }).key === "loading" &&
    A.barState([], now, {}).key === "empty" &&
    A.barState([], now, { backendError: "usage backend failed" }).key === "error" &&
    // Provider state: error and rate-limit outrank stale so an error is never
    // hidden behind old data; stale dims a live number rather than showing it.
    A.providerState(okRec, now, { staleMs: 1800000 }).key === "ready" &&
    A.providerState(base, now, { staleMs: 1800000 }).key === "warn" &&
    A.providerState(base, now, { staleMs: 60000 }).key === "stale" &&
    A.providerState(base, now, { staleMs: 60000 }).opacity === 0.6 &&
    A.providerState(Object.assign({}, base, { retryAdvised: true }), now, { staleMs: 60000 }).key === "rate-limited" &&
    A.providerState(Object.assign({}, base, { authHelpText: "x", usageStatusText: "Codex unavailable" }), now, { staleMs: 60000 }).key === "error" &&
    A.providerState({ id: "x", ready: true, limits: [] }, now, {}).key === "unknown" &&
    A.providerState({ id: "x", ready: true, limits: [] }, now, {}).message === "No live limit reported" &&
    A.providerState(null, now, { loading: true }).key === "loading" &&
    A.providerState(null, now, {}).key === "empty";
process.exit(ok ? 0 : 1);
' "$ui_test" >/dev/null; then
        pass "[unit] agents UI projection covers billable/cache split, states, pace and provider labels"
    else
        fail "[unit] agents UI projection contract failed"
    fi
    rm -f -- "$ui_test"

    # Consolidated dashboard projection, the realistic multi-account fixture,
    # worst-in-cell duplicate buckets, no-limits `—` semantics, balance
    # presence, id-based tab reconciliation and fail-safe diagnostics.
    dashboard_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_dir/AgentUsage.js" >"$dashboard_test"
    cat >>"$dashboard_test" <<'AGENT_DASHBOARD_EXPORTS'
module.exports = { classifyWindow, windowDescription, windowColumnLabel, canonicalWindowOrder, supportedWindowClasses, windowIsOffered, matrixRows, matrixRow, matrixCell, matrixCellMarker, matrixCellTooltip, matrixCellAccessibility, bindingLimit, accountOrder, reconcileSelection, limitDetailRows, hasBalance, anyBalance, balanceText, balanceHeader, severityGlyph, headlineFor, paceWord, worstLimitFor, todayUsage, normalizePercentMode, displayPercent, displayMarker, newestRecord, overallFreshnessPill, diagnoseRecord, diagnoseRecords, collectorDiagnostic, diagnosticLine, diagnosticKey };
AGENT_DASHBOARD_EXPORTS
    if node -e '
const fs = require("fs");
const A = require(process.argv[1]);
const records = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).agents;
const now = Date.parse("2026-09-19T12:00:00Z");
const assert = (c, m) => { if (!c) throw new Error(m); };
// Numeric classification from windowMinutes only.
assert(A.classifyWindow({windowMinutes: 300}) === "five_hour");
assert(A.classifyWindow({windowMinutes: 10080}) === "week");
assert(A.classifyWindow({windowMinutes: 43200}) === "month");
assert(A.classifyWindow({windowMinutes: 1440}) === "other");
assert(A.classifyWindow({windowMinutes: 0}) === "unknown");
assert(A.classifyWindow({windowMinutes: NaN}) === "unknown");
assert(A.classifyWindow({}) === "unknown");
assert(A.classifyWindow(null) === "unknown");
assert(A.windowDescription("month") === "30-day rolling window");
assert(A.windowColumnLabel("five_hour") === "5H");
// Fixed deterministic order: name ascending, id tiebreak.
const rows = A.matrixRows(records, now);
assert(rows.length === 7, "7 rows");
assert(rows.map(r => r.name).join(",") === "Augment,Claude Code,Cline,Codex,Fireworks,OpenCode,OpenCode Blocked", "order");
assert(A.accountOrder(records).map(r => r.id).join(",") === "augment,claude,cline,codex,fireworks,opencode,opencode-blocked", "ids");
assert(A.accountOrder([{id: "b", name: "Same", ready: true}, {id: "a", name: "Same", ready: true}]).map(r => r.id).join(",") === "a,b", "id tiebreak");
const byId = {};
rows.forEach(r => { byId[r.id] = r; });
// Default presentation is remaining (100% = fully available); the fixture
// used fractions invert only at the display boundary.
assert(byId.codex.windows.five_hour.percentText === "58%");
assert(byId.codex.windows.week.percentText === "45%", "worst-in-cell duplicate bucket");
assert(byId.codex.windows.month === null, "no month bucket");
assert(byId.codex.todayTokens === "5.4k");
assert(byId.codex.noLiveLimits === false);
assert(byId.opencode.windows.five_hour.percentText === "10%");
assert(byId.opencode.windows.week.percentText === "65%");
assert(byId.opencode.windows.month.percentText === "82%");
// The user case: a fresh 5h window alongside an exhausted weekly
// window still blocks the account, and the eye is sent to the weekly window.
assert(byId["opencode-blocked"].headlineText === "Blocked");
assert(byId["opencode-blocked"].headlineSeverity === "critical");
assert(byId["opencode-blocked"].bindingWindowClass === "week");
assert(byId["opencode-blocked"].windows.five_hour.muted === true, "non-binding fresh window is muted");
assert(byId["opencode-blocked"].windows.week.isBinding === true, "exhausted weekly window is the binding cell");
assert(byId["opencode-blocked"].windows.week.percentText === "0%");
assert(byId.augment.headlineText === "Blocked" && byId.augment.headlineSeverity === "critical");
assert(byId.claude.headlineText === "no live limits");
// BOTH MODES: the SAME limit renders 90% used and 10% remaining, and severity
// stays critical (used-based) in both. This proves the number and the alarm
// cannot disagree.
const bothModeLimit = {label: "Both", percent: 0.9, windowMinutes: 300,
  resetsAt: new Date(now + 60000).toISOString()};
const usedCell = A.matrixCell(bothModeLimit, "five_hour", now, "used");
const remainingCell = A.matrixCell(bothModeLimit, "five_hour", now, "remaining");
assert(usedCell.percentText === "90%" && Math.abs(usedCell.percent - 0.9) < 1e-9, "used mode fill");
assert(remainingCell.percentText === "10%" && Math.abs(remainingCell.percent - 0.1) < 1e-9, "remaining mode fill");
assert(usedCell.severity === "critical" && remainingCell.severity === "critical", "severity stays used-based");
assert(usedCell.usedPercent === 0.9 && remainingCell.usedPercent === 0.9, "usedPercent retained for risk");
assert(A.normalizePercentMode("used") === "used" && A.normalizePercentMode("USED") === "used");
[undefined, null, "", 0, 1, "remaining", "weird", {}].forEach(function (value) {
    assert(A.normalizePercentMode(value) === "remaining", "fail-closed mode for " + String(value));
});
assert(A.displayMarker(0.25, "used") === 0.25);
assert(Math.abs(A.displayMarker(0.25, "remaining") - 0.75) < 1e-9);
assert(A.displayMarker(-1, "remaining") === -1, "marker sentinel survives");
assert(A.displayPercent(-1, "remaining") === -1, "percent sentinel survives");
// Header freshness spans every account; it never says "Freshness unknown".
assert(A.newestRecord(records).id === "opencode-blocked");
assert(A.newestRecord([{id: "x"}, {id: "y"}]) === null);
assert(A.overallFreshnessPill([], now, 1800000).text === "never updated");
assert(A.overallFreshnessPill(records, now, 1800000).text === "updated 1m ago");
assert(A.overallFreshnessPill(records, now, 30000).text.indexOf("stale · updated ") === 0);
assert(A.overallFreshnessPill([{updatedAt: new Date(now + 60000).toISOString()}], now, 1800000).text === "updated just now", "future clamp");
assert(byId.claude.windows.five_hour === null && byId.claude.windows.week === null && byId.claude.windows.month === null);
assert(byId.claude.noLiveLimits === true, "no live limits semantics");
assert(byId.claude.todayTokens === "1.2k", "no-limits account still shows today tokens");
assert(byId.fireworks.balance === "USD 12.50");
assert(byId.fireworks.hasBalance === true);
assert(byId.claude.balance === "");
assert(A.anyBalance(records) === true, "balance column present");
assert(A.anyBalance([{id: "x", name: "X"}]) === false, "balance column absent");
assert(A.hasBalance({id: "x", subscription: {cost: "20"}}) === false, "subscription.cost is not balance");
assert(A.balanceText({subscription: {cost: "20"}}) === "");
assert(A.balanceHeader([{balance: {spent: 3}}]) === "SPEND");
assert(A.balanceHeader([{balance: {remaining: 3}}]) === "BALANCE");
// Partially-available record: every field it has renders; nothing suppressed.
const partial = {id: "partial", name: "Partial", ready: true, detected: true,
  todayBillableTokens: 42, limits: [{label: "5h", percent: 0.5, windowMinutes: 300}]};
const pr = A.matrixRow(partial, now);
assert(pr.windows.five_hour.percentText === "50%", "partial 5h percent");
assert(pr.windows.five_hour.countdown === "", "percent without resetsAt keeps the percent, drops only the countdown");
assert(pr.windows.five_hour.elapsed === -1, "no pace marker without resetsAt");
assert(pr.windows.week === null && pr.windows.month === null);
assert(pr.todayTokens === "42", "partial today tokens render");
assert(pr.noLiveLimits === false);
const pdetail = A.limitDetailRows(partial, now);
assert(pdetail.length === 1 && pdetail[0].percentText === "50%" && pdetail[0].countdown === "");
// Unusual / missing durations are never dropped from the detail list.
const unusual = A.limitDetailRows({id: "u", limits: [
  {label: "Weird", percent: 0.3, windowMinutes: 999, resetsAt: "2026-09-19T13:30:00Z"},
  {label: "Zero", percent: 0.4, windowMinutes: 0, resetsAt: "2026-09-19T13:00:00Z"},
  {label: "Missing", percent: 0.6}
]}, now);
assert(unusual.length === 3, "all unusual/unknown windows kept");
assert(unusual[0].isOther === true);
assert(unusual[1].isUnknown === true && unusual[1].title === "duration not reported");
assert(unusual[2].isUnknown === true && unusual[2].title === "duration not reported");
// A total-only record shows its available tokens rather than a fabricated zero.
const totalOnly = {id: "t", name: "TotalOnly", ready: true, todayTotalTokens: 777, limits: []};
assert(A.matrixRow(totalOnly, now).todayTokens === "777", "total-only record shows available tokens");
assert(A.todayUsage(totalOnly).billable === 777, "total-only fallback");
assert(A.todayUsage(totalOnly).cache === 0);
// Tab selection reconciliation is by id, then a clamped index.
assert(A.reconcileSelection("claude", 9, rows) === 1, "id wins over stale index");
assert(A.reconcileSelection("gone", 4, rows) === 4, "clamped fallback index");
assert(A.reconcileSelection("gone", 99, rows) === 6, "clamped to last");
assert(A.reconcileSelection("", 0, rows) === 0);
assert(A.reconcileSelection("x", 0, []) === -1);
// Non-colour severity glyphs.
assert(A.severityGlyph("warn") === "\u25b2");
assert(A.severityGlyph("critical") === "\u25cf");
assert(A.severityGlyph("ok") === "");
// Pace word only when both percent and elapsed are finite.
const paceFuture = new Date(now + 3.5 * 86400000).toISOString();
assert(A.paceWord({percent: 0.5, windowMinutes: 10080, resetsAt: paceFuture}, now) === "on pace");
assert(A.paceWord({percent: 0.7, windowMinutes: 10080, resetsAt: paceFuture}, now) === "behind");
assert(A.paceWord({percent: 0.2, windowMinutes: 10080, resetsAt: paceFuture}, now) === "ahead");
assert(A.paceWord({percent: 0.5}, now) === "", "no pace word without elapsed");
// Diagnostics name every unmet condition and the provider.
const codexDiags = A.diagnoseRecord(records.find(r => r.id === "codex"));
const codexConds = codexDiags.map(d => d.condition);
["missing_window_minutes", "zero_window_minutes", "missing_resets_at", "absent_balance"].forEach(c => assert(codexConds.includes(c), "codex diag " + c));
assert(codexDiags.every(d => d.provider === "codex"));
assert(A.diagnoseRecord(records.find(r => r.id === "claude")).some(d => d.condition === "missing_limits"));
const unparse = A.diagnoseRecord({id: "x", name: "X", limits: [{label: "weird", windowMinutes: "abc", percent: 0.5, resetsAt: "nope"}]});
const unparseConds = unparse.map(d => d.condition);
assert(unparseConds.includes("unparseable_window_minutes"));
assert(unparseConds.includes("unparseable_resets_at"));
assert(A.collectorDiagnostic("usage backend failed")[0].condition === "collector_failed");
assert(A.collectorDiagnostic("").length === 0);
assert(A.diagnosticLine({provider: "codex", condition: "zero_window_minutes", detail: "Rate window"}) === "[AGENTS] unmet_condition provider=codex condition=zero_window_minutes detail=Rate window");
assert(A.diagnoseRecord({id: "clean", name: "Clean", balance: {remaining: 1}, limits: [{label: "5h", percent: 0.1, windowMinutes: 300, resetsAt: new Date(now + 60000).toISOString()}]}).length === 0);
// Not offered versus not reported. A declared-but-unreported canonical window
// is a REAL unmet condition (and still emits its diagnostic); a window the
// provider does not offer is a non-problem and must never be logged.
assert(A.windowIsOffered({supportedWindowMinutes: [300, 10080]}, "month") === false);
assert(A.windowIsOffered({supportedWindowMinutes: [300, 10080]}, "week") === true);
assert(A.windowIsOffered({}, "month") === null, "no declaration stays unknown");
assert(A.supportedWindowClasses({supportedWindowMinutes: [300, 10080, 99999]}).join(",") === "five_hour,week");
assert(A.supportedWindowClasses({}) === null);
const missingRec = {id: "claude", name: "Claude Code", supportedWindowMinutes: [300, 10080],
  limits: [{label: "Weekly (7-day)", percent: 0.67, windowMinutes: 10080, resetsAt: new Date(now + 60000).toISOString()}]};
const missingConds = A.diagnoseRecord(missingRec).map(d => d.condition);
assert(missingConds.includes("missing_window"), "supported but unreported still logs");
assert(A.diagnoseRecord(missingRec).some(d => d.condition === "missing_window" && d.detail === "5h"));
assert(!missingConds.includes("undeclared_window"));
const notOfferedRec = {id: "claude", name: "Claude Code", supportedWindowMinutes: [10080],
  limits: [{label: "Weekly (7-day)", percent: 0.67, windowMinutes: 10080, resetsAt: new Date(now + 60000).toISOString()}]};
assert(!A.diagnoseRecord(notOfferedRec).map(d => d.condition).includes("missing_window"), "a not-offered window never logs");
const undeclaredRec = {id: "x", name: "X", supportedWindowMinutes: [300],
  limits: [{label: "Monthly (30-day)", percent: 0.2, windowMinutes: 43200, resetsAt: new Date(now + 60000).toISOString()}]};
assert(A.diagnoseRecord(undeclaredRec).some(d => d.condition === "undeclared_window"), "an undeclared reported window is observable");
// Legacy records without the capability field keep the old behaviour: no
// per-column diagnostics, only the whole-array `missing_limits`.
assert(!A.diagnoseRecord({id: "legacy", limits: []}).map(d => d.condition).includes("missing_window"));
// A plan change between runs recomputes the columns from the current support set.
const twoWindows = [
  {label: "5h window", percent: 0.1, windowMinutes: 300, resetsAt: new Date(now + 60000).toISOString()},
  {label: "Weekly (7-day)", percent: 0.2, windowMinutes: 10080, resetsAt: new Date(now + 60000).toISOString()}];
assert(A.diagnoseRecord({id: "p", supportedWindowMinutes: [300, 10080, 43200], limits: twoWindows})
  .some(d => d.condition === "missing_window" && d.detail === "30-day"), "month added but not reported");
assert(!A.diagnoseRecord({id: "p", supportedWindowMinutes: [300, 10080], limits: twoWindows})
  .map(d => d.condition).includes("missing_window"), "month dropped is not offered");
// Exact markers, tooltips and accessibility text for all three states.
assert(A.matrixCellMarker({percentText: "42%"}, false) === "42%");
assert(A.matrixCellMarker(null, false) === "—", "not reported marker");
assert(A.matrixCellMarker(null, true) === "–", "not offered marker is distinct");
assert(A.matrixCellTooltip(null, "month", true, "remaining") === "30-day · not offered by this provider");
assert(A.matrixCellTooltip(null, "week", false, "remaining") === "Weekly · not reported by this provider");
const reportedTooltip = A.matrixCellTooltip({label: "Weekly (7-day)", percentText: "33%", absoluteReset: "2026-09-30 15:13 UTC", isBinding: false}, "week", false, "remaining");
assert(reportedTooltip.indexOf("remaining") >= 0 && reportedTooltip.indexOf("Resets 2026-09-30 15:13 UTC") >= 0);
assert(A.matrixCellAccessibility(null, "month", true, "remaining") === "MONTH window not offered by this provider");
assert(A.matrixCellAccessibility(null, "week", false, "remaining") === "WEEK window not reported by this provider");
assert(A.matrixCellAccessibility({label: "5h window", percentText: "75%", isBinding: true}, "five_hour", false, "remaining")
  === "5H 5h window: 75% remaining, binding window for this account");
// matrixRow exposes notOffered per column and never fabricates a cell.
const offRow = A.matrixRow({id: "claude", name: "Claude Code", ready: true, limits: [],
  supportedWindowMinutes: [300, 10080]}, now);
assert(offRow.windows.five_hour === null && offRow.windows.week === null && offRow.windows.month === null);
assert(offRow.notOffered.five_hour === false && offRow.notOffered.week === false && offRow.notOffered.month === true);
const reportedRow = A.matrixRow({id: "x", name: "X", ready: true, supportedWindowMinutes: [300, 10080],
  limits: [{label: "5h window", percent: 0.1, windowMinutes: 300, resetsAt: new Date(now + 60000).toISOString()}]}, now);
assert(reportedRow.notOffered.month === true && reportedRow.notOffered.five_hour === false);
// USED direction: 25/100 and 67/100 stay USED; remaining mode inverts for
// display only, and severity stays used-based under both modes.
assert(A.displayPercent(0.25, "remaining") === 0.75);
assert(A.displayPercent(0.25, "used") === 0.25);
const claudeUsedCell = A.matrixCell({label: "5h window", percent: 0.25, windowMinutes: 300, resetsAt: new Date(now + 60000).toISOString()}, "five_hour", now, "remaining");
assert(claudeUsedCell.percentText === "75%" && claudeUsedCell.severity === "ok" && claudeUsedCell.usedPercent === 0.25);
const criticalCell = A.matrixCell({label: "Weekly (7-day)", percent: 0.95, windowMinutes: 10080, resetsAt: new Date(now + 7100000).toISOString()}, "week", now, "remaining");
assert(criticalCell.severity === "critical" && criticalCell.percentText === "5%", "severity stays used-based under remaining mode");
process.exit(0);
' "$dashboard_test" "$ROOT/tests/fixtures/agents-dashboard/records.json" >/dev/null; then
        pass "[unit] agents dashboard projection orders accounts, classifies windows, keeps available data and names every unmet condition"
    else
        fail "[unit] agents dashboard projection contract failed"
    fi
    rm -f -- "$dashboard_test"
else
    skip "[unit] agents record projection (node unavailable)"
fi

# ---------------------------------------------------------------------------
# Backend + collector (isolated sandbox)
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null; then
    skip "[isolated] usage collector record contract (python3 unavailable)"
    return 0
fi

sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox" || true' RETURN
today="$(date +%F)"
yesterday="$(date -d 'yesterday' +%F)"
mkdir -p -- "$sandbox/home/.claude/projects/proj" "$sandbox/state" "$sandbox/config"
cat >"$sandbox/home/.claude/projects/proj/session.jsonl" <<TRANSCRIPT
{"type":"assistant","timestamp":"${today}T10:00:00","sessionId":"s1","message":{"id":"m1","role":"assistant","model":"claude-opus-4","usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":50,"cache_creation_input_tokens":10}}}
{"type":"assistant","timestamp":"${yesterday}T09:00:00","sessionId":"s2","message":{"id":"m2","role":"assistant","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
{"type":"user","message":{"role":"user"}}
TRANSCRIPT

collector_out="$(HOME="$sandbox/home" PI_HOME="$sandbox/no-pi" CLAUDE_CONFIG_DIR="$sandbox/home/.claude" "$collector"  || true)"
if printf '%s' "$collector_out" | jq -e '
        .id == "claude" and
        .ready == true and
        .hasLocalStats == true and
        .todayLabel == "turns" and
        .retryAdvised == false and
        .totalPrompts == 2 and
        .totalSessions == 2 and
        .todayPrompts == 1 and
        .todayTotalTokens == 360 and
        .todayBillableTokens == 300 and
        .todayCacheTokens == 60 and
        (.todayBillableTokens + .todayCacheTokens == .todayTotalTokens) and
        .todayTokensByModel["claude-opus-4"].totalTokens == 360 and
        .todayTokensByModel["claude-opus-4"].billableTokens == 300 and
        .todayTokensByModel["claude-opus-4"].cacheTokens == 60 and
        ([.recentDays[] | (.billableTokens + .cacheTokens == .tokens)] | all) and
        ([.recentDays[] | .messageCount == .tokens] | all) and
        ([.modelUsage[] | (.billableTokens + .cacheTokens == .totalTokens)] | all) and
        (.recentDays | length == 7) and
        .modelUsage["claude-sonnet-4"].outputTokens == 20 and
        .limits == []' >/dev/null; then
    pass "[isolated] collector derives the record contract from local Claude transcripts"
else
    fail "[isolated] collector record contract diverged: $collector_out"
fi

empty_out="$(XDG_STATE_HOME="$sandbox/state" "$backend" usage  || true)"
if printf '%s' "$empty_out" | jq -e '.agents == []' >/dev/null; then
    pass "[isolated] usage backend reports an empty agent list before any collection"
else
    fail "[isolated] empty usage listing is not valid JSON"
fi

if HOME="$sandbox/home" XDG_STATE_HOME="$sandbox/state" XDG_CONFIG_HOME="$sandbox/config" \
       "$backend" usage-update claude >/dev/null &&
   XDG_STATE_HOME="$sandbox/state" "$backend" usage | jq -e '
        .agents | length == 1 and
        .[0].id == "claude" and
        .[0].totalPrompts == 2' >/dev/null; then
    pass "[isolated] usage-update collects a record that usage then serves"
else
    fail "[isolated] usage-update did not produce a servable record"
fi

record_file="$sandbox/state/aurelia/agents/usage/claude.json"
record_mode="$(stat -c '%a' "$record_file"  || true)"
if [[ -f "$record_file" && "$record_mode" == "600" ]]; then
    pass "[isolated] collected usage records are stored private (0600) and atomically"
else
    fail "[isolated] collected usage record permissions are unsafe (mode=$record_mode)"
fi

# Codex and Cline fixtures prove the record contract is collector-agnostic.
# The RPC probe is disabled here (CODEX_BIN points nowhere) so the local-scan
# assertions stay deterministic; the probe itself is covered below.
mkdir -p -- "$sandbox/codex/sessions/${today//-//}" \
    "$sandbox/config/Code/User/globalStorage/saoudrizwan.claude-dev/tasks/t1" \
    "$sandbox/data"
cat >"$sandbox/codex/sessions/${today//-//}/rollout-x.jsonl" <<CODEX_ROLLOUT
{"timestamp":"${today}T10:00:00","type":"session_meta","payload":{"id":"s1"}}
{"timestamp":"${today}T10:00:01","type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5"}}
{"timestamp":"${today}T10:00:02","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":50,"cached_input_tokens":20,"cache_write_input_tokens":5,"total_tokens":175}}}}
CODEX_ROLLOUT
cat >"$sandbox/config/Code/User/globalStorage/saoudrizwan.claude-dev/tasks/t1/ui_messages.json" <<'CLINE_MESSAGES'
[{"ts":1789000000000,"type":"say","say":"api_req_started","text":"{\"tokensIn\":1000,\"tokensOut\":200,\"cacheReads\":50,\"cacheWrites\":10,\"cost\":0}"}]
CLINE_MESSAGES
printf '%s\n' '{"model_usage":[{"model_id":"cline-pass/glm-5.3-flash"}]}' \
    >"$sandbox/config/Code/User/globalStorage/saoudrizwan.claude-dev/tasks/t1/task_metadata.json"

HOME="$sandbox/home" CODEX_HOME="$sandbox/codex" CODEX_BIN="$sandbox/no-codex" \
    XDG_CONFIG_HOME="$sandbox/config" XDG_DATA_HOME="$sandbox/data" XDG_STATE_HOME="$sandbox/state" \
    "$backend" usage-update >/dev/null
if XDG_STATE_HOME="$sandbox/state" "$backend" usage | jq -e '
        ([.agents[] | select(.id == "codex")][0]) as $c |
        ([.agents[] | select(.id == "cline")][0]) as $l |
        $c.detected == true and $c.totalPrompts == 1 and $c.todayTotalTokens == 175 and
        $c.todayLabel == "turns" and
        $c.todayBillableTokens == 150 and $c.todayCacheTokens == 25 and
        ($c.todayBillableTokens + $c.todayCacheTokens == $c.todayTotalTokens) and
        $c.modelUsage["gpt-5"].inputTokens == 100 and
        $l.detected == true and $l.totalPrompts == 1 and
        $l.todayLabel == "requests" and
        $l.modelUsage["cline-pass/glm-5.3-flash"].outputTokens == 200 and
        $l.modelUsage["cline-pass/glm-5.3-flash"].billableTokens == 1200 and
        $l.modelUsage["cline-pass/glm-5.3-flash"].cacheTokens == 60 and
        ($l.modelUsage["cline-pass/glm-5.3-flash"].billableTokens +
            $l.modelUsage["cline-pass/glm-5.3-flash"].cacheTokens ==
            $l.modelUsage["cline-pass/glm-5.3-flash"].totalTokens)' >/dev/null; then
    pass "[isolated] Codex and Cline collectors populate the same record contract"
else
    fail "[isolated] Codex/Cline collector record contract diverged"
fi

# The live-limit probe must read the Codex app-server RPC (fresh), not the
# stale rate_limits snapshot buried in the last rollout file. A mock codex
# speaks the JSON-RPC handshake so the parse stays deterministic.
mkdir -p -- "$sandbox/bin"
cat >"$sandbox/bin/codex" <<'MOCK_CODEX'
#!/usr/bin/env bash
while IFS= read -r line; do
    id=$(printf '%s' "$line" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("id",""))
except Exception:
    pass')
    method=$(printf '%s' "$line" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("method",""))
except Exception:
    pass')
    case "$method" in
        account/read) printf '{"id":%s,"result":{"account":{"type":"chatgpt","planType":"plus"}}}\n' "$id" ;;
        account/rateLimits/read) printf '{"id":%s,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":11,"windowDurationMins":10080,"resetsAt":1800600000}}}}\n' "$id" ;;
        *) printf '{"id":%s,"result":{}}\n' "$id" ;;
    esac
done
MOCK_CODEX
chmod 0755 "$sandbox/bin/codex"
codex_rpc="$(HOME="$sandbox/home" CODEX_HOME="$sandbox/codex" CODEX_BIN="$sandbox/bin/codex" "$repo_root/bin/ai-usage-codex" || true)"
if printf '%s' "$codex_rpc" | jq -e '
        .tierLabel == "plus" and
        .todayLabel == "turns" and
        (.limits | length == 2) and
        .limits[0].percent == 0.42 and .limits[0].label == "5h window" and
        .limits[0].windowMinutes == 300 and
        .limits[1].percent == 0.11 and .limits[1].label == "Weekly (7-day)" and
        (.limits[0].resetsAt | length > 0)' >/dev/null; then
    pass "[isolated] Codex collector reads fresh limits from the app-server RPC"
else
    fail "[isolated] Codex RPC limit contract diverged: $codex_rpc"
fi

# pi drives opencode-go / clinepass / openai-codex through its own API clients,
# so their usage lives only in pi's session logs. Each provider collector must
# merge the matching pi turns.
mkdir -p -- "$sandbox/pi/agent/sessions/proj" "$sandbox/empty-data" "$sandbox/empty-config" "$sandbox/empty-cline"
cat >"$sandbox/pi/agent/sessions/proj/s.jsonl" <<'PI_SESSION'
{"type":"session","id":"s1","timestamp":"2026-09-19T09:00:00Z","cwd":"/tmp"}
{"type":"model_change","provider":"opencode-go","modelId":"deepseek-v4.1-flash"}
{"type":"message","id":"m1","timestamp":"2026-09-19T09:01:00Z","message":{"role":"assistant","provider":"opencode-go","model":"deepseek-v4.1-flash","usage":{"input":100,"output":20,"cacheRead":5,"cacheWrite":0,"reasoning":3,"totalTokens":128},"content":[]}}
{"type":"model_change","provider":"clinepass","modelId":"cline-pass/glm-5.3"}
{"type":"message","id":"m2","timestamp":"2026-09-19T09:02:00Z","message":{"role":"assistant","provider":"clinepass","model":"cline-pass/glm-5.3","usage":{"input":50,"output":10,"cacheRead":0,"cacheWrite":0,"reasoning":0,"totalTokens":60},"content":[]}}
{"type":"model_change","provider":"openai-codex","modelId":"gpt-5.5"}
{"type":"message","id":"m3","timestamp":"2026-09-19T09:03:00Z","message":{"role":"assistant","provider":"openai-codex","model":"gpt-5.5","usage":{"input":7,"output":3,"cacheRead":0,"cacheWrite":0,"reasoning":0,"totalTokens":10},"content":[]}}
{"type":"model_change","provider":"anthropic","modelId":"claude-opus-4-5"}
{"type":"message","id":"m4","timestamp":"2026-09-19T09:04:00Z","message":{"role":"assistant","provider":"anthropic","model":"claude-opus-4-5","usage":{"input":100,"output":20,"cacheRead":5,"cacheWrite":0,"reasoning":3,"totalTokens":128},"content":[]}}
PI_SESSION
pi_opencode="$(HOME="$sandbox/home" PI_HOME="$sandbox/pi" XDG_DATA_HOME="$sandbox/empty-data" "$repo_root/bin/ai-usage-opencode" || true)"
pi_cline="$(HOME="$sandbox/home" PI_HOME="$sandbox/pi" XDG_CONFIG_HOME="$sandbox/empty-config" CLINE_DIR="$sandbox/empty-cline" "$repo_root/bin/ai-usage-cline" || true)"
pi_codex="$(HOME="$sandbox/home" PI_HOME="$sandbox/pi" CODEX_HOME="$sandbox/no-codex-home" CODEX_BIN="$sandbox/no-codex" "$repo_root/bin/ai-usage-codex" || true)"
pi_claude="$(HOME="$sandbox/home" PI_HOME="$sandbox/pi" CLAUDE_CONFIG_DIR="$sandbox/no-claude-projects" "$collector" || true)"
if printf '%s' "$pi_opencode" | jq -e '.detected == true and .totalPrompts == 1 and .todayTotalTokens == 128 and .modelUsage["deepseek-v4.1-flash"].inputTokens == 100' >/dev/null &&
   printf '%s' "$pi_cline" | jq -e '.detected == true and .totalPrompts == 1 and .modelUsage["cline-pass/glm-5.3"].outputTokens == 10' >/dev/null &&
   printf '%s' "$pi_codex" | jq -e '.detected == true and .totalPrompts == 1 and .modelUsage["gpt-5.5"].inputTokens == 7' >/dev/null &&
   printf '%s' "$pi_claude" | jq -e '.detected == true and .ready == true and .totalPrompts == 1 and .todayTotalTokens == 128 and .modelUsage["claude-opus-4-5"].inputTokens == 100 and .usageStatusText == "Local usage only"' >/dev/null; then
    pass "[isolated] pi session usage is merged into the matching provider collectors"
else
    fail "[isolated] pi session merge diverged (opencode=$pi_opencode cline=$pi_cline codex=$pi_codex claude=$pi_claude)"
fi

# An `anthropic` account that pi is configured for but that has no recorded
# turn yet must stay visible (detected, not ready) with an explicit label,
# instead of being hidden by the usage-only visibility rule. The credential
# may appear in either auth.json or models-store.json; a different provider id
# must not be mistaken for Claude. Deliberately no `access` token is present so
# this subprocess cannot reach the network; the credential-bearing probe below
# monkeypatches urlopen instead.
mkdir -p -- "$sandbox/configured-pi/agent" "$sandbox/models-pi/agent" "$sandbox/other-pi/agent" \
    "$sandbox/no-claude-projects"
printf '%s\n' '{"anthropic":{"type":"oauth"}}' \
    >"$sandbox/configured-pi/agent/auth.json"
printf '%s\n' '{"anthropic":{"models":[{"id":"claude-opus-4"}]}}' \
    >"$sandbox/models-pi/agent/models-store.json"
printf '%s\n' '{"openai-codex":{"type":"oauth"}}' \
    >"$sandbox/other-pi/agent/auth.json"
configured_auth="$(HOME="$sandbox/home" PI_HOME="$sandbox/configured-pi" CLAUDE_CONFIG_DIR="$sandbox/no-claude-projects" "$collector" || true)"
configured_models="$(HOME="$sandbox/home" PI_HOME="$sandbox/models-pi" CLAUDE_CONFIG_DIR="$sandbox/no-claude-projects" "$collector" || true)"
other_only="$(HOME="$sandbox/home" PI_HOME="$sandbox/other-pi" CLAUDE_CONFIG_DIR="$sandbox/no-claude-projects" "$collector" || true)"
if printf '%s' "$configured_auth" | jq -e '
        .detected == true and .ready == false and
        .totalPrompts == 0 and .hasLocalStats == false and
        .usageStatusText == "Account configured · no usage yet"' >/dev/null &&
   printf '%s' "$configured_models" | jq -e '
        .detected == true and .ready == false and .totalPrompts == 0 and
        .usageStatusText == "Account configured · no usage yet"' >/dev/null &&
   printf '%s' "$other_only" | jq -e '
        .detected == false and .ready == false and .totalPrompts == 0' >/dev/null; then
    pass "[isolated] pi-configured anthropic accounts are visible before first use"
else
    fail "[isolated] pi-configured anthropic visibility diverged (auth=$configured_auth models=$configured_models other=$other_only)"
fi

# OpenCode upstream may send resetsAt as epoch seconds, epoch milliseconds or
# ISO-8601; the collector must normalise all three into a parseable timestamp
# from which the panel can derive a reset countdown, and must advise the single
# documented retry on a rate-limit/timeout response.
resets_out="$(python3 - "$repo_root/bin/ai-usage-opencode" <<'OPENCODE_RESETS'
import datetime as dt
import importlib.machinery
import importlib.util
import json
import sys

loader = importlib.machinery.SourceFileLoader("aoc", sys.argv[1])
spec = importlib.util.spec_from_loader("aoc", loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
module.opencode_go_key = lambda: "fake"


class Response:
    def __init__(self, payload):
        self.payload = payload

    def read(self):
        return json.dumps(self.payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


payload = {"usage": {
    "rolling": {"percent": 10, "resetsAt": 2208988800},
    "weekly": {"percent": 20, "resetsAt": 2208988800000},
    "monthly": {"percent": 30, "resetsAt": "2040-01-01T00:00:00Z"},
}}
module.urllib.request.urlopen = lambda *args, **kwargs: Response(payload)
now = dt.datetime.now(dt.timezone.utc)
countdowns = {}
for limit in module.fetch_go_limits()["limits"]:
    parsed = dt.datetime.fromisoformat(limit["resetsAt"])
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    countdowns[limit["label"]] = (parsed - now).total_seconds() > 0
module.urllib.request.urlopen = lambda *args, **kwargs: (_ for _ in ()).throw(
    Exception("HTTP Error 429: Too Many Requests")
)
rate_retry = module.fetch_go_limits()["retryAdvised"]
module.urllib.request.urlopen = lambda *args, **kwargs: (_ for _ in ()).throw(
    TimeoutError("timed out")
)
timeout_retry = module.fetch_go_limits()["retryAdvised"]
print(json.dumps({"countdowns": countdowns, "rateRetry": rate_retry, "timeoutRetry": timeout_retry}))
OPENCODE_RESETS
)"
if printf '%s' "$resets_out" | jq -e '
        (.countdowns | length == 3) and
        ([.countdowns[]] | all) and
        .rateRetry == true and .timeoutRetry == true' >/dev/null; then
    pass "[isolated] OpenCode normalises epoch-second, epoch-millisecond and ISO resetsAt into a countdown"
else
    fail "[isolated] OpenCode resetsAt normalisation diverged: $resets_out"
fi

# OpenCode buckets usage by the assistant message's own activity time. A
# session created today whose only turn ran six days ago must not report the
# tokens as today's usage.
mkdir -p -- "$sandbox/oc-data/opencode"
python3 - "$sandbox/oc-data/opencode/opencode.db" <<'OPENCODE_DB'
import datetime as dt
import json
import sqlite3
import sys

now = dt.datetime.now()
today_ms = int(now.timestamp() * 1000)
six_days_ms = int((now - dt.timedelta(days=6)).timestamp() * 1000)
connection = sqlite3.connect(sys.argv[1])
connection.execute(
    "create table session (id text primary key, model text, tokens_input integer, "
    "tokens_output integer, tokens_reasoning integer, tokens_cache_read integer, "
    "tokens_cache_write integer, time_created integer, time_updated integer)"
)
connection.execute(
    "create table message (id text primary key, session_id text, time_created integer, "
    "time_updated integer, data text)"
)
connection.execute(
    "insert into session values (?,?,?,?,?,?,?,?,?)",
    ("ses1", '{"id":"big-pickle"}', 10, 20, 5, 100, 0, today_ms, today_ms),
)
connection.execute(
    "insert into message values (?,?,?,?,?)",
    ("msg1", "ses1", six_days_ms, six_days_ms, json.dumps({
        "role": "assistant", "modelID": "big-pickle",
        "tokens": {"input": 10, "output": 20, "reasoning": 5, "cache": {"read": 100, "write": 0}},
        "time": {"created": six_days_ms, "completed": six_days_ms},
    })),
)
connection.commit()
connection.close()
OPENCODE_DB
opencode_out="$(HOME="$sandbox/home" PI_HOME="$sandbox/no-pi" XDG_DATA_HOME="$sandbox/oc-data" "$repo_root/bin/ai-usage-opencode" || true)"
if printf '%s' "$opencode_out" | jq -e '
        .todayLabel == "sessions" and
        .todayTotalTokens == 0 and
        .todayBillableTokens == 0 and
        .todayCacheTokens == 0 and
        .totalPrompts == 1 and
        ([.recentDays[].tokens] | add) == 135 and
        ([.recentDays[].billableTokens] | add) == 35 and
        ([.recentDays[].cacheTokens] | add) == 100' >/dev/null; then
    pass "[isolated] OpenCode buckets usage by the assistant turn activity time, not session creation"
else
    fail "[isolated] OpenCode activity-time bucketing diverged: $opencode_out"
fi

# ClinePass live windows. The body below was captured from a real authenticated
# call to `GET /api/v1/users/me/plan/usage-limits`; the collector must emit USED
# fractions (the panel inverts to remaining), normalise every resetsAt through
# the shared helper, and never fabricate a missing window. urlopen is
# monkey-patched, so this stays entirely offline.
mkdir -p -- "$sandbox/cline-cred/data/settings" "$sandbox/cline-pass/data/settings" \
    "$sandbox/cline-empty" "$sandbox/pi-auth/agent" "$sandbox/pi-empty" \
    "$sandbox/cline-config"
cat >"$sandbox/cline-cred/data/settings/providers.json" <<'CLINE_PROVIDERS'
{"providers":{"cline":{"settings":{"auth":{"accessToken":"primary-token"}}},"cline-pass":{"settings":{"auth":{"accessToken":"secondary-token"}}}}}
CLINE_PROVIDERS
cat >"$sandbox/cline-pass/data/settings/providers.json" <<'CLINE_PASS_PROVIDERS'
{"providers":{"cline-pass":{"settings":{"auth":{"accessToken":"secondary-token"}}}}}
CLINE_PASS_PROVIDERS
printf '%s\n' '{"clinepass":{"type":"oauth","access":"pi-access-token"}}' \
    >"$sandbox/pi-auth/agent/auth.json"
cline_limits_out="$(HOME="$sandbox/home" python3 - \
        "$repo_root/bin/ai-usage-cline" \
        "$sandbox/cline-cred" "$sandbox/cline-pass" "$sandbox/cline-empty" \
        "$sandbox/pi-auth" "$sandbox/pi-empty" "$sandbox/cline-config" <<'CLINE_LIMITS'
import contextlib
import datetime as dt
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import urllib.error

loader = importlib.machinery.SourceFileLoader("acline", sys.argv[1])
spec = importlib.util.spec_from_loader("acline", loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

cred_dir, pass_dir, empty_dir, pi_auth_dir, pi_empty_dir, config_dir = sys.argv[2:8]
os.environ.pop("WORKSTATION_AI_CONF", None)


def token_with(cline_home, pi_home):
    os.environ["CLINE_DIR"] = cline_home
    os.environ["PI_HOME"] = pi_home
    return module.cline_access_token()


credential = {
    "primary": token_with(cred_dir, pi_auth_dir),
    "secondary": token_with(pass_dir, pi_auth_dir),
    "pi": token_with(empty_dir, pi_auth_dir),
    "absent": token_with(empty_dir, pi_empty_dir),
}


class Response:
    def __init__(self, payload):
        self.payload = payload

    def read(self):
        return json.dumps(self.payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def serve(payload):
    return lambda *args, **kwargs: Response(payload)


def http_error(status, message):
    def raiser(*args, **kwargs):
        raise urllib.error.HTTPError("https://api.cline.bot/x", status, message, {}, None)
    return raiser


module.cline_access_token = lambda: "fake"

CAPTURED = {"data": {"limits": [
    {"type": "five_hour", "percentUsed": 64, "resetsAt": "2026-09-26T17:15:41.129154652Z"},
    {"type": "weekly", "percentUsed": 63, "resetsAt": "2026-09-30T15:13:55.131223642Z"},
    {"type": "monthly", "percentUsed": 81, "resetsAt": "2026-10-16T02:55:30.133217442Z"},
]}, "success": True}
module.urllib.request.urlopen = serve(CAPTURED)
happy = module.fetch_cline_limits()

resets = {"data": {"limits": [
    {"type": "five_hour", "percentUsed": 10, "resetsAt": 2208988800},
    {"type": "weekly", "percentUsed": 20, "resetsAt": 2208988800000},
    {"type": "monthly", "percentUsed": 30, "resetsAt": "2040-01-01T00:00:00Z"},
]}, "success": True}
module.urllib.request.urlopen = serve(resets)
normalised = module.fetch_cline_limits()
normalised_parseable = True
for limit in normalised["limits"]:
    text = limit["resetsAt"]
    try:
        parsed = dt.datetime.fromisoformat(text)
    except Exception:
        normalised_parseable = False
        continue
    if not text or parsed.tzinfo is None:
        normalised_parseable = False

module.urllib.request.urlopen = serve({"data": {"limits": [
    {"type": "five_hour", "percentUsed": 5, "resetsAt": "not-a-date"}]}, "success": True})
junk_reset = module.fetch_cline_limits()["limits"][0]["resetsAt"]

module.urllib.request.urlopen = serve({"data": {"limits": [
    {"type": "five_hour", "percentUsed": 50, "resetsAt": "2040-01-01T00:00:00Z"}]}, "success": True})
partial = module.fetch_cline_limits()["limits"]

module.urllib.request.urlopen = serve({"success": True})
malformed = module.fetch_cline_limits()

module.urllib.request.urlopen = http_error(401, "Unauthorized")
unauth = module.fetch_cline_limits()
module.urllib.request.urlopen = http_error(429, "Too Many Requests")
rate_retry = module.fetch_cline_limits()["retryAdvised"]
module.urllib.request.urlopen = lambda *args, **kwargs: (_ for _ in ()).throw(TimeoutError("timed out"))
timeout_retry = module.fetch_cline_limits()["retryAdvised"]

# Record-level integration: a limits-only account with no local history must be
# detected and ready, with tierLabel set.
os.environ["CLINE_DIR"] = empty_dir
os.environ["PI_HOME"] = pi_empty_dir
os.environ["XDG_CONFIG_HOME"] = config_dir
module.urllib.request.urlopen = serve(CAPTURED)
sys.argv = ["ai-usage-cline"]
buffer = io.StringIO()
with contextlib.redirect_stdout(buffer):
    module.main()
record = json.loads(buffer.getvalue())

print(json.dumps({
    "happy": happy,
    "normalised": normalised["limits"],
    "normalisedParseable": normalised_parseable,
    "junkReset": junk_reset,
    "partial": partial,
    "malformed": malformed,
    "unauth": unauth,
    "rateRetry": rate_retry,
    "timeoutRetry": timeout_retry,
    "credential": credential,
    "record": record,
}))
CLINE_LIMITS
)"
if printf '%s' "$cline_limits_out" | jq -e '
        .happy.tierLabel == "ClinePass" and
        (.happy.limits | length == 3) and
        .happy.limits[0].label == "5h window" and
        .happy.limits[0].percent == 0.64 and
        .happy.limits[0].windowMinutes == 300 and
        (.happy.limits[0].resetsAt | length > 0) and
        .happy.limits[1].label == "Weekly (7-day)" and
        .happy.limits[1].percent == 0.63 and
        .happy.limits[1].windowMinutes == 10080 and
        .happy.limits[2].label == "Monthly (30-day)" and
        .happy.limits[2].percent == 0.81 and
        .happy.limits[2].windowMinutes == 43200 and
        (.normalised | length == 3) and .normalisedParseable == true and
        .junkReset == "" and
        (.partial | length == 1) and .partial[0].label == "5h window" and
        .partial[0].percent == 0.5 and
        (.malformed.limits | length == 0) and
        (.malformed.usageStatusText | length > 0) and
        (.unauth.limits | length == 0) and
        (.unauth.authHelpText | length > 0) and
        .unauth.retryAdvised == false and
        (.unauth.usageStatusText | test("auth"; "i")) and
        .rateRetry == true and .timeoutRetry == true and
        .credential.primary == "primary-token" and
        .credential.secondary == "secondary-token" and
        .credential.pi == "pi-access-token" and
        .credential.absent == "" and
        (.record.limits | length == 3) and
        .record.tierLabel == "ClinePass" and
        .record.ready == true and .record.detected == true and
        .record.retryAdvised == false and .record.totalPrompts == 0 and
        .record.usageStatusText == ""' >/dev/null; then
    pass "[isolated] Cline collector maps the live ClinePass windows, emits USED, normalises resetsAt and fails closed"
else
    fail "[isolated] Cline limit contract diverged: $cline_limits_out"
fi

# A local-only Cline account with no stored credential must return `limits: []`
# with the honest "Local usage only" status and must not touch the network at
# all. The sentinel urlopen fails the test if it is ever called.
cline_nocred_out="$(HOME="$sandbox/home" \
    CLINE_DIR="$sandbox/cline-empty" \
    PI_HOME="$sandbox/pi-empty" \
    XDG_CONFIG_HOME="$sandbox/cline-config" \
    python3 - "$repo_root/bin/ai-usage-cline" <<'CLINE_NOCRED'
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys

loader = importlib.machinery.SourceFileLoader("acline", sys.argv[1])
spec = importlib.util.spec_from_loader("acline", loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
os.environ.pop("WORKSTATION_AI_CONF", None)

calls = []


def sentinel(*args, **kwargs):
    calls.append(args)
    raise AssertionError("network call attempted without a credential")


module.urllib.request.urlopen = sentinel
sys.argv = ["ai-usage-cline"]
buffer = io.StringIO()
with contextlib.redirect_stdout(buffer):
    status = module.main()
record = json.loads(buffer.getvalue())
print(json.dumps({
    "status": status,
    "calls": len(calls),
    "limits": record["limits"],
    "usageStatusText": record["usageStatusText"],
    "retryAdvised": record["retryAdvised"],
}))
CLINE_NOCRED
)"
if printf '%s' "$cline_nocred_out" | jq -e '
        .status == 0 and .calls == 0 and .limits == [] and
        .usageStatusText == "Local usage only" and .retryAdvised == false' >/dev/null; then
    pass "[isolated] Cline local-only account makes no network call and reports limits: [] honestly"
else
    fail "[isolated] Cline local-only behaviour diverged: $cline_nocred_out"
fi

# ---------------------------------------------------------------------------
# Claude 5-hour and weekly limits (live-captured body, entirely offline)
# ---------------------------------------------------------------------------
# The fixture below is the live-captured shape of `GET
# https://api.anthropic.com/api/oauth/usage`: a canonical `limits[]` classified
# on `kind`, top-level `five_hour`/`seven_day` with 0-100 USED percentages and
# ISO-8601 `resets_at` strings, plus `seven_day_overage_included` and a
# `weekly_scoped` row that must NOT become a third window. urlopen is
# monkey-patched, so this section performs no network I/O.
claude_fixture="$ROOT/tests/fixtures/agents-claude/usage.json"
mkdir -p -- "$sandbox/claude-cred-a" "$sandbox/claude-cred-b" "$sandbox/claude-empty" \
    "$sandbox/claude-home/.claude" "$sandbox/claude-pi/agent" \
    "$sandbox/claude-pi-empty/agent" "$sandbox/claude-pi-configured/agent" \
    "$sandbox/claude-config"
cat >"$sandbox/claude-cred-a/.credentials.json" <<'CLAUDE_CRED_A'
{"claudeAiOauth":{"accessToken":"primary-token","rateLimitTier":"default_claude_max_20x"}}
CLAUDE_CRED_A
cat >"$sandbox/claude-cred-b/.credentials.json" <<'CLAUDE_CRED_B'
{"claudeAiOauth":{"accessToken":"home-token","subscriptionType":"pro"}}
CLAUDE_CRED_B
printf '%s\n' '{"anthropic":{"type":"oauth","access":"pi-access-token"}}' \
    >"$sandbox/claude-pi/agent/auth.json"
printf '%s\n' '{"anthropic":{"type":"oauth"}}' \
    >"$sandbox/claude-pi-configured/agent/auth.json"

claude_limits_out="$(HOME="$sandbox/claude-home" python3 - \
        "$repo_root/bin/ai-usage-claude" "$claude_fixture" \
        "$sandbox/claude-cred-a" "$sandbox/claude-cred-b" "$sandbox/claude-empty" \
        "$sandbox/claude-pi" "$sandbox/claude-pi-empty" "$sandbox/claude-pi-configured" \
        "$sandbox/claude-config" <<'CLAUDE_LIMITS'
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import urllib.error

loader = importlib.machinery.SourceFileLoader("aclaude", sys.argv[1])
spec = importlib.util.spec_from_loader("aclaude", loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

fixture_path = sys.argv[2]
cred_a, cred_b, empty_dir, pi_dir, pi_empty, pi_configured, config_dir = sys.argv[3:10]
os.environ.pop("WORKSTATION_AI_CONF", None)
os.environ["XDG_CONFIG_HOME"] = config_dir
with open(fixture_path, encoding="utf-8") as handle:
    CAPTURED = json.load(handle)


class Response:
    def __init__(self, payload, raw=None):
        self.payload = payload
        self.raw = raw

    def read(self):
        if self.raw is not None:
            return self.raw
        return json.dumps(self.payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def serve(payload):
    return lambda *args, **kwargs: Response(payload)


def serve_raw(raw):
    return lambda *args, **kwargs: Response(None, raw)


def http_error(status, message):
    def raiser(*args, **kwargs):
        raise urllib.error.HTTPError("https://api.anthropic.com/x", status, message, {}, None)
    return raiser


def network_error(message):
    def raiser(*args, **kwargs):
        raise urllib.error.URLError(message)
    return raiser


# Credential precedence: $CLAUDE_CONFIG_DIR -> ~/.claude -> PI_HOME/agent/auth.json.
def token_with(claude_home, pi_home):
    if claude_home is None:
        os.environ.pop("CLAUDE_CONFIG_DIR", None)
    else:
        os.environ["CLAUDE_CONFIG_DIR"] = claude_home
    os.environ["PI_HOME"] = pi_home
    return module.claude_access_token()


credential = {
    "primary": token_with(cred_a, pi_dir),
    "home": token_with(cred_b, pi_dir),
    "pi": token_with(empty_dir, pi_dir),
    "absent": token_with(empty_dir, pi_empty),
}
# Plan/tier only ever comes from the user's own credential (never the body).
token_with(cred_a, pi_empty)
tier_max = module.claude_tier_label()
token_with(cred_b, pi_empty)
tier_pro = module.claude_tier_label()

# Regression: the credential reader must never mutate the credential file.
cred_path = os.path.join(cred_a, ".credentials.json")
with open(cred_path, encoding="utf-8") as handle:
    credential_bytes_before = handle.read()
token_with(cred_a, pi_empty)
with open(cred_path, encoding="utf-8") as handle:
    credential_bytes_after = handle.read()

# Happy path: classify on `kind`, emit USED fractions, ignore the scoped bucket.
module.urllib.request.urlopen = serve(CAPTURED)
happy = module.fetch_claude_limits("fake")
mapped = happy["limits"]

# resets_at normalisation: ISO / epoch seconds / epoch millis / string epoch / junk.
module.urllib.request.urlopen = serve({"limits": [
    {"kind": "session", "percent": 10, "resets_at": "2040-01-01T00:00:00Z"},
    {"kind": "weekly_all", "percent": 20, "resets_at": 2208988800},
]})
iso_and_epoch = module.fetch_claude_limits("fake")["limits"]
module.urllib.request.urlopen = serve({"limits": [
    {"kind": "session", "percent": 5, "resets_at": 2208988800000}]})
millis_reset = module.fetch_claude_limits("fake")["limits"][0]["resetsAt"]
module.urllib.request.urlopen = serve({"limits": [
    {"kind": "session", "percent": 5, "resets_at": "2208988800"}]})
string_epoch_reset = module.fetch_claude_limits("fake")["limits"][0]["resetsAt"]
module.urllib.request.urlopen = serve({"limits": [
    {"kind": "session", "percent": 5, "resets_at": "not-a-date"}]})
junk_reset = module.fetch_claude_limits("fake")["limits"][0]["resetsAt"]

# Clamp after division (150 -> 1.0); skip negative / non-numeric / non-finite.
module.urllib.request.urlopen = serve({"limits": [
    {"kind": "session", "percent": 150, "resets_at": "2040-01-01T00:00:00Z"},
    {"kind": "weekly_all", "percent": -5, "resets_at": "2040-01-01T00:00:00Z"},
    {"kind": "session", "percent": "abc", "resets_at": "2040-01-01T00:00:00Z"},
    {"kind": "weekly_all", "percent": float("nan"), "resets_at": "2040-01-01T00:00:00Z"},
]})
clamped = module.fetch_claude_limits("fake")["limits"]

# Fallback only when `limits` is absent, and the overage field adds no window.
fallback_payload = {
    "five_hour": {"utilization": 25, "resets_at": "2040-01-01T00:00:00Z"},
    "seven_day": {"utilization": 67, "resets_at": "2040-01-01T00:00:00Z"},
    "seven_day_overage_included": {"utilization": 84, "resets_at": "2040-01-01T00:00:00Z"},
}
module.urllib.request.urlopen = serve(fallback_payload)
fallback = module.fetch_claude_limits("fake")["limits"]

# Failure states.
module.urllib.request.urlopen = http_error(401, "Unauthorized")
unauth = module.fetch_claude_limits("fake")
module.urllib.request.urlopen = http_error(403, "Forbidden")
forbidden = module.fetch_claude_limits("fake")
module.urllib.request.urlopen = http_error(429, "Too Many Requests")
rate = module.fetch_claude_limits("fake")
module.urllib.request.urlopen = lambda *args, **kwargs: (_ for _ in ()).throw(TimeoutError("timed out"))
timeout = module.fetch_claude_limits("fake")
module.urllib.request.urlopen = network_error("Name or service not known")
dns = module.fetch_claude_limits("fake")
module.urllib.request.urlopen = serve_raw(b"not json")
malformed_body = module.fetch_claude_limits("fake")
module.urllib.request.urlopen = serve({"success": True})
changed = module.fetch_claude_limits("fake")
module.urllib.request.urlopen = serve({"limits": "nope"})
changed_limits = module.fetch_claude_limits("fake")
module.urllib.request.urlopen = serve({"limits": []})
configured = module.fetch_claude_limits("fake")


# Record-level integration: a limits-only account with no local history is
# both detected and ready, and never fabricates a plan.
def run_record():
    sys.argv = ["ai-usage-claude"]
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        module.main()
    return json.loads(buffer.getvalue())


os.environ["CLAUDE_CONFIG_DIR"] = empty_dir
os.environ["PI_HOME"] = pi_dir
module.urllib.request.urlopen = serve(CAPTURED)
limits_only = run_record()

# No credential: NO network call at all, and an honest local-only status. The
# sentinel fails the test if urlopen is ever reached.
calls = []


def sentinel(*args, **kwargs):
    calls.append(args)
    raise AssertionError("network call attempted without a credential")


os.environ["CLAUDE_CONFIG_DIR"] = empty_dir
os.environ["PI_HOME"] = pi_empty
module.urllib.request.urlopen = sentinel
local_only = run_record()
no_credential_calls = len(calls)

# A pi-configured anthropic account with no credential is visible but not
# ready, and still makes no network call.
os.environ["CLAUDE_CONFIG_DIR"] = empty_dir
os.environ["PI_HOME"] = pi_configured
module.urllib.request.urlopen = sentinel
configured_record = run_record()
configured_calls = len(calls) - no_credential_calls

# 401 at record level: an actionable, redacted auth failure with no retry.
os.environ["CLAUDE_CONFIG_DIR"] = empty_dir
os.environ["PI_HOME"] = pi_dir
module.urllib.request.urlopen = http_error(401, "Unauthorized")
auth_record = run_record()

print(json.dumps({
    "credential": credential,
    "tierMax": tier_max,
    "tierPro": tier_pro,
    "credentialUntouched": credential_bytes_before == credential_bytes_after,
    "happy": happy,
    "mapped": mapped,
    "isoReset": iso_and_epoch[0]["resetsAt"] if iso_and_epoch else "",
    "epochReset": iso_and_epoch[1]["resetsAt"] if len(iso_and_epoch) > 1 else "",
    "millisReset": millis_reset,
    "stringEpochReset": string_epoch_reset,
    "junkReset": junk_reset,
    "clamped": clamped,
    "fallback": fallback,
    "unauth": unauth,
    "forbidden": forbidden,
    "rate": rate,
    "timeout": timeout,
    "dns": dns,
    "malformedBody": malformed_body,
    "changed": changed,
    "changedLimits": changed_limits,
    "configured": configured,
    "limitsOnly": limits_only,
    "localOnly": local_only,
    "noCredentialCalls": no_credential_calls,
    "configuredRecord": configured_record,
    "configuredCalls": configured_calls,
    "authRecord": auth_record,
}))
CLAUDE_LIMITS
)"
if printf '%s' "$claude_limits_out" | jq -e '
        .credential.primary == "primary-token" and
        .credential.home == "home-token" and
        .credential.pi == "pi-access-token" and
        .credential.absent == "" and
        .tierMax == "default_claude_max_20x" and
        .tierPro == "pro" and
        .credentialUntouched == true and
        .happy.usageStatusText == "" and
        .happy.authHelpText == "" and
        .happy.retryAdvised == false and
        .happy.supportedWindowMinutes == [300,10080] and
        (.mapped | length == 2) and
        .mapped[0].label == "5h window" and
        .mapped[0].windowMinutes == 300 and
        .mapped[0].percent == 0.25 and
        .mapped[1].label == "Weekly (7-day)" and
        .mapped[1].windowMinutes == 10080 and
        .mapped[1].percent == 0.67 and
        (.isoReset | length > 0) and
        .isoReset == .epochReset and
        .epochReset == .millisReset and
        .millisReset == .stringEpochReset and
        .junkReset == "" and
        (.clamped | length == 1) and .clamped[0].percent == 1.0 and
        (.fallback | length == 2) and
        .fallback[0].percent == 0.25 and .fallback[1].percent == 0.67 and
        (.unauth.limits | length == 0) and
        .unauth.retryAdvised == false and
        (.unauth.authHelpText | length > 0) and
        (.unauth.usageStatusText | test("auth"; "i")) and
        (.forbidden.limits | length == 0) and
        .forbidden.retryAdvised == false and
        (.forbidden.authHelpText | length > 0) and
        (.rate.limits | length == 0) and
        .rate.retryAdvised == true and
        .rate.authHelpText == "" and
        .rate.usageStatusText == "Claude limits unavailable" and
        (.timeout.limits | length == 0) and .timeout.retryAdvised == true and
        .timeout.authHelpText == "" and
        (.dns.limits | length == 0) and .dns.retryAdvised == true and
        .dns.authHelpText == "" and
        (.malformedBody.limits | length == 0) and .malformedBody.retryAdvised == false and
        (.changed.limits | length == 0) and .changed.retryAdvised == false and
        (.changedLimits.limits | length == 0) and .changedLimits.retryAdvised == false and
        (.configured.limits | length == 0) and
        .configured.usageStatusText == "Account configured · no usage yet" and
        .configured.retryAdvised == false and
        .limitsOnly.ready == true and
        .limitsOnly.hasLocalStats == false and
        .limitsOnly.detected == true and
        .limitsOnly.totalPrompts == 0 and
        (.limitsOnly.limits | length == 2) and
        .limitsOnly.usageStatusText == "" and
        .limitsOnly.supportedWindowMinutes == [300,10080] and
        .limitsOnly.tierLabel == "" and
        .localOnly.ready == false and .localOnly.detected == false and
        .localOnly.limits == [] and .localOnly.retryAdvised == false and
        .localOnly.supportedWindowMinutes == [300,10080] and
        .localOnly.usageStatusText == "Local usage only" and
        .noCredentialCalls == 0 and
        .configuredRecord.ready == false and .configuredRecord.detected == true and
        .configuredRecord.hasLocalStats == false and
        .configuredRecord.usageStatusText == "Account configured · no usage yet" and
        .configuredCalls == 0 and
        (.authRecord.limits | length == 0) and
        .authRecord.retryAdvised == false and
        (.authRecord.usageStatusText | test("auth"; "i")) and
        (.authRecord.authHelpText | length > 0) and
        (.authRecord | tostring | test("fake") | not)' >/dev/null; then
    pass "[isolated] Claude collector maps the live oauth limits body, emits USED, normalises resetsAt and fails closed without a credential"
else
    fail "[isolated] Claude limit contract diverged: $claude_limits_out"
fi

# The Claude endpoint is read-only: no refresh token is ever read or written,
# the request is bounded, TLS stays verified and the capability field names the
# two windows Claude actually has (no monthly).
if grep -q 'api/oauth/usage' "$collector" &&
   grep -q 'supportedWindowMinutes' "$collector" &&
   grep -q 'kind == "session"' "$collector" &&
   grep -q 'ssl.create_default_context()' "$collector" &&
   grep -q 'timeout=10' "$collector" &&
   ! grep -q 'refreshToken\|refresh_token' "$collector"; then
    pass "[static] Claude collector is read-only, bounded, TLS-verified and declares its two supported windows"
else
    fail "[static] Claude collector safety or capability contract is incomplete"
fi

for collector_file in claude codex opencode cline; do
    if grep -q 'supportedWindowMinutes' "$repo_root/bin/ai-usage-$collector_file"; then
        pass "[static] $collector_file collector declares supportedWindowMinutes"
    else
        fail "[static] $collector_file collector does not declare supportedWindowMinutes"
    fi
done

# ---------------------------------------------------------------------------
# Offscreen dashboard preview + fail-safe diagnostics (isolated runtime)
# ---------------------------------------------------------------------------
if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] agents dashboard preview (qs or timeout unavailable)"
    return 0
fi

preview_root="$(mktemp -d)"
trap 'rm -rf -- "$preview_root" || true' RETURN
preview_image="$preview_root/dashboard.png"
preview_result="$preview_root/result.json"
preview_log="$preview_root/runtime.log"
preview_status=0
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$preview_root/runtime" \
XDG_CONFIG_HOME="$preview_root/config" \
XDG_STATE_HOME="$preview_root/state" \
XDG_CACHE_HOME="$preview_root/cache" \
AGENTS_DASHBOARD_PLUGIN="$plugin_dir/AgentsDashboard.qml" \
AGENTS_DASHBOARD_FIXTURE="$ROOT/tests/fixtures/agents-dashboard/records.json" \
AGENTS_DASHBOARD_IMAGE="$preview_image" \
AGENTS_DASHBOARD_RESULT="$preview_result" \
AGENTS_DASHBOARD_SELECT="codex" \
AGENTS_DASHBOARD_BACKEND_ERROR="usage backend failed" \
    /usr/bin/timeout --kill-after=1s 16s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/agents-dashboard/shell.qml" >"$preview_log" 2>&1 || preview_status=$?

if [[ "$preview_status" -eq 0 && -s "$preview_image" && -s "$preview_result" ]] &&
   jq -e '.records == 7 and .rows == 7 and .showBalance == true and
          .selected == "codex" and .imageSaved == true' "$preview_result" >/dev/null &&
   runtime_log_is_environment_only "$preview_log" '(\[AGENTS\]|result\.json)' >/dev/null &&
   grep -q '\[AGENTS\] unmet_condition provider=codex condition=missing_window_minutes' "$preview_log" &&
   grep -q 'provider=codex condition=zero_window_minutes' "$preview_log" &&
   grep -q 'provider=codex condition=missing_resets_at' "$preview_log" &&
   grep -q 'provider=codex condition=absent_balance' "$preview_log" &&
   grep -q 'provider=claude condition=missing_limits' "$preview_log" &&
   grep -q 'provider=backend condition=collector_failed' "$preview_log"; then
    pass "[isolated-runtime] offscreen dashboard preview renders the fixture and logs every unmet condition and the collector failure"
else
    preview_log_ok=0
    runtime_log_is_environment_only "$preview_log" '(\[AGENTS\]|result\.json)' >/dev/null && preview_log_ok=1
    preview_image_state="no"
    [[ -s "$preview_image" ]] && preview_image_state="yes"
    preview_result_detail="$(cat "$preview_result" 2>&1 || true)"
    fail "[isolated-runtime] dashboard preview or diagnostics regressed (status=$preview_status log_ok=$preview_log_ok image=$preview_image_state result=$preview_result_detail)"
fi

# ---------------------------------------------------------------------------
# Focus-ring policy (isolated runtime)
# ---------------------------------------------------------------------------
# A focus ring is a keyboard affordance. This drives the real dashboard body
# offscreen, performs a pointer selection through the dashboard's pointer entry
# point, and verifies it leaves no keyboard cursor and no ring on either the
# dashboard-owned wrapper or the shared AureliaIconButton primitive
# (`keyboardFocus`). It then performs a real keyboard navigation and verifies
# the ring returns. The rendered pixels are not asserted; the booleans that
# drive the border are.
if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] agents focus-ring policy (qs or timeout unavailable)"
    return 0
fi

focus_root="$(mktemp -d)"
trap 'rm -rf -- "$focus_root" || true' RETURN
focus_result="$focus_root/focus.json"
focus_log="$focus_root/runtime.log"
focus_status=0
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$focus_root/runtime" \
XDG_CONFIG_HOME="$focus_root/config" \
XDG_STATE_HOME="$focus_root/state" \
XDG_CACHE_HOME="$focus_root/cache" \
AGENTS_DASHBOARD_PLUGIN="$plugin_dir/AgentsDashboard.qml" \
AGENTS_DASHBOARD_FIXTURE="$ROOT/tests/fixtures/agents-dashboard/records.json" \
AGENTS_DASHBOARD_RESULT="$focus_result" \
    /usr/bin/timeout --kill-after=1s 20s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/agents-dashboard/interaction.qml" >"$focus_log" 2>&1 || focus_status=$?

if [[ "$focus_status" -eq 0 && -s "$focus_result" ]] &&
   jq -e '
        .focusPolicy.atRestCursorActive == false and
        .focusPolicy.atRestRefreshRing == false and
        .focusPolicy.atRestCloseRing == false and
        .focusPolicy.atRestRefreshKeyboardFocus == false and
        .focusPolicy.atRestCloseKeyboardFocus == false and
        .focusPolicy.afterPointerCursorActive == false and
        .focusPolicy.afterPointerRefreshRing == false and
        .focusPolicy.afterPointerCloseRing == false and
        .focusPolicy.afterPointerRefreshKeyboardFocus == false and
        .focusPolicy.afterPointerCloseKeyboardFocus == false and
        .focusPolicy.afterKeyboardCursorActive == true and
        .focusPolicy.afterKeyboardFocusRegion == "actions" and
        .focusPolicy.afterKeyboardRefreshRing == true and
        .focusPolicy.afterKeyboardRefreshKeyboardFocus == true' \
       "$focus_result" >/dev/null &&
   runtime_log_is_environment_only "$focus_log" '(\[AGENTS\]|@interaction\.qml)' >/dev/null; then
    pass "[isolated-runtime] a pointer selection leaves no keyboard focus ring while real keyboard navigation establishes and shows one"
else
    fail "[isolated-runtime] focus-ring policy regressed (status=$focus_status result=$(cat "$focus_result" 2>&1 || true))"
fi

# ---------------------------------------------------------------------------
# Backend-path race (isolated runtime)
# ---------------------------------------------------------------------------
if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] agents backend-path race (qs or timeout unavailable)"
    return 0
fi

race_root="$(mktemp -d)"
trap 'rm -rf -- "$race_root" || true' RETURN
mkdir -p -- "$race_root/runtime" "$race_root/state" "$race_root/config" \
    "$race_root/cache" "$race_root/shell" "$race_root/bin"
cat >"$race_root/bin/workstation-ai" <<'MOCK_AI'
#!/usr/bin/env bash
case "${1:-}" in
    usage-update) exit 0 ;;
    usage)
        printf '%s\n' '{"agents":[{"id":"mock","name":"Mock Agent","detected":true,"ready":true,"todayTotalTokens":1234,"todayPrompts":2,"todaySessions":1,"todayTokensByModel":{},"recentDays":[],"modelUsage":{},"totalPrompts":2,"totalSessions":1,"activeDays":1,"activeDates":[],"tierLabel":"","usageStatusText":"","authHelpText":"","limits":[]}]}'
        ;;
    *) exit 0 ;;
esac
MOCK_AI
chmod 0755 "$race_root/bin/workstation-ai"
race_result="$race_root/result.json"
: >"$race_result"
race_status=0
AGENTS_WIDGET_SOURCE="$plugin_dir/AgentsBarWidget.qml" \
AGENTS_AURELIA_PATH="$race_root/shell" \
AGENTS_RACE_RESULT="$race_result" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$race_root/runtime" XDG_STATE_HOME="$race_root/state" \
XDG_CONFIG_HOME="$race_root/config" XDG_CACHE_HOME="$race_root/cache" \
    /usr/bin/timeout --kill-after=1s 14s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/agents-race/shell.qml" \
    >"$race_root/race.log" 2>&1 || race_status=$?
race_log_ok=0
runtime_log_is_environment_only "$race_root/race.log" >/dev/null && race_log_ok=1
if [[ "$race_status" -eq 0 && "$race_log_ok" -eq 1 ]] &&
   jq -e '.loaded == true and .agents == 1 and .hasAgents == true and .lastError == "" and
          .stateKey == "unknown" and .hasApi == true and .square == true' \
       "$race_result" >/dev/null; then
    pass "[isolated-runtime] agents widget recovers when the host assigns aureliaPath after construction"
else
    details="$(cat "$race_result" || true)"
    fail "[isolated-runtime] agents widget backend-path race regressed (status=$race_status log_ok=$race_log_ok result=$details)"
fi
