#!/usr/bin/env bash

# Focused tests for the source-checkout Aurelia development session helpers.

set -Eeuo pipefail

section "Aurelia Development tmux Session"

if [[ -x "$ROOT/bin/aurelia-dev-tmux" && -x "$ROOT/bin/aurelia-dev-console" && -x "$ROOT/bin/aurelia-restart-shell" ]]; then
    pass "Aurelia development helpers and deterministic restart command are executable"
else
    fail "Aurelia development tmux helpers are missing or not executable"
fi

help_output="$("$ROOT/bin/aurelia-dev-tmux" --help 2>&1)"
if [[ "$help_output" == *"pane 0: resident Aurelia Shell host"* &&
      "$help_output" == *"pane 1: readiness probe"* ]]; then
    pass "tmux helper documents the two-pane development workflow"
else
    fail "tmux helper help output does not describe the development workflow"
fi

invalid_session_status=0
invalid_session_output="$("$ROOT/bin/aurelia-dev-tmux" --session 'unsafe/name' --no-attach 2>&1)" ||
    invalid_session_status=$?
if [[ "$invalid_session_status" -eq 2 &&
      "$invalid_session_output" == *"session name may contain only"* ]]; then
    pass "tmux helper rejects unsafe session names before invoking tmux"
else
    fail "tmux helper accepted an unsafe session name: rc=$invalid_session_status output=$invalid_session_output"
fi

if grep -q 'AURELIA_DEVELOPMENT_MODE=1' "$ROOT/bin/aurelia-dev-tmux" &&
   grep -q 'AURELIA_SHELL_ROOT=' "$ROOT/bin/aurelia-dev-tmux" &&
   grep -q 'QUICKSHELL_BIN=' "$ROOT/bin/aurelia-dev-tmux" &&
   grep -q 'aurelia-dev-console' "$ROOT/bin/aurelia-dev-tmux"; then
    pass "tmux panes receive explicit source-checkout Aurelia runtime context"
else
    fail "tmux helper does not define the required Aurelia runtime context"
fi

if grep -q 'source_shell_root' "$ROOT/bin/aurelia-launch-shell" &&
   grep -q 'source_shell_root' "$ROOT/bin/aurelia-shell" &&
   grep -q 'kill --pid' "$ROOT/bin/aurelia-restart-shell" &&
   grep -q 'Process ID:' "$ROOT/bin/aurelia-restart-shell" &&
   grep -q 'AURELIA_SHELL_ROOT=' "$ROOT/bin/aurelia-restart-shell"; then
    pass "source checkout auto-detection removes repeated development exports and restart is scoped to Aurelia"
else
    fail "Aurelia source auto-detection or scoped restart contract is incomplete"
fi

if grep -q 'resolve_aurelia_launcher' "$ROOT/../dotfiles/hypr/startup.lua" &&
   grep -q 'aurelia-launch-shell' "$ROOT/../dotfiles/hypr/startup.lua" &&
   grep -q 'AURELIA_SHELL_LAUNCHER' "$ROOT/../dotfiles/hypr/startup.lua" &&
   grep -q -- '--no-duplicate' "$ROOT/bin/aurelia-launch-shell"; then
    pass "Hyprland startup autostarts the single resident Aurelia Shell with source and installed path resolution"
else
    fail "Aurelia Shell Hyprland autostart contract is incomplete"
fi
