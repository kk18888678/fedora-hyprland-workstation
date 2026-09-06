section "39. Verification Matrix Y: Runtime Provenance, Gesture Ownership, Responsive Layout & Diagnostics"

# 39.1: KeybindingsConfig.qml registers uiRevision and design tokens
if grep -q 'readonly property string uiRevision: "2026.09.05.r2"' "$ROOT/components/keybindings/KeybindingsConfig.qml" && \
   grep -q 'readonly property int settingsContentMaxWidth: 720' "$ROOT/components/keybindings/KeybindingsConfig.qml"; then
    pass "39.1 KeybindingsConfig.qml registers uiRevision and design tokens"
else
    fail "39.1 KeybindingsConfig.qml uiRevision or design tokens missing"
fi

# 39.2: qmldir exports the complete first-party Keybindings component surface
if grep -q 'singleton KeybindingsConfig 1.0 KeybindingsConfig.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'KeybindingsWindow 1.0 KeybindingsWindow.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'KeybindingsSettings 1.0 KeybindingsSettings.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'KeybindingsModel 1.0 KeybindingsModel.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'KeybindingRow 1.0 KeybindingRow.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'KeybindingsHeader 1.0 KeybindingsHeader.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'KeybindingsActionList 1.0 KeybindingsActionList.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'KeybindingsExecutableForm 1.0 KeybindingsExecutableForm.qml' "$ROOT/components/keybindings/qmldir" && \
   grep -q 'KeybindingsFooter 1.0 KeybindingsFooter.qml' "$ROOT/components/keybindings/qmldir"; then
    pass "39.2 qmldir exports the complete first-party Keybindings component surface"
else
    fail "39.2 qmldir missing required component export"
fi

# 39.3: shell.qml provides the Omarchy-style shell/plugin IPC methods
if grep -q 'function ping(): string' "$ROOT/shell.qml" && \
   grep -q 'function summon(pluginId: string, payloadJson: string): string' "$ROOT/shell.qml" && \
   grep -q 'function hide(pluginId: string): string' "$ROOT/shell.qml" && \
   grep -q 'function toggle(pluginId: string, payloadJson: string): string' "$ROOT/shell.qml" && \
   grep -q 'function call(pluginId: string, method: string, argument: string): string' "$ROOT/shell.qml" && \
   grep -q 'function rescanPlugins(): string' "$ROOT/shell.qml" && \
   grep -q 'function setPluginEnabled(pluginId: string, enabled: string): string' "$ROOT/shell.qml" && \
   grep -q 'function listPlugins(): string' "$ROOT/shell.qml"; then
    pass "39.3 shell.qml exposes the resident shell/plugin IPC contract"
else
    fail "39.3 shell.qml missing required IPC methods"
fi

# 39.4: Return/Enter key handlers suppress auto-repeat and claim the physical gesture
if grep -q 'isAutoRepeat' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'function claimActivationKey(event)' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'function handleActivationKeyRelease(event)' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'activationGestureHeld' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "39.4 Return/Enter ownership suppresses auto-repeat and tracks the matching release"
else
    fail "39.4 KeybindingsWindow.qml missing physical Return/Enter gesture ownership"
fi

# 39.5: No timing-based activation workaround or delayed focus remains
if ! grep -q 'activationCooldownUntil' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   ! grep -q 'Date.now() <' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   ! grep -q 'Qt.callLater' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   ! grep -E -q 'Timer\s*\{' "$ROOT/components/keybindings/KeybindingsWindow.qml" && \
   grep -q 'function focusActiveView(view)' "$ROOT/components/keybindings/KeybindingsWindow.qml"; then
    pass "39.5 activation cooldown/debounce replacement is absent; focus follows synchronous view ownership"
else
    fail "39.5 timing-based activation or delayed-focus workaround remains in KeybindingsWindow.qml"
fi

# 39.6: KeybindingsModel implements pendingSelectActionId for selection retention
if grep -q 'property string pendingSelectActionId' "$ROOT/components/keybindings/KeybindingsModel.qml" && \
   grep -q 'pendingSelectActionId = "app:" + desktopId' "$ROOT/components/keybindings/KeybindingsModel.qml"; then
    pass "39.6 KeybindingsModel retains newly added action selection via pendingSelectActionId"
else
    fail "39.6 KeybindingsModel missing pendingSelectActionId logic"
fi

