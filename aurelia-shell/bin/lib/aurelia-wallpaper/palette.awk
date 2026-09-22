# Aurelia wallpaper palette engine.
#
# Reads candidate colors (one #rrggbb per line) on stdin and writes a
# deterministic, data-only colors.toml document to stdout.
#
# Inputs (via -v):
#   mean        #rrggbb average color of the whole image (mode detection)
#   forced      "dark" | "light" | "" (empty uses the mean luminance)
#   source      wallpaper path recorded as provenance
#   digest      sha256 of the wallpaper
#   name        theme slug
#   mode        extraction mode:
#               normal|monochromatic|analogous|pastel|material|colorful|muted|bright
#   gamma       lightness curve, 0.5..2.0 (default 1.0)
#   adj_*       fine-tuning values (0 means "no change"):
#               adj_vibrance, adj_saturation, adj_contrast, adj_brightness,
#               adj_shadows, adj_highlights, adj_black_point, adj_white_point,
#               adj_hue_shift, adj_temperature, adj_tint
#
# Determinism: every selection is derived from sorted luminance/saturation
# order and fixed hue targets, so the same image and the same recipe always
# produce the same palette. No random, no time, no locale-dependent ordering.

function afabs(value) { return (value < 0) ? -value : value }
function hex_value(char) { return index("0123456789abcdef", tolower(char)) - 1 }
function pair(hex, idx) { return hex_value(substr(hex, idx, 1)) * 16 + hex_value(substr(hex, idx + 1, 1)) }
function rl(rr, gg, bb) {
    # WCAG relative luminance.
    return 0.2126 * linear(rr) + 0.7152 * linear(gg) + 0.0722 * linear(bb)
}
function linear(value) {
    value = value / 255
    return (value <= 0.04045) ? value / 12.92 : ((value + 0.055) / 1.055) ^ 2.4
}
function contrast(r1, g1, b1, r2, g2, b2,   l1, l2, swap) {
    l1 = rl(r1, g1, b1)
    l2 = rl(r2, g2, b2)
    if (l1 < l2) { swap = l1; l1 = l2; l2 = swap }
    return (l1 + 0.05) / (l2 + 0.05)
}
function hexof(rr, gg, bb) { return sprintf("#%02x%02x%02x", clamp(rr), clamp(gg), clamp(bb)) }
function clamp(value) {
    value = int(value + 0.5)
    if (value < 0) return 0
    if (value > 255) return 255
    return value
}
function clamp01(value) {
    if (value < 0) return 0
    if (value > 1) return 1
    return value
}
function mix(r1, g1, b1, r2, g2, b2, amount) {
    return hexof(r1 + (r2 - r1) * amount, g1 + (g2 - g1) * amount, b1 + (b2 - b1) * amount)
}

# WCAG text/UI roles derived from the background/foreground anchors. Every
# helper below is fail-closed: the returned color meets its documented minimum
# for any background.

# Move a color toward the mode's contrast pole until it clears `minimum`. If the
# bounded nudge loop is still short, escalate to the pure pole (white or black)
# that yields the highest possible contrast. Escalation guarantees the minimum
# because max(contrast_white, contrast_black) is always >= 4.58 for any
# background, so a sub-4.5 pair can never be emitted silently.
function enforce_min(hex, bgr, bgg, bgb, minimum, to_r, to_g, to_b,
                     fgr, fgg, fgb, candidate, steps) {
    fgr = pair(hex, 2); fgg = pair(hex, 4); fgb = pair(hex, 6)
    steps = 0
    while (contrast(bgr, bgg, bgb, fgr, fgg, fgb) < minimum && steps < 12) {
        candidate = mix(fgr, fgg, fgb, to_r, to_g, to_b, 0.15)
        fgr = pair(candidate, 2); fgg = pair(candidate, 4); fgb = pair(candidate, 6)
        steps++
    }
    if (contrast(bgr, bgg, bgb, fgr, fgg, fgb) < minimum) {
        if (contrast(bgr, bgg, bgb, 255, 255, 255) >= contrast(bgr, bgg, bgb, 0, 0, 0)) {
            fgr = 255; fgg = 255; fgb = 255
        } else {
            fgr = 0; fgg = 0; fgb = 0
        }
    }
    return hexof(fgr, fgg, fgb)
}

