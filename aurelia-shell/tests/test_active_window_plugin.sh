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
       .barWidget.defaults.displayMode == "app" and
       (.barWidget.schema | map(.key) | index("maxWidth")) and
       (.barWidget.schema | map(.key) | index("displayMode")) and
       .barWidget.schema[0].key == "maxWidth" and
       .barWidget.schema[0].type == "integer" and
       .barWidget.schema[0].defaultValue == 280 and
       .barWidget.schema[1].key == "displayMode" and
       .barWidget.schema[1].type == "enum" and
       .barWidget.schema[1].label == "Display" and
       .barWidget.schema[1].defaultValue == "app" and
       .barWidget.schema[1].options[0].value == "app" and
       .barWidget.schema[1].options[0].label == "Application name" and
       .barWidget.schema[1].options[1].value == "title" and
       .barWidget.schema[1].options[1].label == "Window title"
   ' "$manifest_file" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$active_root" >/dev/null; then
    pass "[static] Active Window has a validated left bar-widget manifest with a bounded maxWidth default and a displayMode enum (maxWidth first)"
else
    fail "[static] Active Window manifest, entry point, default section, or maxWidth schema is incomplete"
fi

if grep -Fq 'import Quickshell.Hyprland' "$widget_file" &&
   grep -Fq 'Hyprland.activeToplevel' "$widget_file" &&
   grep -Fq 'property var activeToplevelOverride' "$widget_file" &&
   grep -Fq 'property var toplevelsOverride' "$widget_file" &&
   grep -Fq 'Hyprland.toplevels' "$widget_file" &&
   grep -Fq 'WindowRouting.focusedToplevel' "$widget_file" &&
   grep -Fq 'DesktopEntries.heuristicLookup' "$widget_file" &&
   grep -Fq 'Quickshell.iconPath' "$widget_file" &&
   grep -Fq 'AureliaIcon' "$widget_file" &&
   grep -Fq 'WindowRouting.workspaceRouteInfo' "$widget_file"; then
    pass "[static] Active Window reads compositor state through the Hyprland active toplevel, the model-derived focused-toplevel fallback, and the shared routing/icon boundaries"
else
    fail "[static] Active Window compositor, startup fallback, routing, or icon boundary is incomplete"
fi

window_routing_file="$ROOT/services/WindowRouting.js"
if grep -Fq 'function focusedToplevel' "$window_routing_file" &&
   grep -Fq 'focusHistoryID' "$window_routing_file" &&
   grep -Fq 'focusedToplevel: focusedToplevel' "$window_routing_file"; then
    pass "[static] WindowRouting exposes the pure model-derived focusedToplevel helper keyed on focusHistoryID"
else
    fail "[static] WindowRouting focusedToplevel helper is missing or not keyed on focusHistoryID"
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
   grep -Fq 'preserveColors: !root.symbolicIcon' "$widget_file" &&
   grep -Fq 'readonly property bool symbolicIcon' "$widget_file"; then
    pass "[static] Active Window renders tray-sized image ink centred in the unchanged icon-canvas slot, hides the slot without an icon, and preserves real application logo colours while tinting only symbolic masks"
else
    fail "[static] Active Window icon ink/slot sizing, missing-icon hide, text crispness, or symbolic-icon colour policy contract is incomplete"
fi

if grep -Fq 'split("?")[0]' "$widget_file" &&
   grep -Fq 'slice(-9) === "-symbolic"' "$widget_file" &&
   grep -Fq 'preserveColors: !root.symbolicIcon' "$widget_file"; then
    pass "[static] Active Window symbolic-icon contract strips the query string, tints -symbolic masks, and preserves real application logo colours like the tray"
else
    fail "[static] Active Window symbolic-icon predicate or colour-binding contract is incomplete"
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

if ! grep -Eq 'Timer[[:space:]]*\{|interval:|repeat: true|hyprctl|Quickshell\.execDetached|Process[[:space:]]*\{' "$widget_file" &&
   grep -Fq 'Hyprland.toplevels' "$widget_file" &&
   grep -Fq 'WindowRouting.focusedToplevel' "$widget_file"; then
    pass "[static] Active Window is signal-driven with no polling timer, subprocess, or hyprctl fallback; the startup fallback is model-derived through Hyprland.toplevels and the focusHistoryID helper"
