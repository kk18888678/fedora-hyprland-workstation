#!/usr/bin/env bash

# Standalone Aurelia Shell test runner. The Fedora workstation test runner does
# not load this tree; Aurelia owns its own plugin, backend, and runtime tests.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"

test_mode="strict"
case "${1:-}" in
    "") ;;
    --strict)
        test_mode="strict"
        shift
        ;;
    --allow-skips)
        test_mode="allow-skips"
        shift
        ;;
    --help|-h)
        printf 'Usage: %s [--strict|--allow-skips]\n' "${BASH_SOURCE[0]}"
        printf '%s\n' '  --strict        default; return 2 when any assertion path is skipped'
        printf '%s\n' '  --allow-skips   diagnostic mode; report, but do not reject, environment skips'
        exit 0
        ;;
    *)
        printf 'Usage: %s [--strict|--allow-skips]\n' "${BASH_SOURCE[0]}" >&2
        exit 2
        ;;
esac

(( $# == 0 )) || exit 2

# The normal command is deliberately strict. The opt-in diagnostic mode is
# only for inspecting a headless workstation where an acceptance backend is
# unavailable; it never turns a skipped assertion into a pass.
if [[ "$test_mode" == "strict" ]]; then
    export AURELIA_TESTS_REQUIRE_NO_SKIPS=1
else
    export AURELIA_TESTS_REQUIRE_NO_SKIPS=0
fi

run_suite "$ROOT/tests/test_test_framework.sh"

# Every current Aurelia-owned test_*.sh file in this directory is a suite
# entry point except the shared helper and the framework contract suite above.
# These four legacy repository matrices are retained at their existing paths
# for historical reference, but are not Aurelia suites: their contracts point
# at removed installer paths and their execution is tracked separately instead
# of being presented as shell coverage.
excluded_legacy_suites=(
    test_aurelia_hotkeys.sh
    test_aurelia_keybindings.sh
    test_hotkeys.sh
    test_quickshell_provenance.sh
)
EXCLUDED_SUITES=0
EXCLUDED_SUITE_NAMES=""
candidate_suite_count=0
while IFS= read -r -d '' suite_file; do
    candidate_suite_count=$((candidate_suite_count + 1))
    [[ "$suite_file" == "$ROOT/tests/test_test_framework.sh" ]] && continue
    suite_name="${suite_file##*/}"
    excluded=0
    for excluded_suite in "${excluded_legacy_suites[@]}"; do
        if [[ "$suite_name" == "$excluded_suite" ]]; then
            excluded=1
            break
        fi
    done
    if (( excluded )); then
        EXCLUDED_SUITES=$((EXCLUDED_SUITES + 1))
        EXCLUDED_SUITE_NAMES="${EXCLUDED_SUITE_NAMES:+$EXCLUDED_SUITE_NAMES,}$suite_name"
        continue
    fi
    run_suite "$suite_file"
done < <(find "$ROOT/tests" -maxdepth 1 -type f -name 'test_*.sh' \
    ! -name 'test_helper.sh' -print0 | sort -z)

expected_suite_count=$((candidate_suite_count - EXCLUDED_SUITES))
if [[ "$SUITES" -ne "$expected_suite_count" ]]; then
    fail "Suite discovery executed $SUITES of $expected_suite_count owned suite entry points"
fi

print_test_summary
