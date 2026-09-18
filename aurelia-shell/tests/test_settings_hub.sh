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

if [[ -x "$repo_root/bin/workstation-system-settings" ]] &&
   grep -q 'install_workstation_system_settings' "$repo_root/modules/desktop.sh"; then
    pass "[static] system settings backend exists and the installer ships it"
else
    fail "[static] system settings backend is missing or not installed"
fi

# The clock widget must read the same Aurelia clock preferences the hub writes,
# otherwise the two are visibly out of sync.
if grep -q 'Theme.clockFormat' "$repo_root/aurelia-shell/plugins/aurelia.clock/ClockBarWidget.qml" &&
   grep -q 'Theme.clockHour24' "$repo_root/aurelia-shell/plugins/aurelia.clock/ClockBarWidget.qml" &&
   grep -q 'Theme.clockSeconds' "$repo_root/aurelia-shell/plugins/aurelia.clock/ClockBarWidget.qml" &&
   grep -q 'aurelia.clock.hour24' "$plugin_dir/ui/SettingsWindow.qml"; then
    pass "[static] clock widget follows the Aurelia clock preferences the hub writes"
else
    fail "[static] clock widget does not read the Aurelia clock preferences"
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

if "$backend" schema | python3 -c '
import json, sys
rows = json.load(sys.stdin)
by_cat = {}
for r in rows:
    by_cat[r["category"]] = by_cat.get(r["category"], 0) + 1
assert len(rows) >= 90, len(rows)
for c in ["general", "decoration", "input", "misc", "animations", "workspaces",
          "cursor", "binds", "master", "dwindle", "xwayland", "ecosystem"]:
    assert by_cat.get(c, 0) > 0, c
' >/dev/null; then
    pass "[static] hyprland option registry is extensive and covers every section"
else
    fail "[static] hyprland option registry is incomplete"
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

# Window close must be self-contained (like the keybindings window): plugin
# close() -> requestClose() must not re-enter the plugin (no signal roundtrip).
if grep -q 'function requestClose(reason)' "$plugin_dir/ui/SettingsWindow.qml" &&
   grep -q 'requestClose("plugin-close")' "$plugin_dir/SettingsPlugin.qml" &&
   ! grep -q 'onRequestClose: function' "$plugin_dir/SettingsPlugin.qml"; then
    pass "[static] settings window close is self-contained (no plugin close recursion)"
else
    fail "[static] settings window close lifecycle can recurse through the plugin"
fi

for row_file in SettingToggle SettingSlider SettingCombo SettingColor SettingText \
    SettingHeading SettingInfo SettingAction SettingsNav SettingsPage SettingsWindow \
    ColorPicker ColorChannelSlider SwitchControl ComboControl TextControl SliderControl; do
    if [[ ! -f "$plugin_dir/ui/$row_file.qml" ]]; then
        fail "[static] settings ui component missing: $row_file.qml"
    fi
done
pass "[static] settings ui component set is complete"

if [[ -f "$plugin_dir/ui/ColorUtils.js" ]] &&
   grep -q 'function parseColor' "$plugin_dir/ui/ColorUtils.js" &&
   grep -q 'function toRgba' "$plugin_dir/ui/ColorUtils.js"; then
    pass "[static] shared color utilities module is present"
else
    fail "[static] shared color utilities module is missing"
fi

# Color options must route through the picker/preset surface, never a raw
# rgba text field left in the row.
if ! grep -q 'TextControl' "$plugin_dir/ui/SettingColor.qml" &&
   grep -q 'ColorUtils' "$plugin_dir/ui/SettingColor.qml" &&
   grep -q 'pickRequested' "$plugin_dir/ui/SettingColor.qml" &&
   grep -q 'ColorPicker' "$plugin_dir/ui/SettingsWindow.qml" &&
   grep -q 'openColorPicker' "$plugin_dir/ui/SettingsWindow.qml" &&
   grep -q 'colorPickerRequested' "$plugin_dir/ui/SettingsPage.qml"; then
    pass "[static] color options route through a picker instead of a raw text field"
else
    fail "[static] color option picker wiring is incomplete"
fi

