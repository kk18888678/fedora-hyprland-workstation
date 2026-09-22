#!/usr/bin/env bash

# T53 tests for the remaining Omarchy bar interaction and transparent-text
# contract. Runtime checks use only temporary state and disposable media.

set -Eeuo pipefail

section "Omarchy Bar Interaction and Transparency Parity"

bar_root="$ROOT/plugins/aurelia.bar"
bar_file="$bar_root/Bar.qml"
panel_file="$bar_root/BarPanel.qml"
center_file="$bar_root/BarCenter.qml"
slot_file="$bar_root/BarWidgetSlot.qml"
api_file="$ROOT/services/PluginBarApi.qml"
host_file="$ROOT/services/PluginHost.qml"
facade_manager_file="$ROOT/services/PluginFacadeManager.qml"
text_color_bin="$ROOT/bin/aurelia-bar-text-color"

if [[ -x "$text_color_bin" ]] &&
   grep -Fq 'fallback missing-magick' "$text_color_bin" &&
   grep -Fq 'BarInteractionModel.js' "$bar_file" &&
   grep -Fq 'surfaceFormat.opaque: false' "$panel_file" &&
   grep -Fq 'function refreshTransparentForeground' "$bar_file" &&
   grep -Fq 'function beginBarMove' "$bar_file" &&
   grep -Fq 'function beginWidgetDrag' "$bar_file" &&
   grep -Fq 'onDoubleClicked: function(mouse)' "$center_file" &&
   grep -Fq 'onPressAndHold: function(mouse)' "$center_file" &&
   grep -Fq 'DragHandler {' "$slot_file" &&
   grep -Fq 'moveBarWidget' "$bar_file" &&
   ! grep -Fq 'mapFromItem' "$bar_file" "$center_file" "$slot_file" "$panel_file"; then
    pass "[static] bar owns transparent foreground, direct gestures, and safe item-coordinate boundaries"
else
    fail "[static] T53 bar interaction or transparency boundary is incomplete"
fi

if grep -Fq 'property color foreground' "$api_file" &&
   grep -Fq 'property color barForeground' "$api_file" &&
   grep -Fq 'property color background' "$api_file" &&
   grep -Fq 'property color urgent' "$api_file" &&
   grep -Fq 'property bool transparent' "$api_file" &&
   grep -Fq 'api.barForeground' "$facade_manager_file" &&
   grep -Fq 'api.transparent' "$facade_manager_file"; then
    pass "[static] scoped plugin bar facades expose the Omarchy color and transparency contract"
else
    fail "[static] scoped plugin bar facade color propagation is incomplete"
fi

# The helper returns the best-available foreground (never a silent
# theme-foreground degeneration) and emits an explicit halo signal. The
# transparent bar renders no scrim and no surface; its legibility aid is a
# non-surface MultiEffect shadow on the content layer. The theme still floors
# translucent surface opacity while wiring the declared scrim tokens.
if grep -Fq 'reason=insufficient-contrast' "$text_color_bin" &&
   grep -Fq 'action=halo' "$text_color_bin" &&
   grep -Fq 'grayscale Rec709Luminance' "$text_color_bin" &&
   grep -Fq 'transparentForegroundAidStrong' "$bar_file" &&
   grep -Fq 'transparentRender.transparent' "$bar_file" &&
   grep -Fq 'layer.effect: MultiEffect' "$panel_file" &&
   grep -Fq 'shadowEnabled: true' "$panel_file" &&
   ! grep -Fq 'barScrim' "$panel_file" &&
   ! grep -Eq 'scrimStrongAlpha|bar\.scrim' "$ROOT/theme/Theme.qml" "$bar_file" "$panel_file" &&
   grep -Fq 'minimumSurfaceOpacity' "$ROOT/theme/Theme.qml" &&
   grep -Fq '_getSurfaceAlpha("launcher.background-alpha"' "$ROOT/theme/Theme.qml" &&
   grep -Fq '_getSurfaceAlpha("tooltip.background-alpha"' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'Theme.launcher.scrim' "$ROOT/plugins/aurelia.launcher/ui/CommandCenterPanel.qml" &&
   grep -Fq 'Theme.menu.scrim' "$ROOT/plugins/aurelia.menu/Menu.qml"; then
    pass "[static] transparent bar renders no scrim or surface while its non-surface halo keeps content legible and translucent surfaces stay bounded"
else
    fail "[static] bar or translucent-surface legibility guard is incomplete"
fi

model_result="$(node - "$bar_root/BarInteractionModel.js" <<'NODE'
const assert = require('assert');
const model = require(process.argv[2]);

assert.strictEqual(model.exceedsDragThreshold(1, 2, 4), false);
assert.strictEqual(model.exceedsDragThreshold(2, 2, 4), true);
assert.strictEqual(model.exceedsDragThreshold(-3, 2, 4), true);
assert.strictEqual(model.exceedsDragThreshold('bad', 2, 4), false);

