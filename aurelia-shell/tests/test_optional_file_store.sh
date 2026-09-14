#!/usr/bin/env bash

# Optional user-owned files must not be modeled as missing FileViews. This
# suite exercises the real store's missing/read/write/re-read lifecycle in a
# disposable XDG tree and consumes the complete runtime log.

set -Eeuo pipefail

section "Aurelia Optional File Store"

store_root="$ROOT/services/OptionalFileStore.qml"
store_qmldir="$ROOT/services/qmldir"
fixture_root="$ROOT/tests/fixtures/optional-file-store"
false_value="false"
fileview_false_token="printErrors: ${false_value}"

if [[ -f "$store_root" && -f "$fixture_root/shell.qml" ]] &&
   grep -Fq 'OptionalFileStore 1.0 OptionalFileStore.qml' "$store_qmldir" &&
   grep -Fq 'stat' "$store_root" &&
   grep -Fq 'cat' "$store_root" &&
   grep -Fq 'stdinEnabled' "$store_root" &&
   grep -Fq 'mv -T' "$store_root" &&
   grep -Fq 'signal loadFailed' "$store_root" &&
   ! grep -Fq "$fileview_false_token" "$store_root"; then
    pass "[static] optional files use an explicit probed store with observable read/write failures"
else
    fail "[static] optional-file store boundary is incomplete or suppresses diagnostics"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] optional-file store QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" || true' RETURN
mkdir -p -- "$runtime_root/runtime" "$runtime_root/config" "$runtime_root/state" "$runtime_root/cache"
target_path="$runtime_root/config/aurelia/command-center.json"
result_path="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
: >"$result_path"
runtime_status=0

AURELIA_OPTIONAL_FILE_TARGET="$target_path" \
AURELIA_OPTIONAL_FILE_RESULT="$result_path" \
AURELIA_OPTIONAL_FILE_STORE_SOURCE="file://$store_root" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$result_path" ]] &&
   runtime_log_is_environment_only "$runtime_log" &&
   jq -e '
       .missingObserved == true and
       .firstRead == true and
       .secondRead == true and
       .writeFailed == false and
       .finalValue == "second\n" and
       .exists == true and
       .ready == true and
       .saveCount == 2
   ' "$result_path" >/dev/null &&
   [[ "$(cat "$target_path")" == "second" ]]; then
    pass "[isolated-runtime] absent optional file stays warning-free, then writes atomically and reloads deterministically"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_path" ]]; then details="$details result=$(tr '\n' ' ' <"$result_path")"; fi
    fail "[isolated-runtime] optional-file store fixture failed (status=$runtime_status): $details"
fi

consumer_result="$runtime_root/consumers-result.json"
consumer_log="$runtime_root/consumers.log"
consumer_status=0
consumer_config="$runtime_root/consumer-config"
mkdir -p -- "$consumer_config"
: >"$consumer_result"
AURELIA_OPTIONAL_APP_LIBRARY_SOURCE="file://$ROOT/services/AureliaAppLibrary.qml" \
AURELIA_OPTIONAL_COMMAND_CENTER_SOURCE="file://$ROOT/plugins/aurelia.launcher/ui/CommandCenterModuleRegistry.qml" \
AURELIA_OPTIONAL_MENU_SOURCE="file://$ROOT/plugins/aurelia.menu/MenuModel.qml" \
AURELIA_OPTIONAL_CONSUMERS_RESULT="$consumer_result" \
HOME="$runtime_root/home" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_CONFIG_HOME="$consumer_config" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CACHE_HOME="$runtime_root/cache" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/consumers.qml" --no-color >"$consumer_log" 2>&1 || consumer_status=$?

if [[ "$consumer_status" -eq 0 ]] && [[ -s "$consumer_result" ]] &&
   runtime_log_is_environment_only "$consumer_log" &&
   jq -e '.appLibraryLoaded == true and .commandCenterLoaded == true and .menuLoaded == true' \
       "$consumer_result" >/dev/null; then
    pass "[isolated-runtime] all optional-file consumers load with absent user files without QML warnings"
else
    details="$(tr '\n' ' ' <"$consumer_log")"
    if [[ -s "$consumer_result" ]]; then details="$details result=$(tr '\n' ' ' <"$consumer_result")"; fi
    fail "[isolated-runtime] optional-file consumer fixture failed (status=$consumer_status): $details"
fi

shell_config_result="$runtime_root/shell-config-result.json"
shell_config_log="$runtime_root/shell-config.log"
shell_config_status=0
mkdir -p -- "$runtime_root/shell-home" "$runtime_root/shell-config"
: >"$shell_config_result"
HOME="$runtime_root/shell-home" \
XDG_CONFIG_HOME="$runtime_root/shell-config" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CACHE_HOME="$runtime_root/cache" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
AURELIA_OPTIONAL_SHELL_CONFIG_SOURCE="$ROOT/services/ShellConfig.qml" \
AURELIA_OPTIONAL_SHELL_CONFIG_RESULT="$shell_config_result" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell-config.qml" --no-color \
    >"$shell_config_log" 2>&1 || shell_config_status=$?

if [[ "$shell_config_status" -eq 0 ]] && [[ -s "$shell_config_result" ]] &&
   runtime_log_is_environment_only "$shell_config_log" &&
   jq -e '.ready == true and .rawNonEmpty == true and .configHasBar == true and
          .bootstrapAttempted == true and .lastError == ""' \
       "$shell_config_result" >/dev/null &&
   [[ -f "$(jq -r '.configPath' "$shell_config_result")" ]]; then
    pass "[isolated-runtime] absent ShellConfig state bootstraps through the optional boundary without a missing-file warning"
else
    details="$(tr '\n' ' ' <"$shell_config_log")"
    if [[ -s "$shell_config_result" ]]; then details="$details result=$(tr '\n' ' ' <"$shell_config_result")"; fi
    fail "[isolated-runtime] absent ShellConfig bootstrap fixture failed (status=$shell_config_status): $details"
fi
