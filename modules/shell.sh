#!/usr/bin/env bash

# Zsh workstation configuration.
#
# Fedora owns the shell and CLI packages.
# Oh My Zsh provides the Zsh framework.
# Starship provides the prompt.
#
# This module is intended to be safe to rerun.

###############################################################################
# Oh My Zsh
###############################################################################

install_oh_my_zsh() {
    local omz_dir="$TARGET_HOME/.oh-my-zsh"

    if ! is_true "${OH_MY_ZSH:-false}"; then
        info "Oh My Zsh disabled by profile."
        return 0
    fi

    load_pinned_versions

    if [[ -d "$omz_dir/.git" ]]; then
        info "Oh My Zsh already installed."
        return 0
    fi

    clone_pinned_git \
        "$OH_MY_ZSH_URL" \
        "$omz_dir" \
        "$OH_MY_ZSH_COMMIT" \
        "Oh My Zsh" || {
        record_required "shell" "oh-my-zsh" "Oh My Zsh clone failed."
        return 0
    }
}

###############################################################################
# Zsh plugins
###############################################################################

install_zsh_plugin() {
    local repository="$1"
    local directory_name="$2"
    local commit="$3"

    local custom_dir="${ZSH_CUSTOM:-$TARGET_HOME/.oh-my-zsh/custom}"
    local destination="$custom_dir/plugins/$directory_name"

    if [[ -d "$destination/.git" ]]; then
        info "Zsh plugin already installed: $directory_name"
        return 0
    fi

    clone_pinned_git \
        "$repository" \
        "$destination" \
        "$commit" \
        "Zsh plugin $directory_name" || {
        record_required "shell" "$directory_name" "Zsh plugin clone failed."
        return 0
    }
}

configure_zsh_plugins() {
    if ! is_true "${OH_MY_ZSH:-false}"; then
        return 0
    fi

    load_pinned_versions

    install_zsh_plugin \
        "$ZSH_AUTOSUGGESTIONS_URL" \
        "zsh-autosuggestions" \
        "$ZSH_AUTOSUGGESTIONS_COMMIT"

    install_zsh_plugin \
        "$ZSH_SYNTAX_HIGHLIGHTING_URL" \
        "zsh-syntax-highlighting" \
        "$ZSH_SYNTAX_HIGHLIGHTING_COMMIT"
}

###############################################################################
# Default shell
###############################################################################

configure_default_shell() {
    local zsh_path
    local current_shell

    zsh_path="$(command -v zsh)"

    [[ -n "$zsh_path" ]] || {
        record_required "shell" "zsh" "Could not determine Zsh path."
        return 0
    }

    current_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"

    if [[ "$current_shell" == "$zsh_path" ]]; then
        info "Zsh is already the default shell."
        return 0
    fi

    info "Setting Zsh as default shell for $TARGET_USER."

    sudo usermod --shell "$zsh_path" "$TARGET_USER"
}

###############################################################################
# Main entry point
###############################################################################

deploy_zsh_config() {
    local source="$SCRIPT_DIR/dotfiles/zsh/.zshrc"
    local destination="$TARGET_HOME/.zshrc"

    ensure_symlink "$source" "$destination"

    info "Zsh configuration linked."
}

deploy_starship_config() {
    local source="$SCRIPT_DIR/dotfiles/starship/starship.toml"
    local destination="$TARGET_HOME/.config/starship.toml"

    ensure_symlink "$source" "$destination"

    info "Starship configuration linked."
}

deploy_kitty_config() {
    local source="$SCRIPT_DIR/dotfiles/kitty/kitty.conf"
    local destination="$TARGET_HOME/.config/kitty/kitty.conf"

    ensure_symlink "$source" "$destination"

    info "Kitty configuration linked."
}

deploy_nvim_config() {
    local source="$SCRIPT_DIR/dotfiles/nvim/init.lua"
    local destination="$TARGET_HOME/.config/nvim/init.lua"

    ensure_symlink "$source" "$destination"

    info "Neovim configuration linked."
}

