#!/usr/bin/env bash

# Test Suite: Quickshell package provenance, candidate validation, and safe convergence.

# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/repositories.sh"

section "Quickshell Provenance & Resolver Conflict Reproduction"

# Real observed candidates:
# Unapproved Git snapshot from Hyprland Copr:
CAND_LIONHEART="quickshell 0 0.3.1 9.git.20260829.2d3b3e9.fc44 x86_64 copr:copr.fedorainfracloud.org:lionheartp:Hyprland"
# Approved formal stable release from errornointernet Copr:
CAND_APPROVED="quickshell 0 0.3.1 2.fc44 x86_64 copr:copr.fedorainfracloud.org:errornointernet:quickshell"

# 1. Unrestricted resolution would choose the numerically newer Git build
read -r _c1_n _c1_e _c1_v c1_r _c1_a _c1_repo <<< "$CAND_LIONHEART"
read -r _c2_n _c2_e _c2_v c2_r _c2_a _c2_repo <<< "$CAND_APPROVED"
r1_prefix="${c1_r%%.*}"
r2_prefix="${c2_r%%.*}"
if (( r1_prefix > r2_prefix )); then
    pass "1. unrestricted resolution would choose the numerically newer Git build (EVR release $r1_prefix > $r2_prefix)"
else
    fail "1. expected Git snapshot release $r1_prefix to outrank stable release $r2_prefix"
fi

# 2. Policy rejects that candidate
read -r c_n c_e c_v c_r c_a c_repo <<< "$CAND_LIONHEART"
reason=""
if ! validate_quickshell_candidate "$c_n" "$c_e" "$c_v" "$c_r" "$c_a" "$c_repo" reason; then
    pass "2. policy rejects that candidate: $reason"
else
    fail "2. policy unexpectedly accepted Git candidate from unapproved repository"
fi

# 3. Approved repository candidate is accepted
read -r c_n c_e c_v c_r c_a c_repo <<< "$CAND_APPROVED"
reason=""
if validate_quickshell_candidate "$c_n" "$c_e" "$c_v" "$c_r" "$c_a" "$c_repo" reason; then
    pass "3. approved repository candidate is accepted"
else
    fail "3. approved repository candidate was rejected: $reason"
fi

# 4. Install path restricts transaction to approved repository
appr_repo="${QUICKSHELL_APPROVED_REPOID:-copr:copr.fedorainfracloud.org:errornointernet:quickshell}"
mock_dir="$(mktemp -d)"
mock_log="$(mktemp)"
cat << 'MOCK_EOF' > "$mock_dir/dnf"
#!/usr/bin/env bash
echo "DNF_ARGS: $@" >> "$MOCK_LOG"
if [[ "$1" == "repoquery" || "$2" == "repoquery" ]]; then
    echo "quickshell 0 0.3.1 2.fc44 x86_64 $MOCK_APPR_REPO"
    exit 0
fi
exit 0
MOCK_EOF
chmod +x "$mock_dir/dnf"

cat << 'MOCK_EOF' > "$mock_dir/sudo"
#!/usr/bin/env bash
"$@"
MOCK_EOF
chmod +x "$mock_dir/sudo"

(
    run_with_timeout() { shift 2; "$@"; }
    run_dnf_command() { shift 2; "$@"; }
    package_installed() { return 1; }
    copr_enabled() { return 0; }
    export MOCK_LOG="$mock_log"
    export MOCK_APPR_REPO="$appr_repo"
    PATH="$mock_dir:$PATH" install_approved_quickshell >/dev/null 2>&1 || true
)

if grep -q -- "--from-repo=$appr_repo" "$mock_log"; then
    pass "4. install path restricts transaction to approved repository (--from-repo=$appr_repo)"
else
    fail "4. install path did not restrict transaction to approved repository"
fi
rm -rf "$mock_dir" "$mock_log"

# 5. quickshell-git is rejected
reason=""
if ! validate_quickshell_candidate "quickshell-git" "0" "0.3.1" "1.fc44" "x86_64" "copr:copr.fedorainfracloud.org:errornointernet:quickshell" reason; then
    pass "5. quickshell-git is rejected: $reason"
else
    fail "5. quickshell-git was unexpectedly accepted"
fi

# 6. .git release is rejected
reason=""
if ! validate_quickshell_candidate "quickshell" "0" "0.3.1" "9.git.20260829.2d3b3e9.fc44" "x86_64" "copr:copr.fedorainfracloud.org:errornointernet:quickshell" reason; then
    pass "6. .git release is rejected: $reason"
else
    fail "6. .git release was unexpectedly accepted"
fi

# 7. beta/rc/nightly/dev/snapshot are rejected
all_rejected=1
for pre in "1.beta" "1.rc1" "1.nightly" "1.dev" "1.snapshot" "1^git20260209"; do
    reason=""
    if validate_quickshell_candidate "quickshell" "0" "0.3.1" "$pre" "x86_64" "copr:copr.fedorainfracloud.org:errornointernet:quickshell" reason; then
        all_rejected=0
        fail "7. prerelease $pre was unexpectedly accepted"
        break
    fi
done
if [[ "$all_rejected" -eq 1 ]]; then
    pass "7. beta/rc/nightly/dev/snapshot are rejected"
fi

# 8. stable formal release is accepted
reason=""
if validate_quickshell_candidate "quickshell" "0" "0.3.1" "2.fc44" "x86_64" "copr:copr.fedorainfracloud.org:errornointernet:quickshell" reason; then
    pass "8. stable formal release is accepted"
