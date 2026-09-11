#!/usr/bin/env bash

# Real-session QML regression test for the DNS action state machine. The QML
# is real, but the helper commands are disposable fixtures: this never changes
# the host's NetworkManager or DNS configuration.

set -Eeuo pipefail

section "Network DNS Action Runtime"

if [[ "${AURELIA_QML_RUNTIME_SMOKE:-0}" != "1" ]]; then
    pass "SKIP Network DNS runtime test (set AURELIA_QML_RUNTIME_SMOKE=1 in a real Wayland session)"
    return 0
fi

if [[ -z "${WAYLAND_DISPLAY:-}" || ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "SKIP Network DNS runtime test (Wayland, qs, or timeout unavailable)"
    return 0
fi

test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' RETURN
mkdir -p "$test_dir/bin"

cat >"$test_dir/bin/aurelia-network-status" <<'EOF_STATUS'
#!/usr/bin/env bash
exit 0
EOF_STATUS
cat >"$test_dir/bin/aurelia-network-band" <<'EOF_BAND'
#!/usr/bin/env bash
exit 0
EOF_BAND
cat >"$test_dir/bin/aurelia-network-dns" <<'EOF_DNS'
#!/usr/bin/env bash
case "${1:-}" in
    "") printf '%s\n' DHCP ;;
    Cloudflare) exit 124 ;;
    *) exit 0 ;;
esac
EOF_DNS
cat >"$test_dir/bin/aurelia-network-dns-terminal" <<'EOF_TERMINAL'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$AURELIA_NETWORK_DNS_TERMINAL_LOG"
EOF_TERMINAL
chmod 0755 "$test_dir/bin"/*

shell_file="$test_dir/shell.qml"
output_file="$test_dir/output.log"
cat >"$shell_file" <<EOF_QML
import QtQuick
import Quickshell

ShellRoot {
    id: root
    property var panel: null

    QtObject {
        id: fakeBar
        property int barSize: 26
        property int widgetRevision: 0
        property string position: "top"
        property var contentItem: null
        function requestPopout(owner, ownerId) {}
        function releasePopout(owner) {}
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.network/NetworkPanel.qml"
        onLoaded: {
            root.panel = item
            item.backendRoot = "$test_dir/bin"
            item.bar = fakeBar
            item.open("{}")
            item.setDns("Cloudflare")
        }
    }

    Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: {
            var closed = root.panel && root.panel.shown === false
            var surfaced = root.panel && String(root.panel.dnsError || "").indexOf("Authorization") >= 0
            console.info("NETWORK_DNS_SMOKE closed=" + closed + " surfaced=" + surfaced)
            Qt.quit()
        }
    }
}
EOF_QML

runtime_exit=0
HOME="$test_dir/home" XDG_CONFIG_HOME="$test_dir/config" XDG_STATE_HOME="$test_dir/state" \
    PATH="$test_dir/bin:/usr/local/bin:/usr/bin:/bin" \
    AURELIA_NETWORK_DNS_TERMINAL_LOG="$test_dir/terminal.log" \
    AURELIA_SHELL_ROOT="$ROOT" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate --path "$shell_file" --no-color >"$output_file" 2>&1 || runtime_exit=$?

if grep -Fq 'NETWORK_DNS_SMOKE closed=true surfaced=true' "$output_file" &&
   [[ "$runtime_exit" -eq 0 ]] &&
   ! grep -Eq 'ReferenceError|TypeError|Unable to assign| is not a type|QML Error|FATAL' "$output_file"; then
    pass "Real QML DNS timeout closes the card and surfaces authorization fallback"
elif grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|Operation not permitted' "$output_file"; then
    pass "SKIP Network DNS runtime test (test runner cannot create an additional Wayland QuickShell surface)"
else
    sed -n '1,180p' "$output_file" >&2
    fail "Network DNS QML runtime regression test failed (exit=$runtime_exit)"
fi
