#!/usr/bin/env bash

# Test Suite: Quickshell stable-software provenance and transaction-scoped
# convergence.
#
# This suite exercises the CURRENT installer code paths in
# modules/lib/packages.sh and modules/packages.sh.  Every package mutation is
# mocked; no real dnf, rpm, sudo, repository, or session state is touched.
#
# The defect being defended against: the lionheartp/Hyprland COPR is required
# for Hyprland and also publishes Quickshell Git snapshots whose EVR outranks
# the approved stable release.  Unrestricted resolution therefore selects the
# snapshot, which the repository's stable-software policy must reject and
# converge down to the approved non-git build.

WORKSTATION_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

APPROVED_REPO="copr:copr.fedorainfracloud.org:errornointernet:quickshell"
GIT_EVR="0.3.1-12.git.20260915.c6a5160.fc44"
STABLE_EVR="0.3.1-2.fc44"

run_isolated() {
    bash -s -- "$WORKSTATION_ROOT" <<< "$1"
}

section "Quickshell Provenance: Real Resolver Conflict and Existing Classifier"

# 1. Real RPM EVR comparison.  A git snapshot outranks the stable release, so
#    an unrestricted resolver would select it.  This is the precise state the
#    convergence code must defend against.
vercmp="$(rpm --eval "%{lua:print(rpm.vercmp(\"$STABLE_EVR\", \"$GIT_EVR\"))}" || printf '?')"
if [[ "$vercmp" == "-1" ]]; then
    pass "[static] unrestricted resolution ranks git snapshot above stable release ($STABLE_EVR < $GIT_EVR)"
else
    fail "[static] expected git snapshot to outrank stable release, rpm.vercmp=$vercmp"
fi

# 2. The repository's own classifier still rejects the git snapshot and accepts
#    the non-git release.  It must not be relaxed for this convergence.
classifier_out="$(run_isolated '
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
rpm() {
    case "$*" in
        *"%{EVR}"*) printf "%s\n" "${MOCK_EVR:-}"; return 0 ;;
        *) return 0 ;;
    esac
}
MOCK_EVR="0.3.1-12.git.20260915.c6a5160.fc44"
if package_evr_is_stable quickshell; then echo git=ACCEPTED; else echo git=REJECTED; fi
MOCK_EVR="0.3.1-2.fc44"
if package_evr_is_stable quickshell; then echo stable=ACCEPTED; else echo stable=REJECTED; fi
' || true)"

if grep -q '^git=REJECTED$' <<< "$classifier_out" &&
   grep -q '^stable=ACCEPTED$' <<< "$classifier_out"; then
    pass "[isolated-test] existing package_evr_is_stable classifier rejects git snapshot and accepts the non-git release"
else
    fail "[isolated-test] package_evr_is_stable classifier misclassifies git/stable: $classifier_out"
fi

section "Quickshell Provenance: Candidate Validation Policy"

policy_out="$(run_isolated '
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/packages.sh"
approved="$QUICKSHELL_APPROVED_REPOID"
reason=""
if validate_quickshell_candidate quickshell 0 0.3.1 "12.git.20260915.c6a5160.fc44" x86_64 "$approved" reason >/dev/null; then echo git=ACCEPTED; else echo git=REJECTED; fi
reason=""
if validate_quickshell_candidate quickshell 0 0.3.1 2.fc44 x86_64 "$approved" reason >/dev/null; then echo stable=ACCEPTED; else echo stable=REJECTED; fi
reason=""
if validate_quickshell_candidate quickshell-git 0 0.3.1 1.fc44 x86_64 "$approved" reason >/dev/null; then echo name=ACCEPTED; else echo name=REJECTED; fi
reason=""
if validate_quickshell_candidate quickshell 0 0.3.1 2.fc44 x86_64 "copr:copr.fedorainfracloud.org:lionheartp:Hyprland" reason >/dev/null; then echo repo=ACCEPTED; else echo repo=REJECTED; fi
bad_arch=aarch64
[[ "$(uname -m)" == aarch64 ]] && bad_arch=x86_64
reason=""
if validate_quickshell_candidate quickshell 0 0.3.1 2.fc44 "$bad_arch" "$approved" reason >/dev/null; then echo arch=ACCEPTED; else echo arch=REJECTED; fi
reason=""
if validate_quickshell_candidate quickshell 0 0.3.1 2.fc44 noarch "$approved" reason >/dev/null; then echo noarch=ACCEPTED; else echo noarch=REJECTED; fi
reason=""
if validate_quickshell_candidate quickshell 0 0.3.1 2.fc44 x86_64 "$approved" reason >/dev/null; then echo approved_stable=ACCEPTED; else echo approved_stable=REJECTED; fi
for pre in "1.beta" "1.rc1" "1.nightly" "1.dev" "1.snapshot" "1^git20260209"; do
    reason=""
    if validate_quickshell_candidate quickshell 0 0.3.1 "$pre" x86_64 "$approved" reason >/dev/null; then
        printf "pre:%s=ACCEPTED\n" "$pre"
    else
        printf "pre:%s=REJECTED\n" "$pre"
    fi
