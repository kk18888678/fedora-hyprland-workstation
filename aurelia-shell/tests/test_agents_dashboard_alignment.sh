#!/usr/bin/env bash

# Agents dashboard matrix alignment: a measured, not grepped, regression test.
#
# It renders the real AgentsDashboard body offscreen with the shared fixture,
# walks the live item tree and measures the account column, the window header
# labels, every window cell, every percentage right edge and every meter. It
# then asserts the grid invariants:
#
#   * the meter x and width are identical in every account row AND match the
#     header column boundary;
#   * the percentage right edge is identical in every row;
#   * every account row has the same height;
#   * a narrow width shrinks the ACCOUNT column first and never reintroduces
#     per-row variance.
#
# Nothing here touches the live workstation.

set -Eeuo pipefail

section "Aurelia Agents Dashboard Alignment"

plugin_dir="$ROOT/plugins/aurelia.agents"
fixture="$ROOT/tests/fixtures/agents-dashboard/records.json"
harness="$ROOT/tests/fixtures/agents-dashboard/alignment.qml"

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] agents dashboard alignment (qs or timeout unavailable)"
    return 0
fi

# The fixture must actually exercise the awkward content cases, or a
# content-driven width regression could slip through untested.
if jq -e '
        ([.agents[] | select((.limits // []) | length == 0)] | length) >= 1 and
        ([.agents[].limits[]? | select(.windowMinutes == null)] | length) >= 1 and
        ([.agents[].limits[]? | select(.windowMinutes == 0 or .windowMinutes == 999 or .windowMinutes == 1440)] | length) >= 1 and
        ([.agents[].limits[]? | select(.windowMinutes == 43200)] | length) >= 1' \
       "$fixture" >/dev/null; then
    pass "[unit] alignment fixture includes a no-limits account, a missing duration, a non-canonical duration and a long monthly countdown"
else
    fail "[unit] alignment fixture no longer exercises the awkward content cases"
fi

measure() {
    local width="$1" result="$2" log="$3"
    local mode="${4:-remaining}"
    local select="${5:-codex}"
    local stale_ms="${6:-1800000}"
    local sandbox
    sandbox="$(mktemp -d)"
    local status=0
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$sandbox/runtime" \
    XDG_CONFIG_HOME="$sandbox/config" \
    XDG_STATE_HOME="$sandbox/state" \
    XDG_CACHE_HOME="$sandbox/cache" \
    AGENTS_DASHBOARD_PLUGIN="$plugin_dir/AgentsDashboard.qml" \
    AGENTS_DASHBOARD_FIXTURE="$fixture" \
    AGENTS_DASHBOARD_RESULT="$result" \
    AGENTS_DASHBOARD_WIDTH="$width" \
    AGENTS_DASHBOARD_PERCENT_MODE="$mode" \
    AGENTS_DASHBOARD_SELECT="$select" \
    AGENTS_DASHBOARD_STALE_MS="$stale_ms" \
        /usr/bin/timeout --kill-after=1s 20s /usr/bin/qs --no-duplicate \
        --path "$harness" >"$log" 2>&1 || status=$?
    rm -rf -- "$sandbox" || true
    return "$status"
}

print_measurements() {
    local file="$1" label="$2"
    printf '  measured %s (window width %s):\n' "$label" "$(jq -c '.windowWidth' "$file")"
    jq -r '
        . as $r
        | ($r.columns | split(",")) as $cols
        | $cols[]
        | . as $c
        | ([$r.cells[] | select(.column == $c)][0]) as $cell
        | ($r.headers[$c]) as $head
        | ([$r.meters[] | select(.column == $c)][0]) as $meter
        | ([$r.percentages[] | select(.column == $c)][0]) as $pct
        | "    column=\($c) header_x=\($head.x) header_w=\($head.width) " +
          "cell_x=\($cell.x) cell_w=\($cell.width) meter_x=\($meter.x) meter_w=\($meter.width) " +
          "percent_right=\($pct.right)"' "$file"
    printf '    row_heights=%s account_width=%s\n' \
        "$(jq -c '[.rows[].height] | unique' "$file")" \
        "$(jq -c '.accountHeader.width' "$file")"
}

assert_alignment() {
    local file="$1" label="$2" max_account="$3"
    local ok
    ok="$(jq -r --argjson maxAccount "$max_account" '
        . as $r
        | ($r.columns | split(",")) as $cols
        | [
            $cols[] as $c
            | ([$r.cells[] | select(.column == $c)]) as $cells
            | ([$r.meters[] | select(.column == $c)]) as $meters
            | ([$r.percentages[] | select(.column == $c)]) as $pcts
            | ($r.headers[$c]) as $head
            | {
                column: $c,
                cellsUniform: ((([$cells[].x] | unique | length) == 1) and (([$cells[].width] | unique | length) == 1)),
                metersUniform: ((([$meters[].x] | unique | length) == 1) and (([$meters[].width] | unique | length) == 1)),
                metersVisible: (($meters | map(select(.visible == true)) | length) == ($meters | length)),
                meterMatchesCell: ($meters[0].x == $cells[0].x and $meters[0].width == $cells[0].width),
                headerMatchesCell: ($head.x == $cells[0].x and $head.width == $cells[0].width),
                percentUniform: (([$pcts[].right] | unique | length) == 1),
                percentAtEdge: (($pcts[0].right) == ($cells[0].x + $cells[0].width)),
                counts: (($cells | length) == ($meters | length) and ($pcts | length) == ($cells | length))
              }
          ] as $report
        | (($report | all(.cellsUniform and .metersUniform and .metersVisible and
                          .meterMatchesCell and .headerMatchesCell and
                          .percentUniform and .percentAtEdge and .counts))
           and (([$r.rows[].height] | unique | length) == 1)
           and (([$r.accountCells[].width] | unique | length) == 1)
           and ($r.accountHeader.width == $r.accountCells[0].width)
           and ($r.accountHeader.x == $r.accountCells[0].x)
           and ($r.accountCells[0].width <= $maxAccount))
        | if . then "true" else "false" end
    ' "$file" || true)"
    if [[ "$ok" == "true" ]]; then
        pass "[isolated-runtime] $label: meter x/width, percentage right edge, header boundary and row heights are a true grid"
    else
        fail "[isolated-runtime] $label: matrix columns are not aligned"
    fi
}

# Every QuickShell launch must classify its complete captured runtime log so
# an unexpected QML warning, Loader error or backend failure fails this suite.
assert_runtime_log_clean() {
    local log="$1" label="$2"
    # The dashboard deliberately emits an [AGENTS] unmet_condition diagnostic
    # for every awkward fixture field, and each harness FileView reports its
    # not-yet-written result path. Both are expected test evidence, not
    # production warnings; everything else must be environment-only.
    local expected="${3:-(\[AGENTS\]|@alignment\.qml|@interaction\.qml)}"
    if runtime_log_is_environment_only "$log" "$expected"; then
        pass "[isolated-runtime] $label runtime log contains only environment and expected fixture diagnostics"
    else
        fail "[isolated-runtime] $label runtime log contains unexpected diagnostics"
    fi
}

alignment_root="$(mktemp -d)"
trap 'rm -rf -- "$alignment_root" || true' RETURN

# Default panel width: account column stays at its requested 108 px.
wide_result="$alignment_root/wide.json"
wide_log="$alignment_root/wide.log"
wide_status=0
measure 480 "$wide_result" "$wide_log" || wide_status=$?
if [[ "$wide_status" -eq 0 && -s "$wide_result" ]]; then
    print_measurements "$wide_result" "default width"
    assert_alignment "$wide_result" "default width" 108
else
    fail "[isolated-runtime] default-width alignment probe failed (status=$wide_status)"
    sed -n '1,40p' "$wide_log" >&2 || true
fi
assert_runtime_log_clean "$wide_log" "default-width"

# Narrow panel: the ACCOUNT column shrinks first; the window columns stay equal.
narrow_result="$alignment_root/narrow.json"
narrow_log="$alignment_root/narrow.log"
narrow_status=0
measure 380 "$narrow_result" "$narrow_log" || narrow_status=$?
if [[ "$narrow_status" -eq 0 && -s "$narrow_result" ]]; then
    print_measurements "$narrow_result" "narrow width"
    assert_alignment "$narrow_result" "narrow width" 108
    narrow_account="$(jq -r '.accountHeader.width' "$narrow_result")"
    if [[ "$narrow_account" =~ ^[0-9]+$ ]] && (( narrow_account < 108 )); then
        pass "[isolated-runtime] narrow width degrades the ACCOUNT column first (width $narrow_account < 108)"
    else
        fail "[isolated-runtime] narrow width did not shrink the ACCOUNT column (width $narrow_account)"
    fi
else
    fail "[isolated-runtime] narrow-width alignment probe failed (status=$narrow_status)"
    sed -n '1,40p' "$narrow_log" >&2 || true
fi
assert_runtime_log_clean "$narrow_log" "narrow-width"

# Mode consistency: the meter fill width must equal the displayed percentage
# for BOTH presentations. This is the strongest proof that the number and the
# visual cannot disagree, because the fill and the text are driven by the same
# displayPercent() result.
for percent_mode in remaining used; do
    mode_result="$alignment_root/mode-$percent_mode.json"
    mode_log="$alignment_root/mode-$percent_mode.log"
    mode_status=0
    measure 480 "$mode_result" "$mode_log" "$percent_mode" || mode_status=$?
    if [[ "$mode_status" -eq 0 && -s "$mode_result" ]] &&
       jq -e --arg mode "$percent_mode" '
            . as $r
            | ($r.percentMode == $mode) and
              ([ $r.meterFills[] as $fill
                 | ([$r.percentages[] | select(.row == $fill.row and .column == $fill.column)][0]) as $pct
                 | ([$r.meters[] | select(.row == $fill.row and .column == $fill.column)][0]) as $meter
                 | select($pct != null and $meter != null and $meter.width > 0 and
                          ($pct.text | test("^[0-9]+%$")))
                 | ((((($pct.text | sub("%";"") | tonumber) / 100) * $meter.width) - $fill.width) | fabs) <= 1.5
               ] | all)
           ' "$mode_result" >/dev/null; then
        pass "[isolated-runtime] $percent_mode mode: every meter fill width matches its displayed percentage"
    else
        fail "[isolated-runtime] $percent_mode mode: a meter fill does not match its displayed percentage (status=$mode_status result=$(jq -c '.meterFills, .percentages' "$mode_result" || true))"
    fi
    assert_runtime_log_clean "$mode_log" "$percent_mode mode"
done

# Close/refresh interaction: the close control collapses the detail and the
# icon-only refresh disables and shows its busy state while a probe runs.
interaction_harness="$ROOT/tests/fixtures/agents-dashboard/interaction.qml"
interaction_result="$alignment_root/interaction.json"
interaction_log="$alignment_root/interaction.log"
interaction_status=0
interaction_sandbox="$(mktemp -d)"
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$interaction_sandbox/runtime" \
XDG_CONFIG_HOME="$interaction_sandbox/config" \
XDG_STATE_HOME="$interaction_sandbox/state" \
XDG_CACHE_HOME="$interaction_sandbox/cache" \
AGENTS_DASHBOARD_PLUGIN="$plugin_dir/AgentsDashboard.qml" \
AGENTS_DASHBOARD_FIXTURE="$fixture" \
AGENTS_DASHBOARD_RESULT="$interaction_result" \
    /usr/bin/timeout --kill-after=1s 20s /usr/bin/qs --no-duplicate \
    --path "$interaction_harness" >"$interaction_log" 2>&1 || interaction_status=$?
rm -rf -- "$interaction_sandbox" || true

if [[ "$interaction_status" -eq 0 && -s "$interaction_result" ]] &&
   jq -e '
        .hasSelectionBefore == true and
        .detailVisibleBefore == true and
        .closePresent == true and
        .refreshPresent == true and
        .refreshEnabledBefore == true and
        .hasSelectionAfterClose == false and
        .detailVisibleAfterClose == false and
        .closeVisibleAfterClose == false and
        .refreshEnabledWhileBusy == false and
        .refreshActiveWhileBusy == true and
        .refreshEnabledAfter == true and
        .refreshActiveAfter == false and
        .refreshY < .matrixY and
        .matrixY < .closeY' \
       "$interaction_result" >/dev/null; then
    pass "[isolated-runtime] close collapses the detail and the icon-only refresh disables and shows busy while running"
else
    fail "[isolated-runtime] close/refresh interaction regressed (status=$interaction_status result=$(cat "$interaction_result" || true))"
fi
assert_runtime_log_clean "$interaction_log" "close/refresh interaction"

# ---------------------------------------------------------------------------
# Alert dimming policy (P1/P2): a warn/critical matrix cell must never be
# dimmed, not even when it is not the binding constraint, and its non-colour
# glyph/percent/meter must keep effective opacity 1.0. The `opencode-dual`
# fixture has TWO >=90% windows where only one is binding, which the previous
# `opencode-blocked` fixture (5h 5% ok, week 100% critical) did not exercise.
# The non-alert case (an ok, non-binding cell) must still dim, unchanged.
# ---------------------------------------------------------------------------
alert_result="$alignment_root/alert.json"
alert_log="$alignment_root/alert.log"
alert_status=0
measure 480 "$alert_result" "$alert_log" remaining "opencode-dual" 1800000 || alert_status=$?
if [[ "$alert_status" -eq 0 && -s "$alert_result" ]] &&
   jq -e '
        . as $r
        | ([ $r.cells[] | select(.severity == "warn" or .severity == "critical") ]) as $alerts
        | ([ $r.cells[] | select((.severity == "warn" or .severity == "critical") and .isBinding == false) ] | length) as $nonBindingAlerts
        | ($nonBindingAlerts >= 1)
          and ([ $alerts[] | .effectiveOpacity ] | map(. >= 0.999) | all)
          and ([ $alerts[] as $a
                 | ([ $r.percentages[] | select(.row == $a.row and .column == $a.column)][0]) as $p
                 | ([ $r.meters[] | select(.row == $a.row and .column == $a.column)][0]) as $m
                 | (($p != null) and ($p.effectiveOpacity >= 0.999) and
                    ($m != null) and ($m.effectiveOpacity >= 0.999)) ] | map(.) | all)
          and ([ $r.cells[] | select(.severity == "ok" and .isBinding == false and .effectiveOpacity <= 0.46) ] | length) >= 1
   ' "$alert_result" >/dev/null; then
    pass "[isolated-runtime] alert policy: warn/critical cells (including non-binding) keep effective opacity 1.0 while ok non-binding cells still dim"
else
    fail "[isolated-runtime] alert policy: an alert matrix cell was dimmed by an ancestor (status=$alert_status result=$(jq -c '[.cells[] | select(.severity=="warn" or .severity=="critical")]' "$alert_result" || true))"
fi
assert_runtime_log_clean "$alert_log" "alert opacity"

# ---------------------------------------------------------------------------
# Stale detail pane (P2): staleness is additive. With a stale account whose
# binding window is critical, the alert limit row still renders at effective
# opacity 1.0 (previously the whole detail pane dropped to 0.6), while the
# non-alert ok rows carry the stale dim.
# ---------------------------------------------------------------------------
stale_result="$alignment_root/stale-detail.json"
stale_log="$alignment_root/stale-detail.log"
stale_status=0
measure 480 "$stale_result" "$stale_log" remaining "opencode" 60000 || stale_status=$?
if [[ "$stale_status" -eq 0 && -s "$stale_result" ]] &&
   jq -e '
        . as $r
        | def rowSeverity($id): ([ $r.detailRows[] | select(.row == $id)][0].severity);
        ($r.staleMs == 60000)
          and ([ $r.detailRows[] | select(.severity == "critical") ] | length) >= 1
          and ([ $r.detailRows[] | select(.severity == "critical") | .effectiveOpacity ] | map(. >= 0.999) | all)
          and ([ $r.detailRows[] | select(.severity == "ok") ] | length) >= 1
          and ([ $r.detailRows[] | select(.severity == "ok") | .effectiveOpacity ] | map(. <= 0.61) | all)
          # every inner alert element (percent text, severity glyph, alarming
          # meter) on a critical row keeps effective opacity 1.0, so no row
          # de-emphasis buries the alert; every element on an ok row is dimmed.
          and ([ $r.detailElements[]
                 | select(.kind == "percent" or .kind == "glyph" or .kind == "meter")
                 | select(rowSeverity(.row) == "critical")
                 | .effectiveOpacity ] | map(. >= 0.999) | all)
          and ([ $r.detailElements[] | select(.kind == "percent" or .kind == "glyph" or .kind == "meter")
                 | select(rowSeverity(.row) == "ok")
                 | .effectiveOpacity ] | map(. <= 0.61) | all)
          and ([ $r.detailElements[] | select(.kind == "percent")
                 | select(rowSeverity(.row) == "critical") ] | length) >= 1
          and ([ $r.detailElements[] | select(.kind == "glyph")
                 | select(rowSeverity(.row) == "critical") ] | length) >= 1
          and ([ $r.detailElements[] | select(.kind == "meter")
                 | select(rowSeverity(.row) == "critical") ] | length) >= 1
   ' "$stale_result" >/dev/null; then
    pass "[isolated-runtime] stale detail pane: alert row, percent, glyph and alarm meter stay at effective opacity 1.0 while non-alert rows carry the stale dim"
else
    fail "[isolated-runtime] stale detail pane dimmed an alert row (status=$stale_status result=$(jq -c '.staleMs, .detailRows' "$stale_result" || true))"
fi
assert_runtime_log_clean "$stale_log" "stale detail pane"

# ---------------------------------------------------------------------------
# Measured render: with a critical fixture, the alert token must survive to the
# composited pixels at full opacity and clear 4.5:1 against the sampled
# background. The fixture theme pins the error token so this assertion is
# independent of the wallpaper-palette task.
# ---------------------------------------------------------------------------
if ! command -v magick >/dev/null; then
    skip "[isolated-runtime] ImageMagick is required for the measured alert-contrast render"
elif ! command -v python3 >/dev/null; then
    skip "[isolated-runtime] python3 is required for the measured alert-contrast render"
else
    render_theme="$ROOT/tests/fixtures/agents-dashboard/alert-contrast-theme.conf"
    render_root="$alignment_root/alert-render"
    render_image="$render_root/alert.png"
    render_result="$render_root/result.json"
    render_log="$render_root/render.log"
    mkdir -p -- "$render_root"
    render_status=0
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$render_root/runtime" \
    XDG_CONFIG_HOME="$render_root/config" \
    XDG_STATE_HOME="$render_root/state" \
    XDG_CACHE_HOME="$render_root/cache" \
    AURELIA_THEME_CONF="$render_theme" \
    AGENTS_DASHBOARD_PLUGIN="$plugin_dir/AgentsDashboard.qml" \
    AGENTS_DASHBOARD_FIXTURE="$fixture" \
    AGENTS_DASHBOARD_IMAGE="$render_image" \
    AGENTS_DASHBOARD_RESULT="$render_result" \
    AGENTS_DASHBOARD_SELECT="opencode-dual" \
        /usr/bin/timeout --kill-after=1s 20s /usr/bin/qs --no-duplicate \
        --path "$ROOT/tests/fixtures/agents-dashboard/shell.qml" >"$render_log" 2>&1 || render_status=$?

    if [[ "$render_status" -eq 0 && -s "$render_image" ]]; then
        hist="$(magick "$render_image" -depth 8 -format %c histogram:info:- || true)"
        error_count="$(printf '%s\n' "$hist" | grep -ciE '#eb6f92' || true)"
        bg_hex="$(printf '%s\n' "$hist" | sort -t: -k1,1nr | head -1 | grep -oiE '#[0-9a-f]{6}' | head -1 || true)"
        if [[ -n "$bg_hex" && -n "$error_count" && "$error_count" =~ ^[0-9]+$ ]]; then
            contrast="$(python3 - '#eb6f92' "$bg_hex" <<'CONTRAST_PY'
import sys
def lum(h):
    h = h.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
a, b = lum(sys.argv[1]), lum(sys.argv[2])
print("%.2f" % ((max(a, b) + 0.05) / (min(a, b) + 0.05)))
CONTRAST_PY
)"
        else
            contrast=""
        fi
        if (( error_count > 0 )) && [[ -n "$contrast" ]] &&
           awk -v c="$contrast" 'BEGIN { exit !(c >= 4.5) }'; then
            pass "[isolated-runtime] measured render: the full-strength alert token #eb6f92 persists against sampled background $bg_hex at ${contrast}:1 (>= 4.5:1)"
        else
            fail "[isolated-runtime] measured render: the alert token did not survive at full contrast (error_pixels=$error_count background=$bg_hex contrast=${contrast:-n/a})"
        fi
    else
        fail "[isolated-runtime] measured alert render failed (status=$render_status image=$( [[ -s "$render_image" ]] && printf yes || printf no ))"
    fi
    assert_runtime_log_clean "$render_log" "measured alert render" '(\[AGENTS\]|result\.json|@shell\.qml)'
fi
