#!/usr/bin/env bash

# DNF and RPM package manager helpers.

package_installed() {
    rpm -q "$1" >/dev/null || rpm -q --whatprovides "$1" >/dev/null
}

package_command_owned() {
    local package="$1"
    local command_name="$2"
    local command_path
    local owner_name

    command_path="$(command -v "$command_name"  || true)"
    [[ "$command_path" == /* && -x "$command_path" && ! -L "$command_path" ]] || return 1

    owner_name="$(rpm -qf --qf '%{NAME}\n' -- "$command_path"  || true)"
    [[ "$owner_name" == "$package" ]]
}

package_evr_is_stable() {
    local package="$1"
    local evr

    package_installed "$package" || return 1
    evr="$(rpm -q --qf '%{EVR}' "$package"  || true)"
    [[ -n "$evr" ]] || return 1

    case "${evr,,}" in
        *alpha*|*beta*|*rc*|*preview*|*nightly*|*snapshot*|*git*|*dev*)
            return 1
            ;;
    esac
}
detect_dnf_lock_diagnostics() {
    local log_file="${1:-}"
    local lock_holders=()
    local concurrent_procs=()

    # 1. First extract verified lock holder processes directly reported by DNF in output log
    if [[ -n "$log_file" && -f "$log_file" ]]; then
        local in_lock_block=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ Waiting\ for\ a\ lock\ on || "$line" =~ The\ following\ processes\ are\ currently\ accessing\ it: ]]; then
                in_lock_block=1
                continue
            fi
            if (( in_lock_block == 1 )); then
                if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.+)$ ]]; then
                    lock_holders+=("PID ${BASH_REMATCH[1]}: ${BASH_REMATCH[2]}")
                elif [[ -n "$line" && ! "$line" =~ ^[[:space:]] ]]; then
                    in_lock_block=0
                fi
            fi
        done < "$log_file"
    fi

    if [[ ${#lock_holders[@]} -gt 0 ]]; then
        printf 'LOCK_HOLDERS\n'
        printf '%s\n' "${lock_holders[@]}"
        return 0
    fi

    # 2. Process-table fallback: inspect for concurrent dnf/rpm processes without fragile pipes
    if command -v ps >/dev/null; then
        local ps_out
        ps_out="$(ps -eo pid,args --no-headers )" || ps_out=""
        if [[ -n "$ps_out" ]]; then
            while IFS= read -r proc_line || [[ -n "$proc_line" ]]; do
                [[ -n "$proc_line" ]] || continue
                local pid cmd
                read -r pid cmd <<< "$proc_line"
                if [[ "$pid" != "$$" && "$pid" != "${ACTIVE_TIMEOUT_PID:-}" ]]; then
                    if [[ "$cmd" =~ (^|[[:space:]/])(dnf|dnf5|rpm|rpmbuild|packagekitd)([[:space:]]|$) ]]; then
                        concurrent_procs+=("PID ${pid}: ${cmd}")
                    fi
                fi
            done <<< "$ps_out"
        fi
    fi

    if [[ ${#concurrent_procs[@]} -gt 0 ]]; then
        printf 'CONCURRENT_PROCS\n'
        printf '%s\n' "${concurrent_procs[@]}"
        return 0
    fi

    return 0
}

detect_dnf_lock_holders() {
    local log_file="${1:-}"
    local diag
    diag="$(detect_dnf_lock_diagnostics "$log_file")"
    if [[ -n "$diag" ]]; then
        sed -E '1{/^(LOCK_HOLDERS|CONCURRENT_PROCS)$/d}' <<< "$diag"
    fi
}

run_dnf_command() {
    local timeout_seconds="$1"
    local description="$2"
    shift 2

    if declare -F check_repository_trust >/dev/null; then
        if ! check_repository_trust; then
            error "Refusing DNF operation: repository trust is not converged for: ${description}"
            return 1
        fi
    fi

    local log_tmp
    if ! log_tmp="$(mktemp)"; then
        error "Could not create a secure temporary DNF log for: ${description}"
        return 1
    fi
    local status=0

    # Run bounded command with output captured to log_tmp
    run_with_timeout "$timeout_seconds" "$description" "$@" > "$log_tmp" 2>&1 || status=$?

    # Always output captured command log to standard output/stderr for installer logging
    if [[ -f "$log_tmp" && -s "$log_tmp" ]]; then
        cat "$log_tmp"
    fi

    if (( status == 124 )); then
        local diag
        diag="$(detect_dnf_lock_diagnostics "$log_tmp")"
        local header
        header="$(awk 'NR==1{print}' <<< "$diag")"
        local body
        body="$(sed -E '1{/^(LOCK_HOLDERS|CONCURRENT_PROCS)$/d}' <<< "$diag")"

        if [[ "$header" == "LOCK_HOLDERS" && -n "$body" ]]; then
            error "DNF operation timed out after ${timeout_seconds}s due to package manager lock contention for: ${description}"
            error "Active package manager lock holder(s):"
            while IFS= read -r holder; do
                error "  - $holder"
            done <<< "$body"
        elif [[ "$header" == "CONCURRENT_PROCS" && -n "$body" ]]; then
            error "DNF operation timed out after ${timeout_seconds}s for: ${description}"
            error "Concurrent package manager process(es):"
            while IFS= read -r proc; do
                error "  - $proc"
            done <<< "$body"
        else
            error "DNF operation timed out after ${timeout_seconds}s for: ${description}"
        fi
        rm -f "$log_tmp"
        return 124
    elif (( status != 0 )); then
        local diag
        diag="$(detect_dnf_lock_diagnostics "$log_tmp")"
        local header
        header="$(awk 'NR==1{print}' <<< "$diag")"
        local body
        body="$(sed -E '1{/^(LOCK_HOLDERS|CONCURRENT_PROCS)$/d}' <<< "$diag")"

        if [[ "$header" == "LOCK_HOLDERS" && -n "$body" ]]; then
            warn "DNF operation encountered lock contention for: ${description}"
            warn "Active package manager lock holder(s):"
            while IFS= read -r holder; do
                warn "  - $holder"
            done <<< "$body"
        elif [[ "$header" == "CONCURRENT_PROCS" && -n "$body" ]]; then
            warn "DNF operation encountered error (${status}) with concurrent package manager process(es):"
            while IFS= read -r proc; do
                warn "  - $proc"
            done <<< "$body"
        fi
    fi

    rm -f "$log_tmp"
    return "$status"
}

package_available() {
    local package="$1"
    local output=""
    local status=0

    if declare -F check_repository_trust >/dev/null; then
        if ! check_repository_trust; then
            error "Package availability query blocked: repository trust is not converged for '$package'."
            return 2
        fi
    fi

    output="$(
        run_with_timeout "$TIMEOUT_METADATA_SECONDS" "repoquery $package" \
            dnf -q repoquery --available --qf '%{name}' "$package"
    )" || status=$?

    if (( status == 124 )); then
        error "Package availability query timed out for '$package'."
        return 2
    elif (( status != 0 )); then
        error "Package availability query failed for '$package' (status $status)."
        return 2
    fi

    if [[ -n "$output" ]]; then
        return 0
    fi

    output="$(
        run_with_timeout "$TIMEOUT_METADATA_SECONDS" "repoquery whatprovides $package" \
            dnf -q repoquery --available --whatprovides "$package" --qf '%{name}'
    )" || status=$?

    if (( status == 124 )); then
        error "Package provides query timed out for '$package'."
        return 2
    elif (( status != 0 )); then
        error "Package provides query failed for '$package' (status $status)."
        return 2
    fi

    if [[ -n "$output" ]]; then
        return 0
    fi

    return 1
}

dnf_makecache() {
    run_dnf_command "$TIMEOUT_METADATA_SECONDS" "dnf makecache" \
        sudo dnf makecache --refresh
}

dnf_install() {
    run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" "dnf install $*" \
        sudo dnf install -y "$@"
}

validate_dnf_source_id() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}$ ]]
}

package_available_from_repo() {
    local repo="$1"
    local package="$2"
    local output=""
    local status=0

    validate_dnf_source_id "$repo" || {
        error "Invalid DNF source ID: $repo"
        return 2
    }
    output="$(
        run_with_timeout "$TIMEOUT_METADATA_SECONDS" "repoquery $repo $package" \
            dnf -q repoquery --available --repoid "$repo" --qf $'%{name}\n' "$package"
    )" || status=$?
    if (( status != 0 )); then
        if (( status == 124 )); then
            error "Package availability query timed out for '$package' from '$repo'."
        else
            error "Package availability query failed for '$package' from '$repo' (status $status)."
        fi
        return 2
    fi
    grep -Fxq -- "$package" <<< "$output"
}

dnf_install_packages_from_repo() {
    local repo="$1"
    shift
    local packages=("$@")

    validate_dnf_source_id "$repo" || {
        error "Invalid DNF source ID: $repo"
        return 1
    }
    (( ${#packages[@]} > 0 )) || return 0
    run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" "dnf install from $repo: ${packages[*]}" \
        sudo dnf install "--from-repo=$repo" -y "${packages[@]}"
}

install_dnf_packages() {
    local packages=("$@")
    local missing=()
    local package

    for package in "${packages[@]}"; do
        if ! package_installed "$package"; then
            missing+=("$package")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        info "DNF packages already installed."
        return 0
    fi

    info "Installing ${#missing[@]} package(s): ${missing[*]}"

    local status=0
    dnf_install "${missing[@]}" || status=$?
    if (( status == 124 )); then
        error "Package installation timed out / encountered unreleased lock contention."
        return 1
    elif (( status != 0 )); then
        run_with_retry "dnf install ${missing[*]}" dnf_install "${missing[@]}"
    fi
}

###############################################################################
# Quickshell provenance enforcement
###############################################################################
#
# The lionheartp/Hyprland COPR is required for Hyprland and also publishes
# Quickshell Git snapshots whose EVR outranks the approved stable release.  The
# Hyprland COPR is therefore never disabled, deprioritised, or excluded; only
# the Quickshell transaction itself is scoped to the approved release source
# below.  The approved source is the documented stable release COPR.

QUICKSHELL_PACKAGE_NAME="quickshell"
QUICKSHELL_APPROVED_REPOID="copr:copr.fedorainfracloud.org:errornointernet:quickshell"

# Query the approved repository for a single, explicit Quickshell candidate.
# The transaction is never widened to the whole repository set.
#
# Status:
#   0 -> exact candidate printed as "name epoch version release arch repoid"
#   1 -> query succeeded but no candidate was found
#   2 -> repository query failed or is unavailable
#   3 -> query output was malformed
query_quickshell_candidate() {
    local repoid="${1:-$QUICKSHELL_APPROVED_REPOID}"
    local arch
    arch="$(uname -m || printf 'x86_64')"

    validate_dnf_source_id "$repoid" || {
        error "Invalid DNF source ID for Quickshell candidate query: $repoid"
        return 2
    }

    local err_file=""
    err_file="$(mktemp "${TMPDIR:-/tmp}/quickshell-query.XXXXXX" || true)"

    local query_out=""
    local status=0
    if [[ -n "$err_file" ]]; then
        query_out="$(
            run_with_timeout "$TIMEOUT_METADATA_SECONDS" "repoquery quickshell candidate from $repoid" \
                dnf -q repoquery --repo="$repoid" --arch="$arch,noarch" --latest-limit=1 \
                    "$QUICKSHELL_PACKAGE_NAME" \
                    --queryformat '%{name} %{epoch} %{version} %{release} %{arch} %{repoid}\n' \
                    2>"$err_file"
        )" || status=$?
    else
        query_out="$(
            run_with_timeout "$TIMEOUT_METADATA_SECONDS" "repoquery quickshell candidate from $repoid" \
                dnf -q repoquery --repo="$repoid" --arch="$arch,noarch" --latest-limit=1 \
                    "$QUICKSHELL_PACKAGE_NAME" \
                    --queryformat '%{name} %{epoch} %{version} %{release} %{arch} %{repoid}\n'
        )" || status=$?
    fi

    local bounded_err=""
    if [[ -n "$err_file" && -f "$err_file" ]]; then
        bounded_err="$(head -n 2 "$err_file" | tr '\n' ' ' | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//')"
        rm -f -- "$err_file"
    fi

    if (( status != 0 )); then
        if [[ "$bounded_err" == *"No matching repositories"* ]]; then
            error "Approved Quickshell repository is unavailable: $repoid"
        else
            error "Failed to query approved Quickshell repository: $repoid"
        fi
        [[ -n "$bounded_err" ]] && error "  dnf repoquery exited $status: $bounded_err"
        return 2
    fi

    query_out="$(printf '%s\n' "$query_out" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "$query_out" ]] || return 1

    local first_line
    first_line="$(head -n 1 <<< "$query_out")"
    local c_name="" c_epoch="" c_ver="" c_rel="" c_arch="" c_repo="" extra=""
    read -r c_name c_epoch c_ver c_rel c_arch c_repo extra <<< "$first_line"
    if [[ -z "$c_name" || -z "$c_epoch" || -z "$c_ver" || -z "$c_rel" \
          || -z "$c_arch" || -z "$c_repo" || -n "$extra" ]]; then
        error "Failed to parse Quickshell candidate from $repoid: malformed repoquery output: '$first_line'"
        return 3
    fi

    printf '%s\n' "$first_line"
    return 0
}

# Validate a Quickshell candidate against the repository provenance policy:
# package identity, architecture, approved repository, and stable release
# class (using the repository's existing classifier).  The optional final
# argument receives the rejection reason.  No mutation is performed here.
validate_quickshell_candidate() {
    local cand_name="$1"
    local cand_epoch="$2"
    local cand_version="$3"
    local cand_release="$4"
    local cand_arch="$5"
    local cand_repoid="$6"
    local out_reason_var="${7:-}"
    local approved_repoid="$QUICKSHELL_APPROVED_REPOID"
    local reason=""

    local host_arch
    host_arch="$(uname -m || printf 'x86_64')"

    if [[ "$cand_name" != "$QUICKSHELL_PACKAGE_NAME" ]]; then
        reason="package identity '$cand_name' is not the approved '$QUICKSHELL_PACKAGE_NAME'"
    elif [[ ! "$cand_epoch" =~ ^[0-9]+$ ]]; then
        reason="epoch '$cand_epoch' is not a non-negative integer"
    elif [[ -n "$cand_arch" && "$cand_arch" != "$host_arch" && "$cand_arch" != "noarch" ]]; then
        reason="architecture '$cand_arch' does not match host architecture '$host_arch'"
    elif [[ "$cand_repoid" != "$approved_repoid" ]]; then
        reason="repository '$cand_repoid' is not the approved repository '$approved_repoid'"
    else
        local full_ver="${cand_version}-${cand_release}"
        local tag_class="stable"
        if declare -F classify_release_tag >/dev/null; then
            tag_class="$(classify_release_tag "$full_ver")"
        elif [[ "${full_ver,,}" =~ (\^|\.git|snapshot|nightly|alpha|beta|rc|preview|dev) ]]; then
            tag_class="prerelease"
        fi
        if [[ "$tag_class" != "stable" ]]; then
            reason="release '$full_ver' is not a stable release class (classified as $tag_class)"
        fi
    fi

    if [[ -n "$reason" ]]; then
        [[ -n "$out_reason_var" ]] && printf -v "$out_reason_var" '%s' "$reason"
        error "Rejected Quickshell candidate from ${cand_repoid:-unknown}:"
        error "  package: ${cand_name:-unknown}"
        error "  version: ${cand_version:-unknown}-${cand_release:-unknown}"
        error "  reason: ${reason}"
        return 1
    fi

    info "Quickshell candidate accepted: ${cand_name}-${cand_version}-${cand_release}.${cand_arch} from ${cand_repoid}"
    return 0
}

# Return success only when the installed Quickshell records the approved
# repository as its origin.  Provenance is read from DNF, never inferred from
# vendor strings or the enabled repository set.  Fails closed on any error.
quickshell_installed_from_approved_repo() {
    local approved_repoid="$QUICKSHELL_APPROVED_REPOID"
    local from_repo=""
    local status=0

    package_installed "$QUICKSHELL_PACKAGE_NAME" || return 1

    from_repo="$(
        run_with_timeout "$TIMEOUT_METADATA_SECONDS" "repoquery installed quickshell origin" \
            dnf -q repoquery --installed --queryformat '%{from_repo}\n' "$QUICKSHELL_PACKAGE_NAME"
    )" || status=$?

    (( status == 0 )) || return 1
    from_repo="$(printf '%s\n' "$from_repo" | tr -d '\r' | head -n 1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ "$from_repo" == "$approved_repoid" ]]
}

# Full installed-state policy: present, stable release class, approved origin.
quickshell_installed_is_compliant() {
    package_installed "$QUICKSHELL_PACKAGE_NAME" || return 1
    package_evr_is_stable "$QUICKSHELL_PACKAGE_NAME" || return 1
    quickshell_installed_from_approved_repo || return 1
}

# Convergence entry point.  A validated candidate is resolved from the
# approved repository only.  An already-installed package (including a
# higher-EVR Git snapshot) is converged with a transaction-scoped
# distro-sync, falling back to an explicit allow-downgrade install of the
# validated NEVRA.  Installation is never attempted before the candidate has
# been validated.  Failure to resolve or validate the candidate fails closed
# before any mutation.
install_approved_quickshell() {
    local approved_repoid="$QUICKSHELL_APPROVED_REPOID"

    validate_dnf_source_id "$approved_repoid" || {
        error "Invalid approved Quickshell repository id: $approved_repoid"
        return 1
    }

    # 1. Resolve the single candidate from the approved repository only.
    local cand_line=""
    local q_status=0
    cand_line="$(query_quickshell_candidate "$approved_repoid")" || q_status=$?
    if (( q_status == 1 )) || { (( q_status == 0 )) && [[ -z "$cand_line" ]]; }; then
        error "Cannot converge Quickshell: no candidate found in approved repository: $approved_repoid"
        return 1
    elif (( q_status != 0 )); then
        error "Cannot converge Quickshell: candidate resolution failed for approved repository: $approved_repoid"
        return 1
    fi

    local c_name c_epoch c_ver c_rel c_arch c_repo
    read -r c_name c_epoch c_ver c_rel c_arch c_repo <<< "$cand_line"

    # 2. Validate the candidate BEFORE any package mutation.
    local reject_reason=""
    if ! validate_quickshell_candidate "$c_name" "$c_epoch" "$c_ver" "$c_rel" "$c_arch" "$c_repo" reject_reason; then
        error "Pre-install validation failed for Quickshell candidate (${reject_reason:-unknown reason}); refusing package mutation."
        return 1
    fi

    local cand_nevra="${c_name}-${c_ver}-${c_rel}.${c_arch}"
    if [[ -n "$c_epoch" && "$c_epoch" != "0" ]]; then
        cand_nevra="${c_name}-${c_epoch}:${c_ver}-${c_rel}.${c_arch}"
    fi

    # 3. Converge or install, always transaction-scoped to the approved repo.
    local status=0
    if package_installed "$QUICKSHELL_PACKAGE_NAME"; then
        info "Converging installed Quickshell to approved stable release $cand_nevra from $approved_repoid."
        # distro-sync is scoped to the approved repository.  If it cannot
        # resolve, an explicit allow-downgrade install of the validated NEVRA
        # is the fallback.  Both remain transaction-scoped; no global
        # repository state is changed.
        if ! run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" \
                "dnf distro-sync quickshell from $approved_repoid" \
                sudo dnf distro-sync -y "--from-repo=$approved_repoid" "$QUICKSHELL_PACKAGE_NAME"; then
            run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" \
                "dnf install --allow-downgrade $cand_nevra" \
                sudo dnf install -y --allow-downgrade "--from-repo=$approved_repoid" "$cand_nevra" || status=$?
        fi
    else
        info "Installing Quickshell $cand_nevra from approved repository: $approved_repoid"
        run_dnf_command "$TIMEOUT_PACKAGE_SECONDS" \
            "dnf install $cand_nevra" \
            sudo dnf install -y "--from-repo=$approved_repoid" "$cand_nevra" || status=$?
    fi

    if (( status != 0 )); then
        error "Failed to converge Quickshell from approved repository: $approved_repoid"
        return "$status"
    fi

    # 4. Verify the resulting installed package is stable AND from the
    #    approved repository.  Fail closed if either property is unmet.
    if ! quickshell_installed_is_compliant; then
        error "Post-install verification failed: installed Quickshell is not a stable build from '$approved_repoid'."
        return 1
    fi

    return 0
}
