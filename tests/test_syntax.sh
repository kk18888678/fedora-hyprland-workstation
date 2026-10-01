#!/usr/bin/env bash

# Test Suite: Syntax, duplicate functions, required repository paths, and hygiene.

section "Syntax"

mapfile -t BASH_FILES < <(
    find "$ROOT" -path "$ROOT/aurelia-shell" -prune -o -type f -name '*.sh' -print | sort
)

for file in "${BASH_FILES[@]}"; do
    if bash -n "$file"; then
        pass "bash -n ${file#"$ROOT"/}"
    else
        fail "bash -n ${file#"$ROOT"/}"
    fi
done

if command -v shellcheck >/dev/null; then
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
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$ROOT"/modules/*.sh "$ROOT"/modules/lib/*.sh  |
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
    config/session-shell/noctalia
    config/session-shell/aurelia
    packages/base.txt
    packages/desktop.txt
    packages/aurelia.txt
    packages/bluetooth.txt
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
if git -C "$ROOT" ls-files | grep -E '(^|/)(\.auth|\.token|jetski_state|settings\.json|credentials|[^/]+\.(db|key|pem))$'; then
    fail "sensitive or authentication file tracked in git"
else
    pass "no authentication or secret files tracked in git"
fi

section "SIGPIPE-safe grep producers"

# A producer piped into a quiet grep is unsafe under `set -o pipefail`: the
# consumer exits on its first match, the producer can take SIGPIPE (exit 141),
# and the pipeline result inverts. Producers must use a here-string instead.
# Assemble the tokens at runtime so this guard does not contain the forbidden
# source text it is required to detect.
sigpipe_producer='printf'
sigpipe_consumer='grep -q'
sigpipe_chain_pattern="${sigpipe_producer} .*\\|[[:space:]]*${sigpipe_consumer}"

sigpipe_scan_status=0
sigpipe_offenders="$(
    grep -rnE "$sigpipe_chain_pattern" \
        "$ROOT/tests" "$ROOT/aurelia-shell/tests" \
        --include='*.sh'
)" || sigpipe_scan_status=$?

if (( sigpipe_scan_status > 1 )); then
    fail "SIGPIPE guard scan failed with status $sigpipe_scan_status"
elif [[ -n "$sigpipe_offenders" ]]; then
    while IFS= read -r offender; do
        fail "SIGPIPE-unsafe quiet-grep pipeline: $offender"
    done <<<"$sigpipe_offenders"
else
    pass "no SIGPIPE-unsafe quiet-grep pipelines in tests or aurelia-shell tests"
fi
