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
        "Oh My Zsh" ||
        record_required "shell" "oh-my-zsh" "Oh My Zsh clone failed."
        return 0
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
        "Zsh plugin $directory_name" ||
        record_required "shell" "$directory_name" "Zsh plugin clone failed."
        return 0
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

    [[ -n "$zsh_path" ]] ||
        record_required "shell" "zsh" "Could not determine Zsh path."
        return 0

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
