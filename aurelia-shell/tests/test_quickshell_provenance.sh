#!/usr/bin/env bash

# Test Suite: Quickshell package provenance, candidate validation, and safe convergence.

ROOT="${ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
# shellcheck source=/dev/null
source "$ROOT/tests/test_helper.sh"
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

# 11-12. invalid installed Quickshell detection and convergence planning
mock_rpm_dir="$(mktemp -d)"
cat << 'MOCK_EOF' > "$mock_rpm_dir/rpm"
#!/usr/bin/env bash
if [[ "$*" == *"%{NAME}"* ]]; then echo "quickshell"; exit 0; fi
if [[ "$*" == *"%{ARCH}"* ]]; then uname -m; exit 0; fi
if [[ "$*" == *"%{VERSION}-%{RELEASE}"* ]]; then echo "0.3.1-9.git.20260829.2d3b3e9.fc44"; exit 0; fi
if [[ "$*" == *"%{VENDOR}"* ]]; then echo "Fedora Copr - user lionheartp"; exit 0; fi
if [[ "$1" == "-q" ]]; then exit 0; fi
exit 0
MOCK_EOF
chmod +x "$mock_rpm_dir/rpm"

# 11. invalid installed Quickshell is not classified KEEP
if ! PATH="$mock_rpm_dir:$PATH" detect_quickshell; then
    pass "11. invalid installed Quickshell is detected as not satisfied (detect_quickshell returns 1)"
else
    fail "11. invalid installed Quickshell was incorrectly detected as valid"
fi

# 12. planner generates corrective action
reset_component_registry
init_default_components
init_desired_state "DS_CORR" "vm"
create_recommended_desired_state "DS_CORR" "vm"
desired_state_set_component "DS_CORR" "desktop.keybindings.aurelia" "managed"
desired_state_set_component "DS_CORR" "quickshell" "managed"

PATH="$mock_rpm_dir:$PATH" create_execution_plan "DS_CORR" "PLAN_CORR"
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
rm -rf "$mock_rpm_dir"

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

section "Quickshell Candidate Discovery & Parser Invariants"

# 18. old production repoquery command failure reproduced
old_cmd_rc=0
old_cmd_out=""
old_cmd_out="$(dnf -q repoquery --from-repo="$QUICKSHELL_APPROVED_REPOID" quickshell 2>&1)" || old_cmd_rc=$?
if [[ "$old_cmd_rc" -ne 0 && "$old_cmd_out" == *"Unknown argument \"--from-repo="* ]]; then
    pass "18. old production command failure reproduced (repoquery rejects --from-repo with code $old_cmd_rc)"
else
    fail "18. expected old repoquery command to fail with unknown argument error: rc=$old_cmd_rc out=$old_cmd_out"
fi

# 19. corrected candidate discovery against approved repository
appr_cand="$(query_quickshell_candidate "$QUICKSHELL_APPROVED_REPOID")" || appr_cand=""
read -r p_name p_epoch p_ver p_rel p_arch p_repo extra_tokens <<< "$appr_cand"
host_arch="$(uname -m 2>/dev/null || echo "x86_64")"

if [[ -n "$appr_cand" && \
      "$p_name" == "quickshell" && \
      "$p_epoch" == "0" && \
      "$p_ver" == "0.3.1" && \
      "$p_rel" == "2.fc44" && \
      "$p_arch" == "$host_arch" && \
      "$p_repo" == "$QUICKSHELL_APPROVED_REPOID" && \
      -z "$extra_tokens" ]]; then
    pass "19. approved candidate is discovered and parsed (name=$p_name epoch=$p_epoch ver=$p_ver rel=$p_rel arch=$p_arch repo=$p_repo)"
else
    fail "19. candidate discovery/parsing failed: '$appr_cand'"
fi

# 20. malformed repoquery output fails closed
mock_dir="$(mktemp -d)"
cat << 'MOCK_EOF' > "$mock_dir/dnf"
#!/usr/bin/env bash
echo "quickshell only three fields"
exit 0
MOCK_EOF
chmod +x "$mock_dir/dnf"

