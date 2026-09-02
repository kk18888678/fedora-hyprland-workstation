#!/usr/bin/env bash

# DNF and RPM package manager helpers.

package_installed() {
    rpm -q "$1" >/dev/null 2>&1 || rpm -q --whatprovides "$1" >/dev/null 2>&1
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
    run_with_timeout "$TIMEOUT_METADATA_SECONDS" "dnf makecache" \
        sudo dnf makecache --refresh
}

dnf_install() {
    run_with_timeout "$TIMEOUT_PACKAGE_SECONDS" "dnf install $*" \
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

    run_with_retry "dnf install ${missing[*]}" dnf_install "${missing[@]}"
}
