#!/usr/bin/env bash

# Interactive Setup Mode and Wizard for Fedora Hyprland Workstation.
#
# Provides terminal UI navigation for Setup Mode selection, Component Customization,
# Default Role preferences, and Plan Review.
#
# Invariants:
# - UI navigation does NOT mutate system or component state.
# - Key handlers only mutate in-memory desired state data.
# - Non-interactive executions fail closed with clear diagnostic, avoiding hangs.
# - Deselection in customization never implies removal (unmanaged != remove).
# - Removal is explicit, with separate confirmation required before Apply.
# - Cancellation before Apply results in zero mutations.

# Check if an interactive terminal is available
wizard_is_interactive() {
    # If a test mock input source is active, treat as interactive
    if [[ -n "${WIZARD_MOCK_INPUT:-}" ]]; then
        return 0
    fi

    # Standard input MUST be an interactive terminal
    if [[ ! -t 0 ]]; then
        return 1
    fi

    # Standard output or /dev/tty must be a writable terminal device
    if [[ -t 1 ]] || { [[ -c /dev/tty ]] && [[ -w /dev/tty ]]; }; then
        return 0
    fi

    return 1
}

# Read a single keypress or escape sequence safely
_wizard_read_key() {
    local -n out_key="$1"
    local raw=""

    if [[ -n "${WIZARD_MOCK_INPUT:-}" ]]; then
        # Read next key from mock queue
        if [[ -n "$WIZARD_MOCK_KEYS" ]]; then
            out_key="${WIZARD_MOCK_KEYS%% *}"
            if [[ "$WIZARD_MOCK_KEYS" == *" "* ]]; then
                WIZARD_MOCK_KEYS="${WIZARD_MOCK_KEYS#* }"
            else
                WIZARD_MOCK_KEYS=""
            fi
            return 0
        else
            out_key="QUIT"
            return 0
        fi
    fi

    local tty_in="/dev/tty"
    if [[ ! -c "$tty_in" || ! -r "$tty_in" ]]; then
        tty_in="/dev/stdin"
    fi

    # Read 1 byte with 0.1s timeout for escape sequences
    IFS= read -r -s -n 1 raw < "$tty_in" || { out_key="QUIT"; return 1; }

    if [[ "$raw" == $'\x1b' ]]; then
        local rest=""
        # Read next characters if available
        IFS= read -r -s -n 2 -t 0.1 rest < "$tty_in" || true
        case "$rest" in
            "[A") out_key="UP" ;;
            "[B") out_key="DOWN" ;;
            "[C") out_key="RIGHT" ;;
            "[D") out_key="LEFT" ;;
            *)    out_key="ESC" ;;
        esac
    elif [[ -z "$raw" ]]; then
        out_key="ENTER"
    elif [[ "$raw" == " " ]]; then
        out_key="SPACE"
    elif [[ "$raw" == "k" || "$raw" == "K" ]]; then
        out_key="UP"
    elif [[ "$raw" == "j" || "$raw" == "J" ]]; then
        out_key="DOWN"
    elif [[ "$raw" == "q" || "$raw" == "Q" ]]; then
        out_key="QUIT"
    elif [[ "$raw" == "r" || "$raw" == "R" || "$raw" == "d" || "$raw" == "D" ]]; then
        out_key="REMOVE"
    elif [[ "$raw" == "a" || "$raw" == "A" ]]; then
        out_key="APPLY"
    elif [[ "$raw" == "e" || "$raw" == "E" ]]; then
        out_key="EDIT"
    elif [[ "$raw" == "c" || "$raw" == "C" ]]; then
        out_key="CANCEL"
    else
        out_key="$raw"
    fi

    return 0
}

