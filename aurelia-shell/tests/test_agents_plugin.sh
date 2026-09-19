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

if jq -e '.id == "aurelia.agents" and .kinds == ["bar-widget"] and
          .entryPoints.barWidget == "AgentsBarWidget.qml" and
          .barWidget.defaultSection == "right"' \
       "$plugin_dir/manifest.json" >/dev/null; then
    pass "[static] agents manifest is a self-hiding bar widget registered for the right section"
else
    fail "[static] agents manifest contract is invalid"
fi

if grep -q 'visible: root.hasAgents' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q '"usage-update"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q '"usage"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AgentUsage.parseRecords' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'applyLimitNotifications' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'notify-send' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AgentUsage.severityForLimit' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AgentUsage.bindingWindow' "$plugin_dir/AgentsBarWidget.qml"; then
    pass "[static] agents widget refreshes through workstation-ai and hides until an agent is detected"
else
    fail "[static] agents widget backend wiring is incomplete"
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

if grep -q 'AgentUsage.paceInfo' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'ALL ACCOUNTS' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'AgentUsage.severityForLimit' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'property real marker' "$plugin_dir/AgentsPanel.qml" &&
   grep -q 'AgentUsage.elapsedFraction' "$plugin_dir/AgentsPanel.qml"; then
    pass "[static] agents panel shows pace, severity colours, and an all-accounts snapshot"
else
    fail "[static] agents panel dashboard sections are incomplete"
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
module.exports = { number, formatTokens, parseRecords, readyAgents, detectedAgents, todayTotal, tierLabel, sortedModels, recentBars, bindingWindow, resetMsFor, formatDuration, heroMeta, dayLabel, weekPeak, modelRows, clamp, todayDate, limitTransitions, severityFor, severityForLimit, paceInfo, elapsedFraction };
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
const ok =
    A.severityFor(50) === "ok" && A.severityFor(80) === "warn" && A.severityFor(95) === "critical" &&
    A.severityForLimit({percent: 0.95}) === "critical" &&
    paceEven && Math.abs(paceEven.elapsed - 0.5) < 0.01 && paceEven.behind === false &&
    paceBehind && paceBehind.behind === true &&
    first.notifications.length === 0 &&
    reset.notifications.length === 1 && reset.notifications[0].title.indexOf("reset") >= 0 &&
    exhausted.notifications.length === 1 && exhausted.notifications[0].title.indexOf("critical") >= 0 &&
    steady.notifications.length === 0 &&
    A.bindingWindow({limits: limits}).percent === 0.8 &&
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
mkdir -p -- "$sandbox/home/.claude/projects/proj" "$sandbox/state" "$sandbox/config"
cat >"$sandbox/home/.claude/projects/proj/session.jsonl" <<'TRANSCRIPT'
{"type":"assistant","timestamp":"2026-09-19T10:00:00Z","sessionId":"s1","message":{"id":"m1","role":"assistant","model":"claude-opus-4","usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":50,"cache_creation_input_tokens":10}}}
{"type":"assistant","timestamp":"2026-09-18T09:00:00Z","sessionId":"s2","message":{"id":"m2","role":"assistant","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
{"type":"user","message":{"role":"user"}}
TRANSCRIPT

collector_out="$(CLAUDE_CONFIG_DIR="$sandbox/home/.claude" "$collector"  || true)"
if printf '%s' "$collector_out" | jq -e '
        .id == "claude" and
        .ready == true and
        .hasLocalStats == true and
        .totalPrompts == 2 and
        .totalSessions == 2 and
        .todayPrompts == 1 and
        .todayTotalTokens == 360 and
        .todayTokensByModel["claude-opus-4"] == 360 and
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
mkdir -p -- "$sandbox/codex/sessions/2026/09/19" \
    "$sandbox/config/Code/User/globalStorage/saoudrizwan.claude-dev/tasks/t1" \
    "$sandbox/data"
cat >"$sandbox/codex/sessions/2026/09/19/rollout-x.jsonl" <<'CODEX_ROLLOUT'
{"timestamp":"2026-09-19T10:00:00Z","type":"session_meta","payload":{"id":"s1"}}
{"timestamp":"2026-09-19T10:00:01Z","type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5"}}
{"timestamp":"2026-09-19T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":50,"cached_input_tokens":20,"cache_write_input_tokens":5,"total_tokens":175}}}}
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
        $c.modelUsage["gpt-5"].inputTokens == 100 and
        $l.detected == true and $l.totalPrompts == 1 and
        $l.modelUsage["cline-pass/glm-5.3-flash"].outputTokens == 200' >/dev/null; then
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
    id=$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
    method=$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("method",""))' 2>/dev/null)
    case "$method" in
        account/read) printf '{"id":%s,"result":{"account":{"type":"chatgpt","planType":"plus"}}}\n' "$id" ;;
        account/rateLimits/read) printf '{"id":%s,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":11,"windowDurationMins":10080,"resetsAt":1800600000}}}}\n' "$id" ;;
        *) printf '{"id":%s,"result":{}}\n' "$id" ;;
    esac
