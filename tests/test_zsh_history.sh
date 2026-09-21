#!/usr/bin/env bash

# Test Suite: Zsh history hygiene (drop typo'd and failed commands).

section "Zsh history hygiene"

zshrc="$ROOT/dotfiles/zsh/.zshrc"

if zsh -n "$zshrc"; then
    pass "zsh -n dotfiles/zsh/.zshrc"
else
    fail "zsh -n dotfiles/zsh/.zshrc"
fi

for option in \
    HIST_IGNORE_DUPS \
    HIST_IGNORE_ALL_DUPS \
    HIST_SAVE_NO_DUPS \
    HIST_IGNORE_SPACE \
    SHARE_HISTORY \
    APPEND_HISTORY; do
    if grep -qE "^setopt ${option}$" "$zshrc"; then
        pass "zshrc sets ${option}"
    else
        fail "zshrc does not set ${option}"
    fi
done

if grep -qE '^add-zsh-hook zshaddhistory _zsh_history_add$' "$zshrc"; then
    pass "zshrc registers the pre-exec zshaddhistory hook"
else
    fail "zshrc does not register the pre-exec zshaddhistory hook"
fi

if grep -qE '^add-zsh-hook precmd _zsh_history_precmd$' "$zshrc"; then
    pass "zshrc registers the post-exec history precmd hook"
else
    fail "zshrc does not register the post-exec history precmd hook"
fi

# Behavioural tests source the managed History section so the real hook code
# is exercised, rather than a reimplementation.
sandbox="$(mktemp -d)"
history_section="$sandbox/history.zsh"
history_dump="$sandbox/history.txt"

awk '/^# History$/{emit=1; next} /^# Zsh behaviour$/{emit=0} emit' \
    "$zshrc" > "$history_section"

if [[ -s "$history_section" ]] && zsh -n "$history_section"; then
    pass "extracted the managed History section"
else
    fail "could not extract the managed History section"
fi

if [[ -s "$history_section" ]]; then
    hook_probe="$(
        HOME="$sandbox" ZSH_HISTORY_SECTION="$history_section" \
            zsh -f 2>/dev/null <<'EOS'
source "$ZSH_HISTORY_SECTION"
_zsh_history_add 'zsh_history_unknown_marker_clera'
unknown_candidate="$_zsh_history_candidate"
_zsh_history_add 'true'
known_candidate="$_zsh_history_candidate"
print -r -- "unknown=[$unknown_candidate] known=[$known_candidate]"
EOS
    )"

    if [[ "$hook_probe" == 'unknown=[] known=[true]' ]]; then
        pass "history hook drops an unknown command and keeps a resolvable one"
    else
        fail "history hook unexpected result: $hook_probe"
    fi

    status_probe="$(
        HOME="$sandbox" ZSH_HISTORY_SECTION="$history_section" \
            zsh -f 2>/dev/null <<'EOS'
source "$ZSH_HISTORY_SECTION"
for candidate_status in 0 1 2 126 127 130 137 143; do
    if _zsh_history_status_ok "$candidate_status"; then
        print -r -- "${candidate_status}=keep"
    else
        print -r -- "${candidate_status}=drop"
    fi
done
EOS
    )"

    if grep -q '^0=keep$' <<< "$status_probe" &&
        grep -q '^1=drop$' <<< "$status_probe" &&
        grep -q '^130=keep$' <<< "$status_probe" &&
        grep -q '^137=keep$' <<< "$status_probe"; then
        pass "history status filter keeps 0/130/137 and drops other statuses"
    else
        fail "history status filter unexpected result: $status_probe"
    fi

    if HOME="$sandbox" \
        ZSH_HISTORY_SECTION="$history_section" \
        ZSH_HISTORY_DUMP="$history_dump" \
        zsh -f -i >"$sandbox/session.log" 2>&1 <<'EOS'
PS1='hist-test% '
source "$ZSH_HISTORY_SECTION"
true
false
zsh_history_unknown_marker_clera
echo zsh_history_success_marker
 echo zsh_history_space_marker
print -l -- ${(kv)history} > "$ZSH_HISTORY_DUMP"
EOS
    then
        if grep -q '^true$' "$history_dump" &&
            grep -q 'zsh_history_success_marker' "$history_dump"; then
            pass "history keeps successful commands"
        else
            fail "history did not keep successful commands"
        fi

        if grep -q '^false$' "$history_dump"; then
            fail "history kept a failed command"
        else
            pass "history drops failed commands"
        fi

        if grep -q 'zsh_history_unknown_marker_clera' "$history_dump"; then
            fail "history kept an unknown command"
        else
            pass "history drops unknown commands"
        fi

        if grep -q 'zsh_history_space_marker' "$history_dump"; then
            fail "history kept a HIST_IGNORE_SPACE command"
        else
            pass "history honours HIST_IGNORE_SPACE"
        fi
    else
        fail "zsh history hygiene session failed"
    fi
fi

rm -rf -- "$sandbox"
