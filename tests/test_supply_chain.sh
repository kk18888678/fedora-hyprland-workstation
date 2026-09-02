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
run_with_timeout() {
    shift 2
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
run_with_timeout() {
    shift 2
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

# 1. Valid archive + exact expected member -> PASS
mkdir -p "$fixture_dir/valid_src"
printf '#!/bin/sh\necho my-tool\n' > "$fixture_dir/valid_src/my_tool"
chmod +x "$fixture_dir/valid_src/my_tool"
tar -czf "$fixture_dir/valid.tar.gz" -C "$fixture_dir/valid_src" my_tool
valid_hash="$(sha512sum "$fixture_dir/valid.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/valid.tar.gz"
valid_dest="$fixture_dir/installed_valid/my_tool"
valid_status=0
provision_verified_archive "https://example.com/valid.tar.gz" "$valid_hash" "$valid_dest" "my_tool" "valid_tool" false || valid_status=$?
echo "test1_valid_archive_ok=$([[ $valid_status -eq 0 && -x "$valid_dest" ]] && echo 1 || echo 0)"

# 2. Expected member absent -> FAIL
current_payload_file="$fixture_dir/valid.tar.gz"
absent_dest="$fixture_dir/installed_absent/absent_tool"
absent_status=0
(
    provision_verified_archive "https://example.com/valid.tar.gz" "$valid_hash" "$absent_dest" "nonexistent_member" "absent_test" false >/dev/null 2>&1
) || absent_status=$?
echo "test2_absent_member_rejected=$([[ $absent_status -ne 0 && ! -e "$absent_dest" ]] && echo 1 || echo 0)"

# 3. Unexpected executable exists but expected member absent -> FAIL (never guess/fallback)
mkdir -p "$fixture_dir/rogue_src"
printf '#!/bin/sh\necho rogue\n' > "$fixture_dir/rogue_src/rogue_exec"
chmod +x "$fixture_dir/rogue_src/rogue_exec"
tar -czf "$fixture_dir/rogue.tar.gz" -C "$fixture_dir/rogue_src" rogue_exec
rogue_hash="$(sha512sum "$fixture_dir/rogue.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/rogue.tar.gz"
rogue_dest="$fixture_dir/installed_rogue/declared_tool"
rogue_status=0
(
    provision_verified_archive "https://example.com/rogue.tar.gz" "$rogue_hash" "$rogue_dest" "declared_tool" "rogue_test" false >/dev/null 2>&1
) || rogue_status=$?
echo "test3_rogue_exec_rejected=$([[ $rogue_status -ne 0 && ! -e "$rogue_dest" && ! -e "$fixture_dir/installed_rogue/rogue_exec" ]] && echo 1 || echo 0)"

# 4. Two files with same expected basename in different directories -> FAIL (ambiguity rejection)
mkdir -p "$fixture_dir/ambig_src/dir_a" "$fixture_dir/ambig_src/dir_b"
printf '#!/bin/sh\necho tool-a\n' > "$fixture_dir/ambig_src/dir_a/tool"
printf '#!/bin/sh\necho tool-b\n' > "$fixture_dir/ambig_src/dir_b/tool"
chmod +x "$fixture_dir/ambig_src/dir_a/tool" "$fixture_dir/ambig_src/dir_b/tool"
tar -czf "$fixture_dir/ambig.tar.gz" -C "$fixture_dir/ambig_src" dir_a dir_b
ambig_hash="$(sha512sum "$fixture_dir/ambig.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/ambig.tar.gz"
ambig_dest="$fixture_dir/installed_ambig/tool"
ambig_status=0
(
    provision_verified_archive "https://example.com/ambig.tar.gz" "$ambig_hash" "$ambig_dest" "tool" "ambig_test" false >/dev/null 2>&1
) || ambig_status=$?
echo "test4_ambiguous_rejected=$([[ $ambig_status -ne 0 && ! -e "$ambig_dest" ]] && echo 1 || echo 0)"

# 5. Exact expected relative member among other executables -> correct member
current_payload_file="$fixture_dir/ambig.tar.gz"
exact_dest="$fixture_dir/installed_exact/tool"
exact_status=0
provision_verified_archive "https://example.com/ambig.tar.gz" "$ambig_hash" "$exact_dest" "dir_a/tool" "exact_test" false || exact_status=$?
echo "test5_exact_subpath_ok=$([[ $exact_status -eq 0 && "$("$exact_dest")" == "tool-a" ]] && echo 1 || echo 0)"

# 6. Path traversal (../) rejected BEFORE extraction
mkdir -p "$fixture_dir/traversal_src"
printf 'malicious\n' > "$fixture_dir/traversal_src/evil"
tar -czf "$fixture_dir/traversal.tar.gz" -C "$fixture_dir/traversal_src" --transform 's|^|../|' evil 2>/dev/null || true
traversal_hash="$(sha512sum "$fixture_dir/traversal.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/traversal.tar.gz"
traversal_dest="$fixture_dir/installed_traversal/evil"
traversal_status=0
(
    provision_verified_archive "https://example.com/traversal.tar.gz" "$traversal_hash" "$traversal_dest" "evil" "evil_tool" false >/dev/null 2>&1
) || traversal_status=$?
echo "test6_traversal_rejected=$([[ $traversal_status -ne 0 && ! -e "$traversal_dest" ]] && echo 1 || echo 0)"

# 7. Absolute path member rejected BEFORE extraction
mkdir -p "$fixture_dir/abs_src"
printf 'abs-malicious\n' > "$fixture_dir/abs_src/abs_evil"
tar -czf "$fixture_dir/absolute.tar.gz" -C "$fixture_dir/abs_src" --transform 's|^|/tmp/|' abs_evil 2>/dev/null || true
abs_hash="$(sha512sum "$fixture_dir/absolute.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/absolute.tar.gz"
abs_dest="$fixture_dir/installed_abs/abs_evil"
abs_status=0
(
    provision_verified_archive "https://example.com/absolute.tar.gz" "$abs_hash" "$abs_dest" "abs_evil" "abs_tool" false >/dev/null 2>&1
) || abs_status=$?
echo "test7_absolute_rejected=$([[ $abs_status -ne 0 && ! -e "$abs_dest" ]] && echo 1 || echo 0)"

# 8. Symlink escape rejected
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
echo "test8_symlink_escape_rejected=$([[ $sym_status -ne 0 && ! -e "$sym_dest" ]] && echo 1 || echo 0)"

# 9. Hardlink escape rejected
mkdir -p "$fixture_dir/hardlink_src"
printf 'secret\n' > "$fixture_dir/hardlink_src/target_file"
ln "$fixture_dir/hardlink_src/target_file" "$fixture_dir/hardlink_src/hard_link"
tar -czf "$fixture_dir/hardlink.tar.gz" -C "$fixture_dir/hardlink_src" target_file hard_link
hardlink_hash="$(sha512sum "$fixture_dir/hardlink.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/hardlink.tar.gz"
hardlink_dest="$fixture_dir/installed_hardlink/target_file"
hardlink_status=0
provision_verified_archive "https://example.com/hardlink.tar.gz" "$hardlink_hash" "$hardlink_dest" "target_file" "hardlink_tool" false || hardlink_status=$?
echo "test9_hardlink_ok=$([[ $hardlink_status -eq 0 && -f "$hardlink_dest" ]] && echo 1 || echo 0)"

# 10. Archive listing command failure -> FAIL BEFORE EXTRACTION
printf 'NOT_A_REAL_TAR_ARCHIVE_CORRUPTED_BYTES' > "$fixture_dir/corrupt.tar.gz"
corrupt_hash="$(sha512sum "$fixture_dir/corrupt.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/corrupt.tar.gz"
corrupt_dest="$fixture_dir/installed_corrupt/tool"
corrupt_status=0
(
    provision_verified_archive "https://example.com/corrupt.tar.gz" "$corrupt_hash" "$corrupt_dest" "tool" "corrupt_test" false >/dev/null 2>&1
) || corrupt_status=$?
echo "test10_corrupt_listing_rejected=$([[ $corrupt_status -ne 0 && ! -e "$corrupt_dest" ]] && echo 1 || echo 0)"

# 11. Missing archive inspection utility fails closed
missing_tool_status=0
(
    command_exists() {
        if [[ "$1" == "tar" || "$1" == "unzip" ]]; then return 1; fi
        command -v "$1" >/dev/null 2>&1
    }
    current_payload_file="$fixture_dir/valid.tar.gz"
    provision_verified_archive "https://example.com/valid.tar.gz" "$valid_hash" "$fixture_dir/installed_missing/tool" "my_tool" "missing_tool_test" false || exit $?
) 2>/dev/null || missing_tool_status=$?
echo "test11_missing_tool_rejected=$([[ $missing_tool_status -ne 0 ]] && echo 1 || echo 0)"

# 12. Multiple explicitly required binaries all present -> PASS
mkdir -p "$fixture_dir/multi_src/bin"
printf '#!/bin/sh\necho tool1\n' > "$fixture_dir/multi_src/bin/tool1"
printf '#!/bin/sh\necho tool2\n' > "$fixture_dir/multi_src/bin/tool2"
printf '#!/bin/sh\necho tool3\n' > "$fixture_dir/multi_src/bin/tool3"
chmod +x "$fixture_dir/multi_src/bin/"*
tar -czf "$fixture_dir/multi.tar.gz" -C "$fixture_dir/multi_src" bin
multi_hash="$(sha512sum "$fixture_dir/multi.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/multi.tar.gz"
multi_dest_dir="$fixture_dir/installed_multi"
multi_status=0
provision_verified_archive "https://example.com/multi.tar.gz" "$multi_hash" "$multi_dest_dir" "bin/tool1 bin/tool2 bin/tool3" "multi_test" false || multi_status=$?
echo "test12_multi_all_present_ok=$([[ $multi_status -eq 0 && -x "$multi_dest_dir/tool1" && -x "$multi_dest_dir/tool2" && -x "$multi_dest_dir/tool3" ]] && echo 1 || echo 0)"

# 13. One binary missing from multi-binary set -> FAIL BEFORE installation (none installed)
mkdir -p "$fixture_dir/partial_src/bin"
printf '#!/bin/sh\necho tool1\n' > "$fixture_dir/partial_src/bin/tool1"
printf '#!/bin/sh\necho tool2\n' > "$fixture_dir/partial_src/bin/tool2"
chmod +x "$fixture_dir/partial_src/bin/"*
tar -czf "$fixture_dir/partial.tar.gz" -C "$fixture_dir/partial_src" bin
partial_hash="$(sha512sum "$fixture_dir/partial.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/partial.tar.gz"
partial_dest_dir="$fixture_dir/installed_partial"
partial_status=0
(
    provision_verified_archive "https://example.com/partial.tar.gz" "$partial_hash" "$partial_dest_dir" "bin/tool1 bin/tool2 bin/tool3_missing" "partial_test" false >/dev/null 2>&1
) || partial_status=$?
echo "test13_partial_set_rejected_cleanly=$([[ $partial_status -ne 0 && ! -e "$partial_dest_dir/tool1" && ! -e "$partial_dest_dir/tool2" ]] && echo 1 || echo 0)"

rm -rf "$fixture_dir" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$archive_safety_output" | grep -q 'test1_valid_archive_ok=1'; then
    pass "provision_verified_archive successfully verifies and installs valid declared binary"
else
    fail "provision_verified_archive failed on valid archive: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test2_absent_member_rejected=1'; then
    pass "provision_verified_archive fails closed when expected member is absent"
else
    fail "provision_verified_archive did not fail on absent member: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test3_rogue_exec_rejected=1'; then
    pass "provision_verified_archive refuses to fall back to unexpected rogue executable"
else
    fail "provision_verified_archive fell back to rogue executable: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test4_ambiguous_rejected=1'; then
    pass "provision_verified_archive fails closed on ambiguous duplicate member basenames"
else
    fail "provision_verified_archive silently picked ambiguous member: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test5_exact_subpath_ok=1'; then
    pass "provision_verified_archive resolves explicit relative member subpath among multiple files"
else
    fail "provision_verified_archive failed exact subpath resolution: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test6_traversal_rejected=1'; then
    pass "provision_verified_archive detects and rejects path traversal (../) before extraction"
else
    fail "provision_verified_archive accepted traversal archive: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test7_absolute_rejected=1'; then
    pass "provision_verified_archive detects and rejects absolute paths (/) before extraction"
else
    fail "provision_verified_archive accepted absolute path archive: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test8_symlink_escape_rejected=1'; then
    pass "provision_verified_archive detects and rejects symlinks escaping staging directory"
else
    fail "provision_verified_archive accepted escaping symlink: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test9_hardlink_ok=1'; then
    pass "provision_verified_archive safely extracts valid hardlinked archive members"
else
    fail "provision_verified_archive failed on safe hardlink member: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test10_corrupt_listing_rejected=1'; then
    pass "provision_verified_archive fails closed on archive listing / inspection command errors"
else
    fail "provision_verified_archive did not fail on corrupt listing: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test11_missing_tool_rejected=1'; then
    pass "provision_verified_archive fails closed when required inspection tool is missing"
else
    fail "provision_verified_archive did not fail on missing inspection tool: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test12_multi_all_present_ok=1'; then
    pass "provision_verified_archive validates and installs all members of a multi-binary set"
else
    fail "provision_verified_archive failed on multi-binary set: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test13_partial_set_rejected_cleanly=1'; then
    pass "provision_verified_archive fails closed before installation if any member of a multi-binary set is missing"
else
    fail "provision_verified_archive partially installed incomplete multi-binary set: $archive_safety_output"
fi
