#!/usr/bin/env bash

# T33 regression tests for the shared tooltip and popup coordinate boundary.
# The warning is fixed at its API receiver; no diagnostic filtering is allowed.

set -Eeuo pipefail

section "Shared Anchored Surface Geometry"

tooltip_source="$ROOT/ui/AureliaToolTip.qml"
popup_source="$ROOT/ui/AureliaPopupCard.qml"
keyboard_source="$ROOT/ui/AureliaKeyboardPanel.qml"
notification_source="$ROOT/plugins/aurelia.notifications/ui/NotificationPopupSurface.qml"
fixture_root="$ROOT/tests/fixtures/tooltip-geometry"

if [[ -f "$tooltip_source" && -f "$popup_source" && -f "$keyboard_source" && -f "$notification_source" ]] &&
   grep -Fq 'var point = root.anchorWindow.mapFromItem(target, localX, localY)' "$tooltip_source" &&
   grep -Fq 'var point = root.anchorWindow.mapFromItem(target, localX, localY)' "$popup_source" &&
   grep -Fq 'return anchorWindow.mapFromItem(resolvedAnchorItem, 0, 0)' "$keyboard_source" &&
   grep -Fq 'return root.anchorWindow.mapFromItem(root.anchorSlot, 0, 0)' "$notification_source" &&
   grep -Fq 'typeof root.anchorWindow.mapFromItem !== "function"' "$tooltip_source" &&
   grep -Fq 'typeof root.anchorWindow.mapFromItem !== "function"' "$popup_source" &&
   grep -Fq 'typeof anchorWindow.mapFromItem !== "function"' "$keyboard_source" &&
   grep -Fq 'typeof root.anchorWindow.mapFromItem !== "function"' "$notification_source" &&
   grep -Fq 'anchor_mapping_failed' "$tooltip_source" &&
   grep -Fq 'anchor_mapping_failed' "$popup_source" &&
   grep -Fq 'anchor_mapping_failed' "$keyboard_source" &&
   grep -Fq 'anchor_mapping_failed' "$notification_source" &&
   ! grep -Fq 'root.anchorWindow.contentItem.mapFromItem' "$tooltip_source" &&
   ! grep -Fq 'root.anchorWindow.contentItem.mapFromItem' "$popup_source" &&
   ! grep -Fq 'mapToItem(anchorWindow.contentItem' "$keyboard_source" &&
   ! grep -Fq 'mapToItem(root.anchorWindow.contentItem' "$notification_source" &&
   ! grep -Fq 'target.mapToItem(root.anchorWindow.contentItem' "$tooltip_source" &&
   ! grep -Fq 'target.mapToItem(root.anchorWindow.contentItem' "$popup_source"; then
    pass "[static] all anchored surfaces use the Quickshell window-owned source-item mapping"
else
    fail "[static] an anchored surface still uses an invalid content-item mapping boundary"
fi

if ! grep -Eq 'QT_LOGGING_RULES|QT_FATAL_WARNINGS|printErrors[[:space:]]*:[[:space:]]*false|suppress[[:space:]]+warning|ignore[[:space:]]+warning' \
    "$tooltip_source" "$popup_source"; then
    pass "[static] shared surfaces contain no warning filter or blanket diagnostic suppression"
else
    fail "[static] shared surfaces suppress warning output instead of fixing the mapping"
fi

if [[ -f "$fixture_root/shell.qml" ]] &&
   grep -Fq 'FocusScope {' "$fixture_root/shell.qml" &&
   grep -Fq 'PanelWindow {' "$fixture_root/shell.qml" &&
   grep -Fq 'barWindow.mapFromItem(panelSourceItem' "$fixture_root/shell.qml" &&
   grep -Fq 'sourceItem.mapToItem(contentScope' "$fixture_root/shell.qml"; then
    pass "[static] isolated fixture models a PanelWindow boundary and source-owned mapping"
else
    fail "[static] isolated mapping fixture is missing the source-to-FocusScope contract"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] FocusScope coordinate mapping fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
result_file="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache"

if [[ "${AURELIA_QML_RUNTIME_SMOKE:-0}" == "1" && -n "${WAYLAND_DISPLAY:-}" ]]; then
    runtime_mode="real-wayland"
    AURELIA_TOOLTIP_GEOMETRY_RESULT="$result_file" \
    AURELIA_TOOLTIP_GEOMETRY_TOOLTIP_SOURCE="file://$tooltip_source" \
    AURELIA_TOOLTIP_GEOMETRY_POPUP_SOURCE="file://$popup_source" \
    XDG_RUNTIME_DIR="$runtime_root/runtime" \
    XDG_STATE_HOME="$runtime_root/state" \
    XDG_CONFIG_HOME="$runtime_root/config" \
    XDG_CACHE_HOME="$runtime_root/cache" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?
else
    runtime_mode="offscreen"
    AURELIA_TOOLTIP_GEOMETRY_RESULT="$result_file" \
    AURELIA_TOOLTIP_GEOMETRY_TOOLTIP_SOURCE="file://$tooltip_source" \
    AURELIA_TOOLTIP_GEOMETRY_POPUP_SOURCE="file://$popup_source" \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$runtime_root/runtime" \
    XDG_STATE_HOME="$runtime_root/state" \
    XDG_CONFIG_HOME="$runtime_root/config" \
    XDG_CACHE_HOME="$runtime_root/cache" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?
fi

unexpected_diagnostics="$(grep -E 'WARN|ERROR|FATAL|TypeError|ReferenceError|QML Error' "$runtime_log" | grep -Ev 'ERROR quickshell\.ipc: Failed to start IPC server on path ' || true)"

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$result_file" ]] &&
   [[ -z "$unexpected_diagnostics" ]] &&
   jq -e '
        .sourceHasMapToItem == true and
        (.anchorType | contains("QQuickFocusScope")) and
        (.panelContentType | contains("QQuickFocusScope")) and
        .panelHasMapFromItem == true and
        .panelMappedX == 133 and
        .panelMappedY == 33 and
        .tooltipLoaded == true and
        .popupLoaded == true and
        .mappedFinite == true and
        .mappedX == .expectedX and
        .mappedY == .expectedY
    ' "$result_file" >/dev/null; then
    pass "[isolated-runtime] source-owned mapping succeeds against a QQuickFocusScope target without warnings"
elif [[ "$runtime_mode" == "offscreen" ]] &&
     grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|No PanelWindow backend loaded|Operation not permitted' "$runtime_log"; then
    pass "[skipped:isolated-runtime] QuickShell could not create an additional disposable runtime"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_file" ]]; then details="$details result=$(tr '\n' ' ' <"$result_file")"; fi
    fail "[isolated-runtime] shared coordinate mapping fixture failed (status=$runtime_status): $details"
fi
