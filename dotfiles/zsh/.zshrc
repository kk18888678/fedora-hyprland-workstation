# Fedora Hyprland Workstation
# Zsh configuration

###############################################################################
# Nix
###############################################################################

# Multi-user Nix installation.
#
# Source the daemon environment first, then explicitly expose the user's
# Nix profile. This ensures applications installed with `nix profile`
# such as devenv are available in every interactive Zsh session.

if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

if [[ -d "$HOME/.nix-profile/bin" ]]; then
    export PATH="$HOME/.nix-profile/bin:$PATH"
fi

###############################################################################
# Oh My Zsh
###############################################################################

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""

plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

###############################################################################
# Prompt
###############################################################################

eval "$(starship init zsh)"

###############################################################################
# Navigation
###############################################################################

eval "$(zoxide init zsh)"

###############################################################################
# FZF
###############################################################################

if [[ -f /usr/share/fzf/shell/key-bindings.zsh ]]; then
    source /usr/share/fzf/shell/key-bindings.zsh
fi

if [[ -f /usr/share/fzf/shell/completion.zsh ]]; then
    source /usr/share/fzf/shell/completion.zsh
fi

###############################################################################
# History
###############################################################################

HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000

setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY
setopt APPEND_HISTORY

###############################################################################
# Zsh behaviour
###############################################################################

setopt AUTO_CD
setopt INTERACTIVE_COMMENTS

###############################################################################
# Editor
###############################################################################

export EDITOR="nvim"
export VISUAL="$EDITOR"
