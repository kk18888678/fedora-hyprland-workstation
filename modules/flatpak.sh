#!/usr/bin/env bash

# Flatpak configuration for Fedora Hyprland Workstation.
#
# Responsibilities:
#   - Respect FLATPAK=true/false from the active profile.
#   - Install Flatpak through Fedora if required.
#   - Configure Flathub idempotently.
#   - Do not install arbitrary GUI applications here.
#
# Application selection should remain explicit and separate.

install_flatpak_package() {
    if package_installed flatpak; then
        info "Flatpak already installed."
        return 0
    fi

    info "Installing Flatpak."

    install_dnf_packages flatpak || return 1

    if ! command_exists flatpak; then
        return 1
    fi

    info "Flatpak installation validated."
}

detect_flatpak_package_group() {
    package_installed flatpak && command_exists flatpak
}

install_flatpak_package_group() {
    install_flatpak_package
}

read_flatpak_source_manifest() {
    local manifest="$SCRIPT_DIR/packages/sources.tsv"
    local line provider source url scope extra

    [[ -f "$manifest" && ! -L "$manifest" ]] || {
        error "Flatpak source manifest is missing or is a symlink: $manifest"
        return 1
    }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        provider=""
        source=""
        url=""
        scope=""
        extra=""
        IFS=$'\t' read -r provider source url scope extra <<< "$line"
        if [[ -n "$extra" || "$provider" != "flatpak" ||
              ! "$source" =~ ^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}$ ||
              ! "$url" =~ ^https://[^[:space:]]+$ ||
              ( "$scope" != "system" && "$scope" != "user" ) ]]; then
            error "Malformed Flatpak source row: $line"
            return 1
        fi
        printf '%s\t%s\t%s\n' "$source" "$url" "$scope"
    done < "$manifest"
}

validate_flatpak_source_manifest() {
    local rows_file
    local duplicate

    if ! rows_file="$(mktemp)"; then
        error "Could not create a secure temporary Flatpak source validation file."
        return 1
    fi
    if ! read_flatpak_source_manifest > "$rows_file"; then
        rm -f -- "$rows_file"
        return 1
    fi
    duplicate="$(cut -f1,3 "$rows_file" | sort | uniq -d)"
    if [[ -n "$duplicate" ]]; then
        error "Duplicate Flatpak source: $duplicate"
        rm -f -- "$rows_file"
        return 1
    fi
    rm -f -- "$rows_file"
}

flatpak_source_url_for() {
    local wanted_source="$1"
    local wanted_scope="$2"
    local source url scope
    local rows

    rows="$(read_flatpak_source_manifest)" || return 1
    while IFS=$'\t' read -r source url scope; do
        if [[ "$source" == "$wanted_source" && "$scope" == "$wanted_scope" ]]; then
            printf '%s\n' "$url"
            return 0
        fi
    done <<< "$rows"

    return 1
}

flatpak_source_configured() {
    local source="$1"
    local scope="$2"
    local expected_url="${3:-}"
    local expected_remote_url="$expected_url"
    local remote_rows

    # A .flatpakrepo file is a bootstrap descriptor.  After remote-add,
    # Flatpak stores the repository URL itself, normally with the descriptor
    # filename removed.
    if [[ "$expected_remote_url" == *.flatpakrepo ]]; then
        expected_remote_url="${expected_remote_url%/*}/"
    fi

    remote_rows="$(run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak remotes ($scope)" \
        flatpak remotes "--$scope" --columns=name,url,options 2>/dev/null)" ||
        return 1

    local actual_source actual_url options
    while IFS=$'\t' read -r actual_source actual_url options; do
        [[ "$actual_source" == "$source" ]] || continue

        if [[ -n "$expected_remote_url" && "$actual_url" != "$expected_remote_url" ]]; then
            return 1
        fi

        # Never accept a remote explicitly configured to skip content or
        # summary signature verification.
        if [[ "$options" == *no-gpg-verify* ||
              "$options" == *no-gpg-verify-summary* ]]; then
            return 1
        fi

        return 0
    done <<< "$remote_rows"

    return 1
}