# A dimmer text role derived by mixing the background toward the foreground.
# The requested dimness is preserved unless it would violate `minimum`, in
# which case the role is pulled toward the foreground (which already clears the
# text minimum) until the ratio is met.
function text_role(bgr, bgg, bgb, fgr, fgg, fgb, start, minimum,
                   t, candidate, ratio) {
    t = start
    candidate = mix(bgr, bgg, bgb, fgr, fgg, fgb, t)
    while (t < 1.0) {
        ratio = contrast(bgr, bgg, bgb, pair(candidate, 2), pair(candidate, 4), pair(candidate, 6))
        if (ratio >= minimum) return candidate
        t = t + 0.05
        if (t > 1.0) t = 1.0
        candidate = mix(bgr, bgg, bgb, fgr, fgg, fgb, t)
    }
    return hexof(fgr, fgg, fgb)
}

# An elevation surface between background and foreground. Surfaces are not text
# colors, but text is commonly drawn on them, so the largest elevation that
# still keeps the foreground at 4.5:1 is used. The foreground already clears
# 4.5:1 against the background, so t = 0 is always a valid fallback.
function elevate_surface(bgr, bgg, bgb, fgr, fgg, fgb, start,
                         t, candidate, ratio) {
    t = start
    while (t > 0) {
        candidate = mix(bgr, bgg, bgb, fgr, fgg, fgb, t)
        ratio = contrast(fgr, fgg, fgb, pair(candidate, 2), pair(candidate, 4), pair(candidate, 6))
        if (ratio >= 4.5) return candidate
        t = t - 0.02
        if (t < 0) t = 0
    }
    return hexof(bgr, bgg, bgb)
}

function brightness(rr, gg, bb) { return (rr + gg + bb) / 765 }
function saturation(rr, gg, bb,   mx, mn) {
    mx = max3(rr, gg, bb)
    mn = min3(rr, gg, bb)
    if (mx <= 0) return 0
    return (mx - mn) / mx
}
function max3(a, b, c) { return (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c) }
function min3(a, b, c) { return (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c) }
function hue(rr, gg, bb,   mx, mn, delta, value) {
    mx = max3(rr, gg, bb)
    mn = min3(rr, gg, bb)
    delta = mx - mn
    if (delta == 0) return -1
    if (mx == rr) value = 60 * (((gg - bb) / delta) % 6)
    else if (mx == gg) value = 60 * (((bb - rr) / delta) + 2)
    else value = 60 * (((rr - gg) / delta) + 4)
    if (value < 0) value += 360
    return value
}
function hue_distance(a, b,   d) {
    if (a < 0) return 999
    d = a - b
    if (d < 0) d = -d
    if (d > 180) d = 360 - d
    return d
}

# RGB <-> HSL. Results are returned through the mh/ms/ml and out_r/out_g/out_b
# globals because awk functions cannot return tuples.
function rgb_to_hsl(rr, gg, bb,   mx, mn, d, r, g, b) {
    r = rr / 255; g = gg / 255; b = bb / 255
    mx = max3(r, g, b); mn = min3(r, g, b)
    ml = (mx + mn) / 2
    d = mx - mn
    if (d == 0) { mh = 0; ms = 0; return }
    ms = (ml > 0.5) ? d / (2 - mx - mn) : d / (mx + mn)
    if (mx == r) mh = 60 * (((g - b) / d) % 6)
    else if (mx == g) mh = 60 * (((b - r) / d) + 2)
    else mh = 60 * (((r - g) / d) + 4)
    if (mh < 0) mh += 360
}
function hsl_to_rgb(h, s, l,   c, x, m, r, g, b, hp) {
    h = h % 360
    if (h < 0) h += 360
    c = (1 - afabs(2 * l - 1)) * s
    hp = h / 60
    x = c * (1 - afabs((hp % 2) - 1))
    if (hp < 1) { r = c; g = x; b = 0 }
    else if (hp < 2) { r = x; g = c; b = 0 }
    else if (hp < 3) { r = 0; g = c; b = x }
    else if (hp < 4) { r = 0; g = x; b = c }
    else if (hp < 5) { r = x; g = 0; b = c }
    else { r = c; g = 0; b = x }
    m = l - c / 2
    out_r = clamp((r + m) * 255)
    out_g = clamp((g + m) * 255)
    out_b = clamp((b + m) * 255)
}