assert.strictEqual(model.nearestScreenEdge({x: 320, y: 5}, 640, 360), 'top');
assert.strictEqual(model.nearestScreenEdge({x: 320, y: 355}, 640, 360), 'bottom');
assert.strictEqual(model.nearestScreenEdge({x: 5, y: 180}, 640, 360), 'left');
assert.strictEqual(model.nearestScreenEdge({x: 635, y: 180}, 640, 360), 'right');
assert.strictEqual(model.nearestScreenEdge({}, 640, 360), 'top');

const first = {id: 'first'};
const second = {id: 'second'};
const candidates = [
  {slot: first, x: 10, y: 10, width: 20, height: 30},
  {slot: second, x: 40, y: 10, width: 20, height: 30}
];
assert.deepStrictEqual(model.nearestDropTarget(candidates, {x: 9, y: 20}, false), {slot: first, after: false});
assert.deepStrictEqual(model.nearestDropTarget(candidates, {x: 31, y: 20}, false), {slot: first, after: true});
assert.deepStrictEqual(model.nearestDropTarget(candidates, {x: 61, y: 20}, false), {slot: second, after: true});
assert.deepStrictEqual(model.nearestDropTarget(candidates, {x: 20, y: 9}, true), {slot: first, after: false});
assert.strictEqual(model.nearestDropTarget([], {x: 1, y: 1}, false), null);
assert.deepStrictEqual(model.placementForDrop('aurelia.clock', 'aurelia.weather', 'center', false),
  {section: 'center', before: 'aurelia.weather'});
assert.deepStrictEqual(model.placementForDrop('multi-a', 'multi-b', 'right', true),
  {section: 'right', after: 'multi-b'});
assert.strictEqual(model.placementForDrop('aurelia.clock', 'aurelia.clock', 'center', false), null);
assert.strictEqual(model.placementForDrop('aurelia.clock', 'aurelia.weather', 'middle', false), null);
console.log('bar geometry model ok');
NODE
)"
if [[ "$model_result" == *"bar geometry model ok"* ]]; then
    pass "[isolated-node] edge selection, drag threshold, insertion relation, and invalid geometry are deterministic"
else
    fail "[isolated-node] bar interaction model assertions failed: $model_result"
fi

if [[ ! -x "$(command -v magick  || true)" ||
      ! -x "$(command -v ffmpeg  || true)" ]]; then
    skip "[isolated-media] ImageMagick and ffmpeg are required for transparent foreground sampling"
    return 0
fi

parity_tmp="$(mktemp -d)"
trap 'rm -rf -- "$parity_tmp"  || true' RETURN
magick -size 100x100 xc:'#202020' -fill '#f5f5f5' \
    -draw 'rectangle 0,0 99,19' "$parity_tmp/light.png"
magick -size 100x100 xc:'#f5f5f5' -fill '#202020' \
    -draw 'rectangle 0,0 99,19' "$parity_tmp/dark.png"
# A busy high-variance strip. The alternating dark/light blocks average to a
# misleading mid-tone under a single 1x1 sample, but no candidate foreground
# can stay legible against both extremes.
magick -size 100x100 xc:'#202020' -fill '#ffffff' \
    -draw 'rectangle 0,0 9,19' -draw 'rectangle 20,0 29,19' \
    -draw 'rectangle 40,0 49,19' -draw 'rectangle 60,0 69,19' \
    -draw 'rectangle 80,0 89,19' "$parity_tmp/checker.png"

light_error="$parity_tmp/light.err"
dark_error="$parity_tmp/dark.err"
light_result="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$parity_tmp/light.png" --screen 100x100 2>"$light_error")"
dark_result="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$parity_tmp/dark.png" --screen 100x100 2>"$dark_error")"
if [[ "$light_result" == "#101010" && "$dark_result" == "#ffffff" &&
      ! -s "$light_error" && ! -s "$dark_error" ]]; then
    pass "[isolated-media] transparent foreground selects the higher-contrast color for light and dark still images"
else
    fail "[isolated-media] still-image contrast selection is incorrect: light=$light_result dark=$dark_result"
fi

# The high-variance strip has both a near-black and a near-white region. No
# single foreground clears 4.5:1 against the raw range, so the helper must
# return the best available colour (never a silent theme-foreground
# degeneration) and emit the halo-strengthening signal. Without a surface there
# is no background compositing step.
checker_error="$parity_tmp/checker.err"
checker_result="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$parity_tmp/checker.png" --screen 100x100 2>"$checker_error")"
if [[ "$checker_result" == "#101010" ]] &&
   grep -Fq 'fallback reason=insufficient-contrast' "$checker_error" &&
   grep -Fq 'action=halo' "$checker_error"; then
    pass "[isolated-media] high-variance strip returns the best available foreground and requests the stronger non-surface halo"
else
    fail "[isolated-media] high-variance strip selection is incorrect: $checker_result $(tr '\n' ' ' <"$checker_error")"
fi

