#!/usr/bin/env bash

deploy_hyprland_config() {
local source="$SCRIPT_DIR/dotfiles/hypr"
local destination="$TARGET_HOME/.config/hypr"

```
[[ -d "$source" ]] || die "Hyprland configuration not found: $source"

ensure_symlink "$source" "$destination"

info "Hyprland configuration linked."
```

}

validate_noctalia() {
if ! is_true "${INSTALL_NOCTALIA:-false}"; then
info "Noctalia disabled by profile."
return 0
fi

```
if ! command_exists noctalia; then
    die "Noctalia is enabled by the profile but is not installed."
fi

info "Noctalia installation validated."
```

}

install_noctalia_greeter() {
if ! is_true "${INSTALL_GREETER:-false}"; then
info "Graphical greeter disabled by profile."
return 0
fi

```
info "Installing Noctalia greeter."

install_dnf_packages noctalia-greeter

command_exists noctalia-greeter-session ||
    die "noctalia-greeter-session was not found after installation."

info "Noctalia greeter installed."
```

}

configure_greetd() {
if ! is_true "${INSTALL_GREETER:-false}"; then
return 0
fi

```
local greeter_session
local greetd_config="/etc/greetd/config.toml"

greeter_session="$(command -v noctalia-greeter-session)"

[[ -n "$greeter_session" ]] ||
    die "Could not determine noctalia-greeter-session path."

info "Configuring greetd."

sudo install -d -m 0755 /etc/greetd

sudo tee "$greetd_config" >/dev/null <<EOF
```

[terminal]
vt = 1

[default_session]
command = "$greeter_session"
user = "greeter"
EOF

```
info "greetd configured."
```

}

enable_greetd() {
if ! is_true "${INSTALL_GREETER:-false}"; then
return 0
fi

```
info "Enabling greetd."

sudo systemctl enable greetd.service

info "greetd enabled."
```

}

enable_desktop_services() {
info "Enabling desktop services."

```
if systemctl list-unit-files NetworkManager.service \
    --no-legend 2>/dev/null | grep -q '^NetworkManager.service'; then
    sudo systemctl enable NetworkManager.service
fi

if systemctl list-unit-files power-profiles-daemon.service \
    --no-legend 2>/dev/null | grep -q '^power-profiles-daemon.service'; then
    sudo systemctl enable power-profiles-daemon.service
fi

if is_true "${BLUETOOTH:-false}"; then
    if systemctl list-unit-files bluetooth.service \
        --no-legend 2>/dev/null | grep -q '^bluetooth.service'; then
        sudo systemctl enable bluetooth.service
    else
        die "Bluetooth is enabled by the profile but bluetooth.service was not found."
    fi
fi

info "Desktop services configured."
```

}

configure_graphical_target() {
if ! is_true "${ENABLE_GRAPHICAL_TARGET:-false}"; then
info "Graphical target unchanged by profile."
return 0
fi

```
info "Setting graphical.target as the default system target."

sudo systemctl set-default graphical.target
```

}

validate_hyprland_desktop() {
local required_commands=(
Hyprland
hyprctl
kitty
thunar
hyprpolkitagent
)

```
local command_name

for command_name in "${required_commands[@]}"; do
    command_exists "$command_name" ||
        die "Required desktop command not found: $command_name"
done

[[ -f "$TARGET_HOME/.config/hypr/hyprland.lua" ]] ||
    die "Hyprland configuration was not deployed correctly."

info "Hyprland desktop validation complete."
```

}

install_desktop() {
if [[ "${DESKTOP:-}" != "hyprland" ]]; then
die "Unsupported desktop profile: ${DESKTOP:-<unset>}"
fi

```
info "Configuring Hyprland desktop."

deploy_hyprland_config
validate_noctalia

install_noctalia_greeter
configure_greetd
enable_greetd

enable_desktop_services
configure_graphical_target

validate_hyprland_desktop

info "Hyprland desktop configuration complete."
```

}
