#!/usr/bin/env bash

# Test Suite: Workstation applications, browsers, editor configurations, and nix configuration preservation.

section "Neovim Default Configuration"

expected_nvim_content=$'vim.opt.number = true\nvim.opt.relativenumber = true\nvim.opt.ignorecase = true\nvim.opt.smartcase = true\nvim.opt.clipboard = \'unnamedplus\'\nvim.opt.undofile = true\nvim.opt.scrolloff = 8'

actual_nvim_content="$(cat "$ROOT/dotfiles/nvim/init.lua" 2>/dev/null || true)"
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

section "ChatGPT Official Bootstrap RPM Integration"

if grep -q "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt" "$ROOT/modules/applications.sh"; then
    pass "applications.sh uses official OpenAI bootstrap RPM URL"
else
    fail "applications.sh missing official OpenAI bootstrap RPM URL"
fi

if grep -q "chatgpt.repo" "$ROOT/modules/applications.sh"; then
    fail "applications.sh contains handcrafted chatgpt.repo instead of delegating to official RPM bootstrap"
else
    pass "applications.sh delegates repository configuration to official OpenAI bootstrap RPM"
fi

chatgpt_behavior_output="$(
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

# 1. Disabled profile performs no mutations
CHATGPT=false
download_called=0
install_called=0
curl() { download_called=1; }
sudo() { install_called=1; }
install_chatgpt
echo "disabled_no_mutation=$([[ $download_called -eq 0 && $install_called -eq 0 ]] && echo 1 || echo 0)"

# 2. Already-installed ChatGPT is completely idempotent
CHATGPT=true
package_installed() { [[ "$1" == "chatgpt" ]]; }
download_called=0
install_called=0
install_chatgpt
echo "idempotent_when_installed=$([[ $download_called -eq 0 && $install_called -eq 0 ]] && echo 1 || echo 0)"

# 3. Not installed invokes bootstrap download and dnf install
package_installed() { return 1; }
download_called=0
install_called=0
run_with_retry() {
    shift
    "$@"
}
run_with_timeout() {
    shift 2
    "$@"
}
curl() {
    download_called=1
    local out=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-o" ]]; then out="$2"; shift 2; continue; fi
        shift
    done
    touch "$out"
}
sudo() {
    install_called=1
    if [[ "$*" =~ dnf\ install\ -y ]]; then
        package_installed() { return 0; }
    fi
}
install_chatgpt
echo "bootstrap_invoked=$([[ $download_called -eq 1 && $install_called -eq 1 ]] && echo 1 || echo 0)"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'disabled_no_mutation=1'; then
    pass "install_chatgpt performs no mutations when CHATGPT=false"
else
    fail "install_chatgpt mutated system when CHATGPT=false: $chatgpt_behavior_output"
fi

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'idempotent_when_installed=1'; then
    pass "install_chatgpt is idempotent and avoids redundant downloads when already installed"
else
    fail "install_chatgpt attempted redundant installation when already installed: $chatgpt_behavior_output"
fi

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'bootstrap_invoked=1'; then
    pass "install_chatgpt downloads official RPM and delegates repository establishment to dnf install"
else
    fail "install_chatgpt failed bootstrap execution: $chatgpt_behavior_output"
fi

section "N_m3u8DL-RE Prerelease Policy"

n_m3u8dl_policy_output="$(
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

# Mock dependencies
command_exists() { return 1; }
dovi_ran=0
provision_verified_archive() {
    if [[ "$5" == "dovi_tool" ]]; then
        dovi_ran=1
        return 0
    fi
    # If N_m3u8DL-RE is called, fail test
    if [[ "$5" == "N_m3u8DL-RE" ]]; then
        echo "ERROR: N_m3u8DL-RE beta archive was provisioned!" >&2
        return 1
    fi
    return 0
}
provision_verified_binary() { return 0; }

install_media_utilities