else
    fail "[static] Active Window introduced a polling timer, subprocess, or hyprctl dependency, or lost the model-derived fallback"
fi

if grep -Fq 'property string displayMode' "$widget_file" &&
   grep -Fq 'settings.displayMode' "$widget_file" &&
   grep -Fq 'return raw === "title" ? "title" : "app"' "$widget_file" &&
   grep -Fq 'DesktopEntries.heuristicLookup' "$widget_file" &&
   grep -Fq 'appEntry.name' "$widget_file" &&
   grep -Fq 'root.appId !== ""' "$widget_file" &&
   grep -Fq 'Quickshell.hasThemeIcon(root.appId)' "$widget_file" &&
   grep -Fq 'root.routeInfo.className || root.routeInfo.initialClass' "$widget_file" &&
   grep -Fq 'readonly property string titleLabel' "$widget_file" &&
   grep -Fq 'readonly property string appName' "$widget_file" &&
   grep -Fq 'label: root.displayMode === "title" ? root.titleLabel : root.appName' "$widget_file"; then
    pass "[static] Active Window defaults to app name, resolves it from the desktop entry (then appId, then IPC class), prefers a real theme icon for the raw app id before the substring heuristics, keeps title-first titleLabel, and selects label by displayMode"
else
    fail "[static] Active Window display-mode selection, desktop-entry lookup, theme-icon step, or identity fallback contract is incomplete"
fi

if grep -Fq 'property bool labelWidthInitialized' "$widget_file" &&
   grep -Fq 'enabled: root.labelWidthInitialized' "$widget_file" &&
   grep -Fq 'onLabelChanged' "$widget_file" &&
   grep -Fq 'Qt.callLater' "$widget_file" &&
   ! grep -Fq 'onAnimatedLabelWidthChanged' "$widget_file" &&
   grep -Fq 'duration: 180' "$widget_file" &&
   grep -Fq 'Easing.OutCubic' "$widget_file"; then
    pass "[static] Active Window suppresses the width animation for the first non-empty label only, then keeps the 180 ms OutCubic transition"
else
    fail "[static] Active Window first-population width animation gate is missing or the later animation contract regressed"
fi

if python3 - "$widget_file" <<'TITLE_IDENTITY'
import re, sys
src = open(sys.argv[1]).read()
match = re.search(r"readonly property string titleLabel:\s*\{(.*?)\n    \}", src, re.S)
if not match:
    sys.exit(1)
body = match.group(1)
i_title = body.find("return title")
i_appid = body.find("return handleAppId")
i_class = body.find("return String(root.routeInfo.className || root.routeInfo.initialClass")
sys.exit(0 if 0 <= i_title < i_appid < i_class else 1)
TITLE_IDENTITY
then
    pass "[static] Active Window titleLabel preserves title -> handle.appId -> class preference order"
else
    fail "[static] Active Window titleLabel precedence regressed"
fi

if python3 - "$widget_file" <<'LABEL_MEASURER'
import re, sys
src = open(sys.argv[1]).read()
match = re.search(r"Text\s*\{\s*id:\s*labelMeasure\b(.*?)\n    \}", src, re.S)
if not match:
    sys.exit(1)
body = match.group(1)
# The measurer must use the same engine as the visible render: the same text,
# the same resolved font (including weight/pixelSize) and the same render type.
if not all(token in body for token in (
        "visible: false",
        "text: root.label",
        "font: labelText.font",
        "renderType: labelText.renderType")):
    sys.exit(1)
# A measurer must never elide or clip: an elided Text reports its elided width
# and would shrink the box on every pass (a feedback loop).
if "elide" in body or "contentWidth" in body:
    sys.exit(1)
sys.exit(0)
LABEL_MEASURER
then
    pass "[static] Active Window measures the label with a hidden, non-eliding Text that copies the visible render's font and render type so the metric cannot drift from the render"
