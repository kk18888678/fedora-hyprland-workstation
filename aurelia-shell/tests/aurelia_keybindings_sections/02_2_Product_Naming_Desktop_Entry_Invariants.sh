section "2. Product Naming & Desktop Entry Invariants"

# 2.1: User-facing desktop entry Name=Keybindings, GenericName=Keyboard Shortcuts
desktop_file="$ROOT/config/desktop-entries/workstation-keybindings.desktop"
if [[ -f "$desktop_file" ]] &&
   grep -q '^Name=Keybindings$' "$desktop_file" &&
   grep -q '^GenericName=Keyboard Shortcuts$' "$desktop_file" &&
   ! grep -q '^Name=Aurelia Keybindings$' "$desktop_file"; then
    pass "2.1 user-facing desktop entry presents Name=Keybindings (never Aurelia Keybindings)"
else
    fail "2.1 workstation-keybindings.desktop naming violated"
fi

# 2.2: Compatibility desktop entry workstation-hotkeys.desktop has NoDisplay=true
compat_desktop="$ROOT/config/desktop-entries/workstation-hotkeys.desktop"
if [[ -f "$compat_desktop" ]] && grep -q '^NoDisplay=true$' "$compat_desktop"; then
    pass "2.2 compatibility desktop entry workstation-hotkeys.desktop is hidden (NoDisplay=true)"
else
    fail "2.2 workstation-hotkeys.desktop missing NoDisplay=true"
fi

# 2.3: Internal Aurelia Keybindings QML component naming
qml_dir="$ROOT/components/keybindings"
qml_window="$qml_dir/KeybindingsWindow.qml"
qml_header="$qml_dir/KeybindingsHeader.qml"
qml_action_list="$qml_dir/KeybindingsActionList.qml"
qml_form="$qml_dir/KeybindingsExecutableForm.qml"
qml_footer="$qml_dir/KeybindingsFooter.qml"
qml_row="$qml_dir/KeybindingRow.qml"
if [[ -f "$qml_dir/KeybindingsWindow.qml" && \
      -f "$qml_dir/KeybindingsModel.qml" && \
      -f "$qml_dir/KeybindingRow.qml" && \
      -f "$qml_header" && \
      -f "$qml_action_list" && \
      -f "$qml_form" && \
      -f "$qml_footer" ]]; then
    pass "2.3 internal Aurelia QML tree contains the coordinator and focused Keybindings surfaces"
else
    fail "2.3 Aurelia keybindings QML components missing in $qml_dir"
fi

# 2.4: Aurelia shell.qml exposes the resident plugin registry/host and shell IPC
shell_qml="$ROOT/shell.qml"
if [[ -f "$shell_qml" ]] &&
   grep -q 'target: "shell"' "$shell_qml" &&
   grep -q 'PluginRegistry {' "$shell_qml" &&
   grep -q 'PluginHost {' "$shell_qml"; then
    pass "2.4 shell.qml exposes the resident shell IPC target, PluginRegistry, and PluginHost"
else
    fail "2.4 shell.qml missing shell IPC target, PluginRegistry, or PluginHost"
fi

# 2.5: Compatibility alias IPC endpoint forwards to the plugin host
if grep -q 'target: "hotkeys"' "$shell_qml" &&
   grep -q 'keybindingsIpc\.toggle()' "$shell_qml" &&
   grep -q 'target: "keybindings"' "$shell_qml"; then
    pass "2.5 shell.qml retains thin compatibility IPC aliases for Keybindings"
else
    fail "2.5 shell.qml missing compatibility IPC aliases for hotkeys"
fi
