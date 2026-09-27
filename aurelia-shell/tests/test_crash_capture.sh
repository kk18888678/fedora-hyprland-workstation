#!/usr/bin/env bash

# Crash-capture/diagnosis feature: the coredump watcher, the per-program mute
# and global capture commands, the agent handoff, the user unit, the skill
# contract, and the menu/Command Center wiring.
#
# The watcher is driven through its real command with a stubbed journal and a
# recording notification sender, so the assertions prove what a person sees —
# a toast arriving or not — rather than that a flag file was read.

set -Eeuo pipefail

section "Aurelia Crash Capture and Diagnosis"

watch_bin="$ROOT/bin/aurelia-crash-watch"
mute_bin="$ROOT/bin/aurelia-crash-mute"
toggle_bin="$ROOT/bin/aurelia-toggle-crash-capture"
agent_bin="$ROOT/bin/aurelia-agent-crash"

for backend in "$watch_bin" "$mute_bin" "$toggle_bin" "$agent_bin" "$ROOT/bin/aurelia-notification-wait"; do
    [[ -x "$backend" ]] ||
        fail "crash backend is missing or not executable: $backend"
done

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture" || true' RETURN

# ---------------------------------------------------------------------------
# Global capture toggle and its unit lifecycle
# ---------------------------------------------------------------------------
toggle_home="$fixture/toggle-home"
toggle_log="$fixture/systemctl-log"
mkdir -p "$toggle_home" "$fixture/stub-bin"

cat >"$fixture/stub-bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AURELIA_CRASH_TEST_SYSTEMCTL_LOG"
exit 0
SH
cat >"$fixture/stub-bin/aurelia-notification-send" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fixture/stub-bin/systemctl" "$fixture/stub-bin/aurelia-notification-send"

capture_flag="$toggle_home/.local/state/aurelia/toggles/crash-capture-off"
toggle_capture() {
    HOME="$toggle_home" \
    XDG_STATE_HOME="$toggle_home/.local/state" \
    AURELIA_CRASH_TEST_SYSTEMCTL_LOG="$toggle_log" \
    PATH="$fixture/stub-bin:$PATH" \
        "$toggle_bin" "$@"
}

# off disables capture, creates the persistent flag, and stops the unit now.
toggle_capture off >/dev/null
[[ -f "$capture_flag" ]] ||
    fail "crash capture off does not create the persistent flag the unit checks"
grep -Fqx -- "--user stop aurelia-crash-watch.service" "$toggle_log" ||
    fail "crash capture off does not stop the running watcher for this session"
pass "crash capture off persists and stops the watcher"

# on removes the flag and starts the unit.
: >"$toggle_log"
toggle_capture on >/dev/null
[[ ! -f "$capture_flag" ]] ||
    fail "crash capture on leaves the persistent disable flag in place"
grep -Fqx -- "--user start aurelia-crash-watch.service" "$toggle_log" ||
    fail "crash capture on does not start the watcher for this session"
pass "crash capture on persists and starts the watcher"

# toggle flips both ways, and status reports the flag rather than a cached value.
toggle_capture toggle >/dev/null
[[ -f "$capture_flag" ]] || fail "crash capture toggle does not disable"
[[ "$(toggle_capture status)" == "disabled" ]] ||
    fail "crash capture status does not report the disabled state"
toggle_capture toggle >/dev/null
[[ ! -f "$capture_flag" ]] || fail "crash capture toggle does not re-enable"
[[ "$(toggle_capture status)" == "enabled" ]] ||
    fail "crash capture status does not report the enabled state"
pass "crash capture toggle flips both ways and status is truthful"

# A refused action fails closed rather than silently toggling.
if toggle_capture sideways >/dev/null; then
    fail "crash capture accepted an unknown action"
else
    pass "crash capture rejects an unknown action"
fi

# The unit is enabled for the graphical session and disabled by the flag.
unit="$ROOT/systemd/user/aurelia-crash-watch.service"
grep -Fx 'ConditionPathExists=!%h/.local/state/aurelia/toggles/crash-capture-off' "$unit" >/dev/null ||
    fail "the watcher unit does not stay disabled across logins"
grep -Fx 'ExecStart=/usr/local/bin/aurelia-crash-watch' "$unit" >/dev/null ||
    fail "the watcher unit does not run the installed watcher"
grep -Fx 'WantedBy=graphical-session.target' "$unit" >/dev/null ||
    fail "the watcher unit is not enabled for the graphical session"
grep -Fx 'PartOf=graphical-session.target' "$unit" >/dev/null ||
    fail "the watcher unit does not track the graphical session lifecycle"
grep -Fq 'install_crash_capture' "$ROOT/../modules/desktop.sh" ||
    fail "the installer no longer ships the crash-capture deployment"
pass "the watcher unit has a bounded lifecycle and is shipped by the installer"

