#!/usr/bin/env bash

# Configuration Reconciler for Fedora Hyprland Workstation.
#
# Consumes an already validated Plan and executes component lifecycle actions.
#
# Invariants:
# - Reconciler executes an already validated Plan; it does not decide policy.
# - remove != purge: removal never deletes user personal data, documents, or dotfiles.
# - Lifecycle actions are executed via declarative callbacks, never arbitrary eval.
# - Failure classification follows repository status semantics.

# Set system default application for a role
set_system_role_default() {
    local role="$1"
    local comp_id="$2"

    case "$role" in
        browser)
            if command_exists xdg-mime; then
                local desktop_file=""
                case "$comp_id" in
                    chromium) desktop_file="chromium-browser.desktop" ;;
                    firefox)  desktop_file="firefox.desktop" ;;
                    *)        desktop_file="${comp_id}.desktop" ;;
                esac

                if [[ -n "$desktop_file" ]]; then
                    xdg-mime default "$desktop_file" x-scheme-handler/http 2>/dev/null || true
                    xdg-mime default "$desktop_file" x-scheme-handler/https 2>/dev/null || true
                    xdg-mime default "$desktop_file" text/html 2>/dev/null || true
                fi
            fi
            ;;
        *)
            # Future role adapters
            ;;
    esac
}

# Execute an action via its callback or a mock runner
_reconciler_invoke() {
    local fn_name="$1"
    local comp_id="$2"
    local action_type="$3"

    if [[ -z "$fn_name" ]]; then
        return 0
    fi

    # Support test mock executor injection
    if [[ -n "${RECONCILER_MOCK_EXECUTOR:-}" ]] && type "$RECONCILER_MOCK_EXECUTOR" >/dev/null 2>&1; then
        "$RECONCILER_MOCK_EXECUTOR" "$comp_id" "$action_type" "$fn_name"
        return $?
    fi

    if type "$fn_name" >/dev/null 2>&1; then
        "$fn_name"
        return $?
    else
        printf 'ERROR: Lifecycle callback function not found: %s\n' "$fn_name" >&2
        return 1
    fi
}

# Execute a validated Plan
# Arguments:
#   plan_prefix: name of plan structure
#   out_results_var (optional): name of variable to store execution status
execute_plan() {
    local plan_prefix="$1"
    local out_results_var="${2:-}"

    local -n actions_list="${plan_prefix}_ACTIONS"
    local -n type_map="${plan_prefix}_ACTION_TYPE"
    local -n target_map="${plan_prefix}_ACTION_TARGET"
    local -n reason_map="${plan_prefix}_ACTION_REASON"
    local -n details_map="${plan_prefix}_ACTION_DETAILS"

    local total_actions="${#actions_list[@]}"
    if [[ "$total_actions" -eq 0 ]]; then
        info "Configuration plan has no actions to reconcile."
        return 0
    fi

    local had_failure=0

    # 1. Execute REMOVE actions first
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "REMOVE" ]]; then
            local comp_id="${target_map[$idx]}"
            local rem_fn
            rem_fn="$(get_component_attr "$comp_id" remove_fn)"

            info "Reconciling REMOVE: $comp_id (${details_map[$idx]})"
            if ! _reconciler_invoke "$rem_fn" "$comp_id" "REMOVE"; then
                warn "Failed to remove component: $comp_id"
                had_failure=1
            fi
        fi
    done

    # 2. Execute INSTALL actions
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "INSTALL" ]]; then
            local comp_id="${target_map[$idx]}"
            local inst_fn
            inst_fn="$(get_component_attr "$comp_id" install_fn)"
            local cfg_fn
            cfg_fn="$(get_component_attr "$comp_id" configure_fn)"
            local val_fn
            val_fn="$(get_component_attr "$comp_id" validate_fn)"

            info "Reconciling INSTALL: $comp_id (${details_map[$idx]})"
            if ! _reconciler_invoke "$inst_fn" "$comp_id" "INSTALL"; then
                local is_req
                is_req="$(get_component_attr "$comp_id" required)"
                if [[ "$is_req" == "true" ]]; then
                    if type record_required >/dev/null 2>&1; then
                        record_required "components" "$comp_id" "Required component installation failed: $comp_id"
                    fi
                else
                    if type record_deferred >/dev/null 2>&1; then
                        record_deferred "components" "$comp_id" "Optional component installation failed: $comp_id"
                    fi
                fi
                had_failure=1
                continue
            fi

            # Run configure callback if present
            if [[ -n "$cfg_fn" ]]; then
                _reconciler_invoke "$cfg_fn" "$comp_id" "CONFIGURE" || true
            fi

            # Run validate callback if present
            if [[ -n "$val_fn" ]]; then
                if ! _reconciler_invoke "$val_fn" "$comp_id" "VALIDATE"; then
                    warn "Validation failed for component: $comp_id"
                    had_failure=1
                fi
            fi
        fi
    done

    # 3. Execute CONFIGURE actions
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "CONFIGURE" ]]; then
            local comp_id="${target_map[$idx]}"
            local cfg_fn
            cfg_fn="$(get_component_attr "$comp_id" configure_fn)"

            info "Reconciling CONFIGURE: $comp_id (${details_map[$idx]})"
            _reconciler_invoke "$cfg_fn" "$comp_id" "CONFIGURE" || true
        fi
    done

    # 4. Execute CHANGE_DEFAULT actions
    for idx in "${actions_list[@]}"; do
        if [[ "${type_map[$idx]}" == "CHANGE_DEFAULT" ]]; then
            local comp_id="${target_map[$idx]}"
            local details="${details_map[$idx]}"
            # details format: "role: old -> new"
            local role="${details%%:*}"

            info "Reconciling CHANGE_DEFAULT: $role -> $comp_id"
            set_system_role_default "$role" "$comp_id"
        fi
    done

    if [[ -n "$out_results_var" ]]; then
        printf -v "$out_results_var" '%d' "$had_failure"
    fi

    return "$had_failure"
}
