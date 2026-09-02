#!/usr/bin/env bash

# Test Suite: Package manifests and profile validation.

section "Package manifests"

assert_not_in_manifest() {
    local name="$1"

    if grep -h -vE '^\s*#' "$ROOT"/packages/*.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qx "$name"; then
        fail "forbidden package present: $name"
    else
        pass "forbidden package absent: $name"
    fi
}

assert_in_manifest() {
    local file="$1"
    local name="$2"

    if grep -h -vE '^\s*#' "$ROOT/$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qx "$name"; then
        pass "$name in $file"
    else
        fail "$name missing from $file"
    fi
}

# Legacy/incompatible Fedora packages
assert_not_in_manifest mesa-vdpau-drivers
assert_not_in_manifest p7zip
assert_not_in_manifest p7zip-plugins
assert_not_in_manifest wget

# Project development toolchains forbidden from Fedora host manifests
assert_not_in_manifest pyenv
assert_not_in_manifest nvm
assert_not_in_manifest rustup
assert_not_in_manifest docker-ce
assert_not_in_manifest docker
assert_not_in_manifest nodejs
assert_not_in_manifest npm
assert_not_in_manifest rustc
assert_not_in_manifest cargo
assert_not_in_manifest golang
assert_not_in_manifest gradle
assert_not_in_manifest maven
assert_not_in_manifest dotnet-sdk
assert_not_in_manifest clang
assert_not_in_manifest cmake
assert_not_in_manifest meson
assert_not_in_manifest ninja-build
assert_not_in_manifest pkgconf
assert_not_in_manifest rocm-opencl
assert_not_in_manifest rocm-hip
assert_not_in_manifest steam
assert_not_in_manifest mangohud
assert_not_in_manifest wine
assert_not_in_manifest winetricks
assert_not_in_manifest os-prober
assert_not_in_manifest gnome-software

assert_in_manifest packages/base.txt wget2-wget
assert_in_manifest packages/base.txt 7zip
assert_in_manifest packages/base.txt 7zip-standalone
assert_in_manifest packages/desktop.txt hyprland
assert_in_manifest packages/desktop.txt noctalia
assert_in_manifest packages/desktop.txt greetd
assert_in_manifest packages/desktop.txt hyprpolkitagent
assert_in_manifest packages/desktop.txt gnome-keyring
assert_in_manifest packages/desktop.txt gnome-keyring-pam
assert_in_manifest packages/desktop.txt xdg-desktop-portal-hyprland
assert_in_manifest packages/desktop.txt adwaita-cursor-theme
assert_in_manifest packages/desktop.txt adw-gtk3-theme
assert_in_manifest packages/desktop.txt yaru-icon-theme
assert_in_manifest packages/desktop.txt qt6-qtbase
assert_in_manifest packages/desktop.txt qt6-qtwayland
assert_in_manifest packages/desktop.txt qt6ct
assert_in_manifest packages/desktop.txt nwg-look
assert_in_manifest packages/desktop.txt thunar
assert_in_manifest packages/desktop.txt thunar-archive-plugin
assert_in_manifest packages/desktop.txt thunar-volman
assert_in_manifest packages/desktop.txt thunar-media-tags-plugin
assert_in_manifest packages/desktop.txt file-roller
assert_in_manifest packages/desktop.txt gvfs
assert_in_manifest packages/desktop.txt gvfs-mtp
assert_in_manifest packages/desktop.txt gvfs-smb
assert_in_manifest packages/desktop.txt gvfs-afc
assert_in_manifest packages/desktop.txt xdg-user-dirs
assert_in_manifest packages/desktop.txt tumbler
assert_in_manifest packages/desktop.txt ffmpegthumbnailer
assert_in_manifest packages/desktop.txt poppler-glib
assert_in_manifest packages/desktop.txt libgsf
assert_in_manifest packages/desktop.txt libopenraw
assert_in_manifest packages/desktop.txt gnome-disk-utility
assert_in_manifest packages/desktop.txt gnome-calculator
assert_in_manifest packages/desktop.txt loupe
assert_in_manifest packages/desktop.txt dejavu-sans-fonts
assert_in_manifest packages/base.txt zsh
assert_in_manifest packages/base.txt starship
assert_in_manifest packages/media.txt ffmpeg
assert_in_manifest packages/media.txt mediainfo
assert_in_manifest packages/media.txt mkvtoolnix
assert_in_manifest packages/media.txt gpac
assert_in_manifest packages/diagnostics.txt smartmontools
assert_in_manifest packages/diagnostics.txt nvme-cli
assert_in_manifest packages/diagnostics.txt inxi
assert_in_manifest packages/diagnostics.txt lm_sensors
assert_in_manifest packages/diagnostics.txt htop
assert_in_manifest packages/diagnostics.txt btop
assert_in_manifest packages/diagnostics.txt iotop-c
assert_in_manifest packages/diagnostics.txt sysstat
assert_in_manifest packages/diagnostics.txt lsof
assert_in_manifest packages/diagnostics.txt strace
assert_in_manifest packages/diagnostics.txt nethogs
assert_in_manifest packages/diagnostics.txt duf
assert_in_manifest packages/diagnostics.txt ncdu
assert_in_manifest packages/diagnostics.txt btrfs-progs

if grep -h -vE '^\s*#' "$ROOT/packages/base.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qx "xdg-user-dirs"; then
    fail "xdg-user-dirs should not be duplicated in packages/base.txt"
else
    pass "xdg-user-dirs not duplicated in packages/base.txt"
fi

if grep -vE '^\s*#' "$ROOT"/packages/base.txt | grep -qw chromium; then
    fail "chromium belongs in the browser module, not base.txt"
else
    pass "chromium is not in base.txt"
fi

section "Profiles"

check_profile() {
    local file="$1"

    # shellcheck source=/dev/null
    source "$file"

    local required=(
        PROFILE_NAME GPU DESKTOP DESKTOP_SHELL SHELL PROMPT
        OH_MY_ZSH BROWSER_CHROMIUM BROWSER_ULAA BROWSER_BRAVE_ORIGIN
        BROWSER_FIREFOX CURSOR KATE CHATGPT MEDIA_APPLICATIONS ANTIGRAVITY LOCALSEND
        BLUETOOTH GAMING FLATPAK NIX PODMAN
        NVIDIA ROCM ENABLE_GRAPHICAL_TARGET INSTALL_GREETER INSTALL_NOCTALIA
    )

    local var
    for var in "${required[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            fail "$file missing $var"
        else
            pass "$file has $var"
        fi
    done

    if [[ "$DESKTOP" != "hyprland" ]]; then
        fail "$file DESKTOP is not hyprland"
    else
        pass "$file DESKTOP=hyprland"
    fi

    if [[ "$DESKTOP_SHELL" != "noctalia" ]]; then
        fail "$file DESKTOP_SHELL is not noctalia"
    else
        pass "$file DESKTOP_SHELL=noctalia"
    fi

    if [[ "$BROWSER_ULAA" != "true" ]]; then
        fail "$file BROWSER_ULAA is not true"
    else
        pass "$file BROWSER_ULAA=true"
    fi

    if [[ "$CHATGPT" != "true" ]]; then
        fail "$file CHATGPT is not true"
    else
        pass "$file CHATGPT=true"
    fi
}

check_profile "$ROOT/profiles/vm.conf"
check_profile "$ROOT/profiles/workstation.conf"

section "DNF Contention, Bounds, and Lock Diagnostics"

# 1. Verification that --skip-file-locks is NEVER used anywhere in the codebase
if grep -rn --exclude-dir='.git' --exclude='test_packages.sh' -- '--skip-file-locks' "$ROOT"; then
    fail "forbidden flag --skip-file-locks found in codebase"
else
    pass "--skip-file-locks is never used"
fi

# 2. Verification that no code attempts to kill package manager processes or delete rpm/dnf lock files
if grep -rnE --exclude-dir='.git' --exclude='test_packages.sh' '(pkill|killall|kill).*(dnf|rpm|packagekit)|rm.*(\.rpm\.lock|\.dnf\.lock|dnf.*/lock)' "$ROOT/modules"; then
    fail "dangerous lock-killing or lock-deletion found in modules"
