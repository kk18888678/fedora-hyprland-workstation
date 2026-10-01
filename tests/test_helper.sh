#!/usr/bin/env bash

# Test harness and assertion helpers.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER_ROOT="$ROOT"
export ROOT
export HELPER_ROOT
export WORKSTATION_TEST_MODE=1

# Counters must be idempotent under re-sourcing. tests/test_config_architecture.sh
# re-sources this file while the aggregate runner is live; unconditional
# assignment here used to erase every outcome recorded before the re-source,
# hiding failures because print_test_summary exits on FAILS alone.
: "${FAILS:=0}"
: "${PASSES:=0}"

pass() {
    PASSES=$((PASSES + 1))
    printf '  PASS %s\n' "$*"
}

fail() {
    FAILS=$((FAILS + 1))
    printf '  FAIL %s\n' "$*"
}

section() {
    printf '\n== %s ==\n' "$*"
}

run_suite() {
    local suite_file="$1"
    if [[ -f "$suite_file" ]]; then
        # shellcheck source=/dev/null
        source "$suite_file"
    else
        fail "Test suite not found: $suite_file"
    fi
}

print_test_summary() {
    printf '\n%s\n' "------------------------------------------------------------"
    printf 'Passed: %s  Failed: %s\n' "$PASSES" "$FAILS"

    if (( FAILS > 0 )); then
        exit 1
    fi
    exit 0
}
