#!/usr/bin/env bash

# Real-event tests for the consolidated AI Usage dashboard. Unlike the earlier
# interaction probe, this drives the dashboard with QtTest pointer and key
# events, so it proves the events actually reach the items rather than
# simulating the handlers' inputs directly.
#
# The earlier design had a gap here: it set `panelToolTip.triggerItem`/`lines`
# and called `handleKey()` directly, so it never proved delivery. This suite
# closes that gap.
#
# The bar tooltip binding-loop rule applies to every fixture run: ANY
# `Binding loop detected` line in the captured log fails the suite.

set -Eeuo pipefail

section "Agents Dashboard Real Events"

plugin_dir="$ROOT/plugins/aurelia.agents"
fixture="$ROOT/tests/fixtures/agents-dashboard/records.json"
harness="$ROOT/tests/fixtures/agents-dashboard/events.qml"

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] agents dashboard real events (qs or timeout unavailable)"
    return 0
fi

events_root="$(mktemp -d)"
trap 'rm -rf -- "$events_root"' RETURN
mkdir -p -- "$events_root/runtime" "$events_root/state" \
    "$events_root/config" "$events_root/cache"
events_result="$events_root/events.json"
events_log="$events_root/runtime.log"
events_status=0

QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$events_root/runtime" \
XDG_CONFIG_HOME="$events_root/config" \
XDG_STATE_HOME="$events_root/state" \
XDG_CACHE_HOME="$events_root/cache" \
AGENTS_DASHBOARD_PLUGIN="$plugin_dir/AgentsDashboard.qml" \
AGENTS_DASHBOARD_FIXTURE="$fixture" \
AGENTS_DASHBOARD_RESULT="$events_result" \
    /usr/bin/timeout --kill-after=1s 25s /usr/bin/qs --no-duplicate \
    --path "$harness" >"$events_log" 2>&1 || events_status=$?

binding_loops="$(awk '/Binding loop detected/{count++} END {print count + 0}' "$events_log")"

# --- Item 4: real pointer hover must open the shared inline tooltip and must
# not be wiped by the panel-level keyboard-cursor handler. The footer pace
# legend (priority 3) depends on the same column hover source.
if [[ "$events_status" -eq 0 && -s "$events_result" && "$binding_loops" -eq 0 ]] &&
   jq -e '
        .cellFound == true and
        .cellObjectName == "matrixCell-0-five_hour" and
        .tooltipVisibleOnHover == true and
        .tooltipLinesOnHover >= 1 and
        .tooltipTriggerIsCell == "matrixCell-0-five_hour" and
        .hoverColumnOnHover == "five_hour" and
        .footerKindOnHover == "legend" and
        .footerPriorityOnHover == 3 and
        .tooltipVisibleAfterLeave == false and
        .hoverColumnAfterLeave == ""' \
       "$events_result" >/dev/null &&
   runtime_log_is_environment_only "$events_log" '(\[AGENTS\]|@events\.qml|agents-dashboard)' >/dev/null; then
    pass "[isolated-runtime] real hover opens the cell tooltip and the pace-legend footer hint, and leaving hides it"
else
    fail "[isolated-runtime] real hover delivery regressed (status=$events_status loops=$binding_loops result=$(cat "$events_result" 2>&1))"
fi