# ---------------------------------------------------------------------------
# The watcher, driven through the real command with a stubbed journal
# ---------------------------------------------------------------------------
watch_bin_dir="$fixture/watch-bin"
watch_home="$fixture/watch-home"
notify_log="$fixture/notify-log"
journal_entries="$fixture/journal-entries"
mkdir -p "$watch_bin_dir" "$watch_home"

cat >"$watch_bin_dir/journalctl" <<'SH'
#!/usr/bin/env bash
cat "$AURELIA_CRASH_JOURNAL_ENTRIES"
SH
cat >"$watch_bin_dir/workstation-ai" <<'SH'
#!/usr/bin/env bash
printf '%s\n' claude
SH
cat >"$watch_bin_dir/aurelia-notification-wait" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$watch_bin_dir/aurelia-notification-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AURELIA_CRASH_NOTIFY_LOG"
SH
chmod +x "$watch_bin_dir/journalctl" "$watch_bin_dir/workstation-ai" \
    "$watch_bin_dir/aurelia-notification-wait" "$watch_bin_dir/aurelia-notification-send"

reset_entries() {
    : >"$journal_entries"
}

# One core dump as systemd-coredump journals it. The UID must be this user's.
crash_entry() {
    local comm="$1" exe="$2"
    jq -cn --arg uid "$UID" --arg comm "$comm" --arg exe "$exe" \
        '{_UID: $uid, COREDUMP_COMM: $comm, COREDUMP_PID: "4242",
          COREDUMP_EXE: $exe, COREDUMP_SIGNAL_NAME: "SIGSEGV"}' >>"$journal_entries"
}

# The stubbed journalctl ends after the entries, so the watcher's loop ends
# too. Its exit status is asserted rather than discarded: a watcher that dies
# on a muted crash notifies about nothing afterwards, which every assertion
# below that expects silence would otherwise read as success.
run_watch() {
    local status=0
    : >"$notify_log"
    HOME="$watch_home" \
    XDG_STATE_HOME="$watch_home/.local/state" \
    AURELIA_CRASH_JOURNAL_ENTRIES="$journal_entries" \
    AURELIA_CRASH_NOTIFY_LOG="$notify_log" \
    PATH="$watch_bin_dir:$ROOT/bin:$PATH" \
        "$watch_bin" || status=$?
    ((status == 0)) ||
        fail "the watcher exited $status rather than carrying on, so a mute takes the service down with it"
}

crash_mute() {
    HOME="$watch_home" XDG_STATE_HOME="$watch_home/.local/state" PATH="$ROOT/bin:$PATH" "$mute_bin" "$@"
}

announced() {
    grep -Fq "Process crashed: $1" "$notify_log"
}

reset_entries
crash_entry hyprland /usr/bin/hyprland
run_watch
announced hyprland ||
    fail "a crash nobody muted still announces itself"
grep -Fq -- '--exec aurelia-agent-crash 4242 hyprland /usr/bin/hyprland SIGSEGV' "$notify_log" ||
    fail "the notification does not hand the crash facts to the agent as discrete argv"
pass "an unmuted crash announces itself and hands over discrete argv"

crash_mute hyprland on >/dev/null
run_watch
! announced hyprland ||
    fail "muting a program stops the crash notifications the diagnosis offered to stop"
pass "muting a program stops its crash notifications"

reset_entries
crash_entry nautilus /usr/bin/nautilus
run_watch
announced nautilus ||
    fail "muting one program silences every other program, which is the global switch's job"
pass "muting one program leaves every other program announcing"

crash_mute hyprland off >/dev/null
reset_entries
crash_entry hyprland /usr/bin/hyprland
run_watch
announced hyprland || fail "un-muting a program brings its crash notifications back"
pass "un-muting a program brings its crash notifications back"

# The toast must announce the name the mute is keyed on, not the truncated COMM.
reset_entries
crash_entry chromium-browse /usr/lib/chromium/chromium-browser
run_watch
announced chromium-browser ||
    fail "the toast announces a name the mute cannot be keyed on"
crash_mute chromium-browser on >/dev/null
run_watch
! announced chromium-browser ||
    fail "the mute is keyed on the truncated COMM rather than the announced name"
pass "the announced basename is the name the mute is keyed on"

# A muted crash must not end the watcher.
reset_entries
crash_entry chromium-browse /usr/lib/chromium/chromium-browser
crash_entry nautilus /usr/bin/nautilus
run_watch
announced nautilus ||
    fail "a muted crash stops the watcher reading the journal, losing every crash after it"
pass "a muted crash does not stop the watcher reading the next one"

# A comm that climbs out must not read or write an unrelated toggle.
reset_entries
crash_entry a/../bar-off -
sibling_flag="$watch_home/.local/state/aurelia/toggles/bar-off"
touch "$sibling_flag"
run_watch
announced bar-off ||
    fail "a comm that climbs out reads an unrelated toggle, letting a crash suppress itself"
pass "a comm that climbs out cannot reach an unrelated toggle"
rm -f -- "$sibling_flag"