# Legacy --scrim arguments must be ignored rather than reintroducing a surface
# selection regression: the transparent bar still chooses against the raw
# wallpaper.
legacy_error="$parity_tmp/checker-legacy.err"
legacy_result="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$parity_tmp/checker.png" --screen 100x100 \
    --scrim '#232136' --scrim-alpha 0.85 2>"$legacy_error")"
if [[ "$legacy_result" == "#101010" ]] &&
   grep -Fq 'action=halo' "$legacy_error"; then
    pass "[isolated-media] legacy scrim arguments are ignored so the transparent bar never regains a surface"
else
    fail "[isolated-media] legacy scrim arguments changed surface-less selection: $legacy_result $(tr '\n' ' ' <"$legacy_error")"
fi

ffmpeg -y -f lavfi -i 'color=c=0x202020:s=100x100:d=1' \
    -vf 'drawbox=x=0:y=0:w=100:h=20:color=0xf5f5f5:t=fill' \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p -loglevel error \
    "$parity_tmp/light.mp4"
video_error="$parity_tmp/video.err"
video_result="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$parity_tmp/light.mp4" --screen 100x100 2>"$video_error")"
if [[ "$video_result" == "#101010" && ! -s "$video_error" ]]; then
    pass "[isolated-media] transparent foreground samples one bounded frame of a video wallpaper"
else
    fail "[isolated-media] video foreground sampling is incorrect: $video_result"
fi

fallback_error="$parity_tmp/fallback.err"
fallback_result="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$parity_tmp/missing.png" --screen 100x100 2>"$fallback_error")"
invalid_error="$parity_tmp/invalid.err"
invalid_result="$("$text_color_bin" diagonal 20 '#ffffff' '#101010' \
    --background "$parity_tmp/light.png" --screen 100x100 2>"$invalid_error")"
if [[ "$fallback_result" == "#ffffff" &&
      "$(tr '\n' ' ' <"$fallback_error")" == *'fallback reason=background-not-file'* &&
      "$invalid_result" == "#ffffff" &&
      "$(tr '\n' ' ' <"$invalid_error")" == *'fallback reason=invalid-position'* ]]; then
    pass "[isolated-media] missing media and invalid arguments fall back visibly without mutating state"
else
    fail "[isolated-media] fallback diagnostics or values are incorrect"
fi

mkdir -p "$parity_tmp/home" "$parity_tmp/state/aurelia/current"
printf '%s\n' "$parity_tmp/light.png" >"$parity_tmp/state/aurelia/current/background.path"
state_error="$parity_tmp/state.err"
state_result="$(HOME="$parity_tmp/home" XDG_STATE_HOME="$parity_tmp/state" \
    "$text_color_bin" top 20 '#ffffff' '#101010' --screen 100x100 2>"$state_error")"
if [[ "$state_result" == "#101010" && ! -s "$state_error" ]]; then
    pass "[isolated-media] default Aurelia XDG background state is consumed without an Omarchy path dependency"
else
    fail "[isolated-media] Aurelia XDG background-state resolution failed: $state_result"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] bar parity QML fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root"  || true' RETURN
mkdir -p "$runtime_root/runtime" "$runtime_root/config" "$runtime_root/state" "$runtime_root/cache"
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
logo_expected_diagnostics='\[BAR\][[:space:]]logo_click_failed[[:space:]](reason=shell_unavailable|result=error)'
: >"$runtime_result"
AURELIA_BAR_PARITY_RESULT="$runtime_result" \
AURELIA_BAR_PARITY_CENTER_SOURCE="$bar_root/BarCenter.qml" \
AURELIA_BAR_PARITY_SLOT_SOURCE="$bar_root/BarWidgetSlot.qml" \
AURELIA_BAR_PARITY_LOGO_SOURCE="$bar_root/AureliaLogo.qml" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" XDG_CONFIG_HOME="$runtime_root/config" \
XDG_STATE_HOME="$runtime_root/state" XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-parity/shell.qml" >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 && -s "$runtime_result" ]] &&
   jq -e '
       .centerConstructed == true and
       .slotConstructed == true and
       .logoConstructed == true and
       .logoActionResult == "ok" and
       .logoPendingResult == "pending" and
       .logoBooleanResult == "ok" and
       .logoFailureResult == "error" and
       .logoUnavailableResult == "not-ready" and
       .facadeTransparent == true and
       .facadeForeground == "#101010" and
       .topEdge == "top" and .bottomEdge == "bottom" and
       .leftEdge == "left" and .rightEdge == "right"
   ' "$runtime_result" >/dev/null &&
   runtime_log_is_environment_only "$runtime_log" "$logo_expected_diagnostics"; then
    pass "[isolated-runtime] center, bar-slot, and logo dispatch components construct with the detached color facade and geometry contract"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    if runtime_log_is_environment_only "$runtime_log" "$logo_expected_diagnostics"; then
        :
    else
        fail "[isolated-runtime] bar parity fixture failed (status=$runtime_status): $details"
    fi
fi

rm -rf -- "$parity_tmp" "$runtime_root"
trap - RETURN
