#!/usr/bin/env bash

# Contract tests for the Aurelia Display/monitor bar plugin. These tests use
# isolated command fixtures and never query or mutate the live compositor.

set -Eeuo pipefail

plugin_root="$ROOT/plugins/aurelia.monitor"
model_file="$plugin_root/Model.js"

section "Display Plugin Contract"

if [[ -f "$plugin_root/manifest.json" &&
      -f "$plugin_root/DisplayBarWidget.qml" &&
      -f "$plugin_root/DisplayPanel.qml" &&
      -f "$model_file" ]] &&
   jq -e '.schemaVersion == 1 and
          .id == "aurelia.monitor" and
          .name == "Display" and
          (.kinds == ["bar-widget"]) and
          .entryPoints.barWidget == "DisplayBarWidget.qml" and
          .barWidget.defaultSection == "right"' "$plugin_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$plugin_root" >/dev/null 2>&1; then
    pass "Display declares a validated first-party bar-widget plugin"
else
    fail "Display manifest or entry-point contract is incomplete"
fi

if grep -Fq 'AureliaKeyboardPanel' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'aurelia-monitor-state' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'aurelia-brightness-display' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'aurelia-hyprland-monitor-scaling' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'aurelia-hyprland-monitor-resolution' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'aurelia-display-text-size' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'command: ["/bin/bash", root.stateBin]' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'function toggleDisplay' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'function setResolution' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'enabledDisplayCount <= 1' "$plugin_root/DisplayPanel.qml" &&
   grep -Fq 'function closeForPopoutSwitch' "$plugin_root/DisplayPanel.qml" &&
   ! grep -Eq 'bash[[:space:]]*-c|eval[[:space:]]' "$plugin_root/DisplayPanel.qml"; then
    pass "Display keeps UI state in QML and routes system actions through bounded helpers"
else
    fail "Display panel lifecycle, action routing, or last-display guard is incomplete"
fi

if grep -Fq 'onWheel' "$plugin_root/DisplayBarWidget.qml" &&
   grep -Fq 'wheelBrightness' "$plugin_root/DisplayBarWidget.qml" &&
   grep -Fq 'barAnchorItem' "$plugin_root/DisplayBarWidget.qml" &&
   grep -Fq 'AureliaIcon {' "$plugin_root/DisplayBarWidget.qml" &&
   grep -Fq 'glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"' "$plugin_root/DisplayBarWidget.qml" &&
   ! grep -Fq 'name: Quickshell.screens.length > 1' "$plugin_root/DisplayBarWidget.qml" &&
   ! grep -Fq 'fallbackName: "computer"' "$plugin_root/DisplayBarWidget.qml" &&
   grep -Fq 'tint: root.isVisible() ? Theme.accent : Theme.textSecondary' "$plugin_root/DisplayBarWidget.qml" &&
   grep -Fq 'readonly property string backendRoot: sourceBinRoot' "$plugin_root/DisplayBarWidget.qml" &&
   grep -Fq 'Qt.resolvedUrl("../../bin")' "$plugin_root/DisplayBarWidget.qml" &&
   grep -Fq 'backend_root=' "$plugin_root/DisplayPanel.qml"; then
    pass "Display bar affordance supports anchored opening and brightness wheel control"
else
    fail "Display bar affordance is incomplete"
fi

if grep -Fq 'fontBaseSize' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'displaySettingsProbe' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'watchChanges: themeRoot.displaySettingsAvailable' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'reloadDisplaySettings' "$ROOT/theme/Theme.qml" &&
   grep -Fq 'aurelia.monitor' "$ROOT/config/bar-default.json" &&
   grep -Fq 'aurelia.monitor' "$ROOT/plugins/aurelia.monitor/manifest.json"; then
    pass "Display is included in the default bar and its user-owned text setting is watched"
else
    fail "Display default-bar or text-size integration is incomplete"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$model_file" <<'NODE'
const model = require(process.argv[2])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
assert(model.clampBrightness(0) === 1, "brightness minimum")
assert(model.clampBrightness(101) === 100, "brightness maximum")
assert(model.clampBrightness(42.4) === 42, "brightness rounding")
assert(model.clampBrightness("bad") === 1, "invalid brightness")
assert(model.cleanScale(3, 1280, 800) === "3.2", "clean VM scale")
assert(model.cleanScale(1.25, 6016, 3384) === "1.33", "clean physical scale")
assert(model.matchingScaleIndex(["1", "1.25", "1.6", "2", "3", "4"], 3.2, 1280, 800) === 4, "matching scale")
assert(model.availableScales(["1", "1.25", "1.6", "2", "3", "4"], 1280, 804).join(",") === "1,1.25,2,4", "duplicate scales")
assert(model.currentMode({ width: 1920, height: 1080, refreshRate: 60 }) === "1920x1080@60", "current resolution")
const modes = model.resolutionModes({
  width: 1920,
  height: 1080,
  refreshRate: 60,
  availableModes: ["5120x2880@60Hz", "1920x1080@60.00Hz", "1280x720@60Hz"]
})
assert(modes.length === 3 && modes[0].mode === "5120x2880@60", "available resolutions")
const parsed = model.parseDisplays(JSON.stringify([
  { name: "eDP-1", enabled: true },
  { name: "DP-1", enabled: false },
  { name: "HDMI-A-1", enabled: true }
]))
assert(parsed.enabledDisplayCount === 2, "display count")
NODE
    then
        pass "Display model clamps brightness, cleans scale presets, and counts outputs"
    else
        fail "Display model runtime checks failed"
    fi
else
    pass "SKIP Display model runtime checks (node unavailable)"
fi