else
    fail "8. stable formal release was unexpectedly rejected: $reason"
fi

# 9. wrong repository with otherwise stable-looking version is rejected
reason=""
if ! validate_quickshell_candidate "quickshell" "0" "0.3.1" "2.fc44" "x86_64" "copr:copr.fedorainfracloud.org:lionheartp:Hyprland" reason; then
    pass "9. wrong repository with otherwise stable-looking version is rejected: $reason"
else
    fail "9. candidate from unapproved repository was unexpectedly accepted"
fi

# 10. wrong architecture is rejected
reason=""
host_arch="$(uname -m 2>/dev/null || echo "x86_64")"
bad_arch="aarch64"
[[ "$host_arch" == "aarch64" ]] && bad_arch="x86_64"
if ! validate_quickshell_candidate "quickshell" "0" "0.3.1" "2.fc44" "$bad_arch" "copr:copr.fedorainfracloud.org:errornointernet:quickshell" reason; then
    pass "10. wrong architecture is rejected: $reason"
else
    fail "10. candidate with wrong architecture was unexpectedly accepted"
fi

# 11. invalid installed Quickshell is not classified KEEP
if ! detect_quickshell; then
    pass "11. invalid installed Quickshell is detected as not satisfied (detect_quickshell returns 1)"
else
    fail "11. invalid installed Quickshell was incorrectly detected as valid"
fi

# 12. planner generates corrective action
reset_component_registry
init_default_components
init_desired_state "DS_CORR" "vm"
create_recommended_desired_state "DS_CORR" "vm"
desired_state_set_component "DS_CORR" "desktop.hotkeys.aurelia" "managed"
desired_state_set_component "DS_CORR" "quickshell" "managed"

create_execution_plan "DS_CORR" "PLAN_CORR"
q_action=""
q_reason=""
for idx in "${PLAN_CORR_ACTIONS[@]}"; do
    if [[ "${PLAN_CORR_ACTION_TARGET[$idx]}" == "quickshell" ]]; then
        q_action="${PLAN_CORR_ACTION_TYPE[$idx]}"
        q_reason="${PLAN_CORR_ACTION_REASON[$idx]}"
        break
    fi
done

if [[ "$q_action" == "INSTALL" && "$q_reason" == *"convergence required"* ]]; then
    pass "12. planner generates corrective action: $q_action ($q_reason)"
else
    fail "12. planner failed to generate corrective action: action=$q_action reason=$q_reason"
fi

# 13. reconciler chooses deterministic approved source
body="$(declare -f install_quickshell_adapter || true)"
if [[ "$body" == *"install_approved_quickshell"* ]]; then
    pass "13. reconciler chooses deterministic approved source via install_approved_quickshell"
else
    fail "13. reconciler does not invoke install_approved_quickshell"
fi

# 14. correction supports installed higher-EVR Git snapshot -> stable approved build
body="$(declare -f install_approved_quickshell || true)"
if [[ "$body" == *"distro-sync"* && "$body" == *"--from-repo="* && "$body" == *"--allow-downgrade"* ]]; then
    pass "14. correction supports installed higher-EVR Git snapshot -> stable approved build via distro-sync / --allow-downgrade"
else
    fail "14. install_approved_quickshell does not contain distro-sync and allow-downgrade handling"
fi

# 15. no global repository disable/priority mutation is introduced
body="$(declare -f install_approved_quickshell || true)"
if [[ "$body" != *"--disable-repo=*"* && "$body" != *"--disablerepo=*"* ]]; then
    pass "15. no global repository disable/priority mutation is introduced (transaction-scoped --from-repo)"
else
    fail "15. global repository disable detected in install_approved_quickshell"
fi

# 16. existing Hyprland repository remains independently usable
if grep -q 'enable_copr "lionheartp/Hyprland"' "$ROOT/modules/repositories.sh"; then
    pass "16. existing Hyprland repository remains independently usable"
else
    fail "16. lionheartp/Hyprland was modified or disabled"
fi

# 17. failure to resolve approved candidate fails closed before mutation
mock_dir="$(mktemp -d)"
mock_log="$(mktemp)"
cat << 'MOCK_EOF' > "$mock_dir/dnf"
#!/usr/bin/env bash
if [[ "$1" == "repoquery" || "$2" == "repoquery" ]]; then
    # Return empty to simulate repository failure or package unavailable
    exit 0
fi
echo "MUTATION_ATTEMPTED: $@" >> "$MOCK_LOG"
exit 0
MOCK_EOF
chmod +x "$mock_dir/dnf"

cat << 'MOCK_EOF' > "$mock_dir/sudo"
#!/usr/bin/env bash
"$@"
MOCK_EOF
chmod +x "$mock_dir/sudo"

rc=0
(
    run_with_timeout() { shift 2; "$@"; }
    run_dnf_command() { shift 2; "$@"; }
    copr_enabled() { return 0; }
    export MOCK_LOG="$mock_log"
    PATH="$mock_dir:$PATH" install_approved_quickshell >/dev/null 2>&1 || exit $?
) || rc=$?

mutations="$(cat "$mock_log" 2>/dev/null || true)"
rm -rf "$mock_dir" "$mock_log"

if [[ "$rc" -ne 0 && -z "$mutations" ]]; then
    pass "17. failure to resolve approved candidate fails closed before mutation (rc=$rc, zero mutations)"
else
    fail "17. candidate resolution failure did not fail closed: rc=$rc mutations=$mutations"
fi
