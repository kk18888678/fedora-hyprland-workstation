#!/usr/bin/env bash

# Test Suite: Browser repository identity and package-provider correctness.

section "Browser Repository Trust"

if grep -qF 'install_dnf_packages brave-browser' "$ROOT/modules/browsers.sh" &&
   ! grep -qF 'install_dnf_packages brave-origin' "$ROOT/modules/browsers.sh"; then
    pass "Brave Origin uses the official brave-browser RPM package"
else
    fail "Brave Origin still uses an invalid or ambiguous RPM package name"
fi

browser_repo_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
repo_dir=""
trap 'rm -rf -- "$TARGET_HOME" "$repo_dir"' EXIT

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/browsers.sh"

repo_dir="$(mktemp -d)"
brave_repo_file="$repo_dir/brave-browser.repo"
cursor_repo_file="$repo_dir/cursor.repo"

# Isolate root-file writes while exercising the exact production content.
install_root_file_from_stdin() {
    local destination="$1"
    cat > "$destination"
}
install_root_file_from_stdin_preserving_existing() {
    local destination="$1"
    cat > "$destination"
}

sudo() {
    [[ "${1:-}" == install ]] || return 1
    shift
    while [[ $# -gt 2 ]]; do
        shift
    done
    cp "$1" "$2"
}

configure_brave_origin_repository >/dev/null
brave_valid=0
brave_origin_repo_installed || brave_valid=$?

printf '%s\n' '[brave-browser]' 'enabled=1' 'gpgcheck=0' > "$brave_repo_file"
brave_reject=0
brave_origin_repo_installed || brave_reject=$?

configure_cursor_repository >/dev/null
cursor_valid=0
cursor_repo_configured || cursor_valid=$?

printf '%s\n' '[cursor]' 'baseurl=https://downloads.cursor.com/yumrepo' > "$cursor_repo_file"
cursor_reject=0
cursor_repo_configured || cursor_reject=$?

printf 'brave_valid=%s brave_reject=%s cursor_valid=%s cursor_reject=%s\n' \
    "$brave_valid" "$brave_reject" "$cursor_valid" "$cursor_reject"
EOS
)"

if grep -q 'brave_valid=0' <<< "$browser_repo_test_output" &&
   grep -q 'brave_reject=1' <<< "$browser_repo_test_output" &&
   grep -q 'cursor_valid=0' <<< "$browser_repo_test_output" &&
   grep -q 'cursor_reject=1' <<< "$browser_repo_test_output"; then
    pass "Brave and Cursor repository files require exact reviewed HTTPS definitions"
else
    fail "vendor repository definition validation failed: $browser_repo_test_output"
fi

vendor_repo_repair_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
repo_dir="$(mktemp -d)"
trap 'rm -rf -- "$TARGET_HOME" "$repo_dir"' EXIT

source "$SCRIPT_DIR/modules/common.sh"
source "$SCRIPT_DIR/modules/status.sh"
source "$SCRIPT_DIR/modules/repositories.sh"
source "$SCRIPT_DIR/modules/applications.sh"
source "$SCRIPT_DIR/modules/browsers.sh"

cursor_repo_file="$repo_dir/cursor.repo"
brave_repo_file="$repo_dir/brave-browser.repo"
printf '%s\n' '[cursor]' 'gpgcheck=0' > "$cursor_repo_file"
printf '%s\n' '[brave-browser]' 'gpgcheck=0' > "$brave_repo_file"

# Isolate the root-file mutation while exercising repository convergence.
install_root_file_from_stdin() {
    local destination="$1"
    cat > "$destination"
}
install_root_file_from_stdin_preserving_existing() {
    local destination="$1"
    cat > "$destination"
}

CURSOR=false
BROWSER_BRAVE_ORIGIN=false
converge_vendor_repository_definitions
printf 'cursor_repaired=%s brave_repaired=%s\n' \
    "$([[ "$(sed -n '1,6p' "$cursor_repo_file")" == $'[cursor]\nname=Cursor\nbaseurl=https://downloads.cursor.com/yumrepo\nenabled=1\ngpgcheck=1\ngpgkey=https://downloads.cursor.com/keys/anysphere.asc' ]] && echo 1 || echo 0)" \
    "$([[ "$(sed -n '1,6p' "$brave_repo_file")" == $'[brave-browser]\nname=Brave Browser\nenabled=1\ngpgcheck=1\ngpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc\nbaseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch' ]] && echo 1 || echo 0)"
EOS
)"

if grep -q 'cursor_repaired=1' <<< "$vendor_repo_repair_output" &&
   grep -q 'brave_repaired=1' <<< "$vendor_repo_repair_output"; then
    pass "existing vendor repository drift is repaired before DNF trust gating"
else
    fail "vendor repository repair ordering failed: $vendor_repo_repair_output"
fi

if grep -q 'install_root_file_from_stdin_preserving_existing "\$brave_repo_file"' "$ROOT/modules/browsers.sh" &&
   grep -q 'install_root_file_from_stdin_preserving_existing "\$cursor_repo_file"' "$ROOT/modules/applications.sh"; then
    pass "vendor repository repair preserves replaced definitions as recoverable backups"
else
    fail "vendor repository repair can overwrite existing definitions without preservation"
fi
