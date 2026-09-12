#!/usr/bin/env bash

# Contract and isolated behavior tests for the Aurelia Bluetooth plugin.
# No live BlueZ, PipeWire, compositor, package manager, or systemd state is
# queried or changed by this suite.

set -Eeuo pipefail

plugin_root="$ROOT/plugins/aurelia.bluetooth"
model_file="$plugin_root/Model.js"
panel_file="$plugin_root/BluetoothPanel.qml"
bar_file="$plugin_root/BluetoothBarWidget.qml"
power_bin="$ROOT/bin/aurelia-bluetooth-power"
device_bin="$ROOT/bin/aurelia-bluetooth-device"
audio_bin="$ROOT/bin/aurelia-audio-output-set-default"

section "Bluetooth Plugin Contract"

if [[ -f "$plugin_root/manifest.json" &&
      -f "$bar_file" &&
      -f "$panel_file" &&
      -f "$plugin_root/BluetoothDeviceRow.qml" &&
      -f "$model_file" ]] &&
   jq -e '.schemaVersion == 1 and
          .id == "aurelia.bluetooth" and
          .name == "Bluetooth" and
          .icon == "bluetooth" and
          (.kinds == ["bar-widget"]) and
          .entryPoints.barWidget == "BluetoothBarWidget.qml" and
          .barWidget.defaultSection == "right" and
          .barWidget.allowMultiple == false' "$plugin_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$plugin_root" >/dev/null 2>&1; then
    pass "Bluetooth declares a validated first-party bar-widget plugin"
else
    fail "Bluetooth manifest or entry-point contract is incomplete"
fi

if grep -Fq 'import Quickshell.Bluetooth' "$panel_file" &&
   grep -Fq 'Bluetooth.defaultAdapter' "$panel_file" &&
   grep -Fq 'Bluetooth.devices' "$panel_file" &&
   grep -Fq 'Pipewire.nodes' "$panel_file" &&
   grep -Fq 'BluetoothDeviceRow' "$panel_file"; then
    pass "Bluetooth bar widget's popup consumes Quickshell BlueZ and PipeWire models"
else
    fail "Bluetooth bar-widget native model integration is incomplete"
fi

if grep -Fq 'target: "aurelia.bluetooth"' "$bar_file" &&
   grep -Fq 'function toggleBluetooth()' "$panel_file" &&
   grep -Fq 'root.adapter.enabled ? "off" : "on"' "$panel_file" &&
   grep -Fq 'root.powerBin' "$panel_file" &&
   ! grep -Fq 'adapter.enabled =' "$panel_file"; then
    pass "Bluetooth power toggles use the persistent helper without optimistic BlueZ mutation"
else
    fail "Bluetooth power toggle ownership or persistence boundary is incomplete"
fi

if jq -e '(.kinds == ["bar-widget"]) and ((.kinds | index("panel")) == null)' "$plugin_root/manifest.json" >/dev/null &&
   grep -Fq 'BluetoothBarWidget.qml' "$plugin_root/manifest.json" &&
   grep -Fq 'readonly property var bluetoothPopup' "$bar_file" &&
   grep -Fq 'implicitWidth: adapterAvailable ? (bar ? bar.barSize : 32) : 0' "$bar_file" &&
   grep -Fq 'visible: adapterAvailable' "$bar_file" &&
   grep -Fq 'target: "aurelia.bluetooth"' "$bar_file" &&
   ! grep -Fq 'IpcHandler' "$panel_file"; then
    pass "Bluetooth is exposed only as a bar widget with an internally owned popup"
else
    fail "Bluetooth is incorrectly exposed as a standalone panel"
fi

if grep -Fq 'owesDiscoveryStop = true' "$panel_file" &&
   grep -Fq 'running: !root.shown && root.owesDiscoveryStop' "$panel_file" &&
   grep -Fq 'root.adapter.discovering = false' "$panel_file" &&
   grep -Fq 'sibling.owesDiscoveryStop = true' "$panel_file" &&
   grep -Fq 'function releaseDiscoveryOnDestruction()' "$panel_file" &&
   grep -Fq 'Component.onDestruction' "$bar_file"; then
    pass "Bluetooth bar widget bounds discovery ownership and hands stop debt across popup instances"
else
    fail "Bluetooth discovery start/stop ownership contract is incomplete"
fi