# A name that strips down to nothing or a dot still announces under `unknown`.
for empty_comm in / a/ . ..; do
    reset_entries
    crash_entry "$empty_comm" -
    run_watch
    announced unknown ||
        fail "a comm of '$empty_comm' leaves no usable name for the mute to key on"
done
pass "a comm that strips down to nothing or a dot still announces under a usable name"

# An empty comm is not a missing entry; tab is IFS whitespace and a shifted
# field would drop the crash or misread it as somebody else's.
reset_entries
crash_entry "" -
crash_entry nautilus /usr/bin/nautilus
run_watch
announced unknown ||
    fail "a crash whose comm is empty is dropped instead of announced"
announced nautilus ||
    fail "an empty comm derails the rest of the journal entry"
pass "an empty comm is announced rather than parsed into the next field"

for dotted_comm in .hidden ...; do
    reset_entries
    crash_entry "$dotted_comm" -
    run_watch
    announced "$dotted_comm" ||
        fail "'$dotted_comm' is an ordinary name but lands in the fallback"
done
pass "a leading dot is an ordinary name rather than a special component"

master_mute_flag="$watch_home/.local/state/aurelia/toggles/crash-ignore/unknown"
crash_mute unknown on >/dev/null
[[ -f "$master_mute_flag" ]] || fail "the fallback name cannot be muted"
crash_mute unknown off >/dev/null

# Only this user's crashes are announced.
reset_entries
jq -cn --arg comm nautilus --arg exe /usr/bin/nautilus \
    '{_UID: "0", COREDUMP_COMM: $comm, COREDUMP_PID: "4242",
      COREDUMP_EXE: $exe, COREDUMP_SIGNAL_NAME: "SIGSEGV"}' >>"$journal_entries"
run_watch
! announced nautilus ||
    fail "the watcher announces another user's crash, which is a sysadmin's problem"
pass "the watcher ignores other users' crashes"

# No default agent means nothing to offer; the crash is not announced.
reset_entries
crash_entry hyprland /usr/bin/hyprland
cat >"$watch_bin_dir/workstation-ai" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$watch_bin_dir/workstation-ai"
run_watch
! announced hyprland ||
    fail "the watcher offers a diagnosis with no default agent to diagnose it"
cat >"$watch_bin_dir/workstation-ai" <<'SH'
#!/usr/bin/env bash
printf '%s\n' claude
SH
chmod +x "$watch_bin_dir/workstation-ai"
pass "the watcher offers nothing until a default agent is chosen"

# ---------------------------------------------------------------------------
# The per-program mute command on its own
# ---------------------------------------------------------------------------
mute_home="$fixture/mute-home"
mkdir -p "$mute_home"

standalone_mute() {
    HOME="$mute_home" XDG_STATE_HOME="$mute_home/.local/state" "$mute_bin" "$@"
}

mute_flag() {
    [[ ${1:-} == "--" ]] && shift
    printf '%s' "$mute_home/.local/state/aurelia/toggles/crash-ignore/$1"
}

standalone_mute | grep -Fq "No programs muted" ||
    fail "an empty mute list prints nothing, so a user cannot tell it from a broken command"
pass "the command says so when nothing is muted"

standalone_mute hyprland >/dev/null
standalone_mute | grep -Fqx hyprland ||
    fail "a muted program is missing from the list, so a mute cannot be found again"
pass "the command lists what it muted"

standalone_mute /usr/lib/chromium/chromium-browser >/dev/null
[[ -f "$(mute_flag chromium-browser)" ]] ||
    fail "a binary's path is muted verbatim rather than by name"
pass "the command reduces a path to the name the watcher checks"

standalone_mute hyprland off >/dev/null
[[ ! -f "$(mute_flag hyprland)" ]] ||
    fail "off leaves the program muted, making the mute a one-way door"
pass "the command un-mutes"

# Muting is not flipping.
standalone_mute hyprland >/dev/null
standalone_mute hyprland >/dev/null
[[ -f "$(mute_flag hyprland)" ]] ||
    fail "muting an already-muted program un-mutes it"
pass "asking to mute twice leaves it muted"

standalone_mute .hidden >/dev/null
standalone_mute | grep -Fqx .hidden ||
    fail "a mute on a dotted name is missing from the list"
pass "the list shows a name that begins with a dot"

for bad_name in . .. /; do
    ! standalone_mute "$bad_name" >/dev/null ||
        fail "'$bad_name' is taken as a program name"
done
pass "the command refuses a name that is not a name"

! standalone_mute hyprland sideways >/dev/null ||
    fail "an action it does not know is treated as a mute"
pass "the command refuses an action it does not know"

refusal="$(standalone_mute hyprland sideways 2>&1)" || true
grep -Fq "not an action" <<<"$refusal" ||
    fail "an unknown action is refused without naming it"
pass "the command names the action it refused"

standalone_mute ../bar-off >/dev/null
[[ ! -e "$mute_home/.local/state/aurelia/toggles/bar-off" ]] ||
    fail "a name that climbs out writes a sibling toggle"
pass "the command cannot be talked into writing outside crash-ignore/"

