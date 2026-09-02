#!/usr/bin/env bash

# Upstream artifact provisioning, verification, and archive safety.

load_pinned_versions() {
    local versions_file="${SCRIPT_DIR:-$(pwd -P)}/config/versions.conf"

    [[ -f "$versions_file" ]] ||
        die "Pinned versions file is missing: $versions_file"

    # shellcheck source=/dev/null
    source "$versions_file"
}

download_and_verify_artifact() {
    local url="$1"
    local expected_sha512="$2"
    local output_file="$3"
    local label="$4"

    [[ -n "$url" ]] || {
        error "Download URL is required for $label."
        return 1
    }

    [[ "$url" =~ ^https:// ]] || {
        error "Refusing non-HTTPS download URL for ${label}: $url"
        return 1
    }

    [[ -n "$expected_sha512" ]] || {
        error "Expected SHA-512 checksum is required for $label."
        return 1
    }

    info "Downloading $label."

    if ! run_with_retry "download $label" \
        run_with_timeout "$TIMEOUT_DOWNLOAD_SECONDS" "download $label" \
        curl -fsSL -o "$output_file" "$url"; then
        error "Failed to download $label from $url."
        return 1
    fi

    local actual_sha512
    actual_sha512="$(sha512sum "$output_file" | cut -d' ' -f1 || true)"

    if [[ "$actual_sha512" != "$expected_sha512" ]]; then
        error "Checksum mismatch for ${label}: expected ${expected_sha512}, got ${actual_sha512:-none}."
        return 1
    fi

    info "Checksum verified for $label."
    return 0
}

provision_verified_binary() {
    local url="$1"
    local expected_sha512="$2"
    local destination="$3"
    local label="$4"
    local as_root="${5:-false}"

    local staging_dir
    staging_dir="$(mktemp -d)"
    local staging_file="$staging_dir/$(basename "$destination")"

    if ! download_and_verify_artifact "$url" "$expected_sha512" "$staging_file" "$label"; then
        rm -rf "$staging_dir"
        return 1
    fi

    ensure_directory "$(dirname "$destination")"

    if is_true "$as_root"; then
        sudo install -D -m 0755 "$staging_file" "$destination"
    else
        install -D -m 0755 "$staging_file" "$destination"
    fi

    rm -rf "$staging_dir"

    if [[ ! -x "$destination" ]]; then
        error "$label was not executable after installation at $destination."
        return 1
    fi

    info "$label installed successfully."
    return 0
}

provision_verified_archive() {
    local url="$1"
    local expected_sha512="$2"
    local destination="$3"
    local expected_members_arg="$4"
    local label="$5"
    local as_root="${6:-false}"

    [[ -n "$expected_members_arg" ]] || {
        error "Explicit expected archive member(s) must be specified for $label."
        return 1
    }

    local staging_dir
    staging_dir="$(mktemp -d)"
    local staging_archive="$staging_dir/archive"

    if ! download_and_verify_artifact "$url" "$expected_sha512" "$staging_archive" "$label"; then
        rm -rf "$staging_dir"
        return 1
    fi

    local extracted_dir="$staging_dir/extracted"
    mkdir -p "$extracted_dir"

    # 1. Structural pre-extraction inspection against directory traversal / absolute paths
    if [[ "$url" == *.zip ]]; then
        local zip_members=()
        if command_exists unzip; then
            mapfile -t zip_members < <(unzip -Z1 "$staging_archive" 2>/dev/null || true)
        elif command_exists 7z; then
            mapfile -t zip_members < <(7z l -ba -slt "$staging_archive" 2>/dev/null | grep '^Path = ' | sed 's/^Path = //' || true)
        fi

        local member
        for member in "${zip_members[@]}"; do
            if [[ "$member" == /* || "$member" == *../* || "$member" == *..\\* || "$member" == *.. ]]; then
                rm -rf "$staging_dir"
                error "Archive for $label contains forbidden path or traversal: $member"
                return 1
            fi
        done

        if ! (7z x -y "$staging_archive" -o"$extracted_dir" >/dev/null 2>&1 || unzip -q -o "$staging_archive" -d "$extracted_dir" >/dev/null 2>&1); then
            rm -rf "$staging_dir"
            error "Failed to extract ZIP archive for $label."
            return 1
        fi
    else
        local tar_members=()
        mapfile -t tar_members < <(tar -tf "$staging_archive" 2>/dev/null || true)

        local member
        for member in "${tar_members[@]}"; do
            if [[ "$member" == /* || "$member" == *../* || "$member" == *.. ]]; then
                rm -rf "$staging_dir"
                error "Archive for $label contains forbidden path or traversal: $member"
                return 1
            fi
        done

        if ! tar -xf "$staging_archive" -C "$extracted_dir" --no-same-owner 2>/dev/null; then
            rm -rf "$staging_dir"
            error "Failed to extract tarball for $label."
            return 1
        fi
    fi

    # 2. Post-extraction symlink safety validation
    local symlink_file
    while IFS= read -r symlink_file; do
        if [[ -L "$symlink_file" ]]; then
            local target
            target="$(readlink "$symlink_file")"
            if [[ "$target" == /* ]]; then
                rm -rf "$staging_dir"
                error "Archive for $label contains unsafe absolute symlink: $symlink_file -> $target"
                return 1
            fi
            local resolved
            resolved="$(cd -- "$(dirname -- "$symlink_file")" 2>/dev/null && realpath -m -- "$target" 2>/dev/null || true)"
            if [[ -n "$resolved" && "$resolved" != "$extracted_dir"* ]]; then
                rm -rf "$staging_dir"
                error "Archive for $label contains symlink escaping staging: $symlink_file -> $target"
                return 1
            fi
        fi
    done < <(find "$extracted_dir" -type l 2>/dev/null)

    # 3. Explicit expected member resolution (deterministic, NO guessing or fallback to 'any executable')
    read -r -a expected_members <<< "$expected_members_arg"
    local found_binaries=()
    local exp_member

    for exp_member in "${expected_members[@]}"; do
        local candidate=""

        # Check exact relative path inside extracted tree
        if [[ -f "$extracted_dir/$exp_member" ]]; then
            candidate="$extracted_dir/$exp_member"
        else
            # Search for exact member match in nested directory
            candidate="$(find "$extracted_dir" -type f -name "$(basename "$exp_member")" 2>/dev/null | head -n 1 || true)"
        fi

        if [[ -z "$candidate" || ! -f "$candidate" ]]; then
            rm -rf "$staging_dir"
            error "Archive for $label is missing declared binary member: $exp_member"
            return 1
        fi

        found_binaries+=("$candidate")
    done

    if [[ ${#found_binaries[@]} -eq 0 ]]; then
        rm -rf "$staging_dir"
        error "No declared binaries found in archive for $label."
        return 1
    fi

    # 4. Install binaries
    if [[ -d "$destination" || "$destination" == */ ]]; then
        ensure_directory "$destination"
        for bin_file in "${found_binaries[@]}"; do
            local dest_file="$destination/$(basename "$bin_file")"
            if is_true "$as_root"; then
                sudo install -m 0755 "$bin_file" "$dest_file"
            else
                install -m 0755 "$bin_file" "$dest_file"
            fi
            if [[ ! -x "$dest_file" ]]; then
                rm -rf "$staging_dir"
                error "$label binary $dest_file was not executable after installation."
                return 1
            fi
        done
    else
        ensure_directory "$(dirname "$destination")"
        local primary_bin="${found_binaries[0]}"
        if is_true "$as_root"; then
            sudo install -D -m 0755 "$primary_bin" "$destination"
        else
            install -D -m 0755 "$primary_bin" "$destination"
        fi
        if [[ ! -x "$destination" ]]; then
            rm -rf "$staging_dir"
            error "$label was not executable after installation at $destination."
            return 1
        fi
    fi

    rm -rf "$staging_dir"
    info "$label provisioned successfully."
    return 0
}

clone_pinned_git() {
    local url="$1"
    local destination="$2"
    local commit="$3"
    local label="$4"
    local temp_dir

    if [[ -d "$destination/.git" ]]; then
        info "$label already installed."
        return 0
    fi

    if [[ -e "$destination" ]]; then
        die "Existing non-Git path found at $destination"
    fi

    require_command git

    temp_dir="$(mktemp -d)"

    info "Cloning $label at $commit"

    mkdir -p "$temp_dir/src"
    git -C "$temp_dir/src" init -q
    git -C "$temp_dir/src" remote add origin "$url"

    if ! run_with_retry "git fetch $label" \
        run_with_timeout "$TIMEOUT_GIT_SECONDS" "git fetch $label" \
        git -C "$temp_dir/src" fetch --depth 1 origin "$commit"; then
        rm -rf "$temp_dir"
        return 1
    fi

    git -C "$temp_dir/src" checkout --detach FETCH_HEAD || {
        rm -rf "$temp_dir"
        return 1
    }

    ensure_directory "$(dirname "$destination")"
    mv "$temp_dir/src" "$destination"
    rm -rf "$temp_dir"
}