else
    pass "no dangerous lock-killing or lock-deletion logic in modules"
fi

# 3. Simulate DNF lock contention extraction from DNF output
dnf_lock_holder_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/packages.sh"

log_file="$TARGET_HOME/dnf_lock.log"
cat <<'EOF' > "$log_file"
Waiting for a lock on the system repository.
The following processes are currently accessing it:
27719 dnf list --available *nerd*font* *hack*
28071 dnf info foot
EOF

holders="$(detect_dnf_lock_holders "$log_file")"
echo "has_27719=$(grep -c 'PID 27719: dnf list --available \*nerd\*font\* \*hack\*' <<< "$holders" || true)"
echo "has_28071=$(grep -c 'PID 28071: dnf info foot' <<< "$holders" || true)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$dnf_lock_holder_output" | grep -q 'has_27719=1' &&
   printf '%s\n' "$dnf_lock_holder_output" | grep -q 'has_28071=1'; then
    pass "detect_dnf_lock_holders extracts active lock-holder PIDs and commands from DNF output"
else
    fail "detect_dnf_lock_holders failed to parse lock output: $dnf_lock_holder_output"
fi

# 4. Simulate DNF operation where lock releases before timeout -> succeeds
dnf_release_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/execution.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/packages.sh"

status=0
run_dnf_command 2 "mock dnf success" bash -c 'sleep 0.1; echo Complete!' >/dev/null 2>&1 || status=$?
echo "release-status=$status"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$dnf_release_test_output" | grep -q 'release-status=0'; then
    pass "DNF command that acquires lock before timeout completes successfully"
