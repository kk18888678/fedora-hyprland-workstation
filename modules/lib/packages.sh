#!/usr/bin/env bash

# DNF and RPM package manager helpers.

package_installed() {
    rpm -q "$1" >/dev/null 2>&1 || rpm -q --whatprovides "$1" >/dev/null 2>&1
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
    if command -v ps >/dev/null 2>&1; then
        local ps_out
        ps_out="$(ps -eo pid,args --no-headers 2>/dev/null)" || ps_out=""
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
    log_tmp="$(mktemp)"
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
            dnf -q repoquery --available --qf '%{name}' "$package" 2>/dev/null
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
            dnf -q repoquery --available --whatprovides "$package" --qf '%{name}' 2>/dev/null
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