# Render and handle Setup Mode selection screen
wizard_select_setup_mode() {
    local profile="$1"
    local -n out_mode="$2"

    local selected=0
    local key=""

    while true; do
        printf '\n'
        printf '============================================================\n'
        printf 'Fedora Hyprland Workstation Setup (%s profile)\n' "$profile"
        printf '============================================================\n\n'
        printf 'Please select a setup mode:\n\n'

        if [[ "$selected" -eq 0 ]]; then
            printf '  (*) Recommended Workstation\n'
            printf '      Our complete opinionated configuration\n\n'
            printf '  ( ) Customize Workstation\n'
            printf '      Choose applications, tools and preferences\n\n'
        else
            printf '  ( ) Recommended Workstation\n'
            printf '      Our complete opinionated configuration\n\n'
            printf '  (*) Customize Workstation\n'
            printf '      Choose applications, tools and preferences\n\n'
        fi

        printf 'Controls: [Up/Down or j/k] Navigate  [Enter] Select  [q] Cancel\n'

        _wizard_read_key key

        case "$key" in
            UP|DOWN)
                selected=$(( 1 - selected ))
                ;;
            ENTER)
                if [[ "$selected" -eq 0 ]]; then
                    out_mode="recommended"
                else
                    out_mode="customize"
                fi
                return 0
                ;;
            QUIT|ESC)
                printf '\nSetup mode selection cancelled.\n'
                return 2
                ;;
        esac
    done
}

# Render and handle customization of components by category
wizard_customize() {
    local profile="$1"
    local ds_prefix="$2"

    local categories=()
    while IFS= read -r c; do
        [[ -n "$c" ]] && categories+=("$c")
    done < <(list_component_categories)

    local cat_idx=0
    local total_cats="${#categories[@]}"

    while [[ "$cat_idx" -lt "$total_cats" ]]; do
        local cur_cat="${categories[$cat_idx]}"
        local comp_ids=()
        while IFS= read -r cid; do
            if component_supports_profile "$cid" "$profile"; then
                comp_ids+=("$cid")
            fi
        done < <(list_components_by_category "$cur_cat")

        local cur_item=0
        local total_items="${#comp_ids[@]}"

        local key=""
        local leave_cat=0

        while [[ "$leave_cat" -eq 0 ]]; do
            printf '\n'
            printf '============================================================\n'
            printf 'Customize: %s (Category %d of %d)\n' "$cur_cat" "$(( cat_idx + 1 ))" "$total_cats"
            printf '============================================================\n\n'

            if [[ "$total_items" -eq 0 ]]; then
                printf '  (No components available for this profile in this category)\n\n'
            else
                for i in $(seq 0 $(( total_items - 1 ))); do
                    local cid="${comp_ids[$i]}"
                    local name
                    name="$(get_component_attr "$cid" display_name)"
                    local desc
                    desc="$(get_component_attr "$cid" description)"
                    local is_req
                    is_req="$(get_component_attr "$cid" required)"
                    local is_rem
                    is_rem="$(get_component_attr "$cid" removable)"
                    local st
                    st="$(desired_state_get_component "$ds_prefix" "$cid")"

                    local marker=" "
                    if [[ "$st" == "managed" ]]; then
                        marker="X"
                    elif [[ "$st" == "remove" ]]; then
                        marker="R"
                    fi

                    local prefix="  "
                    [[ "$i" -eq "$cur_item" ]] && prefix="> "

                    local req_note=""
                    [[ "$is_req" == "true" ]] && req_note=" [REQUIRED]"

                    printf '%s[%s] %-20s - %s%s\n' "$prefix" "$marker" "$name" "$desc" "$req_note"
                done
                printf '\n'
            fi

            printf 'Controls: [Up/Down] Navigate  [Space] Toggle Select/Unmanage  [r/d] Mark Remove\n'
            printf '          [Enter] Next Category  [Esc] Prev Category  [q] Cancel\n'

            _wizard_read_key key

            case "$key" in
                UP)
                    if [[ "$total_items" -gt 0 ]]; then
                        cur_item=$(( (cur_item - 1 + total_items) % total_items ))
                    fi
                    ;;
                DOWN)
                    if [[ "$total_items" -gt 0 ]]; then
                        cur_item=$(( (cur_item + 1) % total_items ))
                    fi
                    ;;
                SPACE)
                    if [[ "$total_items" -gt 0 ]]; then
                        local cid="${comp_ids[$cur_item]}"
                        local is_req
                        is_req="$(get_component_attr "$cid" required)"
                        if [[ "$is_req" == "true" ]]; then
                            # Required components cannot be unmanaged
                            continue
                        fi
                        local st
                        st="$(desired_state_get_component "$ds_prefix" "$cid")"
                        if [[ "$st" == "managed" ]]; then
                            desired_state_set_component "$ds_prefix" "$cid" "unmanaged"
                        else
                            desired_state_set_component "$ds_prefix" "$cid" "managed"
                        fi
                    fi
                    ;;
                REMOVE)
                    if [[ "$total_items" -gt 0 ]]; then
                        local cid="${comp_ids[$cur_item]}"
                        local is_req
                        is_req="$(get_component_attr "$cid" required)"
                        local is_rem
                        is_rem="$(get_component_attr "$cid" removable)"
                        if [[ "$is_req" != "true" && "$is_rem" == "true" ]]; then
                            local st
                            st="$(desired_state_get_component "$ds_prefix" "$cid")"
                            if [[ "$st" == "remove" ]]; then
                                desired_state_set_component "$ds_prefix" "$cid" "unmanaged"
                            else
                                desired_state_set_component "$ds_prefix" "$cid" "remove"
                            fi
                        fi
                    fi
                    ;;
                ENTER)
                    leave_cat=1
                    cat_idx=$(( cat_idx + 1 ))
                    ;;
                ESC)
                    leave_cat=1
                    if [[ "$cat_idx" -gt 0 ]]; then
                        cat_idx=$(( cat_idx - 1 ))
                    else
                        return 2
                    fi
                    ;;
                QUIT)
                    return 2
                    ;;
            esac
        done
    done

    return 0
}

