#!/usr/bin/env bash

# Test Suite: Filesystem safety, path validation, symlink replacements, backup collisions, and namespace guards.

section "Path & Symlink Safety Invariants"

path_safety_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

sandbox="$(mktemp -d)"

# 1. Empty path checks
empty_dir_status=0
( ensure_directory "" >/dev/null 2>&1 ) || empty_dir_status=$?

empty_sym_src_status=0
( ensure_symlink "" "$sandbox/dest" >/dev/null 2>&1 ) || empty_sym_src_status=$?

empty_sym_dst_status=0
( ensure_symlink "$sandbox/src" "" >/dev/null 2>&1 ) || empty_sym_dst_status=$?

# 2. Refusal of root '/' as symlink destination
root_dst_status=0
( ensure_symlink "$sandbox/src" "/" >/dev/null 2>&1 ) || root_dst_status=$?

# 3. Refusal of relative '.' and '..'
dot_dir_status=0
( ensure_directory "." >/dev/null 2>&1 ) || dot_dir_status=$?
dot_sym_status=0
( ensure_symlink "$sandbox/src" ".." >/dev/null 2>&1 ) || dot_sym_status=$?

# 4. Target exists as regular file when ensuring directory
file_as_dir_target="$sandbox/existing_file_target"
touch "$file_as_dir_target"
file_as_dir_status=0
( ensure_directory "$file_as_dir_target" >/dev/null 2>&1 ) || file_as_dir_status=$?

# 5. Normal symlink creation & Idempotent re-run
src_file="$sandbox/test_source"
echo "source-content" > "$src_file"
dst_link="$sandbox/test_link"

ensure_symlink "$src_file" "$dst_link"
sym_created=$([[ -L "$dst_link" && "$(readlink "$dst_link")" == "$src_file" ]] && echo 1 || echo 0)

# Re-run same symlink (must be no-op without creating backups)
ensure_symlink "$src_file" "$dst_link"
backup_count_after_rerun="$(find "$sandbox" -name "test_link.bak*" | wc -l)"

# 6. Existing project-owned symlink pointing to old target replaced cleanly without backup
old_src="$sandbox/old_source"
echo "old-content" > "$old_src"
ensure_symlink "$old_src" "$dst_link"
ensure_symlink "$src_file" "$dst_link"
sym_retargeted=$([[ -L "$dst_link" && "$(readlink "$dst_link")" == "$src_file" ]] && echo 1 || echo 0)
backup_count_after_retarget="$(find "$sandbox" -name "test_link.bak*" | wc -l)"

# 7. Existing regular user file backed up before symlink creation
existing_file_dest="$sandbox/user_regular_file"
echo "user-data" > "$existing_file_dest"
ensure_symlink "$src_file" "$existing_file_dest"
file_backed_up=$([[ -L "$existing_file_dest" && $(find "$sandbox" -name "user_regular_file.bak*" | wc -l) -ge 1 ]] && echo 1 || echo 0)

# 8. Backup collision resolution (when .bak timestamp already exists)
collision_dest="$sandbox/collision_target"
echo "user-data-1" > "$collision_dest"
fixed_timestamp="$(date +%Y%m%d-%H%M%S)"
# Pre-create conflicting backup file
touch "${collision_dest}.bak.${fixed_timestamp}"
ensure_symlink "$src_file" "$collision_dest"
collision_resolved=$([[ -L "$collision_dest" && $(find "$sandbox" -name "collision_target.bak*" | wc -l) -ge 2 ]] && echo 1 || echo 0)

# 9. Existing directory backed up before symlink creation
existing_dir_dest="$sandbox/user_dir"
mkdir -p "$existing_dir_dest"
echo "inside-dir" > "$existing_dir_dest/file"
ensure_symlink "$src_file" "$existing_dir_dest"
dir_backed_up=$([[ -L "$existing_dir_dest" && $(find "$sandbox" -name "user_dir.bak*" | wc -l) -ge 1 ]] && echo 1 || echo 0)

