#!/usr/bin/env bash

# Test Suite: Execution primitives, timeouts, retries, target-user privilege handling, and UID verification.

section "Target User Execution & Privilege Handling"

if grep -q "run_as_target_user" "$ROOT/modules/common.sh" "$ROOT/modules/lib/execution.sh"; then
    pass "common.sh / execution.sh defines run_as_target_user"
else
    fail "missing run_as_target_user"
fi

target_user_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="mockuser"
TARGET_HOME="$(mktemp -d)"
OVERRIDE_TARGET_UID=1000
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

sudo_invocations=()
sudo() {
    sudo_invocations+=("SUDO: $*")
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

# 1. Test root -> TARGET_USER invokes real sudo user switching without injecting LC_ALL=C
OVERRIDE_EUID=0
USER="root"
run_as_target_user echo "root-switch" >/dev/null || true
echo "test1_sudo=${sudo_invocations[0]:-none}"

# 2. Test already TARGET_USER (UID matches TARGET_UID) executes directly and preserves caller locale
sudo_invocations=()
OVERRIDE_EUID=1000
USER="mockuser"
cmd_executed=0
cmd_locale=""
my_test_cmd() {
    cmd_executed=1
    cmd_locale="${LC_ALL:-unset}"
}
LC_ALL="en_US.UTF-8" run_as_target_user my_test_cmd
echo "test2_sudo_count=${#sudo_invocations[@]}"
echo "test2_executed=$cmd_executed"
echo "test2_locale=$cmd_locale"

# 3. Test different non-root user + sudo available performs real user switching without injecting LC_ALL=C
sudo_invocations=()
OVERRIDE_EUID=1001
USER="otheruser"
other_cmd_executed=0
other_cmd() { other_cmd_executed=1; }
run_as_target_user other_cmd
echo "test3_sudo=${sudo_invocations[0]:-none}"
echo "test3_executed=$other_cmd_executed"

# 4 & 5. Test different non-root user + NO sudo DOES NOT execute command and returns nonzero
unset -f sudo
command_exists() {
    if [[ "$1" == "sudo" ]]; then
        return 1
    fi
    command -v "$1" >/dev/null 2>&1
}
no_sudo_executed=0
no_sudo_cmd() { no_sudo_executed=1; }
no_sudo_status=0
OVERRIDE_EUID=1001
USER="otheruser"
run_as_target_user no_sudo_cmd >/dev/null 2>&1 || no_sudo_status=$?
echo "test4_executed=$no_sudo_executed"
echo "test5_status=$no_sudo_status"

# 6. Test USER environment spoofing (UID 1001 claims USER="mockuser" when no sudo)
spoofed_executed=0
spoofed_cmd() { spoofed_executed=1; }
spoofed_status=0
OVERRIDE_EUID=1001
USER="mockuser" # Spoofed USER environment variable!
run_as_target_user spoofed_cmd >/dev/null 2>&1 || spoofed_status=$?
echo "test6_executed=$spoofed_executed"
echo "test6_status=$spoofed_status"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$target_user_test_output" | grep -q 'test1_sudo=SUDO: -u mockuser env HOME=.* USER=mockuser echo root-switch'; then
    pass "root -> TARGET_USER invokes real sudo user switching with target HOME and USER (without global LC_ALL=C)"
else
    fail "root -> TARGET_USER did not invoke sudo: $target_user_test_output"
fi

if printf '%s\n' "$target_user_test_output" | grep -q 'test2_sudo_count=0' &&
   printf '%s\n' "$target_user_test_output" | grep -q 'test2_executed=1' &&
   printf '%s\n' "$target_user_test_output" | grep -q 'test2_locale=en_US.UTF-8'; then
    pass "already TARGET_USER executes directly and preserves inherited locale"
else
    fail "already TARGET_USER failed direct execution or locale inheritance: $target_user_test_output"
fi

if printf '%s\n' "$target_user_test_output" | grep -q 'test3_sudo=SUDO: -u mockuser env HOME=.* USER=mockuser other_cmd' &&
   printf '%s\n' "$target_user_test_output" | grep -q 'test3_executed=1'; then
    pass "different non-root user + sudo performs real user switching (without global LC_ALL=C)"
else
    fail "different non-root user + sudo failed: $target_user_test_output"
fi

if printf '%s\n' "$target_user_test_output" | grep -q 'test4_executed=0'; then
    pass "different non-root user without sudo DOES NOT execute command"
else
    fail "different non-root user without sudo executed command: $target_user_test_output"
fi

if printf '%s\n' "$target_user_test_output" | grep -qE 'test5_status=[1-9]'; then
    pass "different non-root user without sudo returns nonzero failure"
else
    fail "different non-root user without sudo returned zero: $target_user_test_output"
fi

if printf '%s\n' "$target_user_test_output" | grep -q 'test6_executed=0' &&
   printf '%s\n' "$target_user_test_output" | grep -qE 'test6_status=[1-9]'; then
    pass "USER environment spoofing cannot trick helper into treating caller as TARGET_USER"
else
    fail "USER environment spoofing bypassed user verification: $target_user_test_output"
fi

xdg_privilege_switch_test="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="xdgtester"
TARGET_HOME="$(mktemp -d)"
OVERRIDE_TARGET_UID=1000
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/shell.sh"

executed_as_user=""
executed_home=""
executed_cmds=()

sudo() {
    if [[ "$1" == "-u" ]]; then
        executed_as_user="$2"
        shift 2
    fi
    if [[ "$1" == "env" ]]; then
        shift
        while [[ $# -gt 0 && "$1" == *=* ]]; do
            if [[ "$1" == HOME=* ]]; then
                executed_home="${1#HOME=}"
            fi
            shift
        done
    fi
    executed_cmds+=("$*")
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

xdg-user-dirs-update() {
    cat > "$TARGET_HOME/.config/user-dirs.dirs" <<'UDIRS'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
UDIRS
}

# Simulate root installer execution
OVERRIDE_EUID=0
USER="root"
configure_user_directories

echo "executed-user=$executed_as_user"
echo "executed-home=$executed_home"
echo "cmds=${executed_cmds[*]}"

all_eight_exist=1
for d in Desktop Documents Downloads Music Pictures Public Templates Videos; do
    if [[ ! -d "$TARGET_HOME/$d" ]]; then
        all_eight_exist=0
    fi
done
echo "all-eight-exist=$all_eight_exist"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$xdg_privilege_switch_test" | grep -q 'executed-user=xdgtester'; then
    pass "configure_user_directories switches process user to TARGET_USER"
else
    fail "configure_user_directories did not switch to TARGET_USER: $xdg_privilege_switch_test"
fi

if printf '%s\n' "$xdg_privilege_switch_test" | grep -q 'cmds=.*env LC_ALL=C xdg-user-dirs-update'; then
    pass "xdg-user-dirs-update is explicitly invoked with LC_ALL=C at call site"
else
    fail "xdg-user-dirs-update missing LC_ALL=C at call site: $xdg_privilege_switch_test"
fi

if printf '%s\n' "$xdg_privilege_switch_test" | grep -q 'all-eight-exist=1'; then
    pass "all 8 standard XDG user directories created via TARGET_USER execution"
else
    fail "XDG user directories missing after target user execution: $xdg_privilege_switch_test"
fi

section "Timeout & hang resilience"

timeout_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

# 1 & 2. run_with_timeout terminates sleeping child and returns 124, child PID is gone
test_cmd_pid_file="$(mktemp)"
child_runner="$(mktemp)"
cat > "$child_runner" << 'RUNNER'
#!/usr/bin/env bash
echo "$$" > "$1"
exec sleep 10
RUNNER
chmod +x "$child_runner"

start_time=$(date +%s)
status=0
run_with_timeout 1 "sleep test" "$child_runner" "$test_cmd_pid_file" || status=$?
end_time=$(date +%s)
elapsed=$((end_time - start_time))

tracked_timeout_pid="$(cat "$test_cmd_pid_file" 2>/dev/null || true)"

if (( status == 124 )) && (( elapsed < 5 )); then
    echo "timeout-terminated-ok"
fi

sleep 0.2
if [[ -n "$tracked_timeout_pid" ]] && ! kill -0 "$tracked_timeout_pid" 2>/dev/null; then
    echo "timeout-tracked-child-dead-ok"
fi
rm -f "$child_runner" "$test_cmd_pid_file"

# 3. run_with_retry retries a timed-out command
RETRY_BACKOFF_SECONDS=(0 0)
retry_test_script="$(mktemp)"
cat > "$retry_test_script" << 'SCRIPT'
#!/usr/bin/env bash
count_file="$1"
count=0
if [[ -f "$count_file" ]]; then
    count=$(cat "$count_file")
fi
count=$((count + 1))
echo "$count" > "$count_file"
if (( count < 3 )); then
    sleep 5
fi
exit 0
SCRIPT
chmod +x "$retry_test_script"

count_file="$(mktemp)"
echo 0 > "$count_file"

retry_timeout_status=0
run_with_retry "flaky timeout command" run_with_timeout 1 "flaky timeout attempt" "$retry_test_script" "$count_file" || retry_timeout_status=$?

final_count=$(cat "$count_file")
if (( retry_timeout_status == 0 )) && (( final_count == 3 )); then
    echo "retry-on-timeout-ok"
fi
rm -f "$retry_test_script" "$count_file"

# 4. Missing timeout command fails closed with 127
missing_timeout_status=0
(
    PATH=""
    run_with_timeout 5 "missing timeout check" true || exit $?
) 2>/dev/null || missing_timeout_status=$?

if (( missing_timeout_status == 127 )); then
    echo "timeout-missing-fail-closed-ok"
fi

# 5. Invalid non-positive timeout fails closed with nonzero status
invalid_timeout_status=0
run_with_timeout 0 "invalid timeout check" true 2>/dev/null || invalid_timeout_status=$?

if (( invalid_timeout_status != 0 )); then
    echo "timeout-invalid-fail-closed-ok"
fi

# 6. package_available distinguishes available (0), unavailable (1), and timeout/error (2)
pkg_avail_ok_status=0
package_available kate || pkg_avail_ok_status=$?
if (( pkg_avail_ok_status == 0 )); then
    echo "pkg-avail-status-0-ok"
fi

pkg_unavail_status=0
package_available nonexistent-pkg-fake-name-xyz || pkg_unavail_status=$?
if (( pkg_unavail_status == 1 )); then
    echo "pkg-unavail-status-1-ok"
fi

# Mock timeout in package_available
TIMEOUT_METADATA_SECONDS=1
pkg_timeout_script="$(mktemp)"
cat > "$pkg_timeout_script" << 'MOCK'
#!/usr/bin/env bash
sleep 5
MOCK
chmod +x "$pkg_timeout_script"

pkg_timeout_status=0
(
    run_with_timeout() { return 124; }
    package_available fake-pkg-timed-out || exit $?
) 2>/dev/null || pkg_timeout_status=$?

if (( pkg_timeout_status == 2 )); then
    echo "pkg-timeout-status-2-ok"
fi
rm -f "$pkg_timeout_script"

# 7. Timeout in non-login stage produces exit code 1 without blocking activation
ACTIVATION_BLOCKED=0
timed_out_stage() {
    run_with_timeout 1 "non-login hang" sleep 5
}

run_classified_step workstation "Simulated hanging workstation stage" timed_out_stage || true
echo "workstation-timeout-blocked=$ACTIVATION_BLOCKED"
echo "workstation-timeout-exit=$(installer_exit_code)"

# 8. Timeout in login-critical stage produces exit code 1 and blocks activation
ACTIVATION_BLOCKED=0
login_hang_stage() {
    run_with_timeout 1 "login-critical hang" sleep 5
}

run_classified_step login "Simulated hanging login stage" login_hang_stage || true
echo "login-timeout-blocked=$ACTIVATION_BLOCKED"
echo "login-timeout-exit=$(installer_exit_code)"

# 9. Real SIGINT interrupt and process cleanup test with full install.sh on_exit semantics
sigint_pid_file="$(mktemp)"
sigint_test_script="$(mktemp)"
cat > "$sigint_test_script" << 'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$1"
PID_FILE="$2"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

INTERRUPTED_SIGNAL=0

cleanup_installer_children() {
    stop_sudo_keepalive
    if [[ -n "${ACTIVE_TIMEOUT_PID:-}" ]]; then
        kill -TERM "$ACTIVE_TIMEOUT_PID" 2>/dev/null || true
        wait "$ACTIVE_TIMEOUT_PID" 2>/dev/null || true
        ACTIVE_TIMEOUT_PID=""
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -P "$$" 2>/dev/null || true
    fi
}

on_interrupt() {
    local sig="${1:-INT}"
    cleanup_installer_children
    ACTIVATION_BLOCKED=1
    record_critical "installer" "interrupt" "Received signal $sig." 1

    if [[ "$sig" == "TERM" ]]; then
        INTERRUPTED_SIGNAL=143
        exit 143
    else
        INTERRUPTED_SIGNAL=130
        exit 130
    fi
}

on_exit() {
    local code=$?
    cleanup_installer_children

    local final_code
    if (( INTERRUPTED_SIGNAL != 0 )); then
        final_code="$INTERRUPTED_SIGNAL"
    elif (( code >= 128 )); then
        final_code="$code"
    else
        final_code="$(installer_exit_code)"
    fi
    exit "$final_code"
}

trap 'on_interrupt INT' INT
trap 'on_interrupt TERM' TERM
trap on_exit EXIT

worker_script="$(mktemp)"
cat > "$worker_script" << 'WORKER'
#!/usr/bin/env bash
echo "$$" > "$1"
exec sleep 30
WORKER
chmod +x "$worker_script"

run_with_timeout 30 "sigint test long sleep" "$worker_script" "$PID_FILE"
SCRIPT
chmod +x "$sigint_test_script"

set -m
"$sigint_test_script" "$SCRIPT_DIR" "$sigint_pid_file" 2>/dev/null &
CHILD_INSTALLER_PID=$!
set +m
sleep 0.4

tracked_worker_pid="$(cat "$sigint_pid_file" 2>/dev/null || true)"

# Send SIGINT to the running child installer script
kill -INT "$CHILD_INSTALLER_PID" 2>/dev/null || true
child_exit_code=0
wait "$CHILD_INSTALLER_PID" 2>/dev/null || child_exit_code=$?

sleep 0.2
if (( child_exit_code == 130 )); then
    echo "sigint-exit-130-ok"
fi

if [[ -n "$tracked_worker_pid" ]] && ! kill -0 "$tracked_worker_pid" 2>/dev/null; then
    echo "sigint-tracked-worker-dead-ok"
fi
rm -f "$sigint_test_script" "$sigint_pid_file"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$timeout_output" | grep -q 'timeout-terminated-ok'; then
    pass "run_with_timeout terminates hung command and returns exit code 124"
else
    fail "run_with_timeout termination failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'timeout-tracked-child-dead-ok'; then
    pass "no orphan processes remain after timeout (tracked child PID terminated)"
else
    fail "orphan process detected after timeout: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'retry-on-timeout-ok'; then
    pass "run_with_retry retries timed-out operations"
else
    fail "run_with_retry did not retry on timeout: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'timeout-missing-fail-closed-ok'; then
    pass "run_with_timeout fails closed when timeout utility is missing (127)"
else
    fail "run_with_timeout did not fail closed on missing timeout: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'timeout-invalid-fail-closed-ok'; then
    pass "run_with_timeout fails closed on non-positive timeout values"
else
    fail "run_with_timeout did not fail closed on invalid timeout: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'pkg-avail-status-0-ok'; then
    pass "package_available returns 0 for available packages"
else
    fail "package_available status 0 failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'pkg-unavail-status-1-ok'; then
    pass "package_available returns 1 for cleanly absent packages"
else
    fail "package_available status 1 failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'pkg-timeout-status-2-ok'; then
    pass "package_available returns 2 on repository timeout/failure"
else
    fail "package_available status 2 failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'workstation-timeout-blocked=0'; then
    pass "workstation operation timeout does not block graphical activation"
else
    fail "workstation operation timeout blocked graphical activation: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'workstation-timeout-exit=1'; then
    pass "workstation operation timeout produces exit code 1"
else
    fail "workstation operation timeout exit code: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'login-timeout-blocked=1'; then
    pass "login-critical operation timeout blocks graphical activation"
else
    fail "login-critical operation timeout did not block activation: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'login-timeout-exit=1'; then
    pass "login-critical operation timeout produces exit code 1"
else
    fail "login-critical operation timeout exit code: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'sigint-exit-130-ok'; then
    pass "SIGINT preserves final exit status 130 through EXIT trap finalization"
else
    fail "SIGINT final exit status 130 failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'sigint-tracked-worker-dead-ok'; then
    pass "SIGINT cleans tracked child process without killing parent test shell"
else
    fail "SIGINT child process cleanup failed: $timeout_output"
fi
