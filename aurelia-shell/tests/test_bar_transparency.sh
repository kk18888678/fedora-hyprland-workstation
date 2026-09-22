#!/usr/bin/env bash

# Regression suite for the transparent-bar legibility contract.
#
# With transparency enabled the bar must render NO surface and NO scrim: the
# wallpaper shows through completely. Legibility is provided by the
# best-available foreground from bin/aurelia-bar-text-color plus a non-surface
# content halo (a MultiEffect shadow) that never paints a background plane.
# This suite exercises the real signal parser and surface decision at runtime
# and checks that the transparent path draws no scrim/background and that the
# legibility aid is not a surface.

set -Eeuo pipefail

section "Aurelia Transparent Bar Legibility"

bar_root="$ROOT/plugins/aurelia.bar"
bar_file="$bar_root/Bar.qml"
panel_file="$bar_root/BarPanel.qml"
model_file="$bar_root/BarTransparencyModel.js"
text_color_bin="$ROOT/bin/aurelia-bar-text-color"
theme_file="$ROOT/theme/Theme.qml"

# Runtime exercise of the exact signal parser and surface decision the resident
# bar imports. The former `[[:space:]]` POSIX class silently never matched in
# ECMAScript; these cases fail if the parser regresses to an unsupported token.
model_result="$(node - "$model_file" <<'NODE'
const assert = require('assert');
const model = require(process.argv[2]);

// A real helper diagnostic, wrapped in the bar's console.warn prefix.
const helperLine =
  '[AURELIA-BAR-TEXT] fallback reason=insufficient-contrast worst=1.17 required=4.5 action=halo';
assert.strictEqual(model.parseForegroundSignal(helperLine).strengthenAid, true, 'space-delimited signal');
assert.strictEqual(
  model.parseForegroundSignal('WARN [BAR] transparent_foreground_fallback detail=' + helperLine).strengthenAid,
  true,
  'prefixed signal'
);
assert.strictEqual(model.parseForegroundSignal('action=halo').strengthenAid, true, 'bare signal');
assert.strictEqual(model.parseForegroundSignal('leading\naction=halo\ntrailing').strengthenAid, true, 'newline-delimited signal');
assert.strictEqual(model.parseForegroundSignal('leading\taction=halo\ttrailing').strengthenAid, true, 'tab-delimited signal');
assert.strictEqual(model.parseForegroundSignal('  action=halo  ').strengthenAid, true, 'padded signal');
assert.strictEqual(model.parseForegroundSignal('no-action=halo-here').strengthenAid, false, 'substring must not match');
assert.strictEqual(model.parseForegroundSignal('action=haloish').strengthenAid, false, 'suffix must not match');
assert.strictEqual(model.parseForegroundSignal('action=opaque').strengthenAid, false, 'legacy surface action must not match');
assert.strictEqual(model.parseForegroundSignal('').strengthenAid, false, 'empty detail');
assert.strictEqual(model.parseForegroundSignal(undefined).strengthenAid, false, 'undefined detail');
assert.strictEqual(model.parseForegroundSignal(null).strengthenAid, false, 'null detail');

// Every fallback diagnostic implies an unverified contrast and therefore a
// strong halo, even if the explicit `action=halo` token is missing.
assert.strictEqual(
  model.parseForegroundSignal('[AURELIA-BAR-TEXT] fallback reason=sample-failed action=halo').strengthenAid,
  true,
  'fallback with explicit halo'
);
assert.strictEqual(
  model.parseForegroundSignal('[AURELIA-BAR-TEXT] fallback reason=missing-magick').strengthenAid,
  true,
  'fallback without explicit halo still strengthens'
);
assert.strictEqual(
  model.parseForegroundSignal('fallback reason=background-not-file').strengthenAid,
  true,
  'bare fallback still strengthens'
);
assert.strictEqual(model.parseForegroundSignal('no fallback reason here').strengthenAid, false, 'fallback word alone must not match');

// The rendered surface decision: a requested transparent bar draws no surface
// and no scrim, only the non-surface halo. The halo is unconditionally the
// strong variant: one foreground colour cannot be guaranteed against an
// arbitrary wallpaper, so legibility must not depend on the signal. An opaque
// bar draws the themed surface and no halo.
const opaque = model.renderState(false, false);
assert.deepStrictEqual(opaque, {transparent: false, drawsSurface: true, drawsScrim: false, halo: false, haloStrong: false});
assert.deepStrictEqual(model.renderState(false, true), opaque, 'opaque ignores the halo signal');
const transparent = model.renderState(true, false);
assert.strictEqual(transparent.transparent, true, 'requested transparent stays transparent');
assert.strictEqual(transparent.drawsSurface, false, 'transparent draws no surface');
assert.strictEqual(transparent.drawsScrim, false, 'transparent draws no scrim');
assert.strictEqual(transparent.halo, true, 'transparent enables the non-surface halo');
assert.strictEqual(transparent.haloStrong, true, 'transparent halo is unconditionally strong');
const strong = model.renderState(true, true);
assert.strictEqual(strong.haloStrong, true, 'signal keeps the strong halo');
assert.strictEqual(strong.drawsSurface, false, 'stronger halo is still not a surface');
assert.strictEqual(strong.drawsScrim, false, 'stronger halo is still not a scrim');
console.log('bar transparency model ok');
NODE
)"
if [[ "$model_result" == *"bar transparency model ok"* ]]; then
    pass "[isolated-node] the resident signal parser and surface decision render no scrim/background and keep the halo non-surface"
