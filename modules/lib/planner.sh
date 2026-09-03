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
# - Dependencies are automatically resolved and marked with dependency reasons.
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
    detect_fn="$(get_component_attr "$id" detect_fn)"

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

    # 2. Dependency resolution loop
    local changed=1
    local iterations=0
    while [[ "$changed" -eq 1 ]]; do
        changed=0
        iterations=$(( iterations + 1 ))
        if [[ "$iterations" -gt 50 ]]; then
            printf 'ERROR: Circular dependency detected in component registry\n' >&2
            return 1
        fi

        for id in $(list_component_ids); do
            if [[ "${working_state[$id]}" == "managed" ]]; then
                local deps
                deps="$(get_component_attr "$id" dependencies)"
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

    # 3. Check for conflicts among all resolved managed components
    for id1 in $(list_component_ids); do
        if [[ "${working_state[$id1]}" == "managed" ]]; then
            local confs
            confs="$(get_component_attr "$id1" conflicts)"
            for id2 in $confs; do
                if [[ "${working_state[$id2]}" == "managed" ]]; then
                    printf 'ERROR: Conflict detected between %s and %s\n' "$id1" "$id2" >&2
                    return 1
                fi
            done
        fi
    done

    # 4. Plan component actions
    for id in $(list_component_ids); do
        local st="${working_state[$id]}"
        local is_present=0

        if [[ -n "$actual_prefix" ]]; then
            local -n act_map="${actual_prefix}_PRESENT"
            if [[ "${act_map[$id]:-false}" == "true" ]]; then
                is_present=1
            fi
        else
            if detect_component_presence "$id"; then
                is_present=1
            fi
        fi

        local disp
        disp="$(get_component_attr "$id" display_name)"
        local cat
        cat="$(get_component_attr "$id" category)"

        if [[ "$st" == "managed" ]]; then
            if [[ "$is_present" -eq 0 ]]; then
                local reason="selected by user"
                if [[ -n "${dependency_reason[$id]:-}" ]]; then
                    reason="${dependency_reason[$id]}"
                fi
                add_plan_action "$plan_prefix" "INSTALL" "$id" "$reason" "$disp ($cat)"
            else
                local cfg_fn
                cfg_fn="$(get_component_attr "$id" configure_fn)"
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
        elif [[ "$st" == "unmanaged" ]]; then
            if [[ "$is_present" -eq 1 ]]; then
                # Crucial invariant: preexisting unselected software is KEPT, not removed
                add_plan_action "$plan_prefix" "KEEP" "$id" "already installed (unmanaged)" "$disp ($cat)"
            fi
            # If absent and unmanaged, no action needed
        elif [[ "$st" == "remove" ]]; then
            if [[ "$is_present" -eq 1 ]]; then
                add_plan_action "$plan_prefix" "REMOVE" "$id" "explicitly deselected for removal" "$disp ($cat)"
            fi
            # If absent and remove, no action needed
        fi
    done

    # 5. Plan role default changes
    for role in "${SUPPORTED_ROLES[@]}"; do
        local desired_def="${ds_def_map[$role]:-}"
        if [[ -n "$desired_def" ]]; then
            local actual_def=""
            if [[ -n "$actual_prefix" ]]; then
                local -n act_def_map="${actual_prefix}_ROLE_DEFAULTS"
                actual_def="${act_def_map[$role]:-}"
            else
                actual_def="$(detect_current_role_default "$role")"
            fi

            if [[ "$actual_def" != "$desired_def" ]]; then
                local disp_desired
                disp_desired="$(get_component_attr "$desired_def" display_name)"
                add_plan_action "$plan_prefix" "CHANGE_DEFAULT" "$desired_def" \
                    "preferred default for $role" \
                    "$role: ${actual_def:-none} -> $disp_desired"
            fi
        fi
    done

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
