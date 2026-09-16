# Aurelia wallpaper palette engine.
#
# Reads candidate colors (one #rrggbb per line) on stdin and writes a
# deterministic, data-only colors.toml document to stdout.
#
# Inputs (via -v):
#   mean      #rrggbb average color of the whole image (mode detection)
#   forced    "dark" | "light" | "" (empty uses the mean luminance)
#   source    wallpaper path recorded as provenance
#   digest    sha256 of the wallpaper
#   name      theme slug
#
# Determinism: every selection is derived from sorted luminance/saturation
# order and fixed hue targets, so the same image always produces the same
# palette. No random, no time, no locale-dependent ordering.

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
function mix(r1, g1, b1, r2, g2, b2, amount) {
    return hexof(r1 + (r2 - r1) * amount, g1 + (g2 - g1) * amount, b1 + (b2 - b1) * amount)
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
function emit_roles(   i, slot_index, bright_index, target, pure_hex, normal, bright) {
    targets[1] = 0;   names[1] = "red";     pure_hex[1] = "#ff0000"
    targets[2] = 60;  names[2] = "yellow";  pure_hex[2] = "#ffff00"
    targets[3] = 120; names[3] = "green";   pure_hex[3] = "#00ff00"
    targets[4] = 180; names[4] = "cyan";    pure_hex[4] = "#00ffff"
    targets[5] = 240; names[5] = "blue";    pure_hex[5] = "#0000ff"
    targets[6] = 300; names[6] = "magenta"; pure_hex[6] = "#ff00ff"

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
            # No extracted color is close enough to this hue: derive it from the
            # accent so every ANSI slot always exists.
            normal = mix(pair(accent, 2), pair(accent, 4), pair(accent, 6),
                         pair(pure_hex[i], 2), pair(pure_hex[i], 4), pair(pure_hex[i], 6), 0.6)
            bright = mix(pair(normal, 2), pair(normal, 4), pair(normal, 6),
                         toward_r, toward_g, toward_b, 0.2)
        }
        role[names[i]] = normal
        role["bright_" names[i]] = bright
    }
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

    # Text must stay readable: nudge the foreground towards the opposite end
    # until the WCAG contrast ratio reaches 4.5:1 (bounded, deterministic).
    steps = 0
    while (contrast(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b) < 4.5 && steps < 12) {
        normal = mix(fg_r, fg_g, fg_b, toward_r, toward_g, toward_b, 0.15)
        fg_r = pair(normal, 2); fg_g = pair(normal, 4); fg_b = pair(normal, 6)
        steps++
    }
    foreground = hexof(fg_r, fg_g, fg_b)

    used[bg_index] = 1
    used[fg_index] = 1

    accent_index = accent_index_for(used)
    if (accent_index > 0 && csat[accent_index] >= 0.12) {
        accent = colors[accent_index]
        used[accent_index] = 1
    } else {
        accent = foreground
    }

    emit_roles()

    print "# Generated by aurelia-wallpaper. Data-only: no executable content."
    print "# theme = " name
    print "# source = " source
    print "# sha256 = " digest
    print "mode = \"" theme_mode "\""
    print "accent = \"" accent "\""
    print "selection = \"" mix(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, 0.15) "\""
    print "muted = \"" mix(bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, 0.45) "\""
    print "background = \"" background "\""
    print "foreground = \"" foreground "\""
    print "bright_foreground = \"" mix(fg_r, fg_g, fg_b, toward_r, toward_g, toward_b, 0.15) "\""
    for (i = 1; i <= 6; i++) print names[i] " = \"" role[names[i]] "\""
    for (i = 1; i <= 6; i++) print "bright_" names[i] " = \"" role["bright_" names[i]] "\""
}