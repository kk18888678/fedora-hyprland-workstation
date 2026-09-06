section "5. Legacy Hotkeys Component Rejection"

reset_component_registry
init_default_components
if ! component_exists "desktop.hotkeys.legacy"; then
    pass "5. legacy fzf hotkeys component is removed from registry"
else
    fail "5. legacy fzf hotkeys component still exists in registry"
fi
