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
# rotation rules (idle only, pause on hover, stop while hidden) intact.
if grep -Fq 'interval: 4000' "$dashboard" &&
   grep -Fq 'running: dashboard.panelShown && dashboard.footerHint.priority === 5 && !footerHover.hovered' "$dashboard" &&
   grep -Fq 'property: "opacity"; to: 0; duration: 75' "$dashboard" &&
   grep -Fq 'property: "opacity"; to: 1; duration: 75' "$dashboard" &&
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
