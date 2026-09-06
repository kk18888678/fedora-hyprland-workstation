section "Component Registry and Invariants"

reset_component_registry

# Valid component registers
register_component \
    id "test_comp_a" \
    display_name "Test Component A" \
    category "Testing" \
    description "A test component" \
    supported_profiles "workstation vm" \
    recommended true \
    required false \
    removable true \
    roles "browser"

if component_exists "test_comp_a" && [[ "$(get_component_attr "test_comp_a" display_name)" == "Test Component A" ]]; then
    pass "valid component registers successfully and attributes are retrievable"
else
    fail "valid component registration failed"
fi

# Duplicate component ID rejected
dup_rc=0
register_component id "test_comp_a" display_name "Duplicate" category "Testing" 2>/dev/null || dup_rc=$?
if [[ "$dup_rc" -ne 0 ]]; then
    pass "duplicate component ID is rejected fail-closed"
else
    fail "duplicate component ID was not rejected"
fi

# Unknown dependency rejected
register_component \
    id "test_comp_b" \
    display_name "Test Component B" \
    category "Testing" \
    dependencies "nonexistent_component"
reg_val_rc=0
validate_component_registry 2>/dev/null || reg_val_rc=$?
if [[ "$reg_val_rc" -ne 0 ]]; then
    pass "registry referential integrity rejects unknown dependency"
else
    fail "registry allowed unknown dependency"
fi

# Invalid profile rejected
inv_prof_rc=0
register_component \
    id "test_comp_c" \
    display_name "Test Component C" \
    category "Testing" \
    supported_profiles "invalid_profile" 2>/dev/null || inv_prof_rc=$?
if [[ "$inv_prof_rc" -ne 0 ]]; then
    pass "component with invalid profile is rejected"
else
    fail "component with invalid profile was allowed"
fi

# Capability metadata available
reset_component_registry
register_component \
    id "prov_comp" \
    display_name "Provider Component" \
    category "Testing" \
    provides "cap_x"

register_component \
    id "test_cap" \
    display_name "Capability Test" \
    category "Testing" \
    provides "cap_y" \
    requires "cap_x"
if [[ "$(get_component_attr "test_cap" provides)" == "cap_y" && "$(get_component_attr "test_cap" requires)" == "cap_x" ]]; then
    pass "component capability provides and requires metadata are available"
else
    fail "component capability metadata retrieval failed"
fi

# Role provider metadata available
reset_component_registry
register_component id "b1" display_name "Browser 1" category "Browsers" roles "browser"
register_component id "b2" display_name "Browser 2" category "Browsers" roles "browser"
register_component id "ed1" display_name "Editor 1" category "Editors" roles "text-editor"
providers="$(get_role_providers "browser")"
if [[ "$providers" == *"b1"* && "$providers" == *"b2"* && "$providers" != *"ed1"* ]]; then
    pass "role provider discovery lists matching components"
else
    fail "role provider discovery failed: $providers"
fi

# Restore default representative components for remaining tests
reset_component_registry
init_default_components
