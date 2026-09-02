#!/usr/bin/env bash

# Local static and unit tests for the Fedora Hyprland workstation installer.
# These tests do not provision a VM and do not modify the host desktop.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FAILS=0
PASSES=0

pass() {
    PASSES=$((PASSES + 1))
    printf '  PASS %s\n' "$*"
}

fail() {
    FAILS=$((FAILS + 1))
    printf '  FAIL %s\n' "$*"
}

section() {
    printf '\n== %s ==\n' "$*"
}

###############################################################################
# bash -n / shellcheck
###############################################################################

section "Syntax"

mapfile -t BASH_FILES < <(
    find "$ROOT" -type f -name '*.sh' | sort
)

for file in "${BASH_FILES[@]}"; do
    if bash -n "$file"; then
        pass "bash -n ${file#"$ROOT"/}"
    else
        fail "bash -n ${file#"$ROOT"/}"
    fi
done

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck --shell=bash \
        --exclude=SC1090,SC1091,SC2034,SC2154,SC2329 \
        "${BASH_FILES[@]}"; then
        pass "shellcheck"
    else
        fail "shellcheck"
    fi
else
    printf '  SKIP shellcheck (not installed)\n'
fi

###############################################################################
# Duplicate functions
###############################################################################

section "Duplicate function definitions"

dupes="$(
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$ROOT"/modules/*.sh |
        sed 's/() {//' |
        grep -vx die |
        sort |
        uniq -d || true
)"

if [[ -z "$dupes" ]]; then
    pass "no duplicate function names across modules"
else
    fail "duplicate functions: $dupes"
fi

###############################################################################
# Referenced paths
###############################################################################

section "Repository paths"

required_paths=(
    install.sh
    config/versions.conf
    config/noctalia-greeter/greeter.toml
    packages/base.txt
    packages/desktop.txt
    packages/media.txt
    packages/diagnostics.txt
    dotfiles/nvim/init.lua
    profiles/vm.conf
    profiles/workstation.conf
    modules/common.sh
    modules/status.sh
    modules/state.sh
    modules/repositories.sh
    modules/packages.sh
    modules/shell.sh
    modules/browsers.sh
    modules/applications.sh
    modules/flatpak.sh
    modules/desktop.sh
    modules/nix.sh
    modules/containers.sh
    modules/validation.sh
    dotfiles/zsh/.zshrc
    dotfiles/starship/starship.toml
    dotfiles/kitty/kitty.conf
    dotfiles/hypr/hyprland.lua
)

for rel in "${required_paths[@]}"; do
    if [[ -e "$ROOT/$rel" ]]; then
        pass "exists $rel"
    else
        fail "missing $rel"
    fi
done

###############################################################################
# Manifests
###############################################################################

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
assert_in_manifest packages/diagnostics.txt duf
assert_in_manifest packages/diagnostics.txt ncdu
assert_in_manifest packages/diagnostics.txt btrfs-progs

if grep -vE '^\s*#' "$ROOT"/packages/base.txt | grep -qw chromium; then
    fail "chromium belongs in the browser module, not base.txt"
else
    pass "chromium is not in base.txt"
fi

###############################################################################
# Profile variables
###############################################################################

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

###############################################################################
# Function coverage
###############################################################################

section "Installer steps resolve to functions"

needed_functions=(
    prepare_system
    configure_repositories
    install_packages
    configure_shell
    install_browsers
    install_applications
    install_cursor
    configure_cursor_flags
    install_chatgpt
    install_kate
    install_media_applications
    install_media_utilities
    install_antigravity
    deploy_nvim_config
    configure_flatpak
    install_flatpak_applications
    install_localsend
    install_ulaa
    install_desktop
    install_nix
    configure_containers
    validate_system
    activate_graphical_session
    run_classified_step
    run_with_timeout
    record_deferred
    record_required
    record_activation_failure
    installer_exit_code
    clone_pinned_git
    validate_hyprland_desktop
    validate_greeter_configuration
    validate_graphical_activation
    validate_login_stack
    validate_diagnostics_environment
    validate_workstation_environment
    activate_graphical_session
)

defined="$(
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' "$ROOT"/modules/*.sh |
        sed 's/() {//'
)"

for fn in "${needed_functions[@]}"; do
    if printf '%s\n' "$defined" | grep -Fxq "$fn"; then
        pass "function $fn"
    else
        fail "missing function $fn"
    fi
done

if grep -R "command -v hyprpolkitagent" "$ROOT"/modules >/dev/null; then
    fail "bogus hyprpolkitagent PATH check is present"
else
    pass "no PATH check for hyprpolkitagent"
fi

if grep -R "systemctl enable --now greetd" "$ROOT"/modules "$ROOT"/install.sh >/dev/null; then
    fail "greetd must not be enable --now"
else
    pass "greetd is not enable --now"
fi

if grep -R "user = \"greeter\"" "$ROOT" >/dev/null; then
    fail "greeter user must not be used"
else
    pass "greetd user is used, not greeter"
fi

if grep -q 'command -v timeout' "$ROOT/install.sh"; then
    pass "install.sh enforces timeout capability preflight check"
else
    fail "install.sh missing timeout preflight check"
fi

###############################################################################
# Helpers: retry / status / manifests
###############################################################################

section "Helper behaviour"

