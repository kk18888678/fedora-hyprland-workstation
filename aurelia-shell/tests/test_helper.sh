#!/usr/bin/env bash

# Test harness and assertion helpers.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER_ROOT="$ROOT"
export ROOT
export HELPER_ROOT
export WORKSTATION_TEST_MODE=1
FAILS=0
PASSES=0
SKIPS=0

pass() {
    PASSES=$((PASSES + 1))
    printf '  PASS %s\n' "$*"
}

skip() {
    SKIPS=$((SKIPS + 1))
    printf '  SKIP %s\n' "$*"
}

fail() {
    FAILS=$((FAILS + 1))
    printf '  FAIL %s\n' "$*"
}

section() {
    printf '\n== %s ==\n' "$*"
}

# Return the diagnostics that are allowed when an isolated QML fixture cannot
# create its optional desktop backend. This list is intentionally narrow:
# arbitrary WARN/ERROR/TypeError/Loader output must keep a fixture failing even
# when a compositor limitation is also present in the same log.
runtime_log_is_environment_only() {
    local log_file="$1"
    local extra_allowed="${2:-}"
    local diagnostics
    local allowed
    local unexpected

    [[ -f "$log_file" ]] || return 1
    diagnostics="$(grep -E 'WARN|ERROR|FATAL|ReferenceError|TypeError|QML Error|Segmentation fault|Cannot assign|Loader\.Error' "$log_file" || true)"
    [[ -z "$diagnostics" ]] && return 0

    allowed='ERROR quickshell\.ipc: Failed to start IPC server on path |Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|No PanelWindow backend loaded|Failed to connect to UPower|Could not connect to UPower|UPower.*unavailable|Failed to connect pipewire context|ERROR quickshell\.service\.pipewire\.loop: Failed to connect pipewire context\. Errno: 1|Signal QQmlEngine::quit\(\) emitted'
    if grep -Eq 'No PanelWindow backend loaded|Failed to create wl_display|Could not load the Qt platform plugin' <<<"$diagnostics"; then
        # These messages are emitted by dependent QML types after the
        # compositor/window backend has already failed. They are accepted only
        # in that explicit context; application warnings remain failures.
        allowed="${allowed}|Type AureliaKeyboardPanel unavailable|Type CommandCenterPanel unavailable|ERROR: Failed to load configuration|\\[[A-Z]+\\] (audio|network|power)_?panel_load_failed|\\[[A-Z]+\\] panel_load_failed"
    fi
    allowed="${allowed}|Failed to connect to system scope bus via local transport: Operation not permitted"
    if [[ -n "$extra_allowed" ]]; then allowed="${allowed}|${extra_allowed}"; fi
    unexpected="$(grep -Ev "$allowed" <<<"$diagnostics" || true)"
    if [[ -n "$unexpected" ]]; then
        printf '%s\n' "$unexpected" >&2
        return 1
    fi
    return 0
}

runtime_skip_if_environment_only() {
    local log_file="$1"
    local description="$2"
    local extra_allowed="${3:-}"
    local diagnostics
    runtime_log_is_environment_only "$log_file" "$extra_allowed" || return 1
    diagnostics="$(grep -E 'WARN|ERROR|FATAL|ReferenceError|TypeError|QML Error|Segmentation fault|Cannot assign|Loader\.Error' "$log_file" || true)"
    if [[ -n "$diagnostics" ]]; then
        printf '  Environment diagnostics for skipped fixture:\n%s\n' "$diagnostics" >&2
    fi
    skip "$description"
}

run_suite() {
    local suite_file="$1"
    if [[ ! -f "$suite_file" ]]; then
        fail "Test suite not found: $suite_file"
        return 0
    fi

    # Each suite receives a fresh shell and helper state. A malformed suite or
    # an unhandled command failure therefore cannot terminate the aggregate
    # runner or leak variables/traps into later suites. The child still uses
    # the real shared helper and emits the same explicit PASS/SKIP/FAIL lines.
    local output
    local status=0
    local pass_count=0
    local skip_count=0
    local fail_count=0
    output="$(bash -c 'set -Eeuo pipefail; source "$1"; source "$2"' _ \
        "$ROOT/tests/test_helper.sh" "$suite_file" 2>&1)" || status=$?
    if [[ -n "$output" ]]; then printf '%s\n' "$output"; fi
    pass_count="$(grep -c '^  PASS ' <<<"$output" || true)"
    skip_count="$(grep -c '^  SKIP ' <<<"$output" || true)"
    fail_count="$(grep -c '^  FAIL ' <<<"$output" || true)"
    PASSES=$((PASSES + pass_count))
    SKIPS=$((SKIPS + skip_count))
    FAILS=$((FAILS + fail_count))
    if (( status != 0 )); then
        if (( fail_count == 0 )); then
            fail "Suite exited unexpectedly: $suite_file (status=$status)"
        else
            printf '  Suite exited after reporting failure: %s (status=%s)\n' "$suite_file" "$status" >&2
        fi
    fi
}

print_test_summary() {
    printf '\n%s\n' "------------------------------------------------------------"
    printf 'Passed: %s  Skipped: %s  Failed: %s\n' "$PASSES" "$SKIPS" "$FAILS"

    if (( FAILS > 0 )); then
        exit 1
    fi
    if (( SKIPS > 0 )) && [[ "${AURELIA_TESTS_REQUIRE_NO_SKIPS:-0}" == "1" ]]; then
        printf 'Strict test mode rejected %s skipped test path(s).\n' "$SKIPS" >&2
        exit 2
    fi
    exit 0
}
