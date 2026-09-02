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

    # 1. Structural pre-extraction inspection & link-type/target validation BEFORE extraction
    if [[ "$url" == *.zip ]]; then
        if ! command_exists unzip; then
            rm -rf "$staging_dir"
            error "Required archive inspection tool 'unzip' is not installed for $label."
            return 1
        fi

        local raw_listing
        if ! raw_listing="$(unzip -Z -s "$staging_archive" 2>/dev/null)"; then
            rm -rf "$staging_dir"
            error "Archive structural inspection failed for $label (unzip listing error)."
            return 1
        fi

        local entry_count=0
        local line
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            if [[ "$line" =~ ^Archive: || "$line" =~ ^Zip\ file\ size: || "$line" =~ [0-9]+\ files,\ [0-9]+\ bytes ]]; then
                continue
            fi

            local type_char="${line:0:1}"
            case "$type_char" in
                -) # Regular file
                    local file_path
                    file_path="$(echo "$line" | awk '{ $1=$2=$3=$4=$5=$6=$7=$8=""; print substr($0,9) }')"
                    file_path="${file_path#./}"
                    if ! validate_path_components "$file_path" || ! normalize_archive_path "" "$file_path" >/dev/null; then
                        rm -rf "$staging_dir"
                        error "ZIP archive for $label contains forbidden regular file path: $file_path"
                        return 1
                    fi
                    ((entry_count++)) || true
                    ;;
                d) # Directory
                    local dir_path
                    dir_path="$(echo "$line" | awk '{ $1=$2=$3=$4=$5=$6=$7=$8=""; print substr($0,9) }')"
                    dir_path="${dir_path#./}"
                    dir_path="${dir_path%/}"
                    if [[ -n "$dir_path" ]] && ( ! validate_path_components "$dir_path" || ! normalize_archive_path "" "$dir_path" >/dev/null ); then
                        rm -rf "$staging_dir"
                        error "ZIP archive for $label contains forbidden directory path: $dir_path"
                        return 1
                    fi
                    ((entry_count++)) || true
                    ;;
                l) # Symlink
                    local symlink_name
                    symlink_name="$(echo "$line" | awk '{ $1=$2=$3=$4=$5=$6=$7=$8=""; print substr($0,9) }')"
                    symlink_name="${symlink_name#./}"
                    if ! validate_path_components "$symlink_name" || ! normalize_archive_path "" "$symlink_name" >/dev/null; then
                        rm -rf "$staging_dir"
                        error "ZIP archive for $label contains forbidden symlink path: $symlink_name"
                        return 1
                    fi

                    local symlink_target
                    if ! symlink_target="$(unzip -p "$staging_archive" "$symlink_name" 2>/dev/null)"; then
                        rm -rf "$staging_dir"
                        error "ZIP archive for $label has unreadable symlink target for: $symlink_name"
                        return 1
                    fi

                    local link_dir=""
                    if [[ "$symlink_name" == */* ]]; then
                        link_dir="${symlink_name%/*}"
                    fi

                    if ! normalize_archive_path "$link_dir" "$symlink_target" >/dev/null; then
                        rm -rf "$staging_dir"
                        error "ZIP archive for $label contains escaping symlink before extraction: $symlink_name -> $symlink_target"
                        return 1
                    fi
                    ((entry_count++)) || true
                    ;;
                *)
                    rm -rf "$staging_dir"
                    error "ZIP archive for $label contains unsupported/special entry type '$type_char': $line"
                    return 1
                    ;;
            esac
        done <<< "$raw_listing"

        if (( entry_count == 0 )); then
            rm -rf "$staging_dir"
            error "ZIP archive for $label is empty or produced no inspectable members."
            return 1
        fi

        # 2. Extract into staging directory
        if ! unzip -q -o "$staging_archive" -d "$extracted_dir" 2>/dev/null; then
            rm -rf "$staging_dir"
            error "Failed to extract ZIP archive for $label."
            return 1
        fi
    else
        if ! command_exists tar; then
            rm -rf "$staging_dir"
            error "Required archive inspection tool 'tar' is not installed for $label."
            return 1
        fi

        local raw_listing
        if ! raw_listing="$(tar --warning=no-unknown-keyword -tvf "$staging_archive" 2>/dev/null)"; then
            rm -rf "$staging_dir"
            error "Archive structural inspection failed for $label (tar listing error)."
            return 1
        fi

        local entry_count=0
        local line
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue

            local type_char="${line:0:1}"
            case "$type_char" in
                -) # Regular file
                    local file_path
                    file_path="$(echo "$line" | awk '{ $1=$2=$3=$4=$5=""; print substr($0,6) }')"
                    file_path="${file_path#./}"
                    if ! validate_path_components "$file_path" || ! normalize_archive_path "" "$file_path" >/dev/null; then
                        rm -rf "$staging_dir"
                        error "Tarball for $label contains forbidden regular file path: $file_path"
                        return 1
                    fi
                    ((entry_count++)) || true
                    ;;
                d) # Directory
                    local dir_path
                    dir_path="$(echo "$line" | awk '{ $1=$2=$3=$4=$5=""; print substr($0,6) }')"
                    dir_path="${dir_path#./}"
                    dir_path="${dir_path%/}"
                    if [[ -n "$dir_path" ]] && ( ! validate_path_components "$dir_path" || ! normalize_archive_path "" "$dir_path" >/dev/null ); then
                        rm -rf "$staging_dir"
                        error "Tarball for $label contains forbidden directory path: $dir_path"
                        return 1
                    fi
                    ((entry_count++)) || true
                    ;;
                l) # Symbolic link
                    local rest
                    rest="$(echo "$line" | awk '{ $1=$2=$3=$4=$5=""; print substr($0,6) }')"
                    local link_name="${rest%% -> *}"
                    local link_target="${rest#* -> }"
                    link_name="${link_name#./}"

                    if ! validate_path_components "$link_name" || ! normalize_archive_path "" "$link_name" >/dev/null; then
                        rm -rf "$staging_dir"
                        error "Tarball for $label contains forbidden symlink path: $link_name"
                        return 1
                    fi

                    local link_dir=""
                    if [[ "$link_name" == */* ]]; then
                        link_dir="${link_name%/*}"
                    fi

                    if ! normalize_archive_path "$link_dir" "$link_target" >/dev/null; then
                        rm -rf "$staging_dir"
                        error "Tarball for $label contains escaping symlink before extraction: $link_name -> $link_target"
                        return 1
                    fi
                    ((entry_count++)) || true
                    ;;
                h) # Hard link
                    local rest
                    rest="$(echo "$line" | awk '{ $1=$2=$3=$4=$5=""; print substr($0,6) }')"
                    local link_name="${rest%% link to *}"
                    local link_target="${rest#* link to }"
                    link_name="${link_name#./}"

                    if ! validate_path_components "$link_name" || ! normalize_archive_path "" "$link_name" >/dev/null; then
                        rm -rf "$staging_dir"
                        error "Tarball for $label contains forbidden hardlink path: $link_name"
                        return 1
                    fi

                    local link_dir=""
                    if [[ "$link_name" == */* ]]; then
                        link_dir="${link_name%/*}"
                    fi

                    if ! normalize_archive_path "$link_dir" "$link_target" >/dev/null && ! normalize_archive_path "" "$link_target" >/dev/null; then
                        rm -rf "$staging_dir"
                        error "Tarball for $label contains escaping hardlink before extraction: $link_name link to $link_target"
                        return 1
                    fi
                    ((entry_count++)) || true
                    ;;
                *) # Special entry types: character/block devices, fifos, sockets, or unrecognized
                    rm -rf "$staging_dir"
                    error "Tarball for $label contains unsupported/special entry type '$type_char': $line"
                    return 1
                    ;;
            esac
        done <<< "$raw_listing"

        if (( entry_count == 0 )); then
            rm -rf "$staging_dir"
            error "Tarball for $label is empty or produced no inspectable members."
            return 1
        fi

        # 2. Extract into staging directory
        if ! tar -xf "$staging_archive" -C "$extracted_dir" --no-same-owner 2>/dev/null; then
            rm -rf "$staging_dir"
            error "Failed to extract tarball for $label."
            return 1
        fi
    fi

    # 3. Post-extraction link safety validation (defense-in-depth with boundary-aware containment)
    local symlink_file
    while IFS= read -r symlink_file; do
        [[ -n "$symlink_file" ]] || continue
        local target
        target="$(readlink "$symlink_file")"
        if [[ "$target" == /* || "$target" =~ ^[a-zA-Z]: ]]; then
            rm -rf "$staging_dir"
            error "Archive for $label contains unsafe absolute symlink after extraction: $symlink_file -> $target"
            return 1
        fi
        local resolved
        resolved="$(cd -- "$(dirname -- "$symlink_file")" 2>/dev/null && realpath -m -- "$target" 2>/dev/null || true)"
        if [[ -z "$resolved" || ( "$resolved" != "$extracted_dir" && "$resolved" != "$extracted_dir/"* ) ]]; then
            rm -rf "$staging_dir"
            error "Archive for $label contains symlink escaping staging: $symlink_file -> $target"
            return 1
        fi
    done < <(find "$extracted_dir" -type l 2>/dev/null)

    # 4. Deterministic expected member resolution
    read -r -a expected_members <<< "$expected_members_arg"
    local resolved_binaries=()
    local exp_member

    for exp_member in "${expected_members[@]}"; do
        if ! validate_path_components "$exp_member"; then
            rm -rf "$staging_dir"
            error "Declared expected member for $label contains invalid path components: $exp_member"
            return 1
        fi

        local candidate=""
        # Exact relative path inside extracted tree
        if [[ -f "$extracted_dir/$exp_member" ]]; then
            candidate="$extracted_dir/$exp_member"
        else
            # Search for subpath or basename matches
            local matches=()
            if [[ "$exp_member" == */* ]]; then
                mapfile -t matches < <(find "$extracted_dir" -type f -path "*/$exp_member" 2>/dev/null)
            else
                mapfile -t matches < <(find "$extracted_dir" -type f -name "$exp_member" 2>/dev/null)
            fi

            if [[ ${#matches[@]} -eq 0 ]]; then
                rm -rf "$staging_dir"
                error "Archive for $label is missing declared binary member: $exp_member (0 matches found in archive tree)."
                return 1
            elif [[ ${#matches[@]} -gt 1 ]]; then
                rm -rf "$staging_dir"
                error "Archive for $label has ambiguous binary member: $exp_member (${#matches[@]} matches found: ${matches[*]}); refusing nondeterministic selection."
                return 1
            else
                candidate="${matches[0]}"
            fi
        fi

        if [[ -z "$candidate" || ! -f "$candidate" ]]; then
            rm -rf "$staging_dir"
            error "Declared binary member for $label could not be resolved as a regular file: $exp_member"
            return 1
        fi

        resolved_binaries+=("$candidate")
    done

    if [[ ${#resolved_binaries[@]} -ne ${#expected_members[@]} ]]; then
        rm -rf "$staging_dir"
        error "Could not resolve all declared binary members for $label (${#resolved_binaries[@]}/${#expected_members[@]} resolved)."
        return 1
    fi

    # 5. Install binaries (only after all declared members are verified)
    if [[ -d "$destination" || "$destination" == */ || ${#resolved_binaries[@]} -gt 1 ]]; then
        ensure_directory "$destination"
        local bin_file
        for bin_file in "${resolved_binaries[@]}"; do
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
        local primary_bin="${resolved_binaries[0]}"
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
