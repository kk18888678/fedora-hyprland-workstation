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
