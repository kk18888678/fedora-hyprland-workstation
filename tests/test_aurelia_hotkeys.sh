#!/usr/bin/env bash

# Aurelia/desktop compatibility test entry point. The numbered domains live
# in tests/aurelia_hotkeys_sections/ so the single repository runner remains
# stable without retaining a monolithic test file.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
for suite in "$ROOT/tests/aurelia_hotkeys_sections"/[0-9][0-9]_*.sh; do
    # shellcheck source=/dev/null
    source "$suite"
done
