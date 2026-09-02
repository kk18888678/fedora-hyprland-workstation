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

if grep -q "CHATGPT_X86_64_URL" "$ROOT/modules/applications.sh" &&
   grep -q "CHATGPT_X86_64_SHA512" "$ROOT/modules/applications.sh"; then
    pass "applications.sh uses pinned OpenAI bootstrap RPM URL and SHA-512"
else
    fail "applications.sh missing pinned OpenAI bootstrap RPM metadata"
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

# 3. Checksum mismatch fails before DNF is ever called
package_installed() { return 1; }
dnf_called_on_mismatch=0
sudo() { dnf_called_on_mismatch=1; }
download_and_verify_artifact() {
    # Simulate checksum mismatch
    return 1
}
install_chatgpt
echo "mismatch_dnf_prevented=$([[ $dnf_called_on_mismatch -eq 0 ]] && echo 1 || echo 0)"
echo "mismatch_deferred=$(grep -c 'Failed to download or verify official OpenAI ChatGPT RPM checksum' <(printf '%s\n' "${INSTALL_DEFERRED[@]}") || true)"

# 4. Valid checksum executes DNF installation and succeeds
package_installed() { return 1; }
dnf_called_on_valid=0
download_and_verify_artifact() {
    local out="$3"
    touch "$out"
    return 0
}
run_with_retry() {
    shift
    "$@"
}
run_with_timeout() {
    shift 2
    "$@"
}
sudo() {
    dnf_called_on_valid=1
    if [[ "$*" =~ dnf\ install\ -y ]]; then
        package_installed() { return 0; }
    fi
}
install_chatgpt
echo "valid_dnf_invoked=$([[ $dnf_called_on_valid -eq 1 ]] && echo 1 || echo 0)"

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

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'mismatch_dnf_prevented=1' &&
   printf '%s\n' "$chatgpt_behavior_output" | grep -q 'mismatch_deferred=1'; then
    pass "install_chatgpt prevents DNF invocation and records deferred on checksum mismatch"
else
    fail "install_chatgpt did not isolate checksum mismatch from DNF: $chatgpt_behavior_output"
fi

if printf '%s\n' "$chatgpt_behavior_output" | grep -q 'valid_dnf_invoked=1'; then
    pass "install_chatgpt verifies checksum before invoking DNF for official RPM installation"
else
    fail "install_chatgpt failed valid bootstrap execution: $chatgpt_behavior_output"
fi

section "N_m3u8DL-RE Prerelease Policy"

n_m3u8dl_policy_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
MEDIA_TOOLS_DIR="$(mktemp -d)"
export MEDIA_TOOLS_DIR
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

rm -rf "$TARGET_HOME" "$MEDIA_TOOLS_DIR"
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

# 1. Prerelease tags rejected
p_alpha=0; is_prerelease_tag "v1.0.0-alpha" || p_alpha=$?
p_beta1=0; is_prerelease_tag "1.0.0-beta" || p_beta1=$?
p_beta2=0; is_prerelease_tag "v0.6.0-beta" || p_beta2=$?
p_rc1=0; is_prerelease_tag "v1.0.0-rc1" || p_rc1=$?
p_rc2=0; is_prerelease_tag "v1.0.0-rc.2" || p_rc2=$?
p_preview=0; is_prerelease_tag "v1.0.0-preview" || p_preview=$?
p_pre1=0; is_prerelease_tag "v1.0.0-pre" || p_pre1=$?
p_pre2=0; is_prerelease_tag "v1.0.0-pre1" || p_pre2=$?
p_dev=0; is_prerelease_tag "v1.0.0-dev" || p_dev=$?
p_nightly=0; is_prerelease_tag "v1.0.0-nightly" || p_nightly=$?
p_snapshot=0; is_prerelease_tag "v1.0.0-snapshot" || p_snapshot=$?

# 2. Standard stable versions accepted
s_v1=0; is_prerelease_tag "v1.0.0" && s_v1=1 || true
s_v2=0; is_prerelease_tag "2.3.3" && s_v2=1 || true
s_v3=0; is_prerelease_tag "v0.96.6" && s_v3=1 || true
s_v4=0; is_prerelease_tag "v3.9.3" && s_v4=1 || true
s_v5=0; is_prerelease_tag "1.6.0-641" && s_v5=1 || true

# 3. Regression test: words containing 'pre' or 'dev' as substring of unrelated words are NOT false positives
r_precise=0; is_prerelease_tag "v1.0.0-precise" && r_precise=1 || true
r_compress=0; is_prerelease_tag "v2.0-compress" && r_compress=1 || true
r_develop=0; is_prerelease_tag "v1.0.0-develop" && r_develop=1 || true
r_device=0; is_prerelease_tag "v1.0.0-device" && r_device=1 || true
r_predict=0; is_prerelease_tag "v1.0.0-prediction" && r_predict=1 || true
r_express=0; is_prerelease_tag "express-1.0" && r_express=1 || true

echo "p_alpha=$p_alpha"
echo "p_beta1=$p_beta1"
echo "p_beta2=$p_beta2"
echo "p_rc1=$p_rc1"
echo "p_rc2=$p_rc2"
echo "p_preview=$p_preview"
echo "p_pre1=$p_pre1"
echo "p_pre2=$p_pre2"
echo "p_dev=$p_dev"
echo "p_nightly=$p_nightly"
echo "p_snapshot=$p_snapshot"
echo "s_v1=$s_v1"
echo "s_v2=$s_v2"
echo "s_v3=$s_v3"
echo "s_v4=$s_v4"
echo "s_v5=$s_v5"
echo "r_precise=$r_precise"
echo "r_compress=$r_compress"
echo "r_develop=$r_develop"
echo "r_device=$r_device"
echo "r_predict=$r_predict"
echo "r_express=$r_express"
EOS
)"

if printf '%s\n' "$prerelease_check_output" | grep -q 'p_alpha=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_beta1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_beta2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_rc1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_rc2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_preview=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_pre1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_pre2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_dev=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_nightly=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'p_snapshot=0'; then
    pass "is_prerelease_tag correctly rejects alpha, beta, rc, preview, pre, dev, nightly, and snapshot tokens"
else
    fail "is_prerelease_tag failed to reject prerelease token: $prerelease_check_output"
fi

if printf '%s\n' "$prerelease_check_output" | grep -q 's_v1=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's_v2=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's_v3=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's_v4=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 's_v5=0'; then
    pass "is_prerelease_tag correctly accepts standard stable version tags"
else
    fail "is_prerelease_tag rejected valid stable tag: $prerelease_check_output"
fi

if printf '%s\n' "$prerelease_check_output" | grep -q 'r_precise=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_compress=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_develop=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_device=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_predict=0' &&
   printf '%s\n' "$prerelease_check_output" | grep -q 'r_express=0'; then
    pass "is_prerelease_tag avoids false positives on words containing 'pre' or 'dev' substrings (precise, develop, device, etc.)"
else
    fail "is_prerelease_tag false positive on boundary regression word: $prerelease_check_output"
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