standalone_mute -- -h >/dev/null ||
    fail "a leading -- is not consumed, so a program named like a flag cannot be muted"
[[ -f "$(mute_flag -- -h)" ]] ||
    fail "a leading -- is taken for the program name"
pass "a leading -- lets a program named like a flag be muted"

standalone_mute toggler off >/dev/null
standalone_mute toggler toggle >/dev/null
[[ -f "$(mute_flag toggler)" ]] || fail "toggle does not mute an un-muted program"
standalone_mute toggler toggle >/dev/null
[[ ! -f "$(mute_flag toggler)" ]] ||
    fail "toggle mutes but never un-mutes"
pass "toggle flips a mute both ways"

mkdir -p "$(mute_flag notactuallymuted)"
! standalone_mute | grep -Fqx notactuallymuted ||
    fail "a directory is reported as muted while crashes keep arriving"
pass "the listing counts only the flags the watcher honours"
rmdir "$(mute_flag notactuallymuted)"

# A mute that could not be written must not be reported as one.
mkdir -p "$(mute_flag failing-write)"
status=0
refusal="$(standalone_mute failing-write 2>&1)" || status=$?
((status != 0)) ||
    fail "a mute that could not be written exits zero"
! grep -Fq "Muted crash notifications" <<<"$refusal" ||
    fail "a mute that could not be written still reports success"
pass "a mute that could not be written is not reported as one"
rmdir "$(mute_flag failing-write)"

# A symlinked flag would truncate its target; refuse it.
ln -s "$fixture/target" "$(mute_flag symlinked)"
status=0
standalone_mute symlinked >/dev/null || status=$?
((status != 0)) || fail "a symlinked mute flag is followed instead of refused"
pass "a symlinked mute flag is refused"
rm -f -- "$(mute_flag symlinked)"

# ---------------------------------------------------------------------------
# The agent handoff and the evidence-first skill
# ---------------------------------------------------------------------------
if "$agent_bin" not-a-pid >/dev/null; then
    fail "the crash handoff accepted a non-PID"
else
    pass "the crash handoff rejects a non-PID"
fi

if grep -Fq 'exec "$candidate" crash "$@"' "$agent_bin" &&
   grep -Fq 'workstation-ai crash "$@"' "$agent_bin"; then
    pass "the crash handoff delegates to the workstation-ai crash command"
else
    fail "the crash handoff does not delegate to workstation-ai"
fi

crash_skill="$ROOT/../config/agent-skill/diagnose-crash/SKILL.md"
report_skill="$ROOT/../config/agent-skill/diagnose-crash/reporting.md"
[[ -f "$crash_skill" && -f "$report_skill" ]] ||
    fail "the diagnose-crash skill or its reporting contract is missing"
grep -Fq 'aurelia crash mute' "$crash_skill" ||
    fail "the diagnosis no longer names the command that mutes"
grep -Fq 'coredumpctl info' "$crash_skill" ||
    fail "the diagnosis does not start from coredumpctl evidence"
grep -Fq 'Metadata only' "$crash_skill" ||
    fail "the diagnosis does not declare itself metadata-only"
grep -Fqi 'never extract, copy, or read a core dump' "$crash_skill" ||
    fail "the diagnosis does not explicitly forbid core dumps"
grep -Fq 'Leave the system as you found it' "$crash_skill" ||
    fail "the diagnosis no longer states the no-mutation rule"
grep -Fq 'kk18888678/fedora-hyprland-workstation' "$report_skill" ||
    fail "the reporting contract does not name the project it reports to"
pass "the metadata-only skill covers evidence, the core-dump prohibition, no-mutation, and reporting"

grep -Fq 'diagnose-crash' "$ROOT/../bin/workstation-ai" ||
    fail "workstation-ai does not install or reference the diagnose-crash skill"
pass "workstation-ai ships the diagnose-crash skill"

# ---------------------------------------------------------------------------
# Crash privacy: no core dump, masking, and a fail-closed review gate
# ---------------------------------------------------------------------------
# Static: the diagnosis and handoff never contain a core-extraction step.
if ! grep -Fq 'coredumpctl dump' "$crash_skill" &&
   ! grep -Eq '(^|[^[:alnum:]_])gdb([^[:alnum:]_]|$)' "$crash_skill" &&
   ! grep -Fq 'debuginfod' "$crash_skill" &&
   ! grep -Fq 'coredumpctl dump' "$ROOT/../bin/workstation-ai"; then
    pass "neither the skill nor the handoff contains a core-extraction step"
else
    fail "the crash feature still contains a core-extraction step"
fi

privacy_home="$fixture/privacy-home"
privacy_bin="$fixture/privacy-bin"
privacy_logs="$fixture/privacy-logs"
privacy_tmp="$fixture/privacy-tmp"
mkdir -p "$privacy_home/.config" "$privacy_bin" "$privacy_logs" "$privacy_tmp"

cat >"$privacy_bin/coredumpctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AURELIA_CRASH_COREDUMP_LOG"
if [[ "${1:-}" == "list" ]]; then
    printf '%s\n' "Mon 2026-01-01 00:00:00 UTC 4242 1000 11 SIGSEGV /usr/bin/hyprland"
