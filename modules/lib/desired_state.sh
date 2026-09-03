#!/usr/bin/env bash

# Desired State representation and validation for Fedora Hyprland Workstation.
#
# Provides a normalized, deterministic desired-state model consumed by both
# Recommended and Customize setup modes.
#
# Invariants:
# - Deselection in customization never implies removal (unmanaged != remove).
# - Removal is explicit.
# - Required components cannot be unmanaged or removed.
# - Role defaults must reference eligible components providing that role.
# - State validation fails closed before mutation.

# Initialize a desired state instance
init_desired_state() {
    local prefix="$1"
    local profile="$2"
    local setup_mode="${3:-recommended}"

    if [[ -z "$prefix" ]]; then
        printf 'ERROR: init_desired_state requires a state prefix\n' >&2
        return 1
    fi

    # Validate profile
    local valid_profile=0
    for p in "${SUPPORTED_PROFILES[@]}"; do
        if [[ "$p" == "$profile" ]]; then valid_profile=1; break; fi
    done
    if [[ "$valid_profile" -eq 0 ]]; then
        printf 'ERROR: Invalid profile for desired state: %s\n' "$profile" >&2
        return 1
    fi

    # Validate setup mode
    if [[ "$setup_mode" != "recommended" && "$setup_mode" != "customize" ]]; then
        printf 'ERROR: Invalid setup mode: %s (must be recommended or customize)\n' "$setup_mode" >&2
        return 1
    fi

    declare -g "${prefix}_PROFILE"="$profile"
    declare -g "${prefix}_SETUP_MODE"="$setup_mode"
    declare -g -A "${prefix}_COMPONENTS"
    declare -g -A "${prefix}_ROLE_DEFAULTS"
    local -n _c_ref="${prefix}_COMPONENTS"
    local -n _d_ref="${prefix}_ROLE_DEFAULTS"
    _c_ref=()
    _d_ref=()

    return 0
}

# Set management state for a component in desired state:
# states: managed, unmanaged, remove
desired_state_set_component() {
    local prefix="$1"
    local id="$2"
    local state="$3"

    if [[ "$state" != "managed" && "$state" != "unmanaged" && "$state" != "remove" ]]; then
        printf 'ERROR: Invalid component desired state: %s (must be managed, unmanaged, or remove)\n' "$state" >&2
        return 1
    fi

    local -n comp_map="${prefix}_COMPONENTS"
    comp_map["$id"]="$state"
    return 0
}

# Get management state for a component
desired_state_get_component() {
    local prefix="$1"
    local id="$2"

    local -n comp_map="${prefix}_COMPONENTS"
    printf '%s\n' "${comp_map[$id]:-unmanaged}"
}

# Set default component for a role
desired_state_set_default() {
    local prefix="$1"
    local role="$2"
    local id="$3"

    local -n def_map="${prefix}_ROLE_DEFAULTS"
    def_map["$role"]="$id"
    return 0
}

# Get default component for a role
desired_state_get_default() {
    local prefix="$1"
    local role="$2"

    local -n def_map="${prefix}_ROLE_DEFAULTS"
    printf '%s\n' "${def_map[$role]:-}"
}

# Create opinionated recommended desired state for a given profile
create_recommended_desired_state() {
    local prefix="$1"
    local profile="$2"

    init_desired_state "$prefix" "$profile" "recommended" || return 1

    local ids
    ids="$(list_component_ids)"
    for id in $ids; do
        if ! component_supports_profile "$id" "$profile"; then
            desired_state_set_component "$prefix" "$id" "unmanaged"
            continue
        fi

        local rec
        rec="$(get_component_attr "$id" recommended)"
        local req
        req="$(get_component_attr "$id" required)"

        if [[ "$rec" == "true" || "$req" == "true" ]]; then
            desired_state_set_component "$prefix" "$id" "managed"
        else
            desired_state_set_component "$prefix" "$id" "unmanaged"
        fi
    done

    # Automatically set defaults for supported roles based on recommended components
    for role in "${SUPPORTED_ROLES[@]}"; do
        local providers
        providers="$(get_role_providers "$role" "$profile")"
        for p in $providers; do
            local st
            st="$(desired_state_get_component "$prefix" "$p")"
            if [[ "$st" == "managed" ]]; then
                desired_state_set_default "$prefix" "$role" "$p"
                break
            fi
        done
    done

    return 0
}

