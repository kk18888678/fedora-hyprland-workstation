#!/usr/bin/env bash

# Test Suite: Declarative release policy, prerelease classification, and exceptions registry.

# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/status.sh"
# shellcheck source=/dev/null
source "$ROOT/modules/applications.sh"

section "Release Tag Boundary-Aware Classification"

# 22. Boundary-aware classifier does not produce false positives for ordinary words
t_precise="$(classify_release_tag "v1.0.0-precise")"
t_compress="$(classify_release_tag "v2.0-compress")"
t_develop="$(classify_release_tag "v1.0.0-develop")"
t_device="$(classify_release_tag "v1.0.0-device")"
t_predict="$(classify_release_tag "v1.0.0-prediction")"
t_express="$(classify_release_tag "express-1.0")"

if [[ "$t_precise" == "stable" && "$t_compress" == "stable" && \
      "$t_develop" == "stable" && "$t_device" == "stable" && \
      "$t_predict" == "stable" && "$t_express" == "stable" ]]; then
    pass "boundary-aware classifier does not produce false positives for ordinary words"
else
    fail "boundary-aware classifier produced false positives: precise=$t_precise compress=$t_compress develop=$t_develop device=$t_device predict=$t_predict express=$t_express"
fi

# 23. Explicit beta token is classified beta
if [[ "$(classify_release_tag "v1.0.0-beta.2")" == "beta" && \
      "$(classify_release_tag "0.6.0-beta")" == "beta" && \
      "$(classify_release_tag "v1.0.0_beta")" == "beta" ]]; then
    pass "explicit beta token is classified beta"
else
    fail "explicit beta token classification failed"
fi

# 24. Explicit rc token is classified rc
if [[ "$(classify_release_tag "v1.0.0-rc1")" == "rc" && \
      "$(classify_release_tag "v1.0.0-rc.2")" == "rc" ]]; then
    pass "explicit rc token is classified rc"
else
    fail "explicit rc token classification failed"
fi

# 25. Explicit preview token is classified preview
if [[ "$(classify_release_tag "v1.0.0-preview")" == "preview" && \
      "$(classify_release_tag "v2.0_preview.1")" == "preview" ]]; then
    pass "explicit preview token is classified preview"
else
    fail "explicit preview token classification failed"
fi

# 26. Explicit nightly token is classified nightly
if [[ "$(classify_release_tag "v1.0.0-nightly")" == "nightly" && \
      "$(classify_release_tag "nightly-2026-09-01")" == "nightly" ]]; then
    pass "explicit nightly token is classified nightly"
else
    fail "explicit nightly token classification failed"
fi

# Authoritative upstream metadata tests (Part 1):
# 1. tag v1.0.0-beta, metadata false -> beta
if [[ "$(classify_release_tag "v1.0.0-beta" "false")" == "beta" && \
      "$(classify_release_tag "v1.0.0-beta|false")" == "beta" ]]; then
    pass "explicit beta tag with metadata false is classified beta"
else
    fail "explicit beta tag with metadata false failed"
fi

# 2. tag v1.0.0-beta, metadata true -> beta
if [[ "$(classify_release_tag "v1.0.0-beta" "true")" == "beta" && \
      "$(classify_release_tag "v1.0.0-beta|true")" == "beta" ]]; then
    pass "explicit beta tag with metadata true is classified beta"
else
    fail "explicit beta tag with metadata true failed"
fi

# 3. tag v1.0.0, metadata false -> stable
if [[ "$(classify_release_tag "v1.0.0" "false")" == "stable" && \
      "$(classify_release_tag "v1.0.0|false")" == "stable" ]]; then
    pass "stable-looking tag with metadata false is classified stable"
else
    fail "stable-looking tag with metadata false failed"
fi

# 4. tag v1.0.0, metadata true -> unknown_prerelease
if [[ "$(classify_release_tag "v1.0.0" "true")" == "unknown_prerelease" && \
      "$(classify_release_tag "v1.0.0|true")" == "unknown_prerelease" ]]; then
    pass "stable-looking tag with authoritative metadata true is classified unknown_prerelease"
else
    fail "stable-looking tag with metadata true failed"
fi