else
    fail "[isolated-node] bar transparency model assertions failed: $model_result"
fi

# The host must import the shared model, leave `transparent` bound to the
# surface decision, own the contrasting halo colour, and fail safe to the
# strong halo whenever the helper emits a diagnostic or exits non-zero.
if grep -Fq 'import "BarTransparencyModel.js" as BarTransparencyModel' "$bar_file" &&
   grep -Fq 'BarTransparencyModel.parseForegroundSignal' "$bar_file" &&
   grep -Fq 'readonly property bool transparent: transparentRender.transparent' "$bar_file" &&
   grep -Fq 'transparentForegroundAidStrong' "$bar_file" &&
   grep -Fq 'var contrastUnverified = code !== 0 || detail !== ""' "$bar_file" &&
   grep -Fq 'barRoot.transparentForegroundAidStrong = contrastUnverified || signal.strengthenAid' "$bar_file" &&
   grep -Fq 'barRoot.transparentForegroundAidStrong = true' "$bar_file" &&
   grep -Fq 'readonly property color transparentHaloColor' "$bar_file" &&
   ! grep -Fq '[[:space:]]' "$bar_file"; then
    pass "[static] the bar host parses the halo signal, fails safe to the strong halo, and owns the transparent surface decision"
else
    fail "[static] transparent-bar host decision is incomplete"
fi

# The transparent path must draw no background rectangle and no scrim, and its
# only legibility aid is a non-surface MultiEffect shadow on the content. The
# shadow is unconditionally strong: legibility cannot depend on a signal that
# may be missed or malformed.
if grep -Fq 'layer.effect: MultiEffect' "$panel_file" &&
   grep -Fq 'id: legibilityHalo' "$panel_file" &&
   grep -Fq 'shadowEnabled: true' "$panel_file" &&
   grep -Fq 'shadowOpacity: 0.95' "$panel_file" &&
   grep -Fq 'shadowBlur: 0.55' "$panel_file" &&
   grep -Fq '"transparent" : (panelRoot.bar ? panelRoot.bar.background' "$panel_file" &&
   grep -Fq 'border.width: panelRoot.bar && panelRoot.bar.transparent ? 0' "$panel_file" &&
   ! grep -Fq 'barScrim' "$panel_file" &&
   ! grep -Fq 'transparentScrim' "$panel_file" &&
   ! grep -Eq 'scrimAlpha|scrimStrongAlpha|bar\.scrim' "$panel_file" "$bar_file" "$theme_file"; then
    pass "[static] the transparent bar renders no scrim/background and its unconditionally strong legibility aid is not a surface"
else
    fail "[static] transparent-bar no-surface contract is incomplete"
fi

# The luminance sample is parsed as a signed value and clamped to [0,1]. An
# HDRI `%[fx:minima]` can be marginally negative (for example -0.00147364);
# the helper must not reject it as `sample-failed`, must still return the best
# available foreground, and must request the strong halo. A fake sampler is
# used so the signed sample is exercised without depending on a real image.
signal_tmp="$(mktemp -d)"
fake_magick="$signal_tmp/magick"
background_file="$signal_tmp/background.png"
: >"$background_file"
cat >"$fake_magick" <<'EOF_MAGICK'
#!/usr/bin/env bash
printf '%s %s' '-0.00147364' '1.00123456'
EOF_MAGICK
chmod 0755 "$fake_magick"
out_of_range_error="$signal_tmp/out-of-range.err"
out_of_range_color="$(AURELIA_BAR_TEXT_COLOR_MAGICK="$fake_magick" \
    "$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$background_file" --screen 100x100 2>"$out_of_range_error")"
if [[ "$out_of_range_color" == "#101010" ]] &&
   ! grep -Fq 'sample-failed' "$out_of_range_error" &&
   grep -Fq 'action=halo' "$out_of_range_error"; then
    pass "[isolated-media] a signed out-of-range luminance sample is clamped and still requests the strong halo"