function prepare(   i) {
    for (i = 1; i <= count; i++) {
        cr[i] = pair(colors[i], 2)
        cg[i] = pair(colors[i], 4)
        cb[i] = pair(colors[i], 6)
        clum[i] = brightness(cr[i], cg[i], cb[i])
        csat[i] = saturation(cr[i], cg[i], cb[i])
        chue[i] = hue(cr[i], cg[i], cb[i])
    }
}

function add_color(hex) {
    if (seen[hex]++) return
    count++
    colors[count] = hex
}

# A flat or nearly monochrome wallpaper must still yield a usable palette.
# Missing entries are synthesized by mixing the extracted extremes toward black
# and white, which keeps the result derivable from the image itself.
function augment(   i, deepest, lightest, before) {
    prepare()
    while (count < 8) {
        deepest = 1
        lightest = 1
        for (i = 2; i <= count; i++) {
            if (clum[i] < clum[deepest]) deepest = i
            if (clum[i] > clum[lightest]) lightest = i
        }
        before = count
        add_color(mix(cr[lightest], cg[lightest], cb[lightest], 255, 255, 255, 0.35))
        add_color(mix(cr[deepest], cg[deepest], cb[deepest], 0, 0, 0, 0.35))
        add_color(mix(cr[lightest], cg[lightest], cb[lightest], 0, 0, 0, 0.30))
        add_color(mix(cr[deepest], cg[deepest], cb[deepest], 255, 255, 255, 0.30))
        if (count == before) break
        prepare()
    }
}

# The hue anchor for monochromatic/analogous modes is the hue of the most
# saturated extracted color (deterministic tie-break by hex order).
function base_hue_for(   i, best, best_sat) {
    best = 0
    best_sat = -1
    for (i = 1; i <= count; i++) {
        if (csat[i] > best_sat) { best_sat = csat[i]; best = i }
    }
    if (best == 0) return 0
    if (chue[best] < 0) return 0
    return chue[best]
}

function nearest_material_hue(h,   i, best, best_distance, distance) {
    best = MAT[1]
    best_distance = 999
    for (i = 1; i <= 15; i++) {
        distance = hue_distance(h, MAT[i])
        if (distance < best_distance) {
            best_distance = distance
            best = MAT[i]
        }
    }
    return best
}

# Extraction modes change the palette character before fine-tuning.
function apply_mode(h, s, l) {
    if (mode == "monochromatic") {
        h = base_h + ((h - base_h + 540) % 360 - 180) * 0.12
    } else if (mode == "analogous") {
        h = base_h + ((h - base_h + 540) % 360 - 180) * 0.28
    } else if (mode == "pastel") {
        s = s * 0.55
        l = 0.56 + l * 0.34
    } else if (mode == "material") {
        h = nearest_material_hue(h)
        s = (s < 0.35) ? 0.35 : ((s > 0.82) ? 0.82 : s)
        l = 0.34 + l * 0.32
    } else if (mode == "colorful") {
        s = clamp01(s * 1.5)
        if (l < 0.34) l = 0.34
        if (l > 0.72) l = 0.72
    } else if (mode == "muted") {
        s = s * 0.35
        l = 0.12 + l * 0.78
    } else if (mode == "bright") {
        s = s * 0.80
        l = 0.55 + l * 0.42
    }
    mh = h
    ms = clamp01(s)
    ml = clamp01(l)
}