echo "dovi_ran=$dovi_ran"
echo "deferred_recorded=$(grep -c 'Skipping N_m3u8DL-RE' <(printf '%s\n' "${INSTALL_DEFERRED[@]}") || true)"
echo "activation_blocked=$ACTIVATION_BLOCKED"
echo "exit_code=$(installer_exit_code)"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$n_m3u8dl_policy_output" | grep -q 'dovi_ran=1' &&
   printf '%s\n' "$n_m3u8dl_policy_output" | grep -q 'deferred_recorded=1' &&
   printf '%s\n' "$n_m3u8dl_policy_output" | grep -q 'activation_blocked=0' &&
   printf '%s\n' "$n_m3u8dl_policy_output" | grep -q 'exit_code=2'; then
    pass "normal installer skips N_m3u8DL-RE beta artifact and records deferred notice without blocking activation"
else
    fail "normal installer did not handle N_m3u8DL-RE prerelease correctly: $n_m3u8dl_policy_output"
fi

section "Upstream Prerelease Classification Logic"

prerelease_check_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/check-updates.sh"

# Test prerelease tags
p1=0; is_prerelease_tag "v0.6.0-beta" || p1=$?
p2=0; is_prerelease_tag "1.0.0-beta" || p2=$?
p3=0; is_prerelease_tag "v1.0.0-rc1" || p3=$?
p4=0; is_prerelease_tag "preview-2026" || p4=$?
p5=0; is_prerelease_tag "v1.0.0-dev" || p5=$?
p6=0; is_prerelease_tag "nightly-20260901" || p6=$?

# Test stable tags
s1=0; is_prerelease_tag "2.3.3" && s1=1 || true
s2=0; is_prerelease_tag "v0.96.6" && s2=1 || true
s3=0; is_prerelease_tag "v3.9.3" && s3=1 || true

echo "p1=$p1"
echo "p2=$p2"
echo "p3=$p3"
echo "p4=$p4"
echo "p5=$p5"
echo "p6=$p6"
echo "s1=$s1"
echo "s2=$s2"
echo "s3=$s3"
EOS
)"

if printf '%s\n' "$prerelease_check_output" | grep -q 'p1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p3=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p4=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p5=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p6=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's3=0'; then
    pass "is_prerelease_tag correctly rejects beta, rc, preview, dev, nightly and accepts stable versions"
else
    fail "is_prerelease_tag classification failed: $prerelease_check_output"
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
    fail "validation.sh missing cursor-flags.conf check"
fi

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

section "User Nix Configuration Preservation"

nix_conf_output="$(
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
source "$SCRIPT_DIR/modules/nix.sh"

mkdir -p "$TARGET_HOME/.config/nix"
cat > "$TARGET_HOME/.config/nix/nix.conf" <<'CONF'
# Custom user nix configuration
trusted-users = root alice
substituters = https://cache.nixos.org https://custom-cache.org
CONF

configure_nix_features

user_custom_ok=$([[ $(grep -c 'trusted-users = root alice' "$TARGET_HOME/.config/nix/nix.conf") -eq 1 ]] && echo 1 || echo 0)
features_added=$([[ $(grep -c 'experimental-features = nix-command flakes' "$TARGET_HOME/.config/nix/nix.conf") -eq 1 ]] && echo 1 || echo 0)
warn_dirty_added=$([[ $(grep -c 'warn-dirty = false' "$TARGET_HOME/.config/nix/nix.conf") -eq 1 ]] && echo 1 || echo 0)

echo "user_custom_ok=$user_custom_ok"
echo "features_added=$features_added"
echo "warn_dirty_added=$warn_dirty_added"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$nix_conf_output" | grep -q 'user_custom_ok=1' &&
   printf '%s\n' "$nix_conf_output" | grep -q 'features_added=1' &&
   printf '%s\n' "$nix_conf_output" | grep -q 'warn_dirty_added=1'; then
    pass "configure_nix_features preserves existing user nix.conf settings while ensuring required flags"
else
    fail "configure_nix_features mutated or wiped user nix.conf: $nix_conf_output"
fi