# 10. Domain-specific namespace boundary checking (caller validates expected managed namespace)
validate_managed_dotfile_path() {
    local target="$1"
    local allowed_prefix="$2"
    if [[ "$target" != "$allowed_prefix"* ]]; then
        error "Destination '$target' escapes managed namespace '$allowed_prefix'."
        return 1
    fi
    return 0
}

ns_ok=0
validate_managed_dotfile_path "$TARGET_HOME/.config/hypr" "$TARGET_HOME" || ns_ok=$?
ns_escape_status=0
validate_managed_dotfile_path "/etc/shadow" "$TARGET_HOME" >/dev/null 2>&1 || ns_escape_status=$?

echo "empty_dir_status=$empty_dir_status"
echo "empty_sym_src_status=$empty_sym_src_status"
echo "empty_sym_dst_status=$empty_sym_dst_status"
echo "root_dst_status=$root_dst_status"
echo "dot_dir_status=$dot_dir_status"
echo "dot_sym_status=$dot_sym_status"
echo "file_as_dir_status=$file_as_dir_status"
echo "sym_created=$sym_created"
echo "backup_count_after_rerun=$backup_count_after_rerun"
echo "sym_retargeted=$sym_retargeted"
echo "backup_count_after_retarget=$backup_count_after_retarget"
echo "file_backed_up=$file_backed_up"
echo "collision_resolved=$collision_resolved"
echo "dir_backed_up=$dir_backed_up"
echo "ns_ok=$ns_ok"
echo "ns_escape_status=$ns_escape_status"

rm -rf "$sandbox" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$path_safety_output" | grep -qE 'empty_dir_status=[1-9]' &&
   printf '%s\n' "$path_safety_output" | grep -qE 'empty_sym_src_status=[1-9]' &&
   printf '%s\n' "$path_safety_output" | grep -qE 'empty_sym_dst_status=[1-9]'; then
    pass "empty path parameters fail closed across directory and symlink helpers"
else
    fail "empty path parameter validation failed: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -qE 'root_dst_status=[1-9]'; then
    pass "ensure_symlink refuses destination as root directory '/'"
else
    fail "ensure_symlink accepted root destination: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -qE 'dot_dir_status=[1-9]' &&
   printf '%s\n' "$path_safety_output" | grep -qE 'dot_sym_status=[1-9]'; then
    pass "path helpers refuse relative '.' and '..' destinations"
else
    fail "path helpers accepted relative dot destinations: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -qE 'file_as_dir_status=[1-9]'; then
    pass "ensure_directory fails closed when target already exists as a non-directory file"
else
    fail "ensure_directory did not fail on existing regular file: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -q 'sym_created=1' &&
   printf '%s\n' "$path_safety_output" | grep -q 'backup_count_after_rerun=0'; then
    pass "ensure_symlink creates valid symlink and is idempotent on repeat runs without backup pollution"
else
    fail "ensure_symlink creation or idempotency failed: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -q 'sym_retargeted=1' &&
   printf '%s\n' "$path_safety_output" | grep -q 'backup_count_after_retarget=0'; then
    pass "existing project-owned symlink is retargeted cleanly without creating redundant backups"
else
    fail "project-owned symlink retargeting failed: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -q 'file_backed_up=1'; then
    pass "existing regular user file is safely backed up before symlink creation"
else
    fail "existing regular file backup failed: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -q 'collision_resolved=1'; then
    pass "backup collision resolution handles duplicate timestamps without data loss"
else
    fail "backup collision resolution failed: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -q 'dir_backed_up=1'; then
    pass "existing user directory is safely moved to backup before symlink creation"
else
    fail "existing directory backup failed: $path_safety_output"
fi

if printf '%s\n' "$path_safety_output" | grep -q 'ns_ok=0' &&
   printf '%s\n' "$path_safety_output" | grep -qE 'ns_escape_status=[1-9]'; then
    pass "domain-specific namespace validation protects against out-of-namespace targets"
else
    fail "domain-specific namespace validation failed: $path_safety_output"
fi
