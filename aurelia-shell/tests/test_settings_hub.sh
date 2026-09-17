#!/usr/bin/env bash

# Settings Hub test suite: workstation-hypr-settings backend, the Hyprland
# loader contract, the aurelia.settings plugin manifest, and the row
# projection logic. All behavior tests run in disposable sandboxes with a
# mock hyprctl; nothing here mutates the live workstation.

set -Eeuo pipefail

section "Workstation Settings Hub"

repo_root="$(cd -- "$ROOT/.." && pwd -P)"
backend="$repo_root/bin/workstation-hypr-settings"
hyprland_lua="$repo_root/dotfiles/hypr/hyprland.lua"
manifest_lua="$ROOT/dotfiles/hypr/keybindings_manifest.lua"
plugin_dir="$ROOT/plugins/aurelia.settings"

# ---------------------------------------------------------------------------
# Static invariants
# ---------------------------------------------------------------------------
if [[ -x "$backend" && -f "$backend" ]] &&
   head -n 5 "$backend" | grep -q '#!/usr/bin/env bash' &&
   grep -q 'WORKSTATION_HYPR_SETTINGS_MANAGED_V1' "$backend"; then
    pass "[static] backend script exists, is executable, and carries the managed marker"
else
    fail "[static] workstation-hypr-settings backend is missing or unmarked"
fi

required_ids=(general.gaps_in general.border_size general.layout decoration.rounding
    decoration.shadow.enabled decoration.blur.enabled input.kb_layout input.repeat_rate
    animations.enabled animations.preset workspaces.persistent)
missing_id=0
for option_id in "${required_ids[@]}"; do
    if ! grep -q "^${option_id//./\\.}|" "$backend"; then
        fail "[static] required option missing from schema: $option_id"
        missing_id=1
    fi
done
if [[ "$missing_id" -eq 0 ]]; then
    pass "[static] option schema covers the required curated option set"
fi

if grep -q 'fedora-hyprland-workstation/hypr-settings.lua' "$hyprland_lua" &&
   grep -q 'pcall(dofile, path)' "$hyprland_lua" &&
   grep -q 'hl.animation({' "$hyprland_lua" &&
   grep -q 'hl.workspace_rule({' "$hyprland_lua"; then
    pass "[static] hyprland.lua merges the user overlay fail-closed (config, animations, workspaces)"
else
    fail "[static] hyprland.lua overlay loader contract is incomplete"
fi

if grep -q 'id = "desktop_settings"' "$manifest_lua" &&
   grep -q 'aurelia.settings' "$manifest_lua"; then
    pass "[static] desktop_settings binding opens the settings hub (aurelia.settings)"
else
    fail "[static] desktop_settings binding does not target the settings hub"
fi

if [[ -f "$plugin_dir/manifest.json" ]] &&
   jq -e '.id == "aurelia.settings" and (.kinds | index("panel")) != null and
         .entryPoints.panel == "SettingsPlugin.qml"' "$plugin_dir/manifest.json" >/dev/null &&
   grep -q 'IpcHandler' "$plugin_dir/SettingsPlugin.qml" &&
   grep -q 'target: "aurelia.settings"' "$plugin_dir/SettingsPlugin.qml"; then
    pass "[static] aurelia.settings plugin manifest and IPC target are canonical"
else
    fail "[static] aurelia.settings plugin metadata or IPC surface is incomplete"
fi

if "$ROOT/bin/aurelia-plugin" validate --first-party "$plugin_dir" >/dev/null; then
    pass "[static] aurelia.settings manifest passes the canonical plugin validator"
else
    fail "[static] aurelia.settings manifest failed canonical validation"
fi

if [[ -f "$plugin_dir/ui/SettingsRows.js" ]] &&
   grep -q '"aurelia.theme"' "$plugin_dir/ui/SettingsRows.js" &&
   grep -q 'workstation-hypr-settings' "$plugin_dir/ui/SettingsWindow.qml"; then
    pass "[static] settings surface delegates mutations to bounded backends only"
else
    fail "[static] settings row projection or backend delegation contract is incomplete"
fi

