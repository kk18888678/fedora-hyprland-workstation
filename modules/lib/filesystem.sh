#!/usr/bin/env bash

# Filesystem and path safety primitives.

validate_mutation_path() {
    local path="$1"

    [[ -n "$path" ]] || {
        error "Filesystem mutation path is empty."
        return 1
    }
    [[ "$path" == /* ]] || {
        error "Filesystem mutation path must be absolute: $path"
        return 1
    }

    local current="/"
    local component
    local components=()
    local IFS='/'
    read -r -a components <<< "${path#/}"

    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        if [[ "$component" == "." || "$component" == ".." ]]; then
            error "Filesystem mutation path contains an unsafe component: $path"
            return 1
        fi
        current="${current%/}/$component"
        if [[ -L "$current" ]]; then
            error "Refusing filesystem mutation through symlinked path component: $current"
            return 1
        fi
    done
}

ensure_directory() {
    local directory="$1"

    validate_mutation_path "$directory" || return 1
    [[ "$directory" != "/" ]] || {
        error "ensure_directory called with root path '/'."
        return 1
    }

    if [[ -e "$directory" && ! -d "$directory" ]]; then
        error "ensure_directory target exists and is not a directory: $directory"
        return 1
    fi

    if [[ ! -d "$directory" ]]; then
        mkdir -p -- "$directory" || {
            error "Failed to create directory: $directory"
            return 1
        }
    fi
}

ensure_symlink() {
    local source="$1"
    local destination="$2"

    [[ -n "$source" ]] || {
        error "ensure_symlink: source path is empty."
        return 1
    }

    [[ -n "$destination" ]] || {
        error "ensure_symlink: destination path is empty."
        return 1
    }

    [[ "$destination" != "/" ]] || {
        error "ensure_symlink: refusing destination as root directory '/'."
        return 1
    }

    # The final destination may legitimately be an existing symlink that we
    # preserve and replace.  Its parent path must not contain symlinks.
    validate_mutation_path "$(dirname -- "$destination")" || return 1

    [[ -e "$source" && ! -L "$source" ]] || {
        error "Symlink source is missing or is a symlink: $source"
        return 1
    }

    ensure_directory "$(dirname "$destination")" || return 1

    if [[ -L "$destination" ]]; then
        local current_target
        if ! current_target="$(readlink -- "$destination")"; then
            error "Could not read existing symlink destination: $destination"
            return 1
        fi

        if [[ "$current_target" == "$source" ]]; then
            return 0
        fi
    fi

    if [[ -e "$destination" || -L "$destination" ]]; then
        local backup
        backup="${destination}.bak.$(date +%Y%m%d-%H%M%S)"

        if [[ -e "$backup" || -L "$backup" ]]; then
            local counter=1
            while [[ -e "${backup}.${counter}" || -L "${backup}.${counter}" ]]; do
                counter=$((counter + 1))
            done
            backup="${backup}.${counter}"
        fi

        warn "Existing path found: $destination"
        warn "Moving it to: $backup"

        if ! mv -- "$destination" "$backup"; then
            error "Failed to preserve existing path at backup location: $backup"
            return 1
        fi
    fi

    if ! ln -s -- "$source" "$destination"; then
        error "Failed to create symlink at $destination"
        return 1
    fi

    if [[ ! -L "$destination" || "$(readlink "$destination")" != "$source" ]]; then
        error "Failed to create symlink at $destination pointing to $source"
        return 1
    fi
}

validate_path_components() {
    local path="$1"

    [[ -n "$path" ]] || return 1

    # Reject absolute path (starts with / or \, or drive letter)
    if [[ "$path" == /* || "$path" == \\* || "$path" =~ ^[a-zA-Z]: ]]; then
        return 1
    fi

    local clean_path="${path//\\//}"
    local parts=()
    local IFS='/'
    read -ra parts <<< "$clean_path"

    local p
    for p in "${parts[@]}"; do
        if [[ "$p" == ".." ]]; then
            # Rejects actual '..' path component
            return 1
        fi
    done

    return 0
}

normalize_archive_path() {
    local base_dir="${1:-}"
    local target="$2"

    [[ -n "$target" ]] || return 1

    # Reject absolute paths (leading slash, leading backslash, or Windows drive letter)
    if [[ "$target" == /* || "$target" == \\* || "$target" =~ ^[a-zA-Z]: ]]; then
        return 1
    fi

    local clean_base="${base_dir//\\//}"
    local clean_target="${target//\\//}"

    local stack=()

    if [[ -n "$clean_base" && "$clean_base" != "." ]]; then
        local IFS='/'
        read -ra base_parts <<< "$clean_base"
        local b
        for b in "${base_parts[@]}"; do
            [[ -n "$b" && "$b" != "." ]] || continue
            if [[ "$b" == ".." ]]; then
                if (( ${#stack[@]} == 0 )); then return 1; fi
                unset 'stack[-1]'
            else
                stack+=("$b")
            fi
        done
    fi

    local IFS='/'
    read -ra target_parts <<< "$clean_target"
    local p
    for p in "${target_parts[@]}"; do
        [[ -n "$p" && "$p" != "." ]] || continue
        if [[ "$p" == ".." ]]; then
            if (( ${#stack[@]} == 0 )); then
                # Underflow: resolves outside archive root
                return 1
            fi
            unset 'stack[-1]'
        else
            stack+=("$p")
        fi
    done

    local IFS='/'
    printf '%s\n' "${stack[*]:-}"
    return 0
}
