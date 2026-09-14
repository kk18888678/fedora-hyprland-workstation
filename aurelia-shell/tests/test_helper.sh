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
SUITES=0
SUITE_FAILURES=0
EXCLUDED_SUITES=0
EXCLUDED_SUITE_NAMES=""
STATIC_ASSERTIONS=0
ISOLATED_ASSERTIONS=0
LIVE_ASSERTIONS=0
UNLABELLED_ASSERTIONS=0

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
            allowed="${allowed}|Type AureliaKeyboardPanel unavailable|Type CommandCenterPanel unavailable|Type BarPanel unavailable|Type ScreenMoveRemap unavailable|ERROR: Failed to load configuration|\\[[A-Z]+\\] (audio|network|power)_?panel_load_failed|\\[[A-Z]+\\] panel_load_failed"
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
    SUITES=$((SUITES + 1))
    if [[ ! -f "$suite_file" ]]; then
        fail "Test suite not found: $suite_file"
        SUITE_FAILURES=$((SUITE_FAILURES + 1))
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
    local outcome_count=0
    local static_count=0
    local isolated_count=0
    local live_count=0
    local unlabelled_count=0
    output="$(bash -c 'set -Eeuo pipefail; source "$1"; source "$2"' _ \
        "$ROOT/tests/test_helper.sh" "$suite_file" 2>&1)" || status=$?
    if [[ -n "$output" ]]; then printf '%s\n' "$output"; fi
    pass_count="$(grep -c '^  PASS ' <<<"$output" || true)"
    skip_count="$(grep -c '^  SKIP ' <<<"$output" || true)"
    fail_count="$(grep -c '^  FAIL ' <<<"$output" || true)"
    outcome_count=$((pass_count + skip_count + fail_count))
    static_count="$(grep -Ec '^  (PASS|SKIP|FAIL) \[static\]' <<<"$output" || true)"
    isolated_count="$(grep -Ec '^  (PASS|SKIP|FAIL) \[isolated-' <<<"$output" || true)"
    live_count="$(grep -Ec '^  (PASS|SKIP|FAIL) \[live-' <<<"$output" || true)"
    unlabelled_count=$((outcome_count - static_count - isolated_count - live_count))
    PASSES=$((PASSES + pass_count))
    SKIPS=$((SKIPS + skip_count))
    FAILS=$((FAILS + fail_count))
    STATIC_ASSERTIONS=$((STATIC_ASSERTIONS + static_count))
    ISOLATED_ASSERTIONS=$((ISOLATED_ASSERTIONS + isolated_count))
    LIVE_ASSERTIONS=$((LIVE_ASSERTIONS + live_count))
    UNLABELLED_ASSERTIONS=$((UNLABELLED_ASSERTIONS + unlabelled_count))
    if (( outcome_count == 0 )); then
        fail "Suite produced no PASS, SKIP, or FAIL outcome: $suite_file"
        SUITE_FAILURES=$((SUITE_FAILURES + 1))
    fi
    if (( status != 0 )); then
        SUITE_FAILURES=$((SUITE_FAILURES + 1))
        if (( fail_count == 0 )); then
            fail "Suite exited unexpectedly: $suite_file (status=$status)"
        else
            printf '  Suite exited after reporting failure: %s (status=%s)\n' "$suite_file" "$status" >&2
        fi
    fi
}

print_test_summary() {
    printf '\n%s\n' "------------------------------------------------------------"
    printf 'Suites: %s  Suite failures: %s\n' "$SUITES" "$SUITE_FAILURES"
    printf 'Excluded suite entry points: %s\n' "$EXCLUDED_SUITES"
    if [[ -n "$EXCLUDED_SUITE_NAMES" ]]; then
        printf 'Excluded (explicit legacy classification): %s\n' "$EXCLUDED_SUITE_NAMES"
    fi
    printf 'Assertions: %s  Passed: %s  Skipped: %s  Failed: %s\n' \
        "$((PASSES + SKIPS + FAILS))" "$PASSES" "$SKIPS" "$FAILS"
    printf 'Evidence tiers: static=%s  isolated=%s  live=%s  unlabelled=%s\n' \
        "$STATIC_ASSERTIONS" "$ISOLATED_ASSERTIONS" "$LIVE_ASSERTIONS" "$UNLABELLED_ASSERTIONS"

    if (( FAILS > 0 || SUITE_FAILURES > 0 )); then
        exit 1
    fi
    if (( SKIPS > 0 )) && [[ "${AURELIA_TESTS_REQUIRE_NO_SKIPS:-0}" == "1" ]]; then
        printf 'Strict test mode rejected %s skipped assertion path(s).\n' "$SKIPS" >&2
        exit 2
    fi
    if (( SKIPS > 0 )); then
        printf 'Diagnostic mode accepted %s explicitly reported skipped assertion path(s).\n' "$SKIPS"
    fi
    exit 0
}