configure_flatpak_sources() {
    local source url scope

    validate_flatpak_source_manifest || return 1
    while IFS=$'\t' read -r source url scope; do
        if flatpak_source_configured "$source" "$scope" "$url"; then
            info "Flatpak source already configured: $source ($scope)."
            continue
        fi

        info "Adding Flatpak source: $source ($scope)."
        if [[ "$scope" == system ]]; then
            run_with_retry "flatpak remote-add $source" \
                run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak remote-add $source" \
                sudo flatpak remote-add --system --if-not-exists "$source" "$url" ||
                return 1
        else
            run_with_retry "flatpak remote-add $source" \
                run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak remote-add $source" \
                flatpak remote-add --user --if-not-exists "$source" "$url" ||
                return 1
        fi

        flatpak_source_configured "$source" "$scope" "$url" || return 1
    done < <(read_flatpak_source_manifest)
}

flathub_configured() {
    local url
    url="$(flatpak_source_url_for flathub system 2>/dev/null || true)"
    [[ -n "$url" ]] && flatpak_source_configured flathub system "$url"
}

configure_flathub() {
    configure_flatpak_sources
}

configure_flatpak() {
    if ! is_true "${FLATPAK:-false}"; then
        info "Flatpak disabled by profile."
        return 0
    fi

    info "Configuring Flatpak."

    if is_component_migrated "packages.flatpak"; then
        info "Flatpak package group is owned by configuration reconciler; skipping legacy stage."
    elif ! install_flatpak_package; then
        record_required "flatpak" "install" "Flatpak package could not be installed."
        return 1
    fi

    if ! configure_flathub; then
        record_required "flatpak" "flathub" "Flathub remote could not be configured."
        return 1
    fi

    info "Flatpak configuration complete."
    record_success "flatpak"
    return 0
}

install_localsend() {
    if ! is_true "${LOCALSEND:-false}"; then
        info "LocalSend disabled by profile."
        return 0
    fi

    if ! is_true "${FLATPAK:-false}"; then
        record_deferred \
            "flatpak" \
            "localsend" \
            "LocalSend requires Flatpak, but Flatpak is disabled by profile."
        return 0
    fi

    if ! command_exists flatpak; then
        record_deferred \
            "flatpak" \
            "localsend" \
            "Flatpak command is unavailable."
        return 0
    fi

    local installed_apps
    if ! installed_apps="$(run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak list (LocalSend)" \
        flatpak list --app --columns=application 2>/dev/null)"; then
        record_deferred "flatpak" "localsend" "Flatpak application inventory query timed out or failed."
        return 0
    fi

    if grep -Fxq "org.localsend.localsend_app" <<< "$installed_apps"; then
        info "LocalSend Flatpak already installed."
        record_success "localsend"
        return 0
    fi

    info "Installing LocalSend from Flathub."

    if ! run_with_retry "flatpak install localsend" \
        run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak install localsend" \
        flatpak install -y flathub org.localsend.localsend_app; then
        record_deferred \
            "flatpak" \
            "localsend" \
            "LocalSend Flatpak could not be installed."
        return 0
    fi

    if ! installed_apps="$(run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak list (LocalSend validation)" \
        flatpak list --app --columns=application 2>/dev/null)" ||
        ! grep -Fxq "org.localsend.localsend_app" <<< "$installed_apps"; then
        record_deferred "flatpak" "localsend" "LocalSend Flatpak was not present after installation."
        return 0
    fi

    info "LocalSend installation validated."
    record_success "localsend"
}