else
    fail "[static] Active Window label measurer does not copy the render font/render type, or it elides and can shrink its own box"
fi

if grep -Fq 'readonly property real measuredLabelWidth: labelMeasure.contentWidth' "$widget_file" &&
   grep -Fq 'readonly property real labelWidth: Math.min(root.measuredLabelWidth + root.textMargin * 2, root.maxWidth)' "$widget_file" &&
   ! grep -Fq 'advanceWidth' "$widget_file" &&
   ! grep -Fq 'labelMetrics' "$widget_file"; then
    pass "[static] Active Window derives measuredLabelWidth from the hidden measurer and keeps the capped text-margin formula, with no leftover TextMetrics advanceWidth"
else
    fail "[static] Active Window measurement source or bounded labelWidth formula regressed"
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
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache" \
    "$runtime_root/data/applications" "$runtime_root/data-home"
: >"$result_file"
# Deterministic desktop-entry resolution: minimal fixture entries in an
# isolated XDG data dir prove the app-name and icon branch without depending
# on the host application database. foot.desktop and chromium-browser.desktop
# are the two reported over-truncation cases.
cat >"$runtime_root/data/applications/fixture-app.desktop" <<'FIXTURE_APP'
[Desktop Entry]
Type=Application
Name=Fixture App
Icon=fixture-app
Exec=fixture-app
FIXTURE_APP

cat >"$runtime_root/data/applications/foot.desktop" <<'FIXTURE_FOOT'
[Desktop Entry]
Type=Application
Name=Foot
Icon=utilities-terminal
Exec=foot
FIXTURE_FOOT

cat >"$runtime_root/data/applications/chromium-browser.desktop" <<'FIXTURE_CHROMIUM'
[Desktop Entry]
Type=Application
Name=Chromium Web Browser
Icon=chromium
Exec=chromium-browser %U
FIXTURE_CHROMIUM

AURELIA_ACTIVE_WINDOW_SOURCE="file://$widget_file" \
AURELIA_ACTIVE_WINDOW_RESULT="$result_file" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
XDG_DATA_HOME="$runtime_root/data-home" \
XDG_DATA_DIRS="$runtime_root/data:/usr/local/share:/usr/share" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$result_file" ]] &&
   runtime_log_is_environment_only "$runtime_log" 'hyprland|Hyprland' &&
   jq -e '
        .loaded == true and
        .labels.app == "fixture.unknown.app" and
        .labels.appId == "fixture.unknown.app" and
        .labels.className == "FixtureClass" and
        .labels.empty == "" and
        .labels.titleMode == "Fixture title" and
        .labels.titleModeTitle == "Fixture title" and
        .labels.invalidMode == "fixture.unknown.app" and
        .labels.fixtureApp == "Fixture App" and
        .labels.modelFallback == "FixtureClass" and
        .labels.modelAmbiguous == "" and
        .labels.modelEmpty == "" and
        .icons.fallbackName == "application-x-executable" and
        (.icons.fallbackSource | contains("application-x-executable")) and
        .icons.emptyAppIconName == "application-x-executable" and
        .icons.fixtureAppName == "fixture-app" and
        .fallback.modelFallbackLabel == "FixtureClass" and
        .fallback.modelFallbackIcon == "application-x-executable" and
        .fallback.modelFallbackHasIcon == true and
        .fallback.modelFallbackAppEntry == false and
        .fallback.modelAmbiguousLabel == "" and
        .fallback.modelEmptyLabel == "" and
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
        .visibility.modelFallbackVisible == true and
        .visibility.modelAmbiguousVisible == false and
        .visibility.modelEmptyVisible == false and
        .clicks.activates == 2 and
        .clicks.closes == 2 and
        .clicks.activateResult == "ok" and
        .clicks.closeResult == "ok" and
        .policy.symbolicIcon == false and
        .policy.preserveColors == true and
        .policy.symbolicName == "fixture-app-symbolic?theme=dark" and
        .policy.symbolicIconFlag == true and
        .policy.symbolicPreserveColors == false and
        .rendered.footApp.label == "Foot" and
        .rendered.footApp.maxWidth == 280 and
        .rendered.footApp.truncated == false and
        .rendered.footApp.elided == false and
        .rendered.footApp.contentDelta < 0.5 and
        .rendered.chromiumApp.label == "Chromium Web Browser" and
        .rendered.chromiumApp.maxWidth == 280 and
        .rendered.chromiumApp.truncated == false and
        .rendered.chromiumApp.elided == false and
        .rendered.chromiumApp.contentDelta < 0.5 and
        .rendered.longTitle.truncated == true and
        .rendered.longTitle.elided == true and
        (.rendered.longTitle.label | length) > 40 and
        .rendered.cappedTitle.truncated == true and
        .rendered.titleMode.label == "Fixture title" and
        .rendered.titleMode.truncated == false and
        .rendered.titleMode.elided == false and
        .rendered.titleMode.contentDelta < 0.5
   ' "$result_file" >/dev/null; then
    pass "[isolated-runtime] real Active Window widget resolves app-name/title identity, the deterministic desktop-entry name/icon branch, invalid-mode fail-closed, icon fallback, elision cap, activate/close dispatch, hidden-when-empty state, the symbolic-only colour policy, the model-derived focused-toplevel fallback (class identity, missing marker ignored, ambiguity fail-closed, empty model hidden), and renders 'Foot' and 'Chromium Web Browser' un-elided with the metric matching the render"
