#!/usr/bin/env bash

# Measured footer contract for the consolidated AI Usage dashboard:
#   * item 8: the pager's right edge is identical across every idle hint kind
#     (text, legend, keys) and the stale hint, because the hint fills the row
#     and the pager has a fixed width and is right-aligned;
#   * item 9: each pace-legend RowLayout centres its mini meter and its label
#     on one line (+/- 1 px);
#   * item 10: the idle rotation runs every 4000 ms with a 150 ms cross-fade
#     (asserted statically; the other rotation rules are unchanged).
#
# Any `Binding loop detected` line in a fixture log fails.

set -Eeuo pipefail

section "Agents Dashboard Footer"

dashboard="$ROOT/plugins/aurelia.agents/AgentsDashboard.qml"
fixture="$ROOT/tests/fixtures/agents-dashboard/records.json"
harness="$ROOT/tests/fixtures/agents-dashboard/footer-geometry.qml"

# Static pins for the rotation timing. The interval gate keeps the other
# rotation rules (idle only, pause on hover, stop while hidden) intact. The
# rotation and key-hint intervals are properties so the event fixture can
# shorten them instead of waiting a real four seconds.
if grep -Fq 'property int rotationIntervalMs: 4000' "$dashboard" &&
   grep -Fq 'property int keyHintIntervalMs: 4000' "$dashboard" &&
   grep -Fq 'interval: dashboard.rotationIntervalMs' "$dashboard" &&
   grep -Fq 'interval: dashboard.keyHintIntervalMs' "$dashboard" &&
   grep -Fq 'keyboard: keyHintVisible' "$dashboard" &&
   grep -Fq 'running: dashboard.panelShown && dashboard.footerHint.priority === 5 && !footerHover.hovered' "$dashboard" &&
   grep -Fq 'property: "opacity"; to: 0; duration: 75' "$dashboard" &&
   grep -Fq 'property: "opacity"; to: 1; duration: 75' "$dashboard" &&
   ! grep -Fq 'keyboard: cursorActive' "$dashboard" &&
   ! grep -Fq 'interval: 8000' "$dashboard" &&
   ! grep -Fq 'duration: 100' "$dashboard"; then
    pass "[static] idle rotation is 4000 ms with a 150 ms cross-fade and the idle/hover/shown gates"
else
    fail "[static] footer rotation timing regressed"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] agents footer geometry (qs or timeout unavailable)"
    return 0
fi

footer_root="$(mktemp -d)"
trap 'rm -rf -- "$footer_root"' RETURN
mkdir -p -- "$footer_root/runtime" "$footer_root/state" \
    "$footer_root/config" "$footer_root/cache"
footer_result="$footer_root/footer.json"
footer_log="$footer_root/runtime.log"
footer_status=0

QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$footer_root/runtime" \
XDG_CONFIG_HOME="$footer_root/config" \
XDG_STATE_HOME="$footer_root/state" \
XDG_CACHE_HOME="$footer_root/cache" \
AGENTS_DASHBOARD_PLUGIN="$dashboard" \
AGENTS_DASHBOARD_FIXTURE="$fixture" \
AGENTS_DASHBOARD_RESULT="$footer_result" \
    /usr/bin/timeout --kill-after=1s 25s /usr/bin/qs --no-duplicate \
    --path "$harness" >"$footer_log" 2>&1 || footer_status=$?

binding_loops="$(awk '/Binding loop detected/{count++} END {print count + 0}' "$footer_log")"

# --- Item 8: one right edge, one fixed width, across text/legend/keys/stale.
if [[ "$footer_status" -eq 0 && -s "$footer_result" && "$binding_loops" -eq 0 ]] &&
   jq -e '
        (.samples | length) == 5 and
        ([.samples[].pagerRight] | unique | length) == 1 and
        ([.samples[].pagerWidth] | unique | length) == 1 and
        .samples[0].kind == "text" and
        .samples[1].kind == "legend" and
        .samples[2].kind == "keys" and
        .samples[3].priority == 1' \
       "$footer_result" >/dev/null; then
    pass "[isolated-runtime] the pager right edge and width are fixed across text, legend, keys and stale hints"
