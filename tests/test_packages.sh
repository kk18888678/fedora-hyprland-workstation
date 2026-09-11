#!/usr/bin/env bash

# Test Suite: Package manifests and profile validation.

section "Package manifests"

assert_not_in_manifest() {
    local name="$1"

    if awk -v wanted="$name" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            if ($0 == wanted) { found = 1 }
        }
        END { exit found ? 0 : 1 }
    ' "$ROOT"/packages/*.txt; then
        fail "forbidden package present: $name"
    else
        pass "forbidden package absent: $name"
    fi
}

assert_in_manifest() {
    local file="$1"
    local name="$2"

    if awk -v wanted="$name" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            if ($0 == wanted) { found = 1 }
        }
        END { exit found ? 0 : 1 }
    ' "$ROOT/$file"; then
        pass "$name in $file"
    else
        fail "$name missing from $file"
    fi
}

manifest_entry_guard_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/packages.sh"

invalid_manifest="$(mktemp)"
symlink_target="$(mktemp)"
symlink_manifest="${invalid_manifest}.symlink"
duplicate_manifest="${invalid_manifest}.duplicate"
trap 'rm -f -- "$invalid_manifest" "$symlink_target" "$symlink_manifest" "$duplicate_manifest"' EXIT

printf '%s\n' '--assumeyes' > "$invalid_manifest"
invalid_status=0
( read_package_manifest "$invalid_manifest" >/dev/null ) || invalid_status=$?

ln -s -- "$symlink_target" "$symlink_manifest"
symlink_status=0
( read_package_manifest "$symlink_manifest" >/dev/null ) || symlink_status=$?

printf '%s\n%s\n' package-a package-a > "$duplicate_manifest"
duplicate_status=0
( read_package_manifest "$duplicate_manifest" >/dev/null ) || duplicate_status=$?

printf 'option_rejected=%s symlink_rejected=%s duplicate_rejected=%s\n' \
    "$([[ $invalid_status -ne 0 ]] && echo 1 || echo 0)" \
    "$([[ $symlink_status -ne 0 ]] && echo 1 || echo 0)" \
    "$([[ $duplicate_status -ne 0 ]] && echo 1 || echo 0)"
EOS
)"

if grep -q 'option_rejected=1 symlink_rejected=1 duplicate_rejected=1' <<< "$manifest_entry_guard_output"; then
    pass "package manifests reject option-like entries, symlinked paths, and duplicate rows"
else
    fail "package manifest input validation failed: $manifest_entry_guard_output"
fi

manifest_error_propagation_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/packages.sh"

invalid_manifest="$(mktemp)"
trap 'rm -f -- "$invalid_manifest"' EXIT
printf '%s\n' '--not-a-package-option' > "$invalid_manifest"
validate_manifest_packages "$invalid_manifest" >/dev/null 2>&1 &&
    validate_status=0 || validate_status=$?
    package_manifest_all_installed "$invalid_manifest" >/dev/null 2>&1 && detect_status=0 || detect_status=$?
printf 'validation_propagates=%s\n' "$([[ "$validate_status" -ne 0 ]] && echo 1 || echo 0)"
printf 'detector_propagates=%s\n' "$([[ "$detect_status" -ne 0 ]] && echo 1 || echo 0)"
EOS
)"

if grep -q 'validation_propagates=1' <<< "$manifest_error_propagation_output" &&
   grep -q 'detector_propagates=1' <<< "$manifest_error_propagation_output"; then
    pass "malformed package manifests propagate failure through validation and group detection"
else
    fail "malformed package manifest failure was swallowed: $manifest_error_propagation_output"
fi

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
assert_in_manifest packages/base.txt tmux
assert_in_manifest packages/base.txt gnome-keyring
assert_in_manifest packages/base.txt gvfs
assert_in_manifest packages/base.txt gvfs-mtp
assert_in_manifest packages/base.txt gvfs-smb
assert_in_manifest packages/desktop.txt hyprland
assert_in_manifest packages/aurelia.txt quickshell
assert_in_manifest packages/aurelia.txt inotify-tools
if awk '$0 == "inotify-tools" { found=1 } END { exit found ? 0 : 1 }' "$ROOT/packages/desktop.txt"; then
    fail "inotify-tools should not be installed for every desktop shell"
else
    pass "Aurelia-only watcher is not included in the general desktop package group"
