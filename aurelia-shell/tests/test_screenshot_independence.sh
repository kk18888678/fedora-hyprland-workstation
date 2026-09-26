#!/usr/bin/env bash

# Central independence property for the screenshot capability.
#
# The screenshot shortcuts must survive the `aurelia.screenshot` bar widget
# being disabled, removed from every bar layout section, or the plugin being
# uninstalled. This suite proves the property directly rather than asserting a
# particular refactor shape: the bindings are core-owned, a disabled and
# layout-absent plugin still resolves to a live core handler, and a capture can
# still start.

set -Eeuo pipefail

section "Screenshot Capability Independence"

service_qml="$ROOT/services/ScreenshotService.qml"
router_qml="$ROOT/services/ShellCallRouter.qml"
widget_qml="$ROOT/plugins/aurelia.screenshot/ui/ScreenshotBarWidget.qml"
manifest_lua="$ROOT/dotfiles/hypr/keybindings_manifest.lua"

if [[ ! -e "$ROOT/plugins/aurelia.screenshot/keybindings.lua" ]] &&
   grep -q 'id = "aurelia.screenshot.quick_region"' "$manifest_lua" &&
   grep -q 'id = "aurelia.screenshot.quick_screen"' "$manifest_lua" &&
   grep -q 'key = "SUPER + SHIFT + R"' "$manifest_lua" &&
   grep -q 'key = "SUPER + SHIFT + S"' "$manifest_lua" &&
   grep -q 'action_type = "plugin_ipc"' "$manifest_lua" &&
   grep -q 'target = "aurelia.screenshot"' "$manifest_lua"; then
    pass "[static] screenshot bindings are core-owned and the plugin no longer declares them"
else
    fail "[static] screenshot binding ownership still depends on the plugin"
fi

if grep -q 'ScreenshotService {' "$ROOT/shell.qml" &&
   grep -q 'ShellCallRouter {' "$ROOT/shell.qml" &&
   grep -q 'shellCallRouter.call(pluginHost' "$ROOT/shell.qml" &&
   [[ -f "$router_qml" ]] &&
   grep -q 'screenshotTarget: "aurelia.screenshot"' "$router_qml" &&
   grep -q 'core.ipcCall' "$router_qml" &&
   grep -q 'screenshot-unavailable' "$router_qml" &&
   [[ -f "$service_qml" ]] &&
   grep -q 'target: "aurelia.screenshot"' "$service_qml" &&
   grep -q 'Process {' "$service_qml" &&
   grep -q 'publishScreenshot' "$service_qml" &&
   grep -q 'function cancelCapture' "$service_qml" &&
   ! grep -q 'plugins/aurelia.screenshot' "$service_qml"; then
    pass "[static] core service, IPC target, and shell-aware fallback are wired without plugin coupling"
else
    fail "[static] core screenshot routing or the shell fallback is incomplete"
fi

if [[ -f "$widget_qml" ]] &&
   ! grep -q 'Process {' "$widget_qml" &&
   ! grep -q 'captureProcess' "$widget_qml" &&
   ! grep -q 'captureStage' "$widget_qml" &&
   ! grep -q 'pendingCaptureRequest' "$widget_qml" &&
   ! grep -q 'publishScreenshot' "$widget_qml" &&
   ! grep -q 'ScreenshotPanel.qml' "$widget_qml" &&
   ! grep -q 'ScreenshotMenuPopup' "$widget_qml" &&
   ! grep -q 'ScreenshotSelectionOverlay' "$widget_qml" &&
   grep -q 'shell.call("aurelia.screenshot"' "$widget_qml" &&
   grep -q 'activePopoutId === "aurelia.screenshot"' "$widget_qml"; then
    pass "[static] the bar widget is a pure view that delegates to the core IPC surface"
else
    fail "[static] the bar widget still owns capture state or presentation loading"
fi

# Keybinding ownership proof: load the real core manifest from a temporary
# shell root that has an empty plugins directory, so no plugin keybindings file
# (screenshot or otherwise) can contribute the two entries. If the ids resolve
# with their keys and action type, the core owns them.
if command -v luajit >/dev/null; then
    ownership_root="$(mktemp -d)"
    trap 'rm -rf -- "$ownership_root" || true' RETURN
    mkdir -p -- "$ownership_root/dotfiles/hypr" "$ownership_root/plugins"
    cp -- "$manifest_lua" "$ownership_root/dotfiles/hypr/keybindings_manifest.lua"
    lua_script="$ownership_root/assert_manifest.lua"
    cat >"$lua_script" <<'LUA_MANIFEST'
local path = arg[1]
local m = dofile(path)
assert(type(m) == "table" and type(m.bindings) == "table", "manifest did not return bindings")
local by_id = {}
for _, b in ipairs(m.bindings) do
    if type(b) == "table" and type(b.id) == "string" then by_id[b.id] = b end
