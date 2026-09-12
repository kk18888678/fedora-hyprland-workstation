#!/usr/bin/env bash

# T16 command, privilege, timeout, and hook-free plugin lifecycle checks.

set -Eeuo pipefail

section "Aurelia Command and Privilege Boundary"

plugin_cli="$ROOT/bin/lib/aurelia-plugin"
lifecycle_cli="$plugin_cli/lifecycle.sh"
facade_root="$ROOT/services"
network_root="$ROOT/plugins/aurelia.network"
custom_bar_root="$ROOT/plugins/aurelia.bar/CustomCommandBarWidget.qml"

if grep -q 'GIT_TERMINAL_PROMPT=0' "$lifecycle_cli" &&
   grep -q 'aurelia_plugin_validate_manifest' "$ROOT/bin/lib/aurelia-plugin/main.sh" &&
   grep -q 'aurelia_plugin_require_root' "$lifecycle_cli" &&
   grep -q '60s git clone' "$lifecycle_cli" &&
   ! grep -R -Eq '\\b(sudo|pkexec|systemctl)\\b' "$facade_root"/Plugin*Api.qml "$facade_root"/PluginHost.qml &&
   grep -q 'function safeArgv' "$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml" &&
   grep -q 'function boundedArgv' "$custom_bar_root"; then
    pass "[static] plugin lifecycle and facades use user-level structured execution without privileged bypasses"
else
    fail "[static] plugin command or facade privilege boundary is incomplete"
fi

if grep -q '/usr/bin/timeout' "$network_root/NetworkPanel.qml" &&
   grep -q 'timeout' "$ROOT/bin/aurelia-screenshot" &&
   grep -q 'stdinEnabled: true' "$network_root/NetworkPanel.qml" &&
   grep -q 'aurelia-network-dns' "$network_root/NetworkPanel.qml" &&
   grep -q 'AURELIA_SHELL_IPC_TIMEOUT' "$ROOT/bin/aurelia-shell" &&
   grep -q 'AURELIA_PLUGIN_STAGING' "$lifecycle_cli"; then
    pass "[static] approved system actions remain bounded and credential input stays on the existing backend/stdin paths"
else
    fail "[static] bounded system-action or credential ownership contract is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] hook-free plugin lifecycle fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mock_bin="$runtime_root/bin"
plugin_dir="$runtime_root/plugins"
mkdir -p -- "$mock_bin" "$plugin_dir"
cp -- "$ROOT/tests/fixtures/privilege-boundary/git" "$mock_bin/git"
cp -- "$ROOT/tests/fixtures/privilege-boundary/aurelia-shell" "$mock_bin/aurelia-shell"
chmod 0755 "$mock_bin/git" "$mock_bin/aurelia-shell"
hook_marker="$runtime_root/hook-ran"
sudo_marker="$runtime_root/sudo-ran"
privilege_calls="$runtime_root/calls"
touch "$privilege_calls"
printf '%s\n' '#!/usr/bin/env bash' 'touch "$AURELIA_SUDO_MARKER"' >"$mock_bin/sudo"
chmod 0755 "$mock_bin/sudo"

add_output="$(
    PATH="$mock_bin:$PATH" \
    HOME="$runtime_root/home" \
    AURELIA_PLUGIN_DIR="$plugin_dir" \
    AURELIA_DEVELOPMENT_MODE=1 \
    AURELIA_PLUGIN_BIN_DIR="$mock_bin" \
    AURELIA_HOOK_MARKER="$hook_marker" \
    AURELIA_SUDO_MARKER="$sudo_marker" \
    AURELIA_PRIVILEGE_CALLS="$privilege_calls" \
    bash -c '
        set -Eeuo pipefail
        source "$1/common.sh"
        source "$1/placement.sh"
        source "$1/manifest.sh"
        source "$1/main.sh"
        source "$1/lifecycle.sh"
        aurelia_plugin_add https://example.invalid/acme-test-widget.git --enable --yes
    ' _ "$plugin_cli"
)"

target="$plugin_dir/acme.test-widget"
if [[ "$add_output" == *"Installed acme.test-widget"* ]] &&
   [[ -d "$target" && -f "$target/manifest.json" && -f "$target/install.sh" ]] &&
   [[ ! -e "$hook_marker" && ! -e "$sudo_marker" ]] &&
   grep -q '^rescanPlugins$' "$privilege_calls" &&
   grep -q '^enablePlugin acme.test-widget {}$' "$privilege_calls" &&
   PATH="$mock_bin:$PATH" HOME="$runtime_root/home" AURELIA_PLUGIN_DIR="$plugin_dir" \
       AURELIA_DEVELOPMENT_MODE=1 AURELIA_PLUGIN_BIN_DIR="$mock_bin" \
       bash -c 'source "$1/common.sh"; source "$1/placement.sh"; source "$1/manifest.sh"; source "$1/main.sh"; aurelia_plugin_validate_manifest "$2" 0 1' \
       _ "$plugin_cli" "$target"; then
    pass "[isolated-runtime] add, validation, and enable never execute a plugin install hook or invoke sudo"
else
    fail "[isolated-runtime] plugin lifecycle crossed the privilege/hook boundary: output=$add_output calls=$(tr '\n' ' ' <"$privilege_calls")"
fi
