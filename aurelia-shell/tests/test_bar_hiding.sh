#!/usr/bin/env bash

# T41 persistent bar hiding, exact shortcut, and Menu Bar contract checks.
# All state and IPC fixtures are disposable; no live shell or compositor is
# contacted by this suite.

set -Eeuo pipefail

section "Aurelia Persistent Bar Hiding"

bar_root="$ROOT/plugins/aurelia.bar"
bar_file="$bar_root/Bar.qml"
watcher_file="$bar_root/BarHiddenWatcher.qml"
bar_module="$ROOT/bin/lib/aurelia-plugin/bar.sh"
hidden_module="$ROOT/bin/lib/aurelia-plugin/hidden.sh"
hidden_writer="$ROOT/bin/aurelia-bar-hidden"
toggle_bin="$ROOT/bin/aurelia-toggle-bar"
bar_cli="$ROOT/bin/aurelia-bar"
binding_file="$bar_root/keybindings.lua"
menu_file="$ROOT/plugins/aurelia.menu/menu.json"
menu_model="$ROOT/plugins/aurelia.menu/MenuModel.qml"

if [[ -x "$hidden_writer" && -x "$toggle_bin" && -f "$hidden_module" && -f "$bar_module" ]] &&
   grep -Fq 'on|off|toggle' "$hidden_module" &&
   grep -Fq 'aurelia_bar_hidden' "$hidden_module" &&
   grep -Fq 'aurelia-bar-hidden' "$toggle_bin" &&
   grep -Fq 'hidden' "$bar_cli"; then
    pass "[static] Aurelia exposes one validated bar-hidden writer through the dedicated toggle command and bar CLI"
else
    fail "[static] bar-hidden command boundary or on/off/toggle vocabulary is incomplete"
fi

if [[ -f "$watcher_file" ]] &&
   grep -Fq 'hiddenStatePath' "$bar_file" &&
   grep -Fq 'hiddenStateDirectory' "$bar_file" &&
   grep -Fq 'hiddenStateWatcher' "$bar_file" &&
   grep -Fq 'inotifywait' "$watcher_file" &&
   grep -Fq 'SplitParser' "$watcher_file" &&
   grep -Fq 'syncHidden' "$bar_file" &&
   grep -Fq 'hidden_state_watcher_failed' "$watcher_file" &&
   grep -Fq 'ExclusionMode.Ignore' "$bar_file" &&
   grep -Fq 'visible: true' "$bar_file" &&
   ! grep -Fq 'FileView' "$bar_file"; then
    pass "[static] bar hiding uses the runtime-supported parent watcher, keeps the surface mapped, and leaves diagnostics enabled"
else
    fail "[static] resident bar hidden-state watcher or truthful diagnostic boundary is incomplete"
fi

if [[ -f "$binding_file" ]] &&
   grep -Fq 'SUPER + SHIFT + SPACE' "$binding_file" &&
   grep -Fq 'aurelia.bar' "$binding_file" &&
   grep -Fq 'action_type = "plugin_ipc"' "$binding_file" &&
   grep -Fq 'method = "toggle"' "$binding_file"; then
    pass "[static] the bar plugin owns the exact Super + Shift + Space structured IPC binding"
else
    fail "[static] exact persistent-bar keybinding declaration is incomplete"
fi

if command -v luajit >/dev/null 2>&1; then
    binding_result="$(luajit - "$ROOT/dotfiles/hypr/keybindings_manifest.lua" <<'LUA'
local manifest = dofile(arg[1])
local found = 0
local seen = {}
for _, item in ipairs(manifest.bindings or {}) do
    if item.key then
        local key = string.lower((item.key:gsub("%s+", "")))
        assert(not seen[key], "duplicate key: " .. item.key)
        seen[key] = true
    end
    if item.id == "aurelia.bar.toggle_hidden" then
        found = found + 1
        assert(item.key == "SUPER + SHIFT + SPACE")
        assert(item.action_type == "plugin_ipc")
        assert(item.target == "aurelia.bar")
        assert(item.method == "toggle")
        assert(type(item.command_argv) == "table" and #item.command_argv == 5)
        assert(item.command_argv[2] == "shell" and item.command_argv[3] == "toggle")
        assert(item.command_argv[4] == "aurelia.bar" and item.command_argv[5] == "{}")
    end
end
assert(found == 1, "bar hidden binding count")
print("ok")
LUA
)"
    if [[ "$binding_result" == "ok" ]]; then
        pass "[isolated-manifest] effective binding loader registers exactly one structured bar toggle without key conflicts"
    else
        fail "[isolated-manifest] exact bar toggle binding failed manifest resolution: $binding_result"
    fi