# 5. Authoritative prerelease metadata survives candidate parsing and formatting
cand_formatted="$(format_release_candidate "v2.0.0" "true")"
parsed_t=""
parsed_m=""
parse_release_candidate "$cand_formatted" parsed_t parsed_m
if [[ "$cand_formatted" == "v2.0.0|true" && "$parsed_t" == "v2.0.0" && "$parsed_m" == "true" ]]; then
    pass "authoritative prerelease metadata survives candidate formatting and parsing"
else
    fail "candidate formatting/parsing failed: formatted=$cand_formatted tag=$parsed_t meta=$parsed_m"
fi

# 6. Unknown prerelease metadata never enters stable candidate list
sel_pre_meta_ret=0
select_eligible_release "app_no_exception" "v2.0.0|true" >/dev/null 2>&1 || sel_pre_meta_ret=$?
if [[ "$sel_pre_meta_ret" -ne 0 ]]; then
    pass "tag with authoritative prerelease metadata true never enters stable candidate path"
else
    fail "tag with prerelease metadata true incorrectly entered stable path"
fi

# 15. Unknown prerelease class -> rejected
t_unknown="$(classify_release_tag "v1.0.0-customtag" "true")"
if [[ "$t_unknown" == "unknown_prerelease" ]]; then
    pass "unidentified prerelease tag is classified as unknown_prerelease when marked as prerelease"
else
    fail "unidentified prerelease tag was not marked unknown_prerelease: $t_unknown"
fi

# 16. Upstream metadata says prerelease but classifier cannot identify class -> rejected
eval_unknown_err=""
eval_unknown_ret=0
evaluate_release_eligibility "n_m3u8dl_re" "v1.0.0-customtag" eval_unknown_err "true" || eval_unknown_ret=$?
if [[ "$eval_unknown_ret" -ne 0 && "$eval_unknown_err" == "unknown prerelease class" ]]; then
    pass "upstream metadata marking prerelease with unidentifiable class fails closed"
else
    fail "unidentifiable prerelease class did not fail closed: ret=$eval_unknown_ret err=$eval_unknown_err"
fi


section "Registry Validation and Fail-Closed Invariants"

reg_test_dir="$(mktemp -d)"

# 17. Malformed registry -> fail closed
bad_syntax_file="$reg_test_dir/bad_syntax.conf"
cat << 'INNER_EOF' > "$bad_syntax_file"
[broken_app]
this is not valid key-value syntax!
INNER_EOF
if ! validate_prerelease_exceptions_registry "$bad_syntax_file" 2>/dev/null; then
    pass "malformed registry with invalid syntax is rejected by validator"
else
    fail "malformed registry with invalid syntax was accepted"
fi

bad_eval_err=""
bad_eval_ret=0
PRERELEASE_EXCEPTIONS_FILE="$bad_syntax_file" evaluate_release_eligibility "n_m3u8dl_re" "v0.6.0-beta" bad_eval_err || bad_eval_ret=$?
if [[ "$bad_eval_ret" -ne 0 && "$bad_eval_err" == "malformed exception policy" ]]; then
    pass "malformed registry causes prerelease evaluation to fail closed"
else
    fail "malformed registry did not fail closed during evaluation: ret=$bad_eval_ret err=$bad_eval_err"
fi

# 18. Duplicate application ID -> fail closed
dup_app_file="$reg_test_dir/dup_app.conf"
cat << 'INNER_EOF' > "$dup_app_file"
[app_one]
enabled = true
allowed_classes = beta
selection_policy = stable_then_allowed_prerelease
reason = "App one"

[app_one]
enabled = true
allowed_classes = beta
selection_policy = stable_then_allowed_prerelease
reason = "App one duplicate"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$dup_app_file" 2>/dev/null; then
    pass "registry with duplicate application ID is rejected"
else
    fail "registry with duplicate application ID was accepted"
fi

# 19. Unknown allowed class in registry -> fail closed
unknown_cls_file="$reg_test_dir/unknown_cls.conf"
cat << 'INNER_EOF' > "$unknown_cls_file"
[app_custom]
enabled = true
allowed_classes = beta,unsupported_class
selection_policy = stable_then_allowed_prerelease
reason = "Custom app"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$unknown_cls_file" 2>/dev/null; then
    pass "registry with unknown prerelease class in allowed_classes is rejected"
else
    fail "registry with unknown prerelease class was accepted"
fi

