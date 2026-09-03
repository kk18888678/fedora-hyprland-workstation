#!/usr/bin/env bash

# Configuration Planner for Fedora Hyprland Workstation.
#
# Consumes Desired State, Actual State, and Component Registry to produce an
# explicit, validated Plan.
#
# Invariants:
# - The planner performs NO mutations and invokes no installation/removal callbacks.
# - Preexisting unselected software is kept (unmanaged == KEEP, not REMOVE).
# - Removal is explicit (REMOVE action only when desired state is 'remove').
# - Dependencies are automatically resolved and ordered (dependency before dependent).
# - Dependency cycles fail closed before mutation.
# - Conflicts fail closed before planning completes.

init_plan() {
    local plan_prefix="$1"

    declare -g "${plan_prefix}_COUNT_INSTALL"=0
    declare -g "${plan_prefix}_COUNT_REMOVE"=0
    declare -g "${plan_prefix}_COUNT_KEEP"=0
    declare -g "${plan_prefix}_COUNT_CONFIGURE"=0
    declare -g "${plan_prefix}_COUNT_CHANGE_DEFAULT"=0

    declare -g -a "${plan_prefix}_ACTIONS"
    declare -g -A "${plan_prefix}_ACTION_TYPE"
    declare -g -A "${plan_prefix}_ACTION_TARGET"
    declare -g -A "${plan_prefix}_ACTION_REASON"
    declare -g -A "${plan_prefix}_ACTION_DETAILS"

    local -n _a_ref="${plan_prefix}_ACTIONS"
    local -n _t_ref="${plan_prefix}_ACTION_TYPE"
    local -n _tr_ref="${plan_prefix}_ACTION_TARGET"
    local -n _r_ref="${plan_prefix}_ACTION_REASON"
    local -n _d_ref="${plan_prefix}_ACTION_DETAILS"
    _a_ref=()
    _t_ref=()
    _tr_ref=()
    _r_ref=()
    _d_ref=()
}

add_plan_action() {
    local plan_prefix="$1"
    local action_type="$2"
    local target="$3"
    local reason="$4"
    local details="${5:-}"

    local -n actions_list="${plan_prefix}_ACTIONS"
    local -n type_map="${plan_prefix}_ACTION_TYPE"
    local -n target_map="${plan_prefix}_ACTION_TARGET"
    local -n reason_map="${plan_prefix}_ACTION_REASON"
    local -n details_map="${plan_prefix}_ACTION_DETAILS"

    local idx="${#actions_list[@]}"
    actions_list+=("$idx")
    type_map["$idx"]="$action_type"
    target_map["$idx"]="$target"
    reason_map["$idx"]="$reason"
    details_map["$idx"]="$details"

    case "$action_type" in
        INSTALL)
            local var="${plan_prefix}_COUNT_INSTALL"
            declare -g "$var"=$(( ${!var} + 1 ))
            ;;
        REMOVE)
            local var="${plan_prefix}_COUNT_REMOVE"
            declare -g "$var"=$(( ${!var} + 1 ))
            ;;
        KEEP)
            local var="${plan_prefix}_COUNT_KEEP"
            declare -g "$var"=$(( ${!var} + 1 ))
            ;;
        CONFIGURE)
            local var="${plan_prefix}_COUNT_CONFIGURE"
            declare -g "$var"=$(( ${!var} + 1 ))
            ;;
        CHANGE_DEFAULT)
            local var="${plan_prefix}_COUNT_CHANGE_DEFAULT"
            declare -g "$var"=$(( ${!var} + 1 ))
            ;;
    esac
}

