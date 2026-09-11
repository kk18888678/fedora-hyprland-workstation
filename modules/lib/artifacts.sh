#!/usr/bin/env bash

# Upstream artifact provisioning, verification, and archive safety.

load_pinned_versions() {
    local versions_file="${SCRIPT_DIR:-$(pwd -P)}/config/versions.conf"

    [[ -f "$versions_file" && ! -L "$versions_file" ]] ||
        die "Pinned versions file is missing or is a symlink: $versions_file"

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
        curl --proto '=https' --proto-redir '=https' -fsSL -o "$output_file" "$url"; then
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

validate_artifact_destination() {
    local destination="$1"
    local destination_dir

    [[ "$destination" == /* && "$destination" != "/" ]] || {
        error "Refusing invalid artifact destination: $destination"
        return 1
    }

    [[ ! -L "$destination" ]] || {
        error "Refusing to install an artifact through an existing symlink: $destination"
        return 1
    }

    destination_dir="$(dirname -- "$destination")"
    if declare -F validate_mutation_path >/dev/null 2>&1 &&
        ! validate_mutation_path "$destination_dir"; then
        error "Refusing artifact destination with an unsafe parent path: $destination"
        return 1
    fi
}

# Install one verified artifact member through a unique sibling and a final
# rename. If an existing path is present, move it to a recoverable backup
# before replacement. The caller receives the backup path so a multi-member
# archive can roll back all earlier replacements when a later member fails.
artifact_atomic_install_member() {
    local source="$1"
    local destination="$2"
    local as_root="$3"
    local backup_output_var="$4"
    local destination_dir
    local token_file
    local stage_destination
    local existing_backup=""
    local backup_stamp
    local backup_counter=1
    local -n backup_output="$backup_output_var"

    backup_output=""

    [[ -f "$source" && ! -L "$source" ]] || return 1
    validate_artifact_destination "$destination" || return 1

    destination_dir="$(dirname -- "$destination")"
    if ! ensure_directory "$destination_dir"; then
        return 1
    fi

    if ! token_file="$(mktemp)"; then
        return 1
    fi
    stage_destination="$destination_dir/.$(basename -- "$destination").fhw-stage.$(basename -- "$token_file")"
    if ! rm -f -- "$token_file" || [[ -e "$stage_destination" || -L "$stage_destination" ]]; then
        rm -f -- "$token_file" 2>/dev/null || true
        return 1
    fi

    if is_true "$as_root"; then
        if ! sudo install -m 0755 -- "$source" "$stage_destination"; then
            sudo rm -f -- "$stage_destination" 2>/dev/null || true
            return 1
        fi
    elif ! install -m 0755 -- "$source" "$stage_destination"; then
        rm -f -- "$stage_destination" 2>/dev/null || true
        return 1
    fi

    if [[ -e "$destination" || -L "$destination" ]]; then
        if ! backup_stamp="$(date +%Y%m%d-%H%M%S)"; then
            if is_true "$as_root"; then
                sudo rm -f -- "$stage_destination" 2>/dev/null || true
            else
                rm -f -- "$stage_destination" 2>/dev/null || true
            fi
            return 1
        fi

        existing_backup="${destination}.bak.${backup_stamp}"
        while [[ -e "$existing_backup" || -L "$existing_backup" ]]; do
            existing_backup="${destination}.bak.${backup_stamp}.${backup_counter}"
            backup_counter=$((backup_counter + 1))
        done

        if is_true "$as_root"; then
            if ! sudo mv -T -- "$destination" "$existing_backup"; then
                sudo rm -f -- "$stage_destination" 2>/dev/null || true
                return 1
            fi
        elif ! mv -T -- "$destination" "$existing_backup"; then
            rm -f -- "$stage_destination" 2>/dev/null || true
            return 1
        fi
    fi

    if is_true "$as_root"; then
        if ! sudo mv -T -- "$stage_destination" "$destination"; then
            if [[ -n "$existing_backup" && ! -e "$destination" && ! -L "$destination" ]]; then
                sudo mv -T -- "$existing_backup" "$destination" || true
            fi
            sudo rm -f -- "$stage_destination" 2>/dev/null || true
            return 1
        fi
    elif ! mv -T -- "$stage_destination" "$destination"; then
        if [[ -n "$existing_backup" && ! -e "$destination" && ! -L "$destination" ]]; then
            mv -T -- "$existing_backup" "$destination" || true
        fi
        rm -f -- "$stage_destination" 2>/dev/null || true
        return 1
    fi

    [[ -f "$destination" && ! -L "$destination" && -x "$destination" ]] || {
        if [[ -e "$destination" || -L "$destination" ]]; then
            if is_true "$as_root"; then
                sudo rm -f -- "$destination" 2>/dev/null || true
            else
                rm -f -- "$destination" 2>/dev/null || true
            fi
        fi
        if [[ -n "$existing_backup" && ! -e "$destination" && ! -L "$destination" ]]; then
            if is_true "$as_root"; then
                sudo mv -T -- "$existing_backup" "$destination" || true
            else
                mv -T -- "$existing_backup" "$destination" || true
            fi
        fi
        return 1
    }

    printf -v "$backup_output_var" '%s' "$existing_backup"
}

artifact_rollback_installations() {
    local paths_var="$1"
    local backups_var="$2"
    local as_root="$3"
    local -n _installed_paths_ref="$paths_var"
    local -n _installed_backups_ref="$backups_var"
    local index
    local destination
    local backup
    local rollback_failed=0

    for (( index=${#_installed_paths_ref[@]} - 1; index >= 0; index--)); do
        destination="${_installed_paths_ref[$index]}"
        backup="${_installed_backups_ref[$index]}"

        # The destination was just installed by this transaction. Remove only
        # a regular file (never recursively remove a raced-in directory).
        if [[ -f "$destination" && ! -L "$destination" ]]; then
            if is_true "$as_root"; then
                sudo rm -f -- "$destination" || rollback_failed=1
            elif ! rm -f -- "$destination"; then
                rollback_failed=1
            fi
        elif [[ -e "$destination" || -L "$destination" ]]; then
            rollback_failed=1
        fi

        if [[ -n "$backup" && -e "$backup" && ! -L "$backup" ]]; then
            if is_true "$as_root"; then
                sudo mv -T -- "$backup" "$destination" || rollback_failed=1
            elif ! mv -T -- "$backup" "$destination"; then
                rollback_failed=1
            fi
        fi
    done

    return "$rollback_failed"
}

artifact_provenance_directory() {
    local directory=""

    if installer_test_override_allowed; then
        directory="${OVERRIDE_ARTIFACT_PROVENANCE_DIR:-}"
    elif [[ "${INSTALLER_PRODUCTION_MODE:-0}" == "1" &&
            -n "${INSTALLER_STATE_ROOT:-}" ]]; then
        directory="${INSTALLER_STATE_ROOT:-}/artifacts"
    fi

    [[ -n "$directory" && "$directory" == /* && "$directory" != "/" ]] || return 1
    if declare -F validate_mutation_path >/dev/null 2>&1 &&
        ! validate_mutation_path "$directory"; then
        return 1
    fi

    printf '%s\n' "$directory"
}

artifact_provenance_file() {
    local artifact_id="$1"
    local directory

    [[ "$artifact_id" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || return 1
    directory="$(artifact_provenance_directory)" || return 1
    printf '%s/%s.manifest\n' "$directory" "$artifact_id"
}

artifact_provenance_content() {
    local artifact_id="$1"
    local expected_sha512="$2"
    shift 2

    [[ "$artifact_id" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || return 1
    [[ "$expected_sha512" =~ ^[a-fA-F0-9]{128}$ ]] || return 1
    [[ $# -gt 0 ]] || return 1

    printf 'format=1\nartifact_id=%s\nsource_sha512=%s\n' \
        "$artifact_id" "$expected_sha512"

    local path
    local actual_sha512
    for path in "$@"; do
        [[ "$path" == /* && "$path" != "/" ]] || return 1
        [[ -f "$path" && ! -L "$path" && -x "$path" ]] || return 1
        actual_sha512="$(sha512sum -- "$path" | awk '{print $1}')" || return 1
        [[ "$actual_sha512" =~ ^[a-fA-F0-9]{128}$ ]] || return 1
        printf 'path=%s\nsha512=%s\n' "$path" "$actual_sha512"
    done
}

artifact_provenance_matches() {
    local artifact_id="$1"
    local expected_sha512="$2"
    shift 2
    local marker
    local expected_content

    marker="$(artifact_provenance_file "$artifact_id")" || return 1
    [[ -f "$marker" && ! -L "$marker" ]] || return 1

    if [[ "${INSTALLER_PRODUCTION_MODE:-0}" == "1" ]]; then
        [[ "$(stat -c '%u' -- "$marker" 2>/dev/null || true)" == "0" ]] || return 1
        [[ "$(stat -c '%a' -- "$marker" 2>/dev/null || true)" == "644" ]] || return 1
    fi

    expected_content="$(artifact_provenance_content "$artifact_id" "$expected_sha512" "$@")" || return 1
    cmp -s "$marker" <(printf '%s\n' "$expected_content")
}

artifact_record_provenance() {
    local artifact_id="$1"
    local expected_sha512="$2"
    shift 2
    local directory
    local marker
    local content
    local temporary

    directory="$(artifact_provenance_directory)" || return 1
    marker="$(artifact_provenance_file "$artifact_id")" || return 1

    if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
        return 1
    fi

    if [[ ! -d "$directory" ]]; then
        if [[ "${INSTALLER_PRODUCTION_MODE:-0}" == "1" ]]; then
            sudo install -d -m 0755 -o root -g root -- "$directory" || return 1
        else
            install -d -m 0755 -- "$directory" || return 1
        fi
    fi

    if [[ "${INSTALLER_PRODUCTION_MODE:-0}" == "1" ]]; then
        [[ "$(stat -c '%u' -- "$directory" 2>/dev/null || true)" == "0" ]] || return 1
        [[ "$(stat -c '%a' -- "$directory" 2>/dev/null || true)" == "755" ]] || return 1
    fi

    [[ ! -L "$marker" ]] || return 1
    content="$(artifact_provenance_content "$artifact_id" "$expected_sha512" "$@")" || return 1
    temporary="$(mktemp)" || return 1
    if ! printf '%s\n' "$content" >"$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi

    if [[ "${INSTALLER_PRODUCTION_MODE:-0}" == "1" ]]; then
        if ! install_root_file_atomically "$temporary" "$marker" 0644 root root; then
            rm -f -- "$temporary"
            return 1
        fi
    elif ! install -m 0644 -- "$temporary" "$marker"; then
        rm -f -- "$temporary"
        return 1
    fi
    rm -f -- "$temporary"

    artifact_provenance_matches "$artifact_id" "$expected_sha512" "$@"
}

provision_verified_binary() {
    local url="$1"
    local expected_sha512="$2"
    local destination="$3"
    local label="$4"
    local as_root="${5:-false}"
    local provenance_id="${6:-}"

    validate_artifact_destination "$destination" || return 1

    local staging_dir
    if ! staging_dir="$(mktemp -d)"; then
        error "Could not create a secure temporary staging directory for $label."
        return 1
    fi
    local staging_file="$staging_dir/$(basename "$destination")"

    if ! download_and_verify_artifact "$url" "$expected_sha512" "$staging_file" "$label"; then
        rm -rf "$staging_dir"
        return 1
    fi

    local backup_path=""
    if ! artifact_atomic_install_member "$staging_file" "$destination" "$as_root" backup_path; then
        rm -rf -- "$staging_dir"
        error "Failed to install $label at $destination."
        return 1
    fi

    rm -rf "$staging_dir"

    if [[ ! -x "$destination" ]]; then
        error "$label was not executable after installation at $destination."
        return 1
    fi

    if [[ -n "$provenance_id" ]] &&
        ! artifact_record_provenance "$provenance_id" "$expected_sha512" "$destination"; then
        local rollback_paths=("$destination")
        local rollback_backups=("$backup_path")
        artifact_rollback_installations rollback_paths rollback_backups "$as_root" ||
            error "Rollback of $label after provenance recording failure was incomplete; inspect preserved backups."
        error "Could not record verified provenance for $label."
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
    local provenance_id="${7:-}"

    [[ -n "$expected_members_arg" ]] || {
        error "Explicit expected archive member(s) must be specified for $label."
        return 1
    }

    validate_artifact_destination "$destination" || return 1

    local staging_dir
    if ! staging_dir="$(mktemp -d)"; then
        error "Could not create a secure temporary staging directory for $label."
        return 1
    fi
    local staging_archive="$staging_dir/archive"

    if ! download_and_verify_artifact "$url" "$expected_sha512" "$staging_archive" "$label"; then
        rm -rf "$staging_dir"
        return 1
    fi

    local extracted_dir="$staging_dir/extracted"
    if ! mkdir -p -- "$extracted_dir"; then
        rm -rf -- "$staging_dir"
        error "Could not create the temporary extraction directory for $label."
        return 1
    fi

    # 1. Structural pre-extraction inspection: accept ONLY regular files and directories.
    # Reject all symbolic links, hard links, and special filesystem entry types before extraction.
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
                    ((entry_count++)) || true
                    ;;
                d) # Directory
                    ((entry_count++)) || true
                    ;;
                l) # Symbolic link rejected
                    rm -rf "$staging_dir"
                    error "ZIP archive for $label contains symbolic link before extraction (symbolic links are disallowed): $line"
                    return 1
                    ;;
                *) # Special or unsupported entry types rejected
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

        # Validate pure member paths from unzip -Z1
        local members_listing
        if ! members_listing="$(unzip -Z1 "$staging_archive" 2>/dev/null)"; then
            rm -rf "$staging_dir"
            error "ZIP archive member path listing failed for $label."
            return 1
        fi

        local member
        while IFS= read -r member; do
            [[ -n "$member" ]] || continue
            local clean="${member#./}"
            clean="${clean%/}"
            [[ -n "$clean" ]] || continue

            if ! validate_path_components "$clean" || ! normalize_archive_path "" "$clean" >/dev/null; then
                rm -rf "$staging_dir"
                error "ZIP archive for $label contains forbidden member path: $member"
                return 1
            fi
        done <<< "$members_listing"

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

        # Check entry modes: reject symlinks, hardlinks, and special entries
        local verbose_listing
        if ! verbose_listing="$(tar --warning=no-unknown-keyword -tvf "$staging_archive" 2>/dev/null)"; then
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
                    ((entry_count++)) || true
                    ;;
                d) # Directory
                    ((entry_count++)) || true
                    ;;
                l) # Symbolic link rejected
                    rm -rf "$staging_dir"
                    error "Tarball for $label contains symbolic link before extraction (symbolic links are disallowed): $line"
                    return 1
                    ;;
                h) # Hard link rejected
                    rm -rf "$staging_dir"
                    error "Tarball for $label contains hard link before extraction (hard links are disallowed): $line"
                    return 1
                    ;;
                *) # Special entry types: character/block devices, fifos, sockets, or unrecognized
                    rm -rf "$staging_dir"
                    error "Tarball for $label contains unsupported/special entry type '$type_char': $line"
                    return 1
                    ;;
            esac
        done <<< "$verbose_listing"

        if (( entry_count == 0 )); then
            rm -rf "$staging_dir"
            error "Tarball for $label is empty or produced no inspectable members."
            return 1
        fi

        # Validate pure member paths from tar -tf
        local members_listing
        if ! members_listing="$(tar -tf "$staging_archive" 2>/dev/null)"; then
            rm -rf "$staging_dir"
            error "Tarball member path listing failed for $label."
            return 1
        fi

        local member
        while IFS= read -r member; do
            [[ -n "$member" ]] || continue
            local clean="${member#./}"
            clean="${clean%/}"
            [[ -n "$clean" ]] || continue

            if ! validate_path_components "$clean" || ! normalize_archive_path "" "$clean" >/dev/null; then
                rm -rf "$staging_dir"
                error "Tarball for $label contains forbidden member path: $member"
                return 1
            fi
        done <<< "$members_listing"

        # 2. Extract into staging directory
        if ! tar -xf "$staging_archive" -C "$extracted_dir" --no-same-owner 2>/dev/null; then
            rm -rf "$staging_dir"
            error "Failed to extract tarball for $label."
            return 1
        fi
    fi

    # 3. Post-extraction symlink validation (defense-in-depth: any symlink appearing is rejected)
    local symlink_file
    while IFS= read -r symlink_file; do
        [[ -n "$symlink_file" ]] || continue
        rm -rf "$staging_dir"
        error "Archive for $label contained unexpected symbolic link after extraction: $symlink_file"
        return 1
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

    # 5. Install binaries (only after all declared members are verified).
    # Each replacement is recorded so a later failure can restore every
    # earlier member and leave no partially installed archive set.
    local installed_paths=()
    local installed_backups=()
    local install_failed=0
    local backup_path=""
    if [[ -d "$destination" || "$destination" == */ || ${#resolved_binaries[@]} -gt 1 ]]; then
        if ! ensure_directory "$destination"; then
            rm -rf -- "$staging_dir"
            error "Could not prepare the artifact destination directory for $label."
            return 1
        fi
        local bin_file
        for bin_file in "${resolved_binaries[@]}"; do
            local dest_file="$destination/$(basename "$bin_file")"
            if ! artifact_atomic_install_member "$bin_file" "$dest_file" "$as_root" backup_path; then
                install_failed=1
                break
            fi
            installed_paths+=("$dest_file")
            installed_backups+=("$backup_path")
        done
    else
        local primary_bin="${resolved_binaries[0]}"
        if ! artifact_atomic_install_member "$primary_bin" "$destination" "$as_root" backup_path; then
            install_failed=1
        else
            installed_paths+=("$destination")
            installed_backups+=("$backup_path")
        fi
    fi

    if (( install_failed != 0 )); then
        if ! artifact_rollback_installations installed_paths installed_backups "$as_root"; then
            error "Rollback of partially installed $label members was incomplete; inspect preserved backups."
        fi
        rm -rf -- "$staging_dir"
        error "Failed to install the complete $label artifact set."
        return 1
    fi

    if [[ -n "$provenance_id" ]] &&
        ! artifact_record_provenance "$provenance_id" "$expected_sha512" "${installed_paths[@]}"; then
        if ! artifact_rollback_installations installed_paths installed_backups "$as_root"; then
            error "Rollback of $label after provenance recording failure was incomplete; inspect preserved backups."
        fi
        rm -rf -- "$staging_dir"
        error "Could not record verified provenance for $label."
        return 1
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

    [[ "$url" =~ ^https:// ]] || {
        error "Refusing non-HTTPS Git source for $label: $url"
        return 1
    }

    [[ "$commit" =~ ^[0-9a-fA-F]{40}$ ]] || {
        error "Pinned Git commit is not a full 40-hex revision for $label."
        return 1
    }

    [[ ! -L "$destination" ]] || {
        error "Refusing to use a symlink as the Git checkout destination for $label: $destination"
        return 1
    }

    if [[ -d "$destination/.git" ]]; then
        local existing_commit
        if ! existing_commit="$(git -C "$destination" rev-parse --verify HEAD 2>/dev/null)"; then
            error "Existing Git checkout for $label has no readable HEAD; refusing to treat it as installed."
            return 1
        fi
        if [[ "$existing_commit" == "$commit" ]]; then
            info "$label already installed at the pinned commit."
            return 0
        fi

        error "Existing Git checkout for $label is not at pinned commit $commit (found $existing_commit); refusing to modify it."
        return 1
    fi

    if [[ -e "$destination" ]]; then
        die "Existing non-Git path found at $destination"
    fi

    require_command git

    if ! temp_dir="$(mktemp -d)"; then
        error "Could not create a secure temporary Git staging directory for $label."
        return 1
    fi

    info "Cloning $label at $commit"

    if ! mkdir -p "$temp_dir/src" ||
       ! git -C "$temp_dir/src" init -q ||
       ! git -C "$temp_dir/src" remote add origin "$url"; then
        rm -rf -- "$temp_dir"
        error "Failed to prepare the temporary Git checkout for $label."
        return 1
    fi

    if ! run_with_retry "git fetch $label" \
        run_with_timeout "$TIMEOUT_GIT_SECONDS" "git fetch $label" \
        env GIT_TERMINAL_PROMPT=0 git -C "$temp_dir/src" fetch --depth 1 origin "$commit"; then
        rm -rf "$temp_dir"
        return 1
    fi

    if ! git -C "$temp_dir/src" checkout --detach FETCH_HEAD; then
        rm -rf "$temp_dir"
        error "Failed to check out pinned commit for $label."
        return 1
    fi

    if ! ensure_directory "$(dirname "$destination")"; then
        rm -rf -- "$temp_dir"
        return 1
    fi
    if ! mv -- "$temp_dir/src" "$destination"; then
        rm -rf -- "$temp_dir"
        error "Failed to install the pinned Git checkout for $label."
        return 1
    fi
    rm -rf -- "$temp_dir"
}