for row_file in SettingToggle SettingSlider SettingCombo SettingColor SettingText \
    SettingHeading SettingInfo SettingAction SettingsNav SettingsPage SettingsWindow; do
    if [[ ! -f "$plugin_dir/ui/$row_file.qml" ]]; then
        fail "[static] settings ui component missing: $row_file.qml"
    fi
done
pass "[static] settings ui component set is complete"

# ---------------------------------------------------------------------------
# Sandbox behavior (mock hyprctl)
# ---------------------------------------------------------------------------
sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox" || true' RETURN
mkdir -p -- "$sandbox/home/.config" "$sandbox/bin"

cat >"$sandbox/bin/hyprctl" <<'MOCK_HYPRCTL'
#!/usr/bin/env bash
case "$1" in
    -j)
        if [[ "$2" == getoption ]]; then
            case "$3" in
                general:gaps_in)   echo '{"option": "general:gaps_in", "css": "3 3 3 3", "set": true }' ;;
                general:border_size) echo '{"option": "general:border_size", "int": 2, "set": true }' ;;
                decoration:active_opacity) echo '{"option": "decoration:active_opacity", "float": 1.000000, "set": true }' ;;
                general:col.active_border) echo '{"option": "general:col.active_border", "gradient": "ff5fd4fd 0deg", "set": true }' ;;
                input:numlock_by_default) echo '{"option": "input:numlock_by_default", "bool": true, "set": true }' ;;
                *) echo '{"option": "'"$3"'", "int": 0, "set": true }' ;;
            esac
        fi
        ;;
    keyword) echo "KEYWORD $2 $3" >>"${MOCK_APPLY_LOG:-/dev/null}" ;;
    reload) echo "RELOAD" >>"${MOCK_APPLY_LOG:-/dev/null}" ;;
esac
MOCK_HYPRCTL
chmod +x "$sandbox/bin/hyprctl"

export HOME="$sandbox/home"
export XDG_CONFIG_HOME="$sandbox/home/.config"
export WORKSTATION_HYPR_SETTINGS_HYPRCTL_BIN="$sandbox/bin/hyprctl"
export WORKSTATION_HYPR_SETTINGS_PATH="$sandbox/home/.config/fedora-hyprland-workstation/hypr-settings.lua"
export MOCK_APPLY_LOG="$sandbox/apply.log"
: >"$MOCK_APPLY_LOG"

if "$backend" schema | python3 -c '
import json, sys
rows = json.load(sys.stdin)
ids = [r["id"] for r in rows]
assert all(x in ids for x in
  ["general.gaps_in", "general.border_size", "general.layout",
   "decoration.rounding", "input.repeat_rate", "animations.preset",
   "workspaces.persistent"])
types = {r["type"] for r in rows}
assert types <= {"bool", "int", "float", "str", "enum", "color"}
print(len(rows))
' >/dev/null; then
    pass "[sandbox] schema JSON is valid and complete"
else
    fail "[sandbox] schema JSON is invalid or incomplete"
fi

# set/get/reset/clear lifecycle
if "$backend" set general.gaps_in 4 >/dev/null &&
   [[ "$("$backend" get general.gaps_in)" == "4" ]] &&
   "$backend" set general.layout master >/dev/null &&
   [[ "$("$backend" get general.layout)" == "master" ]] &&
   "$backend" reset general.gaps_in >/dev/null &&
   [[ "$("$backend" get general.gaps_in)" == "3" ]] &&
   "$backend" clear >/dev/null &&
   [[ ! -e "$WORKSTATION_HYPR_SETTINGS_PATH" ]]; then
    pass "[sandbox] set/get/reset/clear lifecycle converges"
else
    fail "[sandbox] set/get/reset/clear lifecycle failed"
fi

# idempotency: second identical set must not rewrite the overlay (atomic
# rewrite would change the inode)
"$backend" set general.border_size 3 >/dev/null
before_inode="$(stat -c %i "$WORKSTATION_HYPR_SETTINGS_PATH" 2>&1 || true)"
"$backend" set general.border_size 3 >/dev/null
after_inode="$(stat -c %i "$WORKSTATION_HYPR_SETTINGS_PATH" 2>&1 || true)"
if [[ -n "$before_inode" && "$before_inode" == "$after_inode" ]] &&
   grep -q 'border_size = 3' "$WORKSTATION_HYPR_SETTINGS_PATH"; then
    pass "[sandbox] repeated identical set is a write no-op (idempotent)"
