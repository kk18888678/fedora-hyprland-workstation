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

    if [[ -d "$omz_dir/.git" ]]; then
        info "Oh My Zsh already installed."
        return 0
    fi

    if [[ -e "$omz_dir" ]]; then
        die "Existing non-Git path found at $omz_dir"
    fi

    require_command git

    info "Installing Oh My Zsh."

    git clone \
        --depth=1 \
        https://github.com/ohmyzsh/ohmyzsh.git \
        "$omz_dir"
}

###############################################################################
# Zsh plugins
###############################################################################

install_zsh_plugin() {
    local repository="$1"
    local directory_name="$2"

    local custom_dir="${ZSH_CUSTOM:-$TARGET_HOME/.oh-my-zsh/custom}"
    local destination="$custom_dir/plugins/$directory_name"

    if [[ -d "$destination/.git" ]]; then
        info "Zsh plugin already installed: $directory_name"
        return 0
    fi

    if [[ -e "$destination" ]]; then
        die "Existing non-Git plugin path found: $destination"
    fi

    ensure_directory "$(dirname "$destination")"

    info "Installing Zsh plugin: $directory_name"

    git clone \
        --depth=1 \
        "$repository" \
        "$destination"
}

configure_zsh_plugins() {
    if ! is_true "${OH_MY_ZSH:-false}"; then
        return 0
    fi

    install_zsh_plugin \
        "https://github.com/zsh-users/zsh-autosuggestions.git" \
        "zsh-autosuggestions"

    install_zsh_plugin \
        "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
        "zsh-syntax-highlighting"
}

###############################################################################
# Default shell
###############################################################################

configure_default_shell() {
    local zsh_path
    local current_shell

    zsh_path="$(command -v zsh)"

    [[ -n "$zsh_path" ]] ||
        die "Could not determine Zsh path."

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
    configure_default_shell

    if [[ "${PROMPT:-}" == "starship" ]]; then
        if ! command_exists starship; then
            die "Starship is required by the profile but is not installed."
        fi
    else
        die "Unsupported prompt: ${PROMPT:-<unset>}"
    fi

    info "Zsh environment configured."
}
