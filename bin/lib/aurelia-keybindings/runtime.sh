resolve_aurelia_bin() {
    if [[ "${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1" ]] &&
       [[ -n "${WORKSTATION_AURELIA_BIN:-}" ]]; then
        if [[ -x "$WORKSTATION_AURELIA_BIN" ]]; then
            printf '%s\n' "$WORKSTATION_AURELIA_BIN"
            return 0
        fi
        return 1
    fi
    if [[ "${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1" ]] &&
       [[ -x "$script_dir/workstation-aurelia" ]]; then
        printf '%s\n' "$script_dir/workstation-aurelia"
        return 0
    fi
    if [[ -x "/usr/local/bin/workstation-aurelia" ]]; then
        printf '%s\n' "/usr/local/bin/workstation-aurelia"
        return 0
    fi
    return 1
}

find_quickshell_runtime() {
    local current_uid="${UID:-$(id -u)}"
    local expected_root="${1:-}"
    local line pid comm args process_root

    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -n "$line" ]] || continue
        pid="${line%%[[:space:]]*}"
        args="${line#"$pid"}"
        args="${args#"${args%%[![:space:]]*}"}"
        comm="${args%%[[:space:]]*}"
        args="${args#"$comm"}"
        args="${args#"${args%%[![:space:]]*}"}"
        comm="${comm##*/}"
        [[ -n "$pid" && "$pid" != "$$" ]] || continue
        [[ "$comm" == "qs" || "$comm" == "quickshell" ]] || continue
        [[ "$args" == *shell.qml* ]] || continue
        if [[ "$args" =~ --path[[:space:]]+([^[:space:]]+) ]]; then
            process_root="${BASH_REMATCH[1]}"
            if [[ -d "$process_root" && -f "$process_root/shell.qml" ]]; then
                process_root="$process_root/shell.qml"
            fi
            if [[ -n "$expected_root" && "$process_root" != "$expected_root" ]]; then
                continue
            fi
            printf '%s\t%s\n' "$pid" "$args"
            return 0
        fi
    done < <(ps -u "$current_uid" -o pid=,args= 2>/dev/null || true)

    return 1
}

runtime_manifest_path() {
    if [[ "${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1" ]] &&
       [[ -n "${AURELIA_KEYBINDINGS_MANIFEST_PATH:-}" ]]; then
        printf '%s\n' "$AURELIA_KEYBINDINGS_MANIFEST_PATH"
    else
        printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/aurelia/keybindings/deployment-manifest.json"
    fi
}

runtime_backend_path() {
    if [[ "${AURELIA_DEVELOPMENT_MODE:-0}" == "1" && -n "${AURELIA_SHELL_KEYBINDINGS_BIN:-}" && -x "$AURELIA_SHELL_KEYBINDINGS_BIN" ]]; then
        printf '%s\n' "$AURELIA_SHELL_KEYBINDINGS_BIN"
    elif [[ -x "/usr/local/bin/aurelia-shell-keybindings" ]]; then
        printf '%s\n' "/usr/local/bin/aurelia-shell-keybindings"
    elif [[ -x "/usr/local/bin/workstation-keybindings" ]]; then
        # Existing installations may predate the canonical command. Keep
        # diagnostics useful during the bounded migration window.
        printf '%s\n' "/usr/local/bin/workstation-keybindings"
    else
        printf '%s\n' "/usr/local/bin/aurelia-shell-keybindings"
    fi
}

diagnostic_backend_identity_path() {
    if [[ ("${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1") &&
          -n "${AURELIA_SHELL_KEYBINDINGS_BIN:-}" ]]; then
        printf '%s\n' "$AURELIA_SHELL_KEYBINDINGS_BIN"
    else
        printf '%s\n' "/usr/local/bin/aurelia-shell-keybindings"
    fi
}