# 39.7: effective_bindings.lua eliminates compositor reload on user action registration
if ! sed -n '/function M.add_user_application_action/,/^end/p' "$ROOT/dotfiles/hypr/effective_bindings.lua" | grep -q 'M.reload_session' && \
   ! sed -n '/function M.add_user_executable_action/,/^end/p' "$ROOT/dotfiles/hypr/effective_bindings.lua" | grep -q 'M.reload_session'; then
    pass "39.7 effective_bindings.lua avoids compositor reload fallback on action registration"
else
    fail "39.7 effective_bindings.lua still calls compositor reload fallback"
fi

# 39.8: KeybindingsSettings.qml implements responsive layout
if grep -q 'readonly property bool isCompact: settingsContent.width < KeybindingsConfig.settingsBreakpointWidth' "$ROOT/components/keybindings/KeybindingsSettings.qml" && \
   grep -q 'Layout.preferredHeight: settingsRoot.isCompact ? -1' "$ROOT/components/keybindings/KeybindingsSettings.qml"; then
    pass "39.8 KeybindingsSettings.qml implements responsive layout with dynamic row heights"
else
    fail "39.8 KeybindingsSettings.qml missing responsive layout properties"
fi

# 39.9: aurelia-shell-keybindings uses logger -t aurelia-shell-keybindings
if grep -R -q 'logger -t aurelia-shell-keybindings' "$ROOT/bin/lib/aurelia-keybindings" && \
   ! grep -R -q 'logger -t workstation-keybindings' "$ROOT/bin/lib/aurelia-keybindings"; then
    pass "39.9 aurelia-shell-keybindings uses correct syslog tag in its logging module"
else
    fail "39.9 aurelia-shell-keybindings syslog tag incorrect"
fi

# 39.10: aurelia-shell-keybindings diagnostics runtime text output
diag_text="$("$ROOT/bin/aurelia-shell-keybindings" diagnostics runtime)"
if grep -q '=== Aurelia Shell Keybindings Runtime Diagnostics ===' <<< "$diag_text" && \
   grep -q 'Canonical Backend Path' <<< "$diag_text" && \
   grep -q 'Canonical Backend SHA256' <<< "$diag_text" && \
   grep -q 'Running Quickshell PID' <<< "$diag_text" && \
   grep -q 'Running QML Root' <<< "$diag_text" && \
   grep -q 'Managed Component Root' <<< "$diag_text" && \
   grep -q 'Expected Manifest' <<< "$diag_text" && \
   grep -q 'Deployed Manifest' <<< "$diag_text" && \
   grep -q 'Manifest Mismatches' <<< "$diag_text" && \
   grep -q 'Provider' <<< "$diag_text" && \
   grep -q 'Live UI Revision' <<< "$diag_text" && \
   grep -q 'Layer Namespace' <<< "$diag_text" && \
   grep -q 'Motion State' <<< "$diag_text" && \
   grep -q 'Active View' <<< "$diag_text"; then
    pass "39.10 aurelia-shell-keybindings diagnostics runtime generates structured text report"
else
    fail "39.10 diagnostics runtime text output missing expected fields: $diag_text"
fi

# 39.11: aurelia-shell-keybindings diagnostics runtime --json produces valid JSON
diag_json="$("$ROOT/bin/aurelia-shell-keybindings" diagnostics runtime --json)"
json_valid="$(echo "$diag_json" | jq -r '.canonical_backend.path, .canonical_backend.sha256, .managed_component_root, (.expected_manifest.files | length)' 2>/dev/null || true)"
if [[ -n "$json_valid" && "$diag_json" == *"aurelia-keybindings"* && \
      "$diag_json" == *"manifest_mismatches"* && "$diag_json" == *"provider"* ]]; then
    pass "39.11 aurelia-shell-keybindings diagnostics runtime --json produces authoritative provenance JSON"
else
    fail "39.11 diagnostics runtime --json output invalid or incomplete: $diag_json"
fi

# 39.12: workstation-aurelia diagnostics runtime forwards to aurelia-shell-keybindings
wa_diag="$("$ROOT/bin/workstation-aurelia" diagnostics runtime)"
if grep -q '=== Aurelia Shell Keybindings Runtime Diagnostics ===' <<< "$wa_diag"; then
    pass "39.12 workstation-aurelia diagnostics runtime forwards seamlessly"
else
    fail "39.12 workstation-aurelia diagnostics runtime forwarding failed: $wa_diag"
fi
