#!/usr/bin/env bash
# Aurelia Quickshell toggle lifecycle.
#
# This module owns only IPC dispatch and bounded cold-start readiness. It does
# not resolve keybinding data or mutate configuration.

toggle_aurelia() {
    if [[ "${AURELIA_SIMULATE_SUCCESS:-${HOTKEYS_SIMULATE_AURELIA_SUCCESS:-0}}" == "1" ]]; then
        printf '%s\n' "AURELIA_TOGGLE_OK"
        return 0
    fi

    if [[ "${AURELIA_SIMULATE_FAIL:-${HOTKEYS_SIMULATE_AURELIA_FAIL:-0}}" == "1" ]]; then
        log_event "ERROR" "Aurelia simulated failure; failing closed." "dispatch"
        printf '%s\n' "Error: Aurelia simulated failure." >&2
        return 1
    fi

    local qs_bin=""
    if ! qs_bin="$(resolve_quickshell_bin 2>/dev/null)"; then
        log_event "ERROR" "Quickshell runtime binary not found" "dispatch"
        notify_user critical "Keybindings Error" "Quickshell runtime binary not found."
        printf '%s\n' "Error: Quickshell runtime binary not found." >&2
        return 1
    fi

    # Production uses the managed user configuration. Test/development may
    # provide an explicit root so isolated tests never touch live state.
    local aurelia_shell=""
    if [[ ("${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1") &&
          -n "${AURELIA_QML_ROOT:-}" && -f "$AURELIA_QML_ROOT" ]]; then
        aurelia_shell="$AURELIA_QML_ROOT"
    else
        aurelia_shell="${XDG_CONFIG_HOME:-$HOME/.config}/aurelia/shell.qml"
    fi
    if [[ ! -f "$aurelia_shell" &&
          ("${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1") ]]; then
        aurelia_shell="$script_dir/../dotfiles/aurelia/shell.qml"
    fi
    if [[ ! -f "$aurelia_shell" ]]; then
        log_event "ERROR" "Aurelia configuration not found at '$aurelia_shell'" "dispatch"
        notify_user critical "Keybindings Error" "Aurelia configuration not found at '$aurelia_shell'."
        printf '%s\n' "Error: Aurelia configuration not found at '$aurelia_shell'." >&2
        return 1
    fi

    local t_warm_start
    t_warm_start="$(date +%s%3N 2>/dev/null || date +%s)"
    local ipc_ping_target="keybindings"
    local ping_out
    ping_out="$("$qs_bin" ipc --path "$aurelia_shell" call "$ipc_ping_target" ping 2>&1 || true)"
    if [[ "$ping_out" != *"true"* && "$ping_out" != *"pong"* ]]; then
        # Compatibility probe for an older resident shell during migration.
        local ping_hotk
        ping_hotk="$("$qs_bin" ipc --path "$aurelia_shell" call hotkeys ping 2>&1 || true)"
        if [[ "$ping_hotk" == *"true"* || "$ping_hotk" == *"pong"* ]]; then
            ipc_ping_target="hotkeys"
        else
            ipc_ping_target=""
        fi
    fi

    if [[ -n "$ipc_ping_target" ]]; then
        if "$qs_bin" ipc --path "$aurelia_shell" call "$ipc_ping_target" toggle >/dev/null 2>&1; then
            local t_warm_end dur
            t_warm_end="$(date +%s%3N 2>/dev/null || date +%s)"
            dur=$((t_warm_end - t_warm_start))
            log_event "PERF" "Aurelia warm toggle roundtrip: ${dur}ms" "toggle" "$dur"
            log_event "INFO" "Aurelia keybindings toggled successfully on warm instance." "toggle"
            return 0
        fi
        log_event "ERROR" "Aurelia toggle failed on warm instance" "toggle"
        notify_user critical "Keybindings Error" "Failed to toggle keybindings window."
        printf '%s\n' "Error: Aurelia toggle failed on warm instance." >&2
        return 1
    fi

    local t_cold_start
    t_cold_start="$(date +%s%3N 2>/dev/null || date +%s)"
    if ! QSG_INFO=1 "$qs_bin" --no-duplicate --daemonize --log-times -v --path "$aurelia_shell" >>"$AURELIA_LOG" 2>&1; then
        log_event "CRASH" "Aurelia process launch failed" "launch"
        notify_user critical "Keybindings Error" "Failed to launch Aurelia Quickshell process."
        printf '%s\n' "Error: Aurelia process launch failed." >&2
        return 1
    fi

    # Keep readiness bounded. The toggle is sent exactly once, after ping.
    local is_ready=0
    local ready_target="keybindings"
    local kb_out hk_out
    for _ in {1..40}; do
        kb_out="$("$qs_bin" ipc --path "$aurelia_shell" call keybindings ping 2>&1 || true)"
        if [[ "$kb_out" == *"true"* || "$kb_out" == *"pong"* ]]; then
            is_ready=1
            ready_target="keybindings"
            break
        fi
        hk_out="$("$qs_bin" ipc --path "$aurelia_shell" call hotkeys ping 2>&1 || true)"
        if [[ "$hk_out" == *"true"* || "$hk_out" == *"pong"* ]]; then
            is_ready=1
            ready_target="hotkeys"
            break
        fi
        sleep 0.05
    done

    if [[ "$is_ready" -ne 1 ]]; then
        log_event "CRASH" "Aurelia readiness timed out after ~2000ms" "launch" "2000"
        if [[ -f "$AURELIA_LOG" ]]; then
            local tail_diag
            tail_diag="$(tail -n 10 "$AURELIA_LOG" 2>/dev/null || true)"
            if [[ -n "$tail_diag" ]]; then
                log_event "CRASH_DIAGNOSTIC" "Recent Aurelia engine output: $tail_diag" "launch"
            fi
        fi
        notify_user critical "Keybindings Error" "Aurelia readiness timed out."
        printf '%s\n' "Error: Keybindings interface timed out waiting for Quickshell readiness." >&2
        return 1
    fi

    local t_cold_ready dur_ready
    t_cold_ready="$(date +%s%3N 2>/dev/null || date +%s)"
    dur_ready=$((t_cold_ready - t_cold_start))
    log_event "PERF" "Aurelia cold launch to ping readiness: ${dur_ready}ms" "launch" "$dur_ready"
    if "$qs_bin" ipc --path "$aurelia_shell" call "$ready_target" toggle >/dev/null 2>&1; then
        local t_cold_end dur_total
        t_cold_end="$(date +%s%3N 2>/dev/null || date +%s)"
        dur_total=$((t_cold_end - t_cold_start))
        log_event "PERF" "Aurelia cold toggle completed in ${dur_total}ms" "launch" "$dur_total"
        log_event "INFO" "Aurelia keybindings toggled successfully after cold readiness." "toggle"
        return 0
    fi

    log_event "ERROR" "Aurelia toggle failed after cold readiness" "toggle"
    notify_user critical "Keybindings Error" "Failed to toggle keybindings after startup."
    printf '%s\n' "Error: Failed to toggle keybindings after startup." >&2
    return 1
}
