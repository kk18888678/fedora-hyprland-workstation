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