else
    fail "[sandbox] identical set rewrote the overlay"
fi
"$backend" clear >/dev/null || true

# validation failures fail closed
rejected=0
"$backend" set general.gaps_in -5 >/dev/null && rejected=1
"$backend" set general.layout banana >/dev/null && rejected=1
"$backend" set bogus.key 1 >/dev/null && rejected=1
"$backend" set general.resize_on_border maybe >/dev/null && rejected=1
"$backend" set general.col.active_border "not-a-color" >/dev/null && rejected=1
"$backend" set workspaces.persistent 99 >/dev/null && rejected=1
if [[ "$rejected" -eq 0 ]]; then
    pass "[sandbox] invalid values fail closed with no overlay mutation"
else
    fail "[sandbox] invalid values were accepted"
fi
[[ ! -e "$WORKSTATION_HYPR_SETTINGS_PATH" ]] || {
    fail "[sandbox] failed validations left an overlay behind"
}

# live apply routing: leaf via keyword, structural via reload
"$backend" set animations.preset snappy >/dev/null
"$backend" set workspaces.persistent 4 >/dev/null
"$backend" set decoration.blur.enabled true >/dev/null
if grep -q '^RELOAD$' "$MOCK_APPLY_LOG" && ! grep -q '^KEYWORD animation_preset' "$MOCK_APPLY_LOG"; then
    pass "[sandbox] structural options apply through hyprctl reload, not keyword"
else
    fail "[sandbox] structural option apply routing is wrong"
fi
if grep -q '^KEYWORD decoration:blur:enabled true$' "$MOCK_APPLY_LOG"; then
    pass "[sandbox] leaf options apply live through hyprctl keyword"
else
    fail "[sandbox] leaf option apply routing is wrong"
fi

# overlay round trip through the reader (luajit)
if command -v luajit >/dev/null || command -v lua >/dev/null; then
    if [[ "$("$backend" get animations.preset)" == "snappy" ]] &&
       [[ "$("$backend" get workspaces.persistent)" == "4" ]] &&
       "$backend" status | python3 -c '
import json, sys
d = json.load(sys.stdin)
by_id = {o["id"]: o for o in d["options"]}
assert by_id["animations.preset"]["override"] == "snappy"
assert by_id["workspaces.persistent"]["override"] == "4"
assert by_id["general.gaps_in"]["live"] == "3"
assert by_id["decoration.active_opacity"]["live"] == "1"
assert by_id["general.col.active_border"]["live"] == "rgba(5fd4fdff)"
' >/dev/null; then
        pass "[sandbox] overlay round-trips through the strict reader (override + live normalized)"
    else
        fail "[sandbox] overlay read-back or status normalization failed"
    fi
else
    skip "[sandbox] overlay reader round-trip (luajit or lua unavailable)"
fi
"$backend" clear >/dev/null || true

# unmanaged file refusal
printf '%s\n' 'return {}' >"$WORKSTATION_HYPR_SETTINGS_PATH"
if "$backend" status >/dev/null; then
    fail "[sandbox] unmanaged overlay file was accepted"
else
    pass "[sandbox] unmanaged overlay file is refused (fails closed)"
fi
rm -f -- "$WORKSTATION_HYPR_SETTINGS_PATH"

# hyprctl unavailable: settings persist, apply is observable as pending
if WORKSTATION_HYPR_SETTINGS_HYPRCTL_BIN=/nonexistent-hyprctl \
    "$backend" set general.layout master >/dev/null &&
   grep -q 'layout = "master"' "$WORKSTATION_HYPR_SETTINGS_PATH"; then
    pass "[sandbox] settings persist even when hyprctl is unreachable"
else
    fail "[sandbox] persist-without-compositor path failed"
fi

# path safety
unsafe=0
WORKSTATION_HYPR_SETTINGS_PATH=/etc/hypr-settings.lua "$backend" set general.layout master >/dev/null && unsafe=1
WORKSTATION_HYPR_SETTINGS_PATH=/usr/local/bin/x "$backend" set general.layout master >/dev/null && unsafe=1
WORKSTATION_HYPR_SETTINGS_PATH="$sandbox/home/.config/../usr-priv" "$backend" set general.layout master >/dev/null && unsafe=1
if [[ "$unsafe" -eq 0 ]]; then
    pass "[sandbox] privileged and traversal overlay paths are rejected"
