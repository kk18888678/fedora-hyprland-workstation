#!/usr/bin/env bash

# Contract and isolated state tests for Aurelia theme/background ownership.

set -Eeuo pipefail

background_root="$ROOT/plugins/aurelia.background"
theme_plugin_root="$ROOT/plugins/aurelia.theme"
theme_root="$ROOT/theme"

section "Aurelia Theme and Background Plugins"

if [[ -f "$background_root/manifest.json" &&
      -f "$background_root/Background.qml" &&
      -f "$background_root/BackgroundMedia.qml" &&
      -f "$background_root/BackgroundVideo.qml" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.background" and
       .keepLoaded == true and
       (.kinds == ["service"]) and
       .entryPoints.service == "Background.qml"
   ' "$background_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$background_root" >/dev/null 2>&1; then
    pass "Background is a validated resident service plugin with image/video entry surfaces"
else
    fail "Background plugin manifest or entry surfaces are incomplete"
fi

if grep -q 'model: Quickshell.screens' "$background_root/Background.qml" &&
   grep -q 'WlrLayershell.layer: WlrLayer.Background' "$background_root/Background.qml" &&
   grep -q 'updatesEnabled: true' "$background_root/Background.qml" &&
   grep -q 'exclusionMode: ExclusionMode.Ignore' "$background_root/Background.qml" &&
   grep -q 'legacyNoctaliaStatePath' "$background_root/Background.qml" &&
   grep -q 'function setBackground' "$background_root/Background.qml" &&
   grep -q 'target: "aurelia.background"' "$background_root/Background.qml" &&
   grep -q 'aurelia.image-picker' "$background_root/Background.qml"; then
    pass "Background keeps one always-mapped layer per screen with safe state fallback and image-picker entry"
else
    fail "Background layer, fallback, or IPC contract is incomplete"
fi

if grep -q 'property bool video' "$background_root/BackgroundMedia.qml" &&
   grep -q 'source: Qt.resolvedUrl("BackgroundVideo.qml")' "$background_root/BackgroundMedia.qml" &&
   grep -q 'VideoOutput' "$background_root/BackgroundVideo.qml" &&
   grep -q 'MediaPlayer.Infinite' "$background_root/BackgroundVideo.qml" &&
   grep -q 'root.priming' "$background_root/BackgroundVideo.qml"; then
    pass "Background media keeps still images lightweight and primes looping video safely"
else
    fail "Background media image/video separation is incomplete"
fi

if [[ -f "$theme_plugin_root/manifest.json" && -f "$theme_plugin_root/ThemePanel.qml" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.theme" and
       (.kinds == ["panel"]) and
       .entryPoints.panel == "ThemePanel.qml"
   ' "$theme_plugin_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$theme_plugin_root" >/dev/null 2>&1; then
    pass "Theme and Wallpaper selector is a validated on-demand panel plugin"
else
    fail "Theme selector manifest or panel entry point is incomplete"
fi

if grep -q 'activeThemePath' "$theme_root/Theme.qml" &&
   grep -q 'effectiveThemePath' "$theme_root/Theme.qml" &&
   grep -q 'watchChanges: true' "$theme_root/Theme.qml" &&
   grep -q 'function reloadTheme' "$theme_root/Theme.qml" &&
   grep -q 'themeRoot.themeFile.reload()' "$theme_root/Theme.qml" &&
   grep -q 'themeRoot.activeThemeProbe.running = true' "$theme_root/Theme.qml" &&
   grep -q 'reloadToken = _themeReloadToken' "$theme_root/Theme.qml" &&
   grep -q 'function reloadTheme(): string' "$ROOT/shell.qml" &&
   grep -q 'Theme.reloadTheme()' "$ROOT/shell.qml" &&
   grep -q 'function themeStatus(): string' "$ROOT/shell.qml" &&
   grep -q 'Theme.effectiveThemePath' "$ROOT/shell.qml" &&
   grep -q 'function applyTheme(): string' "$ROOT/shell.qml" &&
   grep -q 'function applyTheme()' "$background_root/Background.qml" &&
   grep -q 'activeShellPath' "$theme_root/Theme.qml" &&
   grep -q 'activeThemeAvailable ? activeThemePath' "$theme_root/Theme.qml" &&
   grep -q 'loadedShellOverrides' "$theme_root/Theme.qml" &&
   grep -q 'property QtObject popups' "$theme_root/Theme.qml" &&
   grep -q 'property QtObject imagePicker' "$theme_root/Theme.qml" &&
   grep -q 'shellPath: Theme.effectiveShellPath' "$ROOT/shell.qml" &&
   grep -q 'barBackground: String(Theme.bar.background)' "$ROOT/shell.qml"; then
    pass "Theme singleton reloads active XDG state and exposes one atomic shell apply/status IPC boundary"
else
    fail "Theme active-state reload contract is incomplete"
fi

if grep -q 'function themeStatus()' "$ROOT/plugins/aurelia.bar/Bar.qml" &&
   grep -q 'function barThemeStatus(): string' "$ROOT/shell.qml" &&
   grep -q 'id: barSurface' "$ROOT/plugins/aurelia.bar/Bar.qml"; then
    pass "bar exposes its bound surface and shared theme values for runtime diagnosis"
else
    fail "bar runtime theme diagnosis is incomplete"
fi

if [[ -x "$ROOT/bin/aurelia-theme" &&
      -x "$ROOT/bin/aurelia-theme-bg" &&
      -x "$ROOT/bin/lib/aurelia-theme/common.sh" ]] &&
   bash -n "$ROOT/bin/aurelia-theme" "$ROOT/bin/aurelia-theme-bg" "$ROOT/bin/lib/aurelia-theme/common.sh" &&
   grep -q 'colors.toml' "$ROOT/bin/lib/aurelia-theme/common.sh" &&
   grep -q 'aurelia_theme_atomic_copy' "$ROOT/bin/lib/aurelia-theme/common.sh" &&
   grep -q 'aurelia_theme_lock_state' "$ROOT/bin/lib/aurelia-theme/common.sh" &&
   grep -q 'aurelia_theme_notify_shell' "$ROOT/bin/lib/aurelia-theme/common.sh" &&
   grep -q 'shell applyTheme' "$ROOT/bin/lib/aurelia-theme/common.sh"; then
    pass "Theme/background commands use shared validated helpers and one live apply path"
else
    fail "Theme/background command helper contract is incomplete"
fi

theme_test_tmp="$(mktemp -d)"
trap 'rm -rf -- "$theme_test_tmp"' RETURN
mkdir -p \
    "$theme_test_tmp/home" \
    "$theme_test_tmp/config" \
    "$theme_test_tmp/state" \
    "$theme_test_tmp/themes/tokyo-night/backgrounds"
printf 'background = #1a1b26\naccent = #7aa2f7\n' \
    >"$theme_test_tmp/themes/tokyo-night/colors.toml"
printf 'not-an-image\n' >"$theme_test_tmp/themes/tokyo-night/backgrounds/1-first.png"
printf 'not-an-image\n' >"$theme_test_tmp/themes/tokyo-night/backgrounds/2-second.png"

theme_test_env=(
    "AURELIA_THEMES_DIR=$theme_test_tmp/themes"
    "AURELIA_USE_INSTALLED_SHELL=1"
    "HOME=$theme_test_tmp/home"
    "XDG_CONFIG_HOME=$theme_test_tmp/config"
    "XDG_STATE_HOME=$theme_test_tmp/state"
    "XDG_CACHE_HOME=$theme_test_tmp/cache"
)

list_output="$(env "${theme_test_env[@]}" "$ROOT/bin/aurelia-theme" list)"
if [[ "$list_output" == *"Default"* && "$list_output" == *"Tokyo Night"* ]]; then
    pass "theme list discovers bundled default and external data-only themes"
else
    fail "theme list did not discover expected themes: $list_output"
fi

if env "${theme_test_env[@]}" "$ROOT/bin/aurelia-theme" set "Tokyo Night" >/dev/null &&
   [[ "$(sed -n '1p' "$theme_test_tmp/state/aurelia/current/theme.name")" == "tokyo-night" ]] &&
   grep -q '^background = #1a1b26$' "$theme_test_tmp/state/aurelia/current/theme.conf" &&
   grep -q '^background = "#1a1b26"$' "$theme_test_tmp/state/aurelia/current/shell.toml" &&
   grep -q '^\[image-picker\]$' "$theme_test_tmp/state/aurelia/current/shell.toml" &&
   [[ "$(sed -n '1p' "$theme_test_tmp/state/aurelia/current/background.path")" == *"/1-first.png" ]]; then
    pass "theme set atomically stages palette, surface tokens, active name, and first background"
else
    fail "theme set did not converge isolated Aurelia state"
fi

if env "${theme_test_env[@]}" "$ROOT/bin/aurelia-theme" catalog --json |
   jq -e '
       .currentTheme == "tokyo-night" and
       ([.themes[] | select(.id == "tokyo-night") | .backgrounds[]] | length) == 2
   ' >/dev/null &&
   env "${theme_test_env[@]}" "$ROOT/bin/aurelia-theme-bg" list --json |
   jq -e '.theme == "tokyo-night" and (.backgrounds | length) == 2' >/dev/null; then
    pass "theme and background catalogs expose current state as valid JSON"
else
    fail "theme/background JSON catalog is incomplete"
fi

if env "${theme_test_env[@]}" "$ROOT/bin/aurelia-theme-bg" next >/dev/null &&
   [[ "$(sed -n '1p' "$theme_test_tmp/state/aurelia/current/background.path")" == *"/2-second.png" ]]; then
    pass "background next cycles deterministically through the active theme"
else
    fail "background next did not advance the isolated selection"
fi

if env "${theme_test_env[@]}" "$ROOT/bin/aurelia-theme-bg" set "$theme_test_tmp/home/not-supported.txt" >/dev/null 2>&1; then
    fail "background set accepted an unsupported file extension"
else
    pass "background set rejects unsupported media paths before state mutation"
fi

rm -rf -- "$theme_test_tmp"
trap - RETURN
