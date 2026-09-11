#!/usr/bin/env bash

# T02 test-domain harness. It establishes reusable plugin fixtures and a
# preservation baseline; behavior-changing parity tests belong to later tasks.

set -Eeuo pipefail

source "$ROOT/tests/plugin/harness.sh"
source "$ROOT/tests/plugin/fixtures.sh"
source "$ROOT/tests/plugin/preservation.sh"

section "Aurelia Plugin Test Harness"

if ! plugin_harness_setup; then
    plugin_harness_fail fixture "could not create a safe temporary plugin sandbox"
    return 0
fi

plugin_harness_run_fixture_contract
plugin_harness_run_preservation_contract
plugin_harness_cleanup