# Detect actual state of a component using its registered detect_fn
detect_component_presence() {
    local id="$1"
    local detect_fn
    detect_fn="$(get_component_attr "$id" detect_fn 2>/dev/null || true)"

    if [[ -n "$detect_fn" ]] && type "$detect_fn" >/dev/null 2>&1; then
        if "$detect_fn" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi

    # Fallback to standard command_exists or package_installed
    if command_exists "$id" 2>/dev/null || package_installed "$id" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Detect current default provider for a role on the host
detect_current_role_default() {
    local role="$1"
    case "$role" in
        browser)
            if command_exists xdg-mime 2>/dev/null; then
                local def
                def="$(xdg-mime query default x-scheme-handler/https 2>/dev/null || true)"
                case "$def" in
                    *chromium*) printf 'chromium\n' ;;
                    *firefox*)  printf 'firefox\n' ;;
                    *) printf '' ;;
                esac
            fi
            ;;
        *)
            printf ''
            ;;
    esac
}

# Order component IDs topologically (dependency before dependent)
# Detects direct and indirect cycles without iteration counters.
# Arguments:
#   in_nodes_var: name of array containing component IDs to order
#   out_sorted_var: name of array to output topologically sorted component IDs
# Returns:
#   0 on success
#   1 on dependency cycle detected
topological_sort_components() {
    local in_nodes_var="$1"
    local out_sorted_var="$2"

    local -n _in_nodes="$in_nodes_var"
    local -n _out_sorted="$out_sorted_var"
    _out_sorted=()

    declare -A _in_set=()
    for n in "${_in_nodes[@]}"; do
        _in_set["$n"]=1
    done

    # 0 = unvisited, 1 = visiting (on call stack), 2 = visited (fully resolved)
    declare -A _visit_state=()

    _topo_dfs() {
        local curr="$1"
        local state="${_visit_state[$curr]:-0}"

        if [[ "$state" -eq 1 ]]; then
            printf 'ERROR: Dependency cycle detected involving component: %s\n' "$curr" >&2
            return 1
        fi
        if [[ "$state" -eq 2 ]]; then
            return 0
        fi

        _visit_state["$curr"]=1

        local deps
        deps="$(get_component_attr "$curr" dependencies 2>/dev/null || true)"
        for dep in $deps; do
            if [[ -n "${_in_set[$dep]:-}" ]]; then
                if ! _topo_dfs "$dep"; then
                    return 1
                fi
            fi
        done

        _visit_state["$curr"]=2
        _out_sorted+=("$curr")
        return 0
    }

    # Sort input component IDs alphabetically for deterministic graph traversal
    local sorted_candidates=()
    while IFS= read -r item; do
        [[ -n "$item" ]] && sorted_candidates+=("$item")
    done < <(printf '%s\n' "${_in_nodes[@]}" | sort)

    for cand in "${sorted_candidates[@]}"; do
        if [[ "${_visit_state[$cand]:-0}" -eq 0 ]]; then
            if ! _topo_dfs "$cand"; then
                return 1
            fi
        fi
    done

    return 0
}

# Compute deterministic fingerprint of all actions in a plan
compute_plan_fingerprint() {
    local plan_prefix="$1"
    local -n actions_list="${plan_prefix}_ACTIONS"
    local -n type_map="${plan_prefix}_ACTION_TYPE"
    local -n target_map="${plan_prefix}_ACTION_TARGET"
    local -n reason_map="${plan_prefix}_ACTION_REASON"
    local -n details_map="${plan_prefix}_ACTION_DETAILS"

    local c_inst="${plan_prefix}_COUNT_INSTALL"
    local c_rem="${plan_prefix}_COUNT_REMOVE"
    local c_cfg="${plan_prefix}_COUNT_CONFIGURE"
    local c_keep="${plan_prefix}_COUNT_KEEP"
    local c_def="${plan_prefix}_COUNT_CHANGE_DEFAULT"

    local lines=()
    lines+=("COUNTS:${!c_inst}:${!c_rem}:${!c_cfg}:${!c_keep}:${!c_def}")
    for idx in "${actions_list[@]}"; do
        lines+=("ACTION:$idx:${type_map[$idx]}:${target_map[$idx]}:${reason_map[$idx]}:${details_map[$idx]}")
    done

    printf '%s\n' "${lines[@]}" | sha256sum | awk '{print $1}'
}

