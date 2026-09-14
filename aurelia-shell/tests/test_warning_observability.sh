#!/usr/bin/env bash

# T31 checks that actionable plugin/host failures remain diagnosable while
# preserving the T02A containment boundary.

set -Eeuo pipefail

section "Aurelia Warning Observability"

host_root="$ROOT/services/PluginHost.qml"
bar_root="$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml"
bluetooth_root="$ROOT/plugins/aurelia.bluetooth/BluetoothBarWidget.qml"
probe_root="$ROOT/plugins/aurelia.bluetooth/ProbeModel.js"

if [[ -f "$probe_root" ]] &&
   grep -Fq 'ProbeModel.succeeded' "$bluetooth_root" &&
   grep -Fq 'bluezProbeStderr' "$bluetooth_root" &&
   grep -Fq 'bluez_probe_unavailable' "$bluetooth_root" &&
   grep -Fq 'function status()' "$bluetooth_root"; then
    pass "[static] Bluetooth capability failures retain bounded state and diagnostics"
else
    fail "[static] Bluetooth probe diagnostics are incomplete"
fi

empty_catch_pattern='catch (e) '"{}"
if ! grep -Fq 'status === Loader.Error && !root.available' "$bar_root" &&
   ! grep -Fq "$empty_catch_pattern" "$host_root" &&
   grep -Fq 'loaderErrorDetail' "$bar_root" &&
   grep -Fq 'aurelia.plugin.resolve_id_failed' "$host_root"; then
    pass "[static] host and bar Loader failures are not hidden by the old silent gates"
else
    fail "[static] an actionable host/bar failure is still silently suppressed"
fi

if command -v node >/dev/null; then
    if node - "$probe_root" <<'NODE_PROBE'
const probe = require(process.argv[2]);
const actualOutput = [
  'NAME               TYPE   SIGNATURE  RESULT/VALUE  FLAGS',
  '.GetManagedObjects method -          a{oa{sa{sv}}} -',
  '.InterfacesAdded   signal oa{sa{sv}} -             -'
].join('\n');
if (!probe.hasObjectManagerMember(actualOutput)) process.exit(1);
if (!probe.succeeded(0, actualOutput)) process.exit(1);
if (probe.succeeded(1, actualOutput)) process.exit(1);
if (probe.succeeded(0, 'NAME TYPE SIGNATURE RESULT/VALUE FLAGS')) process.exit(1);
const detail = probe.failureDetail(5, '', 'org.bluez is unavailable');
if (!detail.includes('exit_code=5') || !detail.includes('org.bluez is unavailable')) process.exit(1);
NODE_PROBE
    then
        pass "[isolated-runtime] BlueZ probe accepts real busctl member output and rejects failed/empty probes"
    else
        fail "[isolated-runtime] BlueZ probe classification contract failed"
    fi
else
    skip "[isolated-runtime] Bluetooth probe model checks (node unavailable)"
fi

if grep -Fq 'widget_failure' "$ROOT/tests/test_plugin_survivability.sh" &&
   grep -Fq 'Loader.Error' "$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml"; then
    pass "[static] survivability and warning suites retain explicit failure evidence checks"
else
    fail "[static] failure evidence checks are missing from the regression suites"
fi
