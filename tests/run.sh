#!/usr/bin/env bash

# Local static and unit tests runner for the Fedora Hyprland workstation installer.
# These tests do not provision a VM and do not modify the host desktop.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"

run_suite "$ROOT/tests/test_syntax.sh"
run_suite "$ROOT/tests/test_common.sh"
run_suite "$ROOT/tests/test_execution.sh"
run_suite "$ROOT/tests/test_filesystem.sh"
run_suite "$ROOT/tests/test_state.sh"
run_suite "$ROOT/tests/test_packages.sh"
run_suite "$ROOT/tests/test_applications.sh"
run_suite "$ROOT/tests/test_release_policy.sh"
run_suite "$ROOT/tests/test_supply_chain.sh"
run_suite "$ROOT/tests/test_config_architecture.sh"

run_suite "$ROOT/tests/test_xdg.sh"
run_suite "$ROOT/tests/test_desktop.sh"
run_suite "$ROOT/tests/test_hotkeys.sh"
run_suite "$ROOT/tests/test_aurelia_hotkeys.sh"
run_suite "$ROOT/tests/test_aurelia_keybindings.sh"
run_suite "$ROOT/tests/test_quickshell_provenance.sh"
run_suite "$ROOT/tests/test_validation.sh"
run_suite "$ROOT/tests/test_resilience.sh"

print_test_summary
