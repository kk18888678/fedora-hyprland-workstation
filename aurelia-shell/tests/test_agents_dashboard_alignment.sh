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
    AGENTS_DASHBOARD_SELECT="codex" \
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
    local expected='(\[AGENTS\]|@alignment\.qml|@interaction\.qml)'
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
        .refreshActiveAfter == false' \
       "$interaction_result" >/dev/null; then
    pass "[isolated-runtime] close collapses the detail and the icon-only refresh disables and shows busy while running"
else
    fail "[isolated-runtime] close/refresh interaction regressed (status=$interaction_status result=$(cat "$interaction_result" || true))"
fi
assert_runtime_log_clean "$interaction_log" "close/refresh interaction"