HELPER_ROOT="$ROOT"
export HELPER_ROOT

helper_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/packages.sh"

RETRY_BACKOFF_SECONDS=(0 0)
attempts=0
flaky() {
    attempts=$((attempts + 1))
    if (( attempts < 3 )); then
        return 1
    fi
    return 0
}

if ! run_with_retry "flaky helper" flaky; then
    echo "retry-fail"
    exit 1
fi
echo "retry-ok attempts=$attempts"

never() { return 1; }
if run_with_retry "never" never; then
    echo "retry-should-fail"
    exit 1
fi
echo "retry-gave-up"

record_success "alpha"
echo "exit-success=$(installer_exit_code)"

record_deferred "browsers" "ulaa" "unsupported"
echo "exit-deferred=$(installer_exit_code)"
echo "deferred-blocked=$ACTIVATION_BLOCKED"

record_required "browsers" "chromium" "missing"
echo "exit-required=$(installer_exit_code)"
echo "required-blocked=$ACTIVATION_BLOCKED"

record_required "nix" "devenv" "missing"
echo "nix-blocked=$ACTIVATION_BLOCKED"

record_required "containers" "podman" "missing"
echo "podman-blocked=$ACTIVATION_BLOCKED"

record_activation_failure "desktop" "hyprland" "missing"
echo "exit-login=$(installer_exit_code)"
echo "login-blocked=$ACTIVATION_BLOCKED"

packages=()
while IFS= read -r package; do
    packages+=("$package")
done < <(read_package_manifest "$SCRIPT_DIR/packages/desktop.txt")

