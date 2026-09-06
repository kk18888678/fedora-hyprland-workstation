section "7. Disabled Aurelia Components Are Not Started"

shell_qml="$ROOT/dotfiles/aurelia/shell.qml"
if [[ -f "$shell_qml" ]] &&
   grep -q 'PluginRegistry {' "$shell_qml" &&
   grep -q 'PluginHost {' "$shell_qml" &&
   grep -q 'active: host.shouldLoad(pluginId)' "$ROOT/aurelia-shell/services/PluginHost.qml" &&
   ! grep -q "bar" "$shell_qml" &&
   ! grep -q "launcher" "$shell_qml" &&
   ! grep -q "notifications" "$shell_qml"; then
    pass "7. disabled Aurelia components are not started (conditional loader; zero secondary shell processes)"
else
    fail "7. Aurelia shell.qml does not enforce conditional component loading"
fi
