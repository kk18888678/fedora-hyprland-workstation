section "38-40. Coexistence and Adaptation Invariants"

# Test 38: Inactive Aurelia plugins remain unloaded
if grep -q 'active: host.shouldLoad(pluginId)' "$ROOT/aurelia-shell/services/PluginHost.qml" &&
   grep -q 'function shouldLoad(id)' "$ROOT/aurelia-shell/services/PluginHost.qml"; then
    pass "38. inactive Aurelia plugins remain unloaded"
else
    fail "38. inactive Aurelia plugins not conditionally loaded"
fi

# Test 39: Noctalia components remain untouched when Aurelia Hotkeys is selected
reset_component_registry
init_default_components
init_desired_state "DS_NOCT_UNTOUCH" "workstation"
create_recommended_desired_state "DS_NOCT_UNTOUCH" "workstation"
desired_state_set_component "DS_NOCT_UNTOUCH" "desktop.hotkeys.aurelia" "managed"
noct_status="$(desired_state_get_component "DS_NOCT_UNTOUCH" "desktop.environment.noctalia")"
if [[ "$noct_status" == "managed" ]]; then
    pass "39. Noctalia components remain untouched when Aurelia Hotkeys selected"
else
    fail "39. Noctalia component state mutated: $noct_status"
fi

# Test 40: Nautilus role default detection works
(
    xdg-mime() {
        if [[ "$1" == "query" && "$2" == "default" && "$3" == "inode/directory" ]]; then
            printf '%s\n' "org.gnome.Nautilus.desktop"
        fi
    }
    export -f xdg-mime
    fm_detected="$(detect_file_manager_default_adapter)"
    if [[ "$fm_detected" == "nautilus" ]]; then
        pass "40. Nautilus role default detection works"
    else
        fail "40. Nautilus default detection failed: $fm_detected"
    fi
)