mal_rc=0
mal_out=""
mal_out="$(PATH="$mock_dir:$PATH" query_quickshell_candidate "$QUICKSHELL_APPROVED_REPOID" 2>/dev/null)" || mal_rc=$?
rm -rf "$mock_dir"

if [[ "$mal_rc" -eq 3 && -z "$mal_out" ]]; then
    pass "20. malformed repoquery output fails closed with exit code 3"
else
    fail "20. malformed output was not rejected cleanly: rc=$mal_rc out=$mal_out"
fi

# 21. repoquery nonzero exit is classified as query failure, not 'no candidate'
mock_dir="$(mktemp -d)"
cat << 'MOCK_EOF' > "$mock_dir/dnf"
#!/usr/bin/env bash
echo "Internal error in DNF" >&2
exit 2
MOCK_EOF
chmod +x "$mock_dir/dnf"

fail_rc=0
fail_err_log="$(mktemp)"
PATH="$mock_dir:$PATH" query_quickshell_candidate "$QUICKSHELL_APPROVED_REPOID" 2>"$fail_err_log" || fail_rc=$?
fail_err_content="$(cat "$fail_err_log")"
rm -rf "$mock_dir" "$fail_err_log"

if [[ "$fail_rc" -eq 2 && "$fail_err_content" == *"Failed to query approved Quickshell repository"* ]]; then
    pass "21. repoquery nonzero exit is treated as query failure with diagnostic, not 'no candidate'"
else
    fail "21. nonzero exit handling invalid: rc=$fail_rc err=$fail_err_content"
fi

# 22. genuinely empty successful query returns status 1 ('no candidate')
mock_dir="$(mktemp -d)"
cat << 'MOCK_EOF' > "$mock_dir/dnf"
#!/usr/bin/env bash
exit 0
MOCK_EOF
chmod +x "$mock_dir/dnf"

empty_rc=0
PATH="$mock_dir:$PATH" query_quickshell_candidate "$QUICKSHELL_APPROVED_REPOID" >/dev/null 2>&1 || empty_rc=$?
rm -rf "$mock_dir"

if [[ "$empty_rc" -eq 1 ]]; then
    pass "22. genuinely empty successful query returns status 1 ('no candidate')"
else
    fail "22. empty query did not return 1: rc=$empty_rc"
fi

# 23. unavailable repository returns query failure with repository unavailable diagnostic
unavail_rc=0
unavail_log="$(mktemp)"
query_quickshell_candidate "copr:copr.fedorainfracloud.org:nonexistent:repo" 2>"$unavail_log" || unavail_rc=$?
unavail_content="$(cat "$unavail_log")"
rm -f "$unavail_log"

if [[ "$unavail_rc" -ne 0 && "$unavail_content" == *"Approved Quickshell repository is unavailable"* ]]; then
    pass "23. unavailable repository is distinguished and reported with actionable diagnostic"
else
    fail "23. unavailable repository not distinguished: rc=$unavail_rc content=$unavail_content"
fi

# 24. post-install validation verifies candidate satisfaction
(
    package_installed() { return 0; }
    detect_quickshell() { return 1; }
    mock_dir="$(mktemp -d)"
    cat << 'MOCK_EOF' > "$mock_dir/dnf"
#!/usr/bin/env bash
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

    run_with_timeout() { shift 2; "$@"; }
    run_dnf_command() { shift 2; "$@"; }
    export MOCK_APPR_REPO="$QUICKSHELL_APPROVED_REPOID"
    post_val_rc=0
    PATH="$mock_dir:$PATH" install_approved_quickshell >/dev/null 2>&1 || post_val_rc=$?
    rm -rf "$mock_dir"

    if [[ "$post_val_rc" -ne 0 ]]; then
        pass "24. post-install validation failure fails closed after transaction"
    else
        fail "24. post-install validation failure was ignored"
    fi
)