# 20. Empty allowed-class set -> fail closed
empty_cls_file="$reg_test_dir/empty_cls.conf"
cat << 'INNER_EOF' > "$empty_cls_file"
[app_custom]
enabled = true
allowed_classes =
selection_policy = stable_then_allowed_prerelease
reason = "Custom app"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$empty_cls_file" 2>/dev/null; then
    pass "registry with empty allowed_classes is rejected"
else
    fail "registry with empty allowed_classes was accepted"
fi

# Wildcard in allowed_classes is prohibited
wildcard_cls_file="$reg_test_dir/wildcard_cls.conf"
cat << 'INNER_EOF' > "$wildcard_cls_file"
[app_custom]
enabled = true
allowed_classes = *
selection_policy = stable_then_allowed_prerelease
reason = "Custom app"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$wildcard_cls_file" 2>/dev/null; then
    pass "wildcard in allowed_classes is rejected by validator"
else
    fail "wildcard in allowed_classes was accepted"
fi

# 21. Unsupported selection policy -> fail closed
bad_policy_file="$reg_test_dir/bad_policy.conf"
cat << 'INNER_EOF' > "$bad_policy_file"
[app_custom]
enabled = true
allowed_classes = beta
selection_policy = random_policy
reason = "Custom app"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$bad_policy_file" 2>/dev/null; then
    pass "registry with unsupported selection_policy is rejected"
else
    fail "registry with unsupported selection_policy was accepted"
fi

# Duplicate enabled rejected
dup_enabled_file="$reg_test_dir/dup_enabled.conf"

cat << 'INNER_EOF' > "$dup_enabled_file"
[app_dup]
enabled = true
enabled = false
allowed_classes = beta
selection_policy = stable_then_allowed_prerelease
reason = "Duplicate enabled"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$dup_enabled_file" 2>/dev/null; then
    pass "registry with duplicate enabled property is rejected"
else
    fail "registry with duplicate enabled property was accepted"
fi

# Duplicate allowed_classes rejected
dup_classes_file="$reg_test_dir/dup_classes.conf"
cat << 'INNER_EOF' > "$dup_classes_file"
[app_dup]
enabled = true
allowed_classes = beta
allowed_classes = rc
selection_policy = stable_then_allowed_prerelease
reason = "Duplicate classes"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$dup_classes_file" 2>/dev/null; then
    pass "registry with duplicate allowed_classes property is rejected"
else
    fail "registry with duplicate allowed_classes property was accepted"
fi

# Duplicate selection_policy rejected
dup_pol_file="$reg_test_dir/dup_policy.conf"
cat << 'INNER_EOF' > "$dup_pol_file"
[app_dup]
enabled = true
allowed_classes = beta
selection_policy = stable_then_allowed_prerelease
selection_policy = stable_then_allowed_prerelease
reason = "Duplicate policy"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$dup_pol_file" 2>/dev/null; then
    pass "registry with duplicate selection_policy property is rejected"
else
    fail "registry with duplicate selection_policy property was accepted"
fi

# Duplicate reason rejected
dup_reason_file="$reg_test_dir/dup_reason.conf"
cat << 'INNER_EOF' > "$dup_reason_file"
[app_dup]
enabled = true
allowed_classes = beta
selection_policy = stable_then_allowed_prerelease
reason = "First reason"
reason = "Second reason"
INNER_EOF
if ! validate_prerelease_exceptions_registry "$dup_reason_file" 2>/dev/null; then
    pass "registry with duplicate reason property is rejected"
else
    fail "registry with duplicate reason property was accepted"
fi

# Duplicate property causes prerelease evaluation to fail closed
dup_eval_err=""
dup_eval_ret=0
PRERELEASE_EXCEPTIONS_FILE="$dup_enabled_file" evaluate_release_eligibility "app_dup" "v1.0.0-beta" dup_eval_err || dup_eval_ret=$?
if [[ "$dup_eval_ret" -ne 0 && "$dup_eval_err" == "malformed exception policy" ]]; then
    pass "duplicate property causes prerelease evaluation to fail closed"
else
    fail "duplicate property did not fail closed during evaluation: ret=$dup_eval_ret err=$dup_eval_err"
fi

rm -rf "$reg_test_dir"


section "Release Selection Semantics (stable > allowed prerelease)"