# Validate invariants on Desired State
validate_desired_state() {
    local prefix="$1"

    local prof_var="${prefix}_PROFILE"
    local mode_var="${prefix}_SETUP_MODE"
    local profile="${!prof_var:-}"
    local setup_mode="${!mode_var:-}"

    if [[ -z "$profile" ]]; then
        printf 'ERROR: Desired state profile is not defined\n' >&2
        return 1
    fi

    local valid_prof=0
    for p in "${SUPPORTED_PROFILES[@]}"; do
        if [[ "$p" == "$profile" ]]; then valid_prof=1; break; fi
    done
    if [[ "$valid_prof" -eq 0 ]]; then
        printf 'ERROR: Desired state specifies unknown profile: %s\n' "$profile" >&2
        return 1
    fi

    if [[ "$setup_mode" != "recommended" && "$setup_mode" != "customize" ]]; then
        printf 'ERROR: Desired state specifies invalid setup mode: %s\n' "$setup_mode" >&2
        return 1
    fi

    local -n comp_map="${prefix}_COMPONENTS"
    local -n def_map="${prefix}_ROLE_DEFAULTS"

    # Check each component entry
    for id in "${!comp_map[@]}"; do
        if ! component_exists "$id"; then
            printf 'ERROR: Desired state references unknown component: %s\n' "$id" >&2
            return 1
        fi

        local state="${comp_map[$id]}"
        if [[ "$state" != "managed" && "$state" != "unmanaged" && "$state" != "remove" ]]; then
            printf 'ERROR: Desired state has invalid state for %s: %s\n' "$id" "$state" >&2
            return 1
        fi

        local is_req
        is_req="$(get_component_attr "$id" required)"
        local is_rem
        is_rem="$(get_component_attr "$id" removable)"

        # Required components cannot be unmanaged or removed
        if [[ "$is_req" == "true" ]]; then
            if [[ "$state" == "remove" ]]; then
                printf 'ERROR: Required component %s cannot be removed\n' "$id" >&2
                return 1
            fi
            if [[ "$state" == "unmanaged" ]]; then
                printf 'ERROR: Required component %s cannot be unmanaged\n' "$id" >&2
                return 1
            fi
        fi

        # Only explicitly removable components can be marked remove
        if [[ "$state" == "remove" && "$is_rem" != "true" ]]; then
            printf 'ERROR: Component %s is not removable\n' "$id" >&2
            return 1
        fi
    done

    # Conflict validation between managed components
    for id1 in "${!comp_map[@]}"; do
        if [[ "${comp_map[$id1]}" == "managed" ]]; then
            local confs
            confs="$(get_component_attr "$id1" conflicts)"
            for id2 in $confs; do
                if [[ "${comp_map[$id2]:-unmanaged}" == "managed" ]]; then
                    printf 'ERROR: Conflict in desired state between %s and %s\n' "$id1" "$id2" >&2
                    return 1
                fi
            done
        fi
    done

    # Validate role defaults
    for role in "${!def_map[@]}"; do
        local def_id="${def_map[$role]}"
        if [[ -n "$def_id" ]]; then
            if ! component_exists "$def_id"; then
                printf 'ERROR: Default for role %s references unknown component: %s\n' "$role" "$def_id" >&2
                return 1
            fi

            # Check that component actually provides this role
            local comp_roles
            comp_roles="$(get_component_attr "$def_id" roles)"
            local role_matched=0
            for r in $comp_roles; do
                if [[ "$r" == "$role" ]]; then role_matched=1; break; fi
            done
            if [[ "$role_matched" -eq 0 ]]; then
                printf 'ERROR: Component %s does not provide role: %s\n' "$def_id" "$role" >&2
                return 1
            fi

            # Check that the default component is not marked for removal
            local comp_state="${comp_map[$def_id]:-unmanaged}"
            if [[ "$comp_state" == "remove" ]]; then
                printf 'ERROR: Default component %s for role %s is marked for removal\n' "$def_id" "$role" >&2
                return 1
            fi
        fi
    done

    return 0
}

# Serialize desired state into deterministic text
serialize_desired_state() {
    local prefix="$1"

    local prof_var="${prefix}_PROFILE"
    local mode_var="${prefix}_SETUP_MODE"
    printf 'PROFILE=%s\n' "${!prof_var}"
    printf 'SETUP_MODE=%s\n' "${!mode_var}"

    local -n comp_map="${prefix}_COMPONENTS"
    # Sort keys for deterministic output
    local sorted_ids=()
    while IFS= read -r k; do
        [[ -n "$k" ]] && sorted_ids+=("$k")
    done < <(printf '%s\n' "${!comp_map[@]}" | sort)

    for id in "${sorted_ids[@]}"; do
        printf 'COMPONENT:%s=%s\n' "$id" "${comp_map[$id]}"
    done

    local -n def_map="${prefix}_ROLE_DEFAULTS"
    local sorted_roles=()
    while IFS= read -r k; do
        [[ -n "$k" ]] && sorted_roles+=("$k")
    done < <(printf '%s\n' "${!def_map[@]}" | sort)

    for role in "${sorted_roles[@]}"; do
        printf 'DEFAULT:%s=%s\n' "$role" "${def_map[$role]}"
    done
}

# Deserialize text into desired state
deserialize_desired_state() {
    local prefix="$1"
    local content="$2"

    local prof="workstation"
    local mode="recommended"

    # Extract PROFILE and SETUP_MODE first
    while IFS= read -r line; do
        if [[ "$line" =~ ^PROFILE=(.*)$ ]]; then
            prof="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^SETUP_MODE=(.*)$ ]]; then
            mode="${BASH_REMATCH[1]}"
        fi
    done <<< "$content"

    init_desired_state "$prefix" "$prof" "$mode" || return 1

    local -n comp_map="${prefix}_COMPONENTS"
    local -n def_map="${prefix}_ROLE_DEFAULTS"

    while IFS= read -r line; do
        if [[ "$line" =~ ^COMPONENT:([^=]+)=(.*)$ ]]; then
            comp_map["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^DEFAULT:([^=]+)=(.*)$ ]]; then
            def_map["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi
    done <<< "$content"

    return 0
}