# Validate internal structure of a plan before finalization or execution
_validate_plan_structure() {
    local plan_prefix="$1"

    local -n actions_list="${plan_prefix}_ACTIONS"
    local -n type_map="${plan_prefix}_ACTION_TYPE"
    local -n target_map="${plan_prefix}_ACTION_TARGET"
    local -n reason_map="${plan_prefix}_ACTION_REASON"
    local -n details_map="${plan_prefix}_ACTION_DETAILS"

    local c_inst="${plan_prefix}_COUNT_INSTALL"
    local c_rem="${plan_prefix}_COUNT_REMOVE"
    local c_cfg="${plan_prefix}_COUNT_CONFIGURE"
    local c_keep="${plan_prefix}_COUNT_KEEP"
    local c_def="${plan_prefix}_COUNT_CHANGE_DEFAULT"

    local sum=$(( ${!c_inst:-0} + ${!c_rem:-0} + ${!c_cfg:-0} + ${!c_keep:-0} + ${!c_def:-0} ))
    if [[ "$sum" -ne "${#actions_list[@]}" ]]; then
        printf 'ERROR: Plan action count mismatch: sum=%d, actions=%d\n' "$sum" "${#actions_list[@]}" >&2
        return 1
    fi

    declare -A seen_removes=()
    declare -A seen_installs=()
    for idx in "${actions_list[@]}"; do
        local atype="${type_map[$idx]:-}"
        local target="${target_map[$idx]:-}"

        if [[ -z "$atype" || -z "$target" ]]; then
            printf 'ERROR: Malformed plan action at index %s\n' "$idx" >&2
            return 1
        fi

        case "$atype" in
            INSTALL)
                if ! component_exists "$target"; then
                    printf 'ERROR: Plan INSTALL action references unknown component: %s\n' "$target" >&2
                    return 1
                fi
                seen_installs["$target"]="$idx"
                ;;
            KEEP|CONFIGURE)
                if ! component_exists "$target"; then
                    printf 'ERROR: Plan action %s references unknown component: %s\n' "$atype" "$target" >&2
                    return 1
                fi
                ;;
            REMOVE)
                if ! component_exists "$target"; then
                    printf 'ERROR: Plan REMOVE action references unknown component: %s\n' "$target" >&2
                    return 1
                fi
                local is_req
                is_req="$(get_component_attr "$target" required 2>/dev/null || true)"
                if [[ "$is_req" == "true" ]]; then
                    printf 'ERROR: Illegal plan action: required component %s cannot be removed\n' "$target" >&2
                    return 1
                fi
                local is_rem
                is_rem="$(get_component_attr "$target" removable 2>/dev/null || true)"
                if [[ "$is_rem" != "true" ]]; then
                    printf 'ERROR: Illegal plan action: component %s is not removable\n' "$target" >&2
                    return 1
                fi
                seen_removes["$target"]=1
                ;;
            CHANGE_DEFAULT)
                if ! component_exists "$target"; then
                    printf 'ERROR: Plan CHANGE_DEFAULT action references unknown component: %s\n' "$target" >&2
                    return 1
                fi
                local details="${details_map[$idx]:-}"
                local role="${details%%:*}"
                local valid_role=0
                for r in "${SUPPORTED_ROLES[@]}"; do
                    if [[ "$r" == "$role" ]]; then valid_role=1; break; fi
                done
                if [[ "$valid_role" -eq 0 ]]; then
                    printf 'ERROR: Plan CHANGE_DEFAULT action has unknown role: %s\n' "$role" >&2
                    return 1
                fi
                local comp_roles
                comp_roles="$(get_component_attr "$target" roles 2>/dev/null || true)"
                local has_role=0
                for r in $comp_roles; do
                    if [[ "$r" == "$role" ]]; then has_role=1; break; fi
                done
                if [[ "$has_role" -eq 0 ]]; then
                    printf 'ERROR: Target %s does not provide role %s in CHANGE_DEFAULT action\n' "$target" "$role" >&2
                    return 1
                fi
                ;;
            *)
                printf 'ERROR: Unknown action type in plan: %s\n' "$atype" >&2
                return 1
                ;;
        esac
    done

    # Check that no CHANGE_DEFAULT target is also marked for REMOVE
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "CHANGE_DEFAULT" ]]; then
            local target="${target_map[$idx]}"
            if [[ -n "${seen_removes[$target]:-}" ]]; then
                printf 'ERROR: Invalid plan: CHANGE_DEFAULT target %s is also marked for REMOVE\n' "$target" >&2
                return 1
            fi
        fi
    done

    # Verify dependency ordering in INSTALL actions: dependency must appear before dependent
    for target in "${!seen_installs[@]}"; do
        local target_idx="${seen_installs[$target]}"
        local deps
        deps="$(get_component_attr "$target" dependencies 2>/dev/null || true)"
        for dep in $deps; do
            if [[ -n "${seen_installs[$dep]:-}" ]]; then
                local dep_idx="${seen_installs[$dep]}"
                if [[ "$dep_idx" -ge "$target_idx" ]]; then
                    printf 'ERROR: Dependency ordering violation: %s (idx %d) must precede %s (idx %d)\n' \
                        "$dep" "$dep_idx" "$target" "$target_idx" >&2
                    return 1
                fi
            fi
        done
    done

    return 0
}

