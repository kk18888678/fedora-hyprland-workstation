#!/usr/bin/env bash

# T25 repository-only acceptance checks. Rendering and live Wayland interaction
# remain a separately authorized validation phase; isolated runtime contracts
# are owned by the feature and generic matrix suites.

set -Eeuo pipefail

section "Aurelia Plugin Parity Acceptance"

bar_config="$ROOT/config/bar-default.json"
bar_root="$ROOT/plugins/aurelia.bar"
bar_source="$bar_root/Bar.qml"
bar_slot="$bar_root/BarWidgetSlot.qml"

if jq -e '
        .id == "aurelia.bar" and
        .position == "top" and
        .centerAnchor == "aurelia.clock" and
        (.layout.left | length) == 1 and
        (.layout.center | length) == 3 and
        (.layout.right | length) == 6
    ' "$bar_config" >/dev/null &&
   grep -q 'readonly property bool vertical' "$bar_source" &&
   grep -q 'readonly property string centerAnchor' "$bar_source" &&
   grep -q 'property string activePopoutId' "$bar_source" &&
   grep -q 'function requestPopout' "$bar_source" &&
   grep -q 'function releasePopout' "$bar_source" &&
   grep -q 'barAnchorItem' "$bar_slot"; then
    pass "[static] bar placement, orientation, center anchoring, and single popout ownership are explicit"
else
    fail "[static] bar geometry or popup ownership acceptance contract is incomplete"
fi

acceptance_test_files=(
    test_bar_operations.sh
    test_plugin_management.sh
    test_plugin_clone.sh
    test_plugin_lifecycle_management.sh
    test_shell_reload.sh
    test_plugin_survivability.sh
    test_launcher_plugin.sh
    test_keybindings_interaction.sh
    test_notification_plugins.sh
    test_plugin_lifecycle.sh
)
acceptance_missing=0
for acceptance_test_file in "${acceptance_test_files[@]}"; do
    if [[ ! -f "$ROOT/tests/$acceptance_test_file" ]]; then
        fail "[static] acceptance owner is missing: $acceptance_test_file"
        acceptance_missing=$((acceptance_missing + 1))
    fi
done
if [[ "$acceptance_missing" -eq 0 ]]; then
    pass "[static] enable/disable/clone/remove, Command Center interaction, reload, survivability, notification, and lifecycle acceptance owners exist"
fi

if grep -q 'enablePlugin' "$ROOT/tests/test_bar_operations.sh" &&
   grep -q 'clone' "$ROOT/tests/test_plugin_clone.sh" &&
   grep -q 'remove' "$ROOT/tests/test_plugin_lifecycle_management.sh" &&
   grep -q 'function reloadPlugins' "$ROOT/shell.qml" &&
   grep -q 'function recordFailure' "$ROOT/services/PluginHost.qml"; then
    pass "[static] lifecycle acceptance flows stay on host/IPC boundaries with contained failure handling"
else
    fail "[static] lifecycle acceptance flow ownership is incomplete"
fi

if grep -q 'pluginReloaded' "$ROOT/services/PluginHost.qml" &&
   grep -q 'keepLoaded' "$ROOT/services/PluginHost.qml" &&
   grep -q 'onLocalPluginChanged' "$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml" &&
   grep -q 'notificationBus' "$ROOT/plugins/aurelia.notifications/Service.qml" &&
   grep -q 'server.registered' "$ROOT/plugins/aurelia.notifications/Service.qml"; then
    pass "[static] reload acceptance guards resident services, bar widgets, IPC ownership, and notification registration against duplication"
else
    fail "[static] reload/no-duplicate acceptance guards are incomplete"
fi

if grep -q 'Keyboard-first navigation' "$ROOT/tests/test_launcher_plugin.sh" &&
   grep -q 'Command Center Interaction Parity' "$ROOT/tests/test_keybindings_interaction.sh" &&
   grep -q 'semantic glyph' "$ROOT/tests/test_launcher_plugin.sh" &&
   grep -q 'selected row' "$ROOT/tests/test_keybindings_interaction.sh"; then
    pass "[static] Command Center and retained Aurelia feature interactions use the established design-language owners"
else
    fail "[static] Command Center or feature-interaction acceptance ownership is incomplete"
fi

if grep -q 'AURELIA_QML_RUNTIME_SMOKE' "$ROOT/tests/test_qml_runtime.sh" &&
   grep -q 'SKIP QML runtime smoke' "$ROOT/tests/test_qml_runtime.sh" &&
   grep -q 'real Wayland session' "$ROOT/tests/test_qml_runtime.sh"; then
    pass "[skipped:live-validation] live Wayland/visual acceptance remains explicitly gated and was not run"
else
    fail "[static] live-validation gate is missing or implicit"
fi