fi
assert_in_manifest packages/desktop.txt noctalia
assert_in_manifest packages/desktop.txt greetd
assert_in_manifest packages/desktop.txt noctalia-greeter
assert_in_manifest packages/desktop.txt hyprpolkitagent
assert_in_manifest packages/desktop.txt gnome-keyring-pam
assert_in_manifest packages/desktop.txt xdg-desktop-portal-hyprland
assert_in_manifest packages/desktop.txt adwaita-cursor-theme
assert_in_manifest packages/desktop.txt adw-gtk3-theme
assert_in_manifest packages/desktop.txt yaru-icon-theme
assert_in_manifest packages/desktop.txt qt6-qtbase
assert_in_manifest packages/desktop.txt qt6-qtwayland
assert_in_manifest packages/desktop.txt qt6-qtimageformats
assert_in_manifest packages/desktop.txt qt6ct
assert_in_manifest packages/desktop.txt nwg-look
assert_in_manifest packages/desktop.txt thunar
assert_in_manifest packages/desktop.txt thunar-archive-plugin
assert_in_manifest packages/desktop.txt thunar-volman
assert_in_manifest packages/desktop.txt thunar-media-tags-plugin
assert_in_manifest packages/desktop.txt file-roller
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
assert_in_manifest packages/media.txt ImageMagick
assert_in_manifest packages/bluetooth.txt bluez
assert_in_manifest packages/bluetooth.txt bluez-tools
assert_not_in_manifest bluez-utils
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

if awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if ($0 == "xdg-user-dirs") { found = 1 }
    }
    END { exit found ? 0 : 1 }
' "$ROOT/packages/base.txt"; then
    fail "xdg-user-dirs should not be duplicated in packages/base.txt"
else
    pass "xdg-user-dirs not duplicated in packages/base.txt"
fi

manifest_duplicates="$({
    awk '
        FNR == 1 { file = FILENAME }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            if ($0 != "") {
                count[$0]++
                files[$0] = files[$0] (files[$0] ? " " : "") file
            }
        }
        END {
            for (package in count) {
                if (count[package] > 1) {
                    print package " -> " files[package]
                }
            }
        }
    ' "$ROOT"/packages/*.txt
} | sort)"
if [[ -z "$manifest_duplicates" ]]; then
    pass "package manifests have one clear owner per RPM"
else
    fail "package manifests contain duplicate RPM ownership: $manifest_duplicates"
fi

if grep -vE '^\s*#' "$ROOT"/packages/base.txt | grep -qw chromium; then
    fail "chromium belongs in the browser module, not base.txt"
else
    pass "chromium is not in base.txt"
fi

if grep -h -vE '^\s*#' "$ROOT/packages/desktop.txt" |
   sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
   grep -Eq '^(bluez|bluez-tools|bluez-utils)$'; then
    fail "Bluetooth packages must not be unconditional desktop packages"
else
    pass "Bluetooth packages are not unconditional desktop packages"
fi

bluetooth_profile_matrix="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
DESKTOP="hyprland"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/packages.sh"

install_manifest() {
    if [[ "$1" == */bluetooth.txt ]]; then
        printf 'bluetooth_manifest_called\n'
    fi
    return 0
}

BLUETOOTH=false
install_packages
BLUETOOTH=true
install_packages
EOS
)"

bluetooth_manifest_calls="$(grep -c '^bluetooth_manifest_called$' <<< "$bluetooth_profile_matrix" || true)"
if [[ "$bluetooth_manifest_calls" -eq 1 ]] &&
   grep -q 'Bluetooth disabled by profile; skipping Bluetooth packages.' <<< "$bluetooth_profile_matrix"; then
    pass "Bluetooth package manifest is skipped for vm and used for Bluetooth-enabled profiles"
else
    fail "Bluetooth package profile gating is incorrect: $bluetooth_profile_matrix"
fi

bluetooth_failure_test="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
DESKTOP="hyprland"
BLUETOOTH=true

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/packages.sh"

install_manifest() {
    [[ "$1" != */bluetooth.txt ]]
}

install_status=0
install_packages >/dev/null 2>&1 || install_status=$?
printf 'activation_blocked=%s\n' "$ACTIVATION_BLOCKED"
printf 'required_failures=%s\n' "${#INSTALL_REQUIRED_FAILURES[@]}"
printf 'login_failures=%s\n' "${#INSTALL_LOGIN_FAILURES[@]}"
printf 'install_status=%s success_recorded=%s\n' "$install_status" \
    "$(grep -c '^install_packages$' <(printf '%s\n' "${INSTALL_SUCCEEDED[@]}") || true)"
EOS
)"

if grep -q '^activation_blocked=0$' <<< "$bluetooth_failure_test" &&
   grep -q '^required_failures=1$' <<< "$bluetooth_failure_test" &&
   grep -q '^login_failures=0$' <<< "$bluetooth_failure_test" &&
   grep -q '^install_status=1 success_recorded=0$' <<< "$bluetooth_failure_test"; then
    pass "Bluetooth package failure remains workstation-required, propagates from the package stage, and does not block graphical activation"