else
    skip "[isolated-manifest] exact bar toggle manifest resolution (luajit unavailable)"
fi

if jq -e '
       any(.items[]; .id == "style.bar" and .provider == "bar" and .label == "Menu Bar")
   ' "$menu_file" >/dev/null 2>&1 &&
   grep -Fq 'allowedProviders' "$menu_model" &&
   grep -Fq 'bar-position-top' "$menu_model" &&
   grep -Fq 'bar-transparent-toggle' "$menu_model" &&
   grep -Fq 'bar-defaults' "$menu_model"; then
    pass "[static] shipped menu data exposes the validated Menu Bar provider and safe control actions"
else
    fail "[static] Menu Bar provider data or safe action allow-list is incomplete"
fi

state_root="$(mktemp -d)"
trap 'rm -rf -- "$state_root" 2>/dev/null || true' RETURN
mkdir -p -- "$state_root/home" "$state_root/state" "$state_root/config" "$state_root/cache"
sync_log="$state_root/sync.log"
touch "$sync_log"
cp -- "$ROOT/tests/fixtures/bar-hiding/fake-shell" "$state_root/fake-shell"
chmod 0755 "$state_root/fake-shell"

run_hidden() {
    HOME="$state_root/home" \
    XDG_STATE_HOME="$state_root/state" \
    WORKSTATION_TEST_MODE=1 \
    AURELIA_BAR_HIDDEN_SYNC_CLIENT="$state_root/fake-shell" \
    AURELIA_BAR_HIDDEN_SYNC_LOG="$sync_log" \
    AURELIA_BAR_HIDDEN_SYNC_STATUS="${AURELIA_BAR_HIDDEN_SYNC_STATUS:-0}" \
        "$hidden_writer" "$@"
}

state_file="$state_root/state/aurelia/toggles/bar-off"
read_status=0
read_output="$(run_hidden read 2>"$state_root/read.err")" || read_status=$?
if [[ "$read_status" -eq 0 && "$read_output" == "visible" ]]; then
    pass "[isolated-state] missing bar-hidden state is a valid visible default"
else
    fail "[isolated-state] missing bar-hidden state was not parsed as visible (status=$read_status output=$read_output)"
fi

on_status=0
run_hidden on >"$state_root/on.out" 2>"$state_root/on.err" || on_status=$?
if [[ "$on_status" -eq 0 && -f "$state_file" && ! -L "$state_file" &&
      "$(<"$state_file")" == "hidden" && "$(run_hidden read)" == "hidden" ]]; then
    pass "[isolated-state] on atomically creates a regular hidden marker and read returns hidden"
else
    fail "[isolated-state] on did not create a valid hidden marker (status=$on_status)"
fi

marker_identity_before="$(stat -c '%d:%i:%s:%Y' -- "$state_file")"
run_hidden on >/dev/null
marker_identity_after="$(stat -c '%d:%i:%s:%Y' -- "$state_file")"
if [[ "$marker_identity_before" == "$marker_identity_after" ]]; then
    pass "[isolated-state] repeated on is idempotent and does not replace an already-correct marker"
else
    fail "[isolated-state] repeated on rewrote an already-correct marker"
fi

run_hidden off >/dev/null
if [[ ! -e "$state_file" && ! -L "$state_file" && "$(run_hidden read)" == "visible" ]]; then
    pass "[isolated-state] off removes only the validated marker and is visible after read"
else
    fail "[isolated-state] off did not converge to the visible state"
fi

run_hidden toggle >/dev/null
first_toggle="$(run_hidden read)"
run_hidden toggle >/dev/null
second_toggle="$(run_hidden read)"
if [[ "$first_toggle" == "hidden" && "$second_toggle" == "visible" ]]; then
    pass "[isolated-state] toggle has deterministic missing/hidden transitions"
else
    fail "[isolated-state] toggle transition sequence is incorrect: $first_toggle -> $second_toggle"
fi

mkdir -p -- "$(dirname -- "$state_file")"
printf '%s\n' 'unexpected-state' >"$state_file"
malformed_status=0
malformed_output="$(run_hidden read 2>"$state_root/malformed.err")" || malformed_status=$?
if [[ "$malformed_status" -ne 0 && "$malformed_output" == "visible" &&
      "$malformed_output$(<"$state_root/malformed.err")" == *"malformed"* ]]; then
    pass "[isolated-state] malformed state fails closed to visible and remains observable"