fi
SH
cat >"$privacy_bin/gdb" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AURELIA_CRASH_GDB_LOG"
SH
cat >"$privacy_bin/pi" <<'SH'
#!/usr/bin/env bash
{
    printf 'ARGC=%s\n' "$#"
    for arg in "$@"; do printf 'ARG=%s\n' "$arg"; done
} >>"$AURELIA_CRASH_AGENT_LOG"
SH
# The review now requires a real interactive terminal, so a mock terminal that
# merely pipes an answer is correctly refused. Allocate a real PTY instead:
# pty_run.py forwards this process's stdin to the child's terminal and returns
# the child's own exit status, so the approved/declined paths stay faithful.
cat >"$fixture/pty_run.py" <<'PY'
#!/usr/bin/env python3
"""Run a command on a real pseudo-terminal, forwarding stdin and returning
its exit status. Test-only: it exists so an interactive consent review can be
exercised without a desktop session."""
import os
import pty
import select
import sys


def main():
    argv = sys.argv[1:]
    if not argv:
        return 2
    pid, master = pty.fork()
    if pid == 0:
        try:
            os.execvp(argv[0], argv)
        except OSError as error:
            os.write(2, ("pty_run: cannot exec %s: %s\n" % (argv[0], error)).encode())
            os._exit(127)
    stdin_open = True
    while True:
        fds = [master] + ([0] if stdin_open else [])
        try:
            rlist, _, _ = select.select(fds, [], [], 1.0)
        except InterruptedError:
            continue
        if stdin_open and 0 in rlist:
            try:
                data = os.read(0, 1024)
            except OSError:
                data = b""
            if data:
                os.write(master, data)
            else:
                stdin_open = False
        if master in rlist:
            try:
                data = os.read(master, 4096)
            except OSError:
                data = b""
            if not data:
                break
            os.write(1, data)
    try:
        _, status = os.waitpid(pid, 0)
    except ChildProcessError:
        status = 0
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    sys.exit(main())
PY
cat >"$privacy_bin/kitty" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AURELIA_CRASH_KITTY_LOG"
[[ "${1:-}" == "--title" ]] && shift 2
printf '%s\n' "${KITTY_APPROVE:-}" | exec python3 "$AURELIA_CRASH_PTY_RUNNER" "$@"
SH
chmod +x "$privacy_bin/coredumpctl" "$privacy_bin/gdb" "$privacy_bin/pi" "$privacy_bin/kitty"

privacy_ai() {
    HOME="$privacy_home" \
    XDG_CONFIG_HOME="$privacy_home/.config" \
    XDG_STATE_HOME="$privacy_home/.local/state" \
    AURELIA_CRASH_COREDUMP_LOG="$privacy_logs/coredump" \
    AURELIA_CRASH_GDB_LOG="$privacy_logs/gdb" \
    AURELIA_CRASH_AGENT_LOG="$privacy_logs/agent" \
    AURELIA_CRASH_KITTY_LOG="$privacy_logs/kitty" \
    AURELIA_CRASH_PTY_RUNNER="$fixture/pty_run.py" \
    WORKSTATION_AI_TERMINAL="$privacy_bin/kitty" \
    TMPDIR="$privacy_tmp" \
    KITTY_APPROVE="${KITTY_APPROVE:-}" \
    PATH="$privacy_bin:$PATH" \
        "$ROOT/../bin/workstation-ai" "$@"
}

privacy_ai set pi >/dev/null || fail "could not select the read-only test agent"

# Approved review: the agent receives the masked payload in read-only mode,
# and no core is dumped and no debugger is started.
: >"$privacy_logs/coredump"
: >"$privacy_logs/kitty"
rm -f "$privacy_logs/agent" "$privacy_logs/gdb"
if KITTY_APPROVE=y privacy_ai crash 4242 'password=hunter2' /usr/bin/hyprland SIGSEGV >"$privacy_logs/out" 2>&1; then
    pass "an approved review completes"
else
    fail "an approved review did not complete"
fi
if [[ -f "$privacy_logs/agent" ]] &&
   grep -Fq 'ARG=read,bash' "$privacy_logs/agent" &&
   grep -Fq 'password=[REDACTED]' "$privacy_logs/agent" &&
   ! grep -Fq 'hunter2' "$privacy_logs/agent"; then
    pass "the approved payload reaches the agent masked and in read-only mode"
else
    fail "the approved payload is unmasked or launched in an unsafe mode"
fi
if grep -Fq '__review' "$privacy_logs/kitty" &&
   ! grep -Fq 'password=hunter2' "$privacy_logs/kitty"; then
    pass "the terminal is opened on the review, not on the raw payload"
else
    fail "the terminal was opened without a review step"
fi
if grep -Fq 'list' "$privacy_logs/coredump" &&
   ! grep -Fq 'dump' "$privacy_logs/coredump" &&
   [[ ! -e "$privacy_logs/gdb" ]]; then
    pass "the diagnosis reads coredumpctl metadata and never extracts a core"