done
' || true)"

policy_ok=1
for expected in \
    "git=REJECTED" \
    "stable=ACCEPTED" \
    "name=REJECTED" \
    "repo=REJECTED" \
    "arch=REJECTED" \
    "noarch=ACCEPTED" \
    "approved_stable=ACCEPTED" \
    "pre:1.beta=REJECTED" \
    "pre:1.rc1=REJECTED" \
    "pre:1.nightly=REJECTED" \
    "pre:1.dev=REJECTED" \
    "pre:1.snapshot=REJECTED" \
    "pre:1^git20260209=REJECTED"; do
    grep -Fqx -- "$expected" <<< "$policy_out" || policy_ok=0
done
if (( policy_ok )); then
    pass "[isolated-test] candidate policy rejects git/name/wrong-repo/wrong-arch/prerelease and accepts stable approved (noarch allowed)"
else
    fail "[isolated-test] candidate policy mismatch: $policy_out"
fi

section "Quickshell Provenance: Candidate Query Classification"

query_out="$(run_isolated '
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/packages.sh"
run_with_timeout() { shift 2; "$@"; }
dnf() {
    case "${MOCK_MODE:-}" in
        empty) exit 0 ;;
        malformed) printf "%s\n" "quickshell only three fields"; exit 0 ;;
        error) printf "%s\n" "No matching repositories" >&2; exit 2 ;;
        ok) printf "quickshell 0 0.3.1 2.fc44 x86_64 %s\n" "$QUICKSHELL_APPROVED_REPOID"; exit 0 ;;
    esac
}
for mode in empty malformed error ok; do
    MOCK_MODE="$mode"
    out=""
    rc=0
    out="$(query_quickshell_candidate "$QUICKSHELL_APPROVED_REPOID")" || rc=$?
    printf "case=%s rc=%s out=%s\n" "$mode" "$rc" "$out"
done
' || true)"

if grep -q '^case=empty rc=1 ' <<< "$query_out" &&
   grep -q '^case=malformed rc=3 ' <<< "$query_out" &&
   grep -q '^case=error rc=2 ' <<< "$query_out" &&
   grep -Fq "case=ok rc=0 out=quickshell 0 0.3.1 2.fc44 x86_64 $APPROVED_REPO" <<< "$query_out"; then
    pass "[isolated-test] candidate query distinguishes empty/unavailable/malformed/valid without ambiguity"
else
    fail "[isolated-test] candidate query status classification incorrect: $query_out"
fi

section "Quickshell Provenance: Transaction-Scoped Convergence"

# 5. Convergence of an installed package uses transaction-scoped distro-sync,
#    verifies the result, keeps every package operation bounded, and never
#    mutates global repository state.
converge_common='
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/packages.sh"
LOG="$(mktemp)"
rpm() {
    case "$*" in
        *"%{EVR}"*) printf "%s\n" "0.3.1-2.fc44"; return 0 ;;
        *"%{VERSION}"*) printf "%s\n" "0.3.1"; return 0 ;;
        *) return 0 ;;
    esac
}
sudo() { "$@"; }
run_with_timeout() {
    local t="$1" desc="$2"
    shift 2
    printf "TIMEOUT %s %s\n" "$t" "$desc" >> "$LOG"
    "$@"
}
mutation_count() { grep -Ec "^(DNF )?(distro-sync|install)( |$)" "$LOG" || true; }
'