if [[ ${#packages[@]} -lt 5 ]]; then
    echo "manifest-too-small"
    exit 1
fi
echo "manifest-count=${#packages[@]}"

if printf '%s\n' "${packages[@]}" | grep -qx "adwaita-cursor-theme"; then
    echo "manifest-cursor-ok"
else
    echo "manifest-cursor-missing"
    exit 1
fi

# Package helpers and manifest validation
if package_installed wget2-wget; then
    echo "pkg-installed-wget2-ok"
fi

if package_installed 7zip; then
    echo "pkg-installed-7zip-ok"
fi

if package_installed 7zip-standalone; then
    echo "pkg-installed-7zip-sa-ok"
fi

if package_installed wget; then
    echo "pkg-installed-wget-cap-ok"
fi

if ! package_installed nonexistent-pkg-fake; then
    echo "pkg-installed-nonexistent-fail-ok"
fi

if package_available wget2-wget; then
    echo "pkg-avail-wget2-ok"
fi

if package_available 7zip; then
    echo "pkg-avail-7zip-ok"
fi

if package_available 7zip-standalone; then
    echo "pkg-avail-7zip-sa-ok"
fi

if package_available wget; then
    echo "pkg-avail-wget-cap-ok"
fi

if ! package_available nonexistent-pkg-fake; then
    echo "pkg-avail-nonexistent-fail-ok"
fi

if validate_manifest_packages "$SCRIPT_DIR/packages/base.txt"; then
    echo "validate-base-manifest-ok"
fi

if validate_manifest_packages "$SCRIPT_DIR/packages/diagnostics.txt"; then
    echo "validate-diagnostics-manifest-ok"
fi

if validate_manifest_packages "$SCRIPT_DIR/packages/media.txt"; then
    echo "validate-media-manifest-ok"
fi

if package_available kate; then
    echo "pkg-avail-kate-ok"
fi

if package_available mediainfo; then
    echo "pkg-avail-mediainfo-ok"
fi

if package_available mkvtoolnix; then
    echo "pkg-avail-mkvtoolnix-ok"
fi

if package_available smartmontools; then
    echo "pkg-avail-smartmontools-ok"
fi

if package_available inxi; then
    echo "pkg-avail-inxi-ok"
fi

if package_available iotop-c; then
    echo "pkg-avail-iotop-c-ok"
fi

if grep -Fxq "iotop-c" "$SCRIPT_DIR/packages/diagnostics.txt"; then
    echo "iotop-c-in-manifest-ok"
fi

if grep -Fq "iotop" "$SCRIPT_DIR/modules/validation.sh" && ! grep -Fq "iotop-c" "$SCRIPT_DIR/modules/validation.sh"; then
    echo "iotop-cmd-in-validation-ok"
fi

if grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$SCRIPT_DIR/dotfiles/zsh/.zshrc"; then
    echo "zshrc-local-bin-path-ok"
fi

tmp_manifest="$(mktemp)"
echo "nonexistent-pkg-fake" > "$tmp_manifest"
if ! validate_manifest_packages "$tmp_manifest" 2>/dev/null; then
    echo "validate-invalid-manifest-rejected-ok"
fi
if ! install_manifest "$tmp_manifest" 2>/dev/null; then
    echo "install-invalid-manifest-rejected-ok"
fi
rm -f "$tmp_manifest"
EOS
)"

if printf '%s\n' "$helper_output" | grep -q 'retry-ok attempts=3'; then
    pass "retry succeeds on third attempt"
else
    fail "retry helper: $helper_output"
fi

if printf '%s\n' "$helper_output" | grep -q 'retry-gave-up'; then
    pass "retry classifies permanent failure"
else
    fail "retry did not give up as expected"
fi

if printf '%s\n' "$helper_output" | grep -q 'exit-success=0'; then
    pass "exit code 0 for success"
else
    fail "success exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'exit-deferred=2'; then
    pass "exit code 2 for deferred"
else
    fail "deferred exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'deferred-blocked=0'; then
    pass "deferred failure does not block activation"
else
    fail "deferred activation blocking"
fi

if printf '%s\n' "$helper_output" | grep -q 'exit-required=1'; then
    pass "exit code 1 for required non-login failure"
else
    fail "required exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'required-blocked=0'; then
    pass "missing Chromium does not set ACTIVATION_BLOCKED"
else
    fail "Chromium must not block activation"
fi

if printf '%s\n' "$helper_output" | grep -q 'nix-blocked=0'; then
    pass "missing Nix/devenv does not set ACTIVATION_BLOCKED"
else
    fail "Nix must not block activation"
fi

if printf '%s\n' "$helper_output" | grep -q 'podman-blocked=0'; then
    pass "missing Podman does not set ACTIVATION_BLOCKED"
else
    fail "Podman must not block activation"
fi

if printf '%s\n' "$helper_output" | grep -q 'exit-login=1'; then
    pass "exit code 1 for login-critical failure"
else
    fail "login-critical exit code"
fi

if printf '%s\n' "$helper_output" | grep -q 'login-blocked=1'; then
    pass "Hyprland validation failure sets ACTIVATION_BLOCKED=1"
else
    fail "Hyprland must block activation"
fi

if printf '%s\n' "$helper_output" | grep -q 'manifest-cursor-ok'; then
    pass "desktop manifest parsing"
else
    fail "desktop manifest parsing: $helper_output"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-wget2-ok'; then
    pass "package_installed wget2-wget"
else
    fail "package_installed wget2-wget"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-7zip-ok'; then
    pass "package_installed 7zip"
else
    fail "package_installed 7zip"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-7zip-sa-ok'; then
    pass "package_installed 7zip-standalone"
else
    fail "package_installed 7zip-standalone"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-wget-cap-ok'; then
    pass "package_installed resolves wget capability"
else
    fail "package_installed resolves wget capability"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-installed-nonexistent-fail-ok'; then
    pass "package_installed rejects nonexistent package"
else
    fail "package_installed rejects nonexistent package"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-wget2-ok'; then
    pass "package_available wget2-wget"
else
    fail "package_available wget2-wget"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-7zip-ok'; then
    pass "package_available 7zip"
else
    fail "package_available 7zip"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-7zip-sa-ok'; then
    pass "package_available 7zip-standalone"
else
    fail "package_available 7zip-standalone"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-wget-cap-ok'; then
    pass "package_available resolves wget capability"
else
    fail "package_available resolves wget capability"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-nonexistent-fail-ok'; then
    pass "package_available rejects nonexistent package"
else
    fail "package_available rejects nonexistent package"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-kate-ok'; then
    pass "package_available kate"
else
    fail "package_available kate"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-mediainfo-ok'; then
    pass "package_available mediainfo"
else
    fail "package_available mediainfo"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-mkvtoolnix-ok'; then
    pass "package_available mkvtoolnix"
else
    fail "package_available mkvtoolnix"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-smartmontools-ok'; then
    pass "package_available smartmontools"
else
    fail "package_available smartmontools"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-inxi-ok'; then
    pass "package_available inxi"
else
    fail "package_available inxi"
fi

if printf '%s\n' "$helper_output" | grep -q 'pkg-avail-iotop-c-ok'; then
    pass "package_available iotop-c"
else
    fail "package_available iotop-c"
fi

if printf '%s\n' "$helper_output" | grep -q 'iotop-c-in-manifest-ok'; then
    pass "packages/diagnostics.txt contains package iotop-c"
else
    fail "packages/diagnostics.txt missing package iotop-c"
fi

if printf '%s\n' "$helper_output" | grep -q 'iotop-cmd-in-validation-ok'; then
    pass "modules/validation.sh validates command iotop, not iotop-c"
else
    fail "modules/validation.sh must validate command iotop, not iotop-c"
fi

if printf '%s\n' "$helper_output" | grep -q 'zshrc-local-bin-path-ok'; then
    pass "zshrc exports ~/.local/bin in PATH"
else
    fail "zshrc missing ~/.local/bin in PATH"
fi

if printf '%s\n' "$helper_output" | grep -q 'validate-base-manifest-ok'; then
    pass "validate_manifest_packages succeeds on base.txt"
else
    fail "validate_manifest_packages fails on base.txt"
fi

if printf '%s\n' "$helper_output" | grep -q 'validate-diagnostics-manifest-ok'; then
    pass "validate_manifest_packages succeeds on diagnostics.txt"
else
    fail "validate_manifest_packages fails on diagnostics.txt"
fi

if printf '%s\n' "$helper_output" | grep -q 'validate-media-manifest-ok'; then
    pass "validate_manifest_packages succeeds on media.txt"
else
    fail "validate_manifest_packages fails on media.txt"
fi

if printf '%s\n' "$helper_output" | grep -q 'validate-invalid-manifest-rejected-ok'; then
    pass "validate_manifest_packages rejects nonexistent package"
else
    fail "validate_manifest_packages does not reject nonexistent package"
fi

if printf '%s\n' "$helper_output" | grep -q 'install-invalid-manifest-rejected-ok'; then
    pass "install_manifest rejects invalid manifest"
else
    fail "install_manifest does not reject invalid manifest"
fi

###############################################################################
# Timeout & Hang resilience
###############################################################################

section "Timeout & hang resilience"

timeout_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

# 1 & 2. run_with_timeout terminates sleeping child and returns 124, child PID is gone
test_cmd_pid_file="$(mktemp)"
child_runner="$(mktemp)"
cat > "$child_runner" << 'RUNNER'
#!/usr/bin/env bash
echo "$$" > "$1"
exec sleep 10
RUNNER
chmod +x "$child_runner"

start_time=$(date +%s)
status=0
run_with_timeout 1 "sleep test" "$child_runner" "$test_cmd_pid_file" || status=$?
end_time=$(date +%s)
elapsed=$((end_time - start_time))

tracked_timeout_pid="$(cat "$test_cmd_pid_file" 2>/dev/null || true)"

if (( status == 124 )) && (( elapsed < 5 )); then
    echo "timeout-terminated-ok"
fi

sleep 0.2
if [[ -n "$tracked_timeout_pid" ]] && ! kill -0 "$tracked_timeout_pid" 2>/dev/null; then
    echo "timeout-tracked-child-dead-ok"
fi
rm -f "$child_runner" "$test_cmd_pid_file"

# 3. run_with_retry retries a timed-out command
RETRY_BACKOFF_SECONDS=(0 0)
retry_test_script="$(mktemp)"
cat > "$retry_test_script" << 'SCRIPT'
#!/usr/bin/env bash
count_file="$1"
count=0
if [[ -f "$count_file" ]]; then
    count=$(cat "$count_file")
fi
count=$((count + 1))
echo "$count" > "$count_file"
if (( count < 3 )); then
    sleep 5
fi
exit 0
SCRIPT
chmod +x "$retry_test_script"

count_file="$(mktemp)"
echo 0 > "$count_file"

retry_timeout_status=0
run_with_retry "flaky timeout command" run_with_timeout 1 "flaky timeout attempt" "$retry_test_script" "$count_file" || retry_timeout_status=$?

final_count=$(cat "$count_file")
if (( retry_timeout_status == 0 )) && (( final_count == 3 )); then
    echo "retry-on-timeout-ok"
fi
rm -f "$retry_test_script" "$count_file"

# 4. Missing timeout command fails closed with 127
missing_timeout_status=0
(
    PATH=""
    run_with_timeout 5 "missing timeout check" true || exit $?
) 2>/dev/null || missing_timeout_status=$?

if (( missing_timeout_status == 127 )); then
    echo "timeout-missing-fail-closed-ok"
fi

# 5. Invalid non-positive timeout fails closed with nonzero status
invalid_timeout_status=0
run_with_timeout 0 "invalid timeout check" true 2>/dev/null || invalid_timeout_status=$?

if (( invalid_timeout_status != 0 )); then
    echo "timeout-invalid-fail-closed-ok"
fi

# 6. package_available distinguishes available (0), unavailable (1), and timeout/error (2)
pkg_avail_ok_status=0
package_available kate || pkg_avail_ok_status=$?
if (( pkg_avail_ok_status == 0 )); then
    echo "pkg-avail-status-0-ok"
fi

pkg_unavail_status=0
package_available nonexistent-pkg-fake-name-xyz || pkg_unavail_status=$?
if (( pkg_unavail_status == 1 )); then
    echo "pkg-unavail-status-1-ok"
fi

# Mock timeout in package_available
TIMEOUT_METADATA_SECONDS=1
pkg_timeout_script="$(mktemp)"
cat > "$pkg_timeout_script" << 'MOCK'
#!/usr/bin/env bash
sleep 5
MOCK
chmod +x "$pkg_timeout_script"

pkg_timeout_status=0
(
    run_with_timeout() { return 124; }
    package_available fake-pkg-timed-out || exit $?
) 2>/dev/null || pkg_timeout_status=$?

if (( pkg_timeout_status == 2 )); then
    echo "pkg-timeout-status-2-ok"
fi
rm -f "$pkg_timeout_script"

# 7. Timeout in non-login stage produces exit code 1 without blocking activation
ACTIVATION_BLOCKED=0
timed_out_stage() {
    run_with_timeout 1 "non-login hang" sleep 5
}

run_classified_step workstation "Simulated hanging workstation stage" timed_out_stage || true
echo "workstation-timeout-blocked=$ACTIVATION_BLOCKED"
echo "workstation-timeout-exit=$(installer_exit_code)"

# 8. Timeout in login-critical stage produces exit code 1 and blocks activation
ACTIVATION_BLOCKED=0
login_hang_stage() {
    run_with_timeout 1 "login-critical hang" sleep 5
}

run_classified_step login "Simulated hanging login stage" login_hang_stage || true
echo "login-timeout-blocked=$ACTIVATION_BLOCKED"
echo "login-timeout-exit=$(installer_exit_code)"

# 9. Real SIGINT interrupt and process cleanup test with full install.sh on_exit semantics
sigint_pid_file="$(mktemp)"
sigint_test_script="$(mktemp)"
cat > "$sigint_test_script" << 'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$1"
PID_FILE="$2"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

INTERRUPTED_SIGNAL=0

cleanup_installer_children() {
    stop_sudo_keepalive
    if [[ -n "${ACTIVE_TIMEOUT_PID:-}" ]]; then
        kill -TERM "$ACTIVE_TIMEOUT_PID" 2>/dev/null || true
        wait "$ACTIVE_TIMEOUT_PID" 2>/dev/null || true
        ACTIVE_TIMEOUT_PID=""
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -P "$$" 2>/dev/null || true
    fi
}

on_interrupt() {
    local sig="${1:-INT}"
    cleanup_installer_children
    ACTIVATION_BLOCKED=1
    record_critical "installer" "interrupt" "Received signal $sig." 1

    if [[ "$sig" == "TERM" ]]; then
        INTERRUPTED_SIGNAL=143
        exit 143
    else
        INTERRUPTED_SIGNAL=130
        exit 130
    fi
}

on_exit() {
    local code=$?
    cleanup_installer_children

    local final_code
    if (( INTERRUPTED_SIGNAL != 0 )); then
        final_code="$INTERRUPTED_SIGNAL"
    elif (( code >= 128 )); then
        final_code="$code"
    else
        final_code="$(installer_exit_code)"
    fi
    exit "$final_code"
}

trap 'on_interrupt INT' INT
trap 'on_interrupt TERM' TERM
trap on_exit EXIT

worker_script="$(mktemp)"
cat > "$worker_script" << 'WORKER'
#!/usr/bin/env bash
echo "$$" > "$1"
exec sleep 30
WORKER
chmod +x "$worker_script"

run_with_timeout 30 "sigint test long sleep" "$worker_script" "$PID_FILE"
SCRIPT
chmod +x "$sigint_test_script"

set -m
"$sigint_test_script" "$SCRIPT_DIR" "$sigint_pid_file" 2>/dev/null &
CHILD_INSTALLER_PID=$!
set +m
sleep 0.4

tracked_worker_pid="$(cat "$sigint_pid_file" 2>/dev/null || true)"

# Send SIGINT to the running child installer script
kill -INT "$CHILD_INSTALLER_PID" 2>/dev/null || true
child_exit_code=0
wait "$CHILD_INSTALLER_PID" 2>/dev/null || child_exit_code=$?

sleep 0.2
if (( child_exit_code == 130 )); then
    echo "sigint-exit-130-ok"
fi

if [[ -n "$tracked_worker_pid" ]] && ! kill -0 "$tracked_worker_pid" 2>/dev/null; then
    echo "sigint-tracked-worker-dead-ok"
fi
rm -f "$sigint_test_script" "$sigint_pid_file"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$timeout_output" | grep -q 'timeout-terminated-ok'; then
    pass "run_with_timeout terminates hung command and returns exit code 124"
else
    fail "run_with_timeout termination failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'timeout-tracked-child-dead-ok'; then
    pass "no orphan processes remain after timeout (tracked child PID terminated)"
else
    fail "orphan process detected after timeout: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'retry-on-timeout-ok'; then
    pass "run_with_retry retries timed-out operations"
else
    fail "run_with_retry did not retry on timeout: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'timeout-missing-fail-closed-ok'; then
    pass "run_with_timeout fails closed when timeout utility is missing (127)"
else
    fail "run_with_timeout did not fail closed on missing timeout: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'timeout-invalid-fail-closed-ok'; then
    pass "run_with_timeout fails closed on non-positive timeout values"
else
    fail "run_with_timeout did not fail closed on invalid timeout: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'pkg-avail-status-0-ok'; then
    pass "package_available returns 0 for available packages"
else
    fail "package_available status 0 failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'pkg-unavail-status-1-ok'; then
    pass "package_available returns 1 for cleanly absent packages"
else
    fail "package_available status 1 failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'pkg-timeout-status-2-ok'; then
    pass "package_available returns 2 on repository timeout/failure"
else
    fail "package_available status 2 failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'workstation-timeout-blocked=0'; then
    pass "workstation operation timeout does not block graphical activation"
else
    fail "workstation operation timeout blocked graphical activation: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'workstation-timeout-exit=1'; then
    pass "workstation operation timeout produces exit code 1"
else
    fail "workstation operation timeout exit code: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'login-timeout-blocked=1'; then
    pass "login-critical operation timeout blocks graphical activation"
else
    fail "login-critical operation timeout did not block activation: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'login-timeout-exit=1'; then
    pass "login-critical operation timeout produces exit code 1"
else
    fail "login-critical operation timeout exit code: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'sigint-exit-130-ok'; then
    pass "SIGINT preserves final exit status 130 through EXIT trap finalization"
else
    fail "SIGINT final exit status 130 failed: $timeout_output"
fi

if printf '%s\n' "$timeout_output" | grep -q 'sigint-tracked-worker-dead-ok'; then
    pass "SIGINT cleans tracked child process without killing parent test shell"
else
    fail "SIGINT child process cleanup failed: $timeout_output"
fi

###############################################################################
# Orchestration: non-login failures cannot skip safe activation
###############################################################################

section "Activation orchestration"

orch_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

validate_hyprland_desktop() { return 0; }
validate_greeter_configuration() { return 0; }
enable_greetd() { :; }
configure_graphical_target() { :; }
validate_graphical_activation() { return 0; }

unexpected_podman() { return 9; }

run_classified_step workstation "podman" unexpected_podman
echo "after-unexpected-blocked=$ACTIVATION_BLOCKED"
echo "after-unexpected-exit=$(installer_exit_code)"

run_classified_step login "activate" activate_graphical_session
echo "after-podman-activation=$GRAPHICAL_ACTIVATION_STATE"
echo "after-podman-blocked=$ACTIVATION_BLOCKED"
echo "after-podman-exit=$(installer_exit_code)"
EOS
)"

if printf '%s\n' "$orch_output" | grep -q 'after-unexpected-blocked=0'; then
    pass "uncaught Podman failure does not set ACTIVATION_BLOCKED"
else
    fail "uncaught Podman blocked activation: $orch_output"
fi

if printf '%s\n' "$orch_output" | grep -q 'after-unexpected-exit=1'; then
    pass "uncaught required non-login failure produces exit code 1"
else
    fail "uncaught non-login exit code: $orch_output"
fi

if printf '%s\n' "$orch_output" | grep -q 'after-podman-activation=completed'; then
    pass "required non-login failure still permits activate_graphical_session"
else
    fail "activation skipped after Podman failure: $orch_output"
fi

greeter_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

INSTALL_GREETER=true
ENABLE_GRAPHICAL_TARGET=true

validate_hyprland_desktop() { return 0; }
validate_greeter_configuration() { return 1; }

activate_graphical_session
echo "greeter-blocked=$ACTIVATION_BLOCKED"
echo "greeter-activation=$GRAPHICAL_ACTIVATION_STATE"
echo "greeter-exit=$(installer_exit_code)"
EOS
)"

