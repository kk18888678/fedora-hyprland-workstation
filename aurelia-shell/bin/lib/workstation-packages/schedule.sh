#!/usr/bin/env bash

# User-level background catalog refresh. The timer refreshes metadata/catalog
# only; it never installs or upgrades packages. It starts after boot and the
# network-online target without making graphical login depend on the network.

wsp_schedule_dir() {
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    [[ "$config_home" == /* && "$config_home" != "/" ]] || return 1
    printf '%s/systemd/user\n' "$config_home"
}

wsp_schedule_service_path() {
    printf '%s/workstation-packages-refresh.service\n' "$(wsp_schedule_dir)"
}

wsp_schedule_timer_path() {
    printf '%s/workstation-packages-refresh.timer\n' "$(wsp_schedule_dir)"
}

wsp_daily_enable() {
    local service_path
    local timer_path
    local unit_dir
    local script_path
    local service_tmp
    local timer_tmp

    command -v systemctl >/dev/null || {
        wsp_error 'systemctl is required to enable background package catalog refresh.'
        return 1
    }
    unit_dir="$(wsp_schedule_dir)" || {
        wsp_error "XDG_CONFIG_HOME is unsafe; refusing to write the package refresh timer."
        return 1
    }
    service_path="$(wsp_schedule_service_path)"
    timer_path="$(wsp_schedule_timer_path)"
    script_path="$WSP_SCRIPT_PATH"
    [[ "$script_path" == /* && -x "$script_path" ]] || {
        wsp_error "Package manager executable is not an absolute executable path: $script_path"
        return 1
    }
    mkdir -p -- "$unit_dir" || return 1
    [[ ! -L "$unit_dir" ]] || {
        wsp_error "Refusing to write package refresh units through a symlinked directory: $unit_dir"
        return 1
    }
    [[ ! -L "$service_path" && ! -L "$timer_path" ]] || {
        wsp_error "Refusing to replace a symlinked package refresh unit."
        return 1
    }

    service_tmp="$(mktemp "$unit_dir/.workstation-packages-refresh.service.XXXXXX")" || return 1
    timer_tmp="$(mktemp "$unit_dir/.workstation-packages-refresh.timer.XXXXXX")" || {
        rm -f -- "$service_tmp"
        return 1
    }
    cat > "$service_tmp" <<EOF
[Unit]
Description=Refresh Fedora, Flatpak, and Aurelia package catalogs
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$script_path refresh --scheduled
EOF
cat > "$timer_tmp" <<EOF
[Unit]
Description=Background Fedora, Flatpak, and Aurelia package catalog refresh

[Timer]
OnBootSec=${WSP_CFG_CATALOG_BOOT_DELAY:-45s}
OnUnitActiveSec=${WSP_CFG_CATALOG_REFRESH_INTERVAL:-6h}
Persistent=true
RandomizedDelaySec=${WSP_CFG_CATALOG_REFRESH_JITTER:-5m}

[Install]
WantedBy=timers.target
EOF
    chmod 0644 -- "$service_tmp" "$timer_tmp"
    mv -f -- "$service_tmp" "$service_path"
    mv -f -- "$timer_tmp" "$timer_path"

    systemctl --user daemon-reload || return 1
    systemctl --user enable --now workstation-packages-refresh.timer || return 1
    wsp_info "Background package catalog refresh enabled."
}

wsp_daily_disable() {
    local service_path
    local timer_path

    command -v systemctl >/dev/null || {
        wsp_error 'systemctl is required to disable background package catalog refresh.'
        return 1
    }
    service_path="$(wsp_schedule_service_path)"
    timer_path="$(wsp_schedule_timer_path)"
    local unit_dir
    unit_dir="$(wsp_schedule_dir)" || return 1
    [[ ! -L "$unit_dir" ]] || {
        wsp_error "Refusing to remove package refresh units through a symlinked directory: $unit_dir"
        return 1
    }
    if ! systemctl --user disable --now workstation-packages-refresh.timer; then
        wsp_error 'Could not stop and disable the background package catalog refresh timer; unit files were preserved.'
        return 1
    fi
    if ! systemctl --user daemon-reload; then
        wsp_error 'Could not reload the user systemd manager after disabling package catalog refresh; unit files were preserved.'
        return 1
    fi
    [[ ! -L "$service_path" && ! -L "$timer_path" ]] || {
        wsp_error "Refusing to remove a symlinked package refresh unit."
        return 1
    }
    rm -f -- "$service_path" "$timer_path"
    wsp_info "Background package catalog refresh disabled."
}

wsp_daily_status() {
    local timer_state="disabled"
    local last_run="unknown"

    local enabled_state
    if command -v systemctl >/dev/null; then
        if enabled_state="$(systemctl --user is-enabled workstation-packages-refresh.timer)"; then
            timer_state="enabled"
        elif [[ -n "$enabled_state" && "$enabled_state" != disabled && "$enabled_state" != static && "$enabled_state" != masked ]]; then
            wsp_warn "Could not determine package catalog timer state: $enabled_state"
        fi
    fi
    if command -v systemctl >/dev/null; then
        if last_run="$(systemctl --user show workstation-packages-refresh.service \
            --property=ExecMainExitTimestamp --value)"; then
            :
        else
            wsp_warn 'Could not read the last background package catalog refresh time.'
            last_run='unknown'
        fi
    fi
    printf 'catalog_refresh=%s\nboot_delay=%s\nrefresh_interval=%s\nlast_run=%s\n' \
        "$timer_state" "${WSP_CFG_CATALOG_BOOT_DELAY:-45s}" \
        "${WSP_CFG_CATALOG_REFRESH_INTERVAL:-6h}" "${last_run:-unknown}"
}
