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

# User local binaries (such as agy, local scripts).
if [[ -d "$HOME/.local/bin" ]]; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*)
            ;;
        *)
            export PATH="$HOME/.local/bin:$PATH"
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
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt APPEND_HISTORY

# ---------------------------------------------------------------------------
# History hygiene: do not remember typo'd or failed commands.
#
# zsh's zshaddhistory hook runs before a command executes. It can therefore
# reject a line whose first command word does not resolve, but it cannot know
# the exit status yet. zsh 5.9 has no builtin way to delete a single history
# entry afterwards: `fc -d` prints timestamps rather than deleting, and
# $history is read-only. Deleting entries by rewriting $HISTFILE is unsafe
# with SHARE_HISTORY because other shells hold the file open.
#
# The safe mechanism used here is to defer the entry rather than delete it:
#
#   1. The zshaddhistory hook always returns 1, so zsh never records the line
#      itself. It only remembers the line in _zsh_history_candidate when the
#      first command word resolves (leading NAME=value assignments skipped).
#   2. The precmd hook runs once the command has finished, when $? holds its
#      exit status. It re-adds the remembered line with `print -s` only when
#      the status is 0, 130 (Ctrl+C) or 137 (SIGKILL), then clears it.
#
# Because the line is re-added through zsh's normal history machinery,
# HIST_IGNORE_DUPS, HIST_IGNORE_ALL_DUPS, HIST_SAVE_NO_DUPS and SHARE_HISTORY
# keep working unchanged. HIST_IGNORE_SPACE is enforced explicitly below
# because `print -s` would otherwise bypass it.
#
# Measured limits (history is recorded per line, so decisions are per line):
#
#   * Only the first command word is inspected. `clera | cat` is dropped by
#     the pre-exec check because its first word `clera` does not resolve, even
#     though the pipeline itself exits 0. A wrapped typo such as `sudo clera`
#     passes the check (`sudo` resolves) and is dropped only because the
#     wrapper exits non-zero; a wrapper that exits 0 (`sudo true` once
#     authenticated) is kept.
#   * A typo later in an `&&` / `||` / `|` / `;` chain is not seen by the
#     pre-exec check and is dropped only when the whole line exits non-zero.
#     `false; echo ok` exits 0 and is kept wholesale, so the failed `false` is
#     remembered. `echo ok; clera` exits 127 and is dropped wholesale, so the
#     successful `echo ok` is forgotten.
#   * Whole-line drops are the only granularity: a line is kept or dropped as
#     a unit; individual commands cannot be removed from a kept line.
#   * Statuses 0, 130 and 137 are kept; every other status is dropped.
# ---------------------------------------------------------------------------

# Last accepted line, awaiting its exit status.
typeset -g _zsh_history_candidate=''

# First command word of the line currently being filtered.
typeset -g _zsh_history_first_word=''

# True (0) for exit statuses that should still be remembered.
_zsh_history_status_ok() {
    (( ${1:-0} == 0 || ${1:-0} == 130 || ${1:-0} == 137 ))
}

# Report the first command word, skipping leading NAME=value assignments, in
# _zsh_history_first_word. Returns non-zero when the line has no command word.
_zsh_history_first_word_of() {
    emulate -L zsh
    local line=${1%%$'\n'}
    local -a words
    words=( ${(z)line} )
    local i=1 word
    while (( i <= ${#words} )); do
        word=${words[i]}
        if [[ $word == [A-Za-z_][A-Za-z0-9_]*=* ]]; then
            (( i++ ))
            continue
        fi
        _zsh_history_first_word=$word
        return 0
    done
    _zsh_history_first_word=''
    return 1
}

# Pre-exec hook: remember only lines whose first command word resolves. Always
# returns 1 so zsh never records the line directly; an accepted line is
# re-added by _zsh_history_precmd once its exit status is known.
_zsh_history_add() {
    _zsh_history_candidate=''

    # Preserve HIST_IGNORE_SPACE; `print -s` below would bypass it.
    [[ ${1[1]} == ' ' ]] && return 1

    _zsh_history_first_word_of "$1" || return 1
    whence -- "$_zsh_history_first_word" >/dev/null || return 1

    _zsh_history_candidate=${1%%$'\n'}
    return 1
}

# Post-exec hook: commit the accepted line only on an acceptable status.
_zsh_history_precmd() {
    local ret=$?
    if [[ -n $_zsh_history_candidate ]] && _zsh_history_status_ok "$ret"; then
        print -sr -- "$_zsh_history_candidate"
    fi
    _zsh_history_candidate=''
}

autoload -Uz add-zsh-hook
add-zsh-hook zshaddhistory _zsh_history_add
add-zsh-hook precmd _zsh_history_precmd

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
