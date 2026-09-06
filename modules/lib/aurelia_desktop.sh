#!/usr/bin/env bash

# Aurelia desktop capability deployment.
#
# This module owns Aurelia user configuration, keybindings runtime provenance,
# provider selection, and the compatibility command deployment surface. It is
# sourced by modules/desktop.sh and deliberately has no top-level mutations.

deploy_aurelia_config() {
    local source="$SCRIPT_DIR/dotfiles/aurelia"
    local destination="$TARGET_HOME/.config/aurelia"

    if [[ -d "$source" ]]; then
        ensure_symlink "$source" "$destination"
        info "Aurelia configuration deployed."
    fi
}

# The Aurelia Keybindings deployment manifest is the runtime provenance
# authority.  Keep this list deliberately fixed: diagnostics and deployment
# must agree on the exact managed surface rather than guessing at arbitrary
# files in the QML tree.
aurelia_keybindings_manifest_files() {
    printf '%s\n' \
        "shell.qml" \
        "components/keybindings/KeybindingsWindow.qml" \
        "components/keybindings/KeybindingsHeader.qml" \
        "components/keybindings/KeybindingsActionList.qml" \
        "components/keybindings/KeybindingsExecutableForm.qml" \
        "components/keybindings/KeybindingsFooter.qml" \
        "components/keybindings/KeybindingsSettings.qml" \
        "components/keybindings/KeybindingsConfig.qml" \
        "components/keybindings/KeybindingsModel.qml" \
        "components/keybindings/KeybindingRow.qml" \
        "components/keybindings/qmldir" \
        "theme/Theme.qml"
}

aurelia_keybindings_backend_files() {
    printf '%s\n' \
        "lib/aurelia-keybindings/common.sh" \
        "lib/aurelia-keybindings/queries.sh" \
        "lib/aurelia-keybindings/actions.sh" \
        "lib/aurelia-keybindings/mutations.sh" \
        "lib/aurelia-keybindings/runtime.sh" \
        "lib/aurelia-keybindings/toggle.sh" \
        "lib/aurelia-keybindings/main.sh"
}

aurelia_keybindings_lib_target() {
    local bin_dir="${1:-${KEYBINDINGS_BIN_DIR:-${HOTKEYS_BIN_DIR:-/usr/local/bin}}}"
    local configured_target="${AURELIA_KEYBINDINGS_LIB_DIR:-}"

    if [[ -n "$configured_target" ]]; then
        printf '%s\n' "$configured_target"
    elif [[ "$bin_dir" == /usr/local/bin ]]; then
        printf '%s\n' "/usr/local/lib/aurelia-keybindings"
    else
        printf '%s\n' "$bin_dir/lib/aurelia-keybindings"
    fi
}

aurelia_keybindings_backend_root() {
    local bin_dir="${1:-${KEYBINDINGS_BIN_DIR:-${HOTKEYS_BIN_DIR:-/usr/local/bin}}}"
    local lib_target
    lib_target="$(aurelia_keybindings_lib_target "$bin_dir")" || return 1

    if [[ "$lib_target" == "$bin_dir/lib/aurelia-keybindings" ]]; then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    local parent_dir
    parent_dir="$(dirname -- "$bin_dir")"
    if [[ "$lib_target" == "$parent_dir/lib/aurelia-keybindings" ]]; then
        printf '%s\n' "$parent_dir"
        return 0
    fi

    return 1
}