# Right-hand controls share one alignment edge: the switch draws its full
# implicit width and the row uses the same inset as the combo/text rows.
if grep -q 'implicitWidth: 40' "$plugin_dir/ui/SwitchControl.qml" &&
   grep -q 'Layout.rightMargin: Theme.spacingSm' "$plugin_dir/ui/SettingToggle.qml" &&
   grep -q 'ColorPicker 1.0 ColorPicker.qml' "$plugin_dir/ui/qmldir" &&
   grep -q 'ColorChannelSlider 1.0 ColorChannelSlider.qml' "$plugin_dir/ui/qmldir"; then
    pass "[static] toggle switch alignment and picker registration are stable"
else
    fail "[static] toggle switch alignment or picker registration regressed"
fi

# ColorUtils is pure JS; exercise its parse/format/validate contract directly.
if command -v node >/dev/null 2>&1; then
    color_utils_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_dir/ui/ColorUtils.js" >"$color_utils_test"
    cat >>"$color_utils_test" <<'COLOR_UTILS_EXPORTS'
module.exports = { parseColor, isValid, toRgba, sameRgb };
COLOR_UTILS_EXPORTS
    if node -e '
const C = require(process.argv[1]);
const a = C.parseColor("rgba(5fd4fdff)");
const b = C.parseColor("#5fd4fd80");
const ok = a.r === 0x5f && a.g === 0xd4 && a.b === 0xfd && a.a === 0xff &&
    b.a === 0x80 &&
    C.toRgba(0x5f, 0xd4, 0xfd, 0xff) === "rgba(5fd4fdff)" &&
    C.isValid("rgba(5fd4fdff)") && !C.isValid("not-a-color") &&
    C.sameRgb(1, 2, 3, 1, 2, 3) && !C.sameRgb(1, 2, 3, 4, 5, 6);
process.exit(ok ? 0 : 1);
' "$color_utils_test" >/dev/null 2>&1; then
        pass "[unit] ColorUtils parses, formats, and validates canonical colors"
    else
        fail "[unit] ColorUtils color contract failed"
    fi
    rm -f -- "$color_utils_test"
else
    skip "[unit] ColorUtils color contract (node unavailable)"
fi

# Defaults must be pickers, not file-edit instructions; kb_layout should be a
# curated (but still free-form) selector.
if command -v node >/dev/null 2>&1; then
    rows_projection_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_dir/ui/SettingsRows.js" >"$rows_projection_test"
    cat >>"$rows_projection_test" <<'ROWS_EXPORTS'
module.exports = { buildRows, emptyAureliaState, schemaRow };
ROWS_EXPORTS
    if node -e '
const SR = require(process.argv[1]);
const aurelia = Object.assign({}, SR.emptyAureliaState(), {
    defaults: { currents: { terminal: "kitty.desktop" }, choices: { terminal: ["kitty.desktop"] } }
});
const rows = SR.buildRows("defaults", [], {}, aurelia);
const kinds = rows.map(r => r.kind).join(",");
const term = rows.find(r => r.id === "defaults.terminal");
const kb = SR.schemaRow(
    { id: "input.kb_layout", type: "str", min: "", max: "", enum: "",
      category: "input", default: "us", label: "Keyboard Layout", description: "" },
    { effective: "us,ru" });
const ok = kinds === "heading,combo,combo,combo,combo,combo" &&
    term.enumOptions[0].value === "" &&
    term.enumOptions[1].value === "kitty.desktop" &&
    kb.kind === "combo" && kb.editable === true &&
    kb.enumOptions[0].value === "us,ru";
process.exit(ok ? 0 : 1);
' "$rows_projection_test" >/dev/null 2>&1; then
        pass "[unit] defaults are pickers and kb_layout is an editable selector"
    else
        fail "[unit] defaults/kb_layout row projection contract failed"
    fi
    rm -f -- "$rows_projection_test"
else
    skip "[unit] defaults/kb_layout row projection (node unavailable)"
fi

if [[ -x "$repo_root/bin/workstation-app-defaults" ]]; then
    if "$repo_root/bin/workstation-app-defaults" choices | python3 -c '
import json, sys
d = json.load(sys.stdin)
roles = {"terminal", "file-manager", "browser", "editor", "email-client"}
assert set(d.keys()) == roles, d.keys()
assert all(isinstance(v, list) for v in d.values())
' >/dev/null; then
        pass "[unit] app-defaults choices JSON covers every role"
    else
        fail "[unit] app-defaults choices JSON is invalid"
    fi
