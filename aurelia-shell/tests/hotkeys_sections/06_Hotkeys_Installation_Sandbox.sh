section "Hotkeys Installation Sandbox"

hotkeys_install_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
TARGET_USER="hotkeytest"
TARGET_HOME="$(mktemp -d)"
HOTKEYS_BIN_DIR="$(mktemp -d)"
HOTKEYS_APPS_DIR="$(mktemp -d)"
mkdir -p "$TARGET_HOME/.config"
ln -s "$SCRIPT_DIR" "$TARGET_HOME/.config/aurelia"
AURELIA_KEYBINDINGS_MANIFEST_PATH="$TARGET_HOME/.local/state/aurelia/keybindings/deployment-manifest.json"
export HOTKEYS_BIN_DIR HOTKEYS_APPS_DIR
export AURELIA_KEYBINDINGS_MANIFEST_PATH
OVERRIDE_TARGET_UID=1000

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

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

install_workstation_hotkeys

bin_installed=$([[ -x "$HOTKEYS_BIN_DIR/workstation-hotkeys" ]] && echo 1 || echo 0)
cap_installed=$([[ -x "$HOTKEYS_BIN_DIR/workstation-hotkey-capture" ]] && echo 1 || echo 0)
shell_installed=$([[ -x "$HOTKEYS_BIN_DIR/aurelia-shell" ]] && echo 1 || echo 0)
launcher_installed=$([[ -x "$HOTKEYS_BIN_DIR/aurelia-launch-shell" ]] && echo 1 || echo 0)
plugin_cli_installed=$([[ -x "$HOTKEYS_BIN_DIR/aurelia-plugin" ]] && echo 1 || echo 0)
desktop_installed=$([[ -f "$HOTKEYS_APPS_DIR/workstation-hotkeys.desktop" ]] && echo 1 || echo 0)
manifest_installed=0
if [[ -f "$AURELIA_KEYBINDINGS_MANIFEST_PATH" ]] &&
   python3 - "$AURELIA_KEYBINDINGS_MANIFEST_PATH" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
assert manifest["component"] == "aurelia-keybindings"
assert len(manifest["expected"]["files"]) == 23
assert len(manifest["expected"]["backend_files"]) == 7
assert manifest["mismatches"] == []
PY
then
    manifest_installed=1
fi
host_manifest_installed=0
if [[ -f "$TARGET_HOME/.local/state/aurelia/shell/host-manifest.json" ]] &&
   python3 - "$TARGET_HOME/.local/state/aurelia/shell/host-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
assert manifest["component"] == "aurelia-shell"
assert len(manifest["expected"]["host_files"]) == 3
assert len(manifest["expected"]["plugin_files"]) == 3
assert manifest["mismatches"] == []
PY
then
    host_manifest_installed=1
fi

echo "bin-installed=$bin_installed"
echo "cap-installed=$cap_installed"
echo "shell-installed=$shell_installed"
echo "launcher-installed=$launcher_installed"
echo "plugin-cli-installed=$plugin_cli_installed"
echo "desktop-installed=$desktop_installed"
echo "manifest-installed=$manifest_installed"
echo "host-manifest-installed=$host_manifest_installed"

rm -rf "$TARGET_HOME" "$HOTKEYS_BIN_DIR" "$HOTKEYS_APPS_DIR"
EOS
)"

if printf '%s\n' "$hotkeys_install_output" | grep -q 'bin-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'cap-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'shell-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'launcher-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'plugin-cli-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'desktop-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'manifest-installed=1' &&
   printf '%s\n' "$hotkeys_install_output" | grep -q 'host-manifest-installed=1'; then
    pass "install_workstation_hotkeys deploys binaries, desktop entry, and verified provenance manifest in isolation"
else
    fail "install_workstation_hotkeys failed in sandbox: $hotkeys_install_output"
fi