else
    fail "the diagnosis took a core dump or started a debugger"
fi

# Declined review: the agent is never launched.
rm -f "$privacy_logs/agent"
if KITTY_APPROVE=n privacy_ai crash 4242 hyprland /usr/bin/hyprland SIGSEGV >"$privacy_logs/out" 2>&1; then
    fail "a declined review still exited successfully"
else
    pass "a declined review fails closed"
fi
[[ ! -e "$privacy_logs/agent" ]] ||
    fail "a declined review still launched the agent"
pass "a declined review never launches the agent"

# No answer (EOF): the agent is never launched.
rm -f "$privacy_logs/agent"
if KITTY_APPROVE='' privacy_ai crash 4242 hyprland /usr/bin/hyprland SIGSEGV >"$privacy_logs/out" 2>&1; then
    fail "a review with no answer still exited successfully"
else
    pass "a review with no answer fails closed"
fi
[[ ! -e "$privacy_logs/agent" ]] ||
    fail "a review with no answer still launched the agent"
pass "a review with no answer never launches the agent"

# An unavailable payload cannot be reviewed, so nothing is sent.
if privacy_ai __review --payload "$fixture/does-not-exist" --agent pi >"$privacy_logs/out" 2>&1; then
    fail "__review sent a payload it could not show"
else
    pass "__review fails closed when the payload cannot be shown"
fi

# The crash review masks the payload and launches the agent read-only.
if grep -Fq "build_agent_argv \"\$agent\" \"\$prompt\" readonly" "$ROOT/../bin/workstation-ai" &&
   grep -Fq 'mask_secrets' "$ROOT/../bin/workstation-ai" &&
   grep -Fq 'cmd_launch --review' "$ROOT/../bin/workstation-ai"; then
    pass "the crash review masks the payload and launches the agent read-only"
else
    fail "the crash review is missing its masking or read-only boundary"
fi

# ---------------------------------------------------------------------------
# Crash review TTY gate and staging cleanup (deterministic, desktop-free)
# ---------------------------------------------------------------------------
# Every case below runs the real backend against a private staging directory
# under $privacy_tmp. No desktop session and no real terminal emulator are
# involved. The gate must refuse whenever stdin or stdout is not a TTY, and no
# review path may leave a workstation-ai-crash.* directory behind.
review_env=(
    env
    "HOME=$privacy_home"
    "XDG_CONFIG_HOME=$privacy_home/.config"
    "XDG_STATE_HOME=$privacy_home/.local/state"
    "AURELIA_CRASH_AGENT_LOG=$privacy_logs/agent"
    "AURELIA_CRASH_COREDUMP_LOG=$privacy_logs/coredump"
    "TMPDIR=$privacy_tmp"
    "PATH=$privacy_bin:$PATH"
)

new_review_stage() {
    local stage
    stage="$(mktemp -d "$privacy_tmp/workstation-ai-crash.XXXXXX")"
    printf 'payload password=hunter2\n' >"$stage/payload"
    printf '%s\n' 'Masked secret patterns (best effort): password' >"$stage/disclosure"
    printf '%s\n' "$stage"
}

# A non-interactive invocation must refuse before it prints anything, name the
# entry point that opens a terminal, send nothing, and clean its staging.
stage="$(new_review_stage)"
rm -f "$privacy_logs/agent"
status=0
"${review_env[@]}" "$ROOT/../bin/workstation-ai" __review \
    --payload "$stage/payload" --disclosure "$stage/disclosure" --agent pi \
    </dev/null >"$privacy_logs/out" 2>&1 || status=$?
(( status != 0 )) || fail "a non-TTY crash review exited successfully"
grep -Fq 'interactive terminal' "$privacy_logs/out" ||
    fail "a non-TTY crash review does not explain why it refused"
grep -Fq 'aurelia crash diagnose' "$privacy_logs/out" ||
    fail "a non-TTY crash review does not name the entry point that opens a terminal"
! grep -Fq 'password=hunter2' "$privacy_logs/out" ||
    fail "a non-TTY crash review disclosed the payload to an unanswerable context"
[[ ! -e "$privacy_logs/agent" ]] ||
    fail "a non-TTY crash review launched the agent"
[[ ! -d "$stage" ]] ||
    fail "a non-TTY crash review left its staging directory behind"
pass "a non-TTY crash review refuses without disclosing the payload and cleans up"

# Piped EOF returns promptly and fails closed with no hang.
stage="$(new_review_stage)"
status=0
printf '' | timeout 10 "${review_env[@]}" "$ROOT/../bin/workstation-ai" __review \
    --payload "$stage/payload" --agent pi >"$privacy_logs/out" 2>&1 || status=$?
(( status != 0 && status != 124 )) ||
    fail "a piped EOF either succeeded or hung (status=$status)"
pass "a piped EOF fails closed promptly"
[[ ! -d "$stage" ]] || fail "a piped EOF left its staging directory behind"

