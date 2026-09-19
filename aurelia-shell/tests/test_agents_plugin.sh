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

if grep -q 'visible: root.ready' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q '"usage-update"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q '"usage"' "$plugin_dir/AgentsBarWidget.qml" &&
   grep -q 'AgentUsage.parseRecords' "$plugin_dir/AgentsBarWidget.qml"; then
    pass "[static] agents widget refreshes through workstation-ai and hides until a record is ready"
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
   grep -q 'cmd_usage()' "$backend"; then
    pass "[static] usage collector is executable and the backend exposes usage/usage-update"
else
    fail "[static] usage backend or collector wiring is missing"
fi

# ---------------------------------------------------------------------------
# Pure record projection (node)
# ---------------------------------------------------------------------------
if command -v node >/dev/null; then
    projection_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_dir/AgentUsage.js" >"$projection_test"
    cat >>"$projection_test" <<'AGENT_USAGE_EXPORTS'
module.exports = { number, formatTokens, parseRecords, readyAgents, todayTotal, tierLabel, sortedModels, recentBars };
AGENT_USAGE_EXPORTS
    if node -e '
const A = require(process.argv[1]);
const records = A.parseRecords(JSON.stringify({agents: [
    {id: "claude", ready: true, todayTotalTokens: 1500, tierLabel: "Max"},
    {id: "codex", ready: false}
]}));
const bars = A.recentBars([
    {date: "2026-09-18", messageCount: 0},
    {date: "2026-09-19", messageCount: 10}
]);
const models = A.sortedModels({small: {inputTokens: 1}, big: {inputTokens: 10, outputTokens: 5}});
const ok =
    A.parseRecords("not json").length === 0 &&
    A.parseRecords("{}").length === 0 &&
    records.length === 2 &&
    A.readyAgents(records).length === 1 &&
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