if printf '%s\n' "$greeter_output" | grep -q 'greeter-blocked=1'; then
    pass "greetd/Noctalia greeter validation failure sets ACTIVATION_BLOCKED=1"
else
    fail "greeter must block activation: $greeter_output"
fi

if printf '%s\n' "$greeter_output" | grep -q 'greeter-activation=skipped'; then
    pass "activation is skipped when ACTIVATION_BLOCKED=1"
else
    fail "activation not skipped: $greeter_output"
fi

skip_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

enabled=0
enable_greetd() { enabled=1; }
configure_graphical_target() { enabled=1; }

ACTIVATION_BLOCKED=1
activate_graphical_session
echo "skip-enable=$enabled"
echo "skip-state=$GRAPHICAL_ACTIVATION_STATE"
EOS
)"

if printf '%s\n' "$skip_output" | grep -q 'skip-enable=0' &&
    printf '%s\n' "$skip_output" | grep -q 'skip-state=skipped'; then
    pass "blocked activation does not enable greetd"
else
    fail "blocked activation still enabled greetd: $skip_output"
fi

###############################################################################
# Greeter cursor config
###############################################################################

section "Greeter cursor"

if grep -q 'theme = "Adwaita"' "$ROOT/config/noctalia-greeter/greeter.toml" &&
    grep -q 'size = 24' "$ROOT/config/noctalia-greeter/greeter.toml"; then
    pass "managed greeter.toml sets Adwaita 24"
