#!/usr/bin/env bash

# Test Suite: Syntax, duplicate functions, required repository paths, and hygiene.

section "Syntax"

mapfile -t BASH_FILES < <(
    find "$ROOT" -type f -name '*.sh' | sort
)

for file in "${BASH_FILES[@]}"; do
    if bash -n "$file"; then
        pass "bash -n ${file#"$ROOT"/}"
    else
        fail "bash -n ${file#"$ROOT"/}"
    fi
done

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck --shell=bash \
        --exclude=SC1090,SC1091,SC2034,SC2154,SC2329 \
        "${BASH_FILES[@]}"; then
        pass "shellcheck"
    else
        fail "shellcheck"
    fi
else
    printf '  SKIP shellcheck (not installed)\n'
fi

section "Duplicate function definitions"

dupes="$(
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$ROOT"/modules/*.sh "$ROOT"/modules/lib/*.sh 2>/dev/null |
        sed 's/() {//' |
        grep -vx die |
        sort |
        uniq -d || true
)"

if [[ -z "$dupes" ]]; then
    pass "no duplicate function names across modules"
else
    fail "duplicate functions: $dupes"
fi

section "Repository paths"

required_paths=(
    install.sh
    config/versions.conf
    config/noctalia-greeter/greeter.toml
    packages/base.txt
    packages/desktop.txt
    packages/media.txt
    packages/diagnostics.txt
    dotfiles/nvim/init.lua
    profiles/vm.conf
    profiles/workstation.conf
    modules/common.sh
    modules/lib/output.sh
    modules/lib/execution.sh
    modules/lib/filesystem.sh
    modules/lib/packages.sh
    modules/lib/artifacts.sh
    modules/status.sh
    modules/state.sh
    modules/repositories.sh
    modules/packages.sh
    modules/shell.sh
    modules/browsers.sh
    modules/applications.sh
    modules/flatpak.sh
    modules/desktop.sh
    modules/nix.sh
    modules/containers.sh
    modules/validation.sh
    dotfiles/zsh/.zshrc
    dotfiles/starship/starship.toml
    dotfiles/kitty/kitty.conf
    dotfiles/hypr/hyprland.lua
    scripts/check-updates.sh
    docs/ARCHITECTURE.md
    docs/SAFETY.md
    docs/RELEASE-POLICY.md
)

for rel in "${required_paths[@]}"; do
    if [[ -e "$ROOT/$rel" ]]; then
        pass "exists $rel"
    else
        fail "missing $rel"
    fi
done

section "Repository Hygiene"
if git -C "$ROOT" ls-files | grep -E '(\.auth|\.token|jetski_state|settings\.json|credentials|\.db|\.key|\.pem)'; then
    fail "sensitive or authentication file tracked in git"
else
    pass "no authentication or secret files tracked in git"
fi