# Configure default roles if multiple providers are selected
wizard_configure_defaults() {
    local profile="$1"
    local ds_prefix="$2"

    for role in "${SUPPORTED_ROLES[@]}"; do
        local managed_providers=()
        for p in $(get_role_providers "$role" "$profile"); do
            local st
            st="$(desired_state_get_component "$ds_prefix" "$p")"
            if [[ "$st" == "managed" ]]; then
                managed_providers+=("$p")
            fi
        done

        if [[ "${#managed_providers[@]}" -gt 1 ]]; then
            local cur_def
            cur_def="$(desired_state_get_default "$ds_prefix" "$role")"
            local sel=0
            for i in $(seq 0 $(( ${#managed_providers[@]} - 1 ))); do
                if [[ "${managed_providers[$i]}" == "$cur_def" ]]; then
                    sel="$i"
                    break
                fi
            done

            local key=""
            local done_role=0
            while [[ "$done_role" -eq 0 ]]; do
                printf '\n'
                printf '============================================================\n'
                printf 'Choose Default Application for: %s\n' "$role"
                printf '============================================================\n\n'

                for i in $(seq 0 $(( ${#managed_providers[@]} - 1 ))); do
                    local pid="${managed_providers[$i]}"
                    local pname
                    pname="$(get_component_attr "$pid" display_name)"
                    local mark="( )"
                    [[ "$i" -eq "$sel" ]] && mark="(*)"
                    printf '  %s %s\n' "$mark" "$pname"
                done
                printf '\nControls: [Up/Down] Choose  [Enter] Confirm  [q] Cancel\n'

                _wizard_read_key key
                case "$key" in
                    UP)
                        sel=$(( (sel - 1 + ${#managed_providers[@]}) % ${#managed_providers[@]} ))
                        ;;
                    DOWN)
                        sel=$(( (sel + 1) % ${#managed_providers[@]} ))
                        ;;
                    ENTER)
                        desired_state_set_default "$ds_prefix" "$role" "${managed_providers[$sel]}"
                        done_role=1
                        ;;
                    QUIT|ESC)
                        return 2
                        ;;
                esac
            done
        elif [[ "${#managed_providers[@]}" -eq 1 ]]; then
            desired_state_set_default "$ds_prefix" "$role" "${managed_providers[0]}"
        fi
    done

    return 0
}

# Review Plan screen
wizard_review_plan() {
    local plan_prefix="$1"
    local -n out_action="$2"

    format_plan_summary "$plan_prefix"

    local c_rem="${plan_prefix}_COUNT_REMOVE"
    local has_removals=0
    [[ "${!c_rem}" -gt 0 ]] && has_removals=1

    printf '\nOptions:\n'
    printf '  [A] Apply changes\n'
    printf '  [E] Edit selections (return to customization)\n'
    printf '  [C] Cancel setup (no changes will be made)\n\n'

    local key=""
    while true; do
        printf 'Select option [a/e/c]: '
        _wizard_read_key key
        printf '\n'

        case "$key" in
            APPLY|a|A)
                if [[ "$has_removals" -eq 1 ]]; then
                    printf '\n'
                    printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
                    printf 'WARNING: The configuration plan includes DESTRUCTIVE REMOVALS.\n'
                    printf 'Confirm component removal? (Type "yes" to proceed): '
                    local confirm=""
                    if [[ -n "${WIZARD_MOCK_INPUT:-}" ]]; then
                        confirm="${WIZARD_MOCK_CONFIRM:-yes}"
                    else
                        read -r confirm
                    fi
                    if [[ "$confirm" != "yes" ]]; then
                        printf 'Removal not confirmed. Returning to review options.\n\n'
                        continue
                    fi
                fi
                out_action="APPLY"
                return 0
                ;;
            EDIT|e|E)
                out_action="EDIT"
                return 0
                ;;
            CANCEL|QUIT|ESC|c|C)
                out_action="CANCEL"
                return 0
                ;;
        esac
    done
}

# Top-level setup mode orchestration
# Arguments:
#   profile: workstation | vm
#   out_plan_prefix: name of variable prefix for produced Plan
run_setup_mode() {
    local profile="$1"
    local plan_prefix="$2"

    # Production execution strictly requires an interactive terminal (stdin must be a terminal).
    # Non-interactive executions without test mock input must fail closed safely before mutation.
    if ! wizard_is_interactive; then
        printf 'ERROR: Interactive terminal required for setup mode selection. Run in an interactive terminal.\n' >&2
        return 1
    fi

    local mode=""
    if [[ -n "${SETUP_MODE:-}" ]]; then
        if [[ "$SETUP_MODE" != "recommended" && "$SETUP_MODE" != "customize" ]]; then
            printf 'ERROR: Invalid SETUP_MODE value: %s (must be "recommended" or "customize")\n' "$SETUP_MODE" >&2
            return 1
        fi
        mode="$SETUP_MODE"
    else
        wizard_select_setup_mode "$profile" mode || return 2
    fi

    local ds_prefix="RUN_DS"

    while true; do
        if [[ "$mode" == "recommended" ]]; then
            create_recommended_desired_state "$ds_prefix" "$profile" || return 1
        elif [[ "$mode" == "customize" ]]; then
            create_recommended_desired_state "$ds_prefix" "$profile" || return 1
            declare -g "${ds_prefix}_SETUP_MODE"="customize"
            wizard_customize "$profile" "$ds_prefix" || return 2
            wizard_configure_defaults "$profile" "$ds_prefix" || return 2
        else
            printf 'ERROR: Unsupported setup mode: %s\n' "$mode" >&2
            return 1
        fi

        create_execution_plan "$ds_prefix" "$plan_prefix" || return 1

        # Interactive Review is mandatory for ALL setup modes before Apply.
        # There is no non-interactive auto-apply bypass in production.
        local user_action=""
        wizard_review_plan "$plan_prefix" user_action || return 2

        case "$user_action" in
            APPLY)
                return 0
                ;;
            EDIT)
                mode="customize"
                continue
                ;;
            CANCEL)
                info "Setup cancelled by user. No changes were applied."
                return 2
                ;;
        esac
    done
}