else
    skip "[unit] app-defaults choices JSON (CLI unavailable)"
fi

if command -v node >/dev/null 2>&1; then
    backends_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_dir/ui/SettingsBackends.js" >"$backends_test"
    cat >>"$backends_test" <<'BACKENDS_EXPORTS'
module.exports = { mergeSchemas, schemaMap, mergeStatusMaps, isSystemOption, backendFor };
BACKENDS_EXPORTS
    if node -e '
const B = require(process.argv[1]);
const schemas = B.mergeSchemas([{ id: "general.gaps_in" }], [{ id: "system.power.profile" }]);
const map = B.schemaMap(schemas);
const merged = B.mergeStatusMaps({ "general.gaps_in": { effective: "3" } },
    { "system.power.profile": { effective: "balanced" } });
const ok = schemas.length === 2 && map["system.power.profile"] &&
    merged["general.gaps_in"].effective === "3" &&
    merged["system.power.profile"].effective === "balanced" &&
    B.isSystemOption("system.time.ntp") && !B.isSystemOption("general.gaps_in") &&
    B.backendFor("system.time.ntp", "/hypr", "/sys") === "/sys" &&
    B.backendFor("general.gaps_in", "/hypr", "/sys") === "/hypr";
process.exit(ok ? 0 : 1);
' "$backends_test" >/dev/null 2>&1; then
        pass "[unit] settings backend merge and system-option routing are correct"
    else
        fail "[unit] settings backend routing contract failed"
    fi
    rm -f -- "$backends_test"
else
    skip "[unit] settings backend routing (node unavailable)"
fi

# ---------------------------------------------------------------------------
# Calendar week start (pure layout math + Date & Time row + preference)
# ---------------------------------------------------------------------------
calendar_model="$repo_root/aurelia-shell/plugins/aurelia.calendar/ui/CalendarModel.js"
calendar_panel="$repo_root/aurelia-shell/plugins/aurelia.calendar/ui/CalendarPanel.qml"
if command -v node >/dev/null 2>&1; then
    cal_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$calendar_model" >"$cal_test"
    cat >>"$cal_test" <<'CAL_EXPORTS'
module.exports = { weekdayLabels, firstWeekdayOffset };
CAL_EXPORTS
    if node -e '
const M = require(process.argv[1]);
const sun = M.weekdayLabels(0).join(",");
const mon = M.weekdayLabels(1).join(",");
const ok = sun === "SUN,MON,TUE,WED,THU,FRI,SAT" &&
    mon === "MON,TUE,WED,THU,FRI,SAT,SUN" &&
    M.firstWeekdayOffset(0, 0) === 0 && M.firstWeekdayOffset(1, 0) === 1 &&
    M.firstWeekdayOffset(0, 1) === 6 && M.firstWeekdayOffset(1, 1) === 0 &&
    M.firstWeekdayOffset(6, 1) === 5;
process.exit(ok ? 0 : 1);
' "$cal_test" >/dev/null 2>&1; then
        pass "[unit] calendar week-start rotates weekday labels and offsets"
    else
        fail "[unit] calendar week-start math is wrong"
    fi
    rm -f -- "$cal_test"
else
    skip "[unit] calendar week-start math (node unavailable)"
fi

# Clock format presets must produce the exact layout users pick.
clock_format_js="$repo_root/aurelia-shell/plugins/aurelia.clock/ClockFormat.js"
if command -v node >/dev/null 2>&1; then
    clock_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$clock_format_js" >"$clock_test"
    cat >>"$clock_test" <<'CLOCK_EXPORTS'
module.exports = { buildFormat, timeFormat };
CLOCK_EXPORTS
    if node -e '