# Twelve fine-tuning controls, applied in HSL plus a final RGB tone step.
function apply_adjustments(   h, s, l) {
    h = mh; s = ms; l = ml

    if (adj_saturation != 0) s = s * (1 + adj_saturation / 100)
    if (adj_vibrance != 0) {
        if (adj_vibrance > 0)
            s = s + (adj_vibrance / 50) * (1 - s) * (1 - s) * 0.5
        else
            s = s + (adj_vibrance / 50) * s * 0.5
    }
    if (adj_contrast != 0) l = 0.5 + (l - 0.5) * (1 + adj_contrast / 30)
    if (adj_brightness != 0) l = l + adj_brightness / 100 * 0.30
    if (adj_shadows != 0 && l < 0.5) l = l + (adj_shadows / 50) * (0.5 - l) * 0.5
    if (adj_highlights != 0 && l >= 0.5) l = l + (adj_highlights / 50) * (1 - l) * 0.5
    if (gamma > 0 && gamma != 1) l = l ^ (1 / gamma)
    if (adj_black_point != 0) l = l + adj_black_point / 100 * 0.10
    if (adj_white_point != 0) l = l + adj_white_point / 100 * 0.10
    if (adj_hue_shift != 0) h = h + adj_hue_shift

    mh = h
    ms = clamp01(s)
    ml = clamp01(l)
}

# Warm/cool and green/magenta casts are more natural in RGB.
function apply_rgb_tone() {
    if (adj_temperature != 0) {
        out_r = out_r + adj_temperature * 2.2
        out_b = out_b - adj_temperature * 2.2
    }
    if (adj_tint != 0) {
        out_g = out_g - adj_tint * 1.6
        out_r = out_r + adj_tint * 0.8
        out_b = out_b + adj_tint * 0.8
    }
    out_r = clamp(out_r)
    out_g = clamp(out_g)
    out_b = clamp(out_b)
}

# Rebuild the palette array from the transformed colors, dropping duplicates
# that a strong mode (for example monochromatic) may have produced.
function compact(   i, kept) {
    delete seen
    kept = 0
    for (i = 1; i <= count; i++) {
        if (seen[colors[i]]++) continue
        kept++
        compact_colors[kept] = colors[i]
    }
    count = kept
    for (i = 1; i <= count; i++) colors[i] = compact_colors[i]
}

function transform_all(   i) {
    base_h = base_hue_for()
    for (i = 1; i <= count; i++) {
        rgb_to_hsl(cr[i], cg[i], cb[i])
        apply_mode(mh, ms, ml)
        apply_adjustments()
        hsl_to_rgb(mh, ms, ml)
        apply_rgb_tone()
        cr[i] = out_r
        cg[i] = out_g
        cb[i] = out_b
        colors[i] = hexof(out_r, out_g, out_b)
    }
    compact()
    # A transform can collapse the set below the usable minimum, so top it up
    # again from the transformed extremes.
    augment()
}

function sort_by_luminance(   i, j, key_lum, key_hex, key_r, key_g, key_b, key_s, key_h) {
    for (i = 2; i <= count; i++) {
        key_lum = clum[i]; key_hex = colors[i]; key_r = cr[i]; key_g = cg[i]
        key_b = cb[i]; key_s = csat[i]; key_h = chue[i]
        j = i - 1
        while (j >= 1 && (clum[j] > key_lum || (clum[j] == key_lum && colors[j] > key_hex))) {
            clum[j + 1] = clum[j]; colors[j + 1] = colors[j]; cr[j + 1] = cr[j]
            cg[j + 1] = cg[j]; cb[j + 1] = cb[j]; csat[j + 1] = csat[j]; chue[j + 1] = chue[j]
            j--
        }
        clum[j + 1] = key_lum; colors[j + 1] = key_hex; cr[j + 1] = key_r
        cg[j + 1] = key_g; cb[j + 1] = key_b; csat[j + 1] = key_s; chue[j + 1] = key_h
    }
}

function nearest_hue(target, used,   i, best, best_distance, distance) {
    best = 0
    best_distance = 999
    for (i = 1; i <= count; i++) {
        if (used[i]) continue
        if (csat[i] < 0.08) continue
        distance = hue_distance(chue[i], target)
        if (distance < best_distance) {
            best_distance = distance
            best = i
        }
    }
    return best
}

function most_saturated(used,   i, best, best_saturation) {
    best = 0
    best_saturation = -1
    for (i = 1; i <= count; i++) {
        if (used[i]) continue
        if (csat[i] > best_saturation) {
            best_saturation = csat[i]
            best = i
        }
    }
    return best
}

