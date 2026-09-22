#!/usr/bin/env bash

# Regression suite for the transparent-bar legibility guard.
#
# The user's explicit transparent-bar toggle must stay honoured. The wallpaper
# sampler picks the best available foreground and its fallback signal only
# strengthens the translucent bar-strip scrim; it must never force an opaque
# surface. This suite exercises the real signal parser and render decision at
# runtime and checks that a transparent bar over a high-variance wallpaper
# stays transparent and legible.

set -Eeuo pipefail

section "Aurelia Transparent Bar Legibility"

bar_root="$ROOT/plugins/aurelia.bar"
bar_file="$bar_root/Bar.qml"
panel_file="$bar_root/BarPanel.qml"
model_file="$bar_root/BarTransparencyModel.js"
text_color_bin="$ROOT/bin/aurelia-bar-text-color"
theme_file="$ROOT/theme/Theme.qml"

# Runtime exercise of the exact signal parser the resident bar imports. The
# former `[[:space:]]` POSIX class silently never matched in ECMAScript; these
# cases fail if the parser regresses to an unsupported token.
model_result="$(node - "$model_file" <<'NODE'
const assert = require('assert');
const model = require(process.argv[2]);

// A real helper diagnostic, wrapped in the bar's console.warn prefix.
const helperLine =
  '[AURELIA-BAR-TEXT] fallback reason=insufficient-contrast worst=1.17 required=4.5 action=opaque';
assert.strictEqual(model.parseForegroundSignal(helperLine).strengthenAid, true, 'space-delimited signal');
assert.strictEqual(
  model.parseForegroundSignal('WARN [BAR] transparent_foreground_fallback detail=' + helperLine).strengthenAid,
  true,
  'prefixed signal'
);
assert.strictEqual(model.parseForegroundSignal('action=opaque').strengthenAid, true, 'bare signal');
assert.strictEqual(model.parseForegroundSignal('leading\naction=opaque\ntrailing').strengthenAid, true, 'newline-delimited signal');
assert.strictEqual(model.parseForegroundSignal('leading\taction=opaque\ttrailing').strengthenAid, true, 'tab-delimited signal');
assert.strictEqual(model.parseForegroundSignal('  action=opaque  ').strengthenAid, true, 'padded signal');
assert.strictEqual(model.parseForegroundSignal('no-action=opaque-here').strengthenAid, false, 'substring must not match');
assert.strictEqual(model.parseForegroundSignal('action=opaqueish').strengthenAid, false, 'suffix must not match');
assert.strictEqual(model.parseForegroundSignal('action=transparent').strengthenAid, false, 'other action');
assert.strictEqual(model.parseForegroundSignal('').strengthenAid, false, 'empty detail');
assert.strictEqual(model.parseForegroundSignal(undefined).strengthenAid, false, 'undefined detail');
assert.strictEqual(model.parseForegroundSignal(null).strengthenAid, false, 'null detail');

// The rendered surface decision: a requested transparent bar is never made
// opaque, and the signal only selects the stronger scrim.
assert.deepStrictEqual(model.renderState(true, false, 0.4, 0.85), {transparent: true, scrimAlpha: 0.4});
assert.deepStrictEqual(model.renderState(true, true, 0.4, 0.85), {transparent: true, scrimAlpha: 0.85});
assert.deepStrictEqual(model.renderState(false, false, 0.4, 0.85), {transparent: false, scrimAlpha: 0});
assert.deepStrictEqual(model.renderState(false, true, 0.4, 0.85), {transparent: false, scrimAlpha: 0});
assert.deepStrictEqual(model.renderState(true, true, 0.4, 5), {transparent: true, scrimAlpha: 1});
assert.deepStrictEqual(model.renderState(true, true, 0.4, -1), {transparent: true, scrimAlpha: 0});
console.log('bar transparency model ok');
NODE
)"
if [[ "$model_result" == *"bar transparency model ok"* ]]; then
    pass "[isolated-node] the resident signal parser and render decision keep a requested transparent bar transparent"
else
    fail "[isolated-node] bar transparency model assertions failed: $model_result"
fi

# The host must import the shared model, leave `transparent` bound to the
# render decision, and the panel must own the translucent scrim overlay.
if grep -Fq 'import "BarTransparencyModel.js" as BarTransparencyModel' "$bar_file" &&
   grep -Fq 'BarTransparencyModel.parseForegroundSignal' "$bar_file" &&
   grep -Fq 'readonly property bool transparent: transparentRender.transparent' "$bar_file" &&
   grep -Fq 'transparentForegroundAidStrong' "$bar_file" &&
   grep -Fq 'barScrim' "$panel_file" &&
   grep -Fq 'panelRoot.bar.transparentScrimAlpha' "$panel_file" &&
   grep -Fq 'scrimStrongAlpha' "$theme_file" &&
   ! grep -Fq '[[:space:]]' "$bar_file"; then
    pass "[static] the bar host owns the scrim decision and the panel renders the translucent overlay"
else
    fail "[static] transparent-bar scrim ownership is incomplete"
fi

