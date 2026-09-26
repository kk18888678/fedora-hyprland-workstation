#!/usr/bin/env bash

# Theme-wide font-family resolution contract.
#
# Qt's Text.font.family accepts a SINGLE family name; it does not parse a
# comma-separated list. The theme's `fontFamily` value is therefore a preference
# order that must be resolved to one family before it reaches Qt. This suite
# pins that resolution point and proves, by runtime measurement in the isolated
# offscreen harness, that the bar's TEXT and its ICONS resolve to the SAME
# family.

set -Eeuo pipefail

theme_qml="$ROOT/theme/Theme.qml"
theme_conf="$ROOT/theme.conf"
icon_qml="$ROOT/ui/AureliaIcon.qml"
fixture="$ROOT/tests/fixtures/font-family/shell.qml"
clock_source="file://$ROOT/plugins/aurelia.clock/ClockBarWidget.qml"
icon_source="file://$ROOT/ui/AureliaIcon.qml"

section "Theme Font-Family Resolution"

# --- Static contract -------------------------------------------------------

if grep -q 'readonly property string fontFamily:' "$theme_qml" &&
   grep -q 'readonly property string fontFamilyResolved:' "$theme_qml" &&
   grep -q 'Qt.fontFamilies()' "$theme_qml" &&
   grep -q 'installedFontFamilies.indexOf(candidate)' "$theme_qml"; then
    pass "[static] Theme keeps the declared preference list and resolves it to one installed family"
else
    fail "[static] Theme must keep fontFamily and expose a fontFamilyResolved resolver over Qt.fontFamilies()"
fi

if [[ -f "$theme_conf" ]] &&
   grep -q '^fontFamily = ' "$theme_conf"; then
    pass "[static] theme.conf still declares the raw font preference list"
else
    fail "[static] theme.conf no longer declares fontFamily"
fi

if grep -q 'property string glyphFontFamily: Theme.fontFamilyResolved' "$icon_qml" &&
   ! grep -q 'split(",")\[0\]' "$icon_qml"; then
    pass "[static] AureliaIcon consumes the theme's single resolution point instead of re-implementing first-entry parsing"
else
    fail "[static] AureliaIcon still re-implements its own first-entry font parsing"
fi

raw_family_assignments="$(grep -rE 'font\.family: *Theme\.fontFamily([^A-Za-z]|$)' \
    "$ROOT/plugins" "$ROOT/ui" "$ROOT/services" "$ROOT/components" 2>&1 || true)"
if [[ -z "$raw_family_assignments" ]]; then
    pass "[static] no text consumer assigns the raw comma-separated list to Qt's font.family"
else
    fail "[static] raw comma-separated font list still reaches Qt's font.family: $raw_family_assignments"
fi

# `fontFamilyProse` is a deliberately different (proportional) family for long
# prose surfaces; it must remain independent of the resolved monospace family.
if grep -q 'readonly property string fontFamilyProse:' "$theme_qml"; then
    pass "[static] the deliberate prose family stays a separate token"
else
    fail "[static] the prose font token was removed or collapsed into the monospace family"
fi

# --- Runtime measurement (isolated offscreen harness) ----------------------

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] theme font-family resolution fixture (qs or timeout unavailable)"
    return 0
fi

font_family_installed() {
    command -v fc-list >/dev/null || return 1
    local families
    families="$(fc-list --format='%{family[0]}\n')" || return 1
    grep -Fxq -- "$1" <<<"$families"
}

FONT_CASE_ROOT=""
FONT_CASE_STATUS=0

run_font_case() {
    local override="$1"
    local case_root
    case_root="$(mktemp -d)"
    mkdir -p "$case_root/config/aurelia" "$case_root/runtime" "$case_root/state" "$case_root/cache" "$case_root/home"
    : >"$case_root/result.json"
    if [[ -n "$override" ]]; then
        printf '%s\n' "$override" >"$case_root/override.conf"
    fi
    local runtime_status=0
    AURELIA_FONT_FAMILY_RESULT="$case_root/result.json" \
    AURELIA_FONT_FAMILY_CLOCK_SOURCE="$clock_source" \
    AURELIA_FONT_FAMILY_ICON_SOURCE="$icon_source" \
    AURELIA_THEME_CONF="${override:+$case_root/override.conf}" \
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$case_root/runtime" XDG_CONFIG_HOME="$case_root/config" \
    XDG_STATE_HOME="$case_root/state" XDG_CACHE_HOME="$case_root/cache" HOME="$case_root/home" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$fixture" --no-color >"$case_root/runtime.log" 2>&1 || runtime_status=$?
    FONT_CASE_ROOT="$case_root"
    FONT_CASE_STATUS="$runtime_status"
}

# Case 1: shipped preference list. Before the fix the text path silently fell
# back to Qt's proportional default while the icon used the first entry.
run_font_case ""
if [[ "$FONT_CASE_STATUS" -eq 0 && -s "$FONT_CASE_ROOT/result.json" ]] &&
   jq -e '.loaded == true and .textResolvedFamily == .iconResolvedFamily' "$FONT_CASE_ROOT/result.json" >/dev/null &&
   runtime_log_is_environment_only "$FONT_CASE_ROOT/runtime.log"; then
    text_family="$(jq -r '.textResolvedFamily' "$FONT_CASE_ROOT/result.json")"
    if font_family_installed "JetBrainsMono Nerd Font"; then
        if [[ "$text_family" == "JetBrainsMono Nerd Font" ]]; then
            pass "[isolated-runtime] shipped list: bar text and icon both resolve to the intended JetBrainsMono Nerd Font"
        else
            fail "[isolated-runtime] shipped list resolved the bar text to '$text_family', expected JetBrainsMono Nerd Font"
        fi
    else
        pass "[isolated-runtime] shipped list: bar text and icon resolve to the same family '$text_family' (intended font not installed here)"
    fi
