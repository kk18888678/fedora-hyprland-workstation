#!/usr/bin/env bash

# Test Suite: Workstation applications, browsers, editor configurations, and nix configuration preservation.

section "Neovim Default Configuration"

expected_nvim_content=$'vim.opt.number = true\nvim.opt.relativenumber = true\nvim.opt.ignorecase = true\nvim.opt.smartcase = true\nvim.opt.clipboard = \'unnamedplus\'\nvim.opt.undofile = true\nvim.opt.scrolloff = 8'

actual_nvim_content="$(cat "$ROOT/dotfiles/nvim/init.lua" 2>/dev/null || true)"
actual_nvim_content_trimmed="$(printf '%s' "$actual_nvim_content" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [[ "$actual_nvim_content_trimmed" == "$expected_nvim_content" ]]; then
    pass "Neovim init.lua content matches exact required baseline"
else
    fail "Neovim init.lua content differs from required baseline"
fi

if grep -q "deploy_nvim_config" "$ROOT/modules/shell.sh"; then
    pass "shell.sh defines and invokes deploy_nvim_config"
else
    fail "shell.sh missing deploy_nvim_config"
fi

if grep -q "nvim/init.lua" "$ROOT/modules/validation.sh"; then
    pass "validation.sh validates Neovim config file"
else
    fail "validation.sh does not validate Neovim config"
fi

section "Ulaa Browser Flatpak Integration"

if grep -q "com.ulaa.Ulaa" "$ROOT/modules/flatpak.sh"; then
    pass "flatpak.sh targets Flathub app ID com.ulaa.Ulaa"
else
    fail "flatpak.sh missing Flathub app ID com.ulaa.Ulaa"
fi

if grep -q "com.ulaa.Ulaa" "$ROOT/modules/validation.sh"; then
    pass "validation.sh checks com.ulaa.Ulaa Flatpak"
else
    fail "validation.sh missing com.ulaa.Ulaa check"
fi

section "ChatGPT Official Bootstrap RPM Integration"

if grep -q "CHATGPT_X86_64_URL" "$ROOT/modules/applications.sh" &&
   grep -q "CHATGPT_X86_64_SHA512" "$ROOT/modules/applications.sh"; then
    pass "applications.sh uses pinned OpenAI bootstrap RPM URL and SHA-512"
else
    fail "applications.sh missing pinned OpenAI bootstrap RPM metadata"
fi

if grep -q "chatgpt.repo" "$ROOT/modules/applications.sh"; then
    fail "applications.sh contains handcrafted chatgpt.repo instead of delegating to official RPM bootstrap"
else
    pass "applications.sh delegates repository configuration to official OpenAI bootstrap RPM"
fi

chatgpt_behavior_output="$(
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
source "$SCRIPT_DIR/modules/repositories.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

# 1. Disabled profile performs no mutations
CHATGPT=false
download_called=0
install_called=0
curl() { download_called=1; }
sudo() { install_called=1; }
install_chatgpt
echo "disabled_no_mutation=$([[ $download_called -eq 0 && $install_called -eq 0 ]] && echo 1 || echo 0)"

# 2. Already-installed ChatGPT is completely idempotent
CHATGPT=true
package_installed() { [[ "$1" == "chatgpt" ]]; }
download_called=0
install_called=0
install_chatgpt
echo "idempotent_when_installed=$([[ $download_called -eq 0 && $install_called -eq 0 ]] && echo 1 || echo 0)"

# 3. Checksum mismatch fails before DNF is ever called
package_installed() { return 1; }
dnf_called_on_mismatch=0
sudo() { dnf_called_on_mismatch=1; }
download_and_verify_artifact() {
    # Simulate checksum mismatch
    return 1
}
install_chatgpt
echo "mismatch_dnf_prevented=$([[ $dnf_called_on_mismatch -eq 0 ]] && echo 1 || echo 0)"
echo "mismatch_deferred=$(grep -c 'Failed to download or verify official OpenAI ChatGPT RPM checksum' <(printf '%s\n' "${INSTALL_DEFERRED[@]}") || true)"