else
    fail "[isolated-state] malformed state was not rejected truthfully (status=$malformed_status output=$malformed_output)"
fi

symlink_target="$state_root/target"
printf '%s\n' 'target-preserved' >"$symlink_target"
rm -f -- "$state_file"
ln -s -- "$symlink_target" "$state_file"
symlink_status=0
run_hidden on >"$state_root/symlink.out" 2>"$state_root/symlink.err" || symlink_status=$?
if [[ "$symlink_status" -ne 0 && -L "$state_file" && -f "$symlink_target" &&
      "$(<"$symlink_target")" == "target-preserved" ]]; then
    pass "[isolated-state] symlinked state is rejected without following or replacing the target"
else
    fail "[isolated-state] symlinked state was not rejected safely"
fi
rm -f -- "$state_file"

rapid_status=0
for operation in on off on off on off on; do
    run_hidden "$operation" >/dev/null || rapid_status=$?
done
if [[ "$rapid_status" -eq 0 && "$(run_hidden read)" == "hidden" &&
      -z "$(find "$state_root/state" -type f -name '.bar-off.*' -print -quit)" ]]; then
    pass "[isolated-state] rapid sequential transitions converge with no atomic staging residue"
else
    fail "[isolated-state] rapid transitions left incorrect state or staging residue"
fi

if [[ -x /usr/bin/inotifywait ]]; then
    watch_root="$state_root/watch"
    watch_log="$state_root/watch.log"
    mkdir -p -- "$watch_root"
    watch_status=0
    /usr/bin/timeout --kill-after=1s 3s /usr/bin/inotifywait -m -q \
        -e close_write,create,delete,move --format '%e %f' "$watch_root" \
        >"$watch_log" 2>&1 &
    watch_pid=$!
    sleep 0.1
    printf '%s\n' hidden >"$watch_root/bar-off"
    rm -f -- "$watch_root/bar-off"
    wait "$watch_pid" || watch_status=$?
    if [[ "$watch_status" -eq 124 ]] &&
       grep -Eq 'CREATE.*bar-off|CLOSE_WRITE.*bar-off|DELETE.*bar-off' "$watch_log"; then
        pass "[isolated-state] parent-directory event stream observes first creation and removal of the hidden marker"
    else
        fail "[isolated-state] parent-directory watcher did not observe hidden-marker transitions"
    fi
else
    skip "[isolated-state] parent-directory watcher event stream (inotifywait unavailable)"
fi

watcher_runtime_root="$state_root/watcher-runtime"
mkdir -p -- "$watcher_runtime_root/runtime" "$watcher_runtime_root/state" \
    "$watcher_runtime_root/config" "$watcher_runtime_root/cache" \
    "$watcher_runtime_root/events"
watcher_result="$watcher_runtime_root/result.json"
watcher_log="$watcher_runtime_root/runtime.log"
watcher_status=0
AURELIA_BAR_WATCHER_SOURCE="file://$watcher_file" \
AURELIA_BAR_WATCHER_DIRECTORY="$watcher_runtime_root/events" \
AURELIA_BAR_WATCHER_RESULT="$watcher_result" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$watcher_runtime_root/runtime" \
XDG_STATE_HOME="$watcher_runtime_root/state" \
XDG_CONFIG_HOME="$watcher_runtime_root/config" \
XDG_CACHE_HOME="$watcher_runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-hiding/watcher.qml" >"$watcher_log" 2>&1 || watcher_status=$?
if [[ "$watcher_status" -eq 0 ]] && [[ -s "$watcher_result" ]] &&
   jq -e '.loaded == true and .watcherAvailable == true and .syncEvents >= 2' \
       "$watcher_result" >/dev/null 2>&1 &&
   runtime_log_is_environment_only "$watcher_log"; then
    pass "[isolated-runtime] the real parent-directory watcher observes marker creation/removal without a PanelWindow"
else
    details="$(tail -n 40 "$watcher_log" 2>/dev/null || true)"
    if [[ -s "$watcher_result" ]]; then details="$details result=$(tr '\n' ' ' <"$watcher_result")"; fi
    fail "[isolated-runtime] parent-directory watcher fixture failed (status=$watcher_status): $details"
fi

sync_failure_status=0
AURELIA_BAR_HIDDEN_SYNC_STATUS=17 run_hidden off >"$state_root/sync-failure.out" 2>"$state_root/sync-failure.err" || sync_failure_status=$?
if [[ "$sync_failure_status" -ne 0 && ! -e "$state_file" && ! -L "$state_file" &&
      "$(<"$state_root/sync-failure.err")" == *"sync"* ]]; then
    pass "[isolated-state] resident sync failure is reported after the state commit"
