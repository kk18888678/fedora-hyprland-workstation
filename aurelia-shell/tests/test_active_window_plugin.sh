#!/usr/bin/env bash

# T-active-window bar-widget contract. These checks are isolated and never
# mutate the live compositor, bar, shell.json, or user configuration.

set -Eeuo pipefail

section "Aurelia Active Window Plugin"

active_root="$ROOT/plugins/aurelia.active-window"
manifest_file="$active_root/manifest.json"
widget_file="$active_root/ActiveWindowBarWidget.qml"
default_file="$ROOT/config/bar-default.json"
default_service="$ROOT/services/BarDefaultConfig.qml"
fixture_root="$ROOT/tests/fixtures/active-window"

if [[ -f "$manifest_file" && -f "$widget_file" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.active-window" and
       .name == "Active Window" and
       (.kinds == ["bar-widget"]) and
       .entryPoints.barWidget == "ActiveWindowBarWidget.qml" and
       .barWidget.displayName == "Active Window" and
       .barWidget.category == "Windows" and
       .barWidget.allowMultiple == false and
       .barWidget.defaultSection == "left" and
       .barWidget.defaults.maxWidth == 280 and
       (.barWidget.schema | map(.key) | index("maxWidth")) and
       .barWidget.schema[0].type == "integer" and
       .barWidget.schema[0].defaultValue == 280
   ' "$manifest_file" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$active_root" >/dev/null; then
    pass "[static] Active Window has a validated left bar-widget manifest with a bounded maxWidth default and schema"
else
    fail "[static] Active Window manifest, entry point, default section, or maxWidth schema is incomplete"
fi

if grep -Fq 'import Quickshell.Hyprland' "$widget_file" &&
   grep -Fq 'Hyprland.activeToplevel' "$widget_file" &&
   grep -Fq 'property var activeToplevelOverride' "$widget_file" &&
   grep -Fq 'DesktopEntries.heuristicLookup' "$widget_file" &&
   grep -Fq 'Quickshell.iconPath' "$widget_file" &&
   grep -Fq 'AureliaIcon' "$widget_file" &&
   grep -Fq 'WindowRouting.workspaceRouteInfo' "$widget_file"; then
    pass "[static] Active Window reads compositor state through the Hyprland active toplevel and the shared routing/icon boundaries"
else
    fail "[static] Active Window compositor, routing, or icon boundary is incomplete"
fi

if grep -Fq 'Text.ElideRight' "$widget_file" &&
   grep -Fq 'wrapMode: Text.NoWrap' "$widget_file" &&
   grep -Fq 'clip: true' "$widget_file" &&
   ! grep -Eq '(^|[^[:alnum:]_])opacity:' "$widget_file" &&
   grep -Fq 'duration: 180' "$widget_file" &&
   grep -Fq 'Easing.OutCubic' "$widget_file" &&
   grep -Fq 'bar.barIconCanvas' "$widget_file" &&
   grep -Fq 'bar.barTextMargin' "$widget_file" &&
   grep -Fq 'bar.barTextSize' "$widget_file" &&
   grep -Fq 'application-x-executable' "$widget_file"; then
    pass "[static] Active Window elides its label at full opacity, animates at 180 ms, and uses the shared icon/text canvas tokens"
else
    fail "[static] Active Window elision, full-opacity label, animation, or bar token contract is incomplete"
fi

if grep -Fq 'bar.barTrayIcon' "$widget_file" &&
   grep -Fq 'Theme.bar.trayIcon' "$widget_file" &&
   grep -Fq 'width: root.trayIcon' "$widget_file" &&
   grep -Fq 'height: root.trayIcon' "$widget_file" &&
   grep -Fq 'iconSize: root.trayIcon' "$widget_file" &&
   grep -Fq 'width: root.iconCanvas' "$widget_file" &&
   grep -Fq 'height: root.iconCanvas' "$widget_file" &&
   grep -Fq 'visible: root.hasIcon' "$widget_file" &&
   grep -Fq 'font.weight: Theme.fontWeightMedium' "$widget_file" &&
   grep -Fq 'renderType: Text.NativeRendering' "$widget_file" &&
   ! grep -Fq 'shadowEnabled' "$widget_file" &&
   ! grep -Fq 'preserveColors' "$widget_file"; then
    pass "[static] Active Window renders tray-sized image ink centred in the unchanged icon-canvas slot, hides the slot without an icon, and keeps colorization-only artwork with medium native-rendered text"
else
    fail "[static] Active Window icon ink/slot sizing, missing-icon hide, text crispness, or colorization-only artwork contract is incomplete"
fi

if grep -Fq 'AureliaToolTip' "$widget_file" &&
   grep -Fq 'text: root.label' "$widget_file" &&
   grep -Fq 'HoverHandler' "$widget_file" &&
   grep -Fq 'Theme.selection' "$widget_file" &&
   grep -Fq 'Theme.radiusSm' "$widget_file" &&
   grep -Fq 'visible: !root.vertical && root.label !== ""' "$widget_file" &&
   grep -Fq 'implicitWidth: root.visible' "$widget_file" &&
   grep -Fq 'handle.activate' "$widget_file" &&
   grep -Fq 'handle.close' "$widget_file" &&
   grep -Fq 'Qt.LeftButton' "$widget_file" &&
   grep -Fq 'Qt.MiddleButton' "$widget_file" &&
   grep -Fq 'Qt.RightButton' "$widget_file"; then
    pass "[static] Active Window exposes the full-title tooltip, hover fill, vertical hide, and null-guarded click handlers"
else
    fail "[static] Active Window tooltip, hover, visibility, or click contract is incomplete"
fi

if ! grep -Eq 'Timer[[:space:]]*\{|interval:|repeat: true|hyprctl|Quickshell\.execDetached|Process[[:space:]]*\{' "$widget_file"; then
    pass "[static] Active Window is signal-driven with no polling timer, subprocess, or hyprctl fallback"
else
    fail "[static] Active Window introduced a polling timer, subprocess, or hyprctl dependency"
fi

if jq -e '
        .layout.left[0].id == "aurelia.workspaces" and
        .layout.left[1].id == "aurelia.active-window"
    ' "$default_file" >/dev/null &&
   grep -Fq 'aurelia.active-window' "$default_service"; then
    pass "[static] Active Window is placed immediately after the workspace switcher in the default bar and its fallback"
else
    fail "[static] Active Window default bar placement or fallback mirror is missing"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] Active Window entry-point QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root"  || true' RETURN
result_file="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache"
: >"$result_file"

AURELIA_ACTIVE_WINDOW_SOURCE="file://$widget_file" \
AURELIA_ACTIVE_WINDOW_RESULT="$result_file" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$result_file" ]] &&
   runtime_log_is_environment_only "$runtime_log" 'hyprland|Hyprland' &&
   jq -e '
        .loaded == true and
        .labels.title == "Fixture title" and
        .labels.appId == "fixture.unknown.app" and
        .labels.className == "FixtureClass" and
        .labels.empty == "" and
        .icons.fallbackName == "application-x-executable" and
        (.icons.fallbackSource | contains("application-x-executable")) and
        .icons.emptyAppIconName == "application-x-executable" and
        .elision.maxWidth == 280 and
        .elision.longLabelWidth == 280 and
        .elision.longMeasured > 280 and
        .elision.cappedMaxWidth == 100 and
        .elision.cappedLabelWidth == 100 and
        .elision.shortMaxWidth == 280 and
        .elision.shortLabelWidth == (.elision.shortMeasured + 16) and
        .elision.longVisibleWidth == (.elision.maxWidth - 2 * .elision.longTextMargin) and
        .render.iconInk == 12 and
        .render.iconSlot == 16 and
        .render.iconSlotVisible == true and
        .render.labelOpacity == 1.0 and
        .render.implicitWidth == (.render.iconSlot + .render.iconSpacing + .render.outerLabelWidth) and
        .missingIcon.slotVisible == false and
        .missingIcon.visible == true and
        .missingIcon.implicitWidth == .missingIcon.labelWidth and
        .visibility.emptyVisible == false and
        .visibility.emptyImplicitWidth == 0 and
        .visibility.verticalVisible == false and
        .visibility.verticalImplicitWidth == 0 and
        .visibility.titleVisible == true and
        .visibility.titleImplicitWidth > 0 and
        .clicks.activates == 2 and
        .clicks.closes == 2 and
        .clicks.activateResult == "ok" and
        .clicks.closeResult == "ok"
   ' "$result_file" >/dev/null; then
    pass "[isolated-runtime] real Active Window widget resolves the title/app-id/class label, icon fallback, elision cap, activate/close dispatch, and hidden-when-empty state"
elif runtime_log_has_environment_diagnostic "$runtime_log" &&
     runtime_skip_if_environment_only "$runtime_log" "[isolated-runtime] Active Window entry-point fixture cannot create a disposable runtime backend"; then
    :
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_file" ]]; then details="$details result=$(tr '\n' ' ' <"$result_file")"; fi
    fail "[isolated-runtime] Active Window entry-point fixture failed (status=$runtime_status): $details"
fi
