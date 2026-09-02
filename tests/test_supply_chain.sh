#!/usr/bin/env bash

# Test Suite: Supply chain integrity, cryptographic hashes, deterministic archive safety, and traversal guards.

section "Pins"

# shellcheck source=/dev/null
source "$ROOT/config/versions.conf"

pins=(
    OH_MY_ZSH_COMMIT
    ZSH_AUTOSUGGESTIONS_COMMIT
    ZSH_SYNTAX_HIGHLIGHTING_COMMIT
    NIXPKGS_REV
    DEVENV_NIX_INSTALL_SPEC
    ANTIGRAVITY_VERSION
    ANTIGRAVITY_URL
    ANTIGRAVITY_SHA512
    CCEXTRACTOR_VERSION
    CCEXTRACTOR_URL
    CCEXTRACTOR_SHA512
    BENTO4_VERSION
    BENTO4_URL
    BENTO4_SHA512
    SHAKA_PACKAGER_VERSION
    SHAKA_PACKAGER_URL
    SHAKA_PACKAGER_SHA512
    DOVI_TOOL_VERSION
    DOVI_TOOL_URL
    DOVI_TOOL_SHA512
    N_M3U8DL_RE_VERSION
    N_M3U8DL_RE_URL
    N_M3U8DL_RE_SHA512
)

for p in "${pins[@]}"; do
    if [[ -n "${!p:-}" ]]; then
        pass "pin $p"
    else
        fail "missing pin $p"
    fi
done

