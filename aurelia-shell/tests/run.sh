#!/usr/bin/env bash

# Standalone Aurelia Shell test runner. The Fedora workstation test runner does
# not load this tree; Aurelia owns its own plugin, backend, and runtime tests.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"

run_suite "$ROOT/tests/test_aurelia_shell_plugins.sh"

print_test_summary
