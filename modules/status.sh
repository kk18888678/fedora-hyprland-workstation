#!/usr/bin/env bash

# Installer outcome tracking.
#
# Git remains the desired-state source. These lists are only a run
# journal for humans and for the final exit code.
#
# Exit codes:
#   0  all requested work succeeded
#   2  completed, but optional work was deferred
#   1  critical failure (login activation is skipped when blocked)

INSTALL_SUCCEEDED=()
INSTALL_DEFERRED=()
INSTALL_CRITICAL=()
ACTIVATION_BLOCKED=0
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

record_critical() {
    local stage="$1"
    local operation="$2"
    local reason="$3"
    local block_activation="${4:-1}"

    INSTALL_CRITICAL+=("${stage}: ${operation}: ${reason}")

    if [[ "$block_activation" == "1" ]]; then
        ACTIVATION_BLOCKED=1
    fi

    error "CRITICAL [${stage}] ${operation}: ${reason}"
    error "Rerunning the installer is safe after the cause is fixed."
}

# Fatal programming / activation-blocking failure.
die() {
    record_critical "${CURRENT_STAGE:-installer}" "fatal" "$*" 1
    error "$*"
    exit 1
}

installer_exit_code() {
    if [[ ${#INSTALL_CRITICAL[@]} -gt 0 ]]; then
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

    printf '\nDeferred:\n'
    if [[ ${#INSTALL_DEFERRED[@]} -eq 0 ]]; then
        printf '  (none)\n'
    else
        for item in "${INSTALL_DEFERRED[@]}"; do
            printf '  %s\n' "$item"
        done
    fi

    printf '\nFailed critical:\n'
    if [[ ${#INSTALL_CRITICAL[@]} -eq 0 ]]; then
        printf '  (none)\n'
    else
        for item in "${INSTALL_CRITICAL[@]}"; do
            printf '  %s\n' "$item"
        done
    fi

    printf '\n'

    case "$exit_code" in
        0)
            printf 'Installation completed successfully.\n'
            ;;
        2)
            printf 'Installation completed with deferred optional failures.\n'
            ;;
        *)
            printf 'Installation finished with critical failures.\n'
            if (( ACTIVATION_BLOCKED != 0 )); then
                printf 'Graphical login was NOT activated.\n'
            fi
            ;;
    esac

    if [[ -n "${INSTALL_LOG_FILE:-}" ]]; then
        printf 'Log: %s\n' "$INSTALL_LOG_FILE"
    fi

    if [[ "$exit_code" != "1" ]] && is_true "${ENABLE_GRAPHICAL_TARGET:-false}"; then
        printf '\nReboot when ready:\n'
        printf '    systemctl reboot\n'
    fi

    printf '\n'
}
