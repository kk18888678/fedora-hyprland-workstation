#!/usr/bin/env bash

# T39 Power popup contract. Tests use pure model inputs and a fake panel
# injected into the real bar widget; they never execute a power action or
# mutate UPower, power-profiles-daemon, shell.json, or the live bar.

set -Eeuo pipefail

section "Aurelia Power Plugin"

power_root="$ROOT/plugins/aurelia.power"
manifest_file="$power_root/manifest.json"
panel_file="$power_root/PowerPanel.qml"
widget_file="$power_root/PowerBarWidget.qml"
model_file="$power_root/Model.js"
runtime_file="$power_root/PowerRuntime.qml"
default_file="$ROOT/config/bar-default.json"
fixture_root="$ROOT/tests/fixtures/power-foundation"
panel_fixture_root="$ROOT/tests/fixtures/power-panel"

if [[ -f "$manifest_file" && -f "$panel_file" && -f "$widget_file" && -f "$model_file" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.power" and
       .name == "Power" and
       (.kinds == ["bar-widget"]) and
       .entryPoints.barWidget == "PowerBarWidget.qml" and
       .barWidget.displayName == "Power" and
       .barWidget.allowMultiple == false
   ' "$manifest_file" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$power_root" >/dev/null 2>&1; then
    pass "[static] Power retains its validated first-party bar-widget identity and entry point"
else
    fail "[static] Power manifest or preserved entry-point identity is incomplete"
fi

if grep -Fq 'import Quickshell.Services.UPower' "$panel_file" &&
   grep -Fq 'import "Model.js" as Model' "$panel_file" &&
   grep -Fq 'property var batteryInfo' "$panel_file" &&
   grep -Fq 'property var systemInfo' "$panel_file" &&
   grep -Fq 'property var profiles' "$panel_file" &&
   grep -Fq 'batteryPresent' "$panel_file" &&
   grep -Fq 'batteryFraction' "$panel_file" &&
   grep -Fq 'heroSection' "$panel_file" &&
   grep -Fq 'progressSection' "$panel_file" &&
   grep -Fq 'statsSection' "$panel_file" &&
   grep -Fq 'profilesSection' "$panel_file" &&
   grep -Fq 'AureliaKeyboardPanel' "$panel_file" &&
   ! grep -Fq 'cardHeight' "$panel_file"; then
    pass "[static] Power replaces the fixed action-only popup with UPower hero, progress, stats, and profile sections"
else
    fail "[static] Power reference information hierarchy or dynamic geometry is incomplete"
fi

if [[ -f "$runtime_file" ]] &&
   grep -Fq 'property QtObject runtime' "$panel_file" &&
   grep -Fq 'property var owner' "$runtime_file" &&
   ! grep -Eq '^[[:space:]]+(Process|Timer)[[:space:]]*\{' "$panel_file"; then
    pass "[static] Power keeps non-visual processes and timers outside AureliaKeyboardPanel contentItem"
else
    fail "[static] Power panel still risks inserting a non-visual child into contentItem"
fi

if grep -Fq 'showPercentage' "$panel_file" &&
   grep -Fq 'function togglePercentage' "$panel_file" &&
   grep -Fq 'function setProfile' "$panel_file" &&
   grep -Fq 'function selectProfileByDelta' "$panel_file" &&
   grep -Fq 'function requestAction' "$panel_file" &&
   grep -Fq 'function confirmPendingAction' "$panel_file" &&
   grep -Fq 'function cancelPendingAction' "$panel_file" &&
   grep -Fq 'loginctl' "$panel_file" &&
   grep -Fq 'hyprctl' "$panel_file" &&
   grep -Fq 'systemctl' "$panel_file"; then
    pass "[static] Power preserves structured actions, confirmation, profile selection, and percentage ownership"
else
    fail "[static] Power action or setting ownership regressed"
fi

if grep -Fq 'batteryIcon' "$widget_file" &&
   grep -Fq 'batteryPresent' "$widget_file" &&
   grep -Fq 'showPercentage' "$widget_file" &&
   grep -Fq 'Qt.RightButton' "$widget_file" &&
   grep -Fq 'function handleClick' "$widget_file" &&
   grep -Fq 'AureliaToolTip' "$widget_file" &&
   grep -Fq 'visible: root.batteryPresent' "$widget_file"; then
    pass "[static] Power bar shows battery state, percentage toggle, tooltip, and safe no-battery visibility"
else
    fail "[static] Power bar affordance lifecycle or no-battery boundary is incomplete"
fi

if jq -e '[.layout.left[], .layout.center[], .layout.right[]] | map(.id) | index("aurelia.power")' "$default_file" >/dev/null &&
   ! grep -Fq 'aurelia.power' "$ROOT/services/ShellConfig.qml"; then
    pass "[static] existing Power default placement remains data-owned and not hardcoded into the host"
else
    fail "[static] existing Power placement or host ownership changed"
fi

if grep -Fq 'function clampIndex' "$model_file" &&
   grep -Fq 'function selectProfileIndex' "$model_file" &&
   grep -Fq 'function parseKeyValue' "$model_file" &&
   grep -Fq 'function parseProfiles' "$model_file" &&
   grep -Fq 'function batteryFraction' "$model_file" &&
   grep -Fq 'function chargeThresholdActive' "$model_file" &&
   grep -Fq 'function batteryIcon' "$model_file" &&
   grep -Fq 'function modeLabel' "$model_file" &&
   grep -Fq 'function formatDuration' "$model_file"; then
    pass "[static] Power model owns bounded battery, threshold, profile, duration, and state semantics"
else
    fail "[static] Power pure model contract is incomplete"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$model_file" <<'NODE_POWER_MODEL'
const power = require(process.argv[2])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
const equal = (actual, expected, message) => assert(actual === expected, `${message}: ${actual}`)
const deepEqual = (actual, expected, message) => equal(JSON.stringify(actual), JSON.stringify(expected), message)
const states = { Charging: 1, Discharging: 2, FullyCharged: 3, PendingCharge: 4 }

equal(power.batteryFraction(null), 0, 'missing battery fraction')
equal(power.batteryIcon(null, false, states), '', 'missing battery icon')
equal(power.modeLabel(null, false, states), '', 'missing battery mode')
equal(power.formatDuration(0), '', 'zero duration')
equal(power.formatDuration(3661), '1h 1m', 'duration formatting')
equal(power.selectProfileIndex(99, 1, ['power-saver', 'balanced']), 1, 'profile upper bound')
equal(power.selectProfileIndex(-4, -1, ['power-saver', 'balanced']), 0, 'profile lower bound')
equal(power.selectProfileIndex(4, 1, []), 0, 'empty profile bounds')

const charging = { isPresent: true, percentage: 0.55, state: states.Charging, changeRate: 10, timeToFull: 1200 }
const holding = { isPresent: true, percentage: 0.80, state: states.Charging, changeRate: 0.1, timeToFull: 0 }
const pending = { isPresent: true, percentage: 0.80, state: states.PendingCharge }
const full = { isPresent: true, percentage: 0.95, state: states.FullyCharged }
const discharging = { isPresent: true, percentage: 0.42, state: states.Discharging }

equal(power.batteryFraction(charging), 0.55, 'battery fraction')
assert(!power.chargeThresholdActive(charging, false, states), 'ordinary charging is not holding')
assert(power.chargeThresholdActive(holding, false, states), 'slow charging is holding')
assert(power.chargeThresholdActive(pending, false, states), 'pending charge is holding')
assert(power.chargeThresholdActive(full, false, states), 'partial fully charged is holding')
assert(!power.chargeThresholdActive(discharging, true, states), 'discharging is not holding')
assert(power.batteryIcon(charging, false, states) !== '', 'charging icon')
assert(power.batteryIcon(discharging, true, states) !== '', 'discharging icon')
equal(power.modeLabel(holding, false, states), 'Threshold', 'threshold mode')
equal(power.modeLabel(discharging, true, states), 'On battery', 'battery mode')
equal(power.modeLabel({ isPresent: true, percentage: 1, state: states.FullyCharged }, false, states), 'Fully charged', 'full mode')

const parsed = power.parseProfiles('power-saver\t0\nbalanced\t1\nperformance\t0\n', 0)
assert(JSON.stringify(parsed.profiles) === JSON.stringify(['power-saver', 'balanced', 'performance']), 'profile list')
equal(parsed.activeProfile, 'balanced', 'active profile')
equal(parsed.profileIndex, 0, 'profile index')
const malformed = power.parseProfiles('garbage\n* performance:\n  Driver: test\n', 99)
assert(JSON.stringify(malformed.profiles) === JSON.stringify(['performance']), 'human profile parsing')
equal(malformed.activeProfile, 'performance', 'human active profile')
deepEqual(power.parseKeyValue('percentage\t55%\nstate\tcharging\n'), {percentage: '55%', state: 'charging'}, 'key/value parsing')
NODE_POWER_MODEL
    then
        pass "[isolated-runtime] Power model covers missing, charging, holding, full, discharging, malformed-profile, duration, and bounds cases"
    else
        fail "[isolated-runtime] Power model state/profile matrix failed"
    fi
else
    skip "[isolated-runtime] Power model matrix (node unavailable)"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] Power bar widget fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
result_file="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache"

AURELIA_POWER_FOUNDATION_RESULT="$result_file" \
AURELIA_POWER_FOUNDATION_SOURCE="file://$widget_file" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?

unexpected_diagnostics="$(grep -E 'WARN|ERROR|FATAL|TypeError|ReferenceError|QML Error|Segmentation fault|Cannot assign' "$runtime_log" | \
    grep -Ev 'ERROR quickshell\.ipc: Failed to start IPC server on path |Type AureliaKeyboardPanel unavailable|No PanelWindow backend loaded|\[POWER\] panel_load_failed|Failed to connect to UPower|UPower.*unavailable|Could not connect to UPower|Signal QQmlEngine::quit\(\) emitted' || true)"

backend_diagnostic=0
if grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|Type AureliaKeyboardPanel unavailable|No PanelWindow backend loaded|Failed to connect to UPower|Could not connect to UPower|Signal QQmlEngine::quit\(\) emitted|Operation not permitted' "$runtime_log"; then
    backend_diagnostic=1
fi

if [[ ("$runtime_status" -eq 0 || ("$runtime_status" -eq 124 && "$backend_diagnostic" -eq 1)) ]] && [[ -s "$result_file" ]] &&
   [[ -z "$unexpected_diagnostics" ]] &&
   jq -e '.widgetLoaded == true and .initialVisible == true and
          .shownAfterOpen == true and .percentageAfterRight == true and
          .shownAfterClose == false and .hiddenWithoutBattery == true and
          .actionFailureDidNotEscape == true' "$result_file" >/dev/null; then
    pass "[isolated-runtime] real Power bar widget preserves open/close, percentage toggle, no-battery hiding, and failure isolation"
elif [[ "$backend_diagnostic" -eq 1 ]] &&
     runtime_skip_if_environment_only "$runtime_log" "[isolated-runtime] Power fixture cannot create a disposable window or UPower backend"; then
    :
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_file" ]]; then details="$details result=$(tr '\n' ' ' <"$result_file")"; fi
    fail "[isolated-runtime] Power widget fixture failed (status=$runtime_status): $details"
fi

panel_runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$panel_runtime_root" 2>/dev/null || true' RETURN
panel_result="$panel_runtime_root/result.json"
panel_log="$panel_runtime_root/runtime.log"
panel_status=0
mkdir -p -- "$panel_runtime_root/runtime" "$panel_runtime_root/state" \
    "$panel_runtime_root/config" "$panel_runtime_root/cache"
AURELIA_POWER_PANEL_RESULT="$panel_result" \
AURELIA_POWER_PANEL_SOURCE="file://$panel_file" \
AURELIA_POWER_RUNTIME_SOURCE="file://$runtime_file" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$panel_runtime_root/runtime" \
XDG_STATE_HOME="$panel_runtime_root/state" \
XDG_CONFIG_HOME="$panel_runtime_root/config" \
XDG_CACHE_HOME="$panel_runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$panel_fixture_root/shell.qml" --no-color >"$panel_log" 2>&1 || panel_status=$?

if [[ "$panel_status" -eq 0 ]] && [[ -s "$panel_result" ]] &&
   jq -e '.loaded == true and .runtimeAvailable == true and .entryPointConstructed == true' \
       "$panel_result" >/dev/null; then
    pass "[isolated-runtime] real PowerPanel entry point constructs without contentItem type errors"
elif [[ -s "$panel_result" ]] &&
     jq -e '.runtimeLoaded == true and .runtimeAvailable == true' "$panel_result" >/dev/null 2>&1 &&
     grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|No PanelWindow backend loaded' "$panel_log" &&
     runtime_skip_if_environment_only "$panel_log" "[isolated-runtime] PowerPanel fixture cannot create a disposable window backend"; then
    :
else
    details="$(tail -n 48 "$panel_log" 2>/dev/null || true)"
    if [[ -s "$panel_result" ]]; then details="$details result=$(tr '\n' ' ' <"$panel_result")"; fi
    fail "[isolated-runtime] PowerPanel entry-point fixture failed (status=$panel_status): $details"
fi