else
    fail "[isolated-media] out-of-range luminance sample was rejected: $out_of_range_color $(tr '\n' ' ' <"$out_of_range_error")"
fi

# Every fallback path must imply the strong halo. A fallback means contrast was
# never verified, so failing open would leave content unreadable.
fallback_missing_error="$signal_tmp/missing.err"
fallback_missing_color="$(AURELIA_BAR_TEXT_COLOR_MAGICK="$signal_tmp/does-not-exist" \
    "$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$background_file" --screen 100x100 2>"$fallback_missing_error")"
fallback_position_error="$signal_tmp/position.err"
fallback_position_color="$("$text_color_bin" diagonal 20 '#ffffff' '#101010' \
    --background "$background_file" --screen 100x100 2>"$fallback_position_error")"
if [[ "$fallback_missing_color" == "#ffffff" ]] &&
   grep -Fq 'fallback reason=missing-magick' "$fallback_missing_error" &&
   grep -Fq 'action=halo' "$fallback_missing_error" &&
   [[ "$fallback_position_color" == "#ffffff" ]] &&
   grep -Fq 'fallback reason=invalid-position' "$fallback_position_error" &&
   grep -Fq 'action=halo' "$fallback_position_error"; then
    pass "[isolated-media] every helper fallback diagnostic requests the strong halo"
else
    fail "[isolated-media] a helper fallback did not request the strong halo"
fi
rm -rf -- "$signal_tmp" || true

if [[ ! -x /usr/bin/magick ]]; then
    skip "[isolated-media] ImageMagick is required for the transparent-bar regression"
    return 0
fi

media_tmp="$(mktemp -d)"
trap 'rm -rf -- "$media_tmp" || true' EXIT

# A high-variance strip: alternating near-black and pure-white columns in the
# bar region. No single foreground clears 4.5:1 against the raw range, so the
# helper must return the best available colour (never a silent theme-foreground
# degeneration) and ask for the stronger non-surface halo.
magick -size 100x100 xc:'#202020' -fill '#ffffff' \
    -draw 'rectangle 0,0 9,19' -draw 'rectangle 20,0 29,19' \
    -draw 'rectangle 40,0 49,19' -draw 'rectangle 60,0 69,19' \
    -draw 'rectangle 80,0 89,19' "$media_tmp/checker.png"

checker_error="$media_tmp/checker.err"
checker_color="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$media_tmp/checker.png" --screen 100x100 2>"$checker_error")"
if [[ "$checker_color" == "#101010" ]] &&
   grep -Fq 'fallback reason=insufficient-contrast' "$checker_error" &&
   grep -Fq 'action=halo' "$checker_error"; then
    pass "[isolated-media] the transparent bar keeps the best available foreground and requests only a stronger halo"
else
    fail "[isolated-media] best-available foreground selection is incorrect: $checker_color $(tr '\n' ' ' <"$checker_error")"
fi

# Legacy scrim arguments must not reintroduce a surface-selection regression:
# the transparent bar still chooses against the raw wallpaper.
legacy_error="$media_tmp/legacy.err"
legacy_color="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$media_tmp/checker.png" --screen 100x100 \
    --scrim '#232136' --scrim-alpha 0.85 2>"$legacy_error")"
if [[ "$legacy_color" == "#101010" ]] &&
   grep -Fq 'action=halo' "$legacy_error"; then
    pass "[isolated-media] legacy scrim arguments are ignored so the transparent bar never regains a surface"
else
    fail "[isolated-media] legacy scrim arguments changed surface-less selection: $legacy_color $(tr '\n' ' ' <"$legacy_error")"
fi

# Uniform strips clear WCAG AA against the raw wallpaper: the wallpaper itself
# carries the contrast without any surface or halo request.
magick -size 100x100 xc:'#202020' -fill '#f5f5f5' \
    -draw 'rectangle 0,0 99,19' "$media_tmp/light.png"
magick -size 100x100 xc:'#f5f5f5' -fill '#202020' \
    -draw 'rectangle 0,0 99,19' "$media_tmp/dark.png"
light_error="$media_tmp/light.err"
dark_error="$media_tmp/dark.err"
light_color="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$media_tmp/light.png" --screen 100x100 2>"$light_error")"
dark_color="$("$text_color_bin" top 20 '#ffffff' '#101010' \
    --background "$media_tmp/dark.png" --screen 100x100 2>"$dark_error")"
if [[ "$light_color" == "#101010" && "$dark_color" == "#ffffff" &&
      ! -s "$light_error" && ! -s "$dark_error" ]]; then
    pass "[isolated-media] a uniform wallpaper resolves a legible foreground with no surface and no halo request"
else
    fail "[isolated-media] uniform-wallpaper selection is incorrect: light=$light_color dark=$dark_color"
fi
