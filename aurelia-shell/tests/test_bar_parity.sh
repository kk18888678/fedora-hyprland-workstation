#!/usr/bin/env bash

# T53 tests for the remaining Omarchy bar interaction and transparent-text
# contract. Runtime checks use only temporary state and disposable media.

set -Eeuo pipefail

section "Omarchy Bar Interaction and Transparency Parity"

bar_root="$ROOT/plugins/aurelia.bar"
bar_file="$bar_root/Bar.qml"
center_file="$bar_root/BarCenter.qml"
slot_file="$bar_root/BarWidgetSlot.qml"
api_file="$ROOT/services/PluginBarApi.qml"
host_file="$ROOT/services/PluginHost.qml"
text_color_bin="$ROOT/bin/aurelia-bar-text-color"

if [[ -x "$text_color_bin" ]] &&
   grep -Fq 'BarInteractionModel.js' "$bar_file" &&
   grep -Fq 'surfaceFormat.opaque: false' "$bar_file" &&
   grep -Fq 'function refreshTransparentForeground' "$bar_file" &&
   grep -Fq 'function beginBarMove' "$bar_file" &&
   grep -Fq 'function beginWidgetDrag' "$bar_file" &&
   grep -Fq 'onDoubleClicked: function(mouse)' "$center_file" &&
   grep -Fq 'onPressAndHold: function(mouse)' "$center_file" &&
   grep -Fq 'DragHandler {' "$slot_file" &&
   grep -Fq 'moveBarWidget' "$bar_file" &&
   ! grep -Fq 'mapFromItem' "$bar_file" "$center_file" "$slot_file"; then
    pass "[static] bar owns transparent foreground, direct gestures, and safe item-coordinate boundaries"
else
    fail "[static] T53 bar interaction or transparency boundary is incomplete"
fi

if grep -Fq 'property color foreground' "$api_file" &&
   grep -Fq 'property color barForeground' "$api_file" &&
   grep -Fq 'property color background' "$api_file" &&
   grep -Fq 'property color urgent' "$api_file" &&
   grep -Fq 'property bool transparent' "$api_file" &&
   grep -Fq 'api.barForeground' "$host_file" &&
   grep -Fq 'api.transparent' "$host_file"; then
    pass "[static] scoped plugin bar facades expose the Omarchy color and transparency contract"
else
    fail "[static] scoped plugin bar facade color propagation is incomplete"
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

if [[ ! -x "$(command -v magick 2>/dev/null || true)" ||
      ! -x "$(command -v ffmpeg 2>/dev/null || true)" ]]; then
    skip "[isolated-media] ImageMagick and ffmpeg are required for transparent foreground sampling"
    return 0
fi

parity_tmp="$(mktemp -d)"
trap 'rm -rf -- "$parity_tmp" 2>/dev/null || true' RETURN
magick -size 100x100 xc:'#202020' -fill '#f5f5f5' \
    -draw 'rectangle 0,0 99,19' "$parity_tmp/light.png"
magick -size 100x100 xc:'#f5f5f5' -fill '#202020' \
    -draw 'rectangle 0,0 99,19' "$parity_tmp/dark.png"

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
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p "$runtime_root/runtime" "$runtime_root/config" "$runtime_root/state" "$runtime_root/cache"
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
: >"$runtime_result"
AURELIA_BAR_PARITY_RESULT="$runtime_result" \
AURELIA_BAR_PARITY_CENTER_SOURCE="$bar_root/BarCenter.qml" \
AURELIA_BAR_PARITY_SLOT_SOURCE="$bar_root/BarWidgetSlot.qml" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" XDG_CONFIG_HOME="$runtime_root/config" \
XDG_STATE_HOME="$runtime_root/state" XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-parity/shell.qml" >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 && -s "$runtime_result" ]] &&
   jq -e '
       .centerConstructed == true and
       .slotConstructed == true and
       .facadeTransparent == true and
       .facadeForeground == "#101010" and
       .topEdge == "top" and .bottomEdge == "bottom" and
       .leftEdge == "left" and .rightEdge == "right"
   ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] the real center and bar-slot QML components construct with the detached color facade and geometry contract"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    if runtime_log_is_environment_only "$runtime_log" "[isolated-runtime] bar parity fixture cannot create a disposable runtime backend"; then
        :
    else
        fail "[isolated-runtime] bar parity fixture failed (status=$runtime_status): $details"
    fi
fi

rm -rf -- "$parity_tmp" "$runtime_root"
trap - RETURN
