#!/usr/bin/env bash

# Test Suite: Installer state, journaling, and concurrency locking safety.

section "Installer Concurrency & Locking"

lock_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/state.sh"

test_lock_dir="$(mktemp -d)"
chmod 0700 "$test_lock_dir"
current_uid="${EUID:-$(id -u)}"

# 1. Normal lock acquisition with safe XDG_RUNTIME_DIR
XDG_RUNTIME_DIR="$test_lock_dir"
acquire_installer_lock
echo "lock1_acquired=1"
echo "lock_fd_dynamic=$([[ "$INSTALLER_LOCK_FD" =~ ^[0-9]+$ ]] && echo 1 || echo 0)"

# 2. Attempt concurrent acquisition in subshell while lock is held
concurrent_status=0
(
    acquire_installer_lock 2>/dev/null || exit 1
) || concurrent_status=$?
echo "concurrent_rejected=$concurrent_status"

# 3. Clean release
release_installer_lock
echo "lock1_released=1"

# 4. Re-acquire after release
reacquire_status=0
acquire_installer_lock || reacquire_status=$?
echo "reacquire_ok=$([[ $reacquire_status -eq 0 ]] && echo 1 || echo 0)"
release_installer_lock

# 5. Missing flock utility fails closed
missing_flock_status=0
installer_proceeded=0
(
    command_exists() {
        if [[ "$1" == "flock" ]]; then return 1; fi
        command -v "$1" >/dev/null 2>&1
    }
    acquire_installer_lock || exit $?
    installer_proceeded=1
) 2>/dev/null || missing_flock_status=$?

echo "missing_flock_status=$missing_flock_status"
echo "installer_proceeded=$installer_proceeded"

# 6. Missing stat metadata utility fails closed
missing_stat_status=0
(
    command_exists() {
        if [[ "$1" == "stat" ]]; then return 1; fi
        command -v "$1" >/dev/null 2>&1
    }
    get_installer_lock_path || exit $?
) 2>/dev/null || missing_stat_status=$?
echo "missing_stat_status=$missing_stat_status"

# 7. Foreign-owned candidate rejected
foreign_val_status=0
(
    OVERRIDE_EUID=9995 validate_lock_directory "$test_lock_dir" 9995 >/dev/null 2>&1
) || foreign_val_status=$?
echo "foreign_owned_rejected=$([[ $foreign_val_status -ne 0 ]] && echo 1 || echo 0)"

# 8. Unsafe group/world writable permissions candidate rejected
unsafe_perm_dir="$(mktemp -d)"
chmod 0777 "$unsafe_perm_dir"
unsafe_perm_status=0
(
    validate_lock_directory "$unsafe_perm_dir" "$current_uid" >/dev/null 2>&1
) || unsafe_perm_status=$?
rm -rf "$unsafe_perm_dir"
echo "unsafe_perm_rejected=$([[ $unsafe_perm_status -ne 0 ]] && echo 1 || echo 0)"

# 9. Symlink candidate rejected
symlink_candidate="$(mktemp -u)"
ln -s "$test_lock_dir" "$symlink_candidate"
symlink_cand_status=0
(
    validate_lock_directory "$symlink_candidate" "$current_uid" >/dev/null 2>&1
) || symlink_cand_status=$?
rm -f "$symlink_candidate"
echo "symlink_candidate_rejected=$([[ $symlink_cand_status -ne 0 ]] && echo 1 || echo 0)"

# 10. Relative XDG_RUNTIME_DIR path rejected
relative_xdg_status=0
(
    validate_lock_directory "relative/path" "$current_uid" >/dev/null 2>&1
) || relative_xdg_status=$?
echo "relative_xdg_rejected=$([[ $relative_xdg_status -ne 0 ]] && echo 1 || echo 0)"

# 11. Safe per-user runtime-directory candidate behavior.
# The managed test sandbox may expose /run/user/$UID read-only even when its
# Unix metadata is correct, so use an isolated equivalent fixture when the host
# path cannot be probed without touching live runtime state.
run_user_candidate="/run/user/${current_uid}"
run_user_fixture=""
if [[ ! -w "$run_user_candidate" ]]; then
    run_user_fixture="$(mktemp -d)"
    chmod 0700 "$run_user_fixture"
    run_user_candidate="$run_user_fixture"
fi
run_user_status=0
validate_lock_directory "$run_user_candidate" "$current_uid" || run_user_status=$?
echo "run_user_ok=$([[ $run_user_status -eq 0 ]] && echo 1 || echo 0)"
rm -rf "$run_user_fixture"

