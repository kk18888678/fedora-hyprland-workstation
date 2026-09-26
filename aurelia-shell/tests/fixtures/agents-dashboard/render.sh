#!/usr/bin/env bash

# Render the consolidated AI Usage dashboard preview offscreen, in both the
# resting (no account expanded) and the expanded states.
#
# A PanelWindow cannot render offscreen, so the fixture renders the exact panel
# body (AgentsDashboard.qml) in a plain QtQuick.Window and grabs the real
# pixels. The PNGs are build artifacts and are not committed.
#
# Usage:
#   render.sh [output.png]
#
# Default output: $HOME/agents-usage-dashboard-preview.png
# The expanded state is written beside it as
#   <stem>-expanded.png
# Both absolute paths are printed to stdout.

set -Eeuo pipefail

fixture_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
plugin_path="$(cd -- "$fixture_dir/../../../plugins/aurelia.agents" && pwd -P)/AgentsDashboard.qml"
output="${1:-${HOME}/agents-usage-dashboard-preview.png}"

if [[ ! -x /usr/bin/qs ]]; then
    printf 'render.sh: quickshell (qs) is not installed\n' >&2
    exit 2
fi

output_dir="$(dirname -- "$output")"
mkdir -p -- "$output_dir"
output="$(cd -- "$output_dir" && pwd -P)/$(basename -- "$output")"
expanded="${output%.png}-expanded.png"

runtime_root="$(mktemp -d)"
cleanup() { rm -rf -- "$runtime_root" || true; }
trap cleanup EXIT

render_state() {
    local image="$1"
    local select_id="$2"
    local tag="$3"
    local log_file="$runtime_root/${tag}.log"
    local result_file="$runtime_root/${tag}-result.json"

    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$runtime_root/${tag}-runtime" \
    XDG_CONFIG_HOME="$runtime_root/${tag}-config" \
    XDG_STATE_HOME="$runtime_root/${tag}-state" \
    XDG_CACHE_HOME="$runtime_root/${tag}-cache" \
    AGENTS_DASHBOARD_PLUGIN="$plugin_path" \
    AGENTS_DASHBOARD_FIXTURE="$fixture_dir/records.json" \
    AGENTS_DASHBOARD_IMAGE="$image" \
    AGENTS_DASHBOARD_RESULT="$result_file" \
    AGENTS_DASHBOARD_SELECT="$select_id" \
        /usr/bin/timeout --kill-after=1s 20s /usr/bin/qs --no-duplicate \
        --path "$fixture_dir/shell.qml" >"$log_file" 2>&1 || {
            printf 'render.sh: quickshell exited nonzero for the %s state\n' "$tag" >&2
            sed -n '1,80p' "$log_file" >&2
            exit 1
        }

    if [[ ! -s "$image" ]]; then
        printf 'render.sh: no image was written to %s\n' "$image" >&2
        sed -n '1,80p' "$log_file" >&2
        exit 1
    fi
}

render_state "$output" "" "collapsed"
render_state "$expanded" "codex" "expanded"

printf '%s\n%s\n' "$output" "$expanded"