const C = require(process.argv[1]);
const checks = [
    [C.buildFormat("month_day_time", true, false), "MMM d, HH:mm"],
    [C.buildFormat("weekday_day_month_time", true, false), "ddd d MMM, HH:mm"],
    [C.buildFormat("full_weekday_month_day_time", true, false), "dddd, MMM d, HH:mm"],
    [C.buildFormat("month_day_weekday_time", true, false), "MMM d, dddd HH:mm"],
    [C.buildFormat("time_only", true, false), "HH:mm"],
    [C.buildFormat("month_day_only", true, false), "MMM d"],
    [C.buildFormat("month_day_time", false, false), "MMM d, h:mm AP"],
    [C.buildFormat("weekday_day_month_time", false, true), "ddd d MMM, h:mm:ss AP"],
    [C.buildFormat("month_day_time", true, true), "MMM d, HH:mm:ss"],
];
const ok = checks.every(c => c[0] === c[1]);
if (!ok) console.error(JSON.stringify(checks));
process.exit(ok ? 0 : 1);
' "$clock_test" >/dev/null 2>&1; then
        pass "[unit] clock format presets cover 12/24h, seconds, and layouts"
    else
        fail "[unit] clock format preset mapping is wrong"
    fi
    rm -f -- "$clock_test"
else
    skip "[unit] clock format presets (node unavailable)"
fi

# The weekday header must always render: its row has an explicit height, and
# the panel follows the configured week start through the shared model.
if grep -q 'CalendarModel.weekdayLabels' "$calendar_panel" &&
   grep -q 'CalendarModel.firstWeekdayOffset' "$calendar_panel" &&
   grep -q 'height: parent.height' "$calendar_panel"; then
    pass "[static] calendar weekday header has a bounded height and follows week start"
else
    fail "[static] calendar weekday header can collapse or ignores week start"
fi

if "$repo_root/aurelia-shell/bin/workstation-aurelia" preference get aurelia.calendar.week_start 2>/dev/null |
   grep -qE '^(sunday|monday)$'; then
    pass "[unit] calendar week_start preference resolves to a valid day"
else
    fail "[unit] calendar week_start preference is unavailable"
fi

if "$repo_root/aurelia-shell/bin/workstation-aurelia" preference get aurelia.clock.format 2>/dev/null |
       grep -qE '^(time_only|month_day_time|month_day_weekday_time|weekday_day_month_time|full_weekday_month_day_time|month_day_only)$' &&
   "$repo_root/aurelia-shell/bin/workstation-aurelia" preference get aurelia.clock.hour24 2>/dev/null |
       grep -qE '^(true|false)$' &&
   "$repo_root/aurelia-shell/bin/workstation-aurelia" preference get aurelia.clock.seconds 2>/dev/null |
       grep -qE '^(true|false)$'; then
    pass "[unit] clock format/hour24/seconds preferences resolve"
else
    fail "[unit] clock preferences are unavailable"
fi

if command -v node >/dev/null 2>&1; then
    time_rows_test="$(mktemp --suffix=.js)"
    sed '/^\.pragma library/d' "$plugin_dir/ui/SettingsRows.js" >"$time_rows_test"
    cat >>"$time_rows_test" <<'TIME_ROWS_EXPORTS'
module.exports = { buildRows, emptyAureliaState };
TIME_ROWS_EXPORTS
    if node -e '
const SR = require(process.argv[1]);
const state = Object.assign({}, SR.emptyAureliaState(), {
    weekStart: "monday", clockFormat: "weekday_day_month_time", clockHour24: false, clockSeconds: true });
const rows = SR.buildRows("time", [], {}, state);
const week = rows.find(r => r.id === "aurelia.calendar.weekStart");
const format = rows.find(r => r.id === "aurelia.clock.format");
const hour24 = rows.find(r => r.id === "aurelia.clock.hour24");
const seconds = rows.find(r => r.id === "aurelia.clock.seconds");
const ok = week && week.kind === "combo" && week.effective === "monday" && week.enumOptions.length === 2 &&
    format && format.kind === "combo" && format.effective === "weekday_day_month_time" &&
    format.enumOptions.length === 6 &&
    hour24 && hour24.kind === "toggle" && hour24.effective === false &&
    seconds && seconds.kind === "toggle" && seconds.effective === true;
process.exit(ok ? 0 : 1);
' "$time_rows_test" >/dev/null 2>&1; then
        pass "[unit] Date & Time exposes clock format, hour cycle, seconds and week start"
    else
        fail "[unit] Date & Time clock rows are missing"
    fi
    rm -f -- "$time_rows_test"