else
    fail "[isolated-runtime] pager geometry moves with the hint (status=$footer_status loops=$binding_loops result=$(cat "$footer_result" 2>&1))"
fi

# --- Item 9: the legend mini meter and label share one centre line.
if [[ "$footer_status" -eq 0 && -s "$footer_result" && "$binding_loops" -eq 0 ]] &&
   jq -e '
        .legendCentres as $c
        | ($c.evenMeter != null) and ($c.evenLabel != null) and
          ($c.fastMeter != null) and ($c.fastLabel != null) and
          (($c.evenMeter - $c.evenLabel) | fabs) <= 1 and
          (($c.fastMeter - $c.fastLabel) | fabs) <= 1' \
       "$footer_result" >/dev/null &&
   runtime_log_is_environment_only "$footer_log" '(\[AGENTS\]|agents-dashboard|@footer-geometry\.qml)' >/dev/null; then
    pass "[isolated-runtime] each legend meter and label share one vertical centre line within 1 px"
else
    fail "[isolated-runtime] legend centre-line alignment regressed (status=$footer_status loops=$binding_loops result=$(cat "$footer_result" 2>&1))"
fi

# --- Item 1 (round 2): the bounded key-caps hint must not latch. A real
# arrow key shows the key-caps hint, the shortened key-hint interval decays it
# back to the idle rotation at index 0, and one shortened rotation interval
# advances the rotation. The hover (3/4) and stale (1) hint priorities are
# audited at the same time: none may latch when its condition clears.
latch_fixture="$ROOT/tests/fixtures/agents-dashboard/footer-latch.qml"
latch_result="$footer_root/footer-latch.json"
latch_log="$footer_root/footer-latch.log"
latch_status=0

QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$footer_root/runtime" \
XDG_CONFIG_HOME="$footer_root/config" \
XDG_STATE_HOME="$footer_root/state" \
XDG_CACHE_HOME="$footer_root/cache" \
AGENTS_DASHBOARD_PLUGIN="$dashboard" \
AGENTS_DASHBOARD_FIXTURE="$fixture" \
AGENTS_DASHBOARD_RESULT="$latch_result" \
    /usr/bin/timeout --kill-after=1s 25s /usr/bin/qs --no-duplicate \
    --path "$latch_fixture" >"$latch_log" 2>&1 || latch_status=$?

latch_loops="$(awk '/Binding loop detected/{count++} END {print count + 0}' "$latch_log")"

if [[ "$latch_status" -eq 0 && -s "$latch_result" && "$latch_loops" -eq 0 ]] &&
   jq -e '
        .keyTargetActiveFocus == true and
        .beforeKey.priority == 5 and .beforeKey.kind == "text" and
        .beforeKey.rotationIndex == 0 and .beforeKey.keyHintVisible == false and
        .afterKey.priority == 2 and .afterKey.kind == "keys" and
        .afterKey.keyHintVisible == true and .afterKey.cursorActive == true and
        .afterKeyExpiry.priority == 5 and .afterKeyExpiry.kind == "text" and
        .afterKeyExpiry.rotationIndex == 0 and
        .afterKeyExpiry.keyHintVisible == false and
        .afterKeyExpiry.cursorActive == true and
        .afterRotation.priority == 5 and
        (.afterRotation.rotationIndex > .afterKeyExpiry.rotationIndex) and
        (.afterRotation.kind != .afterKeyExpiry.kind) and
        .priorityLegend == 3 and .priorityAfterLegendExit == 5 and
        .priorityRow == 4 and .priorityAfterRowExit == 5 and
        .priorityStale == 1 and .priorityAfterFresh == 5' \
       "$latch_result" >/dev/null &&
   runtime_log_is_environment_only "$latch_log" '(\[AGENTS\]|agents-dashboard|@footer-latch\.qml)' >/dev/null; then
    pass "[isolated-runtime] a real arrow key shows the key-caps hint, the hint decays back to the idle rotation, and the rotation advances"
else
    fail "[isolated-runtime] bounded key-caps hint regressed (status=$latch_status loops=$latch_loops result=$(cat "$latch_result" 2>&1))"
fi