# 4. Valid checksum executes DNF installation and succeeds
package_installed() { return 1; }
dnf_called_on_valid=0
download_and_verify_artifact() {
    local out="$3"
    touch "$out"
    return 0
}
run_with_retry() {
    shift
    "$@"
}
run_with_timeout() {
    shift 2
    "$@"
}
sudo() {
    dnf_called_on_valid=1
    if [[ "$*" =~ dnf\ install\ -y ]]; then
        package_installed() { return 0; }
    fi
}
converge_chatgpt_gpg_key() { return 0; }
install_chatgpt
echo "valid_dnf_invoked=$([[ $dnf_called_on_valid -eq 1 ]] && echo 1 || echo 0)"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'disabled_no_mutation=1'; then
    pass "install_chatgpt performs no mutations when CHATGPT=false"
else
    fail "install_chatgpt mutated system when CHATGPT=false: $chatgpt_behavior_output"
fi

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'idempotent_when_installed=1'; then
    pass "install_chatgpt is idempotent and avoids redundant downloads when already installed"
else
    fail "install_chatgpt attempted redundant installation when already installed: $chatgpt_behavior_output"
fi

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'mismatch_dnf_prevented=1' &&
   printf '%s\n' "$chatgpt_behavior_output" | grep -q 'mismatch_deferred=1'; then
    pass "install_chatgpt prevents DNF invocation and records deferred on checksum mismatch"
else
    fail "install_chatgpt did not isolate checksum mismatch from DNF: $chatgpt_behavior_output"
fi

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'valid_dnf_invoked=1'; then
    pass "install_chatgpt verifies checksum before invoking DNF for official RPM installation"
else
    fail "install_chatgpt failed valid bootstrap execution: $chatgpt_behavior_output"
fi

section "ChatGPT Repository GPG Key Convergence"

chatgpt_gpg_test_output="$(
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
source "$SCRIPT_DIR/modules/applications.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/repositories.sh"

EXPECTED_FP="3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4"

mock_repos="$(mktemp -d)"
OVERRIDE_YUM_REPOS_DIR="$mock_repos"
empty_pki="$(mktemp -d)"
OVERRIDE_RPM_GPG_DIR="$empty_pki"

# 1. Full-fingerprint RPM-keyring identity verification (is_rpm_gpg_key_imported)
# Case A: Exact full fingerprint matching -> 0 (trusted)
rpm() {
    if [[ "$*" =~ --qf\ %\{DESCRIPTION\} ]]; then
        cat <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----
mQINBGeGrzsBEAC4UV5Ij9oz6h6abEKIRoiezttFfnLhwOAfE9tWtfIFMRmhY91u
-----END PGP PUBLIC KEY BLOCK-----
EOF
        return 0
    fi
    command rpm "$@"
}
gpg() {
    cat <<EOF
pub:u:4096:1:1234567890:1234567890::u:::scESC::::::23::
fpr:::::::::${EXPECTED_FP}:
uid:u::::1234567890::1234567890::Codex Linux Repository:::
EOF
}
full_match_res=0
is_rpm_gpg_key_imported "$EXPECTED_FP" || full_match_res=$?
echo "full_match_status=$full_match_res"

# Case B: Same final 8 hex digits but different full fingerprint -> 1 (NOT trusted)
gpg() {
    cat <<EOF
pub:u:4096:1:1234567890:1234567890::u:::scESC::::::23::
fpr:::::::::111122223333444455556666777788886C4660E4:
uid:u::::1234567890::1234567890::Colliding Suffix Key:::
EOF
}
suffix_mismatch_res=0
is_rpm_gpg_key_imported "$EXPECTED_FP" || suffix_mismatch_res=$?
echo "suffix_mismatch_status=$suffix_mismatch_res"

# Case C: Unrelated installed key -> 1 (NOT trusted)
gpg() {
    cat <<EOF
pub:u:4096:1:1234567890:1234567890::u:::scESC::::::23::
fpr:::::::::36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6:
uid:u::::1234567890::1234567890::Fedora Linux Primary Key:::
EOF
}
unrelated_key_res=0
is_rpm_gpg_key_imported "$EXPECTED_FP" || unrelated_key_res=$?
echo "unrelated_key_status=$unrelated_key_res"