fi

# ---------------------------------------------------------------------------
# System settings backend (mock appearance/audio/bluetooth/network/time tools)
# ---------------------------------------------------------------------------
system_backend="$repo_root/bin/workstation-system-settings"
if [[ -x "$system_backend" ]]; then
    sys_sandbox="$(mktemp -d)"
    sys_log="$sys_sandbox/applied.log"
    gs_store="$sys_sandbox/gsettings.store"
    : >"$sys_log"
    cat >"$gs_store" <<'GSINIT'
gtk-theme='adw-gtk3-dark'
icon-theme='Adwaita'
cursor-theme='default'
cursor-size=24
color-scheme='prefer-dark'
accent-color='blue'
text-scaling-factor=1.0
enable-animations=true
show-battery-percentage=false
clock-format='24h'
clock-show-seconds=false
clock-show-date=true
clock-show-weekday=false
GSINIT
    cat >"$sys_sandbox/powerprofilesctl" <<'MOCK_PP'
#!/usr/bin/env bash
case "$1" in
    get) echo balanced ;;
    set) echo "power $2" >>"$MOCK_SYS_LOG" ;;
esac
MOCK_PP
    cat >"$sys_sandbox/brightnessctl" <<'MOCK_BR'
#!/usr/bin/env bash
case "$1" in
    get) echo 5000 ;;
    max) echo 10000 ;;
    set) echo "brightness $2" >>"$MOCK_SYS_LOG" ;;
esac
MOCK_BR
    cat >"$sys_sandbox/wpctl" <<'MOCK_WP'
#!/usr/bin/env bash
case "$1" in
    get-volume) echo "Volume: 0.50" ;;
    set-volume) echo "volume $3" >>"$MOCK_SYS_LOG" ;;
    set-mute) echo "mute $3" >>"$MOCK_SYS_LOG" ;;
    set-default) echo "default $2" >>"$MOCK_SYS_LOG" ;;
    status) printf 'Audio\n Sinks:\n  *   50. Built-in Analog        [vol: 0.50]\n Sources:\n  *   51. Built-in Analog        [vol: 0.50]\n' ;;
esac
MOCK_WP
    cat >"$sys_sandbox/nmcli" <<'MOCK_NM'
#!/usr/bin/env bash
args="$*"
case "$args" in
    *"ACTIVE,TYPE,NAME connection show"*) printf 'yes:802-11-wireless:MyWifi\n' ;;
    *"TYPE,NAME connection show"*) printf '802-11-wireless:MyWifi\n802-3-ethernet:Wired\n' ;;
    "radio wifi") echo enabled ;;
    "radio wifi on") echo "wifi on" >>"$MOCK_SYS_LOG" ;;
    "radio wifi off") echo "wifi off" >>"$MOCK_SYS_LOG" ;;
    *"connection up"*) echo "connect ${!#}" >>"$MOCK_SYS_LOG" ;;
    *) : ;;
esac
MOCK_NM
    cat >"$sys_sandbox/timedatectl" <<'MOCK_TD'
#!/usr/bin/env bash
case "$*" in
    "show -p NTP --value") echo yes ;;
    "show -p Timezone --value") echo UTC ;;
    "list-timezones") printf 'UTC\nEurope/London\nAsia/Tokyo\n' ;;
    "set-ntp "*) echo "ntp $2" >>"$MOCK_SYS_LOG" ;;
    "set-timezone "*) echo "tz $2" >>"$MOCK_SYS_LOG" ;;
esac
MOCK_TD
    cat >"$sys_sandbox/gsettings" <<'MOCK_GS'
#!/usr/bin/env bash
store="$MOCK_GS_STORE"
case "$1" in
    get)
        grep -m1 "^$3=" "$store" 2>/dev/null | cut -d= -f2-
        ;;
    set)
        if [[ -f "$store" ]]; then
            grep -v "^$3=" "$store" >"$store.tmp" 2>/dev/null || true
            mv "$store.tmp" "$store"
        fi
        printf '%s=%s\n' "$3" "$4" >>"$store"
        ;;
esac
MOCK_GS
    cat >"$sys_sandbox/bluetoothctl" <<'MOCK_BT'