runtime_provider() {
    if [[ "${WORKSTATION_TEST_MODE:-0}" == "1" && -n "${KEYBINDINGS_TEST_PROVIDER:-}" ]]; then
        printf '%s\n' "$KEYBINDINGS_TEST_PROVIDER"
        return 0
    fi
    if [[ "${WORKSTATION_TEST_MODE:-0}" == "1" && -n "${HOTKEYS_TEST_PROVIDER:-}" ]]; then
        printf '%s\n' "$HOTKEYS_TEST_PROVIDER"
        return 0
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/workstation/desktop.conf"
    if [[ -f "$config_file" ]]; then
        local provider
        provider="$(grep -E '^[[:space:]]*(keybindings|hotkeys)[._]provider[[:space:]]*=' "$config_file" 2>/dev/null | tail -n 1 | cut -d '=' -f2 | tr -d ' "[:space:]' || true)"
        if [[ -n "$provider" ]]; then
            printf '%s\n' "$provider"
            return 0
        fi
    fi
    printf '%s\n' "aurelia"
}

resolve_quickshell_bin() {
    if [[ ("${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1") &&
          -n "${QUICKSHELL_BIN:-}" && -x "$QUICKSHELL_BIN" ]]; then
        printf '%s\n' "$QUICKSHELL_BIN"
    elif [[ "${WORKSTATION_TEST_MODE:-0}" == "1" ]] && command -v qs >/dev/null 2>&1; then
        # Test-only PATH injection keeps the isolated mock harness deterministic;
        # production dispatch uses the fixed managed runtime paths below.
        command -v qs
    elif [[ -x "/usr/bin/qs" ]]; then
        printf '%s\n' "/usr/bin/qs"
    elif [[ -x "/usr/bin/quickshell" ]]; then
        printf '%s\n' "/usr/bin/quickshell"
    else
        return 1
    fi
}

