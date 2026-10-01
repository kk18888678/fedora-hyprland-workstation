#!/usr/bin/env bash

# Render one PNG per panel-tooltip state (spec 6.3) over a real panel row.
#
# Inline tooltips cannot render live, so the exact panel body is rendered
# offscreen in a plain QtQuick.Window and grabbed with Item.grabToImage. Each
# image is written as:
#   <output-dir>/<timestamp>-panel-tooltip-<state>.png
# and every absolute path is printed to stdout for the design owner.
#
# Fully isolated: it starts its own Quickshell instance with throwaway
# XDG_RUNTIME_DIR/config/state/cache and never reloads, restarts or talks to
# the live Aurelia shell (no IPC, no `qs ipc`). The PNGs are outside the
# repository and are never committed.
#
# Usage:
#   render-tooltips.sh [output-dir]
# Default output dir: $HOME/Downloads

set -Eeuo pipefail

output_dir="${1:-${HOME}/Downloads}"
if [[ ! -d "$output_dir" ]]; then
    printf 'render-tooltips.sh: output directory does not exist: %s\n' "$output_dir" >&2
    exit 2
fi
output_dir="$(cd -- "$output_dir" && pwd -P)"

fixture_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
plugin_path="$(cd -- "$fixture_dir/../../../plugins/aurelia.agents" && pwd -P)/AgentsDashboard.qml"
fixture_path="$fixture_dir/records.json"
fixture="$fixture_dir/tooltip-states.qml"

if [[ ! -x /usr/bin/qs ]]; then
    printf 'render-tooltips.sh: quickshell (qs) is not installed\n' >&2
    exit 2
fi

runtime_root="$(mktemp -d)"
cleanup() { rm -rf -- "$runtime_root" || true; }
trap cleanup EXIT

timestamp="$(date +%Y%m%d-%H%M%S)"
stem="$output_dir/$timestamp-panel-tooltip"
result_file="$runtime_root/result.json"
log_file="$runtime_root/render.log"

QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CACHE_HOME="$runtime_root/cache" \
AGENTS_DASHBOARD_PLUGIN="$plugin_path" \
AGENTS_DASHBOARD_FIXTURE="$fixture_path" \
AGENTS_DASHBOARD_IMAGE="$stem.png" \
AGENTS_DASHBOARD_RESULT="$result_file" \
    /usr/bin/timeout --kill-after=1s 40s /usr/bin/qs --no-duplicate \
    --path "$fixture" >"$log_file" 2>&1 || {
        printf 'render-tooltips.sh: quickshell exited nonzero\n' >&2
        sed -n '1,80p' "$log_file" >&2
        exit 1
    }

if [[ ! -s "$result_file" ]]; then
    printf 'render-tooltips.sh: no measurement result was written\n' >&2
    sed -n '1,80p' "$log_file" >&2
    exit 1
fi

shopt -s nullglob
images=("$stem"-*.png)
shopt -u nullglob

if (( ${#images[@]} == 0 )); then
    printf 'render-tooltips.sh: no images were written\n' >&2
    sed -n '1,80p' "$log_file" >&2
    exit 1
fi

printf '%s\n' "${images[@]}"