#!/usr/bin/env bash
case "$1" in
    show) printf '\tPowered: yes\n\tDiscoverable: no\n' ;;
    power) echo "bt-power $2" >>"$MOCK_SYS_LOG" ;;
    discoverable) echo "bt-discoverable $2" >>"$MOCK_SYS_LOG" ;;
esac
MOCK_BT
    chmod +x "$sys_sandbox"/powerprofilesctl "$sys_sandbox"/brightnessctl "$sys_sandbox"/wpctl \
        "$sys_sandbox"/nmcli "$sys_sandbox"/timedatectl "$sys_sandbox"/gsettings "$sys_sandbox"/bluetoothctl

    export WORKSTATION_SYSTEM_SETTINGS_POWERPROFILES_BIN="$sys_sandbox/powerprofilesctl"
    export WORKSTATION_SYSTEM_SETTINGS_BRIGHTNESS_BIN="$sys_sandbox/brightnessctl"
    export WORKSTATION_SYSTEM_SETTINGS_WPCTL_BIN="$sys_sandbox/wpctl"
    export WORKSTATION_SYSTEM_SETTINGS_NMCLI_BIN="$sys_sandbox/nmcli"
    export WORKSTATION_SYSTEM_SETTINGS_TIMEDATECTL_BIN="$sys_sandbox/timedatectl"
    export WORKSTATION_SYSTEM_SETTINGS_GSETTINGS_BIN="$sys_sandbox/gsettings"
    export WORKSTATION_SYSTEM_SETTINGS_BLUETOOTHCTL_BIN="$sys_sandbox/bluetoothctl"
    export MOCK_SYS_LOG="$sys_log"
    export MOCK_GS_STORE="$gs_store"

    if "$system_backend" status | python3 -c '
import json, sys
d = json.load(sys.stdin)
by_id = {o["id"]: o for o in d["options"]}
assert by_id["system.power.profile"]["effective"] == "balanced"
assert by_id["system.display.brightness"]["effective"] == "50"
assert by_id["system.appearance.gtk_theme"]["effective"] == "adw-gtk3-dark"
assert by_id["system.appearance.cursor_size"]["effective"] == "24"
assert by_id["system.appearance.color_scheme"]["effective"] == "prefer-dark"
assert by_id["system.audio.output_volume"]["effective"] == "50"
assert by_id["system.audio.output_device"]["effective"] == "50"
assert by_id["system.audio.input_device"]["effective"] == "51"
assert by_id["system.bluetooth.enabled"]["effective"] == "true"
assert by_id["system.network.wifi_enabled"]["effective"] == "true"
assert by_id["system.time.ntp"]["effective"] == "true"
assert by_id["system.time.timezone"]["effective"] == "UTC"
assert "system.time.clock_24h" not in by_id
assert len(by_id["system.time.timezone"]["options"]) == 3
assert any(o["value"] == "50" for o in by_id["system.audio.output_device"]["options"])
' >/dev/null; then
        pass "[sandbox] system settings status reads appearance/audio/bluetooth/time"
    else
        fail "[sandbox] system settings status is wrong"
    fi

    if "$system_backend" set system.power.profile performance >/dev/null &&
       "$system_backend" set system.display.brightness 40 >/dev/null &&
       "$system_backend" set system.appearance.gtk_theme adw-gtk3 >/dev/null &&
       "$system_backend" set system.appearance.cursor_size 32 >/dev/null &&
       "$system_backend" set system.appearance.color_scheme prefer-light >/dev/null &&
       "$system_backend" set system.appearance.text_scaling 1.25 >/dev/null &&
       "$system_backend" set system.appearance.enable_animations false >/dev/null &&
       "$system_backend" set system.audio.output_volume 35 >/dev/null &&
       "$system_backend" set system.audio.input_volume 40 >/dev/null &&
       "$system_backend" set system.audio.output_mute true >/dev/null &&
       "$system_backend" set system.audio.output_device 50 >/dev/null &&
       "$system_backend" set system.bluetooth.enabled false >/dev/null &&
       "$system_backend" set system.bluetooth.discoverable true >/dev/null &&
       "$system_backend" set system.network.wifi_enabled false >/dev/null &&
       "$system_backend" set system.time.ntp false >/dev/null &&
       "$system_backend" set system.time.timezone UTC >/dev/null &&
       grep -q '^power performance$' "$sys_log" &&
       grep -q '^brightness 40%$' "$sys_log" &&
       grep -q '^volume 35%$' "$sys_log" &&
       grep -q '^volume 40%$' "$sys_log" &&
       grep -q '^mute 1$' "$sys_log" &&
       grep -q '^default 50$' "$sys_log" &&
       grep -q '^bt-power off$' "$sys_log" &&
       grep -q '^bt-discoverable on$' "$sys_log" &&
       grep -q '^wifi off$' "$sys_log" &&
       grep -q '^tz UTC$' "$sys_log" &&
       grep -q "^gtk-theme='adw-gtk3'$" "$gs_store" &&
       grep -q '^cursor-size=32$' "$gs_store" &&
       grep -q "^color-scheme='prefer-light'$" "$gs_store" &&
       grep -qE '^text-scaling-factor=1\.2500?$' "$gs_store" &&
       grep -q '^enable-animations=false$' "$gs_store"; then
        pass "[sandbox] system settings apply through the owning tools"
    else
        fail "[sandbox] system settings apply routing is wrong"
    fi

    # Every registered option must independently validate and apply. Sample
    # values are derived from the schema/status so this stays exhaustive as
    # options are added.
    if python3 - "$system_backend" <<'SYS_PER_OPTION' >/dev/null