# Fixture registry with known apps
fixture_dir="$(mktemp -d)"
fixture_conf="$fixture_dir/test_exceptions.conf"
cat << 'INNER_EOF' > "$fixture_conf"
[app_beta_only]
enabled = true
allowed_classes = beta
selection_policy = stable_then_allowed_prerelease
reason = "Approved beta exception"

[app_disabled]
enabled = false
allowed_classes = beta
selection_policy = stable_then_allowed_prerelease
reason = "Disabled exception"

[n_m3u8dl_re]
enabled = true
allowed_classes = beta
selection_policy = stable_then_allowed_prerelease
reason = "N_m3u8DL-RE official beta releases"
INNER_EOF

export PRERELEASE_EXCEPTIONS_FILE="$fixture_conf"
# Force re-load of test fixture
load_prerelease_exceptions_registry "$fixture_conf"

# 1. Stable release with no exception -> stable selected
sel1="$(select_eligible_release "app_no_exception" "v1.0.0")"
if [[ "$sel1" == "v1.0.0" ]]; then
    pass "stable release with no exception selects stable"
else
    fail "stable release with no exception failed: $sel1"
fi

# 2. Beta-only release with no exception -> rejected/deferred
sel2_ret=0
sel2_out="$(select_eligible_release "app_no_exception" "v1.0.0-beta" 2>&1)" || sel2_ret=$?
if [[ "$sel2_ret" -ne 0 && "$sel2_out" == *"Prerelease prohibited by default"* ]]; then
    pass "beta-only release with no exception is rejected by default"
else
    fail "beta-only release with no exception was not rejected: ret=$sel2_ret out=$sel2_out"
fi

# 3. Beta-only release with beta exception -> beta selected
sel3="$(select_eligible_release "app_beta_only" "v1.0.0-beta")"
if [[ "$sel3" == "v1.0.0-beta" ]]; then
    pass "beta-only release with beta exception selects beta"
else
    fail "beta-only release with beta exception failed: $sel3"
fi

# 4. Stable + newer beta with beta exception -> stable selected
sel4="$(select_eligible_release "app_beta_only" "v1.0.0" "v2.0.0-beta")"
if [[ "$sel4" == "v1.0.0" ]]; then
    pass "stable release takes precedence over newer beta release"
else
    fail "newer beta incorrectly beat stable release: $sel4"
fi

# 5. Stable + older beta with beta exception -> stable selected
sel5="$(select_eligible_release "app_beta_only" "v1.9.0" "v1.8.0-beta")"
if [[ "$sel5" == "v1.9.0" ]]; then
    pass "stable release takes precedence over older beta release"
else
    fail "older beta incorrectly beat stable release: $sel5"
fi

# 6. Alpha-only with beta exception -> rejected
sel6_ret=0
select_eligible_release "app_beta_only" "v1.0.0-alpha" >/dev/null 2>&1 || sel6_ret=$?
if [[ "$sel6_ret" -ne 0 ]]; then
    pass "alpha-only release with beta exception is rejected"
else
    fail "alpha-only release was accepted under beta exception"
fi

# 7. RC-only with beta exception -> rejected
sel7_ret=0
select_eligible_release "app_beta_only" "v1.0.0-rc1" >/dev/null 2>&1 || sel7_ret=$?
if [[ "$sel7_ret" -ne 0 ]]; then
    pass "rc-only release with beta exception is rejected"
else
    fail "rc-only release was accepted under beta exception"
fi

# 8. Nightly-only with beta exception -> rejected
sel8_ret=0
select_eligible_release "app_beta_only" "v1.0.0-nightly" >/dev/null 2>&1 || sel8_ret=$?
if [[ "$sel8_ret" -ne 0 ]]; then
    pass "nightly-only release with beta exception is rejected"
else
    fail "nightly-only release was accepted under beta exception"
fi

# 9. Dev-only with beta exception -> rejected
sel9_ret=0
select_eligible_release "app_beta_only" "v1.0.0-dev" >/dev/null 2>&1 || sel9_ret=$?
if [[ "$sel9_ret" -ne 0 ]]; then
    pass "dev-only release with beta exception is rejected"
else
    fail "dev-only release was accepted under beta exception"
fi