if [[ ! -x /usr/bin/magick ]]; then
    skip "[isolated-media] ImageMagick is required for the high-variance transparent-bar regression"
    return 0
fi

media_tmp="$(mktemp -d)"
trap 'rm -rf -- "$media_tmp" || true' EXIT

# A high-variance strip: alternating near-black and pure-white columns in the
# bar region. No single foreground clears 4.5:1 against the raw range.
magick -size 100x100 xc:'#202020' -fill '#ffffff' \
    -draw 'rectangle 0,0 9,19' -draw 'rectangle 20,0 29,19' \
    -draw 'rectangle 40,0 49,19' -draw 'rectangle 60,0 69,19' \
    -draw 'rectangle 80,0 89,19' "$media_tmp/checker.png"

# Independent WCAG relative-luminance contrast of a foreground against the
# scrim-composited bar strip. Mirrors the helper's affine compositing so the
# assertion checks the emitted contract, not a second workflow.
rendered_contrast() {
    local fg="$1" lo="$2" hi="$3" scrim="$4" alpha="$5"
    awk -v fg="$fg" -v lo="$lo" -v hi="$hi" -v scrim="$scrim" -v alpha="$alpha" '
        function hv(c) { return index("0123456789abcdef", tolower(c)) - 1 }
        function pair(h, i) { return hv(substr(h, i, 1)) * 16 + hv(substr(h, i + 1, 1)) }
        function lin(v) { v = v / 255; return (v <= 0.03928) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(h) { return 0.2126 * lin(pair(h, 2)) + 0.7152 * lin(pair(h, 4)) + 0.0722 * lin(pair(h, 6)) }
        function ratio(first, second, swap) {
            if (first < second) { swap = first; first = second; second = swap }
            return (first + 0.05) / (second + 0.05)
        }
        BEGIN {
            scrim_luminance = lum(scrim)
            effective_low = alpha * scrim_luminance + (1 - alpha) * (lo + 0)
            effective_high = alpha * scrim_luminance + (1 - alpha) * (hi + 0)
            fg_luminance = lum(fg)
            low_ratio = ratio(fg_luminance, effective_low)
            high_ratio = ratio(fg_luminance, effective_high)
            printf "%.4f\n", low_ratio < high_ratio ? low_ratio : high_ratio
        }'
}

raw_range="$(magick "$media_tmp/checker.png" -auto-orient \
    -resize '100x100^' -gravity center -extent '100x100' \
    -gravity NorthWest -crop '100x20+0+0' +repage \
    -colorspace sRGB -background '#808080' -alpha remove \
    -grayscale Rec709Luminance \
    -format '%[fx:minima] %[fx:maxima]' info:-)"
raw_low="${raw_range%% *}"
raw_high="${raw_range##* }"

# Default scrim: the light candidate wins, but the strip is still short of AA,
# so the helper emits the strengthening signal the bar uses to select the
# strong scrim alpha.
default_error="$media_tmp/default.err"
default_color="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$media_tmp/checker.png" --screen 100x100 \
    --scrim '#232136' --scrim-alpha 0.4 2>"$default_error")"
if [[ "$default_color" == "#ffffff" ]] &&
   grep -Fq 'fallback reason=insufficient-contrast' "$default_error" &&
   grep -Fq 'action=opaque' "$default_error"; then
    pass "[isolated-media] the high-variance strip signals a stronger scrim for the light best-available foreground"
else
    fail "[isolated-media] default-scrim selection is incorrect: $default_color $(tr '\n' ' ' <"$default_error")"
fi

# Strong scrim: the same transparent surface now clears AA. Assert the helper
# emits no signal and independently verify the rendered contrast.
strong_error="$media_tmp/strong.err"
strong_color="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$media_tmp/checker.png" --screen 100x100 \
    --scrim '#232136' --scrim-alpha 0.85 2>"$strong_error")"
strong_ratio="$(rendered_contrast "$strong_color" "$raw_low" "$raw_high" '#232136' 0.85)"
if [[ "$strong_color" == "#ffffff" && ! -s "$strong_error" ]] &&
   awk -v ratio="$strong_ratio" 'BEGIN { exit !(ratio + 0 >= 4.5) }'; then
    pass "[isolated-media] the transparent bar over the high-variance wallpaper stays transparent and clears WCAG AA (ratio=$strong_ratio)"
else
    fail "[isolated-media] strong-scrim legibility is incorrect: color=$strong_color ratio=$strong_ratio $(tr '\n' ' ' <"$strong_error")"
fi

# The helper must never silently degenerate to the theme foreground: on the
# raw high-variance strip the best available candidate is the contrast colour
# (#101010), so that is what it returns even though it still signals.
still_error="$media_tmp/still.err"
still_result="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$media_tmp/checker.png" --screen 100x100 2>"$still_error")"
if [[ "$still_result" == "#101010" ]] &&
   grep -Fq 'action=opaque' "$still_error"; then
    pass "[isolated-media] the best available candidate is returned instead of degenerating to the theme foreground"
else
    fail "[isolated-media] best-available selection degenerated: raw=$still_result $(tr '\n' ' ' <"$still_error")"
fi