import json, subprocess, sys
backend = sys.argv[1]
schema = json.loads(subprocess.check_output([backend, "schema"]))
status = json.loads(subprocess.check_output([backend, "status"]))
by_id = {o["id"]: o for o in status["options"]}
def sample(o):
    t = o["type"]
    if t == "bool": return "true"
    if t == "int": return o["min"] if o["min"] not in ("", "-") else "0"
    if t == "float": return o["min"] if o["min"] not in ("", "-") else "1"
    if t == "enum": return o["enum"].split(",")[-1]
    if t == "denum":
        opts = by_id.get(o["id"], {}).get("options") or []
        return opts[0]["value"] if opts else None
    if t == "str": return "settings-test"
    return None
failures = []
for o in schema:
    v = sample(o)
    if v is None:
        failures.append((o["id"], "no-sample")); continue
    r = subprocess.run([backend, "set", o["id"], v], capture_output=True, text=True)
    if r.returncode != 0:
        failures.append((o["id"], "set", r.stderr.strip())); continue
    g = subprocess.run([backend, "get", o["id"]], capture_output=True, text=True)
    if g.returncode != 0 or g.stdout.strip() == "":
        failures.append((o["id"], "get", (g.stderr or g.stdout).strip()))
print(json.dumps(failures))
sys.exit(1 if failures else 0)
SYS_PER_OPTION
    then
        pass "[sandbox] every system option validates and applies"
    else
        fail "[sandbox] some system options failed to apply"
    fi

    sys_rejected=0
    "$system_backend" set system.power.profile banana >/dev/null 2>&1 && sys_rejected=1
    "$system_backend" set system.display.brightness 0 >/dev/null 2>&1 && sys_rejected=1
    "$system_backend" set system.display.brightness 200 >/dev/null 2>&1 && sys_rejected=1
    "$system_backend" set system.audio.output_volume 101 >/dev/null 2>&1 && sys_rejected=1
    "$system_backend" set system.appearance.gtk_theme not-a-real-theme >/dev/null 2>&1 && sys_rejected=1
    "$system_backend" set system.appearance.color_scheme rainbow >/dev/null 2>&1 && sys_rejected=1
    "$system_backend" set system.time.timezone Bad/Zone >/dev/null 2>&1 && sys_rejected=1
    "$system_backend" set bogus.option 1 >/dev/null 2>&1 && sys_rejected=1
    if [[ "$sys_rejected" -eq 0 ]]; then
        pass "[sandbox] system settings invalid values fail closed"
    else
        fail "[sandbox] system settings accepted an invalid value"
    fi

    unset WORKSTATION_SYSTEM_SETTINGS_POWERPROFILES_BIN WORKSTATION_SYSTEM_SETTINGS_BRIGHTNESS_BIN \
        WORKSTATION_SYSTEM_SETTINGS_WPCTL_BIN WORKSTATION_SYSTEM_SETTINGS_NMCLI_BIN \
        WORKSTATION_SYSTEM_SETTINGS_TIMEDATECTL_BIN WORKSTATION_SYSTEM_SETTINGS_GSETTINGS_BIN \
        WORKSTATION_SYSTEM_SETTINGS_BLUETOOTHCTL_BIN MOCK_SYS_LOG MOCK_GS_STORE
    rm -rf -- "$sys_sandbox"