elif runtime_log_has_environment_diagnostic "$runtime_log" &&
     runtime_skip_if_environment_only "$runtime_log" "[isolated-runtime] Active Window entry-point fixture cannot create a disposable runtime backend"; then
    :
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_file" ]]; then details="$details result=$(tr '\n' ' ' <"$result_file")"; fi
    fail "[isolated-runtime] Active Window entry-point fixture failed (status=$runtime_status): $details"
fi

# The earliest-population fixture. It loads the real widget only after the
# deterministic desktop-entry scan is ready, publishes the focused fake
# toplevel as the compositor model, and snapshots synchronously inside the
# widget's onLoaded. This is the assertion that fails without the startup
# fallback: at shell start there is no activewindowv2 event, so the label,
# icon, app entry, visibility and final width must all come from the model.
startup_result="$runtime_root/startup-result.json"
startup_log="$runtime_root/startup.log"
startup_status=0
: >"$startup_result"
AURELIA_ACTIVE_WINDOW_SOURCE="file://$widget_file" \
AURELIA_ACTIVE_WINDOW_STARTUP_RESULT="$startup_result" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
XDG_DATA_HOME="$runtime_root/data-home" \
XDG_DATA_DIRS="$runtime_root/data:/usr/local/share:/usr/share" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/startup.qml" --no-color >"$startup_log" 2>&1 || startup_status=$?

if [[ "$startup_status" -eq 0 ]] && [[ -s "$startup_result" ]] &&
   runtime_log_is_environment_only "$startup_log" 'hyprland|Hyprland' &&
   jq -e '
        .loaded == true and
        .snapshot.label == "Fixture App" and
        .snapshot.iconName == "fixture-app" and
        .snapshot.hasIcon == true and
        .snapshot.appEntry == true and
        .snapshot.appEntryName == "Fixture App" and
        .snapshot.visible == true and
        .snapshot.implicitWidth > 0 and
        .snapshot.animatedMatchesLabel == true
   ' "$startup_result" >/dev/null; then
    pass "[isolated-runtime] Active Window discovers an already-focused window from the toplevel model synchronously at load (no settle timer): final app label, desktop-entry theme icon, resolved app entry, visible state and final width are all present"
elif runtime_log_has_environment_diagnostic "$startup_log" &&
     runtime_skip_if_environment_only "$startup_log" "[isolated-runtime] Active Window startup fixture cannot create a disposable runtime backend"; then
    :
else
    details="$(tr '\n' ' ' <"$startup_log")"
    if [[ -s "$startup_result" ]]; then details="$details result=$(tr '\n' ' ' <"$startup_result")"; fi
    fail "[isolated-runtime] Active Window startup fixture failed (status=$startup_status): $details"
fi
