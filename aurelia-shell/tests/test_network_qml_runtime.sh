#!/usr/bin/env bash

# Real-session QML smoke test for the Network bar widget. This test loads the
# actual QML through Quickshell and exercises the nested panel Loader, but it
# never clicks a provider or changes NetworkManager state.

set -Eeuo pipefail

section "Network QML Runtime Smoke"

if [[ "${AURELIA_QML_RUNTIME_SMOKE:-0}" != "1" ]]; then
    pass "SKIP Network QML smoke (set AURELIA_QML_RUNTIME_SMOKE=1 in a real Wayland session)"
    return 0
fi

if [[ -z "${WAYLAND_DISPLAY:-}" || ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "SKIP Network QML smoke (Wayland, qs, or timeout unavailable)"
    return 0
fi

smoke_dir="$(mktemp -d)"
smoke_file="$smoke_dir/shell.qml"
smoke_output="$smoke_dir/output.log"
trap 'rm -rf -- "$smoke_dir"' RETURN

cat >"$smoke_file" <<EOF_QML
import QtQuick
import Quickshell

ShellRoot {
    id: root
    property bool networkPanelReady: false

    Loader {
        id: networkLoader
        active: true
        source: "file://$ROOT/plugins/aurelia.network/NetworkBarWidget.qml"
        onLoaded: {
            root.networkPanelReady = item !== null && item.networkPanel !== null
            console.info("NETWORK_SMOKE panelReady=" + root.networkPanelReady)
        }
    }

    Timer {
        interval: 1800
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
EOF_QML

runtime_exit=0
HOME="$smoke_dir/home" XDG_CONFIG_HOME="$smoke_dir/config" XDG_STATE_HOME="$smoke_dir/state" \
    AURELIA_SHELL_ROOT="$ROOT" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate --path "$smoke_file" --no-color >"$smoke_output" 2>&1 || runtime_exit=$?

if grep -Fq 'NETWORK_SMOKE panelReady=true' "$smoke_output" &&
   [[ "$runtime_exit" -eq 0 ]] &&
   ! grep -Eq 'panel_load_failed|widget_load_failed|ReferenceError|TypeError|Unable to assign| is not a type|QML Error|FATAL' "$smoke_output"; then
    pass "Network bar widget and nested Network panel load in a real Quickshell session"
elif grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|Operation not permitted' "$smoke_output"; then
    pass "SKIP Network QML smoke (test runner cannot create an additional Wayland QuickShell surface)"
else
    sed -n '1,160p' "$smoke_output" >&2
    fail "Network QML runtime smoke failed (exit=$runtime_exit)"
fi
