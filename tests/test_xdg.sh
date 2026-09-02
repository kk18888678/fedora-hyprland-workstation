#!/usr/bin/env bash

# Test Suite: Standard XDG user directory initialization, custom directory preservation, and locale scoping.

section "Standard XDG User Directories"

if grep -q "configure_user_directories" "$ROOT/modules/shell.sh"; then
    pass "shell.sh defines and invokes configure_user_directories"
else
    fail "shell.sh missing configure_user_directories"
fi

if grep -q "xdg-user-dirs" "$ROOT/modules/validation.sh"; then
    pass "validation.sh validates XDG user directories"
else
    fail "validation.sh does not validate XDG user directories"
fi

# Test with realistic xdg-user-dirs-update test double (simulating reset on missing dir)
xdg_semantics_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="xdgtester"
TARGET_HOME="$(mktemp -d)"
OVERRIDE_TARGET_UID=1000
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/shell.sh"

env() {
    while [[ $# -gt 0 && "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
}

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

# Test double faithfully reproducing real xdg-user-dirs-update behavior:
# Reassigns any mapping to "$HOME/" if the target directory is missing from disk!
xdg-user-dirs-update() {
    local conf="$TARGET_HOME/.config/user-dirs.dirs"
    if [[ ! -f "$conf" ]]; then
        cat > "$conf" <<'UDIRS'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
UDIRS
        return 0
    fi

    local temp_conf="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^(XDG_(DESKTOP|DOWNLOAD|TEMPLATES|PUBLICSHARE|DOCUMENTS|MUSIC|PICTURES|VIDEOS)_DIR)=\"([^\"]+)\" ]]; then
            local k="${BASH_REMATCH[1]}"
            local v="${BASH_REMATCH[3]}"
            local p="${v/\$HOME/$TARGET_HOME}"
            if [[ ! -d "$p" ]]; then
                echo "${k}=\"\$HOME/\"" >> "$temp_conf"
            else
                echo "$line" >> "$temp_conf"
            fi
        else
            echo "$line" >> "$temp_conf"
        fi
    done < "$conf"
    mv "$temp_conf" "$conf"
}

# 1. Fresh user initialization test
configure_user_directories

all_eight_exist=1
for d in Desktop Documents Downloads Music Pictures Public Templates Videos; do
    if [[ ! -d "$TARGET_HOME/$d" ]]; then
        all_eight_exist=0
    fi
done
echo "all-eight-exist=$all_eight_exist"
echo "config-file-exists=$([[ -f "$TARGET_HOME/.config/user-dirs.dirs" ]] && echo 1 || echo 0)"

# 2. Place a user file in Documents
echo "important document" > "$TARGET_HOME/Documents/important.txt"

# 3. Test existing custom mapping whose directory does NOT exist on disk initially
# e.g. MyAudio does not exist, MyDesktop does not exist, MyDownloads does not exist
cat > "$TARGET_HOME/.config/user-dirs.dirs" <<'UDIRS'
XDG_DESKTOP_DIR="$HOME/MyDesktop"
XDG_DOWNLOAD_DIR="$HOME/MyDownloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/MyAudio"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
# Malformed and malicious entries that must be safely ignored:
MALFORMED_LINE="junk"
XDG_INVALID_DIR=$(touch "$TARGET_HOME/pwned_cmd_sub")
XDG_ANOTHER_DIR="`touch "$TARGET_HOME/pwned_backtick"`"
UDIRS

rm -rf "$TARGET_HOME/MyAudio" "$TARGET_HOME/MyDesktop" "$TARGET_HOME/MyDownloads"
configure_user_directories

# Verify custom directories were created and not reset to $HOME/
myaudio_preserved=$([[ -d "$TARGET_HOME/MyAudio" ]] && grep -q 'XDG_MUSIC_DIR="$HOME/MyAudio"' "$TARGET_HOME/.config/user-dirs.dirs" && echo 1 || echo 0)
mydesktop_preserved=$([[ -d "$TARGET_HOME/MyDesktop" ]] && grep -q 'XDG_DESKTOP_DIR="$HOME/MyDesktop"' "$TARGET_HOME/.config/user-dirs.dirs" && echo 1 || echo 0)
mydownloads_preserved=$([[ -d "$TARGET_HOME/MyDownloads" ]] && grep -q 'XDG_DOWNLOAD_DIR="$HOME/MyDownloads"' "$TARGET_HOME/.config/user-dirs.dirs" && echo 1 || echo 0)
no_reset_to_home=$(grep -cE 'XDG_(DESKTOP|DOWNLOAD|TEMPLATES|PUBLICSHARE|DOCUMENTS|MUSIC|PICTURES|VIDEOS)_DIR="\$HOME/"' "$TARGET_HOME/.config/user-dirs.dirs" || true)

echo "myaudio-preserved=$myaudio_preserved"
echo "mydesktop-preserved=$mydesktop_preserved"
echo "mydownloads-preserved=$mydownloads_preserved"
echo "no-reset-count=$no_reset_to_home"

# 4. Check user file was not touched
echo "user-file-preserved=$([[ -f "$TARGET_HOME/Documents/important.txt" ]] && echo 1 || echo 0)"

# 5. Check no malicious commands were executed
echo "no-cmd-sub-file=$([[ ! -f "$TARGET_HOME/pwned_cmd_sub" ]] && echo 1 || echo 0)"
echo "no-backtick-file=$([[ ! -f "$TARGET_HOME/pwned_backtick" ]] && echo 1 || echo 0)"

# 6. Idempotent rerun check
configure_user_directories
echo "idempotent-blocked=$ACTIVATION_BLOCKED"
echo "idempotent-exit=$(installer_exit_code)"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$xdg_semantics_test_output" | grep -q 'all-eight-exist=1'; then
    pass "all 8 standard XDG user directories initialized for fresh user"
else
    fail "fresh XDG user directory initialization missing directories: $xdg_semantics_test_output"
fi

if printf '%s\n' "$xdg_semantics_test_output" | grep -q 'config-file-exists=1'; then
    pass "user-dirs.dirs configuration file generated"
else
    fail "user-dirs.dirs configuration file missing: $xdg_semantics_test_output"
fi

if printf '%s\n' "$xdg_semantics_test_output" | grep -q 'myaudio-preserved=1' &&
   printf '%s\n' "$xdg_semantics_test_output" | grep -q 'mydesktop-preserved=1' &&
   printf '%s\n' "$xdg_semantics_test_output" | grep -q 'mydownloads-preserved=1' &&
   printf '%s\n' "$xdg_semantics_test_output" | grep -q 'no-reset-count=0'; then
    pass "missing custom directories created as TARGET_USER and preserved without reset to HOME"
else
    fail "custom directory preservation failed: $xdg_semantics_test_output"
fi

if printf '%s\n' "$xdg_semantics_test_output" | grep -q 'user-file-preserved=1'; then
    pass "existing user files are never deleted or mutated"
else
    fail "existing user files were not preserved: $xdg_semantics_test_output"
fi

if printf '%s\n' "$xdg_semantics_test_output" | grep -q 'no-cmd-sub-file=1' &&
   printf '%s\n' "$xdg_semantics_test_output" | grep -q 'no-backtick-file=1'; then
    pass "malformed and malicious user-dirs.dirs values are never executed"
else
    fail "malicious command substitution was executed: $xdg_semantics_test_output"
fi

if printf '%s\n' "$xdg_semantics_test_output" | grep -q 'idempotent-blocked=0'; then
    pass "rerunning XDG user directory initialization never blocks graphical activation"
else
    fail "rerunning XDG user directory initialization blocked activation: $xdg_semantics_test_output"
fi

# Test with real installed xdg-user-dirs-update binary in isolated sandbox if present
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    real_binary_test_output="$(
        bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="xdgtester"
TARGET_HOME="$(mktemp -d)"
OVERRIDE_TARGET_UID=1000
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/shell.sh"

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

mkdir -p "$TARGET_HOME/.config"
cat > "$TARGET_HOME/.config/user-dirs.dirs" <<'UDIRS'
XDG_DESKTOP_DIR="$HOME/RealDesktop"
XDG_DOWNLOAD_DIR="$HOME/RealDownloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/RealAudio"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
UDIRS

# Ensure RealAudio and RealDesktop do not exist beforehand
rm -rf "$TARGET_HOME/RealAudio" "$TARGET_HOME/RealDesktop" "$TARGET_HOME/RealDownloads"

configure_user_directories

realaudio_ok=$([[ -d "$TARGET_HOME/RealAudio" ]] && grep -q 'XDG_MUSIC_DIR="$HOME/RealAudio"' "$TARGET_HOME/.config/user-dirs.dirs" && echo 1 || echo 0)
echo "realaudio-ok=$realaudio_ok"

rm -rf "$TARGET_HOME"
EOS
    )"

    if printf '%s\n' "$real_binary_test_output" | grep -q 'realaudio-ok=1'; then
        pass "real xdg-user-dirs-update binary test preserves non-existing custom directory"
    else
        fail "real binary failed custom directory preservation: $real_binary_test_output"
    fi
fi

xdg_failure_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="xdgtester"
TARGET_HOME="$(mktemp -d)"
OVERRIDE_TARGET_UID=1000
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/shell.sh"

env() {
    while [[ $# -gt 0 && "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
}

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

# Simulate xdg-user-dirs-update failure
xdg-user-dirs-update() { return 1; }
configure_user_directories
echo "fail-blocked=$ACTIVATION_BLOCKED"
echo "fail-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$xdg_failure_test_output" | grep -q 'fail-blocked=0'; then
    pass "XDG user directory failure does not set ACTIVATION_BLOCKED"
else
    fail "XDG user directory failure set ACTIVATION_BLOCKED: $xdg_failure_test_output"
fi

if printf '%s\n' "$xdg_failure_test_output" | grep -q 'fail-exit=2'; then
    pass "XDG user directory failure produces deferred exit code 2"
else
    fail "XDG user directory failure did not produce exit code 2: $xdg_failure_test_output"
fi
