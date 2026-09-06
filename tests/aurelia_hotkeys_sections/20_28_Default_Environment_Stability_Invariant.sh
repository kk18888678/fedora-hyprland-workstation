section "28. Default Environment Stability Invariant"

# Noctalia must remain the Recommended/default environment unless explicitly changed
rec_noct="$(get_component_attr "desktop.environment.noctalia" recommended)"
rec_aure="$(get_component_attr "desktop.environment.aurelia" recommended)"
if [[ "$rec_noct" == "true" && "$rec_aure" == "false" ]]; then
    pass "28. Noctalia remains Recommended/default environment unless explicitly changed"
else
    fail "28. Desktop environment recommendation violated: noctalia=$rec_noct aurelia=$rec_aure"
fi
