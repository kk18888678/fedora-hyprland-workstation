#!/usr/bin/env bash

# Standalone Aurelia Shell test runner. The Fedora workstation test runner does
# not load this tree; Aurelia owns its own plugin, backend, and runtime tests.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"

run_suite "$ROOT/tests/test_aurelia_shell_plugins.sh"
run_suite "$ROOT/tests/test_dev_session.sh"
run_suite "$ROOT/tests/test_keybindings_interaction.sh"
run_suite "$ROOT/tests/test_screenshot_plugins.sh"
run_suite "$ROOT/tests/test_qml_runtime.sh"
run_suite "$ROOT/tests/test_bar_widgets.sh"
run_suite "$ROOT/tests/test_launcher_plugin.sh"
run_suite "$ROOT/tests/test_hyprland_provider.sh"

print_test_summary