else
    fail "Bluetooth package failure classification is incorrect: $bluetooth_failure_test"
fi

section "Manifest Groups in Reviewed Plan"

package_group_plan_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
PROFILE_NAME="workstation"
DESKTOP_SHELL="aurelia"
FLATPAK=true
PODMAN=true
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/packages.sh"

# Simulate a fresh Fedora Everything install without touching the host.
command_exists() { return 1; }
package_installed() { return 1; }
create_recommended_desired_state DS_FRESH_GROUPS workstation aurelia
create_execution_plan DS_FRESH_GROUPS PLAN_FRESH_GROUPS
for idx in "${PLAN_FRESH_GROUPS_ACTIONS[@]}"; do
    case "${PLAN_FRESH_GROUPS_ACTION_TARGET[$idx]}" in
        packages.base|packages.desktop|packages.aurelia|packages.diagnostics|packages.media|packages.flatpak|packages.containers)
            printf '%s=%s\n' "${PLAN_FRESH_GROUPS_ACTION_TARGET[$idx]}" "${PLAN_FRESH_GROUPS_ACTION_TYPE[$idx]}"
            ;;
    esac
done
EOS
)"

if grep -q '^packages.base=INSTALL$' <<< "$package_group_plan_output" &&
   grep -q '^packages.desktop=INSTALL$' <<< "$package_group_plan_output" &&
   grep -q '^packages.aurelia=INSTALL$' <<< "$package_group_plan_output" &&
   grep -q '^packages.diagnostics=INSTALL$' <<< "$package_group_plan_output" &&
   grep -q '^packages.media=INSTALL$' <<< "$package_group_plan_output" &&
   grep -q '^packages.flatpak=INSTALL$' <<< "$package_group_plan_output" &&
   grep -q '^packages.containers=INSTALL$' <<< "$package_group_plan_output"; then
    pass "fresh CLI-only package manifests appear as reviewed plan install actions"
else
    fail "fresh package manifests were omitted from reviewed plan: $package_group_plan_output"
fi

noctalia_group_plan_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
PROFILE_NAME="workstation"
DESKTOP_SHELL="noctalia"
FLATPAK=false
PODMAN=false
source "$SCRIPT_DIR/modules/common.sh"
source "$SCRIPT_DIR/modules/status.sh"
source "$SCRIPT_DIR/modules/packages.sh"
command_exists() { return 1; }
package_installed() { return 1; }
create_recommended_desired_state DS_NOCTALIA_GROUP workstation noctalia
printf 'aurelia_state=%s\n' "$(desired_state_get_component DS_NOCTALIA_GROUP packages.aurelia)"
EOS
)"
if grep -q '^aurelia_state=unmanaged$' <<< "$noctalia_group_plan_output"; then
    pass "Noctalia desired state does not select the Aurelia-only package group"
else
    fail "Noctalia desired state unexpectedly selected Aurelia packages: $noctalia_group_plan_output"
fi

quickshell_repo_scope_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/status.sh"
source "$ROOT/modules/repositories.sh"

converge_chatgpt_gpg_key() { return 0; }
install_dnf_packages() { return 0; }
enable_copr() { printf '%s\n' "$1"; }
install_rpmfusion() { :; }
dnf_makecache() { :; }
validate_repository_configuration() { :; }

DESKTOP_SHELL=noctalia
noctalia_repos="$(configure_repositories)"
DESKTOP_SHELL=aurelia
aurelia_repos="$(configure_repositories)"
printf 'noctalia_has_quickshell=%s aurelia_has_quickshell=%s\n' \
    "$([[ "$noctalia_repos" == *errornointernet/quickshell* ]] && echo 1 || echo 0)" \
    "$([[ "$aurelia_repos" == *errornointernet/quickshell* ]] && echo 1 || echo 0)"
EOS
)"
if grep -q 'noctalia_has_quickshell=0 aurelia_has_quickshell=1' <<< "$quickshell_repo_scope_output"; then
    pass "stable Quickshell release source is enabled only for Aurelia"
else
    fail "Quickshell release COPR scope is incorrect: $quickshell_repo_scope_output"
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

    local expected_desktop_shell="noctalia"
    if [[ "$file" == *"/profiles/vm.conf" ]]; then
        expected_desktop_shell="aurelia"
    fi

    if [[ "$DESKTOP_SHELL" != "$expected_desktop_shell" ]]; then
        fail "$file DESKTOP_SHELL is not $expected_desktop_shell"
    else
        pass "$file DESKTOP_SHELL=$expected_desktop_shell"
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