converge_out="$(run_isolated "$converge_common"'
dnf() {
    printf "DNF %s\n" "$*" >> "$LOG"
    case "$*" in
        *repoquery*--installed*) printf "%s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *repoquery*) printf "quickshell 0 0.3.1 2.fc44 x86_64 %s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *distro-sync*) return 0 ;;
        *install*) return 0 ;;
    esac
    return 0
}
rc=0
install_approved_quickshell >/dev/null || rc=$?
printf "RC=%s\n" "$rc"
printf "FROM_REPO=%s\n" "$(grep -c -- "--from-repo=$QUICKSHELL_APPROVED_REPOID" "$LOG" || true)"
printf "DISTRO_SYNC=%s\n" "$(grep -c -- "distro-sync" "$LOG" || true)"
printf "GLOBAL_DISABLE=%s\n" "$(grep -Eic -- "--(disablerepo|disable-repo|enablerepo|exclude)" "$LOG" || true)"
timeouts_ok=1
while read -r tag val _rest; do
    [[ "$tag" == "TIMEOUT" ]] || continue
    if [[ ! "$val" =~ ^[0-9]+$ ]] || (( val <= 0 )); then timeouts_ok=0; fi
done < "$LOG"
printf "TIMEOUTS_OK=%s\n" "$timeouts_ok"
rm -f "$LOG"
' || true)"

if grep -q '^RC=0$' <<< "$converge_out" &&
   grep -q '^FROM_REPO=[1-9]' <<< "$converge_out" &&
   grep -q '^DISTRO_SYNC=[1-9]' <<< "$converge_out" &&
   grep -q '^GLOBAL_DISABLE=0$' <<< "$converge_out" &&
   grep -q '^TIMEOUTS_OK=1$' <<< "$converge_out"; then
    pass "[isolated-test] convergence uses transaction-scoped --from-repo plus distro-sync, verifies the result, keeps timeouts positive, and never disables repos globally"
else
    fail "[isolated-test] convergence invariants failed: $converge_out"
fi

# 6. If distro-sync cannot converge the installed snapshot, the explicit
#    allow-downgrade install fallback remains transaction-scoped.
fallback_out="$(run_isolated "$converge_common"'
dnf() {
    printf "DNF %s\n" "$*" >> "$LOG"
    case "$*" in
        *repoquery*--installed*) printf "%s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *repoquery*) printf "quickshell 0 0.3.1 2.fc44 x86_64 %s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *distro-sync*) return 1 ;;
        *install*) return 0 ;;
    esac
    return 0
}
rc=0
install_approved_quickshell >/dev/null || rc=$?
printf "RC=%s\n" "$rc"
printf "ALLOW_DOWNGRADE=%s\n" "$(grep -c -- "--allow-downgrade" "$LOG" || true)"
printf "FROM_REPO=%s\n" "$(grep -c -- "--from-repo=$QUICKSHELL_APPROVED_REPOID" "$LOG" || true)"
printf "MUTATIONS=%s\n" "$(mutation_count)"
rm -f "$LOG"
' || true)"

if grep -q '^RC=0$' <<< "$fallback_out" &&
   grep -q '^ALLOW_DOWNGRADE=[1-9]' <<< "$fallback_out" &&
   grep -q '^FROM_REPO=[1-9]' <<< "$fallback_out" &&
   grep -q '^MUTATIONS=2$' <<< "$fallback_out"; then
    pass "[isolated-test] failed distro-sync falls back to transaction-scoped install --allow-downgrade --from-repo"
else
    fail "[isolated-test] allow-downgrade fallback invariants failed: $fallback_out"
fi

# 7. A transaction that leaves the git snapshot installed must fail closed:
#    post-transaction verification is real, not assumed.
verify_out="$(run_isolated "$converge_common"'
dnf() {
    printf "DNF %s\n" "$*" >> "$LOG"
    case "$*" in
        *repoquery*--installed*) printf "%s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *repoquery*) printf "quickshell 0 0.3.1 2.fc44 x86_64 %s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *distro-sync*) return 0 ;;
        *install*) return 0 ;;
    esac
    return 0
}
# rpm still reports the git snapshot after the transaction.
rpm() {
    case "$*" in
        *"%{EVR}"*) printf "%s\n" "0.3.1-12.git.20260915.c6a5160.fc44"; return 0 ;;
        *"%{VERSION}"*) printf "%s\n" "0.3.1"; return 0 ;;
        *) return 0 ;;
    esac
}
rc=0
install_approved_quickshell >/dev/null || rc=$?
printf "RC=%s\n" "$rc"
rm -f "$LOG"
' || true)"

