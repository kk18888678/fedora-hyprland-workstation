#!/usr/bin/env bash

# T54 regression gate for the production bar QML context and runtime-log
# classification. The headless runner cannot provide a real PanelWindow
# backend, so source identity and the diagnostic classifier are tested without
# pretending that a backend skip is live entry-point coverage.

set -Eeuo pipefail

section "Aurelia Production Bar Entry Point"

bar_file="$ROOT/plugins/aurelia.bar/Bar.qml"
panel_file="$ROOT/plugins/aurelia.bar/BarPanel.qml"

if [[ -f "$bar_file" ]] &&
   grep -Fq 'id: barRoot' "$bar_file" &&
   ! grep -Eq '\broot\.' "$bar_file" &&
   grep -Fq 'property color transparentForeground' "$bar_file" &&
   grep -Fq 'barRoot.transparentForeground' "$bar_file"; then
    pass "[static] production Bar.qml uses its declared barRoot context for every transparent-state mutation"
else
    fail "[static] production Bar.qml contains an undeclared root reference or missing transparent-state property"
fi

production_log="$(mktemp)"
trap 'rm -f -- "$production_log" 2>/dev/null || true' RETURN
property_error_source='file://'"/tmp/Bar.qml[309:-1]"
printf '%s\n' \
    'ERROR quickshell.ipc: Failed to start IPC server on path /tmp/ipc.sock' \
    "WARN scene: ${property_error_source}: Error: Cannot assign to non-existent property \"transparentForeground\"" \
    >"$production_log"
if ! runtime_log_is_environment_only "$production_log"; then
    pass "[isolated-framework] a production non-existent-property warning cannot be accepted as a backend-only skip"
else
    fail "[isolated-framework] production non-existent-property warning was classified as environment-only"
fi
rm -f -- "$production_log"
trap - RETURN

if grep -Fq 'id: barRoot' "$bar_file" &&
   grep -Fq 'model: Quickshell.screens' "$bar_file" &&
   grep -Fq 'BarPanel' "$bar_file" &&
   grep -Fq 'surfaceFormat.opaque: false' "$panel_file" &&
   grep -Fq 'function refreshTransparentForeground' "$bar_file" &&
   grep -Fq 'function beginBarMove' "$bar_file" &&
   grep -Fq 'function beginWidgetDrag' "$bar_file" &&
   grep -Fq 'onBarHiddenChanged' "$bar_file" &&
   grep -Fq 'visible: !remapGuard.remapping' "$panel_file" &&
   grep -Fq 'ScreenMoveRemap' "$panel_file" &&
   grep -Fq 'columns: root.vertical ? 1' "$ROOT/plugins/aurelia.tray/TrayBarWidget.qml" &&
   grep -Fq 'columns: root.vertical ? 1' "$ROOT/plugins/aurelia.tasklist/TasklistBarWidget.qml" &&
   grep -Fq 'visible: !root.vertical' "$ROOT/plugins/aurelia.weather/WeatherBarWidget.qml" &&
   grep -Fq 'function openCommandCenter()' "$ROOT/plugins/aurelia.bar/AureliaLogo.qml" &&
   grep -Fq 'logo_click_failed' "$ROOT/plugins/aurelia.bar/AureliaLogo.qml" &&
   grep -Fq 'action.mode === "object"' "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml" &&
   grep -Fq 'click_dispatched' "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml" &&
   grep -Fq 'WorkspaceActionModel.js' "$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml"; then
    pass "[static] production bar entry-point contract retains non-opaque rendering, gestures, drag ownership, and facade synchronization"
else
    fail "[static] production bar entry-point contract is incomplete after the warning repair"
fi

workspace_model_result="$(node - "$ROOT/plugins/aurelia.workspaces/WorkspaceActionModel.js" <<'NODE'
const assert = require('assert');
const model = require(process.argv[2]);
const liveWorkspace = { activate() {} };

assert.deepStrictEqual(model.actionFor(liveWorkspace, 2, true),
  {ok: true, mode: 'object', id: '2'});
assert.deepStrictEqual(model.actionFor(null, 3, true),
  {ok: true, mode: 'dispatch', id: '3', command: 'hl.dsp.focus({ workspace = "3" })'});
assert.deepStrictEqual(model.actionFor(null, 4, false),
  {ok: true, mode: 'dispatch', id: '4', command: 'workspace 4'});
assert.deepStrictEqual(model.actionFor(null, 0, false),
  {ok: false, reason: 'invalid-workspace'});
console.log('workspace action model ok');
NODE
)"
if [[ "$workspace_model_result" == *"workspace action model ok"* ]]; then
    pass "[isolated-node] workspace clicks choose live activation or a bounded empty-workspace dispatch and reject invalid IDs"