# Case D: Malformed / unparseable key material in RPM keyring -> 1 (NOT trusted)
gpg() {
    return 1
}
malformed_key_res=0
is_rpm_gpg_key_imported "$EXPECTED_FP" || malformed_key_res=$?
echo "malformed_key_status=$malformed_key_res"

# Case E: Absent key in RPM database -> 1 (NOT trusted)
rpm() {
    if [[ "$*" =~ --qf\ %\{DESCRIPTION\} ]]; then
        return 0 # empty output
    fi
    command rpm "$@"
}
absent_key_res=0
is_rpm_gpg_key_imported "$EXPECTED_FP" || absent_key_res=$?
echo "absent_key_status=$absent_key_res"

# Unset test gpg/rpm mocks before convergence tests
unset -f gpg rpm

# 2. Unconfigured repository: absence of key is safe no-op (status 0, no import)
package_installed() { return 1; }
rpm_import_called=0
sudo() {
    if [[ "$*" =~ rpm\ --import ]]; then rpm_import_called=1; fi
}
unconfigured_res=0
converge_chatgpt_gpg_key || unconfigured_res=$?
echo "unconfigured_status=$unconfigured_res"
echo "unconfigured_imported=$rpm_import_called"

# Now configure the repository (e.g. chatgpt.repo exists)
touch "$mock_repos/chatgpt-test.repo"

# 3. Configured repository + missing key file -> FAIL CLOSED (status 1)
missing_key_res=0
converge_chatgpt_gpg_key || missing_key_res=$?
echo "missing_key_status=$missing_key_res"

# 4. Configured repository + missing gpg verifier in PATH sandbox -> FAIL CLOSED (status 1)
staging_pki="$(mktemp -d)"
OVERRIDE_RPM_GPG_DIR="$staging_pki"
key_file="$staging_pki/RPM-GPG-KEY-chatgpt-${EXPECTED_FP}.asc"
touch "$key_file"