# Finalize plan and compute deterministic integrity fingerprint
finalize_plan() {
    local plan_prefix="$1"

    if ! _validate_plan_structure "$plan_prefix"; then
        return 1
    fi

    local fp
    fp="$(compute_plan_fingerprint "$plan_prefix")"
    declare -g "${plan_prefix}_FINGERPRINT"="$fp"
    declare -g "${plan_prefix}_VALIDATED"="true"
    return 0
}

# Validate plan before execution (fails closed on unfinalized, malformed, or modified plans)
validate_plan() {
    local plan_prefix="$1"

    local val_var="${plan_prefix}_VALIDATED"
    if [[ "${!val_var:-}" != "true" ]]; then
        printf 'ERROR: Plan %s has not been finalized or validated\n' "$plan_prefix" >&2
        return 1
    fi

    if ! _validate_plan_structure "$plan_prefix"; then
        return 1
    fi

    local fp_var="${plan_prefix}_FINGERPRINT"
    local expected_fp="${!fp_var:-}"
    if [[ -z "$expected_fp" ]]; then
        printf 'ERROR: Plan %s lacks validation fingerprint\n' "$plan_prefix" >&2
        return 1
    fi

    local actual_fp
    actual_fp="$(compute_plan_fingerprint "$plan_prefix")"
    if [[ "$expected_fp" != "$actual_fp" ]]; then
        printf 'ERROR: Plan %s failed integrity check: fingerprint mismatch (unexpected plan mutation)\n' "$plan_prefix" >&2
        return 1
    fi

    return 0
}

