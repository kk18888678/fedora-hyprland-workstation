# Fedora Hyprland Workstation
# Zsh configuration

###############################################################################
# Nix
###############################################################################

# Fedora Nix environment.
if [[ -e /etc/profile.d/nix-daemon.sh ]]; then
    source /etc/profile.d/nix-daemon.sh
fi

# Compatibility with an existing upstream multi-user Nix installation.
if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Applications installed with `nix profile install`, such as devenv.
if [[ -d "$HOME/.nix-profile/bin" ]]; then
    case ":$PATH:" in
        *":$HOME/.nix-profile/bin:"*)
            ;;
        *)
            export PATH="$HOME/.nix-profile/bin:$PATH"
            ;;
    esac
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
