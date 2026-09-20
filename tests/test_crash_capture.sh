#!/usr/bin/env bash

# Crash-capture/diagnosis repository contract: the installer deployment, the
# user systemd unit, the extended workstation-ai crash handoff, and the
# evidence-first skill files. Static and isolated; no live system mutation.

set -Eeuo pipefail

section "Crash Capture and Diagnosis Repository Contract"

for backend in \
    aurelia-crash-watch \
    aurelia-crash-mute \
    aurelia-toggle-crash-capture \
    aurelia-agent-crash \
    aurelia-notification-wait; do
    if [[ -x "$ROOT/aurelia-shell/bin/$backend" ]]; then
        pass "crash backend exists and is executable: $backend"
    else
        fail "crash backend is missing or not executable: $backend"
    fi
done

unit="$ROOT/aurelia-shell/systemd/user/aurelia-crash-watch.service"
if [[ -f "$unit" ]] &&
   grep -Fx 'ExecStart=/usr/local/bin/aurelia-crash-watch' "$unit" >/dev/null &&
   grep -Fx 'WantedBy=graphical-session.target' "$unit" >/dev/null &&
   grep -Fx 'PartOf=graphical-session.target' "$unit" >/dev/null &&
   grep -Fx 'ConditionPathExists=!%h/.local/state/aurelia/toggles/crash-capture-off' "$unit" >/dev/null &&
   grep -Fx 'Restart=always' "$unit" >/dev/null; then
    pass "the crash watcher user unit has a bounded, flag-gated lifecycle"
else
    fail "the crash watcher user unit is missing or incomplete"
fi

if grep -q 'install_crash_capture()' "$ROOT/modules/desktop.sh" &&
   grep -q 'install_crash_capture$' "$ROOT/modules/desktop.sh" &&
   grep -q 'graphical-session.target.wants' "$ROOT/modules/desktop.sh" &&
   grep -q 'install_root_cli_file' "$ROOT/modules/desktop.sh" &&
   grep -q 'aurelia-notification-send' "$ROOT/modules/desktop.sh" &&
   grep -q 'record_deferred "desktop" "crash-' "$ROOT/modules/desktop.sh" &&
   ! grep -q 'chown -R' "$ROOT/modules/desktop.sh"; then
    pass "the installer deploys the crash backends and unit non-blockingly"
else
    fail "the installer does not deploy the crash feature safely"
fi

if grep -q 'diagnose-crash' "$ROOT/modules/desktop.sh" &&
   grep -q 'diagnose-crash' "$ROOT/bin/workstation-ai" &&
   grep -q 'aurelia-shell/bin/aurelia' "$ROOT/modules/desktop.sh"; then
    pass "the installer ships the diagnose-crash skill and the aurelia CLI"
else
    fail "the diagnose-crash skill or aurelia CLI is not shipped"
fi

crash_skill="$ROOT/config/agent-skill/diagnose-crash/SKILL.md"
reporting="$ROOT/config/agent-skill/diagnose-crash/reporting.md"
if [[ -f "$crash_skill" && -f "$reporting" ]] &&
   grep -q '^name: diagnose-crash' "$crash_skill" &&
   grep -q 'coredumpctl info' "$crash_skill" &&
   grep -q 'coredumpctl list' "$crash_skill" &&
   grep -q 'Metadata only' "$crash_skill" &&
   grep -qi 'never extract, copy, or read a core dump' "$crash_skill" &&
   ! grep -q 'coredumpctl dump' "$crash_skill" &&
   ! grep -q 'debuginfod' "$crash_skill" &&
   ! grep -Eq '(^|[^[:alnum:]_])gdb([^[:alnum:]_]|$)' "$crash_skill" &&
   grep -q 'Leave the system as you found it' "$crash_skill" &&
   grep -q 'aurelia crash mute' "$crash_skill" &&
   grep -q 'kk18888678/fedora-hyprland-workstation' "$reporting"; then
    pass "the diagnose-crash skill is metadata-only and evidence-first with a bounded reporting contract"
else
    fail "the diagnose-crash skill contract is incomplete"
fi

if grep -q 'mask_secrets()' "$ROOT/bin/workstation-ai" &&
   grep -q 'cmd_review()' "$ROOT/bin/workstation-ai" &&
   grep -q '__review' "$ROOT/bin/workstation-ai" &&
   grep -Fq "build_agent_argv \"\$agent\" \"\$prompt\" readonly" "$ROOT/bin/workstation-ai" &&
   grep -q 'cmd_launch --review' "$ROOT/bin/workstation-ai" &&
   ! grep -q 'coredumpctl dump' "$ROOT/bin/workstation-ai"; then
    pass "the crash handoff masks, reviews, and launches the agent read-only"
else
    fail "the crash handoff is missing its privacy boundary"
fi

# The extended crash handoff and the dual-skill install run in a sandbox HOME.
ai_backend="$ROOT/bin/workstation-ai"
if [[ -x "$ai_backend" ]]; then
    sandbox="$(mktemp -d)"
    trap 'rm -rf -- "$sandbox" || true' RETURN
    mkdir -p "$sandbox/home/.config"
    export HOME="$sandbox/home"
    export XDG_CONFIG_HOME="$sandbox/home/.config"
    export XDG_STATE_HOME="$sandbox/home/.local/state"

    if "$ai_backend" crash not-a-pid >/dev/null; then
        fail "workstation-ai crash accepted a non-numeric PID"
    else
        pass "workstation-ai crash rejects a non-numeric PID"
    fi

    # A valid PID with no default agent must fail closed rather than hang or
    # launch anything.
    if "$ai_backend" crash 1 >/dev/null; then
        fail "workstation-ai crash launched without a default agent"
    else
        pass "workstation-ai crash fails closed without a default agent"
    fi

    if "$ai_backend" skill install >/dev/null &&
       [[ -L "$HOME/.agents/skills/fedora-hyprland-workstation" ]] &&
       [[ -L "$HOME/.agents/skills/diagnose-crash" ]] &&
       [[ -f "$HOME/.agents/skills/diagnose-crash/SKILL.md" ]] &&
       "$ai_backend" skill remove >/dev/null &&
       [[ ! -e "$HOME/.agents/skills/diagnose-crash" ]]; then
        pass "workstation-ai installs and removes both skills by symlink"
    else
        fail "workstation-ai skill install/remove does not cover both skills"
    fi

    unset HOME XDG_CONFIG_HOME XDG_STATE_HOME
    rm -rf -- "$sandbox"
else
    fail "workstation-ai backend is missing"
fi

if grep -q 'crash) cmd_crash "$@"' "$ROOT/aurelia-shell/bin/aurelia" &&
   grep -q 'aurelia-crash-watch' "$ROOT/aurelia-shell/bin/aurelia" &&
   grep -q 'aurelia-crash-mute' "$ROOT/aurelia-shell/bin/aurelia" &&
   grep -q 'aurelia-toggle-crash-capture' "$ROOT/aurelia-shell/bin/aurelia" &&
   grep -q 'aurelia-agent-crash' "$ROOT/aurelia-shell/bin/aurelia"; then
    pass "the aurelia CLI crash group routes every crash backend"
else
    fail "the aurelia CLI crash group is incomplete"
fi
