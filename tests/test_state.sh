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

# 11. Safe /run/user/$UID candidate behavior
run_user_status=0
if [[ -d "/run/user/${current_uid}" ]]; then
    validate_lock_directory "/run/user/${current_uid}" "$current_uid" || run_user_status=$?
fi
echo "run_user_ok=$([[ $run_user_status -eq 0 ]] && echo 1 || echo 0)"

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
