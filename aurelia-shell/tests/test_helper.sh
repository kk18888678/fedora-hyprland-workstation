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

# Runtime fixture diagnostics are consumed line by line. No diagnostic is
# deleted from the stream before classification: an approved environment
# limitation is printed, while every other WARN/ERROR/FATAL/QML failure is
# printed as unexpected and fails the caller.
runtime_log_line_is_diagnostic() {
    local line="$1"
    [[ "$line" == *WARN* || "$line" == *ERROR* || "$line" == *FATAL* ||
       "$line" == *ReferenceError* || "$line" == *TypeError* ||
       "$line" == *QML\ Error* || "$line" == *"Segmentation fault"* ||
       "$line" == *Cannot\ assign* || "$line" == *Loader.Error* ]]
}

runtime_log_line_is_window_backend_failure() {
    local line="$1"
    [[ "$line" == *"No PanelWindow backend loaded"* ||
       "$line" == *"Failed to create wl_display"* ||
       "$line" == *"Could not load the Qt platform plugin"* ]]
}

runtime_log_line_matches_extra() {
    local line="$1"
    local extra_allowed="${2:-}"
    [[ -n "$extra_allowed" && "$line" =~ $extra_allowed ]]
}

runtime_log_contains_window_backend_failure() {
    local log_file="$1"
    local line

    [[ -f "$log_file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        if runtime_log_line_is_window_backend_failure "$line"; then return 0; fi
    done <"$log_file"
    return 1
}

runtime_log_line_is_environment_only() {
    local line="$1"
    local extra_allowed="${2:-}"
    local backend_failure_seen="${3:-0}"

    case "$line" in
        *"ERROR quickshell.ipc: Failed to start IPC server on path "*|\
        *"Failed to create wl_display"*|\
        *"Could not create instance runtime directory"*|\
        *"Could not load the Qt platform plugin"*|\
        *"No PanelWindow backend loaded"*|\
        *"Failed to connect to UPower"*|\
        *"Could not connect to UPower"*|\
        *"UPower"*"unavailable"*|\
        *"Failed to connect pipewire context"*|\
        *"Signal QQmlEngine::quit() emitted"*|\
        *"Failed to connect to system scope bus via local transport: Operation not permitted"*)
            return 0
            ;;
    esac

    # A dependent QML type may be reported unavailable only after the window
    # backend failure above is present in the same complete log. Never accept
    # these names on their own.
    if [[ "$backend_failure_seen" == "1" ]] &&
       [[ "$line" == *"Type AureliaKeyboardPanel unavailable"* ||
          "$line" == *"Type CommandCenterPanel unavailable"* ||
          "$line" == *"Type WallpapersPanel unavailable"* ||
          "$line" == *"Type BarPanel unavailable"* ||
          "$line" == *"Type ScreenMoveRemap unavailable"* ||
          "$line" == *"ERROR: Failed to load configuration"* ||
          "$line" =~ \[[A-Z]+\][[:space:]].*(panel|wifiqr)_load_failed ]]; then
        return 0
    fi

    if runtime_log_line_matches_extra "$line" "$extra_allowed"; then return 0; fi
    return 1
}

runtime_log_has_environment_diagnostic() {
    local log_file="$1"
    local extra_allowed="${2:-}"
    local line

    [[ -f "$log_file" ]] || return 1
    local backend_failure_seen=0
    if runtime_log_contains_window_backend_failure "$log_file"; then backend_failure_seen=1; fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        if runtime_log_line_is_diagnostic "$line" &&
           runtime_log_line_is_environment_only "$line" "$extra_allowed" "$backend_failure_seen"; then
            return 0
        fi
    done <"$log_file"
    return 1
}

runtime_log_is_environment_only() {
    local log_file="$1"
    local extra_allowed="${2:-}"
    local line
    local unexpected=0
    local backend_failure_seen=0

    [[ -f "$log_file" ]] || return 1
    if runtime_log_contains_window_backend_failure "$log_file"; then backend_failure_seen=1; fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        runtime_log_line_is_diagnostic "$line" || continue
        if runtime_log_line_is_environment_only "$line" "$extra_allowed" "$backend_failure_seen"; then
            if runtime_log_line_matches_extra "$line" "$extra_allowed"; then
                printf '  Expected diagnostic: %s\n' "$line" >&2
            else
                printf '  Environment diagnostic: %s\n' "$line" >&2
            fi
        else
            printf '  Unexpected diagnostic: %s\n' "$line" >&2
            unexpected=1
        fi
    done <"$log_file"

    if (( unexpected == 0 )); then return 0; fi
    return 1
}

# Negative fixtures intentionally contain a diagnostic that must be rejected.
# Keep those lines visible, but label them as expected test evidence so a
# passing test run cannot be mistaken for an unnoticed production failure.
runtime_log_has_rejected_diagnostic() {
    local log_file="$1"
    local line
    local rejected=0
    local backend_failure_seen=0

    [[ -f "$log_file" ]] || return 1
    if runtime_log_contains_window_backend_failure "$log_file"; then backend_failure_seen=1; fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        runtime_log_line_is_diagnostic "$line" || continue
        if runtime_log_line_is_environment_only "$line" "" "$backend_failure_seen"; then
            printf '  Environment diagnostic: %s\n' "$line" >&2
        else
            printf '  Expected rejected diagnostic: %s\n' "$line" >&2
            rejected=1
        fi
    done <"$log_file"

    (( rejected == 1 ))
}

runtime_skip_if_environment_only() {
    local log_file="$1"
    local description="$2"
    local extra_allowed="${3:-}"
    runtime_log_is_environment_only "$log_file" "$extra_allowed" || return 1
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
