section "2. Environment IDs Distinction"

noct_id="desktop.environment.noctalia"
aure_id="desktop.environment.aurelia"
if [[ "$noct_id" != "$aure_id" ]] &&
   [[ "$(get_component_attr "$noct_id" provides)" == "desktop_environment" ]] &&
   [[ "$(get_component_attr "$aure_id" provides)" == "desktop_environment" ]] &&
   [[ "$(get_component_attr "$noct_id" conflicts)" == *"$aure_id"* ]] &&
   [[ "$(get_component_attr "$aure_id" conflicts)" == *"$noct_id"* ]]; then
    pass "2. Noctalia and Aurelia environment IDs are distinct, registered as peers, and mutually conflicting"
else
    fail "2. Noctalia and Aurelia environment IDs or conflict declarations invalid"
fi
