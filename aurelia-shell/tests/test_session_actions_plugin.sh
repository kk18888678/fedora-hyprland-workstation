#!/usr/bin/env bash

# T47 restoration contract. Session actions are intentionally separate from
# the battery-gated aurelia.power plugin and never execute destructive commands
# in disposable fixtures.

set -Eeuo pipefail

section "Aurelia Session Actions Plugin"

session_root="$ROOT/plugins/aurelia.session-actions"
manifest_file="$session_root/manifest.json"
model_file="$session_root/Model.js"
widget_file="$session_root/SessionActionsBarWidget.qml"
panel_file="$session_root/SessionActionsPanel.qml"
runtime_file="$session_root/SessionActionsRuntime.qml"
default_file="$ROOT/config/bar-default.json"
fixture_root="$ROOT/tests/fixtures/session-actions"

if [[ -f "$manifest_file" && -f "$widget_file" && -f "$panel_file" && -f "$runtime_file" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.session-actions" and
       .name == "Session Actions" and
       (.kinds == ["bar-widget"]) and
       .entryPoints.barWidget == "SessionActionsBarWidget.qml" and
       .barWidget.displayName == "Session Actions" and
       .barWidget.defaultSection == "right" and
       .barWidget.allowMultiple == false
   ' "$manifest_file" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$session_root" >/dev/null 2>&1; then
    pass "[static] Session Actions has a validated distinct first-party bar-widget identity"
else
    fail "[static] Session Actions manifest or entry-point contract is incomplete"
fi

if grep -Fq 'property QtObject runtime' "$panel_file" &&
   grep -Fq 'property var owner' "$runtime_file" &&
   ! grep -Eq '^[[:space:]]+(Process|Timer)[[:space:]]*\{' "$panel_file" &&
   ! grep -Fq 'Quickshell.Services.UPower' "$panel_file" &&
   grep -Fq 'Model.actionRows()' "$panel_file" &&
   grep -Fq 'GridLayout' "$panel_file" &&
   grep -Fq 'Layout.preferredHeight: 40' "$panel_file"; then
    pass "[static] Session Actions owns the former five rows without battery coupling or contentItem Process children in a compact grid"
else
    fail "[static] Session Actions panel structure or isolation boundary is incomplete"
fi

if grep -Fq 'visible: true' "$widget_file" &&
   grep -Fq 'system-shutdown' "$widget_file" &&
   grep -Fq 'function handleClick' "$widget_file" &&
   grep -Fq 'AureliaToolTip' "$widget_file" &&
   ! grep -Fq 'batteryPresent' "$widget_file"; then
    pass "[static] Session Actions remains visible independently of battery hardware with a theme-aware affordance"
else
    fail "[static] Session Actions bar affordance is battery-coupled or incomplete"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$model_file" <<'NODE_SESSION_MODEL'
const model = require(process.argv[2])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
const equal = (actual, expected, message) => {
  assert(JSON.stringify(actual) === JSON.stringify(expected), `${message}: ${JSON.stringify(actual)}`)
}
const rows = model.actionRows()
equal(rows.map(row => row.id), ['lock', 'logout', 'suspend', 'reboot', 'shutdown'], 'all former actions remain ordered')
equal(rows.map(row => row.label), ['Lock', 'Log out', 'Suspend', 'Restart', 'Power off'], 'action labels remain deterministic')
equal(model.commandFor('lock'), ['/usr/bin/loginctl', 'lock-session'], 'lock argv')
equal(model.commandFor('logout'), ['/usr/bin/hyprctl', 'dispatch', 'exit'], 'logout argv')
equal(model.commandFor('suspend'), ['/usr/bin/systemctl', 'suspend'], 'suspend argv')
equal(model.commandFor('reboot'), ['/usr/bin/systemctl', 'reboot'], 'reboot argv')
equal(model.commandFor('shutdown'), ['/usr/bin/systemctl', 'poweroff'], 'shutdown argv')
assert(!model.requiresConfirmation('lock'), 'lock is not destructive confirmation')
assert(!model.requiresConfirmation('logout'), 'logout is not destructive confirmation')
assert(!model.requiresConfirmation('suspend'), 'suspend is not destructive confirmation')
assert(model.requiresConfirmation('reboot'), 'reboot requires confirmation')
assert(model.requiresConfirmation('shutdown'), 'shutdown requires confirmation')
assert(!model.isKnownAction('unknown'), 'unknown action rejected')
equal(model.commandFor('unknown'), [], 'unknown action has no command')
equal(model.confirmationRows('shutdown').map(row => row.id), ['confirm', 'cancel'], 'shutdown confirmation rows')
equal(model.confirmationRows('lock'), [], 'non-destructive action has no confirmation rows')
NODE_SESSION_MODEL
    then
        pass "[isolated-runtime] pure model covers all five session actions, exact argv, confirmation, and invalid input"
    else
        fail "[isolated-runtime] Session Actions model contract failed"
    fi
else
    skip "[isolated-runtime] Session Actions model matrix (node unavailable)"
fi

if jq -e '
       [.layout.right[].id] == [
         "aurelia.tray", "aurelia.network", "aurelia.audio",
         "aurelia.bluetooth", "aurelia.monitor", "aurelia.screenshot",
         "aurelia.session-actions", "aurelia.power"
       ]
   ' "$default_file" >/dev/null; then
    pass "[static] Session Actions is added at the former action affordance location while Power remains present"
else
    fail "[static] canonical default bar does not preserve Power and add Session Actions"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] Session Actions QuickShell fixtures (qs or timeout unavailable)"
    return 0
fi

session_runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$session_runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$session_runtime_root/runtime" "$session_runtime_root/state" \
    "$session_runtime_root/config" "$session_runtime_root/cache"

widget_result="$session_runtime_root/widget-result.json"
widget_log="$session_runtime_root/widget.log"
widget_status=0
AURELIA_SESSION_WIDGET_RESULT="$widget_result" \
AURELIA_SESSION_WIDGET_SOURCE="file://$widget_file" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$session_runtime_root/runtime" \
XDG_STATE_HOME="$session_runtime_root/state" \
XDG_CONFIG_HOME="$session_runtime_root/config" \
XDG_CACHE_HOME="$session_runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/widget.qml" --no-color >"$widget_log" 2>&1 || widget_status=$?
widget_completed=0
if [[ "$widget_status" -eq 0 ]] ||
   [[ "$widget_status" -eq 124 && -f "$widget_log" ]] &&
   grep -Fq 'Signal QQmlEngine::quit() emitted' "$widget_log"; then
    widget_completed=1
fi
if [[ "$widget_completed" -eq 1 ]] &&
   [[ -s "$widget_result" ]] &&
   runtime_log_is_environment_only "$widget_log" &&
   jq -e '.loaded == true and .initialVisible == true and .initialWidth > 0 and
          .openResult == "ok" and .shownAfterOpen == true and
          .closeResult == "ok" and .shownAfterClose == false and
          .actionReady == true' "$widget_result" >/dev/null; then
    pass "[isolated-runtime] real Session Actions bar widget remains visible and opens/closes without battery hardware"
else
    details="$(tail -n 32 "$widget_log" 2>/dev/null || true)"
    if [[ -s "$widget_result" ]]; then details="$details result=$(tr '\n' ' ' <"$widget_result")"; fi
    fail "[isolated-runtime] Session Actions bar widget fixture failed (status=$widget_status): $details"
fi

runtime_result="$session_runtime_root/runtime-result.json"
runtime_log="$session_runtime_root/runtime.log"
runtime_status=0
AURELIA_SESSION_RUNTIME_RESULT="$runtime_result" \
AURELIA_SESSION_RUNTIME_SOURCE="file://$runtime_file" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$session_runtime_root/runtime-runtime" \
XDG_STATE_HOME="$session_runtime_root/state-runtime" \
XDG_CONFIG_HOME="$session_runtime_root/config-runtime" \
XDG_CACHE_HOME="$session_runtime_root/cache-runtime" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/runtime.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?
runtime_completed=0
if [[ "$runtime_status" -eq 0 ]] ||
   [[ "$runtime_status" -eq 124 && -f "$runtime_log" ]] &&
   grep -Fq 'Signal QQmlEngine::quit() emitted' "$runtime_log"; then
    runtime_completed=1
fi
if [[ "$runtime_completed" -eq 1 ]] &&
   [[ -s "$runtime_result" ]] &&
   runtime_log_is_environment_only "$runtime_log" '\[SESSION-ACTIONS\] action_failed kind=shutdown' &&
   jq -e '.loaded == true and .success == "ok" and .failure == "error" and
          .invalid == "invalid" and .actionError == "Session action failed." and
          (.calls | length) == 2 and .calls[0].argv == ["/usr/bin/loginctl", "lock-session"] and
          .calls[1].argv == ["/usr/bin/systemctl", "poweroff"] and
          .processRunning == false' "$runtime_result" >/dev/null &&
   grep -Fq '[SESSION-ACTIONS] action_failed kind=shutdown' "$runtime_log"; then
    pass "[isolated-runtime] session runtime records structured argv, contains executor failure, and launches no production command"
else
    details="$(tail -n 32 "$runtime_log" 2>/dev/null || true)"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] Session Actions runtime fixture failed (status=$runtime_status): $details"