if grep -Fq 'Model.deviceRow' "$panel_file" &&
   grep -Fq 'function deviceFor(row)' "$panel_file" &&
   grep -Fq 'function syncPendingActions()' "$panel_file" &&
   grep -Fq 'pendingTimeout' "$panel_file" &&
   grep -Fq 'function bluetoothAudioSink(device)' "$panel_file" &&
   grep -Fq 'Pipewire.preferredDefaultAudioSink' "$panel_file"; then
    pass "Bluetooth projects primitive rows and resolves live devices/audio sinks at action time"
else
    fail "Bluetooth row projection, pending state, or audio handoff is incomplete"
fi

if grep -Fq 'acceptedButtons: Qt.LeftButton | Qt.RightButton' "$bar_file" &&
   grep -Fq 'mouse.button === Qt.RightButton' "$bar_file" &&
   grep -Fq 'BluetoothPanel.qml' "$bar_file" &&
   grep -Fq 'barAnchorItem' "$bar_file" &&
   grep -Fq 'AureliaToolTip' "$bar_file"; then
    pass "Bluetooth bar affordance owns anchored left-click and radio-toggle right-click behavior"
else
    fail "Bluetooth bar affordance or popup ownership is incomplete"
fi

if grep -Fq 'SUPER + CTRL + B' "$plugin_root/keybindings.lua" &&
   grep -Fq 'aurelia.bluetooth' "$plugin_root/keybindings.lua" &&
   grep -Fq 'action_type = "plugin_ipc"' "$plugin_root/keybindings.lua"; then
    pass "Bluetooth provides the reference Super + Ctrl + B plugin IPC binding"
else
    fail "Bluetooth plugin keybinding is incomplete"
fi

if grep -Fq 'id: bluezProbe' "$bar_file" &&
   grep -Fq '"/usr/bin/busctl"' "$bar_file" &&
   grep -Fq 'active: root.bluezServiceAvailable' "$bar_file" &&
   grep -Fq 'function hasBluezService(output)' "$bar_file"; then
    pass "Bluetooth probes for BlueZ before constructing the native QML model"
else
    fail "Bluetooth does not gate its native QML model on bounded BlueZ availability"
fi

if grep -Fq 'aurelia.bluetooth' "$ROOT/config/bar-default.json" &&
   grep -Fq 'aurelia.bluetooth' "$ROOT/plugins/aurelia.bluetooth/manifest.json"; then
    pass "Bluetooth is present in the Aurelia default bar layout"
else
    fail "Bluetooth default bar integration is incomplete"
fi

