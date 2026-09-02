#!/usr/bin/env bash

# DNF and RPM package manager helpers.

package_installed() {
    rpm -q "$1" >/dev/null 2>&1 || rpm -q --whatprovides "$1" >/dev/null 2>&1
}

detect_dnf_lock_holders() {
    local log_file="${1:-}"
    local holders=()

    # 1. First extract lock holder processes directly reported by DNF if present in output log
    if [[ -n "$log_file" && -f "$log_file" ]]; then
        local in_lock_block=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ Waiting\ for\ a\ lock\ on || "$line" =~ The\ following\ processes\ are\ currently\ accessing\ it: ]]; then
                in_lock_block=1
                continue
            fi
            if (( in_lock_block == 1 )); then
                if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.+)$ ]]; then
                    holders+=("PID ${BASH_REMATCH[1]}: ${BASH_REMATCH[2]}")
                elif [[ -n "$line" && ! "$line" =~ ^[[:space:]] ]]; then
                    in_lock_block=0
                fi
            fi
        done < "$log_file"
    fi

    # 2. If no holders parsed from output, inspect process table for concurrent dnf/rpm processes
    if [[ ${#holders[@]} -eq 0 ]] && command_exists ps; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] || continue
            local pid cmd
            pid="$(awk '{print $1}' <<< "$line")"
            cmd="$(cut -d' ' -f2- <<< "$line")"
            if [[ "$pid" != "$$" && "$pid" != "${ACTIVE_TIMEOUT_PID:-}" ]]; then
                holders+=("PID ${pid}: ${cmd}")
            fi
        done < <(ps -eo pid,args --no-headers 2>/dev/null | grep -E '\b(dnf|dnf5|rpm|rpmbuild|packagekitd)\b' | grep -v 'grep' || true)
    fi

    if [[ ${#holders[@]} -gt 0 ]]; then
        printf '%s\n' "${holders[@]}"
    fi
}

run_dnf_command() {
    local timeout_seconds="$1"
    local description="$2"
    shift 2

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
        local lock_holders
        lock_holders="$(detect_dnf_lock_holders "$log_tmp")"
        if [[ -n "$lock_holders" ]]; then
            error "DNF operation timed out after ${timeout_seconds}s due to package manager lock contention for: ${description}"
            error "Active package manager process(es):"
            while IFS= read -r holder; do
                error "  - $holder"
            done <<< "$lock_holders"
        else
            error "DNF operation timed out after ${timeout_seconds}s for: ${description}"
        fi
        rm -f "$log_tmp"
        return 124
    elif (( status != 0 )); then
        local lock_holders
        lock_holders="$(detect_dnf_lock_holders "$log_tmp")"
        if [[ -n "$lock_holders" ]]; then
            warn "DNF operation encountered lock contention for: ${description}"
            while IFS= read -r holder; do
                warn "  - $holder"
            done <<< "$lock_holders"
        fi
    fi

    rm -f "$log_tmp"
    return "$status"
}

package_available() {
    local package="$1"
    local output=""
    local status=0

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