if grep -q '^RC=1$' <<< "$verify_out"; then
    pass "[isolated-test] post-transaction verification fails closed when the installed EVR remains a git snapshot"
else
    fail "[isolated-test] post-transaction git snapshot was incorrectly accepted: $verify_out"
fi

# 8-10. Unresolvable, invalid, or failing candidates must fail closed BEFORE any
#        mutation.
failclosed_common='
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/packages.sh"
LOG="$(mktemp)"
rpm() { return 0; }
sudo() { "$@"; }
run_with_timeout() { shift 2; "$@"; }
mutation_count() { grep -Ec "^(DNF )?(distro-sync|install)( |$)" "$LOG" || true; }
'

invalid_out="$(run_isolated "$failclosed_common"'
dnf() {
    printf "DNF %s\n" "$*" >> "$LOG"
    case "$*" in
        *repoquery*) printf "quickshell 0 0.3.1 12.git.20260915.c6a5160.fc44 x86_64 %s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
    esac
    return 0
}
rc=0
install_approved_quickshell >/dev/null || rc=$?
printf "RC=%s\n" "$rc"
printf "MUTATIONS=%s\n" "$(mutation_count)"
rm -f "$LOG"
' || true)"

unresolvable_out="$(run_isolated "$failclosed_common"'
dnf() {
    printf "DNF %s\n" "$*" >> "$LOG"
    return 0
}
rc=0
install_approved_quickshell >/dev/null || rc=$?
printf "RC=%s\n" "$rc"
printf "MUTATIONS=%s\n" "$(mutation_count)"
rm -f "$LOG"
' || true)"

error_out="$(run_isolated "$failclosed_common"'
dnf() {
    printf "DNF %s\n" "$*" >> "$LOG"
    printf "%s\n" "No matching repositories" >&2
    return 2
}
rc=0
install_approved_quickshell >/dev/null || rc=$?
printf "RC=%s\n" "$rc"
printf "MUTATIONS=%s\n" "$(mutation_count)"
rm -f "$LOG"
' || true)"

if grep -q '^RC=1$' <<< "$invalid_out" && grep -q '^MUTATIONS=0$' <<< "$invalid_out" &&
   grep -q '^RC=1$' <<< "$unresolvable_out" && grep -q '^MUTATIONS=0$' <<< "$unresolvable_out" &&
   grep -q '^RC=1$' <<< "$error_out" && grep -q '^MUTATIONS=0$' <<< "$error_out"; then
    pass "[isolated-test] invalid, unresolvable, and failing candidates all fail closed before any mutation"
else
    fail "[isolated-test] fail-closed-before-mutation violated: invalid='$invalid_out' unresolvable='$unresolvable_out' error='$error_out'"
fi

section "Quickshell Provenance: Adapter Idempotency and Convergence"

# 11. A second run with the stable approved package already installed is an
#     idempotent KEEP/no-op: no package transaction is issued.
idempotent_out="$(run_isolated '
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/packages.sh"
LOG="$(mktemp)"
rpm() {
    case "$*" in
        *"%{EVR}"*) printf "%s\n" "0.3.1-2.fc44"; return 0 ;;
        *"%{VERSION}"*) printf "%s\n" "0.3.1"; return 0 ;;
        *) return 0 ;;
    esac
}
dnf() {
    printf "DNF %s\n" "$*" >> "$LOG"
    case "$*" in
        *repoquery*--installed*) printf "%s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *repoquery*) printf "quickshell 0 0.3.1 2.fc44 x86_64 %s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
    esac
    return 0
}
sudo() { "$@"; }
run_with_timeout() { shift 2; "$@"; }
rc=0
install_aurelia_package_group >/dev/null || rc=$?
printf "RC=%s\n" "$rc"
printf "MUTATIONS=%s\n" "$(grep -Ec "^(DNF )?(distro-sync|install)( |$)" "$LOG" || true)"
printf "DETECT=%s\n" "$(detect_aurelia_package_group && echo 0 || echo 1)"
rm -f "$LOG"
' || true)"

if grep -q '^RC=0$' <<< "$idempotent_out" &&
   grep -q '^MUTATIONS=0$' <<< "$idempotent_out" &&
   grep -q '^DETECT=0$' <<< "$idempotent_out"; then
    pass "[isolated-test] stable approved Quickshell is an idempotent KEEP/no-op on re-run, and detection reports satisfied"