# Create an execution plan
# Arguments:
#   desired_state_prefix: name of desired state variable structure
#   plan_prefix: name of plan structure to output
#   actual_state_prefix (optional): synthetic actual state for isolated testing
create_execution_plan() {
    local ds_prefix="$1"
    local plan_prefix="$2"
    local actual_prefix="${3:-}"

    # 1. Validate Desired State invariants before anything else
    validate_desired_state "$ds_prefix" || return 1

    init_plan "$plan_prefix"

    local -n ds_comp_map="${ds_prefix}_COMPONENTS"
    local -n ds_def_map="${ds_prefix}_ROLE_DEFAULTS"

    # Working copy of component states for dependency resolution
    declare -A working_state=()
    declare -A dependency_reason=()

    for id in $(list_component_ids); do
        working_state["$id"]="${ds_comp_map[$id]:-unmanaged}"
    done

    # 2. Dependency resolution loop (auto-promotes unmanaged dependencies to managed)
    local changed=1
    while [[ "$changed" -eq 1 ]]; do
        changed=0
        for id in $(list_component_ids); do
            if [[ "${working_state[$id]}" == "managed" ]]; then
                local deps
                deps="$(get_component_attr "$id" dependencies 2>/dev/null || true)"
                for dep in $deps; do
                    # Cannot depend on a component explicitly marked for removal
                    if [[ "${working_state[$dep]}" == "remove" ]]; then
                        printf 'ERROR: Component %s requires %s, which is marked for removal\n' "$id" "$dep" >&2
                        return 1
                    fi
                    if [[ "${working_state[$dep]}" != "managed" ]]; then
                        working_state["$dep"]="managed"
                        dependency_reason["$dep"]="required by $id"
                        changed=1
                    fi
                done
            fi
        done
    done

    # 3. Cycle detection and topological sort of all managed components
    local managed_ids=()
    for id in $(list_component_ids); do
        if [[ "${working_state[$id]}" == "managed" ]]; then
            managed_ids+=("$id")
        fi
    done
    local sorted_managed=()
    if ! topological_sort_components managed_ids sorted_managed; then
        return 1
    fi

    # 4. Check for conflicts among all resolved managed components
    for id1 in "${sorted_managed[@]}"; do
        local confs
        confs="$(get_component_attr "$id1" conflicts 2>/dev/null || true)"
        for id2 in $confs; do
            if [[ "${working_state[$id2]}" == "managed" ]]; then
                printf 'ERROR: Conflict detected between %s and %s\n' "$id1" "$id2" >&2
                return 1
            fi
        done
    done

    # 5. Capability requirements validation
    for id in "${sorted_managed[@]}"; do
        local reqs
        reqs="$(get_component_attr "$id" requires 2>/dev/null || true)"
        for req in $reqs; do
            local satisfied=0
            for other in $(list_component_ids); do
                local other_st="${working_state[$other]}"
                if [[ "$other_st" == "managed" ]]; then
                    local provs
                    provs="$(get_component_attr "$other" provides 2>/dev/null || true)"
                    for p in $provs; do
                        if [[ "$p" == "$req" ]]; then satisfied=1; break 2; fi
                    done
                fi
            done
            if [[ "$satisfied" -eq 0 ]]; then
                printf 'ERROR: Component %s requires capability %s, but no active component provides it\n' "$id" "$req" >&2
                return 1
            fi
        done
    done

    # 6. Removal ordering: dependents must be removed before dependencies
    local remove_ids=()
    for id in $(list_component_ids); do
        if [[ "${working_state[$id]}" == "remove" ]]; then
            remove_ids+=("$id")
        fi
    done
    local sorted_removes=()
    if [[ "${#remove_ids[@]}" -gt 0 ]]; then
        if ! topological_sort_components remove_ids sorted_removes; then
            return 1
        fi
    fi
    # Reverse topological sort so dependent is removed before dependency
    local ordered_removes=()
    local rem_len="${#sorted_removes[@]}"
    for (( i = rem_len - 1; i >= 0; i-- )); do
        ordered_removes+=("${sorted_removes[i]}")
    done

    # 7. Plan REMOVE actions first (in safe reverse-dependency order)
    for id in "${ordered_removes[@]}"; do
        local is_present=0
        if [[ -n "$actual_prefix" ]]; then
            local act_pres_var="${actual_prefix}_PRESENT"
            if declare -p "$act_pres_var" >/dev/null 2>&1; then
                local -n act_map="$act_pres_var"
                if [[ "${act_map[$id]:-false}" == "true" ]]; then is_present=1; fi
            fi
        else
            if detect_component_presence "$id"; then is_present=1; fi
        fi

        local disp
        disp="$(get_component_attr "$id" display_name 2>/dev/null || true)"
        local cat
        cat="$(get_component_attr "$id" category 2>/dev/null || true)"

        if [[ "$is_present" -eq 1 ]]; then
            add_plan_action "$plan_prefix" "REMOVE" "$id" "explicitly deselected for removal" "$disp ($cat)"
        fi
    done

    # 8. Plan INSTALL, CONFIGURE, and KEEP actions for managed components (in dependency order)
    for id in "${sorted_managed[@]}"; do
        local is_present=0
        if [[ -n "$actual_prefix" ]]; then
            local act_pres_var="${actual_prefix}_PRESENT"
            if declare -p "$act_pres_var" >/dev/null 2>&1; then
                local -n act_map="$act_pres_var"
                if [[ "${act_map[$id]:-false}" == "true" ]]; then is_present=1; fi
            fi
        else
            if detect_component_presence "$id"; then is_present=1; fi
        fi

        local disp
        disp="$(get_component_attr "$id" display_name 2>/dev/null || true)"
        local cat
        cat="$(get_component_attr "$id" category 2>/dev/null || true)"

        if [[ "$is_present" -eq 0 ]]; then
            local reason="selected by user"
            if [[ -n "${dependency_reason[$id]:-}" ]]; then
                reason="${dependency_reason[$id]}"
            fi
            add_plan_action "$plan_prefix" "INSTALL" "$id" "$reason" "$disp ($cat)"
        else
            local cfg_fn
            cfg_fn="$(get_component_attr "$id" configure_fn 2>/dev/null || true)"
            if [[ -n "$cfg_fn" ]]; then
                add_plan_action "$plan_prefix" "CONFIGURE" "$id" "configuration update" "$disp ($cat)"
            else
                local reason="already installed and managed"
                if [[ -n "${dependency_reason[$id]:-}" ]]; then
                    reason="already installed (${dependency_reason[$id]})"
                fi
                add_plan_action "$plan_prefix" "KEEP" "$id" "$reason" "$disp ($cat)"
            fi
        fi
    done

    # 9. Plan KEEP actions for preexisting unmanaged components (preservation invariant)
    local unmanaged_ids=()
    for id in $(list_component_ids); do
        if [[ "${working_state[$id]}" == "unmanaged" ]]; then
            unmanaged_ids+=("$id")
        fi
    done
    local sorted_unmanaged=()
    while IFS= read -r item; do
        [[ -n "$item" ]] && sorted_unmanaged+=("$item")
    done < <(printf '%s\n' "${unmanaged_ids[@]}" | sort)

    for id in "${sorted_unmanaged[@]}"; do
        local is_present=0
        if [[ -n "$actual_prefix" ]]; then
            local act_pres_var="${actual_prefix}_PRESENT"
            if declare -p "$act_pres_var" >/dev/null 2>&1; then
                local -n act_map="$act_pres_var"
                if [[ "${act_map[$id]:-false}" == "true" ]]; then is_present=1; fi
            fi
        else
            if detect_component_presence "$id"; then is_present=1; fi
        fi

        local disp
        disp="$(get_component_attr "$id" display_name 2>/dev/null || true)"
        local cat
        cat="$(get_component_attr "$id" category 2>/dev/null || true)"

        if [[ "$is_present" -eq 1 ]]; then
            add_plan_action "$plan_prefix" "KEEP" "$id" "already installed (unmanaged)" "$disp ($cat)"
        fi
    done

    # 10. Plan role default changes
    for role in "${SUPPORTED_ROLES[@]}"; do
        local desired_def="${ds_def_map[$role]:-}"
        if [[ -n "$desired_def" ]]; then
            local actual_def=""
            if [[ -n "$actual_prefix" ]]; then
                local act_def_var="${actual_prefix}_ROLE_DEFAULTS"
                if declare -p "$act_def_var" >/dev/null 2>&1; then
                    local -n act_def_map="$act_def_var"
                    actual_def="${act_def_map[$role]:-}"
                fi
            else
                actual_def="$(detect_current_role_default "$role")"
            fi

            if [[ "$actual_def" != "$desired_def" ]]; then
                local disp_desired
                disp_desired="$(get_component_attr "$desired_def" display_name 2>/dev/null || true)"
                add_plan_action "$plan_prefix" "CHANGE_DEFAULT" "$desired_def" \
                    "preferred default for $role" \
                    "$role: ${actual_def:-none} -> $disp_desired"
            fi
        fi
    done

    # 11. Finalize plan structure and attach integrity fingerprint
    finalize_plan "$plan_prefix" || return 1

    return 0
}

