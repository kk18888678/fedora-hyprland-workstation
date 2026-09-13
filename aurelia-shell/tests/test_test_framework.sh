#!/usr/bin/env bash

# T43 test-framework contract. This suite proves that skipped coverage is not
# counted as a pass and that backend-only limitations cannot mask QML errors.

set -Eeuo pipefail

section "Aurelia Test Framework Truthfulness"

accounting_output="$(
    bash -c 'set -Eeuo pipefail; source "$1"; pass executed; skip unavailable; printf "counts=%s:%s:%s\n" "$PASSES" "$SKIPS" "$FAILS"' _ \
        "$ROOT/tests/test_helper.sh"
)"
if [[ "$accounting_output" == *"counts=1:1:0"* ]] &&
   [[ "$accounting_output" == *"PASS executed"* ]] &&
   [[ "$accounting_output" == *"SKIP unavailable"* ]] &&
   [[ "$accounting_output" != *"PASS unavailable"* ]]; then
    pass "[isolated-framework] skip has independent accounting and cannot inflate the pass count"
else
    fail "[isolated-framework] skip/pass accounting is not independent: $accounting_output"
fi

strict_root="$(mktemp -d)"
trap 'rm -rf -- "$strict_root" 2>/dev/null || true' RETURN
strict_status=0
AURELIA_TESTS_REQUIRE_NO_SKIPS=1 bash -c 'set -Eeuo pipefail; source "$1"; skip unavailable; print_test_summary' _ \
    "$ROOT/tests/test_helper.sh" \
    >"$strict_root/strict.out" 2>"$strict_root/strict.err" || strict_status=$?
if [[ "$strict_status" -eq 2 ]] &&
   grep -Fq 'Passed: 0  Skipped: 1  Failed: 0' "$strict_root/strict.out" &&
   grep -Fq 'Strict test mode rejected 1 skipped test path(s).' "$strict_root/strict.err"; then
    pass "[isolated-framework] strict mode returns a distinct non-zero result for skipped coverage"
else
    fail "[isolated-framework] strict no-skip gate is incomplete (status=$strict_status)"
fi

clean_log="$strict_root/clean.log"
diagnostic_source_prefix='file://'
printf '%s\n' \
    'ERROR quickshell.ipc: Failed to start IPC server on path /tmp/ipc.sock' \
    "WARN scene: ${diagnostic_source_prefix}/tmp/test.qml[1:1]: No PanelWindow backend loaded" \
    >"$clean_log"
dirty_log="$strict_root/dirty.log"
printf '%s\n' \
    'ERROR quickshell.ipc: Failed to start IPC server on path /tmp/ipc.sock' \
    "WARN scene: ${diagnostic_source_prefix}/tmp/test.qml[1:1]: No PanelWindow backend loaded" \
    "WARN scene: ${diagnostic_source_prefix}/tmp/test.qml[2:1]: TypeError: Cannot assign object of type Process" \
    >"$dirty_log"
if runtime_log_is_environment_only "$clean_log" &&
   ! runtime_log_is_environment_only "$dirty_log"; then
    pass "[isolated-framework] runtime skip classifier accepts only approved backend diagnostics"
else
    fail "[isolated-framework] runtime skip classifier masked an unrelated diagnostic"
fi

isolated_suite="$strict_root/child-suite.sh"
printf '%s\n' 'pass child-suite-pass' 'skip child-suite-skip' >"$isolated_suite"
suite_output="$strict_root/child-suite.out"
before_passes="$PASSES"
before_skips="$SKIPS"
before_fails="$FAILS"
run_suite "$isolated_suite" >"$suite_output"
if [[ "$PASSES" -eq $((before_passes + 1)) ]] &&
   [[ "$SKIPS" -eq $((before_skips + 1)) ]] &&
   [[ "$FAILS" -eq "$before_fails" ]] &&
   grep -Fq 'PASS child-suite-pass' "$suite_output" &&
   grep -Fq 'SKIP child-suite-skip' "$suite_output"; then
    pass "[isolated-framework] each suite runs in a fresh child process and aggregates explicit outcomes"
else
    fail "[isolated-framework] suite isolation or parent aggregation is incomplete"
fi

legacy_skip_paths=0
while IFS= read -r test_path; do
    case "$test_path" in
        */test_test_framework.sh|*/test_helper.sh) continue ;;
    esac
    if rg -n 'pass \"[^\"]*(SKIP|skipped)' "$test_path" >/dev/null 2>&1 ||
       rg -n 'printf .*SKIP' "$test_path" >/dev/null 2>&1; then
        legacy_skip_paths=1
        break
    fi
done < <(rg --files "$ROOT/tests" -g 'test_*.sh')

if [[ "$legacy_skip_paths" -eq 0 ]]; then
    pass "[static] all Aurelia test skip paths use the explicit skip primitive"
else
    fail "[static] legacy pass/printf skip paths remain in the Aurelia test suites"
fi

if grep -Fq -- '--strict' "$ROOT/tests/run.sh" &&
   grep -Fq 'AURELIA_TESTS_REQUIRE_NO_SKIPS=1' "$ROOT/tests/run.sh"; then
    pass "[static] the public Aurelia test runner exposes an explicit strict no-skip gate"
else
    fail "[static] strict no-skip runner mode is not exposed"
fi