aurelia_keybindings_manifest_path() {
    local manifest_path="${AURELIA_KEYBINDINGS_MANIFEST_PATH:-}"
    if [[ -z "$manifest_path" ]]; then
        local state_home="${XDG_STATE_HOME:-${TARGET_HOME:-$HOME}/.local/state}"
        manifest_path="$state_home/aurelia/keybindings/deployment-manifest.json"
    fi

    [[ "$manifest_path" == /* && "$manifest_path" != "/" ]] || return 1
    printf '%s\n' "$manifest_path"
}

aurelia_keybindings_sha256() {
    local path="$1"
    [[ -f "$path" ]] || return 1
    sha256sum "$path" | awk '{print $1}'
}

write_aurelia_keybindings_manifest() {
    local source_root="$SCRIPT_DIR/dotfiles/aurelia"
    local deployed_root="${TARGET_HOME:-$HOME}/.config/aurelia"
    local bin_dir="${KEYBINDINGS_BIN_DIR:-${HOTKEYS_BIN_DIR:-/usr/local/bin}}"
    local deployed_backend_root=""
    local source_backend="$SCRIPT_DIR/bin/aurelia-shell-keybindings"
    local deployed_backend="$bin_dir/aurelia-shell-keybindings"
    local manifest_path state_dir tmp_file

    manifest_path="$(aurelia_keybindings_manifest_path 2>/dev/null || true)"
    [[ -n "$manifest_path" ]] || return 1
    deployed_backend_root="$(aurelia_keybindings_backend_root "$bin_dir" 2>/dev/null || true)"
    [[ -n "$deployed_backend_root" ]] || return 1
    [[ -f "$source_backend" ]] || return 1
    [[ -f "$deployed_root/shell.qml" ]] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    local -a relative_files source_hashes deployed_hashes
    local -a backend_files source_backend_hashes deployed_backend_hashes
    mapfile -t relative_files < <(aurelia_keybindings_manifest_files)
    [[ "${#relative_files[@]}" -eq 12 ]] || return 1
    mapfile -t backend_files < <(aurelia_keybindings_backend_files)
    [[ "${#backend_files[@]}" -eq 7 ]] || return 1

    local relative_path source_hash deployed_hash
    for relative_path in "${relative_files[@]}"; do
        [[ -f "$source_root/$relative_path" ]] || return 1
        if ! source_hash="$(aurelia_keybindings_sha256 "$source_root/$relative_path")"; then
            return 1
        fi
        source_hashes+=("$source_hash")

        deployed_hash=""
        if [[ -f "$deployed_root/$relative_path" ]]; then
            if ! deployed_hash="$(aurelia_keybindings_sha256 "$deployed_root/$relative_path")"; then
                return 1
            fi
        fi
        deployed_hashes+=("$deployed_hash")
    done

    for relative_path in "${backend_files[@]}"; do
        [[ -f "$SCRIPT_DIR/bin/$relative_path" ]] || return 1
        if ! source_hash="$(aurelia_keybindings_sha256 "$SCRIPT_DIR/bin/$relative_path")"; then
            return 1
        fi
        source_backend_hashes+=("$source_hash")

        deployed_hash=""
        if [[ -f "$deployed_backend_root/$relative_path" ]]; then
            if ! deployed_hash="$(aurelia_keybindings_sha256 "$deployed_backend_root/$relative_path")"; then
                return 1
            fi
        fi
        deployed_backend_hashes+=("$deployed_hash")
    done

    local source_backend_hash deployed_backend_hash=""
    if ! source_backend_hash="$(aurelia_keybindings_sha256 "$source_backend")"; then
        return 1
    fi
    if [[ -f "$deployed_backend" ]]; then
        if ! deployed_backend_hash="$(aurelia_keybindings_sha256 "$deployed_backend")"; then
            return 1
        fi
    fi

    state_dir="$(dirname -- "$manifest_path")"
    if ! mkdir -p "$state_dir"; then
        return 1
    fi
    if [[ -L "$manifest_path" ]]; then
        warn "Refusing to replace symlinked generated manifest: $manifest_path"
        return 1
    fi
    tmp_file="$(mktemp "$state_dir/.deployment-manifest.XXXXXX" 2>/dev/null || true)"
    [[ -n "$tmp_file" ]] || return 1

    local generation_rc=0
    python3 - "$source_root" "$deployed_root" "$source_backend" "$deployed_backend" \
        "$source_backend_hash" "$deployed_backend_hash" \
        "${source_hashes[@]}" "${deployed_hashes[@]}" \
        "${source_backend_hashes[@]}" "${deployed_backend_hashes[@]}" > "$tmp_file" <<'PY_MANIFEST' || generation_rc=$?
import json
import sys

relative_files = (
    "shell.qml",
    "components/keybindings/KeybindingsWindow.qml",
    "components/keybindings/KeybindingsHeader.qml",
    "components/keybindings/KeybindingsActionList.qml",
    "components/keybindings/KeybindingsExecutableForm.qml",
    "components/keybindings/KeybindingsFooter.qml",
    "components/keybindings/KeybindingsSettings.qml",
    "components/keybindings/KeybindingsConfig.qml",
    "components/keybindings/KeybindingsModel.qml",
    "components/keybindings/KeybindingRow.qml",
    "components/keybindings/qmldir",
    "theme/Theme.qml",
)
backend_files = (
    "lib/aurelia-keybindings/common.sh",
    "lib/aurelia-keybindings/queries.sh",
    "lib/aurelia-keybindings/actions.sh",
    "lib/aurelia-keybindings/mutations.sh",
    "lib/aurelia-keybindings/runtime.sh",
    "lib/aurelia-keybindings/toggle.sh",
    "lib/aurelia-keybindings/main.sh",
)

source_root, deployed_root, source_backend, deployed_backend = sys.argv[1:5]
source_backend_hash, deployed_backend_hash = sys.argv[5:7]
source_hashes = sys.argv[7:19]
deployed_hashes = sys.argv[19:31]
source_backend_hashes = sys.argv[31:38]
deployed_backend_hashes = sys.argv[38:45]

expected_files = [
    {"path": relative_path, "sha256": digest}
    for relative_path, digest in zip(relative_files, source_hashes)
]
deployed_files = [
    {"path": relative_path, "sha256": digest or None}
    for relative_path, digest in zip(relative_files, deployed_hashes)
]
expected_backend_files = [
    {"path": relative_path, "sha256": digest}
    for relative_path, digest in zip(backend_files, source_backend_hashes)
]
deployed_backend_files = [
    {"path": relative_path, "sha256": digest or None}
    for relative_path, digest in zip(backend_files, deployed_backend_hashes)
]

deployed_by_path = {item["path"]: item["sha256"] for item in deployed_files}
mismatches = []
if source_backend_hash != deployed_backend_hash:
    mismatches.append(
        "backend: expected " + (source_backend_hash or "missing") +
        ", deployed " + (deployed_backend_hash or "missing")
    )
for expected in expected_files:
    relative_path = expected["path"]
    expected_hash = expected["sha256"]
    deployed_hash = deployed_by_path[relative_path]
    if expected_hash != deployed_hash:
        mismatches.append(
            "files/" + relative_path + ": expected " +
            (expected_hash or "missing") + ", deployed " +
            (deployed_hash or "missing")
        )
deployed_backend_by_path = {item["path"]: item["sha256"] for item in deployed_backend_files}
for expected in expected_backend_files:
    relative_path = expected["path"]
    expected_hash = expected["sha256"]
    deployed_hash = deployed_backend_by_path[relative_path]
    if expected_hash != deployed_hash:
        mismatches.append(
            "backend-files/" + relative_path + ": expected " +
            (expected_hash or "missing") + ", deployed " +
            (deployed_hash or "missing")
        )

manifest = {
    "schema": 1,
    "component": "aurelia-keybindings",
    "expected": {
        "qml_root": source_root,
        "backend_path": source_backend,
        "backend_sha256": source_backend_hash,
        "backend_files": expected_backend_files,
        "files": expected_files,
    },
    "deployed": {
        "qml_root": deployed_root,
        "backend_path": deployed_backend,
        "backend_sha256": deployed_backend_hash or None,
        "backend_files": deployed_backend_files,
        "files": deployed_files,
    },
    "mismatches": mismatches,
}
print(json.dumps(manifest, indent=2, sort_keys=True))
sys.exit(1 if mismatches else 0)
PY_MANIFEST

    if [[ "$generation_rc" -gt 1 ]]; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! mv -f "$tmp_file" "$manifest_path"; then
        rm -f "$tmp_file"
        return 1
    fi
    return "$generation_rc"
}

set_workstation_keybindings_provider() {
    local provider="$1"
    local dest_dir="${TARGET_HOME:-$HOME}/.config/workstation"
    local dest_file="$dest_dir/desktop.conf"

    if declare -F ensure_directory >/dev/null 2>&1; then
        ensure_directory "$dest_dir" 2>/dev/null || mkdir -p "$dest_dir"
    else
        mkdir -p "$dest_dir"
    fi

    # Write atomically via mktemp and mv
    local tmp_file
    tmp_file="$(mktemp "${dest_dir}/.tmp.desktop.conf.XXXXXX" 2>/dev/null || true)"
    if [[ -z "$tmp_file" ]]; then
        printf 'keybindings.provider = %s\nhotkeys.provider = %s\n' "$provider" "$provider" > "$dest_file"
        return 0
    fi

    if [[ -f "$dest_file" ]]; then
        grep -v -E '^[[:space:]]*(keybindings|hotkeys)[._]provider[[:space:]]*=' "$dest_file" > "$tmp_file" 2>/dev/null || true
    fi
    printf 'keybindings.provider = %s\nhotkeys.provider = %s\n' "$provider" "$provider" >> "$tmp_file"
    mv -f "$tmp_file" "$dest_file"
}

set_workstation_hotkeys_provider() {
    set_workstation_keybindings_provider "$@"
}

install_workstation_keybindings() {
    local bin_dir="${KEYBINDINGS_BIN_DIR:-${HOTKEYS_BIN_DIR:-/usr/local/bin}}"
    local apps_dir="${KEYBINDINGS_APPS_DIR:-${HOTKEYS_APPS_DIR:-/usr/local/share/applications}}"

    local canonical_bin_source="$SCRIPT_DIR/bin/aurelia-shell-keybindings"
    local keybindings_lib_source="$SCRIPT_DIR/bin/lib/aurelia-keybindings"
    local kb_bin_source="$SCRIPT_DIR/bin/workstation-keybindings"
    local hk_bin_source="$SCRIPT_DIR/bin/workstation-hotkeys"
    local cap_source="$SCRIPT_DIR/bin/workstation-hotkey-capture"
    local aur_bin_source="$SCRIPT_DIR/bin/workstation-aurelia"
    local canonical_desktop_source="$SCRIPT_DIR/config/desktop-entries/aurelia-shell-keybindings.desktop"
    local kb_desktop_source="$SCRIPT_DIR/config/desktop-entries/workstation-keybindings.desktop"
    local hk_desktop_source="$SCRIPT_DIR/config/desktop-entries/workstation-hotkeys.desktop"

    local canonical_bin_target="$bin_dir/aurelia-shell-keybindings"
    local keybindings_lib_target=""
    keybindings_lib_target="$(aurelia_keybindings_lib_target "$bin_dir")" || return 1
    local keybindings_backend_root=""
    keybindings_backend_root="$(aurelia_keybindings_backend_root "$bin_dir" 2>/dev/null || true)"
    if [[ -z "$keybindings_backend_root" ]]; then
        warn "Refusing unsupported Aurelia Keybindings module layout: $keybindings_lib_target"
        return 1
    fi
    local kb_bin_target="$bin_dir/workstation-keybindings"
    local hk_bin_target="$bin_dir/workstation-hotkeys"
    local cap_target="$bin_dir/workstation-hotkey-capture"
    local aur_bin_target="$bin_dir/workstation-aurelia"
    local canonical_desktop_target="$apps_dir/aurelia-shell-keybindings.desktop"
    local kb_desktop_target="$apps_dir/workstation-keybindings.desktop"
    local hk_desktop_target="$apps_dir/workstation-hotkeys.desktop"

    local is_privileged=0
    if [[ "$bin_dir" == /usr/* || "$bin_dir" == /etc/* || "$apps_dir" == /usr/* || "$apps_dir" == /etc/* ]]; then
        is_privileged=1
    fi
    if [[ "$keybindings_lib_target" == /usr/* || "$keybindings_lib_target" == /etc/* ]]; then
        is_privileged=1
    fi

    # Install the canonical command's owned runtime modules beside it. The
    # entrypoint deliberately does not embed unrelated responsibilities; a
    # partial module deployment must fail before the command is advertised as
    # usable.
    if [[ ! -f "$canonical_bin_source" || ! -d "$keybindings_lib_source" ]]; then
        warn "Aurelia Keybindings runtime modules are missing: $keybindings_lib_source"
        return 1
    fi
    if [[ "$keybindings_lib_target" != /* || "$keybindings_lib_target" == "/" ||
          -L "$keybindings_lib_target" ]]; then
        warn "Refusing unsafe Aurelia Keybindings module target: $keybindings_lib_target"
        return 1
    fi
    local -a backend_files=()
    mapfile -t backend_files < <(aurelia_keybindings_backend_files)
    [[ "${#backend_files[@]}" -eq 7 ]] || return 1
    local relative_path lib_source_file lib_target_file
    for relative_path in "${backend_files[@]}"; do
        lib_source_file="$SCRIPT_DIR/bin/$relative_path"
        [[ -f "$lib_source_file" ]] || {
            warn "Missing Aurelia Keybindings module: $lib_source_file"
            return 1
        }
        lib_target_file="$keybindings_lib_target/$(basename "$relative_path")"
        if [[ -L "$lib_target_file" ]]; then
            warn "Refusing to replace symlinked Aurelia Keybindings module: $lib_target_file"
            return 1
        fi
        if [[ "$is_privileged" -eq 1 ]]; then
            if ! sudo mkdir -p "$keybindings_lib_target" ||
               ! sudo cp "$lib_source_file" "$lib_target_file" ||
               ! sudo chmod 0644 "$lib_target_file"; then
                warn "Could not install Aurelia Keybindings module: $lib_target_file"
                return 1
            fi
        else
            if ! mkdir -p "$keybindings_lib_target" ||
               ! cp "$lib_source_file" "$lib_target_file" ||
               ! chmod 0644 "$lib_target_file"; then
                warn "Could not install Aurelia Keybindings module: $lib_target_file"
                return 1
            fi
        fi
    done

    # Install canonical aurelia-shell-keybindings executable
    if [[ -f "$canonical_bin_source" ]]; then
        info "Installing aurelia-shell-keybindings command to $canonical_bin_target."
        if [[ "$is_privileged" -eq 1 ]]; then
            sudo mkdir -p "$(dirname "$canonical_bin_target")"
            sudo cp "$canonical_bin_source" "$canonical_bin_target"
            sudo chmod 0755 "$canonical_bin_target"
        else
            mkdir -p "$(dirname "$canonical_bin_target")"
            cp "$canonical_bin_source" "$canonical_bin_target"
            chmod 0755 "$canonical_bin_target"
        fi
    fi

    # Install workstation-keybindings forwarding shim
    if [[ -f "$kb_bin_source" ]]; then
        info "Installing workstation-keybindings forwarding shim to $kb_bin_target."
        if [[ "$is_privileged" -eq 1 ]]; then
            sudo mkdir -p "$(dirname "$kb_bin_target")"
            sudo cp "$kb_bin_source" "$kb_bin_target"
            sudo chmod 0755 "$kb_bin_target"
        else
            mkdir -p "$(dirname "$kb_bin_target")"
            cp "$kb_bin_source" "$kb_bin_target"
            chmod 0755 "$kb_bin_target"
        fi
    fi

    # Install Aurelia Shell Core CLI executable
    if [[ -f "$aur_bin_source" ]]; then
        info "Installing workstation-aurelia command to $aur_bin_target."
        if [[ "$is_privileged" -eq 1 ]]; then
            sudo mkdir -p "$(dirname "$aur_bin_target")"
            sudo cp "$aur_bin_source" "$aur_bin_target"
            sudo chmod 0755 "$aur_bin_target"
        else
            mkdir -p "$(dirname "$aur_bin_target")"
            cp "$aur_bin_source" "$aur_bin_target"
            chmod 0755 "$aur_bin_target"
        fi
    fi

    # Install compatibility workstation-hotkeys wrapper
    if [[ -f "$hk_bin_source" ]]; then
        info "Installing workstation-hotkeys compatibility wrapper to $hk_bin_target."
        if [[ "$is_privileged" -eq 1 ]]; then
            sudo mkdir -p "$(dirname "$hk_bin_target")"
            sudo cp "$hk_bin_source" "$hk_bin_target"
            sudo chmod 0755 "$hk_bin_target"
        else
            mkdir -p "$(dirname "$hk_bin_target")"
            cp "$hk_bin_source" "$hk_bin_target"
            chmod 0755 "$hk_bin_target"
        fi
    fi

    # Install capture binary
    if [[ -f "$cap_source" ]]; then
        info "Installing workstation-hotkey-capture command to $cap_target."
        if [[ "$is_privileged" -eq 1 ]]; then
            sudo mkdir -p "$(dirname "$cap_target")"
            sudo cp "$cap_source" "$cap_target"
            sudo chmod 0755 "$cap_target"
        else
            mkdir -p "$(dirname "$cap_target")"
            cp "$cap_source" "$cap_target"
            chmod 0755 "$cap_target"
        fi
    fi

    # Install canonical aurelia-shell-keybindings desktop entry
    if [[ -f "$canonical_desktop_source" ]]; then
        info "Installing aurelia-shell-keybindings desktop entry to $canonical_desktop_target."
        if [[ "$is_privileged" -eq 1 ]]; then
            sudo mkdir -p "$(dirname "$canonical_desktop_target")"
            sudo cp "$canonical_desktop_source" "$canonical_desktop_target"
            sudo chmod 0644 "$canonical_desktop_target"
        else
            mkdir -p "$(dirname "$canonical_desktop_target")"
            cp "$canonical_desktop_source" "$canonical_desktop_target"
            chmod 0644 "$canonical_desktop_target"
        fi
    fi

    # Install compatibility workstation-keybindings desktop entry
    if [[ -f "$kb_desktop_source" ]]; then
        info "Installing workstation-keybindings desktop entry to $kb_desktop_target."
        if [[ "$is_privileged" -eq 1 ]]; then
            sudo mkdir -p "$(dirname "$kb_desktop_target")"
            sudo cp "$kb_desktop_source" "$kb_desktop_target"
            sudo chmod 0644 "$kb_desktop_target"
        else
            mkdir -p "$(dirname "$kb_desktop_target")"
            cp "$kb_desktop_source" "$kb_desktop_target"
            chmod 0644 "$kb_desktop_target"
        fi
    fi

    # Install compatibility workstation-hotkeys desktop entry
    if [[ -f "$hk_desktop_source" ]]; then
        info "Installing workstation-hotkeys compatibility desktop entry to $hk_desktop_target."
        if [[ "$is_privileged" -eq 1 ]]; then
            sudo mkdir -p "$(dirname "$hk_desktop_target")"
            sudo cp "$hk_desktop_source" "$hk_desktop_target"
            sudo chmod 0644 "$hk_desktop_target"
        else
            mkdir -p "$(dirname "$hk_desktop_target")"
            cp "$hk_desktop_source" "$hk_desktop_target"
            chmod 0644 "$hk_desktop_target"
        fi
    fi

    info "Workstation keybindings installed."
    if write_aurelia_keybindings_manifest; then
        info "Aurelia Keybindings deployment manifest verified."
        record_success "aurelia-keybindings-provenance"
    else
        if declare -F record_deferred >/dev/null 2>&1; then
            record_deferred \
                "desktop" \
                "aurelia-keybindings-provenance" \
                "Could not verify the generated Aurelia Keybindings deployment manifest."
        else
            warn "Could not verify the generated Aurelia Keybindings deployment manifest."
        fi
    fi
    record_success "aurelia-shell-keybindings"
    record_success "workstation-keybindings"
    record_success "workstation-aurelia"
    record_success "workstation-hotkeys"
}

install_workstation_hotkeys() {
    install_workstation_keybindings "$@"
}