else
    fail "managed greeter.toml cursor block"
fi

###############################################################################
# Pinned versions
###############################################################################

section "Pins"

# shellcheck source=/dev/null
source "$ROOT/config/versions.conf"

pins=(
    OH_MY_ZSH_COMMIT
    ZSH_AUTOSUGGESTIONS_COMMIT
    ZSH_SYNTAX_HIGHLIGHTING_COMMIT
    NIXPKGS_REV
    DEVENV_NIX_INSTALL_SPEC
    ANTIGRAVITY_VERSION
    ANTIGRAVITY_URL
    ANTIGRAVITY_SHA512
    CCEXTRACTOR_VERSION
    CCEXTRACTOR_URL
    CCEXTRACTOR_SHA512
    BENTO4_VERSION
    BENTO4_URL
    BENTO4_SHA512
    SHAKA_PACKAGER_VERSION
    SHAKA_PACKAGER_URL
    SHAKA_PACKAGER_SHA512
    DOVI_TOOL_VERSION
    DOVI_TOOL_URL
    DOVI_TOOL_SHA512
    N_M3U8DL_RE_VERSION
    N_M3U8DL_RE_URL
    N_M3U8DL_RE_SHA512
)

for var in "${pins[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        pass "pin $var"
    else
        fail "pin missing $var"
    fi