else
    fail "DNF lock release test failed: $dnf_release_test_output"
fi

# 5. Simulate DNF operation where lock never releases -> bounded failure with status 124
dnf_unreleased_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/execution.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/packages.sh"

status=0
out="$(run_dnf_command 1 "mock dnf timeout" bash -c 'echo "Waiting for a lock on the system repository."; echo "The following processes are currently accessing it:"; echo "99999 /usr/bin/dnf install -y heavy-package"; sleep 10' 2>&1)" || status=$?
echo "timeout-status=$status"
echo "has_holder_diag=$(grep -c 'PID 99999: /usr/bin/dnf install -y heavy-package' <<< "$out" || true)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$dnf_unreleased_test_output" | grep -q 'timeout-status=124' &&
   printf '%s\n' "$dnf_unreleased_test_output" | grep -q 'has_holder_diag=1'; then
    pass "Unreleased lock contention fails in bounded time (status 124) with holder diagnostics"
else
    fail "Unreleased lock contention test failed: $dnf_unreleased_test_output"
fi

# 6. Distinguish lock contention / timeout from package unavailable
dnf_distinguish_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/execution.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/packages.sh"

TIMEOUT_METADATA_SECONDS=1

mock_bin="$(mktemp -d)"
export PATH="$mock_bin:$PATH"

# 1. Mock DNF that times out due to lock contention
cat <<'EOF' > "$mock_bin/dnf"
#!/usr/bin/env bash
if [[ "$*" =~ timeout-pkg ]]; then
    sleep 5
    exit 0
fi
exit 0
EOF
chmod +x "$mock_bin/dnf"

status=0
package_available "timeout-pkg" >/dev/null 2>&1 || status=$?
echo "timeout-query-status=$status"

# 2. Mock DNF that returns cleanly with empty output (package cleanly absent)
cat <<'EOF' > "$mock_bin/dnf"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$mock_bin/dnf"

status=0
package_available "absent-pkg" >/dev/null 2>&1 || status=$?
echo "empty-query-status=$status"

rm -rf "$mock_bin" "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$dnf_distinguish_test_output" | grep -q 'timeout-query-status=2' &&
   printf '%s\n' "$dnf_distinguish_test_output" | grep -q 'empty-query-status=1'; then
    pass "package_available distinguishes timeout/contention (status 2) from package unavailable (status 1)"
else
    fail "package_available failed to distinguish contention from unavailable: $dnf_distinguish_test_output"
fi

# 7. Process-table fallback results are labeled as concurrent processes (not lock holders)
dnf_proc_fallback_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/execution.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/packages.sh"

# Mock ps to return concurrent process
ps() {
    cat <<'EOF'
12345 /usr/bin/dnf5 makecache
EOF
}

diag="$(detect_dnf_lock_diagnostics "")"
echo "header=$(awk 'NR==1{print}' <<< "$diag")"
echo "has_pid=$(grep -c 'PID 12345: /usr/bin/dnf5 makecache' <<< "$diag" || true)"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$dnf_proc_fallback_output" | grep -q 'header=CONCURRENT_PROCS' &&
   printf '%s\n' "$dnf_proc_fallback_output" | grep -q 'has_pid=1'; then
    pass "Process-table fallback is accurately categorized as concurrent processes (not assumed lock holders)"
else
    fail "Process table fallback diagnostic failed: $dnf_proc_fallback_output"
fi
