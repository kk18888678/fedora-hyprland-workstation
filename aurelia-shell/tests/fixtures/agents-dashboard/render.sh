#!/usr/bin/env bash

# Render the consolidated AI Usage dashboard preview offscreen, in both the
# resting (no account expanded) and the expanded states.
#
# A PanelWindow cannot render offscreen, so the fixture renders the exact panel
# body (AgentsDashboard.qml) in a plain QtQuick.Window and grabs the real
# pixels. The PNGs are build artifacts and are not committed.
#
# The render is fully isolated: it starts its own Quickshell instance with a
# throwaway XDG_RUNTIME_DIR/config/state/cache and a fixture XDG home. It NEVER
# reloads, restarts or talks to the live Aurelia shell (no IPC, no `qs ipc`).
#
# Usage:
#   render.sh [--accounts N] [--select ID] [--expand-details] [output.png]
#
# Options (all off by default; the default run is unchanged):
#   --accounts N       render using only the first N fixture accounts. With the
#                      full 8-account fixture the detail pane measures
#                      detailHeight 0, so the expanded view and ACCOUNT DETAILS
#                      cannot be reviewed; a smaller matrix frees the room.
#   --select ID        fixture account to expand (default: codex).
#   --expand-details   expand the selected account's ACCOUNT DETAILS disclosure
#                      using the fixture's fake identity rows only.
#   -h, --help         show this help.
#
# Default output: $HOME/agents-usage-dashboard-preview.png
# The expanded state is written beside it as
#   <stem>-expanded.png
# Both absolute paths are printed to stdout.

set -Eeuo pipefail

usage() {
    cat <<'USAGE'
Usage: render.sh [--accounts N] [--select ID] [--expand-details] [output.png]

Options (all off by default; the default run is unchanged):
  --accounts N       render using only the first N fixture accounts.
  --select ID        fixture account to expand (default: codex).
  --expand-details   expand the selected account's ACCOUNT DETAILS disclosure.
  -h, --help         show this help.

Default output: $HOME/agents-usage-dashboard-preview.png
USAGE
}

accounts=""
select_id="codex"
expand_details=0
output=""

while (( $# > 0 )); do
    case "$1" in
        --accounts)
            shift
            accounts="${1:-}"
            if [[ ! "$accounts" =~ ^[1-9][0-9]*$ ]]; then
                printf 'render.sh: --accounts requires a positive integer\n' >&2
                exit 2
            fi
            ;;
        --accounts=*)
            accounts="${1#--accounts=}"
            if [[ ! "$accounts" =~ ^[1-9][0-9]*$ ]]; then
                printf 'render.sh: --accounts requires a positive integer\n' >&2
                exit 2
            fi
            ;;
        --select)
            shift
            select_id="${1:-}"
            if [[ -z "$select_id" ]]; then
                printf 'render.sh: --select requires an account id\n' >&2
                exit 2
            fi
            ;;
        --select=*)
            select_id="${1#--select=}"
            if [[ -z "$select_id" ]]; then
                printf 'render.sh: --select requires an account id\n' >&2
                exit 2
            fi
            ;;
        --expand-details)
            expand_details=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf 'render.sh: unknown option %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "$output" ]]; then
                printf 'render.sh: unexpected extra argument %s\n' "$1" >&2
                exit 2
            fi
            output="$1"
            ;;
    esac
    shift
done

if (( $# > 0 )); then
    if [[ -n "$output" ]]; then
        printf 'render.sh: unexpected extra argument %s\n' "$1" >&2
        exit 2
    fi
    output="$1"
fi

output="${output:-${HOME}/agents-usage-dashboard-preview.png}"

fixture_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
plugin_path="$(cd -- "$fixture_dir/../../../plugins/aurelia.agents" && pwd -P)/AgentsDashboard.qml"
fixture_path="$fixture_dir/records.json"

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

# `--accounts N` is implemented as a filtered view of the SAME fixture rather
# than a mutation of it, so the fixture remains the single source of the fake
# records and the default run reads the untouched file. jq is only required
# when the opt-in is actually used.
if [[ -n "$accounts" ]]; then
    if ! command -v jq >/dev/null; then
        printf 'render.sh: jq is required for --accounts\n' >&2
        exit 2
    fi
    filtered_fixture="$runtime_root/records-$accounts.json"
    if ! jq --argjson n "$accounts" '{agents: .agents[:$n]}' \
            "$fixture_dir/records.json" >"$filtered_fixture"; then
        printf 'render.sh: could not filter %s to the first %s accounts\n' \
            "$fixture_dir/records.json" "$accounts" >&2
        exit 1
    fi
    fixture_path="$filtered_fixture"
fi

render_state() {
    local image="$1"
    local select="$2"
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
    AGENTS_DASHBOARD_FIXTURE="$fixture_path" \
    AGENTS_DASHBOARD_IMAGE="$image" \
    AGENTS_DASHBOARD_RESULT="$result_file" \
    AGENTS_DASHBOARD_SELECT="$select" \
    AGENTS_DASHBOARD_EXPAND_ACCOUNT="$expand_details" \
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
render_state "$expanded" "$select_id" "expanded"

printf '%s\n%s\n' "$output" "$expanded"