configure_user_directories() {
    info "Configuring standard XDG user directories."

    if ! command_exists xdg-user-dirs-update; then
        record_deferred "shell" "xdg-user-dirs" "xdg-user-dirs-update command not found."
        return 0
    fi

    local user_dirs_config_dir="$TARGET_HOME/.config"
    local user_dirs_file="$user_dirs_config_dir/user-dirs.dirs"

    if [[ ! -d "$user_dirs_config_dir" ]]; then
        if ! run_as_target_user mkdir -p "$user_dirs_config_dir"; then
            record_deferred "shell" "xdg-user-dirs" "Failed to create user configuration directory: $user_dirs_config_dir."
            return 0
        fi
    fi

    if [[ -f "$user_dirs_file" ]]; then
        # EXISTING USER: Read and preserve existing configuration before any update tooling runs.
        # Safely parse user-dirs.dirs line by line without eval or sourcing.
        local line key raw_val dir_path
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Ignore empty lines and comments
            [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue

            # Strict syntax matching: only the eight valid standard XDG directory keys
            if [[ "$line" =~ ^[[:space:]]*(XDG_(DESKTOP|DOWNLOAD|TEMPLATES|PUBLICSHARE|DOCUMENTS|MUSIC|PICTURES|VIDEOS)_DIR)=[\"\']?([^\"\'\`\$]+|\$HOME/[^\"\'\`\$]*)[\"\']?[[:space:]]*$ ]]; then
                key="${BASH_REMATCH[1]}"
                raw_val="${BASH_REMATCH[3]}"

                # Prevent arbitrary command execution or parameter expansion
                if [[ "$raw_val" == *'`'* || "$raw_val" == *'$('* || "$raw_val" == *'${'* ]]; then
                    continue
                fi

                # Expand supported forms: $HOME/... or absolute /...
                if [[ "$raw_val" == '$HOME'* ]]; then
                    dir_path="${TARGET_HOME}${raw_val#\$HOME}"
                elif [[ "$raw_val" == /* ]]; then
                    dir_path="$raw_val"
                else
                    continue
                fi

                # Create the configured custom directory as TARGET_USER before xdg-user-dirs-update can reset it
                if [[ -n "$dir_path" && ! -d "$dir_path" ]]; then
                    if ! run_as_target_user mkdir -p "$dir_path"; then
                        record_deferred "shell" "xdg-user-dirs" "Failed to create configured XDG directory: $dir_path."
                        return 0
                    fi
                fi
            fi
        done < "$user_dirs_file"

        # Now that all existing configured directories exist on disk, run xdg-user-dirs-update
        # with LC_ALL=C to populate any missing standard keys without reassigning existing custom paths.
        if ! run_as_target_user env LC_ALL=C xdg-user-dirs-update; then
            record_deferred "shell" "xdg-user-dirs" "Failed to update user directories configuration as $TARGET_USER."
            return 0
        fi
    else
        # FRESH USER: No existing ~/.config/user-dirs.dirs.
        # Execute xdg-user-dirs-update with LC_ALL=C as TARGET_USER to establish standard English baseline.
        if ! run_as_target_user env LC_ALL=C xdg-user-dirs-update; then
            record_deferred "shell" "xdg-user-dirs" "Failed to execute xdg-user-dirs-update as $TARGET_USER."
            return 0
        fi

        # Ensure all standard baseline directories exist on disk with TARGET_USER ownership.
        local standard_dirs=(
            "$TARGET_HOME/Desktop"
            "$TARGET_HOME/Documents"
            "$TARGET_HOME/Downloads"
            "$TARGET_HOME/Music"
            "$TARGET_HOME/Pictures"
            "$TARGET_HOME/Public"
            "$TARGET_HOME/Templates"
            "$TARGET_HOME/Videos"
        )
        local sdir
        for sdir in "${standard_dirs[@]}"; do
            if [[ ! -d "$sdir" ]]; then
                if ! run_as_target_user mkdir -p "$sdir"; then
                    record_deferred "shell" "xdg-user-dirs" "Failed to create standard directory: $sdir."
                    return 0
                fi
            fi
        done
    fi

    info "Standard XDG user directories configured."
    record_success "xdg-user-dirs"

    configure_gtk_bookmarks
}

configure_gtk_bookmarks() {
    info "Configuring standard GTK / Thunar bookmarks."

    local gtk3_config_dir="$TARGET_HOME/.config/gtk-3.0"
    local bookmarks_file="$gtk3_config_dir/bookmarks"
    local user_dirs_file="$TARGET_HOME/.config/user-dirs.dirs"

    if [[ ! -d "$gtk3_config_dir" ]]; then
        if ! run_as_target_user mkdir -p "$gtk3_config_dir"; then
            record_deferred "shell" "gtk-bookmarks" "Failed to create GTK-3.0 config directory: $gtk3_config_dir."
            return 0
        fi
    fi

    # Resolve standard paths using user-dirs.dirs or fallback to standard TARGET_HOME paths
    local download_dir="$TARGET_HOME/Downloads"
    local documents_dir="$TARGET_HOME/Documents"
    local music_dir="$TARGET_HOME/Music"
    local pictures_dir="$TARGET_HOME/Pictures"
    local videos_dir="$TARGET_HOME/Videos"

    if [[ -f "$user_dirs_file" ]]; then
        local line k v
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
            if [[ "$line" =~ ^[[:space:]]*(XDG_(DOWNLOAD|DOCUMENTS|MUSIC|PICTURES|VIDEOS)_DIR)=[\"\']?([^\"\'\`\$]+|\$HOME/[^\"\'\`\$]*)[\"\']?[[:space:]]*$ ]]; then
                k="${BASH_REMATCH[1]}"
                v="${BASH_REMATCH[3]}"
                local resolved=""
                if [[ "$v" == '$HOME'* ]]; then
                    resolved="${TARGET_HOME}${v#\$HOME}"
                elif [[ "$v" == /* ]]; then
                    resolved="$v"
                fi
                if [[ -n "$resolved" ]]; then
                    case "$k" in
                        XDG_DOWNLOAD_DIR) download_dir="$resolved" ;;
                        XDG_DOCUMENTS_DIR) documents_dir="$resolved" ;;
                        XDG_MUSIC_DIR) music_dir="$resolved" ;;
                        XDG_PICTURES_DIR) pictures_dir="$resolved" ;;
                        XDG_VIDEOS_DIR) videos_dir="$resolved" ;;
                    esac
                fi
            fi
        done < "$user_dirs_file"
    fi

    # Standard bookmark URIs to ensure (DO NOT automatically bookmark Desktop, Templates, or Public)
    local standard_uris=(
        "file://$download_dir"
        "file://$documents_dir"
        "file://$music_dir"
        "file://$pictures_dir"
        "file://$videos_dir"
    )

    local existing_lines=()
    if [[ -f "$bookmarks_file" ]]; then
        local bline
        while IFS= read -r bline || [[ -n "$bline" ]]; do
            bline="${bline%$'\r'}"
            [[ -n "$bline" ]] && existing_lines+=("$bline")
        done < "$bookmarks_file"
    fi

    local final_lines=("${existing_lines[@]}")
    local uri
    for uri in "${standard_uris[@]}"; do
        local found=0
        local existing
        for existing in "${existing_lines[@]}"; do
            if [[ "$existing" == "$uri" || "$existing" == "$uri "* ]]; then
                found=1
                break
            fi
        done
        if [[ $found -eq 0 ]]; then
            final_lines+=("$uri")
        fi
    done

    local content
    content="$(printf '%s\n' "${final_lines[@]}")"
    if ! run_as_target_user bash -c 'cat > "$1"' _ "$bookmarks_file" <<< "$content"; then
        record_deferred "shell" "gtk-bookmarks" "Failed to write bookmarks file: $bookmarks_file."
        return 0
    fi

    info "GTK / Thunar bookmarks configured."
    record_success "gtk-bookmarks"
}

configure_shell() {
    if [[ "${SHELL:-}" != "zsh" ]]; then
        die "Unsupported shell profile: ${SHELL:-<unset>}"
    fi

    require_command zsh
    require_command git

    install_oh_my_zsh
    configure_zsh_plugins
    deploy_zsh_config
    deploy_starship_config
    deploy_kitty_config
    deploy_nvim_config
    configure_user_directories
    configure_default_shell

    if [[ "${PROMPT:-}" == "starship" ]]; then
        if ! command_exists starship; then
            record_required "shell" "starship" "Starship is required by the profile but is not installed."
            return 0
        fi
    else
        die "Unsupported prompt: ${PROMPT:-<unset>}"
    fi

    info "Zsh environment configured."
    record_success "configure_shell"
}
