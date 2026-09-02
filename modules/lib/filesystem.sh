#!/usr/bin/env bash

# Filesystem and path safety primitives.

ensure_directory() {
    local directory="$1"

    [[ -n "$directory" ]] ||
        die "ensure_directory called with empty path."

    [[ "$directory" != "." && "$directory" != ".." ]] ||
        die "ensure_directory called with invalid relative path: '$directory'"

    if [[ -e "$directory" && ! -d "$directory" ]]; then
        die "ensure_directory target exists and is not a directory: $directory"
    fi

    if [[ ! -d "$directory" ]]; then
        mkdir -p "$directory"
    fi
}

ensure_symlink() {
    local source="$1"
    local destination="$2"

    [[ -n "$source" ]] ||
        die "ensure_symlink: source path is empty."

    [[ -n "$destination" ]] ||
        die "ensure_symlink: destination path is empty."

    [[ "$destination" != "/" ]] ||
        die "ensure_symlink: refusing destination as root directory '/'."

    [[ "$destination" != "." && "$destination" != ".." ]] ||
        die "ensure_symlink: refusing destination as relative '.' or '..'."

    [[ -e "$source" || -L "$source" ]] ||
        die "Symlink source does not exist: $source"

    ensure_directory "$(dirname "$destination")"

    if [[ -L "$destination" ]]; then
        local current_target
        current_target="$(readlink "$destination")"

        if [[ "$current_target" == "$source" ]]; then
            return 0
        fi

        rm -f "$destination"

    elif [[ -e "$destination" ]]; then
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

        mv "$destination" "$backup"
    fi

    ln -s "$source" "$destination"

    [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]] ||
        die "Failed to create symlink at $destination pointing to $source"
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
