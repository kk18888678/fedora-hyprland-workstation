#!/usr/bin/env bash

# Aurelia Keybindings test entry point. Domain sections live in
# tests/aurelia_keybindings_sections/ so the runner remains one command while
# each test file has one coherent responsibility.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
for suite in "$ROOT/tests/aurelia_keybindings_sections"/[0-9][0-9]_*.sh; do
    # shellcheck source=/dev/null
    source "$suite"
done
