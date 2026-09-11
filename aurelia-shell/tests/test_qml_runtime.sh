#!/usr/bin/env bash

# Bounded runtime smoke tests for QML entry points. Static manifest checks do
# not catch duplicate QML property assignments or unavailable component types.

set -Eeuo pipefail

section "QuickShell QML Runtime Smoke"

if [[ "${AURELIA_QML_RUNTIME_SMOKE:-0}" != "1" ]]; then
    pass "SKIP QML runtime smoke (set AURELIA_QML_RUNTIME_SMOKE=1 in a real Wayland session)"
    return 0
fi

if [[ -z "${WAYLAND_DISPLAY:-}" || ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "SKIP QML runtime smoke (Wayland, qs, or timeout unavailable)"
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
    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml"
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.weather/WeatherBarWidget.qml"
    }

    Loader {
        id: notificationService
        active: true
        source: "file://$ROOT/plugins/aurelia.notifications/Service.qml"
        onLoaded: {
            if (item && "centerOpen" in item) item.centerOpen = true
        }
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.notifications/BarWidget.qml"
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.notifications/ui/NotificationToast.qml"
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.monitor/DisplayBarWidget.qml"
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.workspaces/WorkspacesBarWidget.qml"
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.workspace-switcher/WorkspaceSwitcher.qml"
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.background/Background.qml"
    }

    Loader {
        active: true
        source: "file://$ROOT/plugins/aurelia.theme/ThemePanel.qml"
    }

    Loader {
        id: imagePicker
        active: true
        source: "file://$ROOT/plugins/aurelia.image-picker/ImagePicker.qml"
        onLoaded: {
            item.aureliaPath = "$ROOT"
            item.open('{"mode":"theme"}')
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
EOF_QML

runtime_status=0
XDG_STATE_HOME="$smoke_dir/state" XDG_CONFIG_HOME="$smoke_dir/config" XDG_CACHE_HOME="$smoke_dir/cache" \
    /usr/bin/timeout --kill-after=1s 6s /usr/bin/qs --no-duplicate --path "$smoke_file" >"$smoke_output" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] &&
   ! grep -Eq 'WARN|ERROR|FATAL|ReferenceError|TypeError|widget_load_failed|panel_load_failed' "$smoke_output"; then
    pass "Screenshot, weather, notification, workspace, workspace-overview, and image-picker surfaces instantiate in QuickShell without QML warnings or errors"
elif grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin' "$smoke_output"; then
    pass "SKIP QML runtime smoke (test runner cannot create an additional Wayland QuickShell surface)"
else
    fail "Screenshot bar widget runtime smoke failed (status=$runtime_status): $(tr '\n' ' ' <"$smoke_output")"
fi