else
    fail "[isolated-state] resident sync failure was hidden or state commit was lost"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] bar-hidden QuickShell fixtures (qs or timeout unavailable)"
    return 0
fi

menu_root="$state_root/menu"
mkdir -p -- "$menu_root/runtime" "$menu_root/state" "$menu_root/config/aurelia" "$menu_root/cache"
jq -n '{version:1,items:[
    {id:"user.custom",label:"Custom",description:"User extension",action:"open-command-center",order:5},
    {id:"user.invalid",label:"Invalid",action:"systemctl reboot",order:6}
]}' >"$menu_root/config/aurelia/menu.json"
menu_result="$menu_root/result.json"
menu_log="$menu_root/runtime.log"
menu_status=0
AURELIA_MENU_MODEL_SOURCE="$menu_model" \
AURELIA_MENU_MODEL_RESULT="$menu_result" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$menu_root/runtime" XDG_STATE_HOME="$menu_root/state" \
XDG_CONFIG_HOME="$menu_root/config" XDG_CACHE_HOME="$menu_root/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-hiding/menu.qml" >"$menu_log" 2>&1 || menu_status=$?

if [[ "$menu_status" -eq 0 ]] && jq -e '
       .menuBarToggle and .toggleChecked and .toggleAccepted and
       .positionAccepted and .transparencyAccepted and .defaultsAccepted and
       .userExtension and .invalidRejected and
       .lastAction == "bar-defaults"
   ' "$menu_result" >/dev/null 2>&1; then
    pass "[isolated-runtime] Menu Bar controls dispatch through safe shell APIs, expose checked state, and preserve user extensions"
elif grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin' "$menu_log" &&
     runtime_skip_if_environment_only "$menu_log" "[isolated-runtime] Menu Bar model fixture could not create a disposable QuickShell surface"; then
    :
else
    details="$(tail -n 32 "$menu_log" 2>/dev/null || true)"
    if [[ -s "$menu_result" ]]; then details="$details result=$(tr '\n' ' ' <"$menu_result")"; fi
    fail "[isolated-runtime] Menu Bar model fixture failed (status=$menu_status): $details"
fi

bar_root_runtime="$state_root/bar"
mkdir -p -- "$bar_root_runtime/runtime" "$bar_root_runtime/state" "$bar_root_runtime/config" "$bar_root_runtime/cache"
bar_result="$bar_root_runtime/result.json"
bar_log="$bar_root_runtime/runtime.log"
bar_status=0
HOME="$bar_root_runtime/home" \
XDG_RUNTIME_DIR="$bar_root_runtime/runtime" XDG_STATE_HOME="$bar_root_runtime/state" \
XDG_CONFIG_HOME="$bar_root_runtime/config" XDG_CACHE_HOME="$bar_root_runtime/cache" \
AURELIA_BAR_HIDING_RESULT="$bar_result" \
AURELIA_BAR_HIDING_SOURCE="file://$bar_file" \
AURELIA_BAR_HIDING_WRITER="$hidden_writer" \
AURELIA_BAR_HIDDEN_SYNC_CLIENT="$state_root/fake-shell" \
AURELIA_BAR_HIDDEN_SYNC_LOG="$sync_log" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-hiding/bar.qml" >"$bar_log" 2>&1 || bar_status=$?

if [[ "$bar_status" -eq 0 ]] && jq -e '
       .loaded and .initialVisible and .hidden and .hiddenVisible and
       .hiddenExclusion and .hiddenOffscreen and .restored and
       .restoredExclusion and .widgetBefore == "healthy" and
       .widgetAfter == "healthy" and .writerFailureReported == false
   ' "$bar_result" >/dev/null 2>&1; then
    pass "[isolated-runtime] mapped bar hides off-screen, removes exclusion, restores in place, and keeps healthy widget routing alive"
elif grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|No PanelWindow backend loaded' "$bar_log" &&
     runtime_skip_if_environment_only "$bar_log" "[isolated-runtime] bar-hidden surface fixture could not create a disposable window backend"; then
    :
else
    details="$(tail -n 48 "$bar_log" 2>/dev/null || true)"
    if [[ -s "$bar_result" ]]; then details="$details result=$(tr '\n' ' ' <"$bar_result")"; fi
    fail "[isolated-runtime] bar-hidden surface fixture failed (status=$bar_status): $details"
fi