# 11b. Production mode must ignore the fixture-only UID override.
production_lock_path=""
production_lock_status=0
production_lock_path="$(INSTALLER_PRODUCTION_MODE=1 OVERRIDE_EUID=9992 \
    XDG_RUNTIME_DIR="$test_lock_dir" get_installer_lock_path)" || production_lock_status=$?
echo "production_override_ignored=$([[ $production_lock_status -eq 0 && \
    "$production_lock_path" == "$test_lock_dir/fedora-hyprland-workstation.lock" ]] && echo 1 || echo 0)"

# 12. Fallback to safe private directory in /tmp when XDG_RUNTIME_DIR and /run/user are unavailable
unset XDG_RUNTIME_DIR
fallback_path="$(get_installer_lock_path)"
echo "fallback_uses_private_dir=$([[ "$fallback_path" == "/run/user/"*"/fedora-hyprland-workstation.lock" || "$fallback_path" == "/tmp/.fhw-lock-${current_uid}/installer.lock" ]] && echo 1 || echo 0)"

# 13. Hostile pre-existing fallback symlink rejected
hostile_sym_uid="9994"
hostile_sym_dir="/tmp/.fhw-lock-${hostile_sym_uid}"
rm -rf "$hostile_sym_dir"
ln -s "/tmp" "$hostile_sym_dir"
hostile_sym_status=0
(
    OVERRIDE_EUID="$hostile_sym_uid" get_installer_lock_path >/dev/null 2>&1
) || hostile_sym_status=$?
rm -f "$hostile_sym_dir"
echo "hostile_fallback_symlink_rejected=$([[ $hostile_sym_status -ne 0 ]] && echo 1 || echo 0)"

# 14. Hostile/foreign fallback directory rejected without chmod-ing
hostile_dir_uid="9993"
hostile_dir="/tmp/.fhw-lock-${hostile_dir_uid}"
rm -rf "$hostile_dir"
mkdir -m 0700 "$hostile_dir"
hostile_dir_status=0
(
    OVERRIDE_EUID="$hostile_dir_uid" get_installer_lock_path >/dev/null 2>&1
) || hostile_dir_status=$?
rm -rf "$hostile_dir"
echo "hostile_foreign_fallback_rejected=$([[ $hostile_dir_status -ne 0 ]] && echo 1 || echo 0)"

rm -rf "$test_lock_dir" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$lock_test_output" | grep -q 'lock1_acquired=1' &&
   printf '%s\n' "$lock_test_output" | grep -q 'lock_fd_dynamic=1' &&
   printf '%s\n' "$lock_test_output" | grep -qE 'concurrent_rejected=[1-9]' &&
   printf '%s\n' "$lock_test_output" | grep -q 'reacquire_ok=1'; then
    pass "installer concurrency lock prevents simultaneous runs and releases cleanly"
else
    fail "installer concurrency lock failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -qE 'missing_flock_status=[1-9]' &&
   printf '%s\n' "$lock_test_output" | grep -q 'installer_proceeded=0'; then
    pass "missing flock utility fails closed and prevents installer execution from proceeding"
else
    fail "missing flock fail-closed verification failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -qE 'missing_stat_status=[1-9]'; then
    pass "missing stat utility fails closed and prevents lock path determination"
else
    fail "missing stat fail-closed verification failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'foreign_owned_rejected=1'; then
    pass "validate_lock_directory rejects foreign-owned directory candidates"
else
    fail "foreign-owned directory rejection failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'unsafe_perm_rejected=1'; then
    pass "validate_lock_directory rejects candidates with unsafe group/world write permissions"
else
    fail "unsafe permissions rejection failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'symlink_candidate_rejected=1'; then
    pass "validate_lock_directory rejects symlink candidate directories"
else
    fail "symlink candidate rejection failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'relative_xdg_rejected=1'; then
    pass "validate_lock_directory rejects relative path candidates"
else
    fail "relative path candidate rejection failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'run_user_ok=1'; then
    pass "validate_lock_directory verifies valid /run/user/\$UID directory when available"
else
    fail "/run/user/\$UID validation failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'fallback_uses_private_dir=1'; then
    pass "locking safely falls back to a private per-user directory when runtime directory is missing"
else
    fail "lock fallback resolution failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'hostile_fallback_symlink_rejected=1'; then
    pass "lock path resolution rejects pre-existing hostile symlinks in fallback directory"