# The accent becomes the visible highlight color, so it must be vivid without
# being nearly black or nearly white. Colors outside a usable luminance band are
# only considered when the image offers nothing else.
function accent_index_for(used,   i, best, best_score, score) {
    best = 0
    best_score = -1
    for (i = 1; i <= count; i++) {
        if (used[i]) continue
        if (clum[i] < 0.15 || clum[i] > 0.85) continue
        score = csat[i] - 0.25 * ((clum[i] > 0.5) ? (clum[i] - 0.5) : (0.5 - clum[i]))
        if (score > best_score) {
            best_score = score
            best = i
        }
    }
    if (best == 0) best = most_saturated(used)
    return best
}
# When the image offers no color near an ANSI hue, derive the slot from the
# accent by re-hueing it in HSL. This preserves the palette's saturation and
# lightness character (a desaturated palette stays desaturated) instead of
# reintroducing a pure primary color.
function derive_from_accent(target,   s, l) {
    rgb_to_hsl(pair(accent, 2), pair(accent, 4), pair(accent, 6))
    s = clamp01(ms * 1.15)
    l = ml
    hsl_to_rgb(target, s, l)
    return hexof(out_r, out_g, out_b)
}
function emit_roles(   i, slot_index, bright_index, target, normal, bright) {
    targets[1] = 0;   names[1] = "red"
    targets[2] = 60;  names[2] = "yellow"
    targets[3] = 120; names[3] = "green"
    targets[4] = 180; names[4] = "cyan"
    targets[5] = 240; names[5] = "blue"
    targets[6] = 300; names[6] = "magenta"

    for (i = 1; i <= 6; i++) {
        target = targets[i]
        slot_index = nearest_hue(target, used)
        if (slot_index > 0 && hue_distance(chue[slot_index], target) <= 60) {
            normal = colors[slot_index]
            used[slot_index] = 1
            bright_index = nearest_hue(target, used)
            if (bright_index > 0 && clum[bright_index] >= clum[slot_index]) {
                bright = colors[bright_index]
                used[bright_index] = 1
            } else {
                bright = mix(cr[slot_index], cg[slot_index], cb[slot_index],
                             toward_r, toward_g, toward_b, 0.2)
            }
        } else {
            normal = derive_from_accent(target)
            bright = mix(pair(normal, 2), pair(normal, 4), pair(normal, 6),
                         toward_r, toward_g, toward_b, 0.2)
        }
        role[names[i]] = normal
        role["bright_" names[i]] = bright
    }
}

BEGIN {
    MAT[1] = 0; MAT[2] = 14; MAT[3] = 36; MAT[4] = 45; MAT[5] = 54
    MAT[6] = 66; MAT[7] = 88; MAT[8] = 122; MAT[9] = 174; MAT[10] = 187
    MAT[11] = 210; MAT[12] = 230; MAT[13] = 260; MAT[14] = 270; MAT[15] = 330
    if (mode == "") mode = "normal"
    if (gamma == "") gamma = 1
    if (forced != "dark" && forced != "light") forced = ""
    if (name == "") name = "wallpaper"
    if (adj_vibrance == "") adj_vibrance = 0
    if (adj_saturation == "") adj_saturation = 0
    if (adj_contrast == "") adj_contrast = 0
    if (adj_brightness == "") adj_brightness = 0
    if (adj_shadows == "") adj_shadows = 0
    if (adj_highlights == "") adj_highlights = 0
    if (adj_black_point == "") adj_black_point = 0
    if (adj_white_point == "") adj_white_point = 0
    if (adj_hue_shift == "") adj_hue_shift = 0
    if (adj_temperature == "") adj_temperature = 0
    if (adj_tint == "") adj_tint = 0
    # ImageMagick emits uppercase hex in `txt:` output; the mode gate below is
    # lowercase, so normalize once here to keep dark wallpapers dark.
    mean = tolower(mean)
}

{
    hex = tolower($0)
    if (hex !~ /^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/) next
    add_color(hex)
}