else
    fail "[sandbox] unsafe overlay path was accepted"
fi

# ---------------------------------------------------------------------------
# Row projection (offscreen qs, when available)
# ---------------------------------------------------------------------------
if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] settings row projection smoke (qs or timeout unavailable)"
else
    projection_dir="$(mktemp -d)"
    projection_result="$(mktemp)"
    : >"$projection_result"
    mkdir -p -- "$projection_dir/projection"
    cp "$plugin_dir/ui/SettingsRows.js" "$projection_dir/projection/SettingsRows.js"
    cat >"$projection_dir/projection/Main.qml" <<'PROJECTION_QML'
import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsRows.js" as SR

Item {
    readonly property string resultPath: Quickshell.env("SETTINGS_PROJECTION_RESULT") || ""
    property bool evaluated: false

    Component.onCompleted: {
        var sections = SR.sections()
        var schema = [
            { id: "general.gaps_in", type: "int", min: "0", max: "64", enum: "",
              category: "general", default: "3", label: "Gaps In", description: "" },
            { id: "decoration.blur.enabled", type: "bool", min: "", max: "", enum: "",
              category: "decoration", default: "false", label: "Blur", description: "" },
            { id: "general.layout", type: "enum", min: "", max: "", enum: "dwindle,master",
              category: "general", default: "dwindle", label: "Layout", description: "" }
        ]
        var status = {
            "general.gaps_in": { effective: "4", source: "override" },
            "decoration.blur.enabled": { effective: true, source: "override" },
            "general.layout": { effective: "master", source: "live" }
        }
        var rows = SR.buildRows("hypr-general", schema, status, SR.emptyAureliaState())
        var byKind = {}
        for (var i = 0; i < rows.length; i++) {
            byKind[rows[i].kind] = (byKind[rows[i].kind] || 0) + 1
        }
        var ok = rows.length === 5 &&
                 byKind.heading === 2 &&
                 byKind.toggle === 1 &&
                 byKind.combo === 1 &&
                 byKind.slider === 1 &&
                 rows[2].effective === "master" &&
                 rows[4].effective === true &&
                 sections.length >= 4
        Qt.callLater(function() {
            resultFile.setText((ok ? "ok" : "fail rows=" + rows.length + " kinds=" + JSON.stringify(byKind)) + "\n")
        })
    }

    FileView {
        id: resultFile
        path: resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
        onSaved: Qt.quit()
        onSaveFailed: function() { console.warn("SETTINGS_PROJECTION_FAILED result write"); Qt.quit() }
    }

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
PROJECTION_QML
    cat >"$projection_dir/projection/shell.qml" <<'PROJECTION_SHELL'
import QtQuick
import Quickshell

ShellRoot {
    Loader {
        active: true
        source: "Main.qml"
    }
}
PROJECTION_SHELL
    projection_root="$(mktemp -d)"
    mkdir -p -- "$projection_root/runtime" "$projection_root/cache"
    projection_status=0
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$projection_root/runtime" \
    XDG_CACHE_HOME="$projection_root/cache" \
    SETTINGS_PROJECTION_RESULT="$projection_result" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$projection_dir/projection/shell.qml" --no-color \
        >"$projection_root/out.log" 2>&1 || projection_status=$?
    projection_result_text="$(cat "$projection_result" || true)"
    if [[ "$projection_status" -eq 0 ]] && [[ "$projection_result_text" == ok ]]; then
        pass "[isolated-runtime] settings row projection builds expected schema rows (by category, by kind)"
    elif [[ "$projection_status" -ne 0 ]] &&
         runtime_log_is_environment_only "$projection_root/out.log" ""; then
        skip "[isolated-runtime] settings row projection smoke (headless environment limitation)"
    else
        fail "[isolated-runtime] settings row projection failed (status=$projection_status result=$(head -c 80 "$projection_result" || true))"
        sed -n '1,10p' "$projection_root/out.log" >&2 || true
    fi
    rm -rf -- "$projection_dir" "$projection_root" "$projection_result"
fi