# 10. Snapshot-only with beta exception -> rejected
sel10_ret=0
select_eligible_release "app_beta_only" "v1.0.0-snapshot" >/dev/null 2>&1 || sel10_ret=$?
if [[ "$sel10_ret" -ne 0 ]]; then
    pass "snapshot-only release with beta exception is rejected"
else
    fail "snapshot-only release was accepted under beta exception"
fi

# 11. Preview-only with beta exception -> rejected
sel11_ret=0
select_eligible_release "app_beta_only" "v1.0.0-preview" >/dev/null 2>&1 || sel11_ret=$?
if [[ "$sel11_ret" -ne 0 ]]; then
    pass "preview-only release with beta exception is rejected"
else
    fail "preview-only release was accepted under beta exception"
fi

# 12. Beta allowed for application A does not allow beta for application B
sel12_ret=0
select_eligible_release "app_unrelated" "v1.0.0-beta" >/dev/null 2>&1 || sel12_ret=$?
if [[ "$sel12_ret" -ne 0 ]]; then
    pass "beta exception for application A does not grant permission to application B"
else
    fail "beta exception leaked across applications"
fi

# 13. Disabled exception -> prerelease rejected
sel13_ret=0
select_eligible_release "app_disabled" "v1.0.0-beta" >/dev/null 2>&1 || sel13_ret=$?
if [[ "$sel13_ret" -ne 0 ]]; then
    pass "disabled exception in registry rejects prerelease"
else
    fail "disabled exception permitted prerelease"
fi

# 14. Unknown application ID -> prerelease rejected
sel14_ret=0
select_eligible_release "nonexistent_app_id" "v1.0.0-beta" >/dev/null 2>&1 || sel14_ret=$?
if [[ "$sel14_ret" -ne 0 ]]; then
    pass "unknown application ID rejects prerelease"
else
    fail "unknown application ID permitted prerelease"
fi

section "N_m3u8DL-RE Realistic Release Fixtures"

# 30. N_m3u8DL-RE fixture selects stable when a stable candidate exists
n_stable_res="$(select_eligible_release "n_m3u8dl_re" "v1.0.0" "v0.6.0-beta")"
if [[ "$n_stable_res" == "v1.0.0" ]]; then
    pass "N_m3u8DL-RE fixture selects stable when stable candidate exists"
else
    fail "N_m3u8DL-RE fixture failed to select stable over beta: $n_stable_res"
fi

# 31. N_m3u8DL-RE fixture selects beta when no stable exists and beta is permitted
n_beta_res="$(select_eligible_release "n_m3u8dl_re" "v0.5.1-beta" "v0.6.0-beta")"
if [[ "$n_beta_res" == "v0.6.0-beta" ]]; then
    pass "N_m3u8DL-RE fixture selects newest beta when no stable candidate exists"
else
    fail "N_m3u8DL-RE fixture failed to select newest beta: $n_beta_res"
fi

# 32. N_m3u8DL-RE fixture rejects alpha/nightly/etc.
n_alpha_ret=0
select_eligible_release "n_m3u8dl_re" "v0.7.0-alpha" >/dev/null 2>&1 || n_alpha_ret=$?
n_nightly_ret=0
select_eligible_release "n_m3u8dl_re" "v0.7.0-nightly" >/dev/null 2>&1 || n_nightly_ret=$?
if [[ "$n_alpha_ret" -ne 0 && "$n_nightly_ret" -ne 0 ]]; then
    pass "N_m3u8DL-RE fixture strictly rejects alpha and nightly releases"
else
    fail "N_m3u8DL-RE fixture permitted alpha or nightly releases: alpha_ret=$n_alpha_ret nightly_ret=$n_nightly_ret"
fi

# 33. Second-run/idempotent behavior remains deterministic
run1="$(select_eligible_release "n_m3u8dl_re" "v0.6.0-beta")"
run2="$(select_eligible_release "n_m3u8dl_re" "v0.6.0-beta")"
if [[ "$run1" == "v0.6.0-beta" && "$run2" == "v0.6.0-beta" ]]; then
    pass "second-run evaluation remains completely idempotent and deterministic"
else
    fail "evaluation was not idempotent across multiple calls"
fi

rm -rf "$fixture_dir"
unset PRERELEASE_EXCEPTIONS_FILE
# Reload canonical repository registry
load_prerelease_exceptions_registry "$ROOT/config/prerelease_exceptions.conf"