# An open pipe that never closes must exit non-zero quickly. This is the direct
# regression for the reported hang, where the old read() blocked forever and a
# killed process leaked its staging directory.
stage="$(new_review_stage)"
open_pipe="$privacy_tmp/open-pipe"
mkfifo "$open_pipe"
sleep 30 >"$open_pipe" &
pipe_holder=$!
status=0
timeout 10 "${review_env[@]}" "$ROOT/../bin/workstation-ai" __review \
    --payload "$stage/payload" --agent pi <"$open_pipe" >"$privacy_logs/out" 2>&1 || status=$?
kill "$pipe_holder" || true
wait "$pipe_holder" || true
rm -f "$open_pipe"
(( status != 0 && status != 124 )) ||
    fail "an open pipe that never closes either succeeded or hung (status=$status)"
pass "an open pipe that never closes refuses promptly instead of hanging"
[[ ! -d "$stage" ]] || fail "the open-pipe refusal left its staging directory behind"

# No environment variable may approve a review, and a custom config cannot
# route around the gate either.
stage="$(new_review_stage)"
rm -f "$privacy_logs/agent"
status=0
YES=1 FORCE_YES=1 CI=1 NONINTERACTIVE=1 WORKSTATION_AI_APPROVE=1 \
PLAINLY_APPROVE=1 WORKSTATION_AI_AUTO_APPROVE=1 \
WORKSTATION_AI_CONF="$privacy_home/.config/workstation/ai.conf" \
    timeout 10 "${review_env[@]}" "$ROOT/../bin/workstation-ai" __review \
        --payload "$stage/payload" --agent pi </dev/null >"$privacy_logs/out" 2>&1 || status=$?
(( status != 0 )) || fail "an environment variable approved a non-TTY review"
[[ ! -e "$privacy_logs/agent" ]] ||
    fail "an environment variable launched the agent from a non-TTY review"
[[ ! -d "$stage" ]] || fail "an env-bypass refusal left its staging directory behind"
pass "no environment variable can approve a non-TTY crash review"

# A real pty still works: 'y' proceeds and 'n' refuses with "Not sent.".
stage="$(new_review_stage)"
rm -f "$privacy_logs/agent"
status=0
printf 'y\n' | timeout 15 "${review_env[@]}" python3 "$fixture/pty_run.py" \
    "$ROOT/../bin/workstation-ai" __review --payload "$stage/payload" --agent pi \
    >"$privacy_logs/out" 2>&1 || status=$?
(( status == 0 )) || fail "a pty 'y' review did not complete (status=$status)"
[[ -f "$privacy_logs/agent" ]] || fail "a pty 'y' review did not launch the agent"
[[ ! -d "$stage" ]] || fail "an approved review left its staging directory behind"
pass "a pty 'y' review still proceeds and cleans up"

stage="$(new_review_stage)"
rm -f "$privacy_logs/agent"
status=0
printf 'n\n' | timeout 15 "${review_env[@]}" python3 "$fixture/pty_run.py" \
    "$ROOT/../bin/workstation-ai" __review --payload "$stage/payload" --agent pi \
    >"$privacy_logs/out" 2>&1 || status=$?
(( status != 0 )) || fail "a pty 'n' review exited successfully"
[[ ! -e "$privacy_logs/agent" ]] || fail "a pty 'n' review launched the agent"
grep -Fq 'Not sent.' "$privacy_logs/out" || fail "a pty 'n' review did not say it refused"
[[ ! -d "$stage" ]] || fail "a declined review left its staging directory behind"
pass "a pty 'n' review still refuses with 'Not sent.' and cleans up"

# An invalid payload under a real terminal fails closed and cleans the staging
# directory that the old code leaked when a check ran before it was derived.
stage="$(mktemp -d "$privacy_tmp/workstation-ai-crash.XXXXXX")"
rm -f "$privacy_logs/agent"
status=0
printf 'y\n' | timeout 15 "${review_env[@]}" python3 "$fixture/pty_run.py" \
    "$ROOT/../bin/workstation-ai" __review --payload "$stage/does-not-exist" --agent pi \
    >"$privacy_logs/out" 2>&1 || status=$?
(( status != 0 )) || fail "a review with an unreadable payload exited successfully"
[[ ! -e "$privacy_logs/agent" ]] ||
    fail "a review with an unreadable payload launched the agent"
[[ ! -d "$stage" ]] || fail "an unreadable payload left its staging directory behind"
pass "an invalid payload fails closed under a real terminal and cleans up"

# The invariant across every path above.
leftover="$(find "$privacy_tmp" -maxdepth 1 -mindepth 1 -name 'workstation-ai-crash.*' -print -quit)"
[[ -z "$leftover" ]] ||
    fail "a staging directory survived a review path: $leftover"
pass "no crash staging directory survives any review path"