done
MOCK_CODEX
chmod 0755 "$sandbox/bin/codex"
codex_rpc="$(HOME="$sandbox/home" CODEX_HOME="$sandbox/codex" CODEX_BIN="$sandbox/bin/codex" "$repo_root/bin/ai-usage-codex" 2>/dev/null || true)"
if printf '%s' "$codex_rpc" | jq -e '
        .tierLabel == "plus" and
        (.limits | length == 2) and
        .limits[0].percent == 0.42 and .limits[0].label == "5h window" and
        .limits[0].windowMinutes == 300 and
        .limits[1].percent == 0.11 and .limits[1].label == "Weekly (7-day)" and
        (.limits[0].resetsAt | length > 0)' >/dev/null 2>&1; then
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
PI_SESSION
pi_opencode="$(HOME="$sandbox/home" PI_HOME="$sandbox/pi" XDG_DATA_HOME="$sandbox/empty-data" "$repo_root/bin/ai-usage-opencode" 2>/dev/null || true)"
pi_cline="$(HOME="$sandbox/home" PI_HOME="$sandbox/pi" XDG_CONFIG_HOME="$sandbox/empty-config" CLINE_DIR="$sandbox/empty-cline" "$repo_root/bin/ai-usage-cline" 2>/dev/null || true)"
pi_codex="$(HOME="$sandbox/home" PI_HOME="$sandbox/pi" CODEX_HOME="$sandbox/no-codex-home" CODEX_BIN="$sandbox/no-codex" "$repo_root/bin/ai-usage-codex" 2>/dev/null || true)"
if printf '%s' "$pi_opencode" | jq -e '.detected == true and .totalPrompts == 1 and .todayTotalTokens == 128 and .modelUsage["deepseek-v4.1-flash"].inputTokens == 100' >/dev/null 2>&1 &&
   printf '%s' "$pi_cline" | jq -e '.detected == true and .totalPrompts == 1 and .modelUsage["cline-pass/glm-5.3"].outputTokens == 10' >/dev/null 2>&1 &&
   printf '%s' "$pi_codex" | jq -e '.detected == true and .totalPrompts == 1 and .modelUsage["gpt-5.5"].inputTokens == 7' >/dev/null 2>&1; then
    pass "[isolated] pi session usage is merged into the matching provider collectors"
else
    fail "[isolated] pi session merge diverged (opencode=$pi_opencode cline=$pi_cline codex=$pi_codex)"
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
runtime_log_is_environment_only "$race_root/race.log" >/dev/null 2>&1 && race_log_ok=1
if [[ "$race_status" -eq 0 && "$race_log_ok" -eq 1 ]] &&
   jq -e '.loaded == true and .agents == 1 and .hasAgents == true and .lastError == ""' \
       "$race_result" >/dev/null 2>&1; then
    pass "[isolated-runtime] agents widget recovers when the host assigns aureliaPath after construction"
else
    details="$(cat "$race_result" 2>/dev/null || true)"
    fail "[isolated-runtime] agents widget backend-path race regressed (status=$race_status log_ok=$race_log_ok result=$details)"
fi
