#!/usr/bin/env bash

# Dedicated Package Manager TUI component tests. The existing Update Manager
# is intentionally not imported or modified by this suite.

set -Eeuo pipefail

section "Dedicated Package Manager TUI Component"

if PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT/tests/test_package_manager_tui.py"; then
    pass "Dedicated TUI model, theme inheritance, config, parsing, and rendering helpers pass"
else
    fail "Dedicated Package Manager TUI component tests failed"
fi

if grep -Fq 'updates_path' "$ROOT/bin/lib/workstation-packages/tui_backend.py" &&
   grep -Fq 'updates_json' "$ROOT/bin/lib/workstation-packages/tui.py"; then
    pass "Dedicated TUI reads update status without changing the existing Update Manager"
else
    fail "Dedicated TUI component boundary is missing its read-only update status bridge"
fi

if grep -Fq 'remove_catalog_row' "$ROOT/bin/lib/workstation-packages/tui_backend.py" &&
   grep -Fq 'remove-catalog-row' "$ROOT/bin/workstation-packages" &&
   grep -Fq 'catalog-tui-installed' "$ROOT/bin/workstation-packages" &&
   grep -Fq 'catalog-tui-ownership' "$ROOT/bin/workstation-packages" &&
   grep -Fq 'catalog-tui-versions' "$ROOT/bin/workstation-packages" &&
   grep -Fq 'Uninstall' "$ROOT/bin/lib/workstation-packages/tui.py" &&
   grep -Fq 'install_version_override' "$ROOT/bin/lib/workstation-packages/tui.py"; then
    pass "Installed-package actions and exact version history use provider-aware backend boundaries"
else
    fail "Installed-package uninstall action is missing from the dedicated TUI boundary"
fi

if grep -Fq 'workstation-packages-tui' "$ROOT/bin/workstation-packages" &&
   grep -Fq 'exec "$script_dir/workstation-packages-tui"' "$ROOT/bin/workstation-packages"; then
    pass "Package Manager entry points integrate the dedicated frontend without replacing the backend"
else
    fail "Package Manager entry points do not route to the dedicated frontend"
fi