END {
    if (count < 2) {
        print "palette: fewer than two distinct colors were extracted" > "/dev/stderr"
        exit 1
    }

    augment()
    transform_all()
    prepare()
    sort_by_luminance()

    if (forced == "dark" || forced == "light") {
        theme_mode = forced
    } else if (mean ~ /^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/) {
        theme_mode = ((pair(mean, 2) + pair(mean, 4) + pair(mean, 6)) > 382) ? "light" : "dark"
    } else {
        theme_mode = (clum[count] > 0.5) ? "light" : "dark"
    }

    if (theme_mode == "dark") {
        bg_index = 1
        fg_index = count
        toward_r = 255; toward_g = 255; toward_b = 255
    } else {
        bg_index = count
        fg_index = 1
        toward_r = 0; toward_g = 0; toward_b = 0
    }

    background = colors[bg_index]
    bg_r = cr[bg_index]; bg_g = cg[bg_index]; bg_b = cb[bg_index]
    fg_r = cr[fg_index]; fg_g = cg[fg_index]; fg_b = cb[fg_index]

    # Text must stay readable. The bounded nudge loop moves the foreground
    # toward the mode's contrast pole; if that is still short of 4.5:1 the
    # foreground is escalated to the pure pole (white or black) with the
    # highest possible contrast. The contract is therefore fail-closed: the
    # emitted foreground always meets 4.5:1 against the emitted background.
    foreground = enforce_min(hexof(fg_r, fg_g, fg_b), bg_r, bg_g, bg_b, 4.5,
                             toward_r, toward_g, toward_b)
    fg_r = pair(foreground, 2); fg_g = pair(foreground, 4); fg_b = pair(foreground, 6)

    used[bg_index] = 1
    used[fg_index] = 1

    accent_index = accent_index_for(used)
    if (accent_index > 0 && csat[accent_index] >= 0.12) {
        accent = colors[accent_index]
        used[accent_index] = 1
    } else {
        accent = foreground
    }
    # accent is a text/icon role and must clear the WCAG non-text/UI threshold
    # of 3.0:1 against the background (see docs/aurelia-wallpapers.md).
    accent = enforce_min(accent, bg_r, bg_g, bg_b, 3.0, toward_r, toward_g, toward_b)

    # Text-bearing roles, each pinned to its documented minimum:
    #   muted            >= 4.5:1 against the background
    #   light_foreground >= 4.5:1 against the background (secondary text)
    #   dark_foreground  >= 3.0:1 against the background (subtle text)
    muted = text_role(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, 0.45, 4.5)
    light_foreground = text_role(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, 0.75, 4.5)
    dark_foreground = text_role(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, 0.40, 3.0)

    # Non-text surfaces derived from the anchors. selection is a background for
    # selected rows, not a text color, so it is explicitly exempt from the text
    # contrast minimums. Every surface is still bounded so text drawn on it
    # keeps the foreground's 4.5:1 ratio.
    surface = elevate_surface(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, 0.06)
    lighter_background = surface
    surfaceElevated = elevate_surface(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, 0.12)
    selection = elevate_surface(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, 0.15)

    emit_roles()

    print "# Generated by aurelia-wallpaper. Data-only: no executable content."
    print "# theme = " name
    print "# source = " source
    print "# sha256 = " digest
    print "# extraction_mode = " mode
    print "# adjustments = vibrance=" adj_vibrance " saturation=" adj_saturation \
        " contrast=" adj_contrast " brightness=" adj_brightness \
        " shadows=" adj_shadows " highlights=" adj_highlights \
        " gamma=" gamma " black_point=" adj_black_point \
        " white_point=" adj_white_point " hue_shift=" adj_hue_shift \
        " temperature=" adj_temperature " tint=" adj_tint
    print "mode = \"" theme_mode "\""
    print "extraction_mode = \"" mode "\""
    print "accent = \"" accent "\""
    print "selection = \"" selection "\""
    print "muted = \"" muted "\""
    print "background = \"" background "\""
    print "foreground = \"" foreground "\""
    print "surface = \"" surface "\""
    print "surfaceElevated = \"" surfaceElevated "\""
    print "lighter_background = \"" lighter_background "\""
    print "light_foreground = \"" light_foreground "\""
    print "dark_foreground = \"" dark_foreground "\""
    print "bright_foreground = \"" mix(fg_r, fg_g, fg_b, toward_r, toward_g, toward_b, 0.15) "\""
    for (i = 1; i <= 6; i++) print names[i] " = \"" role[names[i]] "\""
    for (i = 1; i <= 6; i++) print "bright_" names[i] " = \"" role["bright_" names[i]] "\""
}