section "Supply-Chain Separation: Exceptions Affect Eligibility Only"

# 27. Exception affects eligibility only: checksum/integrity validation path remains strictly required
mismatch_deferred=0
(
    TARGET_HOME="$(mktemp -d)"
    MEDIA_TOOLS_DIR="$(mktemp -d)"
    export MEDIA_TOOLS_DIR
    N_M3U8DL_RE_SHA512="00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    command_exists() { return 1; }
    provision_verified_archive() {
        # Simulate checksum failure in provision_verified_archive
        return 1
    }
    install_media_utilities
    grep -q "Failed to download, verify, or extract N_m3u8DL-RE" <(printf '%s\n' "${INSTALL_DEFERRED[@]}")
) || mismatch_deferred=$?

if [[ "$mismatch_deferred" -eq 0 ]]; then
    pass "prerelease exception does not weaken checksum verification; integrity failure records deferred"
else
    fail "prerelease exception bypassed or suppressed checksum verification failure"
fi

# 28. Exception affects eligibility only: archive safety validation remains required
archive_safety_enforced=0
(
    TARGET_HOME="$(mktemp -d)"
    MEDIA_TOOLS_DIR="$(mktemp -d)"
    export MEDIA_TOOLS_DIR
    command_exists() { return 1; }
    provision_verified_archive() {
        # Verify that provision_verified_archive still receives enforce_single_binary = true
        local enforce="$6"
        if [[ "$enforce" == "true" ]]; then
            return 0
        fi
        return 1
    }
    install_media_utilities
) && archive_safety_enforced=1 || true

if [[ "$archive_safety_enforced" -eq 1 ]]; then
    pass "prerelease exception does not weaken archive safety enforcement (enforce_single_binary preserved)"
else
    fail "archive safety enforcement was weakened for prerelease artifact"
fi

# 29. Exception affects eligibility only: architecture matching remains required
arch_guard_enforced=0
(
    TARGET_HOME="$(mktemp -d)"
    MEDIA_TOOLS_DIR="$(mktemp -d)"
    export MEDIA_TOOLS_DIR
    load_pinned_versions
    # Test that N_M3U8DL_RE_URL architecture token matches current x86_64 target
    if [[ "${N_M3U8DL_RE_URL:-}" == *"linux-x64"* ]]; then
        exit 0
    fi
    exit 1
) && arch_guard_enforced=1 || true


if [[ "$arch_guard_enforced" -eq 1 ]]; then
    pass "prerelease artifact explicitly specifies and enforces supported target architecture (linux-x64)"
else
    fail "prerelease artifact did not enforce target architecture"
fi

section "Bounded Pagination & Discovery Semantics"

# 7. Stable on first page -> stable selected
mock_fetcher_stable_first() {
    local slug="$1" page="$2" per_page="$3"
    if [[ "$page" -eq 1 ]]; then
        cat << 'INNER_EOF'
[
  {"tag_name": "v1.0.0", "prerelease": false}
]
INNER_EOF
    else
        echo "[]"
    fi
}
cand_p1=()
st_p1=""
discover_github_release_candidates "mock/repo" cand_p1 st_p1 mock_fetcher_stable_first
sel_p1="$(select_eligible_release --discovery-status "$st_p1" "test_app" "${cand_p1[@]}")"
if [[ "$sel_p1" == "v1.0.0" && "$st_p1" == "complete" ]]; then
    pass "stable release on first page is discovered and selected"
else
    fail "first page stable discovery failed: sel=$sel_p1 st=$st_p1"
fi

# 8. Stable on later page -> stable selected (stable beats newer beta on earlier page)
mock_fetcher_stable_later() {
    local slug="$1" page="$2" per_page="$3"
    if [[ "$page" -eq 1 ]]; then
        # Page 1 has 30 beta releases
        printf '['
        for i in $(seq 1 30); do
            [[ "$i" -gt 1 ]] && printf ','
            printf '{"tag_name": "v2.0.0-beta.%d", "prerelease": true}' "$i"
        done
        printf ']\n'
    elif [[ "$page" -eq 2 ]]; then
        # Page 2 has a stable release
        cat << 'INNER_EOF'
[
  {"tag_name": "v1.9.0", "prerelease": false}
]
INNER_EOF
    else
        echo "[]"
    fi
}
cand_p2=()
st_p2=""
discover_github_release_candidates "mock/repo" cand_p2 st_p2 mock_fetcher_stable_later
sel_p2="$(select_eligible_release --discovery-status "$st_p2" "n_m3u8dl_re" "${cand_p2[@]}")"
if [[ "$sel_p2" == "v1.9.0" && "$st_p2" == "complete" ]]; then
    pass "stable release on later page is discovered and takes precedence over newer beta on earlier page"
