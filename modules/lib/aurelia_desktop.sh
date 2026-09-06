#!/usr/bin/env bash

# Aurelia desktop capability deployment.
#
# This module owns Aurelia user configuration, keybindings runtime provenance,
# provider selection, and the compatibility command deployment surface. It is
# sourced by modules/desktop.sh and deliberately has no top-level mutations.

deploy_aurelia_config() {
    local source="$SCRIPT_DIR/aurelia-shell"
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
        "services/PluginRegistry.qml" \
        "services/PluginHost.qml" \
        "services/ShellConfig.qml" \
        "services/qmldir" \
        "plugins/aurelia.keybindings/manifest.json" \
        "plugins/aurelia.keybindings/KeybindingsPlugin.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsAddActionPicker.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsActionTypeRow.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingRow.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsActionList.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsConfig.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsExecutableForm.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsFooter.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsHeader.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsModel.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsSettings.qml" \
        "plugins/aurelia.keybindings/ui/KeybindingsWindow.qml" \
        "plugins/aurelia.keybindings/ui/qmldir" \
        "theme/Theme.qml" \
        "theme/qmldir" \
        "theme.conf" \
        "core/preferences.lua"
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

aurelia_plugin_lib_target() {
    local bin_dir="${1:-${KEYBINDINGS_BIN_DIR:-${HOTKEYS_BIN_DIR:-/usr/local/bin}}}"
    local configured_target="${AURELIA_PLUGIN_LIB_DIR:-}"

    if [[ -n "$configured_target" ]]; then
        printf '%s\n' "$configured_target"
    elif [[ "$bin_dir" == /usr/local/bin ]]; then
        printf '%s\n' "/usr/local/lib/aurelia-plugin"
    else
        printf '%s\n' "$bin_dir/lib/aurelia-plugin"
    fi
}

aurelia_plugin_backend_root() {
    local bin_dir="${1:-${KEYBINDINGS_BIN_DIR:-${HOTKEYS_BIN_DIR:-/usr/local/bin}}}"
    local lib_target
    lib_target="$(aurelia_plugin_lib_target "$bin_dir")" || return 1
    if [[ "$lib_target" == "$bin_dir/lib/aurelia-plugin" ]]; then
        printf '%s\n' "$bin_dir"
        return 0
    fi
    local parent_dir
    parent_dir="$(dirname -- "$bin_dir")"
    if [[ "$lib_target" == "$parent_dir/lib/aurelia-plugin" ]]; then
        printf '%s\n' "$parent_dir"
        return 0
    fi
    return 1
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

aurelia_shell_host_manifest_path() {
    local state_home="${XDG_STATE_HOME:-${TARGET_HOME:-$HOME}/.local/state}"
    local manifest_path="$state_home/aurelia/shell/host-manifest.json"
    [[ "$manifest_path" == /* && "$manifest_path" != "/" ]] || return 1
    printf '%s\n' "$manifest_path"
}

write_aurelia_shell_host_manifest() {
    local source_root="$SCRIPT_DIR/bin"
    local bin_dir="${KEYBINDINGS_BIN_DIR:-${HOTKEYS_BIN_DIR:-/usr/local/bin}}"
    local plugin_root=""
    plugin_root="$(aurelia_plugin_backend_root "$bin_dir" 2>/dev/null || true)"
    [[ -n "$plugin_root" ]] || return 1
    local manifest_path state_dir tmp_file
    manifest_path="$(aurelia_shell_host_manifest_path 2>/dev/null || true)"
    [[ -n "$manifest_path" ]] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    local -a host_files plugin_files
    host_files=("aurelia-shell" "aurelia-launch-shell" "aurelia-plugin")
    plugin_files=("lib/aurelia-plugin/common.sh" "lib/aurelia-plugin/manifest.sh" "lib/aurelia-plugin/main.sh")
    local -a source_hashes deployed_hashes source_plugin_hashes deployed_plugin_hashes
    local relative_path source_hash deployed_hash
    for relative_path in "${host_files[@]}"; do
        source_hash="$(aurelia_keybindings_sha256 "$source_root/$relative_path")" || return 1
        source_hashes+=("$source_hash")
        deployed_hash=""
        [[ -f "$bin_dir/$relative_path" ]] && deployed_hash="$(aurelia_keybindings_sha256 "$bin_dir/$relative_path")" || true
        deployed_hashes+=("$deployed_hash")
    done
    for relative_path in "${plugin_files[@]}"; do
        source_hash="$(aurelia_keybindings_sha256 "$source_root/$relative_path")" || return 1
        source_plugin_hashes+=("$source_hash")
        deployed_hash=""
        [[ -f "$plugin_root/$relative_path" ]] && deployed_hash="$(aurelia_keybindings_sha256 "$plugin_root/$relative_path")" || true
        deployed_plugin_hashes+=("$deployed_hash")
    done

    state_dir="$(dirname -- "$manifest_path")"
    mkdir -p "$state_dir" || return 1
    [[ ! -L "$manifest_path" ]] || return 1
    tmp_file="$(mktemp "$state_dir/.host-manifest.XXXXXX" 2>/dev/null || true)"
    [[ -n "$tmp_file" ]] || return 1
    python3 - "$source_root" "$bin_dir" "$plugin_root" \
        "${source_hashes[@]}" "${deployed_hashes[@]}" \
        "${source_plugin_hashes[@]}" "${deployed_plugin_hashes[@]}" > "$tmp_file" <<'PY_HOST_MANIFEST'
import json
import sys

host_files = ("aurelia-shell", "aurelia-launch-shell", "aurelia-plugin")
plugin_files = ("lib/aurelia-plugin/common.sh", "lib/aurelia-plugin/manifest.sh", "lib/aurelia-plugin/main.sh")
source_root, deployed_root, plugin_root = sys.argv[1:4]
source_hashes = sys.argv[4:7]
deployed_hashes = sys.argv[7:10]
source_plugin_hashes = sys.argv[10:13]
deployed_plugin_hashes = sys.argv[13:16]
expected = [{"path": p, "sha256": h} for p, h in zip(host_files, source_hashes)]
deployed = [{"path": p, "sha256": h or None} for p, h in zip(host_files, deployed_hashes)]
expected_plugins = [{"path": p, "sha256": h} for p, h in zip(plugin_files, source_plugin_hashes)]
deployed_plugins = [{"path": p, "sha256": h or None} for p, h in zip(plugin_files, deployed_plugin_hashes)]
mismatches = []
for group, expected_items, deployed_items in (("host", expected, deployed), ("plugin", expected_plugins, deployed_plugins)):
    deployed_by_path = {item["path"]: item["sha256"] for item in deployed_items}
    for item in expected_items:
        if item["sha256"] != deployed_by_path.get(item["path"]):
            mismatches.append(group + "/" + item["path"])
print(json.dumps({
    "schema": 1,
    "component": "aurelia-shell",
    "expected": {"root": source_root, "host_files": expected, "plugin_files": expected_plugins},
    "deployed": {"root": deployed_root, "plugin_root": plugin_root, "host_files": deployed, "plugin_files": deployed_plugins},
    "mismatches": mismatches,
}, indent=2, sort_keys=True))
PY_HOST_MANIFEST
    mv -f "$tmp_file" "$manifest_path" || { rm -f "$tmp_file"; return 1; }
}

write_aurelia_keybindings_manifest() {
    local source_root="$SCRIPT_DIR/aurelia-shell"
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
    [[ "${#relative_files[@]}" -eq 23 ]] || return 1
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
    "services/PluginRegistry.qml",
    "services/PluginHost.qml",
    "services/ShellConfig.qml",
    "services/qmldir",
    "plugins/aurelia.keybindings/manifest.json",
    "plugins/aurelia.keybindings/KeybindingsPlugin.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsAddActionPicker.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsActionTypeRow.qml",
    "plugins/aurelia.keybindings/ui/KeybindingRow.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsActionList.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsConfig.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsExecutableForm.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsFooter.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsHeader.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsModel.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsSettings.qml",
    "plugins/aurelia.keybindings/ui/KeybindingsWindow.qml",
    "plugins/aurelia.keybindings/ui/qmldir",
    "theme/Theme.qml",
    "theme/qmldir",
    "theme.conf",
    "core/preferences.lua",
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
source_hashes = sys.argv[7:30]
deployed_hashes = sys.argv[30:53]
source_backend_hashes = sys.argv[53:60]
deployed_backend_hashes = sys.argv[60:67]

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

aurelia_install_file() {
    local source="$1"
    local target="$2"
    local mode="$3"
    local privileged="$4"

    [[ -f "$source" ]] || return 1
    [[ "$target" == /* && "$target" != "/" && ! -L "$target" && (! -e "$target" || -f "$target") ]] || {
        warn "Refusing unsafe Aurelia managed file target: $target"
        return 1
    }
    if [[ "$privileged" -eq 1 ]]; then
        sudo mkdir -p "$(dirname -- "$target")" || return 1
        sudo cp "$source" "$target" || return 1
        sudo chmod "$mode" "$target" || return 1
    else
        mkdir -p "$(dirname -- "$target")" || return 1
        cp "$source" "$target" || return 1
        chmod "$mode" "$target" || return 1
    fi
}

install_workstation_keybindings() {
    local bin_dir="${KEYBINDINGS_BIN_DIR:-${HOTKEYS_BIN_DIR:-/usr/local/bin}}"
    local apps_dir="${KEYBINDINGS_APPS_DIR:-${HOTKEYS_APPS_DIR:-/usr/local/share/applications}}"

    local canonical_bin_source="$SCRIPT_DIR/bin/aurelia-shell-keybindings"
    local keybindings_lib_source="$SCRIPT_DIR/bin/lib/aurelia-keybindings"
    local kb_bin_source="$SCRIPT_DIR/bin/workstation-keybindings"
    local hk_bin_source="$SCRIPT_DIR/bin/workstation-hotkeys"
    local cap_source="$SCRIPT_DIR/bin/workstation-hotkey-capture"
    local shell_ipc_source="$SCRIPT_DIR/bin/aurelia-shell"
    local shell_launcher_source="$SCRIPT_DIR/bin/aurelia-launch-shell"
    local plugin_cli_source="$SCRIPT_DIR/bin/aurelia-plugin"
    local plugin_lib_source="$SCRIPT_DIR/bin/lib/aurelia-plugin"
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
    local shell_ipc_target="$bin_dir/aurelia-shell"
    local shell_launcher_target="$bin_dir/aurelia-launch-shell"
    local plugin_cli_target="$bin_dir/aurelia-plugin"
    local plugin_lib_target=""
    plugin_lib_target="$(aurelia_plugin_lib_target "$bin_dir")" || return 1
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
    if [[ "$plugin_lib_target" == /usr/* || "$plugin_lib_target" == /etc/* ]]; then
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
    if [[ ! -f "$shell_ipc_source" || ! -f "$shell_launcher_source" ]]; then
        warn "Aurelia Shell host commands are missing: $shell_ipc_source"
        return 1
    fi
    if [[ ! -f "$plugin_cli_source" || ! -d "$plugin_lib_source" ]]; then
        warn "Aurelia plugin management modules are missing: $plugin_lib_source"
        return 1
    fi
    if [[ "$keybindings_lib_target" != /* || "$keybindings_lib_target" == "/" ||
          -L "$keybindings_lib_target" ]]; then
        warn "Refusing unsafe Aurelia Keybindings module target: $keybindings_lib_target"
        return 1
    fi
    if [[ "$plugin_lib_target" != /* || "$plugin_lib_target" == "/" ||
          -L "$plugin_lib_target" ]]; then
        warn "Refusing unsafe Aurelia plugin module target: $plugin_lib_target"
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
        if ! aurelia_install_file "$lib_source_file" "$lib_target_file" 0644 "$is_privileged"; then
            warn "Could not install Aurelia Keybindings module: $lib_target_file"
            return 1
        fi
    done

    local -a plugin_files=()
    mapfile -t plugin_files < <(find "$plugin_lib_source" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | LC_ALL=C sort)
    [[ "${#plugin_files[@]}" -eq 3 ]] || return 1
    local plugin_file
    for plugin_file in "${plugin_files[@]}"; do
        lib_target_file="$plugin_lib_target/$plugin_file"
        if ! aurelia_install_file "$plugin_lib_source/$plugin_file" "$lib_target_file" 0644 "$is_privileged"; then
            warn "Could not install Aurelia plugin module: $lib_target_file"
            return 1
        fi
    done

    # Install canonical aurelia-shell-keybindings executable
    if [[ -f "$canonical_bin_source" ]]; then
        info "Installing aurelia-shell-keybindings command to $canonical_bin_target."
        aurelia_install_file "$canonical_bin_source" "$canonical_bin_target" 0755 "$is_privileged" || return 1
    fi

    # Install the resident-host IPC client and session launcher. The IPC
    # client never starts Quickshell; the launcher is the single autostart
    # owner used by Hyprland.
    info "Installing Aurelia Shell host commands to $bin_dir."
    aurelia_install_file "$shell_ipc_source" "$shell_ipc_target" 0755 "$is_privileged" || return 1
    aurelia_install_file "$shell_launcher_source" "$shell_launcher_target" 0755 "$is_privileged" || return 1

    info "Installing aurelia-plugin management command to $plugin_cli_target."
    aurelia_install_file "$plugin_cli_source" "$plugin_cli_target" 0755 "$is_privileged" || return 1

    # Install workstation-keybindings forwarding shim
    if [[ -f "$kb_bin_source" ]]; then
        info "Installing workstation-keybindings forwarding shim to $kb_bin_target."
        aurelia_install_file "$kb_bin_source" "$kb_bin_target" 0755 "$is_privileged" || return 1
    fi

    # Install Aurelia Shell Core CLI executable
    if [[ -f "$aur_bin_source" ]]; then
        info "Installing workstation-aurelia command to $aur_bin_target."
        aurelia_install_file "$aur_bin_source" "$aur_bin_target" 0755 "$is_privileged" || return 1
    fi

    # Install compatibility workstation-hotkeys wrapper
    if [[ -f "$hk_bin_source" ]]; then
        info "Installing workstation-hotkeys compatibility wrapper to $hk_bin_target."
        aurelia_install_file "$hk_bin_source" "$hk_bin_target" 0755 "$is_privileged" || return 1
    fi

    # Install capture binary
    if [[ -f "$cap_source" ]]; then
        info "Installing workstation-hotkey-capture command to $cap_target."
        aurelia_install_file "$cap_source" "$cap_target" 0755 "$is_privileged" || return 1
    fi

    # Install canonical aurelia-shell-keybindings desktop entry
    if [[ -f "$canonical_desktop_source" ]]; then
        info "Installing aurelia-shell-keybindings desktop entry to $canonical_desktop_target."
        aurelia_install_file "$canonical_desktop_source" "$canonical_desktop_target" 0644 "$is_privileged" || return 1
    fi

    # Install compatibility workstation-keybindings desktop entry
    if [[ -f "$kb_desktop_source" ]]; then
        info "Installing workstation-keybindings desktop entry to $kb_desktop_target."
        aurelia_install_file "$kb_desktop_source" "$kb_desktop_target" 0644 "$is_privileged" || return 1
    fi

    # Install compatibility workstation-hotkeys desktop entry
    if [[ -f "$hk_desktop_source" ]]; then
        info "Installing workstation-hotkeys compatibility desktop entry to $hk_desktop_target."
        aurelia_install_file "$hk_desktop_source" "$hk_desktop_target" 0644 "$is_privileged" || return 1
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
    if write_aurelia_shell_host_manifest; then
        info "Aurelia Shell host deployment manifest verified."
        record_success "aurelia-shell-provenance"
    else
        if declare -F record_deferred >/dev/null 2>&1; then
            record_deferred \
                "desktop" \
                "aurelia-shell-provenance" \
                "Could not verify the generated Aurelia Shell host deployment manifest."
        else
            warn "Could not verify the generated Aurelia Shell host deployment manifest."
        fi
    fi
    record_success "aurelia-shell-keybindings"
    record_success "aurelia-shell"
    record_success "aurelia-launch-shell"
    record_success "aurelia-plugin"
    record_success "workstation-keybindings"
    record_success "workstation-aurelia"
    record_success "workstation-hotkeys"
}

install_workstation_hotkeys() {
    install_workstation_keybindings "$@"
}
