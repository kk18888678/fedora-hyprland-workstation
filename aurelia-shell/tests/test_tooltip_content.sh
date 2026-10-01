#!/usr/bin/env bash

# Shared tooltip body: the `lineCount` alignment binding must stay a one-way,
# content-driven decision. The previous `horizontalAlignment: lineCount > 1 ?
# ...` read a property the Text's own laid-out width influences, which the
# live shell reported as:
#   QML QQuickText at aurelia-shell/ui/AureliaToolTipContent.qml[135:9]:
#   Binding loop detected for property "horizontalAlignment": ...:144:13
#
# The regression guard is measured, not grepped: the fixture instantiates the
# real content with a short, a long (wrapping) and a multi-line string and the
# test fails if the captured log contains ANY `Binding loop detected` line.
# Every fixture run in this repository now applies the same rule.

set -Eeuo pipefail

section "Shared Tooltip Content Binding Loop"

content_source="$ROOT/ui/AureliaToolTipContent.qml"
fixture="$ROOT/tests/fixtures/tooltip-content/binding-loop.qml"

if [[ -f "$content_source" ]] &&
   grep -Fq 'readonly property bool textIsWrapped' "$content_source" &&
   grep -Fq 'plainTextMetrics.advanceWidth > maxTextWidth' "$content_source" &&
   grep -Fq 'horizontalAlignment: contentRoot.textIsWrapped' "$content_source" &&
   ! grep -Eq 'horizontalAlignment:[[:space:]]*lineCount' "$content_source"; then
    pass "[static] tooltip alignment is a one-way content decision, not a lineCount binding"
else
    fail "[static] tooltip content still derives alignment from a layout-owned property"
fi

section "Bar Tooltip Input Pass-Through"

bar_tooltip_source="$ROOT/ui/AureliaToolTip.qml"

# The bar tooltip is a PopupWindow that describes the icon under the pointer.
# If its surface accepted pointer input it could map under the cursor and make
# the icon lose hover, dismissing the tooltip and reopening it: the reported
# open-then-close flicker. The empty input region is the structural guard; the
# live checklist exercises it on the real compositor.
if grep -Fq 'mask: Region {}' "$bar_tooltip_source"; then
    pass "[static] bar tooltip sets an empty input region and can never steal pointer hover"
else
    fail "[static] bar tooltip has no empty input region; it can still flicker under the cursor"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] tooltip content binding loop (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root"' RETURN
runtime_log="$runtime_root/runtime.log"
runtime_status=0
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" \
    "$runtime_root/config" "$runtime_root/cache"

QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
TOOLTIP_CONTENT_SOURCE="file://$content_source" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 15s /usr/bin/qs --no-duplicate \
    --path "$fixture" --no-color >"$runtime_log" 2>&1 || runtime_status=$?

binding_loops="$(awk '/Binding loop detected/{count++} END {print count + 0}' "$runtime_log")"

if [[ "$binding_loops" -eq 0 ]] &&
   runtime_log_is_environment_only "$runtime_log"; then
    pass "[isolated-runtime] short, long and multi-line tooltip bodies render with zero binding loops"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    fail "[isolated-runtime] tooltip body logged $binding_loops binding loops (status=$runtime_status): $details"
fi

section "Bar Tooltip Model Ticks"

# Permanent opt-in observability must be gated on AURELIA_TOOLTIP_DEBUG=1 and a
# complete no-op without it, and the host must not let a data refresh collapse
# its size or drop its visibility.
if grep -Fq 'Quickshell.env("AURELIA_TOOLTIP_DEBUG") === "1"' "$bar_tooltip_source" &&
   grep -Fq 'if (!root.tooltipDebugEnabled) return' "$bar_tooltip_source" &&
   grep -Fq 'backingWindowVisible=' "$bar_tooltip_source" &&
   grep -Fq 'implicitHeight: Math.max(1, tooltipBody.implicitHeight + verticalPadding * 2)' "$bar_tooltip_source" &&
   grep -Fq 'if (root.hovered && !root.revealed) showTimer.restart()' "$bar_tooltip_source"; then
    pass "[static] bar tooltip observability is opt-in and content refreshes cannot reset a revealed tooltip"
else
    fail "[static] bar tooltip observability gate or refresh handling regressed"
fi

ticks_fixture="$ROOT/tests/fixtures/bar-tooltip/ticks.qml"
ticks_debug_result="$runtime_root/ticks-debug.json"
ticks_debug_log="$runtime_root/ticks-debug.log"
ticks_noop_result="$runtime_root/ticks-noop.json"
ticks_noop_log="$runtime_root/ticks-noop.log"
ticks_debug_status=0
ticks_noop_status=0

QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
TT_SOURCE="file://$bar_tooltip_source" \
TT_RESULT="$ticks_debug_result" \
AURELIA_TOOLTIP_DEBUG=1 \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 15s /usr/bin/qs --no-duplicate \
    --path "$ticks_fixture" --no-color >"$ticks_debug_log" 2>&1 || ticks_debug_status=$?

QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
TT_SOURCE="file://$bar_tooltip_source" \
TT_RESULT="$ticks_noop_result" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 15s /usr/bin/qs --no-duplicate \
    --path "$ticks_fixture" --no-color >"$ticks_noop_log" 2>&1 || ticks_noop_status=$?

ticks_debug_loops="$(awk '/Binding loop detected/{count++} END {print count + 0}' "$ticks_debug_log")"
tooltip_log_lines="$(grep -c '\[TOOLTIP\]' "$ticks_debug_log" || true)"
tooltip_noop_lines="$(grep -c '\[TOOLTIP\]' "$ticks_noop_log" || true)"

if [[ "$ticks_debug_status" -eq 0 && -s "$ticks_debug_result" ]] &&
   jq -e '
        (.samples | length) == 4 and
        ([ .samples[].present ] | all) and
        ([ .samples[].hovered ] | all) and
        ([ .samples[].revealed ] | all) and
        ([ .samples[].visible ] | all) and
        ([ .samples[].backingWindowVisible ] | all) and
        ([ .samples[] | select(.width <= 0 or .height <= 0) ] | length) == 0 and
        ([ .samples[] | select(.contentWidth <= 0 or .contentHeight <= 0) ] | length) == 0 and
        .samples[0].kind == "list" and .samples[0].length == 2' \
       "$ticks_debug_result" >/dev/null &&
   [[ "$ticks_debug_loops" -eq 0 ]] &&
   [[ "$tooltip_log_lines" -gt 0 ]] &&
   runtime_log_is_environment_only "$ticks_debug_log" '(\[TOOLTIP-FIXTURE\]|@ticks\.qml|window masks)' >/dev/null; then
    pass "[isolated-runtime] three model ticks keep the bar tooltip visible at a non-zero size, with opt-in transition logs"
else
    fail "[isolated-runtime] bar tooltip model ticks regressed (status=$ticks_debug_status loops=$ticks_debug_loops logs=$tooltip_log_lines result=$(cat "$ticks_debug_result" 2>&1))"
fi

if [[ "$ticks_noop_status" -eq 0 && -s "$ticks_noop_result" && "$tooltip_noop_lines" -eq 0 ]]; then
    pass "[isolated-runtime] without AURELIA_TOOLTIP_DEBUG=1 the bar tooltip logging is a complete no-op"
else
    fail "[isolated-runtime] bar tooltip logged without AURELIA_TOOLTIP_DEBUG=1 (status=$ticks_noop_status lines=$tooltip_noop_lines)"
fi