for backend in \
    "$ROOT/bin/aurelia-monitor-state" \
    "$ROOT/bin/aurelia-brightness-display" \
    "$ROOT/bin/aurelia-hyprland-monitor-scaling" \
    "$ROOT/bin/aurelia-hyprland-monitor-resolution" \
    "$ROOT/bin/aurelia-display-text-size"; do
    if [[ -x "$backend" ]] && [[ "$(head -1 "$backend")" == "#!/bin/bash" ]] && bash -n "$backend"; then
        pass "backend is executable and syntactically valid: $(basename "$backend")"
    else
        fail "backend is missing or syntactically invalid: $backend"
    fi
done

display_tmp="$(mktemp -d)"
display_bin="$display_tmp/bin"
display_runtime="$display_tmp/runtime"
display_home="$display_tmp/home"
display_backlight="$display_tmp/backlight"
display_calls="$display_tmp/calls"
mkdir -p "$display_bin" "$display_runtime" "$display_home" "$display_backlight/intel_backlight"

cat >"$display_bin/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
if [[ "$*" == "monitors all -j" || "$*" == "monitors -j" ]]; then
    printf '%s\n' '[{"name":"eDP-1","focused":true,"disabled":false,"width":1920,"height":1080,"scale":1.5,"refreshRate":60.0,"availableModes":["1920x1080@60.00Hz","1280x720@60.00Hz"],"mirrorOf":"none"},{"name":"DP-1","focused":false,"disabled":false,"width":2560,"height":1440,"scale":1.0,"refreshRate":60.0,"availableModes":["2560x1440@60.00Hz"],"mirrorOf":"none"}]'
elif [[ "$1" == "keyword" || "$1" == "eval" ]]; then
    printf '%s\n' "$*" >>"$AURELIA_DISPLAY_TEST_CALLS"
else
    exit 1
fi
EOF_HYPRCTL

cat >"$display_bin/aurelia-brightness-display" <<'EOF_BRIGHTNESS'
#!/usr/bin/env bash
printf '%s\n' 42
EOF_BRIGHTNESS

cat >"$display_bin/aurelia-hyprland-monitor-scaling" <<'EOF_SCALE'
#!/usr/bin/env bash
printf '%s\n' 1.5
EOF_SCALE

cat >"$display_bin/brightnessctl" <<'EOF_BRIGHTNESSCTL'
#!/usr/bin/env bash
if [[ "$*" == *" -m"* ]]; then
    printf '%s\n' 'intel_backlight,backlight,42,42%'
else
    printf '%s\n' "$*" >>"$AURELIA_DISPLAY_TEST_CALLS"
fi
EOF_BRIGHTNESSCTL

chmod 0755 "$display_bin"/*

state_output="$(PATH="$display_bin:$PATH" \
    AURELIA_BACKLIGHT_PATH="$display_backlight" \
    AURELIA_DISPLAY_TEST_CALLS="$display_calls" \
    "$ROOT/bin/aurelia-monitor-state")"
if [[ "$(sed -n '1p' <<<"$state_output")" == "42" &&
      "$(sed -n '6p' <<<"$state_output")" == "eDP-1" &&
      "$(sed -n '8p' <<<"$state_output")" == '[{"name":"eDP-1","enabled":true,"focused":true,"width":1920,"height":1080,"refreshRate":60.0,"availableModes":["1920x1080@60.00Hz","1280x720@60.00Hz"]},{"name":"DP-1","enabled":true,"focused":false,"width":2560,"height":1440,"refreshRate":60.0,"availableModes":["2560x1440@60.00Hz"]}]' ]]; then
    pass "monitor-state keeps the eight-line record aligned and preserves display fields"
else
    fail "monitor-state output contract drifted: $state_output"
fi

PATH="$display_bin:$PATH" \
    AURELIA_BACKLIGHT_PATH="$display_backlight" \
    XDG_RUNTIME_DIR="$display_runtime" \
    AURELIA_DISPLAY_TEST_CALLS="$display_calls" \
    "$ROOT/bin/aurelia-brightness-display" --no-osd --monitor eDP-1 55% >/dev/null

PATH="$display_bin:$PATH" \
    AURELIA_DISPLAY_TEST_CALLS="$display_calls" \
    "$ROOT/bin/aurelia-hyprland-monitor-scaling" 1.25 >/dev/null

PATH="$display_bin:$PATH" \
    AURELIA_DISPLAY_TEST_CALLS="$display_calls" \
    "$ROOT/bin/aurelia-hyprland-monitor-resolution" 1280x720@60 >/dev/null

if grep -Fq -- '-d intel_backlight set 55%' "$display_calls" &&
   grep -Fq -- 'eval hl.monitor({ output = "eDP-1", mode = "1920x1080@60.0", position = "auto", scale = 1.25 })' "$display_calls" &&
   grep -Fq -- 'eval hl.monitor({ output = "eDP-1", mode = "1280x720@60", position = "auto", scale = 1.5 })' "$display_calls"; then
    pass "brightness, scale, and resolution helpers use validated focused-display commands"
else
    fail "brightness, scale, or resolution helper fixture did not receive the expected command"
fi

PATH="$PATH" HOME="$display_home" XDG_CONFIG_HOME="$display_tmp/config" \
    "$ROOT/bin/aurelia-display-text-size" 16 >/dev/null
if grep -Fxq 'fontBaseSize = 16' "$display_tmp/config/aurelia/display.conf" &&
   HOME="$display_home" XDG_CONFIG_HOME="$display_tmp/config" "$ROOT/bin/aurelia-display-text-size" | grep -Fxq 16; then
    pass "text-size helper atomically persists a user-owned Aurelia setting"
else
    fail "text-size helper did not persist or read back the expected value"
fi

rm -rf -- "$display_tmp"
