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
XDG_RUNTIME_DIR="$test_lock_dir"

# 1. Normal lock acquisition
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

# 6. Fallback to private directory in /tmp when XDG_RUNTIME_DIR and /run/user are unavailable
unset XDG_RUNTIME_DIR
current_uid="${EUID:-$(id -u)}"
fallback_path="$(get_installer_lock_path)"
echo "fallback_uses_private_dir=$([[ "$fallback_path" == "/run/user/"*"/fedora-hyprland-workstation.lock" || "$fallback_path" == "/tmp/.fhw-lock-${current_uid}/installer.lock" ]] && echo 1 || echo 0)"

# 7. Foreign ownership and symlink attack rejection on fallback directory
foreign_uid="9998"
foreign_attack_dir="/tmp/.fhw-lock-${foreign_uid}"
rm -rf "$foreign_attack_dir"
mkdir -m 0700 "$foreign_attack_dir"
foreign_attack_status=0
(
    OVERRIDE_EUID="$foreign_uid" get_installer_lock_path >/dev/null 2>&1
) || foreign_attack_status=$?
rm -rf "$foreign_attack_dir"

symlink_attack_dir="/tmp/.fhw-lock-${foreign_uid}"
ln -s "/tmp" "$symlink_attack_dir"
symlink_attack_status=0
(
    OVERRIDE_EUID="$foreign_uid" get_installer_lock_path >/dev/null 2>&1
) || symlink_attack_status=$?
rm -f "$symlink_attack_dir"

echo "foreign_ownership_rejected=$([[ $foreign_attack_status -ne 0 ]] && echo 1 || echo 0)"
echo "symlink_attack_rejected=$([[ $symlink_attack_status -ne 0 ]] && echo 1 || echo 0)"

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

if printf '%s\n' "$lock_test_output" | grep -q 'fallback_uses_private_dir=1'; then
    pass "locking safely falls back to a private per-user directory when runtime directory is missing"
else
    fail "lock fallback resolution failed: $lock_test_output"
fi

if printf '%s\n' "$lock_test_output" | grep -q 'foreign_ownership_rejected=1' &&
   printf '%s\n' "$lock_test_output" | grep -q 'symlink_attack_rejected=1'; then
    pass "lock path resolution rejects foreign directory ownership and pre-existing symlinks in fallback directory"
else
    fail "foreign ownership or symlink attack rejection failed: $lock_test_output"
fi
