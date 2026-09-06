#!/usr/bin/env bash

# Configuration architecture test entry point. The numbered domains live in
# tests/config_architecture_sections/ to keep planner/reconciler tests focused.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"
for suite in "$ROOT/tests/config_architecture_sections"/[0-9][0-9]_*.sh; do
    # shellcheck source=/dev/null
    source "$suite"
done