if [[ "$DOVI_TOOL_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "DOVI_TOOL_SHA512 is valid 128-character hex"
else
    fail "DOVI_TOOL_SHA512 format invalid"
fi

if [[ "$CCEXTRACTOR_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "CCEXTRACTOR_SHA512 is valid 128-character hex"
else
    fail "CCEXTRACTOR_SHA512 format invalid"
fi

if [[ "$BENTO4_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "BENTO4_SHA512 is valid 128-character hex"
else
    fail "BENTO4_SHA512 format invalid"
fi

if [[ "$SHAKA_PACKAGER_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "SHAKA_PACKAGER_SHA512 is valid 128-character hex"
else
    fail "SHAKA_PACKAGER_SHA512 format invalid"
fi

if [[ "$N_M3U8DL_RE_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "N_M3U8DL_RE_SHA512 is valid 128-character hex"
else
    fail "N_M3U8DL_RE_SHA512 format invalid"
fi

section "Verified Supply-Chain Artifact Provisioning"

artifact_prov_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

test_sandbox="$(mktemp -d)"
test_payload="$test_sandbox/bin_content"
printf '#!/bin/sh\necho test-bin\n' > "$test_payload"
chmod +x "$test_payload"

correct_sha512="$(sha512sum "$test_payload" | cut -d' ' -f1)"
wrong_sha512="00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

RETRY_BACKOFF_SECONDS=()
timeout() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" =~ ^--kill-after= || "$1" =~ ^[0-9]+s?$ ]]; then
            shift
            continue
        fi
        break
    done
    "$@"
}

# Mock curl to copy local payload
curl() {
    local out_file=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-o" ]]; then
            out_file="$2"
            shift 2
            continue
        fi
        shift
    done
    cp "$test_payload" "$out_file"
}

# 1. Successful verified binary provision
test_dest="$test_sandbox/installed_bin"
status_ok=0
provision_verified_binary "https://example.com/bin" "$correct_sha512" "$test_dest" "test_bin" false || status_ok=$?
echo "prov_ok=$([[ $status_ok -eq 0 && -x "$test_dest" ]] && echo 1 || echo 0)"

# 2. Checksum mismatch fails closed
test_bad_dest="$test_sandbox/bad_bin"
status_bad=0
provision_verified_binary "https://example.com/bin" "$wrong_sha512" "$test_bad_dest" "bad_bin" false >/dev/null 2>&1 || status_bad=$?
echo "mismatch_rejected=$([[ $status_bad -ne 0 && ! -e "$test_bad_dest" ]] && echo 1 || echo 0)"

# 3. Non-HTTPS URL rejected
test_insecure_dest="$test_sandbox/insecure_bin"
status_insecure=0
provision_verified_binary "http://insecure.example.com/bin" "$correct_sha512" "$test_insecure_dest" "insecure_bin" false >/dev/null 2>&1 || status_insecure=$?
echo "insecure_rejected=$([[ $status_insecure -ne 0 && ! -e "$test_insecure_dest" ]] && echo 1 || echo 0)"

rm -rf "$test_sandbox" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$artifact_prov_output" | grep -q 'prov_ok=1'; then
    pass "provision_verified_binary successfully verifies and deploys executable"
else
    fail "provision_verified_binary failed successful deploy: $artifact_prov_output"
fi

if printf '%s\n' "$artifact_prov_output" | grep -q 'mismatch_rejected=1'; then
    pass "provision_verified_binary rejects checksum mismatch and does not install"
else
    fail "provision_verified_binary failed to reject checksum mismatch: $artifact_prov_output"
fi

if printf '%s\n' "$artifact_prov_output" | grep -q 'insecure_rejected=1'; then
    pass "provision_verified_binary rejects insecure non-HTTPS download URLs"
else
    fail "provision_verified_binary accepted non-HTTPS URL: $artifact_prov_output"
fi

section "Archive Provisioning & Structure Safety Fixtures"

archive_safety_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

fixture_dir="$(mktemp -d)"
current_payload_file=""

RETRY_BACKOFF_SECONDS=()
timeout() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" =~ ^--kill-after= || "$1" =~ ^[0-9]+s?$ ]]; then
            shift
            continue
        fi
        break
    done
    "$@"
}

curl() {
    local out_file=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-o" ]]; then
            out_file="$2"
            shift 2
            continue
        fi
        shift
    done
    cp "$current_payload_file" "$out_file"
}

# 1. Valid tar archive with declared binary
mkdir -p "$fixture_dir/valid_src"
printf '#!/bin/sh\necho my-tool\n' > "$fixture_dir/valid_src/my_tool"
chmod +x "$fixture_dir/valid_src/my_tool"
tar -czf "$fixture_dir/valid.tar.gz" -C "$fixture_dir/valid_src" my_tool
valid_hash="$(sha512sum "$fixture_dir/valid.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/valid.tar.gz"
valid_dest="$fixture_dir/installed_valid/my_tool"
valid_status=0
provision_verified_archive "https://example.com/valid.tar.gz" "$valid_hash" "$valid_dest" "my_tool" "valid_tool" false || valid_status=$?

echo "valid_archive_ok=$([[ $valid_status -eq 0 && -x "$valid_dest" ]] && echo 1 || echo 0)"

# 2. Path traversal (../) rejected
mkdir -p "$fixture_dir/traversal_src"
printf 'malicious\n' > "$fixture_dir/traversal_src/evil"
tar -czf "$fixture_dir/traversal.tar.gz" -C "$fixture_dir" ../traversal.tar.gz 2>/dev/null || true
# Manually create archive with relative .. path member if needed
tar -czf "$fixture_dir/traversal.tar.gz" -C "$fixture_dir/traversal_src" --transform 's|^|../|' evil 2>/dev/null || true

traversal_hash="$(sha512sum "$fixture_dir/traversal.tar.gz" | cut -d' ' -f1)"
current_payload_file="$fixture_dir/traversal.tar.gz"
traversal_dest="$fixture_dir/installed_traversal/evil"
traversal_status=0
(
    provision_verified_archive "https://example.com/traversal.tar.gz" "$traversal_hash" "$traversal_dest" "evil" "evil_tool" false >/dev/null 2>&1
) || traversal_status=$?

echo "traversal_rejected=$([[ $traversal_status -ne 0 && ! -e "$traversal_dest" ]] && echo 1 || echo 0)"

# 3. Symlink escape rejected
mkdir -p "$fixture_dir/sym_src"
ln -s "/etc/shadow" "$fixture_dir/sym_src/sym_link"
tar -czf "$fixture_dir/symlink_escape.tar.gz" -C "$fixture_dir/sym_src" sym_link
sym_hash="$(sha512sum "$fixture_dir/symlink_escape.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/symlink_escape.tar.gz"
sym_dest="$fixture_dir/installed_sym/sym_link"
sym_status=0
(
    provision_verified_archive "https://example.com/symlink_escape.tar.gz" "$sym_hash" "$sym_dest" "sym_link" "sym_tool" false >/dev/null 2>&1
) || sym_status=$?

echo "symlink_escape_rejected=$([[ $sym_status -ne 0 && ! -e "$sym_dest" ]] && echo 1 || echo 0)"

# 4. Missing declared binary rejected (archive contains tool_b, but we declare tool_a)
mkdir -p "$fixture_dir/mismatch_src"
printf '#!/bin/sh\necho other\n' > "$fixture_dir/mismatch_src/other_binary"
chmod +x "$fixture_dir/mismatch_src/other_binary"
tar -czf "$fixture_dir/mismatch.tar.gz" -C "$fixture_dir/mismatch_src" other_binary
mismatch_hash="$(sha512sum "$fixture_dir/mismatch.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/mismatch.tar.gz"
mismatch_dest="$fixture_dir/installed_mismatch/expected_binary"
mismatch_status=0
(
    provision_verified_archive "https://example.com/mismatch.tar.gz" "$mismatch_hash" "$mismatch_dest" "expected_binary" "missing_test" false >/dev/null 2>&1
) || mismatch_status=$?

echo "missing_binary_rejected=$([[ $mismatch_status -ne 0 && ! -e "$mismatch_dest" ]] && echo 1 || echo 0)"

rm -rf "$fixture_dir" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$archive_safety_output" | grep -q 'valid_archive_ok=1'; then
    pass "provision_verified_archive successfully verifies and installs valid declared binary"
else
    fail "provision_verified_archive failed on valid archive: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'traversal_rejected=1'; then
    pass "provision_verified_archive detects and rejects path traversal (../) in archive members"
else
    fail "provision_verified_archive accepted traversal archive: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'symlink_escape_rejected=1'; then
    pass "provision_verified_archive detects and rejects symlinks escaping staging directory"
else
    fail "provision_verified_archive accepted escaping symlink: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'missing_binary_rejected=1'; then
    pass "provision_verified_archive fails closed when declared binary is missing and refuses to install arbitrary executables"
else
    fail "provision_verified_archive fell back to arbitrary executable: $archive_safety_output"
fi