else
    fail "hostile fallback symlink rejection failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'hostile_foreign_fallback_rejected=1'; then
    pass "lock path resolution rejects foreign-owned fallback directory without modifying it"
else
    fail "hostile foreign fallback rejection failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'production_override_ignored=1'; then
    pass "production lock-path resolution ignores test UID overrides"
else
    fail "production lock-path resolution honored a test UID override: $lock_test_output"
fi

lock_lifecycle_body="$(sed -n '/^cleanup_installer_children() {/,/^}/p' "$ROOT/install.sh")"
if [[ -n "$lock_lifecycle_body" ]] &&
   ! grep -q 'release_installer_lock' <<< "$lock_lifecycle_body" &&
   grep -q 'wait.*ACTIVE_TIMEOUT_PID' <<< "$lock_lifecycle_body" &&
   grep -q 'finalize_installer_state' "$ROOT/install.sh" &&
   grep -q 'release_installer_lock' "$ROOT/install.sh"; then
    pass "installer keeps the exclusive lock through child cleanup and final state handling"
else
    fail "installer lock lifecycle releases the lock before cleanup/finalization"
fi

if grep -q 'exec {INSTALLER_LOCK_FD}>' "$ROOT/modules/state.sh" &&
   ! grep -q 'eval .*INSTALLER_LOCK' "$ROOT/modules/state.sh" &&
   grep -q 'validate_mutation_path "\$INSTALLER_STATE_ROOT"' "$ROOT/modules/state.sh" &&
   grep -q -- '-g "\$target_gid"' "$ROOT/modules/state.sh" &&
   grep -q 'write_installer_state_file' "$ROOT/modules/state.sh" &&
   grep -q 'mktemp "\$INSTALLER_STATE_ROOT/logs/install-' "$ROOT/modules/state.sh"; then
    pass "state initialization uses validated paths and numeric target ownership without dynamic redirection"
else
    fail "state initialization safety contract is incomplete"
fi

state_file_safety_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
TARGET_HOME="$(mktemp -d)"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/status.sh"
source "$ROOT/modules/state.sh"
INSTALLER_STATE_ROOT="$TARGET_HOME/state"
mkdir -p "$INSTALLER_STATE_ROOT/state"

safe_target="$INSTALLER_STATE_ROOT/state/last-run"
write_installer_state_file "$safe_target" 'status=ok'
safe_write_ok=$([[ -f "$safe_target" && "$(<"$safe_target")" == 'status=ok' ]] && echo 1 || echo 0)

outside="$TARGET_HOME/outside"
printf 'preserve-me\n' > "$outside"
rm -f "$safe_target"
ln -s "$outside" "$safe_target"
symlink_write_status=0
write_installer_state_file "$safe_target" 'status=must-not-write' || symlink_write_status=$?
printf 'safe_write=%s symlink_rejected=%s outside_preserved=%s\n' \
    "$safe_write_ok" \
    "$([[ $symlink_write_status -ne 0 ]] && echo 1 || echo 0)" \
    "$([[ "$(<"$outside")" == 'preserve-me' ]] && echo 1 || echo 0)"

outside_journal="$TARGET_HOME/outside-journal"
journal_target="$INSTALLER_STATE_ROOT/state/journal"
printf 'preserve-journal-target\n' > "$outside_journal"
ln -- "$outside_journal" "$journal_target"
journal_stage_status=0
journal_stage test-stage started || journal_stage_status=$?
journal_written=0
if [[ -f "$journal_target" ]] && grep -q 'test-stage started' "$journal_target"; then
    journal_written=1
fi
printf 'journal_hardlink_safe=%s journal_written=%s\n' \
    "$([[ $journal_stage_status -eq 0 && "$(<"$outside_journal")" == 'preserve-journal-target' ]] && echo 1 || echo 0)" \
    "$journal_written"
rm -rf -- "$TARGET_HOME"
EOS
)"

if grep -q 'safe_write=1 symlink_rejected=1 outside_preserved=1' <<< "$state_file_safety_output"; then
    pass "persistent installer state writes atomically and rejects symlinked destinations"
else
    fail "persistent installer state file safety failed: $state_file_safety_output"
fi

if grep -q 'journal_hardlink_safe=1 journal_written=1' <<< "$state_file_safety_output"; then
    pass "persistent journal updates cannot mutate a hardlinked external file"
else
    fail "persistent journal update followed a hardlink or failed to write safely: $state_file_safety_output"
fi
