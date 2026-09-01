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

installer_exit_code() {
    if [[ ${#INSTALL_LOGIN_FAILURES[@]} -gt 0 ]] ||
        [[ ${#INSTALL_REQUIRED_FAILURES[@]} -gt 0 ]]; then
        printf '1'
        return
    fi

    if [[ ${#INSTALL_DEFERRED[@]} -gt 0 ]]; then
        printf '2'
        return
    fi

    printf '0'
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
    local class="$1"
    local description="$2"
    local function_name="$3"
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

    if [[ "$class" == "abort" ]]; then
        "$function_name"
        if declare -F journal_stage >/dev/null; then
            journal_stage "$function_name" "done"
        fi
        return 0
    fi

    "$function_name" || rc=$?

    if (( rc == 0 )); then
        if declare -F journal_stage >/dev/null; then
            journal_stage "$function_name" "done"
        fi
        return 0
    fi

    if declare -F journal_stage >/dev/null; then
        journal_stage "$function_name" "failed:${rc}"
    fi

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
            record_required \
                "$function_name" \
                "stage" \
                "Stage exited ${rc} without classifying the failure."
            ;;
        optional)
            record_deferred \
                "$function_name" \
                "stage" \
                "Stage exited ${rc}."
            ;;
        *)
            die "Unknown installer step class: $class"
            ;;
    esac

    return 0
}