done

if [[ "$DEVENV_NIX_INSTALL_SPEC" == *nixpkgs#devenv && "$DEVENV_NIX_INSTALL_SPEC" != *"github:NixOS/nixpkgs/"* ]]; then
    fail "devenv install spec is unpinned nixpkgs#devenv"
else
    pass "devenv install spec is pinned"
fi

url_vars=(
    ANTIGRAVITY_URL
    CCEXTRACTOR_URL
    BENTO4_URL
    SHAKA_PACKAGER_URL
    DOVI_TOOL_URL
    N_M3U8DL_RE_URL
)

for uvar in "${url_vars[@]}"; do
    if [[ "${!uvar}" =~ ^https:// ]]; then
        pass "$uvar is HTTPS"
    else
        fail "$uvar is not HTTPS: ${!uvar}"
    fi
done

sha_vars=(
    ANTIGRAVITY_SHA512
    CCEXTRACTOR_SHA512
    BENTO4_SHA512
    SHAKA_PACKAGER_SHA512
    DOVI_TOOL_SHA512
    N_M3U8DL_RE_SHA512
)

for svar in "${sha_vars[@]}"; do
    if [[ "${!svar}" =~ ^[0-9a-f]{128}$ ]]; then
        pass "$svar is valid 128-character hex"
    else
        fail "$svar is not valid sha512: ${!svar}"
    fi
done

###############################################################################
# Subsystem Tests
###############################################################################

section "Neovim Default Configuration"

expected_nvim_content=$'vim.opt.number = true\nvim.opt.relativenumber = true\nvim.opt.ignorecase = true\nvim.opt.smartcase = true\nvim.opt.clipboard = \'unnamedplus\'\nvim.opt.undofile = true\nvim.opt.scrolloff = 8'

actual_nvim_content="$(cat "$ROOT/dotfiles/nvim/init.lua" 2>/dev/null || true)"
# Trim trailing whitespace/newlines for strict comparison
actual_nvim_content_trimmed="$(printf '%s' "$actual_nvim_content" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [[ "$actual_nvim_content_trimmed" == "$expected_nvim_content" ]]; then
    pass "Neovim init.lua content matches exact required baseline"
else
    fail "Neovim init.lua content differs from required baseline"
fi

if grep -q "deploy_nvim_config" "$ROOT/modules/shell.sh"; then
    pass "shell.sh defines and invokes deploy_nvim_config"
else
    fail "shell.sh missing deploy_nvim_config"
fi

if grep -q "nvim/init.lua" "$ROOT/modules/validation.sh"; then
    pass "validation.sh validates Neovim config file"
else
    fail "validation.sh does not validate Neovim config"
fi

section "Host-Global Media Utilities"

if [[ -d "$ROOT/environments/media-tools" ]]; then
    fail "environments/media-tools should be removed"
else
    pass "environments/media-tools is removed"
fi

media_expected_tools=(ffmpeg ffprobe mediainfo mkvmerge MP4Box ccextractor mp4dump packager dovi_tool N_m3u8DL-RE)
for mtool in "${media_expected_tools[@]}"; do
    if grep -qF "$mtool" "$ROOT/modules/validation.sh"; then
        pass "validation.sh checks media tool runtime command: $mtool"
    else
        fail "validation.sh missing runtime check for $mtool"
    fi
done

section "Ulaa Browser Flatpak Integration"

if grep -q "com.ulaa.Ulaa" "$ROOT/modules/flatpak.sh"; then
    pass "flatpak.sh targets Flathub app ID com.ulaa.Ulaa"
else
    fail "flatpak.sh missing Flathub app ID com.ulaa.Ulaa"
fi

if grep -q "com.ulaa.Ulaa" "$ROOT/modules/validation.sh"; then
    pass "validation.sh checks com.ulaa.Ulaa Flatpak"
else
    fail "validation.sh missing com.ulaa.Ulaa check"
fi

section "ChatGPT Desktop Application"

if grep -q "https://persistent.oaistatic.com/codex-app-prod/linux/rpm" "$ROOT/modules/applications.sh"; then
    pass "applications.sh configures official ChatGPT RPM repository"
else
    fail "applications.sh missing official ChatGPT RPM repository URL"
fi

if grep -q "install_dnf_packages chatgpt" "$ROOT/modules/applications.sh"; then
    pass "applications.sh installs chatgpt package"
else
    fail "applications.sh missing chatgpt package installation"
fi

section "Cursor Window Controls and Wayland Integration"

if grep -q -- "--ozone-platform=wayland" "$ROOT/modules/applications.sh" &&
   grep -q -- "--enable-features=UseOzonePlatform" "$ROOT/modules/applications.sh"; then
    pass "applications.sh configures Cursor Wayland Ozone flags"
else
    fail "applications.sh missing Cursor Wayland Ozone flags"
fi

if grep -q "cursor-flags.conf" "$ROOT/modules/validation.sh"; then
    pass "validation.sh validates cursor-flags.conf"
else
    fail "validation.sh does not validate cursor-flags.conf"
fi

section "GNOME Keyring PAM Auto-Unlock"

if grep -q "pam_gnome_keyring.so" "$ROOT/modules/validation.sh"; then
    pass "validation.sh validates pam_gnome_keyring.so"
else
    fail "validation.sh does not validate pam_gnome_keyring.so"
fi

section "Appearance and Qt Settings"

if grep -q "QT_QPA_PLATFORMTHEME,qt6ct" "$ROOT/dotfiles/hypr/startup.lua"; then
    pass "startup.lua exports QT_QPA_PLATFORMTHEME,qt6ct"
else
    fail "startup.lua missing QT_QPA_PLATFORMTHEME,qt6ct"
fi

if git -C "$ROOT" ls-files | grep -q "dotfiles/hypr/noctalia.lua"; then
    fail "untracked/dynamic noctalia.lua should not be tracked in git"
else
    pass "no dynamic noctalia.lua tracked in git"
fi

section "Resilience Semantics for Applications"

chatgpt_resilience_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

CHATGPT=true
configure_chatgpt_repository() { return 1; }
install_chatgpt
echo "chatgpt-blocked=$ACTIVATION_BLOCKED"
echo "chatgpt-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$chatgpt_resilience_output" | grep -q 'chatgpt-blocked=0'; then
    pass "ChatGPT repository failure does not set ACTIVATION_BLOCKED"
else
    fail "ChatGPT repository failure set ACTIVATION_BLOCKED: $chatgpt_resilience_output"
fi

if printf '%s\n' "$chatgpt_resilience_output" | grep -q 'chatgpt-exit=2'; then
    pass "ChatGPT failure produces deferred exit code 2"
else
    fail "ChatGPT failure did not produce exit code 2: $chatgpt_resilience_output"
fi

media_resilience_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

MEDIA_APPLICATIONS=true
install_dnf_packages() { return 1; }
install_media_applications
echo "media-blocked=$ACTIVATION_BLOCKED"
echo "media-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$media_resilience_output" | grep -q 'media-blocked=0'; then
    pass "Media applications failure does not set ACTIVATION_BLOCKED"
else
    fail "Media applications failure set ACTIVATION_BLOCKED: $media_resilience_output"
fi

if printf '%s\n' "$media_resilience_output" | grep -q 'media-exit=2'; then
    pass "Media applications failure produces deferred exit code 2"
else
    fail "Media applications failure did not produce exit code 2: $media_resilience_output"
fi

media_cli_decoupling_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

CURSOR=false
KATE=false
CHATGPT=false
ANTIGRAVITY=false
MEDIA_APPLICATIONS=false

media_cli_ran=0
install_media_utilities() {
    media_cli_ran=1
}

install_applications
echo "cli-ran-when-gui-disabled=$media_cli_ran"

MEDIA_APPLICATIONS=true
install_media_applications() {
    record_deferred "applications" "media-apps" "GUI media app failure"
}
media_cli_ran_after_gui_fail=0
install_media_utilities() {
    media_cli_ran_after_gui_fail=1
}

install_applications
echo "cli-ran-after-gui-fail=$media_cli_ran_after_gui_fail"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$media_cli_decoupling_output" | grep -q 'cli-ran-when-gui-disabled=1'; then
    pass "MEDIA_APPLICATIONS=false does not suppress install_media_utilities"
else
    fail "MEDIA_APPLICATIONS=false suppressed install_media_utilities: $media_cli_decoupling_output"
fi

if printf '%s\n' "$media_cli_decoupling_output" | grep -q 'cli-ran-after-gui-fail=1'; then
    pass "GUI media app failure does not prevent install_media_utilities"
else
    fail "GUI media app failure prevented install_media_utilities: $media_cli_decoupling_output"
fi

media_cli_failure_resilience="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

# Simulate media utility download failure
run_with_retry() { return 1; }
install_media_utilities
echo "cli-fail-blocked=$ACTIVATION_BLOCKED"
echo "cli-fail-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$media_cli_failure_resilience" | grep -q 'cli-fail-blocked=0'; then
    pass "Media CLI failure does not set ACTIVATION_BLOCKED"
else
    fail "Media CLI failure set ACTIVATION_BLOCKED: $media_cli_failure_resilience"
fi

if printf '%s\n' "$media_cli_failure_resilience" | grep -q 'cli-fail-exit=2'; then
    pass "Media CLI failure produces deferred exit code 2"
else
    fail "Media CLI failure did not produce exit code 2: $media_cli_failure_resilience"
fi

media_validation_decoupling="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/validation.sh"

MEDIA_APPLICATIONS=false
CURSOR=false
CHATGPT=false
KATE=false
LOCALSEND=false
ANTIGRAVITY=false

command_exists() { return 1; }
validate_application_environment
echo "validation-def-count=$(grep -c 'Media utility command is missing' <(printf '%s\n' "${INSTALL_DEFERRED[@]}") || true)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$media_validation_decoupling" | grep -qE 'validation-def-count=[1-9]'; then
    pass "Media CLI validation runs independently of MEDIA_APPLICATIONS=false"
else
    fail "Media CLI validation did not run when MEDIA_APPLICATIONS=false: $media_validation_decoupling"
fi

# Antigravity architecture guard test
section "Antigravity architecture guard"
agy_arch_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

ANTIGRAVITY=true
uname() {
    if [[ "$1" == "-m" ]]; then
        echo "armv7l"
    else
        command uname "$@"
    fi
}
install_antigravity
echo "agy-arch-blocked=$ACTIVATION_BLOCKED"
echo "agy-arch-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$agy_arch_output" | grep -q 'agy-arch-blocked=0'; then
    pass "unsupported arch does not set ACTIVATION_BLOCKED"
else
    fail "unsupported arch set ACTIVATION_BLOCKED: $agy_arch_output"
fi

if printf '%s\n' "$agy_arch_output" | grep -q 'agy-arch-exit=2'; then
    pass "unsupported arch produces deferred exit code 2"
else
    fail "unsupported arch exit code: $agy_arch_output"
fi

# Ensure no credentials or auth state files are tracked in Git
section "Repository Hygiene"
if git -C "$ROOT" ls-files | grep -E '(\.auth|\.token|jetski_state|settings\.json|credentials|\.db|\.key|\.pem)'; then
    fail "sensitive or authentication file tracked in git"
else
    pass "no authentication or secret files tracked in git"
fi

###############################################################################
# Summary
###############################################################################

printf '\n%s\n' "------------------------------------------------------------"
printf 'Passed: %s  Failed: %s\n' "$PASSES" "$FAILS"

if (( FAILS > 0 )); then
    exit 1
fi

exit 0
