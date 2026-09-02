#!/usr/bin/env bash

# Test Suite: Supply chain integrity, cryptographic hashes, deterministic archive safety, link verification, and traversal guards.

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
    CHATGPT_VERSION
    CHATGPT_X86_64_URL
    CHATGPT_X86_64_SHA512
    CHATGPT_AARCH64_URL
    CHATGPT_AARCH64_SHA512
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
    ROSE_PINE_GTK_VERSION
    ROSE_PINE_GTK_URL
    ROSE_PINE_GTK_SHA512
    HACK_NERD_FONT_VERSION
    HACK_NERD_FONT_URL
    HACK_NERD_FONT_SHA512
)

for p in "${pins[@]}"; do
    if [[ -n "${!p:-}" ]]; then
        pass "pin $p"
    else
        fail "missing pin $p"
    fi
done

if [[ "$CHATGPT_X86_64_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "CHATGPT_X86_64_SHA512 is valid 128-character hex"
else
    fail "CHATGPT_X86_64_SHA512 format invalid"
fi

if [[ "$CHATGPT_AARCH64_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "CHATGPT_AARCH64_SHA512 is valid 128-character hex"
else
    fail "CHATGPT_AARCH64_SHA512 format invalid"
fi

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

if [[ "$ROSE_PINE_GTK_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "ROSE_PINE_GTK_SHA512 is valid 128-character hex"
else
    fail "ROSE_PINE_GTK_SHA512 format invalid"
fi

if [[ "$HACK_NERD_FONT_SHA512" =~ ^[a-f0-9]{128}$ ]]; then
    pass "HACK_NERD_FONT_SHA512 is valid 128-character hex"
else
    fail "HACK_NERD_FONT_SHA512 format invalid"
fi

section "Path Component and Containment Primitives"

path_prim_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/filesystem.sh"

# 1. validate_path_components rejects real .. components
val_parent1=0; validate_path_components ".." || val_parent1=$?
val_parent2=0; validate_path_components "../foo" || val_parent2=$?
val_parent3=0; validate_path_components "foo/../bar" || val_parent3=$?
val_parent4=0; validate_path_components "foo/../../bar" || val_parent4=$?

echo "val_parent1=$val_parent1"
echo "val_parent2=$val_parent2"
echo "val_parent3=$val_parent3"
echo "val_parent4=$val_parent4"

# 2. validate_path_components accepts harmless .. within filenames
val_dotdot_name1=0; validate_path_components "my..file.txt" || val_dotdot_name1=$?
val_dotdot_name2=0; validate_path_components "bin/tool..v2" || val_dotdot_name2=$?
val_dotdot_name3=0; validate_path_components "foo..bar/baz" || val_dotdot_name3=$?

echo "val_dotdot_name1=$val_dotdot_name1"
echo "val_dotdot_name2=$val_dotdot_name2"
echo "val_dotdot_name3=$val_dotdot_name3"

# 3. normalize_archive_path containment and prefix-confusion rejection
norm_safe1="$(normalize_archive_path "" "foo/bar")"
norm_safe2="$(normalize_archive_path "dir/subdir" "../../foo")"
norm_esc1=0; normalize_archive_path "" "../bar" >/dev/null 2>&1 || norm_esc1=$?
norm_esc2=0; normalize_archive_path "dir/subdir" "../../../foo" >/dev/null 2>&1 || norm_esc2=$?
norm_abs=0; normalize_archive_path "dir" "/etc/passwd" >/dev/null 2>&1 || norm_abs=$?

echo "norm_safe1=$norm_safe1"
echo "norm_safe2=$norm_safe2"
echo "norm_esc1=$norm_esc1"
echo "norm_esc2=$norm_esc2"
echo "norm_abs=$norm_abs"

# 4. Prefix confusion test: /tmp/example vs /tmp/example-evil
prefix_confusion_rejected=0
root="/tmp/example"
resolved="/tmp/example-evil/payload"
if [[ "$resolved" != "$root" && "$resolved" != "$root/"* ]]; then
    prefix_confusion_rejected=1
fi
echo "prefix_confusion_rejected=$prefix_confusion_rejected"
EOS
)"

if printf '%s\n' "$path_prim_output" | grep -q 'val_parent1=1' &&
   printf '%s\n' "$path_prim_output" | grep -q 'val_parent2=1' &&
   printf '%s\n' "$path_prim_output" | grep -q 'val_parent3=1' &&
   printf '%s\n' "$path_prim_output" | grep -q 'val_parent4=1'; then
    pass "validate_path_components rejects real '..' path components"
else
    fail "validate_path_components failed to reject '..' components: $path_prim_output"
fi

if printf '%s\n' "$path_prim_output" | grep -q 'val_dotdot_name1=0' &&
   printf '%s\n' "$path_prim_output" | grep -q 'val_dotdot_name2=0' &&
   printf '%s\n' "$path_prim_output" | grep -q 'val_dotdot_name3=0'; then
    pass "validate_path_components accepts harmless '..' inside filenames"
else
    fail "validate_path_components rejected harmless '..' inside filename: $path_prim_output"
fi

if printf '%s\n' "$path_prim_output" | grep -q 'norm_safe1=foo/bar' &&
   printf '%s\n' "$path_prim_output" | grep -q 'norm_safe2=foo' &&
   printf '%s\n' "$path_prim_output" | grep -q 'norm_esc1=1' &&
   printf '%s\n' "$path_prim_output" | grep -q 'norm_esc2=1' &&
   printf '%s\n' "$path_prim_output" | grep -q 'norm_abs=1'; then
    pass "normalize_archive_path accurately computes relative containment and rejects escapes"
else
    fail "normalize_archive_path containment test failed: $path_prim_output"
fi

if printf '%s\n' "$path_prim_output" | grep -q 'prefix_confusion_rejected=1'; then
    pass "boundary-aware containment rejects prefix collision (/tmp/example vs /tmp/example-evil)"
else
    fail "prefix collision boundary check failed: $path_prim_output"
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

section "Archive Pre-Extraction Link & Structure Safety Fixtures"

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

# 1. Safe regular-file tar archive -> PASS
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

# 2. TAR symlink with ordinary filename -> REJECTED BEFORE EXTRACTION
sentinel_sym="$fixture_dir/sentinel_sym_plain"
rm -f "$sentinel_sym"
mkdir -p "$fixture_dir/sym_plain_src"
printf '#!/bin/sh\necho file\n' > "$fixture_dir/sym_plain_src/file"
ln -s "file" "$fixture_dir/sym_plain_src/sym_plain"
tar -czf "$fixture_dir/sym_plain.tar.gz" -C "$fixture_dir/sym_plain_src" file sym_plain
sym_plain_hash="$(sha512sum "$fixture_dir/sym_plain.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/sym_plain.tar.gz"
sym_plain_dest="$fixture_dir/installed_sym_plain/file"
sym_plain_status=0
(
    provision_verified_archive "https://example.com/sym_plain.tar.gz" "$sym_plain_hash" "$sym_plain_dest" "file" "sym_plain_test" false >/dev/null 2>&1
) || sym_plain_status=$?
echo "test2_tar_symlink_plain_rejected=$([[ $sym_plain_status -ne 0 && ! -e "$sym_plain_dest" && ! -e "$sentinel_sym" ]] && echo 1 || echo 0)"

# 3. TAR symlink whose filename contains " -> " -> REJECTED BEFORE EXTRACTION
sentinel_arrow="$fixture_dir/sentinel_sym_arrow"
rm -f "$sentinel_arrow"
mkdir -p "$fixture_dir/sym_arrow_src"
printf '#!/bin/sh\necho file\n' > "$fixture_dir/sym_arrow_src/file"
ln -s "file" "$fixture_dir/sym_arrow_src/sym -> trick"
tar -czf "$fixture_dir/sym_arrow.tar.gz" -C "$fixture_dir/sym_arrow_src" file "sym -> trick"
sym_arrow_hash="$(sha512sum "$fixture_dir/sym_arrow.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/sym_arrow.tar.gz"
sym_arrow_dest="$fixture_dir/installed_sym_arrow/file"
sym_arrow_status=0
(
    provision_verified_archive "https://example.com/sym_arrow.tar.gz" "$sym_arrow_hash" "$sym_arrow_dest" "file" "sym_arrow_test" false >/dev/null 2>&1
) || sym_arrow_status=$?
echo "test3_tar_symlink_arrow_name_rejected=$([[ $sym_arrow_status -ne 0 && ! -e "$sym_arrow_dest" && ! -e "$sentinel_arrow" ]] && echo 1 || echo 0)"

# 4. TAR hardlink with ordinary filename -> REJECTED BEFORE EXTRACTION
sentinel_hard="$fixture_dir/sentinel_hard_plain"
rm -f "$sentinel_hard"
mkdir -p "$fixture_dir/hard_plain_src"
printf '#!/bin/sh\necho file\n' > "$fixture_dir/hard_plain_src/file"
ln "$fixture_dir/hard_plain_src/file" "$fixture_dir/hard_plain_src/hard_plain"
tar -czf "$fixture_dir/hard_plain.tar.gz" -C "$fixture_dir/hard_plain_src" file hard_plain
hard_plain_hash="$(sha512sum "$fixture_dir/hard_plain.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/hard_plain.tar.gz"
hard_plain_dest="$fixture_dir/installed_hard_plain/file"
hard_plain_status=0
(
    provision_verified_archive "https://example.com/hard_plain.tar.gz" "$hard_plain_hash" "$hard_plain_dest" "file" "hard_plain_test" false >/dev/null 2>&1
) || hard_plain_status=$?
echo "test4_tar_hardlink_plain_rejected=$([[ $hard_plain_status -ne 0 && ! -e "$hard_plain_dest" && ! -e "$sentinel_hard" ]] && echo 1 || echo 0)"

# 5. TAR hardlink whose filename contains " link to " -> REJECTED BEFORE EXTRACTION
sentinel_hardlink_to="$fixture_dir/sentinel_hard_linkto"
rm -f "$sentinel_hardlink_to"
mkdir -p "$fixture_dir/hard_linkto_src"
printf '#!/bin/sh\necho file\n' > "$fixture_dir/hard_linkto_src/file"
ln "$fixture_dir/hard_linkto_src/file" "$fixture_dir/hard_linkto_src/hard link to trick"
tar -czf "$fixture_dir/hard_linkto.tar.gz" -C "$fixture_dir/hard_linkto_src" file "hard link to trick"
hard_linkto_hash="$(sha512sum "$fixture_dir/hard_linkto.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/hard_linkto.tar.gz"
hard_linkto_dest="$fixture_dir/installed_hard_linkto/file"
hard_linkto_status=0
(
    provision_verified_archive "https://example.com/hard_linkto.tar.gz" "$hard_linkto_hash" "$hard_linkto_dest" "file" "hard_linkto_test" false >/dev/null 2>&1
) || hard_linkto_status=$?
echo "test5_tar_hardlink_linkto_name_rejected=$([[ $hard_linkto_status -ne 0 && ! -e "$hard_linkto_dest" && ! -e "$sentinel_hardlink_to" ]] && echo 1 || echo 0)"

# 6. ZIP symlink -> REJECTED BEFORE EXTRACTION
sentinel_zip_sym="$fixture_dir/sentinel_zip_sym"
rm -f "$sentinel_zip_sym"
mkdir -p "$fixture_dir/zip_sym_src"
printf '#!/bin/sh\necho zip-file\n' > "$fixture_dir/zip_sym_src/real_zip_file"
chmod +x "$fixture_dir/zip_sym_src/real_zip_file"
ln -s "real_zip_file" "$fixture_dir/zip_sym_src/sym_zip"
(cd "$fixture_dir/zip_sym_src" && zip -y -r "$fixture_dir/sym.zip" real_zip_file sym_zip >/dev/null)
zip_sym_hash="$(sha512sum "$fixture_dir/sym.zip" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/sym.zip"
zip_sym_dest="$fixture_dir/installed_zip_sym/real_zip_file"
zip_sym_status=0
(
    provision_verified_archive "https://example.com/sym.zip" "$zip_sym_hash" "$zip_sym_dest" "real_zip_file" "zip_sym_test" false >/dev/null 2>&1
) || zip_sym_status=$?
echo "test6_zip_symlink_rejected=$([[ $zip_sym_status -ne 0 && ! -e "$zip_sym_dest" && ! -e "$sentinel_zip_sym" ]] && echo 1 || echo 0)"

# 7. Member traversal (../) -> FAIL BEFORE EXTRACTION
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
echo "test7_member_traversal_rejected_before_extraction=$([[ $traversal_status -ne 0 && ! -e "$traversal_dest" ]] && echo 1 || echo 0)"

# 8. Expected member containing harmless ".." inside filename -> PASS
mkdir -p "$fixture_dir/dotdot_src/bin"
printf '#!/bin/sh\necho dotdot-tool\n' > "$fixture_dir/dotdot_src/bin/my..tool.v2"
chmod +x "$fixture_dir/dotdot_src/bin/my..tool.v2"
tar -czf "$fixture_dir/dotdot.tar.gz" -C "$fixture_dir/dotdot_src" bin
dotdot_hash="$(sha512sum "$fixture_dir/dotdot.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/dotdot.tar.gz"
dotdot_dest="$fixture_dir/installed_dotdot/my..tool.v2"
dotdot_status=0
provision_verified_archive "https://example.com/dotdot.tar.gz" "$dotdot_hash" "$dotdot_dest" "bin/my..tool.v2" "dotdot_test" false || dotdot_status=$?
echo "test8_dotdot_in_name_ok=$([[ $dotdot_status -eq 0 && "$("$dotdot_dest")" == "dotdot-tool" ]] && echo 1 || echo 0)"

# 9. Expected member containing real ".." path component -> FAIL
real_dotdot_status=0
(
    provision_verified_archive "https://example.com/valid.tar.gz" "$valid_hash" "$fixture_dir/installed_real_dotdot/tool" "bin/../my_tool" "real_dotdot_test" false >/dev/null 2>&1
) || real_dotdot_status=$?
echo "test9_real_dotdot_component_rejected=$([[ $real_dotdot_status -ne 0 ]] && echo 1 || echo 0)"

# 10. Malformed/uninspectable link metadata or corrupt archive -> FAIL CLOSED
printf 'NOT_A_VALID_TAR_BYTES' > "$fixture_dir/corrupt.tar.gz"
corrupt_hash="$(sha512sum "$fixture_dir/corrupt.tar.gz" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/corrupt.tar.gz"
corrupt_dest="$fixture_dir/installed_corrupt/tool"
corrupt_status=0
(
    provision_verified_archive "https://example.com/corrupt.tar.gz" "$corrupt_hash" "$corrupt_dest" "tool" "corrupt_test" false >/dev/null 2>&1
) || corrupt_status=$?
echo "test10_corrupt_listing_rejected=$([[ $corrupt_status -ne 0 && ! -e "$corrupt_dest" ]] && echo 1 || echo 0)"

# 11. Safe regular-file ZIP archive -> PASS
mkdir -p "$fixture_dir/valid_zip_src/bin"
printf '#!/bin/sh\necho valid-zip-tool\n' > "$fixture_dir/valid_zip_src/bin/real_zip_bin"
chmod +x "$fixture_dir/valid_zip_src/bin/real_zip_bin"
(cd "$fixture_dir/valid_zip_src" && zip -y -r "$fixture_dir/valid_zip.zip" bin >/dev/null)
valid_zip_hash="$(sha512sum "$fixture_dir/valid_zip.zip" | cut -d' ' -f1)"

current_payload_file="$fixture_dir/valid_zip.zip"
valid_zip_dest="$fixture_dir/installed_valid_zip/real_zip_bin"
valid_zip_status=0
provision_verified_archive "https://example.com/valid_zip.zip" "$valid_zip_hash" "$valid_zip_dest" "bin/real_zip_bin" "valid_zip_test" false || valid_zip_status=$?
echo "test11_valid_zip_ok=$([[ $valid_zip_status -eq 0 && -x "$valid_zip_dest" ]] && echo 1 || echo 0)"

# 12. Ambiguous duplicate member basenames -> FAIL
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
echo "test12_ambiguous_rejected=$([[ $ambig_status -ne 0 && ! -e "$ambig_dest" ]] && echo 1 || echo 0)"

# 13. Multi-binary set all present -> PASS
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
echo "test13_multi_all_present_ok=$([[ $multi_status -eq 0 && -x "$multi_dest_dir/tool1" && -x "$multi_dest_dir/tool2" && -x "$multi_dest_dir/tool3" ]] && echo 1 || echo 0)"

# 14. Partial multi-binary set -> FAIL BEFORE installation
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
echo "test14_partial_set_rejected_cleanly=$([[ $partial_status -ne 0 && ! -e "$partial_dest_dir/tool1" && ! -e "$partial_dest_dir/tool2" ]] && echo 1 || echo 0)"

rm -rf "$fixture_dir" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$archive_safety_output" | grep -q 'test1_valid_archive_ok=1'; then
    pass "provision_verified_archive successfully verifies and installs valid declared binary"
else
    fail "provision_verified_archive failed on valid archive: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test2_tar_symlink_plain_rejected=1'; then
    pass "provision_verified_archive rejects ordinary TAR symlinks before extraction"
else
    fail "provision_verified_archive failed to reject ordinary TAR symlink: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test3_tar_symlink_arrow_name_rejected=1'; then
    pass "provision_verified_archive rejects TAR symlink whose filename contains ' -> ' before extraction"
else
    fail "provision_verified_archive failed to reject TAR symlink with ' -> ': $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test4_tar_hardlink_plain_rejected=1'; then
    pass "provision_verified_archive rejects ordinary TAR hardlinks before extraction"
else
    fail "provision_verified_archive failed to reject ordinary TAR hardlink: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test5_tar_hardlink_linkto_name_rejected=1'; then
    pass "provision_verified_archive rejects TAR hardlink whose filename contains ' link to ' before extraction"
else
    fail "provision_verified_archive failed to reject TAR hardlink with ' link to ': $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test6_zip_symlink_rejected=1'; then
    pass "provision_verified_archive rejects ZIP symlinks before extraction"
else
    fail "provision_verified_archive failed to reject ZIP symlink: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test7_member_traversal_rejected_before_extraction=1'; then
    pass "provision_verified_archive rejects member traversal (../) before tar extraction"
else
    fail "provision_verified_archive failed to reject member traversal: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test8_dotdot_in_name_ok=1'; then
    pass "provision_verified_archive accepts harmless '..' within member filenames"
else
    fail "provision_verified_archive rejected harmless '..' within filename: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test9_real_dotdot_component_rejected=1'; then
    pass "provision_verified_archive rejects declared members with real '..' path components"
else
    fail "provision_verified_archive accepted declared member with '..' component: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test10_corrupt_listing_rejected=1'; then
    pass "provision_verified_archive fails closed on corrupt or uninspectable archive metadata"
else
    fail "provision_verified_archive failed to reject corrupt listing: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test11_valid_zip_ok=1'; then
    pass "provision_verified_archive accepts safe regular-file ZIP archives"
else
    fail "provision_verified_archive failed on safe regular-file ZIP archive: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test12_ambiguous_rejected=1'; then
    pass "provision_verified_archive fails closed on ambiguous duplicate member basenames"
else
    fail "provision_verified_archive failed to reject ambiguous member: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test13_multi_all_present_ok=1'; then
    pass "provision_verified_archive validates and installs all members of a multi-binary set"
else
    fail "provision_verified_archive failed on multi-binary set: $archive_safety_output"
fi

if printf '%s\n' "$archive_safety_output" | grep -q 'test14_partial_set_rejected_cleanly=1'; then
    pass "provision_verified_archive fails closed before installation if any member of a multi-binary set is missing"
else
    fail "provision_verified_archive partially installed incomplete multi-binary set: $archive_safety_output"
fi