else
    details="$(tr '\n' ' ' <"$FONT_CASE_ROOT/runtime.log" || true)"
    if [[ -s "$FONT_CASE_ROOT/result.json" ]]; then details="$details result=$(tr '\n' ' ' <"$FONT_CASE_ROOT/result.json")"; fi
    fail "[isolated-runtime] shipped list: text and icon did not resolve to the same family: $details"
fi
rm -rf -- "$FONT_CASE_ROOT" || true

# Case 2: a single family with no comma must pass straight through.
run_font_case "fontFamily = Hack Nerd Font"
if [[ "$FONT_CASE_STATUS" -eq 0 && -s "$FONT_CASE_ROOT/result.json" ]] &&
   jq -e '.loaded == true and .iconGlyphFamilyProperty == "Hack Nerd Font" and
          .textResolvedFamily == .iconResolvedFamily' "$FONT_CASE_ROOT/result.json" >/dev/null &&
   runtime_log_is_environment_only "$FONT_CASE_ROOT/runtime.log"; then
    if font_family_installed "Hack Nerd Font"; then
        if jq -e '.textResolvedFamily == "Hack Nerd Font"' "$FONT_CASE_ROOT/result.json" >/dev/null; then
            pass "[isolated-runtime] single-family theme resolves text and icon to Hack Nerd Font"
        else
            fail "[isolated-runtime] single-family theme did not resolve to Hack Nerd Font"
        fi
    else
        pass "[isolated-runtime] single-family theme resolves text and icon to the same family"
    fi
else
    details="$(tr '\n' ' ' <"$FONT_CASE_ROOT/runtime.log" || true)"
    if [[ -s "$FONT_CASE_ROOT/result.json" ]]; then details="$details result=$(tr '\n' ' ' <"$FONT_CASE_ROOT/result.json")"; fi
    fail "[isolated-runtime] single-family theme broke resolution: $details"
fi
rm -rf -- "$FONT_CASE_ROOT" || true

# Case 3: a list whose FIRST entry is missing must honour the preference order
# and pick the next installed entry instead of handing Qt a missing family.
run_font_case "fontFamily = DefinitelyMissingFontXYZ, Hack Nerd Font, monospace"
if [[ "$FONT_CASE_STATUS" -eq 0 && -s "$FONT_CASE_ROOT/result.json" ]] &&
   jq -e '.loaded == true and .textResolvedFamily == .iconResolvedFamily' "$FONT_CASE_ROOT/result.json" >/dev/null &&
   runtime_log_is_environment_only "$FONT_CASE_ROOT/runtime.log"; then
    if font_family_installed "Hack Nerd Font"; then
        if jq -e '.iconGlyphFamilyProperty == "Hack Nerd Font" and .textResolvedFamily == "Hack Nerd Font"' "$FONT_CASE_ROOT/result.json" >/dev/null; then
            pass "[isolated-runtime] missing first entry falls through to the next installed family"
        else
            fail "[isolated-runtime] missing first entry was not resolved to the next installed family"
        fi
    else
        pass "[isolated-runtime] missing-first list keeps text and icon on the same family"
    fi
else
    details="$(tr '\n' ' ' <"$FONT_CASE_ROOT/runtime.log" || true)"
    if [[ -s "$FONT_CASE_ROOT/result.json" ]]; then details="$details result=$(tr '\n' ' ' <"$FONT_CASE_ROOT/result.json")"; fi
    fail "[isolated-runtime] missing-first list produced divergent text/icon families: $details"
fi
rm -rf -- "$FONT_CASE_ROOT" || true

# Case 4: a list where NO entry is installed must fail closed to the first
# declared entry and must still keep text and icon on the same resolved family.
run_font_case "fontFamily = NoSuchFontABC, NoSuchFontDEF, monospace"
if [[ "$FONT_CASE_STATUS" -eq 0 && -s "$FONT_CASE_ROOT/result.json" ]] &&
   jq -e '.loaded == true and .iconGlyphFamilyProperty == "NoSuchFontABC" and
          .textResolvedFamily == .iconResolvedFamily' "$FONT_CASE_ROOT/result.json" >/dev/null &&
   runtime_log_is_environment_only "$FONT_CASE_ROOT/runtime.log"; then
    pass "[isolated-runtime] fully-missing list fails closed to the first declared entry with text and icon agreeing"
else
    details="$(tr '\n' ' ' <"$FONT_CASE_ROOT/runtime.log" || true)"
    if [[ -s "$FONT_CASE_ROOT/result.json" ]]; then details="$details result=$(tr '\n' ' ' <"$FONT_CASE_ROOT/result.json")"; fi
    fail "[isolated-runtime] fully-missing list broke fail-closed resolution: $details"
fi
rm -rf -- "$FONT_CASE_ROOT" || true
