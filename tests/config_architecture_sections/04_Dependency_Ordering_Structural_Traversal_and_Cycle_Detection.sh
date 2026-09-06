section "Dependency Ordering, Structural Traversal, and Cycle Detection"

# Register isolated synthetic components for dependency graph tests
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "dep_a" display_name "Comp A" category "Testing" dependencies "dep_b"
register_component id "dep_b" display_name "Comp B" category "Testing" dependencies "dep_c"
register_component id "dep_c" display_name "Comp C" category "Testing"
register_component id "dia_top" display_name "Dia Top" category "Testing" dependencies "dia_left dia_right"
register_component id "dia_left" display_name "Dia Left" category "Testing" dependencies "dia_base"
register_component id "dia_right" display_name "Dia Right" category "Testing" dependencies "dia_base"
register_component id "dia_base" display_name "Dia Base" category "Testing"

# 20. Dependency ordered before dependent (simple)
ds_ord1="DS_ORD1"
init_desired_state "$ds_ord1" "workstation" "customize"
desired_state_set_component "$ds_ord1" "foot" "managed"
desired_state_set_component "$ds_ord1" "dep_b" "managed"
declare -g -A ACT_ORD1_PRESENT=([foot]=true [dep_b]=false [dep_c]=false)
create_execution_plan "$ds_ord1" "PLAN_ORD1" "ACT_ORD1"
idx_b=-1
idx_c=-1
for idx in "${PLAN_ORD1_ACTIONS[@]}"; do
    if [[ "${PLAN_ORD1_ACTION_TARGET[$idx]}" == "dep_b" && "${PLAN_ORD1_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_b=$idx; fi
    if [[ "${PLAN_ORD1_ACTION_TARGET[$idx]}" == "dep_c" && "${PLAN_ORD1_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_c=$idx; fi
done
if [[ "$idx_c" -ge 0 && "$idx_b" -ge 0 && "$idx_c" -lt "$idx_b" ]]; then
    pass "20. dependency (dep_c) is ordered before dependent (dep_b) in execution plan"
else
    fail "20. dependency ordering failed: idx_c=$idx_c, idx_b=$idx_b"
fi

# 21. Multi-level dependency ordering (A -> B -> C)
ds_ord2="DS_ORD2"
init_desired_state "$ds_ord2" "workstation" "customize"
desired_state_set_component "$ds_ord2" "foot" "managed"
desired_state_set_component "$ds_ord2" "dep_a" "managed"
declare -g -A ACT_ORD2_PRESENT=([foot]=true [dep_a]=false [dep_b]=false [dep_c]=false)
create_execution_plan "$ds_ord2" "PLAN_ORD2" "ACT_ORD2"
idx_a=-1; idx_b=-1; idx_c=-1
for idx in "${PLAN_ORD2_ACTIONS[@]}"; do
    if [[ "${PLAN_ORD2_ACTION_TARGET[$idx]}" == "dep_a" && "${PLAN_ORD2_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_a=$idx; fi
    if [[ "${PLAN_ORD2_ACTION_TARGET[$idx]}" == "dep_b" && "${PLAN_ORD2_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_b=$idx; fi
    if [[ "${PLAN_ORD2_ACTION_TARGET[$idx]}" == "dep_c" && "${PLAN_ORD2_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_c=$idx; fi
done
if [[ "$idx_c" -ge 0 && "$idx_b" -ge 0 && "$idx_a" -ge 0 && "$idx_c" -lt "$idx_b" && "$idx_b" -lt "$idx_a" ]]; then
    pass "21. multi-level dependency ordering (C < B < A) is preserved"
else
    fail "21. multi-level ordering failed: C=$idx_c, B=$idx_b, A=$idx_a"
fi

# 22. Diamond dependency ordering (Top -> Left, Right -> Base)
ds_dia="DS_DIA"
init_desired_state "$ds_dia" "workstation" "customize"
desired_state_set_component "$ds_dia" "foot" "managed"
desired_state_set_component "$ds_dia" "dia_top" "managed"
declare -g -A ACT_DIA_PRESENT=([foot]=true [dia_top]=false [dia_left]=false [dia_right]=false [dia_base]=false)
create_execution_plan "$ds_dia" "PLAN_DIA" "ACT_DIA"
idx_base=-1; idx_left=-1; idx_right=-1; idx_top=-1
for idx in "${PLAN_DIA_ACTIONS[@]}"; do
    if [[ "${PLAN_DIA_ACTION_TARGET[$idx]}" == "dia_base" && "${PLAN_DIA_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_base=$idx; fi
    if [[ "${PLAN_DIA_ACTION_TARGET[$idx]}" == "dia_left" && "${PLAN_DIA_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_left=$idx; fi
    if [[ "${PLAN_DIA_ACTION_TARGET[$idx]}" == "dia_right" && "${PLAN_DIA_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_right=$idx; fi
    if [[ "${PLAN_DIA_ACTION_TARGET[$idx]}" == "dia_top" && "${PLAN_DIA_ACTION_TYPE[$idx]}" == "INSTALL" ]]; then idx_top=$idx; fi
done
if [[ "$idx_base" -lt "$idx_left" && "$idx_base" -lt "$idx_right" && "$idx_left" -lt "$idx_top" && "$idx_right" -lt "$idx_top" ]]; then
    pass "22. diamond dependency graph orders base before branches and branches before top"
else
    fail "22. diamond ordering failed: base=$idx_base, left=$idx_left, right=$idx_right, top=$idx_top"
fi

# 23. Direct dependency cycle -> fail
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "cyc_a" display_name "Cycle A" category "Testing" dependencies "cyc_b"
register_component id "cyc_b" display_name "Cycle B" category "Testing" dependencies "cyc_a"
ds_cyc1="DS_CYC1"
init_desired_state "$ds_cyc1" "workstation" "customize"
desired_state_set_component "$ds_cyc1" "foot" "managed"
desired_state_set_component "$ds_cyc1" "cyc_a" "managed"
cyc1_rc=0
create_execution_plan "$ds_cyc1" "PLAN_CYC1" 2>/dev/null || cyc1_rc=$?
if [[ "$cyc1_rc" -ne 0 ]]; then
    pass "23. direct dependency cycle (A -> B -> A) fails closed before mutation"
else
    fail "23. direct cycle was allowed"
fi

# 24. Indirect dependency cycle -> fail
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "ind_a" display_name "Ind A" category "Testing" dependencies "ind_b"
register_component id "ind_b" display_name "Ind B" category "Testing" dependencies "ind_c"
register_component id "ind_c" display_name "Ind C" category "Testing" dependencies "ind_a"
ds_cyc2="DS_CYC2"
init_desired_state "$ds_cyc2" "workstation" "customize"
desired_state_set_component "$ds_cyc2" "foot" "managed"
desired_state_set_component "$ds_cyc2" "ind_a" "managed"
cyc2_rc=0
create_execution_plan "$ds_cyc2" "PLAN_CYC2" 2>/dev/null || cyc2_rc=$?
if [[ "$cyc2_rc" -ne 0 ]]; then
    pass "24. indirect dependency cycle (A -> B -> C -> A) fails closed before mutation"
else
    fail "24. indirect cycle was allowed"
fi

# 25. Dependency marked remove -> fail
reset_component_registry
register_component id "foot" display_name "Foot" category "Desktop" required true removable false roles "terminal"
register_component id "parent_comp" display_name "Parent" category "Testing" dependencies "child_comp"
register_component id "child_comp" display_name "Child" category "Testing" removable true
ds_rem_dep="DS_REM_DEP"
init_desired_state "$ds_rem_dep" "workstation" "customize"
desired_state_set_component "$ds_rem_dep" "foot" "managed"
desired_state_set_component "$ds_rem_dep" "parent_comp" "managed"
desired_state_set_component "$ds_rem_dep" "child_comp" "remove"
rem_dep_rc=0
create_execution_plan "$ds_rem_dep" "PLAN_REM_DEP" 2>/dev/null || rem_dep_rc=$?
if [[ "$rem_dep_rc" -ne 0 ]]; then
    pass "25. planning fails closed when required dependency is marked for removal"
else
    fail "25. planning permitted dependency marked remove"
fi

# 26. Deterministic plan ordering across repeated planning
reset_component_registry
init_default_components
ds_det="DS_DET"
create_recommended_desired_state "$ds_det" "workstation"
declare -g -A ACT_DET_PRESENT=([foot]=false [chromium]=false [firefox]=false [neovim]=false [nix]=false [devenv]=false [htop]=false)
create_execution_plan "$ds_det" "PLAN_DET_1" "ACT_DET"
create_execution_plan "$ds_det" "PLAN_DET_2" "ACT_DET"
if [[ "$PLAN_DET_1_FINGERPRINT" == "$PLAN_DET_2_FINGERPRINT" ]]; then
    pass "26. repeated plan generation produces byte-identical deterministic plan fingerprint"
else
    fail "26. plan generation was non-deterministic"
fi