end
local region = by_id["aurelia.screenshot.quick_region"]
local screen = by_id["aurelia.screenshot.quick_screen"]
assert(region, "quick_region missing without plugin declarations")
assert(screen, "quick_screen missing without plugin declarations")
assert(region.key == "SUPER + SHIFT + R", "quick_region key changed")
assert(screen.key == "SUPER + SHIFT + S", "quick_screen key changed")
assert(region.action_type == "plugin_ipc", "quick_region action_type changed")
assert(screen.action_type == "plugin_ipc", "quick_screen action_type changed")
assert(region.target == "aurelia.screenshot" and screen.target == "aurelia.screenshot", "target changed")
assert(region.method == "quickRegion" and screen.method == "quickScreen", "method changed")
assert(region.category == "Applications & Launchers", "quick_region category changed")
assert(region.editable == true and region.runnable == true and region.keyboard_bindable == true, "quick_region flags changed")
assert(screen.editable == true and screen.runnable == true and screen.keyboard_bindable == true, "quick_screen flags changed")
assert(type(region.command_argv) == "table" and region.command_argv[2] == "shell" and
    region.command_argv[3] == "call" and region.command_argv[4] == "aurelia.screenshot" and
    region.command_argv[5] == "quickRegion", "quick_region command contract changed")
assert(type(screen.command_argv) == "table" and screen.command_argv[2] == "shell" and
    screen.command_argv[3] == "call" and screen.command_argv[4] == "aurelia.screenshot" and
    screen.command_argv[5] == "quickScreen", "quick_screen command contract changed")
print("ok")
LUA_MANIFEST
    ownership_status=0
    ownership_output="$(luajit "$lua_script" "$ownership_root/dotfiles/hypr/keybindings_manifest.lua" 2>&1)" || ownership_status=$?
    if [[ "$ownership_status" -eq 0 && "$ownership_output" == "ok" ]]; then
        pass "[isolated-lua] core manifest resolves both screenshot actions with no plugin keybindings present"
    else
        fail "[isolated-lua] core manifest ownership proof failed: $ownership_output"
    fi
else
    skip "[isolated-lua] core manifest ownership proof (luajit unavailable)"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] screenshot independence fixture (qs or timeout unavailable)"
    return 0
fi

runtime_dir="$(mktemp -d)"
runtime_result="$runtime_dir/result.json"
runtime_output="$runtime_dir/output.log"
trap 'rm -rf -- "$runtime_dir" || true' RETURN
: >"$runtime_result"

runtime_status=0
AURELIA_SCREENSHOT_INDEPENDENCE_RESULT="$runtime_result" \
AURELIA_SCREENSHOT_HOST_SOURCE="$ROOT/services/PluginHost.qml" \
AURELIA_SCREENSHOT_ROUTER_SOURCE="$ROOT/services/ShellCallRouter.qml" \
AURELIA_SCREENSHOT_SERVICE_SOURCE="$ROOT/services/ScreenshotService.qml" \
AURELIA_SCREENSHOT_SHELL_ROOT="$ROOT" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_STATE_HOME="$runtime_dir/state" \
XDG_CONFIG_HOME="$runtime_dir/config" \
XDG_CACHE_HOME="$runtime_dir/cache" \
XDG_RUNTIME_DIR="$runtime_dir/runtime" \
    /usr/bin/timeout --kill-after=1s 15s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/screenshot-independence/shell.qml" \
    >"$runtime_output" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   runtime_log_is_environment_only "$runtime_output" \
       '\[SCREENSHOT\] (menu_load_failed|overlay_load_failed)' &&
   jq -e '
        .pluginKnown == true and
        .pluginDisabled == true and
        .barLayoutEmpty == true and
        .pluginCallResult == "not-loaded" and
        .quickScreenResult == "started" and
        .routerReachedCore == true and
        .pingResult == "ok" and
        .capturedMode == "full" and
        .capturedCount >= 1 and
        .captureStartable == true and
        .quickRegionResult == "started" and
        .regionStage == "region-selecting" and
        .isVisibleResult == "true"
   ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] disabled and layout-absent screenshot plugin still reaches the core service and starts a capture"
elif grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin' "$runtime_output" &&
     runtime_skip_if_environment_only "$runtime_output" \
         "[isolated-runtime] screenshot independence fixture (QuickShell could not create a disposable runtime)" \
         '\[SCREENSHOT\] (menu_load_failed|overlay_load_failed)'; then
    :
else
    details="$(tr '\n' ' ' <"$runtime_output")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] screenshot independence fixture failed (status=$runtime_status): $details"
fi
