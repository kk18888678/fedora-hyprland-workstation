#!/usr/bin/env bash

# Contract and isolated model tests for the Aurelia Network plugins.
# No live NetworkManager mutation, connection attempt, DNS change, or speed
# test is performed here.

set -Eeuo pipefail

network_root="$ROOT/plugins/aurelia.network"
wifiqr_root="$ROOT/plugins/aurelia.wifiqr"
speed_root="$ROOT/plugins/aurelia.speedtest"

section "Network Plugin Contract"

if [[ -f "$network_root/manifest.json" &&
      -f "$network_root/NetworkBarWidget.qml" &&
      -f "$network_root/NetworkPanel.qml" &&
      -f "$network_root/NetworkRow.qml" &&
      -f "$network_root/Model.js" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.network" and
       .name == "Network" and
       (.kinds == ["bar-widget"]) and
       .entryPoints.barWidget == "NetworkBarWidget.qml" and
       .barWidget.defaultSection == "right"
   ' "$network_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$network_root" >/dev/null 2>&1; then
    pass "Network declares a validated first-party bar-widget plugin"
else
    fail "Network manifest or bar-widget entry point is incomplete"
fi

if grep -Fq 'import Quickshell.Io' "$network_root/NetworkBarWidget.qml" &&
   grep -Fq 'Quickshell.Networking' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'AureliaKeyboardPanel' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'function setScannerEnabled' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'if (scannerDevice) scannerDevice.scannerEnabled = false' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'function disconnectRow' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'function connectEnterprise' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'stdinEnabled: true' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'Model.wifiRow(network)' "$network_root/NetworkPanel.qml" &&
   ! grep -Eq 'passwordText.*command|command:.*passwordText' "$network_root/NetworkPanel.qml"; then
    pass "Network keeps NetworkManager state, scanner ownership, primitive rows, and stdin-only enterprise secrets separated"
else
    fail "Network panel safety or action-routing contract is incomplete"
fi

if grep -Fq 'AureliaIcon {' "$network_root/NetworkBarWidget.qml" &&
   grep -Fq 'glyph: root.networkPanel && root.networkPanel.icon' "$network_root/NetworkBarWidget.qml" &&
   grep -Fq 'tint: root.networkPanel && root.networkPanel.restricted' "$network_root/NetworkBarWidget.qml" &&
   grep -Fq 'settings.showLabel === true' "$network_root/NetworkBarWidget.qml" &&
   grep -Fq 'root.networkPanel.barLabel' "$network_root/NetworkBarWidget.qml"; then
    pass "Network bar affordance uses a compact theme-tinted icon and wired/Wi-Fi label"
else
    fail "Network bar icon and connection-label rendering is incomplete"
fi

if grep -Fq 'popupHeight: Math.min(560' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'column.implicitHeight + contentPadding * 2' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'popupWidth: 380' "$network_root/NetworkPanel.qml"; then
    pass "Network popup fits visible content with bounded compact geometry"
else
    fail "Network popup still uses fixed oversized geometry"
fi

if [[ -f "$network_root/NetworkDetails.qml" ]] &&
   grep -Fq 'Downloaded' "$network_root/NetworkDetails.qml" &&
   grep -Fq 'Uploaded' "$network_root/NetworkDetails.qml" &&
   grep -Fq 'copyToClipboard' "$network_root/NetworkDetails.qml" &&
   grep -Fq 'connectionPhrases' "$network_root/NetworkPanel.qml"; then
    pass "Network details include Omarchy-style totals, copy actions, and connection status phrases"
else
    fail "Network details parity is incomplete"
fi

if [[ -f "$network_root/NetworkDnsControls.qml" ]] &&
   grep -Fq 'pendingDnsProvider' "$network_root/NetworkDnsControls.qml" &&
   grep -Fq 'dnsError' "$network_root/NetworkDnsControls.qml" &&
   grep -Fq 'ToolTip.text' "$network_root/NetworkDnsControls.qml" &&
   grep -Fq 'write_resolved_dns' "$ROOT/bin/aurelia-network-dns" &&
   grep -Fq 'RESOLVED_DNS_CONF=/etc/systemd/resolved.conf.d/20-aurelia-dns.conf' "$ROOT/bin/aurelia-network-dns" &&
   grep -Fq 'actionErrorStreamSeen' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'finishAction()' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'dnsServers' "$network_root/NetworkDnsControls.qml" &&
   grep -Fq 'current_dns_servers' "$ROOT/bin/aurelia-network-dns" &&
   grep -Fq '"--servers"' "$ROOT/bin/aurelia-network-dns" &&
   grep -Fq 'code === 124' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'pendingDnsProvider = provider' "$network_root/NetworkPanel.qml"; then
    pass "DNS provider controls expose reference-style status/tooltips and preserve resolved.conf with a managed drop-in"
else
    fail "DNS provider wiring or safe resolved drop-in handling is incomplete"
fi

if grep -Fq 'startPendingDns()' "$network_root/NetworkPanel.qml" &&
   grep -Fq 'Match Omarchy: the helper owns authorization.' "$network_root/NetworkPanel.qml" &&
   ! grep -Fq 'dnsAuthProc' "$network_root/NetworkPanel.qml"; then
    pass "DNS actions use the Omarchy direct-helper path without a preflight polkit delay"
else
    fail "DNS actions still depend on the obsolete preflight polkit process"
fi

if [[ -f "$wifiqr_root/manifest.json" && -f "$wifiqr_root/WifiQrPlugin.qml" && -f "$wifiqr_root/WifiQrPanel.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.wifiqr" and (.kinds == ["panel"]) and .entryPoints.panel == "WifiQrPlugin.qml"' "$wifiqr_root/manifest.json" >/dev/null &&
   grep -Fq 'Model.parseQrOutput' "$wifiqr_root/WifiQrPanel.qml" &&
   grep -Fq 'passwordExpectedStop' "$wifiqr_root/WifiQrPanel.qml"; then
    pass "Wi-Fi QR sharing is a separate cancellable panel plugin"
else
    fail "Wi-Fi QR plugin contract is incomplete"
fi

if [[ -f "$speed_root/manifest.json" && -f "$speed_root/SpeedtestPlugin.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.speedtest" and (.kinds == ["panel"])' "$speed_root/manifest.json" >/dev/null &&
   grep -Fq 'interval: 5000' "$speed_root/SpeedtestPlugin.qml" &&
   grep -Fq 'expectedStop' "$speed_root/SpeedtestPlugin.qml"; then
    pass "Speed test is a separate bounded, cancellable panel plugin"
else
    fail "Speed-test plugin contract is incomplete"
fi

if grep -Fq 'aurelia.network' "$ROOT/config/bar-default.json" &&
   grep -Fq 'aurelia.network' "$ROOT/plugins/aurelia.network/manifest.json" &&
   grep -Fq 'SUPER + CTRL + W' "$network_root/keybindings.lua" &&
   grep -Fq 'aurelia.network' "$network_root/keybindings.lua" &&
   grep -Fxq 'iw' "$ROOT/../packages/base.txt" &&
   grep -Fxq 'qrencode' "$ROOT/../packages/base.txt"; then
    pass "Network is present in the default Aurelia bar, shortcut registry, and host capability manifest"
else
    fail "Network default-bar, shortcut, or package integration is incomplete"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$network_root/Model.js" "$wifiqr_root/Model.js" <<'NODE'
const network = require(process.argv[2])
const wifiqr = require(process.argv[3])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
const tab = String.fromCharCode(9)
const newline = String.fromCharCode(10)
assert(network.parseNetworkStatus('wifi' + tab + 'Cafe WiFi' + tab + '78' + tab + '5200' + newline).label === 'Cafe WiFi', 'status parser')
assert(network.connectionIcon('wifi', 80) === network.wifiIconFor(80), 'wifi icon')
assert(network.formatHeaderSpeed('2500') === '2.5gbit', 'header speed')
assert(network.formatHeaderFreq('6455.0') === '6ghz', 'header frequency')
assert(network.decodeIwSsid('Cafe\\xe2\\x80\\x99') === 'Cafe’', 'SSID decoding')
const seeded = network.throughputState({ prevIface: '', prevSampleTime: 0 }, { iface: 'wlan0', rx_bytes: '100', tx_bytes: '50' }, 10)
const delta = network.throughputState(seeded, { iface: 'wlan0', rx_bytes: '300', tx_bytes: '90' }, 12)
assert(delta.downloadRate === 100 && delta.uploadRate === 20, 'throughput')
const rows = network.sortWifiRows([
  { ssid: 'Open', connected: false, known: false, signal: 95 },
  { ssid: 'Known', connected: false, known: true, signal: 10 },
  { ssid: 'Connected', connected: true, known: true, signal: 20 }
])
assert(rows.map(row => row.ssid).join(',') === 'Connected,Known,Open', 'row sorting')
assert(network.requiresCredentials(11, 10, 9) && !network.requiresCredentials(9, 10, 9), 'credential policy')
assert(network.parseBandStatus('band' + tab + '5' + newline + 'available' + tab + '2.4 5 6' + newline + 'selected' + tab + 'auto' + newline).available.join(',') === '2.4,5,6', 'band parser')
assert(wifiqr.parseQrOutput('meta' + tab + 'wlan0' + tab + 'WPA' + tab + 'Cafe' + newline + '010' + newline + '111' + newline + '010' + newline).matrix.size === 3, 'QR parser')
assert(wifiqr.parseQrOutput('010' + newline + '1x1' + newline + '010' + newline).matrix.size === 0, 'QR rejects malformed matrix')
NODE
    then
        pass "Network and QR models preserve the reference parsing, sorting, and safety invariants"
    else
        fail "Network model runtime checks failed"
    fi
else
    pass "SKIP Network model runtime checks (node unavailable)"
fi

for backend in \
    "$ROOT/bin/aurelia-network-status" \
    "$ROOT/bin/aurelia-network-band" \
    "$ROOT/bin/aurelia-network-dns" \
    "$ROOT/bin/aurelia-network-password" \
    "$ROOT/bin/aurelia-network-qr" \
    "$ROOT/bin/aurelia-network-speedtest" \
    "$ROOT/bin/aurelia-network-dns-terminal"; do
    if [[ -x "$backend" ]] && bash -n "$backend"; then
        pass "network backend is executable and syntactically valid: $(basename "$backend")"
    else
        fail "network backend is missing or syntactically invalid: $backend"
    fi
done

dns_terminal_fixture="$(mktemp -d)"
trap 'rm -rf -- "$dns_terminal_fixture"' RETURN
cat >"$dns_terminal_fixture/kitty" <<'EOF_KITTY_DNS'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$AURELIA_NETWORK_TERMINAL_CALLS"
EOF_KITTY_DNS
chmod 0755 "$dns_terminal_fixture/kitty"
if PATH="$dns_terminal_fixture:$PATH" \
   AURELIA_TERMINAL=kitty \
   AURELIA_NETWORK_TERMINAL_CALLS="$dns_terminal_fixture/call" \
   "$ROOT/bin/aurelia-network-dns-terminal" Cloudflare >/dev/null 2>&1 &&
   grep -Fq -- "--title Aurelia DNS -- /bin/bash $ROOT/bin/aurelia-network-dns Cloudflare" "$dns_terminal_fixture/call"; then
    pass "DNS fallback launches the real helper in a supported terminal with structured provider arguments"
else
    fail "DNS terminal fallback did not produce the expected terminal argv"
fi
rm -rf -- "$dns_terminal_fixture"
trap - RETURN

if command -v bwrap >/dev/null 2>&1; then
    dns_fixture="$(mktemp -d)"
    trap 'rm -rf -- "$dns_fixture"' RETURN
    mkdir -p "$dns_fixture/etc/NetworkManager/conf.d" \
        "$dns_fixture/etc/systemd/resolved.conf.d" \
        "$dns_fixture/usr-local-bin"
    printf '%s\n' '# preserved base configuration' 'DNS=9.9.9.9' >"$dns_fixture/etc/systemd/resolved.conf"

    cat >"$dns_fixture/usr-local-bin/nmcli" <<'EOF_NMCLI_DNS'
#!/usr/bin/env bash
case "$*" in
    *"UUID,TYPE connection show"*)
        printf '%s\n' 'wifi-uuid:802-11-wireless' 'ether-uuid:802-3-ethernet' 'vpn-uuid:vpn'
        ;;
    *"DEVICE,TYPE,STATE device status"*)
        printf '%s\n' 'wlan0:wifi:connected' 'eth0:ethernet:disconnected'
        ;;
    *"connection modify"*|*"device reapply"*|*"general reload"*)
        printf '%s\n' "$*" >>"$AURELIA_NETWORK_DNS_TEST_LOG"
        ;;
esac
EOF_NMCLI_DNS
    cat >"$dns_fixture/usr-local-bin/systemctl" <<'EOF_SYSTEMCTL_DNS'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" ]]; then exit 0; fi
printf '%s\n' "$*" >>"$AURELIA_NETWORK_DNS_TEST_LOG"
EOF_SYSTEMCTL_DNS
    chmod 0755 "$dns_fixture/usr-local-bin/nmcli" "$dns_fixture/usr-local-bin/systemctl"

    dns_fixture_run() {
        local provider="$1"
        AURELIA_NETWORK_DNS_TEST_LOG="$dns_fixture/calls.log" \
            bwrap --unshare-user --uid 0 --gid 0 \
                --ro-bind / / \
                --bind "$dns_fixture/etc/NetworkManager" /etc/NetworkManager \
                --bind "$dns_fixture/etc/systemd" /etc/systemd \
                --bind "$dns_fixture/usr-local-bin" /usr/local/bin \
                --bind "$dns_fixture" "$dns_fixture" \
                --dev /dev --proc /proc --dir /tmp \
                /bin/bash "$ROOT/bin/aurelia-network-dns" "$provider"
    }

    dns_fixture_ok=1
    dns_fixture_output="$dns_fixture/output.log"
    if ! dns_fixture_run Cloudflare >"$dns_fixture_output" 2>&1; then
        dns_fixture_ok=0
    elif ! grep -Fq 'servers=1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001' \
        "$dns_fixture/etc/NetworkManager/conf.d/20-aurelia-dns.conf" ||
        ! grep -Fq 'DNS=1.1.1.1#cloudflare-dns.com' \
        "$dns_fixture/etc/systemd/resolved.conf.d/20-aurelia-dns.conf" ||
        ! grep -Fq 'DNS=9.9.9.9' "$dns_fixture/etc/systemd/resolved.conf"; then
        dns_fixture_ok=0
    fi
    if (( dns_fixture_ok )); then
        pass "DNS helper applies Cloudflare through NetworkManager and an atomic resolved drop-in without overwriting base config"
    else
        if grep -Fq 'Creating new namespace failed' "$dns_fixture_output"; then
            pass "SKIP DNS helper write fixture (user namespaces unavailable)"
        else
            sed -n '1,80p' "$dns_fixture_output" >&2
            fail "DNS helper Cloudflare fixture did not converge the expected isolated state"
        fi
    fi

    if (( dns_fixture_ok )) && dns_fixture_run DHCP >/dev/null 2>&1 &&
       [[ ! -e "$dns_fixture/etc/NetworkManager/conf.d/20-aurelia-dns.conf" ]] &&
       [[ ! -e "$dns_fixture/etc/systemd/resolved.conf.d/20-aurelia-dns.conf" ]] &&
       grep -Fq 'DNS=9.9.9.9' "$dns_fixture/etc/systemd/resolved.conf"; then
        pass "DNS helper restores DHCP by removing only Aurelia-managed overrides"
    elif (( dns_fixture_ok )); then
        fail "DNS helper DHCP fixture did not remove only managed overrides"
    fi
    rm -rf -- "$dns_fixture"
    trap - RETURN
else
    pass "SKIP DNS helper write fixture (bwrap unavailable)"
fi

if grep -Fq 'exec pkexec /bin/bash "$PACKAGED_PATH" "$@"' "$ROOT/bin/aurelia-network-dns" &&
   grep -Fq 'exec sudo "$PACKAGED_PATH" "$@"' "$ROOT/bin/aurelia-network-dns"; then
    pass "DNS helper re-executes through a trusted interpreter for graphical and terminal privilege paths"
else
    fail "DNS helper privilege handoff is incomplete"
fi