install_ulaa() {
    if ! is_true "${BROWSER_ULAA:-false}"; then
        info "Ulaa disabled by profile."
        return 0
    fi

    if ! is_true "${FLATPAK:-false}"; then
        record_deferred \
            "flatpak" \
            "ulaa" \
            "Ulaa requires Flatpak, but Flatpak is disabled by profile."
        return 0
    fi

    if ! command_exists flatpak; then
        record_deferred \
            "flatpak" \
            "ulaa" \
            "Flatpak command is unavailable."
        return 0
    fi

    local installed_apps
    if ! installed_apps="$(run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak list (Ulaa)" \
        flatpak list --app --columns=application 2>/dev/null)"; then
        record_deferred "flatpak" "ulaa" "Flatpak application inventory query timed out or failed."
        return 0
    fi

    if grep -Fxq "com.ulaa.Ulaa" <<< "$installed_apps"; then
        info "Ulaa Flatpak already installed."
        record_success "ulaa"
        return 0
    fi

    info "Installing Ulaa browser from Flathub."

    if ! run_with_retry "flatpak install ulaa" \
        run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak install ulaa" \
        flatpak install -y flathub com.ulaa.Ulaa; then
        record_deferred \
            "flatpak" \
            "ulaa" \
            "Ulaa Flatpak could not be installed."
        return 0
    fi

    if ! installed_apps="$(run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak list (Ulaa validation)" \
        flatpak list --app --columns=application 2>/dev/null)" ||
        ! grep -Fxq "com.ulaa.Ulaa" <<< "$installed_apps"; then
        record_deferred \
            "flatpak" \
            "ulaa" \
            "Ulaa Flatpak was not present after installation."
        return 0
    fi

    info "Ulaa Flatpak installation validated."
    record_success "ulaa"
}

install_user_managed_flatpak_applications() {
    local rows
    local provider
    local source
    local identifier
    local scope
    local profiles
    local failed=0
    local installed_apps=""

    validate_user_managed_manifest || {
        record_deferred "flatpak" "user-managed-manifest" "The user-managed package manifest is invalid."
        return 0
    }
    if ! rows="$(read_user_managed_manifest)"; then
        record_deferred "flatpak" "user-managed-manifest" "The user-managed package manifest could not be read."
        return 0
    fi
    while IFS=$'\t' read -r provider source identifier scope profiles; do
        [[ "$provider" == flatpak ]] || continue
        if ! installed_apps="$(run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak list ($identifier)" \
            flatpak list --app "--$scope" --columns=application 2>/dev/null)"; then
            record_deferred "flatpak" "$identifier" "Flatpak application inventory query timed out or failed."
            failed=1
            continue
        fi
        if grep -Fxq "$identifier" <<< "$installed_apps"; then
            info "Tracked Flatpak already installed: $identifier ($scope)."
            continue
        fi
        local expected_url
        expected_url="$(flatpak_source_url_for "$source" "$scope" 2>/dev/null || true)"
        if [[ -z "$expected_url" ]] ||
            ! flatpak_source_configured "$source" "$scope" "$expected_url"; then
            record_deferred "flatpak" "$identifier" "Tracked Flatpak source is not configured: $source ($scope)."
            failed=1
            continue
        fi

        info "Installing tracked Flatpak $identifier from $source ($scope)."
        if [[ "$scope" == system ]]; then
            if ! run_with_retry "flatpak install $identifier" \
                run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak install $identifier" \
                sudo flatpak install -y --system "$source" "$identifier"; then
                record_deferred "flatpak" "$identifier" "Tracked Flatpak installation failed."
                failed=1
                continue
            fi
        else
            if ! run_with_retry "flatpak install $identifier" \
                run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak install $identifier" \
                flatpak install -y --user "$source" "$identifier"; then
                record_deferred "flatpak" "$identifier" "Tracked Flatpak installation failed."
                failed=1
                continue
            fi
        fi

        if ! installed_apps="$(run_with_timeout "$TIMEOUT_FLATPAK_SECONDS" "flatpak list ($identifier validation)" \
            flatpak list --app "--$scope" --columns=application 2>/dev/null)" ||
            ! grep -Fxq "$identifier" <<< "$installed_apps"; then
            record_deferred "flatpak" "$identifier" "Tracked Flatpak was not present after installation."
            failed=1
        else
            info "Tracked Flatpak installation validated: $identifier."
        fi
    done <<< "$rows"

    (( failed == 0 )) || return 0
    return 0
}

install_flatpak_applications() {
    if ! is_true "${FLATPAK:-false}"; then
        info "Flatpak applications disabled (FLATPAK=false)."
        return 0
    fi

    info "Installing Flatpak applications."

    install_localsend
    install_ulaa
    install_user_managed_flatpak_applications

    info "Flatpak application installation complete."
}
