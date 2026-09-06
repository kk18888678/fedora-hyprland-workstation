#!/usr/bin/env bash

# Focused tests for the resident Aurelia Shell host and Omarchy-compatible
# plugin boundary. This suite intentionally stays separate from the legacy
# Keybindings behavior matrix so plugin architecture assertions do not grow a
# second god test.

set -Eeuo pipefail

shell_root="$ROOT"
plugin_root="$shell_root/plugins/aurelia.keybindings"
services_root="$shell_root/services"

section "Aurelia Shell Package and Plugin Contract"

if [[ -f "$shell_root/shell.qml" && -f "$shell_root/README.md" && -f "$shell_root/plugins/README.md" ]]; then
    pass "Aurelia Shell has a canonical top-level package and plugin documentation"
else
    fail "Aurelia Shell top-level package or documentation is missing"
fi

if [[ ! -e "$ROOT/../dotfiles/aurelia" ]]; then
    pass "Aurelia Shell has no parent-repository compatibility symlink"
else
    fail "Aurelia Shell parent compatibility symlink still exists"
fi

if [[ -f "$plugin_root/manifest.json" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.keybindings" and
       .name == "Keybindings" and
       (.kinds == ["panel"]) and
       .entryPoints.panel == "KeybindingsPlugin.qml" and
       .keepLoaded == true
   ' "$plugin_root/manifest.json" >/dev/null; then
    pass "aurelia.keybindings declares a valid resident panel manifest"
else
    fail "aurelia.keybindings manifest is missing or violates the plugin contract"
fi

plugin_validation_output="$("$ROOT/bin/aurelia-plugin" validate --first-party "$plugin_root" 2>&1)"
if [[ "$plugin_validation_output" == *"Valid Aurelia plugin: aurelia.keybindings"* ]]; then
    pass "aurelia-plugin CLI uses the same manifest validation boundary for first-party plugins"
else
    fail "aurelia-plugin CLI rejected the shipped first-party manifest: $plugin_validation_output"
fi

add_without_confirmation=0
add_output="$("$ROOT/bin/aurelia-plugin" add https://example.invalid/aurelia-plugin.git 2>&1)" || add_without_confirmation=$?
if [[ "$add_without_confirmation" -eq 1 && "$add_output" == *"requires --yes"* ]]; then
    pass "plugin download/install requires explicit --yes and cannot mutate by omission"
else
    fail "plugin add confirmation gate failed: rc=$add_without_confirmation output=$add_output"
fi

if [[ -f "$plugin_root/KeybindingsPlugin.qml" &&
      -f "$plugin_root/ui/KeybindingsWindow.qml" &&
      -f "$plugin_root/ui/KeybindingsModel.qml" &&
      -f "$plugin_root/ui/qmldir" ]] &&
   grep -q 'import Quickshell.Io' "$plugin_root/KeybindingsPlugin.qml" &&
   ! grep -q 'required property' "$plugin_root/KeybindingsPlugin.qml"; then
    pass "Keybindings plugin entry point and private UI/logic surfaces are present without dynamic required-property failure"
else
    fail "Keybindings plugin entry point or private surface contract is incomplete"
fi

section "Resident Host Services"

if grep -q 'import Quickshell.Io' "$shell_root/shell.qml" &&
   grep -q 'target: "shell"' "$shell_root/shell.qml" &&
   grep -q 'PluginRegistry {' "$shell_root/shell.qml" &&
   grep -q 'PluginHost {' "$shell_root/shell.qml" &&
   grep -q 'target: "keybindings"' "$shell_root/shell.qml" &&
   grep -q 'target: "hotkeys"' "$shell_root/shell.qml"; then
    pass "shell.qml exposes one resident host with compatibility targets"
else
    fail "shell.qml is missing the resident host or compatibility IPC targets"
fi

if grep -q 'function summon(pluginId: string, payloadJson: string): string' "$shell_root/shell.qml" &&
   grep -q 'function hide(pluginId: string): string' "$shell_root/shell.qml" &&
   grep -q 'function toggle(pluginId: string, payloadJson: string): string' "$shell_root/shell.qml" &&
   grep -q 'function call(pluginId: string, method: string, argument: string): string' "$shell_root/shell.qml" &&
   grep -q 'function rescanPlugins(): string' "$shell_root/shell.qml" &&
   grep -q 'function reloadConfig(): string' "$shell_root/shell.qml" &&
   grep -q 'function setPluginEnabled(pluginId: string, enabled: string): string' "$shell_root/shell.qml" &&
   grep -q 'function listPlugins(): string' "$shell_root/shell.qml"; then
    pass "shell IPC implements the complete lifecycle and registry contract"
else
    fail "shell IPC lifecycle or registry contract is incomplete"
fi

if grep -q 'property string userPluginsDir' "$services_root/PluginRegistry.qml" &&
   grep -q 'entryPointUrl(id, kind)' "$services_root/PluginRegistry.qml" &&
   grep -q 'find -P' "$services_root/PluginRegistry.qml" &&
   grep -q 'jq -e' "$services_root/PluginRegistry.qml" &&
   ! grep -q 'inotifywait' "$services_root/PluginRegistry.qml"; then
    pass "PluginRegistry discovers built-in/user roots, validates entry points, rejects symlink trees, and has no unbounded watcher"
else
    fail "PluginRegistry discovery or safety boundary is incomplete"
fi

if grep -q 'Repeater {' "$services_root/PluginHost.qml" &&
   grep -q 'Loader {' "$services_root/PluginHost.qml" &&
   grep -q 'function open(id, payloadJson)' "$services_root/PluginHost.qml" &&
   grep -q 'function close(id)' "$services_root/PluginHost.qml" &&
   grep -q 'function toggle(id, payloadJson)' "$services_root/PluginHost.qml" &&
   grep -q 'function call(id, method, argument)' "$services_root/PluginHost.qml"; then
    pass "PluginHost owns dynamic Loader lifecycle and plugin-scoped calls"
else
    fail "PluginHost lifecycle boundary is incomplete"
fi

if grep -q 'FileView' "$services_root/ShellConfig.qml" &&
   grep -q 'atomicWrites: true' "$services_root/ShellConfig.qml" &&
   grep -q 'blockWrites: true' "$services_root/ShellConfig.qml" &&
   grep -q 'aurelia/shell.json' "$services_root/ShellConfig.qml"; then
    pass "ShellConfig persists only plugin state with atomic blocking writes"
else
    fail "ShellConfig persistence boundary is incomplete"
fi

if [[ -x "$ROOT/bin/aurelia-shell" && -x "$ROOT/bin/aurelia-launch-shell" && -x "$ROOT/bin/aurelia-plugin" ]] &&
   grep -q 'ipc --path' "$ROOT/bin/aurelia-shell" &&
   ! grep -q -- '--no-duplicate' "$ROOT/bin/aurelia-shell" &&
   grep -q -- '--no-duplicate' "$ROOT/bin/aurelia-launch-shell" &&
   grep -q 'readlink -f' "$ROOT/bin/aurelia-shell" &&
   grep -q 'readlink -f' "$ROOT/bin/aurelia-launch-shell"; then
    pass "host IPC, resident launcher, and plugin lifecycle CLI have separate bounded responsibilities"
else
    fail "Aurelia host command boundaries are incomplete or the IPC client can start a second shell"
fi

if grep -q 'source_kind.*thirdparty' "$services_root/PluginRegistry.qml" &&
   grep -q 'root_real' "$services_root/PluginRegistry.qml" &&
   grep -q 'readlink -f' "$services_root/PluginRegistry.qml"; then
    pass "PluginRegistry ignores overlapping first-party/user roots instead of rejecting the same plugin twice"
else
    fail "PluginRegistry does not guard against overlapping first-party/user plugin roots"
fi

ipc_fixture="$(mktemp -d)"
trap 'rm -rf -- "$ipc_fixture"' EXIT
mkdir -p "$ipc_fixture/config/aurelia" "$ipc_fixture/bin"
touch "$ipc_fixture/config/aurelia/shell.qml"
cat > "$ipc_fixture/bin/qs" <<'EOF_QS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AURELIA_QS_TEST_LOG"
printf 'ok\n'
EOF_QS
chmod 0755 "$ipc_fixture/bin/qs"
if AURELIA_SHELL_ROOT="$ipc_fixture/config/aurelia" \
   QUICKSHELL_BIN="$ipc_fixture/bin/qs" \
   AURELIA_QS_TEST_LOG="$ipc_fixture/qs.log" \
   AURELIA_DEVELOPMENT_MODE=1 \
   "$ROOT/bin/aurelia-shell" shell ping >/tmp/aurelia-shell-ipc.out 2>&1 &&
   grep -q '^ok$' /tmp/aurelia-shell-ipc.out &&
   ! grep -q -- '--no-duplicate' "$ipc_fixture/qs.log"; then
    pass "aurelia-shell is a bounded IPC-only client and never starts a second Quickshell"
else
    fail "aurelia-shell IPC client fixture failed"
fi
rm -rf -- "$ipc_fixture"
trap - EXIT

symlink_fixture="$(mktemp -d)"
mkdir -p "$symlink_fixture/bin"
ln -s "$ROOT/bin/aurelia-shell-keybindings" "$symlink_fixture/bin/aurelia-shell-keybindings"
if "$symlink_fixture/bin/aurelia-shell-keybindings" --help >"$symlink_fixture/help.out" 2>&1 &&
   grep -q 'Usage: aurelia-shell-keybindings' "$symlink_fixture/help.out"; then
    pass "source-linked Aurelia command resolves its real module directory"
else
    fail "source-linked Aurelia command cannot resolve its real module directory"
fi
rm -rf -- "$symlink_fixture"

section "Keybindings Plugin Redesign and Runtime Ownership"

if grep -q 'KeybindingsAddActionPicker {' "$plugin_root/ui/KeybindingsWindow.qml" &&
   grep -q 'readonly property bool pickerVisible' "$plugin_root/ui/KeybindingsAddActionPicker.qml" &&
   grep -q 'KeybindingsActionTypeRow {' "$plugin_root/ui/KeybindingsAddActionPicker.qml" &&
   grep -q 'windowController.activateSelected("mouse")' "$plugin_root/ui/KeybindingsActionTypeRow.qml" &&
   grep -q 'mouse.accepted = true' "$plugin_root/ui/KeybindingsActionTypeRow.qml"; then
    pass "Add Action uses a dedicated picker and claims Application/Executable pointer gestures"
else
    fail "Add Action dedicated picker or pointer ownership is incomplete"
fi

if grep -q '/usr/local/bin/aurelia-shell-keybindings' "$plugin_root/ui/KeybindingsModel.qml" &&
   grep -q 'target: "aurelia.keybindings"' "$plugin_root/KeybindingsPlugin.qml" &&
   [[ -x "$ROOT/bin/aurelia-launch-shell" ]]; then
    pass "Keybindings keeps backend logic separate and starts through the resident Aurelia host"
else
    fail "Keybindings backend/plugin/startup ownership is incomplete"
fi

if ! find -P "$plugin_root" -type l -print -quit | grep -q .; then
    pass "first-party Keybindings plugin tree contains no symlinked executable/code surface"
else
    fail "first-party Keybindings plugin tree contains an unexpected symlink"
fi

section "Aurelia Shell File-Size Guard"

size_failures=0
while IFS= read -r -d '' file; do
    line_count="$(wc -l < "$file")"
    if [[ "$line_count" -gt 1000 ]]; then
        printf '  FAIL file exceeds 1000-line Aurelia shell guard: %s (%s lines)\n' "$file" "$line_count"
        size_failures=$((size_failures + 1))
    fi
done < <(find "$shell_root/services" "$plugin_root" -type f \( -name '*.qml' -o -name '*.sh' -o -name '*.lua' \) -print0)

if [[ "$size_failures" -eq 0 ]]; then
    pass "Aurelia Shell service/plugin source files remain below the god-file guard"
else
    fail "$size_failures Aurelia Shell service/plugin source files exceed the god-file guard"
fi