# The terminal used for a review is resolved from a fixed location or the
# documented override, never from PATH, so a shadowing executable cannot
# intercept the consent prompt.
shadow_bin="$fixture/shadow-bin"
mkdir -p "$shadow_bin"
cat >"$shadow_bin/kitty" <<'SH'
#!/usr/bin/env bash
printf 'shadowed\n' >>"$AURELIA_CRASH_SHADOW_LOG"
exit 99
SH
chmod +x "$shadow_bin/kitty"
shadow_log="$privacy_logs/shadow"
: >"$shadow_log"
: >"$privacy_logs/kitty"
rm -f "$privacy_logs/agent"
status=0
PATH="$shadow_bin:$privacy_bin:$PATH" \
WORKSTATION_AI_TERMINAL="$privacy_bin/kitty" \
KITTY_APPROVE=y \
AURELIA_CRASH_SHADOW_LOG="$shadow_log" \
AURELIA_CRASH_AGENT_LOG="$privacy_logs/agent" \
AURELIA_CRASH_KITTY_LOG="$privacy_logs/kitty" \
AURELIA_CRASH_COREDUMP_LOG="$privacy_logs/coredump" \
AURELIA_CRASH_PTY_RUNNER="$fixture/pty_run.py" \
HOME="$privacy_home" XDG_CONFIG_HOME="$privacy_home/.config" \
XDG_STATE_HOME="$privacy_home/.local/state" TMPDIR="$privacy_tmp" \
    timeout 15 "$ROOT/../bin/workstation-ai" crash 4242 hyprland /usr/bin/hyprland SIGSEGV \
    >"$privacy_logs/out" 2>&1 || status=$?
(( status == 0 )) ||
    fail "the override-selected terminal did not complete an approved review (status=$status)"
! grep -Fq 'shadowed' "$shadow_log" ||
    fail "a PATH-shadowing executable replaced the consent review terminal"
grep -Fq '__review' "$privacy_logs/kitty" ||
    fail "the override-selected terminal did not run the review"
pass "a PATH-shadowing executable cannot replace the consent review terminal"

# A missing notification handoff command must be recorded, not discarded into
# the null device with the notification row removed regardless.
notification_service="$ROOT/plugins/aurelia.notifications/Service.qml"
if grep -Fq 'function spawnNotificationCommand' "$notification_service" &&
   grep -Fq 'logger -t aurelia-notification' "$notification_service" &&
   grep -Fq 'command -v "$cmd"' "$notification_service" &&
   grep -Fq 'service.spawnNotificationCommand(argv)' "$notification_service" &&
   ! grep -Fq '"bash", "-lc", "exec \"\$@\""' "$notification_service"; then
    pass "a missing notification handoff command is recorded to the journal instead of silently discarded"
else
    fail "the notification exec path still swallows a missing handoff command"
fi

# ---------------------------------------------------------------------------
# Menu and Command Center integration
# ---------------------------------------------------------------------------
menu_root="$ROOT/plugins/aurelia.menu"
menu_json="$menu_root/menu.json"
if jq -e '.items | map(select(.id == "trigger.crash-capture" and .action == "toggle-crash-capture")) | length == 1' \
    "$menu_json" >/dev/null; then
    pass "the menu exposes a Crash Capture toggle"
else
    fail "the menu does not expose a Crash Capture toggle"
fi
grep -q 'toggle-crash-capture' "$menu_root/MenuModel.qml" ||
    fail "the menu action allow-list does not include the crash toggle"
grep -q 'Quickshell.execDetached(root.crashCaptureArgv)' "$menu_root/MenuModel.qml" ||
    fail "the menu does not dispatch the crash toggle through a fixed argv"
pass "the menu dispatches the crash toggle through an approved, fixed argv"

launcher_root="$ROOT/plugins/aurelia.launcher"
grep -q '"crash"' "$launcher_root/ui/CommandCenterModuleRegistry.qml" ||
    fail "the Command Center does not register a crash module"
grep -q 'function crashRows' "$launcher_root/ui/CommandCenterModel.qml" ||
    fail "the Command Center has no crash provider rows"
grep -q 'crash-capture-toggle' "$launcher_root/ui/CommandCenterModel.qml" ||
    fail "the Command Center cannot dispatch the crash capture toggle"
grep -q 'property string crashCaptureBin' "$launcher_root/ui/CommandCenterModel.qml" &&
    grep -q 'crashCaptureBin: pluginRoot.crashCaptureBin' "$launcher_root/CommandCenterPlugin.qml" &&
    grep -q 'crashCaptureBin: panelRoot.crashCaptureBin' "$launcher_root/ui/CommandCenterPanel.qml" ||
    fail "the Command Center crash backend is not wired through the panel"
pass "the Command Center exposes and dispatches the crash capture toggle"

grep -Fq 'crash) cmd_crash "$@"' "$ROOT/bin/aurelia" ||
    fail "the aurelia CLI has no crash group dispatch"
grep -q 'AURELIA_CLI_GROUPS=(.* crash)' "$ROOT/bin/aurelia" ||
    fail "the aurelia CLI does not list the crash group"
pass "the aurelia CLI routes the crash group"
