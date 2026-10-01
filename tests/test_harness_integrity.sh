#!/usr/bin/env bash

# Harness integrity regression tests.
#
# HIDDEN-FAILURE INVARIANT (pre-existing defect, confirmed on origin/main):
# tests/test_helper.sh used to initialise its counters as top-level
# `FAILS=0` / `PASSES=0` assignments. tests/test_config_architecture.sh
# re-sources the helper while the aggregate runner is still live, so the
# re-source reset both counters mid-run. Because print_test_summary exits on
# FAILS alone, a failure recorded before the re-source was erased while
# ./tests/run.sh still exited 0 and printed "Failed: 0". The raw "  FAIL ..."
# lines were the only surviving evidence, which is why this repository's
# results have had to be judged on raw line counts rather than the summary.
#
# These tests pin the invariant: the helper must be idempotent under
# re-sourcing, and the aggregate summary must equal the raw outcome lines.

# (1) A recorded FAIL must survive a second source of the helper.
resource_fail_output="$(
    bash -c 'set -Eeuo pipefail; source "$1"; fail recorded-before-resource; source "$1"; printf "FAILS=%s PASSES=%s\n" "$FAILS" "$PASSES"' _ \
        "$ROOT/tests/test_helper.sh"
)"
if [[ "$resource_fail_output" == "  FAIL recorded-before-resource"* ]] &&
   [[ "$resource_fail_output" == *"FAILS=1 PASSES=0"* ]]; then
    pass "[isolated-helper] FAILS survives a second source of test_helper.sh"
else
    fail "[isolated-helper] FAILS was erased by a helper re-source: ${resource_fail_output//$'\n'/ | }"
fi

# (2) A recorded PASS must survive a second source of the helper.
resource_pass_output="$(
    bash -c 'set -Eeuo pipefail; source "$1"; pass recorded-before-resource; source "$1"; printf "FAILS=%s PASSES=%s\n" "$FAILS" "$PASSES"' _ \
        "$ROOT/tests/test_helper.sh"
)"
if [[ "$resource_pass_output" == "  PASS recorded-before-resource"* ]] &&
   [[ "$resource_pass_output" == *"FAILS=0 PASSES=1"* ]]; then
    pass "[isolated-helper] PASSES survives a second source of test_helper.sh"
else
    fail "[isolated-helper] PASSES was erased by a helper re-source: ${resource_pass_output//$'\n'/ | }"
fi

# (3) The aggregate runner's summary must equal its raw outcome lines. Every
# suite is sourced into one shell by tests/run.sh, so each pass/fail call feeds
# the same counter and the equality is exact (never a >= check). The runner is
# exercised in a guarded child (WORKSTATION_HARNESS_SUMMARY_SELFCHECK) so this
# test cannot recurse; the child defers this branch and still runs every other
# suite, so the comparison remains a full aggregate run.
if [[ "${WORKSTATION_HARNESS_SUMMARY_SELFCHECK:-0}" == "1" ]]; then
    pass "[isolated-harness] aggregate summary self-check deferred inside the guarded child run"
else
    nested_status=0
    nested_output="$(
        WORKSTATION_HARNESS_SUMMARY_SELFCHECK=1 timeout 900 "$ROOT/tests/run.sh" 2>&1
    )" || nested_status=$?
    nested_raw_pass="$(printf '%s\n' "$nested_output" | grep -c '^  PASS ' || true)"
    nested_raw_fail="$(printf '%s\n' "$nested_output" | grep -c '^  FAIL ' || true)"
    nested_summary_pass="$(printf '%s\n' "$nested_output" |
        sed -n 's/^Passed: \([0-9][0-9]*\)  Failed: [0-9][0-9]*$/\1/p' | tail -n1)"
    nested_summary_fail="$(printf '%s\n' "$nested_output" |
        sed -n 's/^Passed: [0-9][0-9]*  Failed: \([0-9][0-9]*\)$/\1/p' | tail -n1)"
    if [[ -n "$nested_summary_pass" && -n "$nested_summary_fail" ]] &&
       [[ "$nested_summary_pass" == "$nested_raw_pass" ]] &&
       [[ "$nested_summary_fail" == "$nested_raw_fail" ]]; then
        pass "[isolated-harness] ./tests/run.sh summary equals raw PASS/FAIL lines (Passed=$nested_summary_pass Failed=$nested_summary_fail)"
    else
        printf '  Nested ./tests/run.sh exit=%s summary Passed=%s Failed=%s raw PASS=%s FAIL=%s\n' \
            "$nested_status" "${nested_summary_pass:-<none>}" "${nested_summary_fail:-<none>}" \
            "$nested_raw_pass" "$nested_raw_fail" >&2
        printf '%s\n' "$nested_output" | grep -E '^  FAIL |^Passed:' >&2 || true
        fail "[isolated-harness] ./tests/run.sh summary does not equal its raw PASS/FAIL line counts"
    fi
fi