# Create PATH sandbox excluding gpg binaries
gpg_sandbox_bin="$(mktemp -d)"
for bin_candidate in /usr/bin/* /bin/*; do
    [[ -x "$bin_candidate" && ! -d "$bin_candidate" ]] || continue
    bname="$(basename "$bin_candidate")"
    if [[ "$bname" != "gpg"* ]]; then
        ln -s "$bin_candidate" "$gpg_sandbox_bin/$bname" 2>/dev/null || true
    fi
done

missing_gpg_res=0
(
    export PATH="$gpg_sandbox_bin"
    converge_chatgpt_gpg_key || exit $?
) || missing_gpg_res=$?
echo "missing_gpg_status=$missing_gpg_res"
rm -rf "$gpg_sandbox_bin"

# 5. Configured repository + wrong fingerprint -> FAIL CLOSED (status 1, no import)
wrong_pki="$(mktemp -d)"
OVERRIDE_RPM_GPG_DIR="$wrong_pki"
wrong_key_file="$wrong_pki/RPM-GPG-KEY-chatgpt-${EXPECTED_FP}.asc"
touch "$wrong_key_file"
gpg() {
    cat <<EOF
pub:u:4096:1:1234567890:1234567890::u:::scESC::::::23::
fpr:::::::::1111222233334444555566667777888899990000:
uid:u::::1234567890::1234567890::Malicious Untrusted Key:::
EOF
}
rpm_import_called=0
wrong_res=0
converge_chatgpt_gpg_key || wrong_res=$?
echo "wrong_key_status=$wrong_res"
echo "wrong_key_imported=$rpm_import_called"

# 6. Configured repository + import failure -> FAIL CLOSED (status 1)
OVERRIDE_RPM_GPG_DIR="$staging_pki"
gpg() {
    cat <<EOF
pub:u:4096:1:1234567890:1234567890::u:::scESC::::::23::
fpr:::::::::${EXPECTED_FP}:
uid:u::::1234567890::1234567890::Codex Linux Repository:::
EOF
}
is_rpm_gpg_key_imported() { return 1; }
sudo() {
    if [[ "$*" =~ rpm\ --import ]]; then return 1; fi
    command sudo "$@"
}
import_fail_res=0
converge_chatgpt_gpg_key || import_fail_res=$?
echo "import_fail_status=$import_fail_res"

# 7. First successful convergence -> verifies and imports into RPM keyring
rpm_import_called=0
imported_file=""
sudo() {
    if [[ "$1" == "rpm" && "$2" == "--import" ]]; then
        rpm_import_called=1
        imported_file="$3"
        return 0
    fi
}
is_rpm_gpg_key_imported() { return 1; }
valid_res=0
converge_chatgpt_gpg_key || valid_res=$?
echo "valid_key_status=$valid_res"
echo "valid_key_imported=$rpm_import_called"
echo "valid_key_target=$([[ "$imported_file" == "$key_file" ]] && echo 1 || echo 0)"

# 8. Already-converged second invocation -> performs NO import and returns 0
is_rpm_gpg_key_imported() { return 0; }
rpm_import_called=0
second_res=0
converge_chatgpt_gpg_key || second_res=$?
echo "second_run_status=$second_res"
echo "second_run_imported=$rpm_import_called"

# 9. configure_repositories skips global metadata refresh when ChatGPT GPG convergence fails
INSTALL_REQUIRED_FAILURES=()
makecache_called=0
install_dnf_packages() { return 0; }
enable_copr() { return 0; }
dnf_makecache() { makecache_called=1; return 0; }
install_rpmfusion() { return 0; }
validate_repository_configuration() { return 0; }
converge_chatgpt_gpg_key() { return 1; } # simulate convergence failure

repo_stage_res=0
configure_repositories || repo_stage_res=$?
echo "repo_stage_res=$repo_stage_res"
echo "repo_stage_makecache_called=$makecache_called"
echo "repo_stage_has_required_fail=${#INSTALL_REQUIRED_FAILURES[@]}"

# 10. configure_repositories ordering: converge_chatgpt_gpg_key runs FIRST before package operations and metadata refresh
call_order=()
converge_chatgpt_gpg_key() { call_order+=("converge_chatgpt"); return 0; }
install_dnf_packages() { call_order+=("install_dnf_packages"); return 0; }
enable_copr() { call_order+=("enable_copr"); return 0; }
install_rpmfusion() { call_order+=("install_rpmfusion"); return 0; }
dnf_makecache() { call_order+=("dnf_makecache"); return 0; }
validate_repository_configuration() { call_order+=("validate_repos"); return 0; }

configure_repositories
echo "first_operation=${call_order[0]:-none}"
echo "full_call_sequence=${call_order[*]}"

# 11. prepare_system does not perform premature dnf_makecache
prep_makecache_called=0
dnf_makecache() { prep_makecache_called=1; return 0; }
validate_profile() { return 0; }
validate_fedora() { return 0; }
validate_target_user() { return 0; }
require_command() { return 0; }
prepare_system
echo "prep_makecache_called=$prep_makecache_called"

rm -rf "$mock_repos" "$empty_pki" "$staging_pki" "$wrong_pki" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'full_match_status=0' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'suffix_mismatch_status=1' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'unrelated_key_status=1' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'malformed_key_status=1' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'absent_key_status=1'; then
    pass "is_rpm_gpg_key_imported validates exact full fingerprint from OpenPGP blocks and rejects mismatches/malformed data"
else
    fail "is_rpm_gpg_key_imported full-fingerprint test failed: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'unconfigured_status=0' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'unconfigured_imported=0'; then
    pass "converge_chatgpt_gpg_key is safe no-op when ChatGPT repository is not configured"
else
    fail "converge_chatgpt_gpg_key failed unconfigured repo no-op: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'missing_key_status=1'; then
    pass "converge_chatgpt_gpg_key fails closed when configured repo is missing GPG key file"
else
    fail "converge_chatgpt_gpg_key did not fail on missing key file: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'missing_gpg_status=1'; then
    pass "converge_chatgpt_gpg_key fails closed when gpg verifier command is genuinely unavailable"
else
    fail "converge_chatgpt_gpg_key did not fail on missing gpg: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'wrong_key_status=1' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'wrong_key_imported=0'; then
    pass "converge_chatgpt_gpg_key rejects key with mismatched fingerprint without importing"
else
    fail "converge_chatgpt_gpg_key did not reject wrong fingerprint: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'import_fail_status=1'; then
    pass "converge_chatgpt_gpg_key fails closed when rpm --import fails"
else
    fail "converge_chatgpt_gpg_key did not fail on import error: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'valid_key_status=0' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'valid_key_imported=1' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'valid_key_target=1'; then
    pass "converge_chatgpt_gpg_key imports verified official OpenAI GPG key on first run"
else
    fail "converge_chatgpt_gpg_key failed valid key import: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'second_run_status=0' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'second_run_imported=0'; then
    pass "converge_chatgpt_gpg_key avoids redundant import when key is already trusted in RPM keyring"
else
    fail "converge_chatgpt_gpg_key failed already-imported idempotency: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'repo_stage_makecache_called=0' &&
   printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'repo_stage_has_required_fail=1'; then
    pass "configure_repositories stops and skips metadata refresh when ChatGPT GPG convergence fails"
else
    fail "configure_repositories did not skip metadata refresh on GPG failure: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'first_operation=converge_chatgpt'; then
    pass "configure_repositories establishes ChatGPT GPG trust BEFORE package installations and metadata refresh"
else
    fail "configure_repositories did not run ChatGPT GPG convergence first: $chatgpt_gpg_test_output"
fi

if printf '%s\n' "$chatgpt_gpg_test_output" | grep -q 'prep_makecache_called=0'; then
    pass "prepare_system does not perform premature global DNF metadata refresh"
else
    fail "prepare_system invoked premature dnf_makecache: $chatgpt_gpg_test_output"
fi

section "Post-Bootstrap Repository Trust Gating & DNF Invariant"

post_bootstrap_gate_output="$(
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
source "$SCRIPT_DIR/modules/repositories.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

EXPECTED_FP="3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4"
mock_repos="$(mktemp -d)"
OVERRIDE_YUM_REPOS_DIR="$mock_repos"
mock_pki="$(mktemp -d)"
OVERRIDE_RPM_GPG_DIR="$mock_pki"

# 1. State 1: Clean machine - repo absent, package absent -> DNF permitted
package_installed() { return 1; }
s1_trust=0
check_repository_trust || s1_trust=$?
echo "s1_trust=$s1_trust"

# 2. State 4: Clean install -> bootstrap RPM installed -> repo created -> key convergence FAILS
# install_chatgpt must record required failure and subsequent DNF must be blocked
CHATGPT=true
CHATGPT_X86_64_URL="https://example.com/chatgpt.rpm"
CHATGPT_X86_64_SHA512="dummy"
CHATGPT_VERSION="pinned"
uname() { echo "x86_64"; }
download_and_verify_artifact() { touch "$3"; return 0; }

# Mock DNF execution in run_dnf_command
dnf_ran=0
run_with_timeout() {
    shift 2
    dnf_ran=1
    "$@"
}

# When RPM is installed, simulate it creating repo on disk
sudo() {
    if [[ "$*" =~ dnf\ install.*chatgpt\.rpm ]]; then
        touch "$mock_repos/chatgpt.repo"
        return 0
    fi
    return 0
}
is_rpm_gpg_key_imported() { return 1; }
converge_chatgpt_gpg_key() { return 1; } # simulate trust convergence failure

INSTALL_REQUIRED_FAILURES=()
INSTALL_DEFERRED=()
s4_chatgpt_rc=0
install_chatgpt || s4_chatgpt_rc=$?

echo "s4_chatgpt_rc=$s4_chatgpt_rc"
echo "s4_has_required_fail=${#INSTALL_REQUIRED_FAILURES[@]}"
echo "s4_has_deferred_fail=${#INSTALL_DEFERRED[@]}"

# Now verify subsequent DNF is blocked by check_repository_trust / run_dnf_command
s4_dnf_rc=0
dnf_ran=0
run_dnf_command 10 "install media apps" sudo dnf install -y mpv || s4_dnf_rc=$?
echo "s4_dnf_rc=$s4_dnf_rc"
echo "s4_dnf_ran=$dnf_ran"

s4_pkg_avail_rc=0
package_available "mpv" || s4_pkg_avail_rc=$?
echo "s4_pkg_avail_rc=$s4_pkg_avail_rc"

# 3. State 3: Clean install -> bootstrap RPM installed -> repo created -> key convergence SUCCEEDS
converge_chatgpt_gpg_key() { return 0; }
is_rpm_gpg_key_imported() { return 0; }
package_installed() {
    if [[ "$1" == "chatgpt" ]]; then return 0; fi
    return 1
}

s3_trust=0
check_repository_trust || s3_trust=$?
echo "s3_trust=$s3_trust"

s3_dnf_rc=0
dnf_ran=0
run_dnf_command 10 "install media apps" sudo dnf install -y mpv || s3_dnf_rc=$?
echo "s3_dnf_rc=$s3_dnf_rc"
echo "s3_dnf_ran=$dnf_ran"

# 4. State 5: Existing repo + valid trust -> idempotent and DNF permitted
is_rpm_gpg_key_imported() { return 0; }
s5_trust=0
check_repository_trust || s5_trust=$?
echo "s5_trust=$s5_trust"

# 5. State 6: Existing repo + invalid trust -> check_repository_trust fails closed
is_rpm_gpg_key_imported() { return 1; }
s6_trust=0
check_repository_trust || s6_trust=$?
echo "s6_trust=$s6_trust"

# 6. State 2 / Case A: Bootstrap failure before repo creation (e.g. checksum mismatch)
rm -f "$mock_repos/chatgpt.repo"
package_installed() { return 1; }
download_and_verify_artifact() { return 1; } # checksum mismatch
INSTALL_REQUIRED_FAILURES=()
INSTALL_DEFERRED=()
s2_chatgpt_rc=0
install_chatgpt || s2_chatgpt_rc=$?
echo "s2_chatgpt_rc=$s2_chatgpt_rc"
echo "s2_has_required_fail=${#INSTALL_REQUIRED_FAILURES[@]}"
echo "s2_has_deferred_fail=${#INSTALL_DEFERRED[@]}"
s2_trust=0
check_repository_trust || s2_trust=$?
echo "s2_trust=$s2_trust"

rm -rf "$mock_repos" "$mock_pki" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's1_trust=0' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's4_chatgpt_rc=1' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's4_has_required_fail=1' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's4_has_deferred_fail=0' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's4_dnf_rc=1' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's4_dnf_ran=0' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's4_pkg_avail_rc=2'; then
    pass "Post-bootstrap trust convergence failure records required failure and strictly blocks subsequent DNF operations"
else
    fail "Post-bootstrap trust failure did not fail closed or gate DNF: $post_bootstrap_gate_output"
fi

if printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's3_trust=0' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's3_dnf_rc=0' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's3_dnf_ran=1'; then
    pass "Successful post-bootstrap trust convergence establishes trust and permits subsequent DNF operations"
else
    fail "Successful post-bootstrap trust convergence failed: $post_bootstrap_gate_output"
fi

if printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's5_trust=0' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's6_trust=1'; then
    pass "check_repository_trust validates converged keyring state (permits trusted, rejects unconverged)"
else
    fail "check_repository_trust state evaluation failed: $post_bootstrap_gate_output"
fi

if printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's2_chatgpt_rc=0' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's2_has_required_fail=0' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's2_has_deferred_fail=1' &&
   printf '%s\n' "$post_bootstrap_gate_output" | grep -q 's2_trust=0'; then
    pass "Bootstrap download/checksum failure before repo creation correctly records deferred without blocking general DNF"
else
    fail "Pre-repo bootstrap failure handling failed: $post_bootstrap_gate_output"
fi

section "N_m3u8DL-RE Prerelease Policy"

n_m3u8dl_policy_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
MEDIA_TOOLS_DIR="$(mktemp -d)"
export MEDIA_TOOLS_DIR
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

# Mock dependencies
command_exists() { return 1; }
dovi_ran=0
provision_verified_archive() {
    if [[ "$5" == "dovi_tool" ]]; then
        dovi_ran=1
        return 0
    fi
    # If N_m3u8DL-RE is called, fail test
    if [[ "$5" == "N_m3u8DL-RE" ]]; then
        echo "ERROR: N_m3u8DL-RE beta archive was provisioned!" >&2
        return 1
    fi
    return 0
}
provision_verified_binary() { return 0; }

install_media_utilities

echo "dovi_ran=$dovi_ran"
echo "deferred_recorded=$(grep -c 'Skipping N_m3u8DL-RE' <(printf '%s\n' "${INSTALL_DEFERRED[@]}") || true)"
echo "activation_blocked=$ACTIVATION_BLOCKED"
echo "exit_code=$(installer_exit_code)"

rm -rf "$TARGET_HOME" "$MEDIA_TOOLS_DIR"
EOS
)"

if printf '%s\n' "$n_m3u8dl_policy_output" | grep -q 'dovi_ran=1' &&
   printf '%s\n' "$n_m3u8dl_policy_output" | grep -q 'deferred_recorded=1' &&
   printf '%s\n' "$n_m3u8dl_policy_output" | grep -q 'activation_blocked=0' &&
   printf '%s\n' "$n_m3u8dl_policy_output" | grep -q 'exit_code=2'; then
    pass "normal installer skips N_m3u8DL-RE beta artifact and records deferred notice without blocking activation"
else
    fail "normal installer did not handle N_m3u8DL-RE prerelease correctly: $n_m3u8dl_policy_output"
fi

section "Upstream Prerelease Classification Logic"

prerelease_check_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/check-updates.sh"

# 1. Prerelease tags rejected
p_alpha=0; is_prerelease_tag "v1.0.0-alpha" || p_alpha=$?
p_beta1=0; is_prerelease_tag "1.0.0-beta" || p_beta1=$?
p_beta2=0; is_prerelease_tag "v0.6.0-beta" || p_beta2=$?
p_rc1=0; is_prerelease_tag "v1.0.0-rc1" || p_rc1=$?
p_rc2=0; is_prerelease_tag "v1.0.0-rc.2" || p_rc2=$?
p_preview=0; is_prerelease_tag "v1.0.0-preview" || p_preview=$?
p_pre1=0; is_prerelease_tag "v1.0.0-pre" || p_pre1=$?
p_pre2=0; is_prerelease_tag "v1.0.0-pre1" || p_pre2=$?
p_dev=0; is_prerelease_tag "v1.0.0-dev" || p_dev=$?
p_nightly=0; is_prerelease_tag "v1.0.0-nightly" || p_nightly=$?
p_snapshot=0; is_prerelease_tag "v1.0.0-snapshot" || p_snapshot=$?

# 2. Standard stable versions accepted
s_v1=0; is_prerelease_tag "v1.0.0" && s_v1=1 || true
s_v2=0; is_prerelease_tag "2.3.3" && s_v2=1 || true
s_v3=0; is_prerelease_tag "v0.96.6" && s_v3=1 || true
s_v4=0; is_prerelease_tag "v3.9.3" && s_v4=1 || true
s_v5=0; is_prerelease_tag "1.6.0-641" && s_v5=1 || true

# 3. Regression test: words containing 'pre' or 'dev' as substring of unrelated words are NOT false positives
r_precise=0; is_prerelease_tag "v1.0.0-precise" && r_precise=1 || true
r_compress=0; is_prerelease_tag "v2.0-compress" && r_compress=1 || true
r_develop=0; is_prerelease_tag "v1.0.0-develop" && r_develop=1 || true
r_device=0; is_prerelease_tag "v1.0.0-device" && r_device=1 || true
r_predict=0; is_prerelease_tag "v1.0.0-prediction" && r_predict=1 || true
r_express=0; is_prerelease_tag "express-1.0" && r_express=1 || true

echo "p_alpha=$p_alpha"
echo "p_beta1=$p_beta1"
echo "p_beta2=$p_beta2"
echo "p_rc1=$p_rc1"
echo "p_rc2=$p_rc2"
echo "p_preview=$p_preview"
echo "p_pre1=$p_pre1"
echo "p_pre2=$p_pre2"
echo "p_dev=$p_dev"
echo "p_nightly=$p_nightly"
echo "p_snapshot=$p_snapshot"
echo "s_v1=$s_v1"
echo "s_v2=$s_v2"
echo "s_v3=$s_v3"
echo "s_v4=$s_v4"
echo "s_v5=$s_v5"
echo "r_precise=$r_precise"
echo "r_compress=$r_compress"
echo "r_develop=$r_develop"
echo "r_device=$r_device"
echo "r_predict=$r_predict"
echo "r_express=$r_express"
EOS
)"

if printf '%s\n' "$prerelease_check_output" | grep -q 'p_alpha=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_beta1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_beta2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_rc1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_rc2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_preview=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_pre1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_pre2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_dev=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_nightly=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_snapshot=0'; then
    pass "is_prerelease_tag correctly rejects alpha, beta, rc, preview, pre, dev, nightly, and snapshot tokens"
else
    fail "is_prerelease_tag failed to reject prerelease token: $prerelease_check_output"
fi

if printf '%s\n' "$prerelease_check_output" | grep -q 's_v1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's_v2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's_v3=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's_v4=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's_v5=0'; then
    pass "is_prerelease_tag correctly accepts standard stable version tags"
else
    fail "is_prerelease_tag rejected valid stable tag: $prerelease_check_output"
fi

if printf '%s\n' "$prerelease_check_output" | grep -q 'r_precise=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_compress=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_develop=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_device=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_predict=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_express=0'; then
    pass "is_prerelease_tag avoids false positives on words containing 'pre' or 'dev' substrings (precise, develop, device, etc.)"
else
    fail "is_prerelease_tag false positive on boundary regression word: $prerelease_check_output"
fi

section "Cursor Window Controls and Wayland Integration"

if grep -q -- "--ozone-platform=wayland" "$ROOT/modules/applications.sh" &&
   grep -q -- "--enable-features=UseOzonePlatform" "$ROOT/modules/applications.sh"; then
    pass "applications.sh configures Cursor Wayland Ozone flags"
else
    fail "applications.sh missing Cursor Wayland Ozone flags"
fi

if grep -q "cursor-flags.conf" "$ROOT/modules/validation.sh"; then
    pass "validation.sh validates cursor-flags.conf"
else
    fail "validation.sh missing cursor-flags.conf check"
fi

section "Antigravity architecture guard"
agy_arch_output="$(
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
source "$SCRIPT_DIR/modules/applications.sh"

ANTIGRAVITY=true
uname() {
    if [[ "$1" == "-m" ]]; then
        echo "armv7l"
    else
        command uname "$@"
    fi
}
install_antigravity
echo "agy-arch-blocked=$ACTIVATION_BLOCKED"
echo "agy-arch-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$agy_arch_output" | grep -q 'agy-arch-blocked=0'; then
    pass "unsupported arch does not set ACTIVATION_BLOCKED"
else
    fail "unsupported arch set ACTIVATION_BLOCKED: $agy_arch_output"
fi

if printf '%s\n' "$agy_arch_output" | grep -q 'agy-arch-exit=2'; then
    pass "unsupported arch produces deferred exit code 2"
else
    fail "unsupported arch exit code: $agy_arch_output"
fi

section "User Nix Configuration Preservation"

nix_conf_output="$(
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
source "$SCRIPT_DIR/modules/nix.sh"

mkdir -p "$TARGET_HOME/.config/nix"
cat > "$TARGET_HOME/.config/nix/nix.conf" <<'CONF'
# Custom user nix configuration
trusted-users = root alice
substituters = https://cache.nixos.org https://custom-cache.org
CONF

configure_nix_features

user_custom_ok=$([[ $(grep -c 'trusted-users = root alice' "$TARGET_HOME/.config/nix/nix.conf") -eq 1 ]] && echo 1 || echo 0)
features_added=$([[ $(grep -c 'experimental-features = nix-command flakes' "$TARGET_HOME/.config/nix/nix.conf") -eq 1 ]] && echo 1 || echo 0)
warn_dirty_added=$([[ $(grep -c 'warn-dirty = false' "$TARGET_HOME/.config/nix/nix.conf") -eq 1 ]] && echo 1 || echo 0)

echo "user_custom_ok=$user_custom_ok"
echo "features_added=$features_added"
echo "warn_dirty_added=$warn_dirty_added"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$nix_conf_output" | grep -q 'user_custom_ok=1' &&
   printf '%s\n' "$nix_conf_output" | grep -q 'features_added=1' &&
   printf '%s\n' "$nix_conf_output" | grep -q 'warn_dirty_added=1'; then
    pass "configure_nix_features preserves existing user nix.conf settings while ensuring required flags"
else
    fail "configure_nix_features mutated or wiped user nix.conf: $nix_conf_output"
fi
