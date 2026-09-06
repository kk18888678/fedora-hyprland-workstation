#!/usr/bin/env bash

# Workstation keybinding backend test entry point. Domain suites live in
# tests/hotkeys_sections/ so backend, installation, persistence, and runtime
# tests do not accumulate in one file.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"
for suite in "$ROOT/tests/hotkeys_sections"/[0-9][0-9]_*.sh; do
    # shellcheck source=/dev/null
    source "$suite"
done
