#!/usr/bin/env bash

# Installer outcome tracking.
#
# Git remains the desired-state source. These lists are a run journal
# for humans and for the final exit code.
#
# Exit codes:
#   0  all requested work succeeded
#   2  only optional/deferred work remains
#   1  one or more required components failed
#
# Exit code 1 does not by itself mean graphical activation was blocked.
# ACTIVATION_BLOCKED means only that the configured login stack is unsafe.

INSTALL_SUCCEEDED=()
INSTALL_DEFERRED=()
INSTALL_REQUIRED_FAILURES=()
INSTALL_LOGIN_FAILURES=()
ACTIVATION_BLOCKED=0
GRAPHICAL_ACTIVATION_STATE="not-attempted"
SUMMARY_PRINTED=0
CURRENT_STAGE="installer"

record_success() {
    local item="$1"

    INSTALL_SUCCEEDED+=("$item")
}

record_deferred() {
    local stage="$1"
    local operation="$2"
    local reason="$3"

    INSTALL_DEFERRED+=("${stage}: ${operation}: ${reason}")

    warn "DEFERRED [${stage}] ${operation}: ${reason}"
    warn "Rerunning the installer is safe."
}

# Required workstation capability. Does not block greetd/Hyprland activation.
record_required() {
    local stage="$1"
    local operation="$2"
    local reason="$3"

    INSTALL_REQUIRED_FAILURES+=("${stage}: ${operation}: ${reason}")

    error "REQUIRED [${stage}] ${operation}: ${reason}"
    error "This does not block graphical login activation."
    error "Rerunning the installer is safe after the cause is fixed."
}

# Unsafe to enable greetd / graphical.target.
record_activation_failure() {
    local stage="$1"
    local operation="$2"
    local reason="$3"

    INSTALL_LOGIN_FAILURES+=("${stage}: ${operation}: ${reason}")
    ACTIVATION_BLOCKED=1

    error "LOGIN-CRITICAL [${stage}] ${operation}: ${reason}"
    error "Graphical login will not be activated."
    error "Rerunning the installer is safe after the cause is fixed."
}

# Compatibility wrapper used by older call sites/tests.
record_critical() {
    local stage="$1"
    local operation="$2"
    local reason="$3"
    local block_activation="${4:-1}"

    if [[ "$block_activation" == "1" ]]; then
        record_activation_failure "$stage" "$operation" "$reason"
    else
        record_required "$stage" "$operation" "$reason"
    fi
}

# Preconditions and programming errors. These abort the process.
die() {
    record_activation_failure "${CURRENT_STAGE:-installer}" "fatal" "$*"
    error "$*"
    exit 1
}

