section "33. Verification Matrix S: Core Deployment, CLI Delegation & Path Isolation"

# 33.1: workstation-aurelia deployed to /usr/local/bin/workstation-aurelia (mode 0755)
desktop_mod="$ROOT/modules/lib/aurelia_desktop.sh"
if grep -q 'aur_bin_source=.*bin/workstation-aurelia' "$desktop_mod" && \
   grep -q 'aur_bin_target=.*bin_dir/workstation-aurelia' "$desktop_mod" && \
   grep -q 'aurelia_install_file.*aur_bin_source.*aur_bin_target.*0755' "$desktop_mod"; then
    pass "33.1 workstation-aurelia is deployed by the Aurelia desktop module with mode 0755"
else
    fail "33.1 workstation-aurelia deployment declaration missing or incorrect in Aurelia desktop module"
fi

# 33.2: workstation-keybindings delegates to workstation-aurelia and fails closed if missing
test_33_2_out="$(WORKSTATION_AURELIA_BIN="/nonexistent/workstation-aurelia" "$ROOT/bin/workstation-keybindings" preference get 2>&1 || true)"
test_33_2_code="$(WORKSTATION_AURELIA_BIN="/nonexistent/workstation-aurelia" "$ROOT/bin/workstation-keybindings" preference get >/dev/null 2>&1; echo $?)"
if [[ "$test_33_2_code" -eq 1 && "$test_33_2_out" == *"workstation-aurelia"* && "$test_33_2_out" == *"not found"* ]]; then
    pass "33.2 workstation-keybindings delegation fails closed with exit code 1 when workstation-aurelia missing"
else
    fail "33.2 workstation-keybindings missing delegation check failed (code=$test_33_2_code, out=$test_33_2_out)"
fi

# 33.3: A clean non-privileged deployment includes every canonical runtime module
deployment_check="$(bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
root="$1"
sb="$(mktemp -d)"
trap 'rm -rf "$sb"' EXIT
home="$sb/home"
prefix="$sb/prefix"
bin_dir="$prefix/bin"
apps_dir="$sb/apps"
mkdir -p "$home/.config" "$bin_dir" "$apps_dir"
cp -a "$root/aurelia-shell" "$home/.config/aurelia"

SCRIPT_DIR="$root"
TARGET_HOME="$home"
KEYBINDINGS_BIN_DIR="$bin_dir"
AURELIA_KEYBINDINGS_LIB_DIR="$prefix/lib/aurelia-keybindings"
KEYBINDINGS_APPS_DIR="$apps_dir"
info() { :; }
warn() { :; }
record_success() { :; }
record_deferred() { :; }
source "$root/modules/desktop.sh"
install_workstation_keybindings >/dev/null

for module in common queries actions mutations runtime toggle main; do
    [[ -f "$prefix/lib/aurelia-keybindings/$module.sh" ]] || exit 1
done
KEYBINDINGS_MANIFEST="$root/dotfiles/hypr/keybindings_manifest.lua" \
    HOME="$home" "$bin_dir/aurelia-shell-keybindings" json |
    jq -e 'length > 0' >/dev/null
jq -e '.mismatches == [] and (.deployed.backend_files | length) == 7' \
    "$home/.local/state/aurelia/keybindings/deployment-manifest.json" >/dev/null
printf 'DEPLOYMENT_COMPLETE\n'
EOS
)"
if [[ "$deployment_check" == *"DEPLOYMENT_COMPLETE"* ]]; then
    pass "33.3 clean deployment installs canonical backend with all owned runtime modules"
else
    fail "33.3 clean deployment omitted a canonical backend module: $deployment_check"
fi

# 33.4: Aurelia preferences owned under dotfiles/aurelia/core/preferences.lua (and dotfiles/hypr/aurelia_preferences.lua is removed)
if [[ -f "$ROOT/dotfiles/aurelia/core/preferences.lua" && ! -f "$ROOT/dotfiles/hypr/aurelia_preferences.lua" ]]; then
    pass "33.4 Aurelia preferences canonically owned under dotfiles/aurelia/core/preferences.lua with hypr/ removal"
else
    fail "33.4 Aurelia preferences ownership violation: missing core/preferences.lua or stale hypr/aurelia_preferences.lua exists"
fi

# 33.5: Zero references to ~/.config/hypr/ in workstation-aurelia
if ! grep -q 'config/hypr' "$ROOT/bin/workstation-aurelia" && \
   ! grep -q 'config/hypr' "$ROOT/dotfiles/aurelia/core/preferences.lua"; then
    pass "33.5 zero references to ~/.config/hypr/ in workstation-aurelia or core preferences engine"
else
    fail "33.5 found legacy ~/.config/hypr/ references in workstation-aurelia or core preferences"
fi