fi

panel_result="$session_runtime_root/panel-result.json"
panel_log="$session_runtime_root/panel.log"
panel_status=0
mkdir -p -- "$session_runtime_root/panel-runtime" "$session_runtime_root/panel-state" \
    "$session_runtime_root/panel-config" "$session_runtime_root/panel-cache"
AURELIA_SESSION_PANEL_RESULT="$panel_result" \
AURELIA_SESSION_PANEL_SOURCE="file://$panel_file" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$session_runtime_root/panel-runtime" \
XDG_STATE_HOME="$session_runtime_root/panel-state" \
XDG_CONFIG_HOME="$session_runtime_root/panel-config" \
XDG_CACHE_HOME="$session_runtime_root/panel-cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/panel.qml" --no-color >"$panel_log" 2>&1 || panel_status=$?
if [[ "$panel_status" -eq 0 ]] && [[ -s "$panel_result" ]] &&
   runtime_log_is_environment_only "$panel_log" &&
   jq -e '.loaded == true and .openResult == "ok" and
          .confirmationResult == "confirm" and .pendingAction == "shutdown" and
          .cancelResult == "ok" and .lockResult == "ok" and
          .invalidResult == "invalid" and (.calls | length) == 1 and
          .calls[0].argv == ["/usr/bin/loginctl", "lock-session"] and
          .actionRunning == false' "$panel_result" >/dev/null; then
    pass "[isolated-runtime] real Session Actions panel covers open, confirmation, cancellation, action routing, and invalid input"
elif [[ -s "$panel_result" ]] &&
     grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|No PanelWindow backend loaded' "$panel_log" &&
     runtime_skip_if_environment_only "$panel_log" "[isolated-runtime] Session Actions panel cannot create a disposable window backend"; then
    :
else
    details="$(tail -n 40 "$panel_log" 2>/dev/null || true)"
    if [[ -s "$panel_result" ]]; then details="$details result=$(tr '\n' ' ' <"$panel_result")"; fi
    fail "[isolated-runtime] Session Actions panel fixture failed (status=$panel_status): $details"
fi