if grep -Fxq 'bluez' "$ROOT/../packages/bluetooth.txt" 2>/dev/null &&
   grep -Fxq 'bluez-tools' "$ROOT/../packages/bluetooth.txt" 2>/dev/null &&
   ! grep -R -Fxq 'bluez-utils' "$ROOT/../packages"/*.txt 2>/dev/null; then
    pass "Bluetooth package ownership uses the Fedora BlueZ runtime and CLI tools manifest"
else
    fail "Bluetooth package manifest is missing valid BlueZ dependencies"
fi

if grep -Fq 'validate_bluetooth_environment()' "$ROOT/../modules/validation.sh" &&
   grep -Fq 'validate_bluetooth_environment || true' "$ROOT/../modules/validation.sh"; then
    pass "Profile-enabled Bluetooth commands and service are validated as non-login-critical"
else
    fail "Bluetooth capability validation is missing or not wired into workstation validation"
fi

section "Bluetooth Model"

if command -v node >/dev/null 2>&1; then
    if node - "$model_file" <<'NODE'
const model = require(process.argv[2])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
const equal = (actual, expected, message) => assert(actual === expected, `${message}: ${actual}`)
const deepEqual = (actual, expected, message) => equal(JSON.stringify(actual), JSON.stringify(expected), message)

equal(model.deviceLabel({ deviceName: 'MX Master 3S', name: 'Generic' }), 'MX Master 3S', 'device label prefers deviceName')
assert(model.isUuidLike('0000110b-0000-1000-8000-00805f9b34fb'), 'UUID-like labels are detected')
assert(model.isAddressLike('AA:BB:CC:DD:EE:FF'), 'address-like labels are detected')
equal(model.normalizedAddress('AA:BB_CC-dd-ee-ff'), 'aabbccddeeff', 'addresses normalize across separators')
assert(!model.hasHumanName({ name: 'AA:BB:CC:DD:EE:FF' }), 'address-only labels are hidden')
assert(model.hasHumanName({ deviceName: 'MX Master 3S' }), 'human labels remain visible')

const devices = [
  { name: 'Speaker', connected: false, paired: true, address: '2' },
  { name: 'Headphones', connected: true, address: '1' },
  { name: 'Keyboard', connected: false, address: '3' },
  { name: 'AA:BB:CC:DD:EE:FF', connected: true, address: '4' },
  { name: 'Mouse', connected: false, trusted: true, address: '5' }
]
const lists = model.deviceLists(devices)
deepEqual(lists.connected.map(model.deviceLabel), ['Headphones'], 'connected devices are grouped')
deepEqual(lists.known.map(model.deviceLabel), ['Mouse', 'Speaker'], 'known devices are grouped')
deepEqual(lists.discovered.map(model.deviceLabel), ['Keyboard'], 'discovered devices are grouped')
deepEqual(model.visibleSections(lists, true), ['connected', 'known', 'discovered'], 'scan exposes discovered section')
deepEqual(model.visibleSections(lists, false), ['connected', 'known'], 'closed scan hides discovered section')

deepEqual(
  model.deviceRow({ name: 'Deadbeef', address: '1', connected: false }),
  { address: '1', name: 'Deadbeef', deviceName: '', connected: false, state: -1, batteryAvailable: false, battery: 0, pairing: false },
  'device rows contain primitives only'
)
deepEqual(model.withPendingAction({ a: 'connecting' }, 'b', 'forgetting'), { a: 'connecting', b: 'forgetting' }, 'pending actions are immutable')
deepEqual(model.withPendingAction({ a: 'connecting' }, 'a', ''), {}, 'pending actions clear immutably')

const sink = {
  isSink: true,
  isStream: false,
  ready: true,
  name: 'bluez_output.AA_BB_CC_DD_EE_FF.1',
  properties: { 'device.product.name': 'JBL Go 3' }
}
assert(model.bluetoothSinkMatchesDevice(sink, { address: 'AA:BB:CC:DD:EE:FF', name: 'JBL Go 3' }), 'sinks match by address')
assert(model.bluetoothSinkMatchesDevice(
  { isSink: true, isStream: false, ready: true, name: 'alsa_output.usb', properties: { 'device.product.name': 'JBL Go 3' } },
  { address: '11:22:33:44:55:66', name: 'JBL Go 3' }
), 'sinks match by human label')
assert(!model.bluetoothSinkMatchesDevice(
  { isSink: false, isStream: false, ready: true, name: 'bluez_output.AA_BB_CC_DD_EE_FF.1', properties: {} },
  { address: 'AA:BB:CC:DD:EE:FF', name: 'JBL Go 3' }
), 'non-sinks are ignored')
NODE
    then
        pass "Bluetooth model groups devices, protects row lifetimes, and matches audio sinks"
    else
        fail "Bluetooth model runtime checks failed"
    fi
else
    printf '  SKIP Bluetooth model runtime checks (node unavailable)\n'
fi

section "Bluetooth Helpers"

for backend in "$power_bin" "$device_bin" "$audio_bin"; do
    if [[ -x "$backend" && "$(head -1 "$backend")" == "#!/bin/bash" ]] && bash -n "$backend"; then
        pass "backend is executable and syntactically valid: $(basename "$backend")"
    else
        fail "backend is missing or syntactically invalid: $backend"
    fi
done

bluetooth_tmp="$(mktemp -d)"
trap 'rm -rf -- "$bluetooth_tmp"' EXIT
mock_bin="$bluetooth_tmp/bin"
mkdir -p "$mock_bin"
export POWERED_FILE="$bluetooth_tmp/powered"
export BLUETOOTH_LOG="$bluetooth_tmp/log"

cat >"$mock_bin/bluetoothctl" <<'EOF_BLUETOOTHCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BLUETOOTH_LOG"
if [[ "$1" == "list" ]]; then
    for controller in ${MOCK_CONTROLLERS:-AA:BB:CC:DD:EE:FF}; do
        printf 'Controller %s mock\n' "$controller"
    done
elif [[ "$1" == "show" ]]; then
    state="$POWERED_FILE"
    if [[ -n "${2:-}" && -f "$POWERED_FILE.$2" ]]; then state="$POWERED_FILE.$2"; fi
    printf '\tPowered: %s\n' "$(<"$state")"
elif [[ "$1" == "power" && "${2:-}" == "on" ]]; then
    printf 'yes\n' >"$POWERED_FILE"
fi
EOF_BLUETOOTHCTL

cat >"$mock_bin/rfkill" <<'EOF_RFKILL'
#!/usr/bin/env bash
printf 'rfkill %s\n' "$*" >>"$BLUETOOTH_LOG"
if [[ "$1" == "unblock" && -z "${RFKILL_INERT:-}" ]]; then printf 'yes\n' >"$POWERED_FILE"; fi
if [[ "$1" == "block" ]]; then printf 'no\n' >"$POWERED_FILE"; fi
EOF_RFKILL

chmod 0755 "$mock_bin/bluetoothctl" "$mock_bin/rfkill"

bluetooth_run() {
    local powered="$1"
    shift
    printf '%s\n' "$powered" >"$POWERED_FILE"
    : >"$BLUETOOTH_LOG"
    PATH="$mock_bin:$ROOT/bin:$PATH" \
        AURELIA_BLUETOOTH_POWER_WAIT_SECONDS=0 \
        "$@"
}

bluetooth_run yes "$power_bin" off
if grep -Fxq 'rfkill block bluetooth' "$BLUETOOTH_LOG" && ! grep -Fq 'power off' "$BLUETOOTH_LOG"; then
    pass "Bluetooth off is an rfkill block and does not issue transient power off"
else
    fail "Bluetooth off helper did not preserve the reference rfkill behavior: $(cat "$BLUETOOTH_LOG")"
fi

bluetooth_run no "$power_bin" on
if grep -Fxq 'rfkill unblock bluetooth' "$BLUETOOTH_LOG" && ! grep -Fq 'power on' "$BLUETOOTH_LOG"; then
    pass "Bluetooth on lifts the persistent block when BlueZ follows AutoEnable"
else
    fail "Bluetooth on helper unexpectedly changed the BlueZ power path: $(cat "$BLUETOOTH_LOG")"
fi

bluetooth_run no "$power_bin" toggle
if grep -Fxq 'rfkill unblock bluetooth' "$BLUETOOTH_LOG"; then
    pass "Bluetooth toggle detects an unpowered controller and unblocks it"
else
    fail "Bluetooth toggle did not unblock an unpowered controller: $(cat "$BLUETOOTH_LOG")"
fi

printf 'yes\n' >"$POWERED_FILE.11:22:33:44:55:66"
MOCK_CONTROLLERS='AA:BB:CC:DD:EE:FF 11:22:33:44:55:66' bluetooth_run no "$power_bin" toggle
rm -f -- "$POWERED_FILE.11:22:33:44:55:66"
if grep -Fxq 'rfkill block bluetooth' "$BLUETOOTH_LOG"; then
    pass "Bluetooth power state considers secondary controllers"
else
    fail "Bluetooth power state ignored a secondary controller: $(cat "$BLUETOOTH_LOG")"
fi

bluetooth_run yes "$device_bin" connect AA:BB:CC:DD:EE:FF
if grep -Fxq 'connect AA:BB:CC:DD:EE:FF' "$BLUETOOTH_LOG" &&
   ! grep -Fq 'rfkill' "$BLUETOOTH_LOG"; then
    pass "Connecting an already powered device skips the power-on path"
else
    fail "Powered device connect helper behavior drifted: $(cat "$BLUETOOTH_LOG")"
fi

bluetooth_run no "$device_bin" connect AA:BB:CC:DD:EE:FF
if grep -Fxq 'rfkill unblock bluetooth' "$BLUETOOTH_LOG" &&
   grep -Fxq 'connect AA:BB:CC:DD:EE:FF' "$BLUETOOTH_LOG"; then
    pass "Connecting an unpowered device unblocks before connecting"
else
    fail "Unpowered device connect helper behavior drifted: $(cat "$BLUETOOTH_LOG")"
fi

if "$device_bin" connect invalid-address >/dev/null 2>&1; then
    fail "Bluetooth device helper accepted an invalid address"
else
    pass "Bluetooth device helper rejects invalid addresses before BlueZ calls"
fi

if "$power_bin" invalid >/dev/null 2>&1; then
    fail "Bluetooth power helper accepted an invalid operation"
else
    pass "Bluetooth power helper rejects invalid operations"
fi