else
    fail "later page stable discovery failed: sel=$sel_p2 st=$st_p2"
fi

# 9. Complete beta-only history permits beta for approved app
mock_fetcher_beta_only_complete() {
    local slug="$1" page="$2" per_page="$3"
    if [[ "$page" -eq 1 ]]; then
        cat << 'INNER_EOF'
[
  {"tag_name": "v0.6.0-beta", "prerelease": true},
  {"tag_name": "v0.5.0-beta", "prerelease": true}
]
INNER_EOF
    else
        echo "[]"
    fi
}
cand_p3=()
st_p3=""
discover_github_release_candidates "mock/repo" cand_p3 st_p3 mock_fetcher_beta_only_complete
sel_p3="$(select_eligible_release --discovery-status "$st_p3" "n_m3u8dl_re" "${cand_p3[@]}")"
if [[ "$sel_p3" == "v0.6.0-beta" && "$st_p3" == "complete" ]]; then
    pass "complete pagination with beta-only history permits allowed beta for approved app"
else
    fail "complete beta-only discovery failed: sel=$sel_p3 st=$st_p3"
fi

# 10. Discovery bound reached before completion -> fails closed, no beta fallback
mock_fetcher_infinite_betas() {
    local slug="$1" page="$2" per_page="$3"
    printf '['
    for i in $(seq 1 30); do
        [[ "$i" -gt 1 ]] && printf ','
        printf '{"tag_name": "v0.9.%d-beta", "prerelease": true}' "$i"
    done
    printf ']\n'
}
cand_p4=()
st_p4=""
RELEASE_DISCOVERY_MAX_PAGES=3 discover_github_release_candidates "mock/repo" cand_p4 st_p4 mock_fetcher_infinite_betas
sel_p4_ret=0
sel_p4_out="$(select_eligible_release --discovery-status "$st_p4" "n_m3u8dl_re" "${cand_p4[@]}" 2>&1)" || sel_p4_ret=$?
if [[ "$st_p4" == "bound_reached" && "$sel_p4_ret" -ne 0 && "$sel_p4_out" == *"Release discovery was incomplete"* ]]; then
    pass "discovery bound reached without stable release fails closed and rejects beta fallback"
else
    fail "discovery bound reached did not fail closed: st=$st_p4 ret=$sel_p4_ret out=$sel_p4_out"
fi

# 11. Incomplete discovery never enables beta fallback
incomplete_sel_ret=0
incomplete_sel_out="$(select_eligible_release --discovery-status "incomplete" "n_m3u8dl_re" "v0.6.0-beta|true" 2>&1)" || incomplete_sel_ret=$?
if [[ "$incomplete_sel_ret" -ne 0 && "$incomplete_sel_out" == *"Release discovery was incomplete"* ]]; then
    pass "incomplete discovery status explicitly blocks prerelease fallback"
else
    fail "incomplete discovery incorrectly permitted beta fallback: ret=$incomplete_sel_ret out=$incomplete_sel_out"
fi

# 12. Page retrieval error rejects prerelease fallback
mock_fetcher_network_error() {
    return 1
}
cand_p5=()
st_p5=""
discover_github_release_candidates "mock/repo" cand_p5 st_p5 mock_fetcher_network_error
sel_p5_ret=0
sel_p5_out="$(select_eligible_release --discovery-status "$st_p5" "n_m3u8dl_re" "v0.6.0-beta|true" 2>&1)" || sel_p5_ret=$?
if [[ "$st_p5" == "fetch_error" && "$sel_p5_ret" -ne 0 && "$sel_p5_out" == *"Release discovery was incomplete"* ]]; then
    pass "network or page retrieval failure fails closed and rejects prerelease fallback"
else
    fail "page retrieval error did not fail closed: st=$st_p5 ret=$sel_p5_ret out=$sel_p5_out"
fi