resolve_installer_exit_code() {
    local _raw_code="${1:-0}"
    local _interrupted_sig="${2:-0}"
    local _out_var="${3:-}"

    local _resolved_status=0

    # 1. Explicitly trapped external signal has authoritative priority and retains conventional 128+signal exit status
    if (( _interrupted_sig != 0 )); then
        _resolved_status="$_interrupted_sig"
    elif (( _raw_code != 0 )); then
        # 2. If an unclassified nonzero error or unexpected fatal signal occurred (raw_code != 0),
        # it must NEVER silently resolve to 0 (success) or 2 (deferred-only).
        if [[ ${#INSTALL_LOGIN_FAILURES[@]} -eq 0 ]] && [[ ${#INSTALL_REQUIRED_FAILURES[@]} -eq 0 ]]; then
            record_activation_failure \
                "installer" \
                "exit" \
                "Installer terminated unexpectedly with status ${_raw_code}."
        fi
        _resolved_status=1
    elif [[ ${#INSTALL_LOGIN_FAILURES[@]} -gt 0 ]] ||
         [[ ${#INSTALL_REQUIRED_FAILURES[@]} -gt 0 ]]; then
        # 3. Classified required or login-critical failure
        _resolved_status=1
    elif [[ ${#INSTALL_DEFERRED[@]} -gt 0 ]]; then
        # 4. Deferred-only completion
        _resolved_status=2
    else
        # 5. Clean successful completion
        _resolved_status=0
    fi

    if [[ -n "$_out_var" ]]; then
        printf -v "$_out_var" '%s' "$_resolved_status"
    else
        printf '%s' "$_resolved_status"
    fi
}

installer_exit_code() {
    local code=0
    resolve_installer_exit_code 0 0 code
    printf '%s' "$code"
}

print_installer_summary() {
    local item
    local exit_code

    SUMMARY_PRINTED=1
    exit_code="$(installer_exit_code)"

    printf '\n'
    printf '============================================================\n'
    printf 'Installation summary\n'
    printf '============================================================\n'
    printf 'Profile : %s\n' "${PROFILE_NAME:-unknown}"
    printf 'User    : %s\n' "${TARGET_USER:-unknown}"
    printf '\n'

    printf 'Succeeded:\n'
    if [[ ${#INSTALL_SUCCEEDED[@]} -eq 0 ]]; then
        printf '  (none recorded)\n'
    else
        for item in "${INSTALL_SUCCEEDED[@]}"; do
            printf '  %s\n' "$item"
        done
    fi

    printf '\nDeferred optional:\n'
    if [[ ${#INSTALL_DEFERRED[@]} -eq 0 ]]; then
        printf '  (none)\n'
    else
        for item in "${INSTALL_DEFERRED[@]}"; do
            printf '  %s\n' "$item"
        done
    fi

    printf '\nFailed required (login still eligible):\n'
    if [[ ${#INSTALL_REQUIRED_FAILURES[@]} -eq 0 ]]; then
        printf '  (none)\n'
    else
        for item in "${INSTALL_REQUIRED_FAILURES[@]}"; do
            printf '  %s\n' "$item"
        done
    fi

    printf '\nFailed activation-critical:\n'
    if [[ ${#INSTALL_LOGIN_FAILURES[@]} -eq 0 ]]; then
        printf '  (none)\n'
    else
        for item in "${INSTALL_LOGIN_FAILURES[@]}"; do
            printf '  %s\n' "$item"
        done
    fi

    printf '\nGraphical activation: '
    case "${GRAPHICAL_ACTIVATION_STATE}" in
        completed)
            printf 'enabled for next boot\n'
            ;;
        skipped)
            printf 'SKIPPED (login stack unsafe)\n'
            ;;
        *)
            if (( ACTIVATION_BLOCKED != 0 )); then
                printf 'SKIPPED (login stack unsafe)\n'
            else
                printf 'not attempted\n'
            fi
            ;;
    esac

    printf '\n'

    case "$exit_code" in
        0)
            printf 'Installation completed successfully.\n'
            ;;
        2)
            printf 'Installation completed with deferred optional failures.\n'
            ;;
        *)
            printf 'Installation finished with required-component failures.\n'
            if (( ACTIVATION_BLOCKED != 0 )); then
                printf 'Graphical login was NOT activated.\n'
            else
                printf 'Graphical login stack was considered safe to activate.\n'
            fi
            ;;
    esac

    if [[ -n "${INSTALL_LOG_FILE:-}" ]]; then
        printf 'Log: %s\n' "$INSTALL_LOG_FILE"
    fi

    if [[ "${GRAPHICAL_ACTIVATION_STATE}" == "completed" ]] &&
        is_true "${ENABLE_GRAPHICAL_TARGET:-false}"; then
        printf '\nReboot when ready:\n'
        printf '    systemctl reboot\n'
    fi

    printf '\n'
}

# Catch unexpected non-zero from a stage without disabling set -e globally.
# login        -> unexpected failure blocks activation
# workstation  -> unexpected failure is required, activation still allowed
# optional     -> unexpected failure is deferred
# abort        -> let set -e abort (preconditions)
run_classified_step() {
    local class="${1:-}"
    local description="${2:-}"
    local function_name="${3:-}"
    local rc=0

    CURRENT_STAGE="$function_name"

    printf '\n'
    printf '==> %s\n' "$description"

    if declare -F journal_stage >/dev/null; then
        journal_stage "$function_name" "start"
    fi

    if ! declare -F "$function_name" >/dev/null; then
        die "Installer function not found: $function_name"
    fi

    if [[ $# -ge 3 ]]; then
        shift 3
    else
        shift "$#"
    fi

    if [[ "$class" == "abort" ]]; then
        "$function_name" "$@"
        if declare -F journal_stage >/dev/null; then
            journal_stage "$function_name" "done"
        fi
        return 0
    fi

    local prev_login_count="${#INSTALL_LOGIN_FAILURES[@]}"
    local prev_req_count="${#INSTALL_REQUIRED_FAILURES[@]}"
    local prev_def_count="${#INSTALL_DEFERRED[@]}"

    "$function_name" "$@" || rc=$?

    if (( rc == 0 )); then
        if declare -F journal_stage >/dev/null; then
            journal_stage "$function_name" "done"
        fi
        return 0
    fi

    if declare -F journal_stage >/dev/null; then
        journal_stage "$function_name" "failed:${rc}"
    fi

    local new_login_count="${#INSTALL_LOGIN_FAILURES[@]}"
    local new_req_count="${#INSTALL_REQUIRED_FAILURES[@]}"
    local new_def_count="${#INSTALL_DEFERRED[@]}"
    local new_classified=$(( (new_login_count - prev_login_count) + (new_req_count - prev_req_count) + (new_def_count - prev_def_count) ))

    case "$class" in
        login)
            if (( ACTIVATION_BLOCKED == 0 )); then
                record_activation_failure \
                    "$function_name" \
                    "stage" \
                    "Stage exited ${rc} without classifying the failure."
            fi
            ;;
        workstation)
            if (( new_classified == 0 )); then
                record_required \
                    "$function_name" \
                    "stage" \
                    "Stage exited ${rc} without classifying the failure."
            fi
            ;;
        optional)
            if (( new_classified == 0 )); then
                record_deferred \
                    "$function_name" \
                    "stage" \
                    "Stage exited ${rc}."
            fi
            ;;
        *)
            die "Unknown installer step class: $class"
            ;;
    esac

    return 0
}
