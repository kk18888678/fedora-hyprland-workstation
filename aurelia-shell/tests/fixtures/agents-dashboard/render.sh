#!/usr/bin/env bash

# Render the consolidated Usage dashboard preview offscreen.
#
# A PanelWindow cannot render offscreen, so the fixture renders the exact panel
# body (AgentsDashboard.qml) in a plain QtQuick.Window and grabs the real
# pixels. The PNG is a build artifact and is not committed.
#
# Usage:
#   render.sh [output.png]
#
# Default output: $HOME/agents-usage-dashboard-preview.png

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

runtime_root="$(mktemp -d)"
cleanup() { rm -rf -- "$runtime_root" || true; }
trap cleanup EXIT

log_file="$runtime_root/runtime.log"
result_file="$runtime_root/result.json"

QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CACHE_HOME="$runtime_root/cache" \
AGENTS_DASHBOARD_PLUGIN="$plugin_path" \
AGENTS_DASHBOARD_FIXTURE="$fixture_dir/records.json" \
AGENTS_DASHBOARD_IMAGE="$output" \
AGENTS_DASHBOARD_RESULT="$result_file" \
    /usr/bin/timeout --kill-after=1s 20s /usr/bin/qs --no-duplicate \
    --path "$fixture_dir/shell.qml" >"$log_file" 2>&1 || {
        printf 'render.sh: quickshell exited nonzero\n' >&2
        sed -n '1,80p' "$log_file" >&2
        exit 1
    }

if [[ ! -s "$output" ]]; then
    printf 'render.sh: no image was written to %s\n' "$output" >&2
    sed -n '1,80p' "$log_file" >&2
    exit 1
fi

printf '%s\n' "$output"
