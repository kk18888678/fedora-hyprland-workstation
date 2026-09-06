#!/usr/bin/env bash

# Test Suite: Aurelia Foundation, Quickshell Integration, Native Hotkeys Component, and Desktop Coexistence.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SCRIPT_DIR="$ROOT"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"

# Source component and planner modules
# shellcheck source=/dev/null
source "$ROOT/modules/lib/components.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/desired_state.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/planner.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/lib/reconciler.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/status.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/desktop.sh"

lua_bin="$(command -v luajit 2>/dev/null || command -v lua 2>/dev/null || true)"