else
    fail "[isolated-node] workspace action decision model failed: $workspace_model_result"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] production bar entry-point and orientation fixtures (qs or timeout unavailable)"
    return 0
fi

production_root="$(mktemp -d)"
trap 'rm -rf -- "$production_root" 2>/dev/null || true' RETURN
mkdir -p "$production_root/runtime" "$production_root/config" "$production_root/state" "$production_root/cache"
production_result="$production_root/result.json"
production_log="$production_root/runtime.log"
production_status=0
: >"$production_result"
AURELIA_BAR_PRODUCTION_SOURCE="file://$bar_file" \
AURELIA_BAR_PRODUCTION_RESULT="$production_result" \
AURELIA_BAR_PRODUCTION_STATE="$production_root/state/aurelia/toggles/bar-off" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$production_root/runtime" XDG_CONFIG_HOME="$production_root/config" \
XDG_STATE_HOME="$production_root/state" XDG_CACHE_HOME="$production_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-parity/production.qml" >"$production_log" 2>&1 || production_status=$?

if [[ "$production_status" -eq 0 && -s "$production_result" ]] &&
   jq -e '.hostLoaded == true and .hostIsPanelWindow == false and
          .panelLoaded == true and .panelHasScreen == true and
          .panelNonOpaque == true and .panelHasHorizontalVerticalLoader == true' \
       "$production_result" >/dev/null &&
   runtime_log_is_environment_only "$production_log"; then
    pass "[isolated-runtime] the real Bar.qml entry point constructs a host plus mapped per-screen panel with no application diagnostics"
elif [[ -s "$production_result" ]] &&
     jq -e '.hostLoaded == true and .panelLoaded == false and .panelCount == 0' \
         "$production_result" >/dev/null &&
     grep -Eq 'No PanelWindow backend loaded|Failed to create wl_display|Could not load the Qt platform plugin' "$production_log" &&
     runtime_skip_if_environment_only "$production_log" "[isolated-runtime] production Bar.qml host loaded but the mapped PanelWindow backend is unavailable"; then
    :
elif grep -Eq 'No PanelWindow backend loaded|Failed to create wl_display|Could not load the Qt platform plugin' "$production_log" &&
     runtime_skip_if_environment_only "$production_log" "[isolated-runtime] production Bar.qml mapped-panel entry path is unavailable without a window backend"; then
    :
else
    details="$(tr '\n' ' ' <"$production_log")"
    if [[ -s "$production_result" ]]; then details="$details result=$(tr '\n' ' ' <"$production_result")"; fi
    fail "[isolated-runtime] production Bar.qml entry-point fixture failed (status=$production_status): $details"
fi
rm -rf -- "$production_root"
trap - RETURN

layout_root="$(mktemp -d)"
trap 'rm -rf -- "$layout_root" 2>/dev/null || true' RETURN
mkdir -p "$layout_root/runtime" "$layout_root/config" "$layout_root/state" "$layout_root/cache"
layout_result="$layout_root/result.json"
layout_log="$layout_root/runtime.log"
: >"$layout_result"
layout_status=0
AURELIA_BAR_LAYOUT_ROW_SOURCE="$ROOT/plugins/aurelia.bar/BarWidgetRow.qml" \
AURELIA_BAR_LAYOUT_WIDGET_SOURCE="$ROOT/tests/fixtures/bar-parity/widget.qml" \
AURELIA_BAR_LAYOUT_RESULT="$layout_result" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$layout_root/runtime" XDG_CONFIG_HOME="$layout_root/config" \
XDG_STATE_HOME="$layout_root/state" XDG_CACHE_HOME="$layout_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-parity/layout.qml" >"$layout_log" 2>&1 || layout_status=$?

if [[ "$layout_status" -eq 0 && -s "$layout_result" ]] &&
   jq -e '
       .horizontalInBounds == true and
       .verticalInBounds == true and
       .restoredInBounds == true and
       .verticalWidthsFit == true and
       .horizontalWidthsRestored == true
   ' "$layout_result" >/dev/null &&
   runtime_log_is_environment_only "$layout_log"; then
    pass "[isolated-runtime] real bar rows keep every widget inside the bar through horizontal/vertical/orientation restoration"
else
    details="$(tr '\n' ' ' <"$layout_log")"
    if [[ -s "$layout_result" ]]; then details="$details result=$(tr '\n' ' ' <"$layout_result")"; fi
    fail "[isolated-runtime] production bar orientation fixture failed (status=$layout_status): $details"
fi
rm -rf -- "$layout_root"
trap - RETURN