run_diagnostics_runtime() {
    local format_json=0
    for arg in "$@"; do
        if [[ "$arg" == "--json" ]]; then
            format_json=1
        fi
    done

    local source_qml_root="$script_dir/../aurelia-shell"
    local active_qml_root=""
    local explicit_qml_root=0
    if [[ ("${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1") &&
          -n "${AURELIA_QML_ROOT:-}" && -f "$AURELIA_QML_ROOT" ]]; then
        active_qml_root="$AURELIA_QML_ROOT"
        explicit_qml_root=1
    elif [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/aurelia/shell.qml" ]]; then
        active_qml_root="${XDG_CONFIG_HOME:-$HOME/.config}/aurelia/shell.qml"
    elif [[ "${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1" ]] &&
         [[ -f "$source_qml_root/shell.qml" ]]; then
        active_qml_root="$source_qml_root/shell.qml"
    fi

    local running_pid="" running_args="" running_qml_root=""
    local runtime_info=""
    if ! runtime_info="$(find_quickshell_runtime "$active_qml_root" 2>/dev/null)" &&
       [[ -n "$active_qml_root" ]]; then
        # If the configured Aurelia tree is not the resident process, expose
        # the other Quickshell root so a stale or wrong instance is diagnosable.
        runtime_info="$(find_quickshell_runtime 2>/dev/null || true)"
    fi
    if [[ -n "$runtime_info" ]]; then
        IFS=$'\t' read -r running_pid running_args <<< "$runtime_info"
        if [[ "$running_args" =~ --path[[:space:]]+([^[:space:]]+) ]]; then
            running_qml_root="${BASH_REMATCH[1]}"
            if [[ -d "$running_qml_root" && -f "$running_qml_root/shell.qml" ]]; then
                running_qml_root="$running_qml_root/shell.qml"
            fi
        fi
    fi
    if [[ -z "$running_qml_root" ]]; then
        running_qml_root="not running"
    fi

    local ipc_qml_root="$running_qml_root"
    if [[ "$ipc_qml_root" == "not running" ]]; then
        ipc_qml_root="$active_qml_root"
    fi

    local live_revision="not running"
    local active_view="none"
    local qs_bin=""
    if qs_bin="$(resolve_quickshell_bin 2>/dev/null)" &&
       [[ -n "$running_pid" && "$running_pid" =~ ^[0-9]+$ ]] &&
       [[ -n "$ipc_qml_root" && -f "$ipc_qml_root" ]]; then
        local q_rev q_view
        q_rev="$("$qs_bin" ipc --path "$ipc_qml_root" call keybindings revision 2>/dev/null || true)"
        if [[ -n "$q_rev" ]]; then
            live_revision="$q_rev"
        fi
        q_view="$("$qs_bin" ipc --path "$ipc_qml_root" call keybindings activeView 2>/dev/null || true)"
        if [[ -n "$q_view" ]]; then
            active_view="$q_view"
        fi
    fi

    local managed_component_root=""
    local deployed_qml_root=""
    if [[ -n "$active_qml_root" ]]; then
        deployed_qml_root="$(dirname "$active_qml_root")"
        managed_component_root="$deployed_qml_root/components/keybindings"
    fi
    # In production, compare the actual running tree so a stale copied
    # configuration cannot appear healthy merely because the current managed
    # symlink/configuration is up to date. An explicit development/test root
    # is authoritative and must never be replaced by an unrelated resident
    # process; this keeps isolated provenance tests deterministic.
    if [[ "$explicit_qml_root" -eq 0 &&
          "$running_qml_root" != "not running" && -f "$running_qml_root" ]]; then
        deployed_qml_root="$(dirname "$running_qml_root")"
        if [[ -z "$managed_component_root" ]]; then
            managed_component_root="$deployed_qml_root/components/keybindings"
        fi
    fi

    local canonical_backend_path canonical_backend_hash=""
    local selected_backend_path selected_backend_hash=""
    local deployed_backend_root=""
    canonical_backend_path="$(diagnostic_backend_identity_path)"
    selected_backend_path="$(runtime_backend_path)"
    if [[ -n "${AURELIA_KEYBINDINGS_LIB_DIR:-}" ]]; then
        deployed_backend_root="$(dirname -- "$(dirname -- "$AURELIA_KEYBINDINGS_LIB_DIR")")"
    elif [[ "$selected_backend_path" == "/usr/local/bin/"* ]]; then
        # The production layout keeps the canonical executable in
        # /usr/local/bin and its owned modules in /usr/local/lib.  Derive the
        # stable installation root even when no development override is set.
        deployed_backend_root="/usr/local"
    elif [[ "$selected_backend_path" == */bin/* ]]; then
        # Isolated/development deployments place the module directory beside
        # the selected executable: <prefix>/bin/lib/aurelia-keybindings.
        deployed_backend_root="$(dirname -- "$selected_backend_path")"
    fi
    if [[ -f "$canonical_backend_path" ]]; then
        canonical_backend_hash="$(sha256sum "$canonical_backend_path" 2>/dev/null | awk '{print $1}')"
    fi
    if [[ -f "$selected_backend_path" ]]; then
        selected_backend_hash="$(sha256sum "$selected_backend_path" 2>/dev/null | awk '{print $1}')"
    fi

    local provider
    provider="$(runtime_provider)"
    local motion_enabled="true" motion_scale="1.0"
    local aurelia_bin=""
    if aurelia_bin="$(resolve_aurelia_bin 2>/dev/null)"; then
        local me ms
        me="$("$aurelia_bin" preference get components.keybindings.motion.enabled 2>/dev/null || true)"
        ms="$("$aurelia_bin" preference get components.keybindings.motion.scale 2>/dev/null || true)"
        [[ -n "$me" ]] && motion_enabled="$me"
        [[ -n "$ms" ]] && motion_scale="$ms"
    fi

    local manifest_path
    manifest_path="$(runtime_manifest_path)"

    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "Error: python3 is required for authoritative runtime diagnostics." >&2
        return 1
    fi

    python3 - "$format_json" "$canonical_backend_path" "$canonical_backend_hash" \
        "$selected_backend_path" "$selected_backend_hash" \
        "$deployed_backend_root" \
        "$active_qml_root" "$running_qml_root" "$managed_component_root" \
        "$running_pid" "$live_revision" "$active_view" "$provider" \
        "$motion_enabled" "$motion_scale" "aurelia-keybindings" "$manifest_path" \
        "$source_qml_root" "$deployed_qml_root" "$script_dir/aurelia-shell-keybindings" <<'PY_DIAGNOSTICS'
import hashlib
import json
import os
import sys
from pathlib import Path

RELATIVE_FILES = (
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
BACKEND_RELATIVE_FILES = (
    "lib/aurelia-keybindings/common.sh",
    "lib/aurelia-keybindings/queries.sh",
    "lib/aurelia-keybindings/actions.sh",
    "lib/aurelia-keybindings/mutations.sh",
    "lib/aurelia-keybindings/runtime.sh",
    "lib/aurelia-keybindings/toggle.sh",
    "lib/aurelia-keybindings/main.sh",
)

def digest(path):
    try:
        with open(path, "rb") as handle:
            hasher = hashlib.sha256()
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                hasher.update(chunk)
            return hasher.hexdigest()
    except (OSError, TypeError):
        return None

def entries(root):
    if not root:
        return [{"path": rel, "sha256": None} for rel in RELATIVE_FILES]
    root_path = Path(root)
    return [{"path": rel, "sha256": digest(root_path / rel)} for rel in RELATIVE_FILES]

def backend_entries(root):
    if not root:
        return [{"path": rel, "sha256": None} for rel in BACKEND_RELATIVE_FILES]
    root_path = Path(root)
    return [{"path": rel, "sha256": digest(root_path / rel)} for rel in BACKEND_RELATIVE_FILES]

def entry_map(items):
    if not isinstance(items, list):
        return {}
    result = {}
    for item in items:
        if isinstance(item, dict) and isinstance(item.get("path"), str):
            result[item["path"]] = item.get("sha256")
    return result

(
    format_json,
    canonical_backend_path,
    canonical_backend_hash,
    selected_backend_path,
    selected_backend_hash,
    deployed_backend_root,
    active_qml_root,
    running_qml_root,
    managed_component_root,
    running_pid,
    live_revision,
    active_view,
    provider,
    motion_enabled,
    motion_scale,
    layer_namespace,
    manifest_path,
    source_qml_root,
    deployed_qml_root,
    source_backend_path,
) = sys.argv[1:21]

source_backend_hash = digest(source_backend_path)
source_entries = entries(source_qml_root)
source_backend_entries = backend_entries(str(Path(source_backend_path).parent))
manifest_source = "repository-fallback"
manifest_errors = []
raw_expected = None

if manifest_path:
    try:
        with open(manifest_path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        if isinstance(payload, dict) and isinstance(payload.get("expected"), dict):
            raw_expected = payload["expected"]
            manifest_source = "deployment"
        else:
            manifest_errors.append("deployment manifest malformed: expected object missing")
    except FileNotFoundError:
        manifest_errors.append("deployment manifest missing")
    except (OSError, ValueError, TypeError):
        manifest_errors.append("deployment manifest unreadable or invalid JSON")

if raw_expected is None:
    expected_backend_hash = source_backend_hash
    expected_backend_files = source_backend_entries
    expected_files = source_entries
    expected_backend_path = source_backend_path
else:
    expected_backend_hash = raw_expected.get("backend_sha256")
    expected_backend_path = raw_expected.get("backend_path") or source_backend_path
    expected_by_path = entry_map(raw_expected.get("files"))
    expected_backend_by_path = entry_map(raw_expected.get("backend_files"))
    expected_files = []
    expected_backend_files = []
    for relative_path in RELATIVE_FILES:
        if relative_path in expected_by_path:
            expected_files.append({
                "path": relative_path,
                "sha256": expected_by_path[relative_path],
            })
        else:
            expected_files.append({"path": relative_path, "sha256": None})
            manifest_errors.append("deployment manifest missing expected hash: " + relative_path)
    for relative_path in BACKEND_RELATIVE_FILES:
        if relative_path in expected_backend_by_path:
            expected_backend_files.append({
                "path": relative_path,
                "sha256": expected_backend_by_path[relative_path],
            })
        else:
            expected_backend_files.append({"path": relative_path, "sha256": None})
            manifest_errors.append("deployment manifest missing expected backend hash: " + relative_path)
    if not isinstance(expected_backend_hash, str) or not expected_backend_hash:
        manifest_errors.append("deployment manifest missing expected backend hash")
        expected_backend_hash = None

expected_manifest = {
    "schema": 1,
    "component": "aurelia-keybindings",
    "qml_root": raw_expected.get("qml_root", source_qml_root) if raw_expected else source_qml_root,
    "backend_path": expected_backend_path,
    "backend_sha256": expected_backend_hash,
    "backend_files": expected_backend_files,
    "files": expected_files,
}

deployed_manifest = {
    "schema": 1,
    "component": "aurelia-keybindings",
    "qml_root": deployed_qml_root,
    "backend_path": canonical_backend_path,
    "backend_sha256": canonical_backend_hash or None,
    "backend_files": backend_entries(deployed_backend_root),
    "files": entries(deployed_qml_root),
}

mismatches = list(manifest_errors)
if expected_backend_hash != canonical_backend_hash:
    mismatches.append(
        "backend: expected " + str(expected_backend_hash or "missing") +
        ", deployed " + str(canonical_backend_hash or "missing")
    )
deployed_by_path = entry_map(deployed_manifest["files"])
for expected_file in expected_files:
    relative_path = expected_file["path"]
    expected_hash = expected_file.get("sha256")
    deployed_hash = deployed_by_path.get(relative_path)
    if expected_hash != deployed_hash:
        mismatches.append(
            "files/" + relative_path + ": expected " +
            str(expected_hash or "missing") + ", deployed " +
            str(deployed_hash or "missing")
        )
deployed_backend_by_path = entry_map(deployed_manifest["backend_files"])
for expected_file in expected_backend_files:
    relative_path = expected_file["path"]
    expected_hash = expected_file.get("sha256")
    deployed_hash = deployed_backend_by_path.get(relative_path)
    if expected_hash != deployed_hash:
        mismatches.append(
            "backend-files/" + relative_path + ": expected " +
            str(expected_hash or "missing") + ", deployed " +
            str(deployed_hash or "missing")
        )

try:
    motion_scale_value = float(motion_scale)
except (TypeError, ValueError):
    motion_scale_value = None

diagnostics = {
    "component": "aurelia-keybindings",
    "canonical_backend": {
        "path": canonical_backend_path,
        "sha256": canonical_backend_hash or None,
    },
    "runtime_backend": {
        "path": selected_backend_path,
        "sha256": selected_backend_hash or None,
    },
    "executable_path": selected_backend_path,
    "executable_sha256": selected_backend_hash or None,
    "active_qml_root": active_qml_root or None,
    "running_qml_root": running_qml_root if running_qml_root != "not running" else None,
    "managed_component_root": managed_component_root or None,
    "component_path": managed_component_root or None,
    "running_quickshell_pid": int(running_pid) if running_pid.isdigit() else None,
    "running_pid": int(running_pid) if running_pid.isdigit() else None,
    "live_ui_revision": live_revision,
    "active_view": active_view,
    "provider": provider,
    "motion_state": {
        "enabled": str(motion_enabled).lower() in ("1", "true", "yes"),
        "scale": motion_scale_value,
    },
    "effective_motion": {
        "enabled": str(motion_enabled).lower() in ("1", "true", "yes"),
        "scale": motion_scale_value,
    },
    "layer_namespace": layer_namespace,
    "expected_manifest_path": manifest_path or None,
    "manifest_source": manifest_source,
    "expected_manifest": expected_manifest,
    "deployed_manifest": deployed_manifest,
    "manifest_mismatches": mismatches,
}
if format_json == "1":
    print(json.dumps(diagnostics, indent=2, sort_keys=True))
else:
    print("=== Aurelia Shell Keybindings Runtime Diagnostics ===")
    print("Canonical Backend Path : " + str(canonical_backend_path))
    print("Canonical Backend SHA256: " + str(canonical_backend_hash or "missing"))
    print("Selected Runtime Path  : " + str(selected_backend_path))
    print("Selected Runtime SHA256: " + str(selected_backend_hash or "missing"))
    print("Running Quickshell PID : " + str(diagnostics["running_quickshell_pid"] or "not running"))
    print("Running QML Root       : " + str(running_qml_root))
    print("Managed Component Root : " + str(managed_component_root or "missing"))
    print("Expected Manifest Path : " + str(manifest_path or "missing"))
    print("Manifest Source        : " + manifest_source)
    print("Expected Manifest      : " + json.dumps(expected_manifest, sort_keys=True))
    print("Deployed Manifest      : " + json.dumps(deployed_manifest, sort_keys=True))
    print("Manifest Mismatches    : " + ("none" if not mismatches else "; ".join(mismatches)))
    print("Provider               : " + str(provider))
    print("Live UI Revision       : " + str(live_revision))
    print("Layer Namespace        : " + str(layer_namespace))
    print("Motion State           : enabled=" + str(diagnostics["motion_state"]["enabled"]).lower() +
          " scale=" + str(motion_scale_value))
    print("Active View            : " + str(active_view))
PY_DIAGNOSTICS
}