else
    fail "[static] workstation-system-settings backend is missing"
fi

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
                input:kb_variant) echo '{"option": "input:kb_variant", "str": "[[EMPTY]]", "set": false }' ;;
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

# Newer option categories must persist into the overlay as nested tables.
if "$backend" set cursor.inactive_timeout 15 >/dev/null &&
   "$backend" set master.mfact 0.6 >/dev/null &&
   "$backend" set binds.scroll_event_delay 100 >/dev/null &&
   "$backend" set dwindle.preserve_split true >/dev/null &&
   [[ "$("$backend" get cursor.inactive_timeout)" == "15" ]] &&
   grep -q 'inactive_timeout = 15' "$WORKSTATION_HYPR_SETTINGS_PATH" &&
   grep -q 'mfact = 0.6' "$WORKSTATION_HYPR_SETTINGS_PATH" &&
   grep -q 'scroll_event_delay = 100' "$WORKSTATION_HYPR_SETTINGS_PATH" &&
   grep -q 'preserve_split = true' "$WORKSTATION_HYPR_SETTINGS_PATH"; then
    pass "[sandbox] new-category options persist into the overlay"
else
    fail "[sandbox] new-category options did not persist"
fi
"$backend" clear >/dev/null || true

# Every registered Hyprland option must validate and round-trip through the
# overlay. Sample values are derived from the schema so this stays exhaustive.
if python3 - "$backend" <<'HYPR_PER_OPTION' >/dev/null
import json, subprocess, sys
backend = sys.argv[1]
schema = json.loads(subprocess.check_output([backend, "schema"]))
def sample(o):
    t = o["type"]
    if t == "bool": return "true"
    if t == "int": return o["min"] if o["min"] not in ("", "-") else "0"
    if t == "float": return o["min"] if o["min"] not in ("", "-") else "1"
    if t == "enum": return o["enum"].split(",")[-1]
    if t == "str": return "settings-test"
    if t == "color": return "rgba(112233ff)"
    return None
failures = []
for o in schema:
    v = sample(o)
    if v is None:
        failures.append((o["id"], "no-sample")); continue
    r = subprocess.run([backend, "set", o["id"], v], capture_output=True, text=True)
    if r.returncode != 0:
        failures.append((o["id"], "set", r.stderr.strip())); continue
    g = subprocess.run([backend, "get", o["id"]], capture_output=True, text=True)
    got = g.stdout.strip()
    if g.returncode != 0:
        failures.append((o["id"], "get", g.stderr.strip())); continue
    if o["type"] == "float":
        try:
            if abs(float(got) - float(v)) > 1e-6:
                failures.append((o["id"], "value", got, v))
        except Exception:
            failures.append((o["id"], "parse", got))
    elif got != v:
        failures.append((o["id"], "value", got, v))
print(json.dumps(failures))
sys.exit(1 if failures else 0)
HYPR_PER_OPTION
then
    pass "[sandbox] every hyprland option validates and round-trips"
else
    fail "[sandbox] some hyprland options failed to round-trip"
fi
"$backend" clear >/dev/null || true

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

# Hyprland reports unset string options as the literal [[EMPTY]] marker; it
# must surface as an empty value, not that marker.
if "$backend" status | python3 -c '
import json, sys
d = json.load(sys.stdin)
by_id = {o["id"]: o for o in d["options"]}
assert by_id["input.kb_variant"]["effective"] == "", by_id["input.kb_variant"]
assert by_id["input.kb_variant"]["source"] == "live", by_id["input.kb_variant"]
assert "[[EMPTY]]" not in json.dumps(d)
' >/dev/null; then
    pass "[sandbox] [[EMPTY]] string options surface as empty values"
else
    fail "[sandbox] [[EMPTY]] marker leaked into settings state"
fi

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
