section "1. Aurelia Component Metadata Validation"

reset_component_registry
init_default_components

if component_exists "desktop.environment.aurelia" &&
   component_exists "desktop.hotkeys.aurelia" &&
   component_exists "quickshell"; then
    pass "1. Aurelia component metadata validates successfully"
else
    fail "1. Aurelia components missing from registry"
fi