# Format plan summary for display/review
format_plan_summary() {
    local plan_prefix="$1"

    local -n actions_list="${plan_prefix}_ACTIONS"
    local -n type_map="${plan_prefix}_ACTION_TYPE"
    local -n target_map="${plan_prefix}_ACTION_TARGET"
    local -n reason_map="${plan_prefix}_ACTION_REASON"
    local -n details_map="${plan_prefix}_ACTION_DETAILS"

    local c_inst="${plan_prefix}_COUNT_INSTALL"
    local c_rem="${plan_prefix}_COUNT_REMOVE"
    local c_cfg="${plan_prefix}_COUNT_CONFIGURE"
    local c_keep="${plan_prefix}_COUNT_KEEP"
    local c_def="${plan_prefix}_COUNT_CHANGE_DEFAULT"

    printf '%s\n' '============================================================'
    printf 'WORKSTATION CONFIGURATION PLAN\n'
    printf '%s\n\n' '============================================================'

    # 1. INSTALL
    local has_inst=0
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "INSTALL" ]]; then
            if [[ "$has_inst" -eq 0 ]]; then
                printf 'INSTALL (%d components):\n' "${!c_inst}"
                has_inst=1
            fi
            printf '  + %-24s [%s]\n' "${details_map[$idx]}" "${reason_map[$idx]}"
        fi
    done
    [[ "$has_inst" -eq 1 ]] && printf '\n'

    # 2. CONFIGURE
    local has_cfg=0
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "CONFIGURE" ]]; then
            if [[ "$has_cfg" -eq 0 ]]; then
                printf 'CONFIGURE (%d components):\n' "${!c_cfg}"
                has_cfg=1
            fi
            printf '  * %-24s [%s]\n' "${details_map[$idx]}" "${reason_map[$idx]}"
        fi
    done
    [[ "$has_cfg" -eq 1 ]] && printf '\n'

    # 3. CHANGE DEFAULT
    local has_def=0
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "CHANGE_DEFAULT" ]]; then
            if [[ "$has_def" -eq 0 ]]; then
                printf 'CHANGE DEFAULT (%d roles):\n' "${!c_def}"
                has_def=1
            fi
            printf '  > %-24s [%s]\n' "${details_map[$idx]}" "${reason_map[$idx]}"
        fi
    done
    [[ "$has_def" -eq 1 ]] && printf '\n'

    # 4. KEEP
    local has_keep=0
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "KEEP" ]]; then
            if [[ "$has_keep" -eq 0 ]]; then
                printf 'KEEP (%d components):\n' "${!c_keep}"
                has_keep=1
            fi
            printf '    %-24s [%s]\n' "${details_map[$idx]}" "${reason_map[$idx]}"
        fi
    done
    [[ "$has_keep" -eq 1 ]] && printf '\n'

    # 5. REMOVE (Destructive highlight)
    local has_rem=0
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "REMOVE" ]]; then
            if [[ "$has_rem" -eq 0 ]]; then
                printf '!!! REMOVE (DESTRUCTIVE) (%d components) !!!\n' "${!c_rem}"
                has_rem=1
            fi
            printf '  - %-24s [%s]\n' "${details_map[$idx]}" "${reason_map[$idx]}"
        fi
    done
    [[ "$has_rem" -eq 1 ]] && printf '\n'

    printf '%s\n' '------------------------------------------------------------'
    printf 'Summary: %d install, %d configure, %d default change, %d keep, %d remove\n' \
        "${!c_inst}" "${!c_cfg}" "${!c_def}" "${!c_keep}" "${!c_rem}"
    printf '%s\n' '------------------------------------------------------------'
}