else
    fail "[isolated-test] idempotent KEEP invariant failed: $idempotent_out"
fi

# 12. The adapter converges an already-installed higher-EVR git snapshot to the
#     approved stable build (the live-host state) instead of failing closed.
adapter_out="$(run_isolated '
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/packages.sh"
LOG="$(mktemp)"
STATE="$(mktemp)"
printf "%s\n" "0.3.1-12.git.20260915.c6a5160.fc44" > "$STATE"
rpm() {
    case "$*" in
        *"%{EVR}"*) cat "$STATE"; return 0 ;;
        *"%{VERSION}"*) printf "%s\n" "0.3.1"; return 0 ;;
        *) return 0 ;;
    esac
}
dnf() {
    printf "DNF %s\n" "$*" >> "$LOG"
    case "$*" in
        *repoquery*--installed*) printf "%s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *repoquery*) printf "quickshell 0 0.3.1 2.fc44 x86_64 %s\n" "$QUICKSHELL_APPROVED_REPOID"; return 0 ;;
        *distro-sync*) printf "%s\n" "0.3.1-2.fc44" > "$STATE"; return 0 ;;
        *install*) printf "%s\n" "0.3.1-2.fc44" > "$STATE"; return 0 ;;
    esac
    return 0
}
sudo() { "$@"; }
run_with_timeout() { shift 2; "$@"; }
git_detect=0
detect_aurelia_package_group || git_detect=1
rc=0
install_aurelia_package_group >/dev/null || rc=$?
printf "GIT_DETECT=%s\n" "$git_detect"
printf "RC=%s\n" "$rc"
printf "DISTRO_SYNC=%s\n" "$(grep -c -- "distro-sync" "$LOG" || true)"
printf "FINAL_EVR=%s\n" "$(cat "$STATE")"
rm -f "$LOG" "$STATE"
' || true)"

if grep -q '^GIT_DETECT=1$' <<< "$adapter_out" &&
   grep -q '^RC=0$' <<< "$adapter_out" &&
   grep -q '^DISTRO_SYNC=[1-9]' <<< "$adapter_out" &&
   grep -q "^FINAL_EVR=$STABLE_EVR$" <<< "$adapter_out"; then
    pass "[isolated-test] adapter detects the non-compliant git snapshot and converges it to the approved stable release"
else
    fail "[isolated-test] adapter convergence from git snapshot failed: $adapter_out"
fi

section "Quickshell Provenance: Source Invariants"

if grep -q 'enable_copr "lionheartp/Hyprland"' "$WORKSTATION_ROOT/modules/repositories.sh"; then
    pass "[static] lionheartp/Hyprland COPR remains independently enabled for Hyprland"
else
    fail "[static] lionheartp/Hyprland COPR was removed or disabled"
fi

owned_modules=(
    "$WORKSTATION_ROOT/modules/lib/packages.sh"
    "$WORKSTATION_ROOT/modules/packages.sh"
)
if grep -q -- '--from-repo=' "${owned_modules[@]}" &&
   grep -q -- 'distro-sync' "${owned_modules[@]}" &&
   grep -q -- '--allow-downgrade' "${owned_modules[@]}"; then
    pass "[static] production convergence uses transaction-scoped --from-repo, distro-sync, and allow-downgrade"
else
    fail "[static] production convergence is missing transaction-scoped convergence flags"
fi

if grep -Eq -- '(^|[[:space:]])--(disablerepo|disable-repo|exclude)' "${owned_modules[@]}"; then
    fail "[static] global repository disable/priority mutation found in owned package modules"
else
    pass "[static] owned package modules never disable, deprioritise, or exclude a repository globally"
fi

if grep -Eq -- 'dnf[[:space:]]+(upgrade|update)[[:space:]].*quickshell' "${owned_modules[@]}"; then
    fail "[static] unrestricted dnf upgrade/update of quickshell found"
else
    pass "[static] no unrestricted dnf upgrade/update of quickshell exists"
fi

if grep -Eiq -- 'nogpgcheck|gpgcheck[[:space:]]*=[[:space:]]*0' "${owned_modules[@]}"; then
    fail "[static] GPG signature verification is weakened in owned package modules"
else
    pass "[static] GPG signature verification remains enabled for Quickshell transactions"
fi
