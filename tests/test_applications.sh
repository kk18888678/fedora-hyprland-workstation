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
