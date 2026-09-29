#!/usr/bin/env bash

# Shared AureliaIcon rendering-primitive contract.
#
# The primitive must render NOTHING when an icon is unavailable instead of
# leaving Qt's built-in missing-image placeholder on screen. This suite pins
# the static shape of that failure handling and then renders the REAL primitive
# offscreen for a missing path, an empty source, and a theme name the theme
# does not provide, asserting that neither render element is visible and the
# primitive reports `hasIcon === false`. It also proves a genuinely resolvable
# theme icon and a real logo path still draw with their colours preserved.
#
# Pixel grabbing is unavailable under the offscreen backend, so the runtime
# assertion is the render-path state that decides whether pixels are drawn.

set -Eeuo pipefail

section "Aurelia Icon Primitive"

icon_primitive="$ROOT/ui/AureliaIcon.qml"
fixture_root="$ROOT/tests/fixtures/icon-primitive"

if grep -Fq 'readonly property bool iconReady' "$icon_primitive" &&
   grep -Fq 'readonly property bool hasIcon' "$icon_primitive" &&
   grep -Fq 'iconSource.status === Image.Ready' "$icon_primitive" &&
   grep -Fq 'visible: !root.usingGlyph && root.preserveColors && root.iconReady' "$icon_primitive" &&
   grep -Fq 'visible: !root.usingGlyph && root.iconReady && !root.preserveColors' "$icon_primitive"; then
    pass "[static] AureliaIcon hides both render elements unless the artwork is drawable and exposes the outcome to callers"
else
    fail "[static] AureliaIcon does not gate rendering on a drawable outcome or does not expose it"
fi

if ! grep -Fq 'AppIconResolver' "$icon_primitive" &&
   ! grep -Fq 'function resolve' "$icon_primitive"; then
    pass "[static] AureliaIcon stays a pure rendering primitive with no resolution policy"
else
    fail "[static] AureliaIcon grew resolution logic instead of staying a pure rendering primitive"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] AureliaIcon primitive fixture (qs or timeout unavailable)"
    return 0
fi

primitive_rt="$(mktemp -d)"
trap 'rm -rf -- "$primitive_rt" || true' RETURN
mkdir -p -- "$primitive_rt/runtime" "$primitive_rt/state" "$primitive_rt/config" \
    "$primitive_rt/cache" "$primitive_rt/home" "$primitive_rt/data-home" \
    "$primitive_rt/data/icons/hicolor/16x16/apps"

# A real 1x1 PNG for the logo path and the deterministic theme icons.
sample_png="$primitive_rt/sample.png"
base64 -d >"$sample_png" <<'PRIMITIVE_PNG_B64'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
PRIMITIVE_PNG_B64
cp -- "$sample_png" "$primitive_rt/data/icons/hicolor/16x16/apps/fixture-app.png"
cp -- "$sample_png" "$primitive_rt/data/icons/hicolor/16x16/apps/fixture-app-symbolic.png"

primitive_result="$primitive_rt/result.json"
primitive_log="$primitive_rt/runtime.log"
: >"$primitive_result"
primitive_status=0
AURELIA_ICON_PRIMITIVE_PROBE_SOURCE="file://$fixture_root/probe.qml" \
AURELIA_ICON_PRIMITIVE_SOURCE="file://$icon_primitive" \
AURELIA_ICON_PRIMITIVE_RESULT="$primitive_result" \
AURELIA_ICON_PRIMITIVE_PNG="$sample_png" \
AURELIA_ICON_PRIMITIVE_MISSING="$primitive_rt/does-not-exist.png" \
HOME="$primitive_rt/home" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$primitive_rt/runtime" \
XDG_STATE_HOME="$primitive_rt/state" \
XDG_CONFIG_HOME="$primitive_rt/config" \
XDG_CACHE_HOME="$primitive_rt/cache" \
XDG_DATA_HOME="$primitive_rt/data-home" \
XDG_DATA_DIRS="$primitive_rt/data:/usr/local/share:/usr/share" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color >"$primitive_log" 2>&1 || primitive_status=$?

# The missing-path case deliberately asks Qt to open a file that is absent, so
# the "Cannot open" scene warning is expected evidence for that negative case,
# never a discarded diagnostic.
if [[ "$primitive_status" -eq 0 ]] && [[ -s "$primitive_result" ]] &&
   runtime_log_is_environment_only "$primitive_log" 'Cannot open' &&
   jq -e '
        .readyStatus == 1 and
        .errorStatus == 3 and
        .nullStatus == 0 and
        .cases.missingPath.hasIcon == false and
        .cases.missingPath.imageVisible == false and
        .cases.missingPath.effectVisible == false and
        .cases.missingPath.imageStatus == .errorStatus and
        .cases.emptySource.hasIcon == false and
        .cases.emptySource.imageVisible == false and
        .cases.emptySource.effectVisible == false and
        .cases.emptySource.imageStatus == .nullStatus and
        .cases.missingName.hasIcon == false and
        .cases.missingName.nameUsable == false and
        .cases.missingName.imageVisible == false and
        .cases.missingName.effectVisible == false and
        .cases.missingName.imageStatus == .nullStatus and
        .cases.validTheme.hasIcon == true and
        .cases.validTheme.imageVisible == true and
        .cases.validTheme.imageStatus == .readyStatus and
        .cases.validTheme.preserveColors == true and
        .cases.logoPath.hasIcon == true and
        .cases.logoPath.imageVisible == true and
        .cases.logoPath.imageStatus == .readyStatus and
        .cases.logoPath.preserveColors == true and
        .cases.symbolicMask.hasIcon == true and
        .cases.symbolicMask.imageVisible == false and
        .cases.symbolicMask.effectVisible == true and
        .cases.symbolicMask.imageStatus == .readyStatus and
        .cases.symbolicMask.preserveColors == false
   ' "$primitive_result" >/dev/null; then
    pass "[isolated-runtime] AureliaIcon draws nothing for a missing path, an empty source and an unknown theme name, while a real theme icon and a real logo path draw with colours preserved and a symbolic mask tints"
elif runtime_log_has_environment_diagnostic "$primitive_log" &&
     runtime_skip_if_environment_only "$primitive_log" "[isolated-runtime] AureliaIcon primitive fixture cannot create a disposable runtime backend"; then
    :
else
    details="$(tr '\n' ' ' <"$primitive_log")"
    if [[ -s "$primitive_result" ]]; then details="$details result=$(tr '\n' ' ' <"$primitive_result")"; fi
    fail "[isolated-runtime] AureliaIcon primitive fixture failed (status=$primitive_status): $details"
fi
