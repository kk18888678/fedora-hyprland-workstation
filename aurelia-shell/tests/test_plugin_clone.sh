#!/usr/bin/env bash

# T17 built-in clone, provenance, compatibility, and recovery checks.

set -Eeuo pipefail

section "Aurelia Built-in Plugin Cloning"

cli_root="$ROOT/bin/lib/aurelia-plugin"
clone_root="$ROOT/tests/fixtures/plugin-clone"
state_source="$ROOT/services/ShellConfig.qml"
clone_state_source="$ROOT/services/PluginCloneState.qml"

if [[ -f "$cli_root/clone.sh" ]] &&
   grep -q 'clone <aurelia.plugin-id>' "$ROOT/bin/lib/aurelia-plugin/main.sh" &&
   grep -q 'for module in common placement manifest main clone' "$ROOT/bin/aurelia-plugin" &&
   grep -q 'clonedFrom' "$ROOT/bin/lib/aurelia-plugin/manifest.sh"; then
    pass "[static] clone lifecycle is a separate CLI module with validated provenance metadata"
else
    fail "[static] clone CLI module or provenance metadata is missing"
fi

if grep -q 'function enableClonePluginInConfig' "$clone_state_source" &&
   grep -q 'function restoreCloneInConfig' "$clone_state_source" &&
   grep -q 'cloneSourceRestores' "$state_source" &&
   grep -q 'function resolveEnabledId' "$ROOT/services/PluginRegistry.qml" &&
   grep -q 'function resolvePluginId' "$ROOT/services/PluginHost.qml" &&
   grep -q 'compatibilityId' "$ROOT/services/PluginRegistryApi.qml" &&
   grep -q 'compatibilityId' "$ROOT/services/PluginShellApi.qml"; then
    pass "[static] clone state restoration and stable source-ID routing are host-owned"
else
    fail "[static] clone state or source-ID compatibility wiring is incomplete"
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$runtime_root/bin" "$runtime_root/first-party" "$runtime_root/home"
cp -a -- "$clone_root/first-party/." "$runtime_root/first-party/"
cp -- "$clone_root/fake-aurelia-shell" "$runtime_root/bin/aurelia-shell"
cp -- "$clone_root/fake-editor" "$runtime_root/bin/fake-editor"
chmod 0755 "$runtime_root/bin/aurelia-shell" "$runtime_root/bin/fake-editor"
calls="$runtime_root/calls"
touch "$calls"

plugin_command() {
    AURELIA_FIRST_PARTY_PLUGIN_DIR="$runtime_root/first-party" \
    AURELIA_PLUGIN_DIR="$runtime_root/home/plugins" \
    AURELIA_PLUGIN_BIN_DIR="$runtime_root/bin" \
    AURELIA_DEVELOPMENT_MODE=1 \
    FAKE_CALLS="$calls" \
    FAKE_NO_DISCOVERY="${FAKE_NO_DISCOVERY:-0}" \
    FAKE_ENABLE_FAIL="${FAKE_ENABLE_FAIL:-0}" \
    HOME="$runtime_root/home" USER=tester \
    bash -c '
        set -Eeuo pipefail
        module_root="$1"
        shift
        source "$module_root/common.sh"
        source "$module_root/placement.sh"
        source "$module_root/manifest.sh"
        source "$module_root/main.sh"
        source "$module_root/clone.sh"
        source "$module_root/lifecycle.sh"
        aurelia_plugin_main "$@"
    ' _ "$cli_root" "$@"
}

clone_command() {
    plugin_command clone "$@"
}

source_hash_before="$(sha256sum "$runtime_root/first-party/aurelia.clock/Clock.qml" | awk '{print $1}')"
mkdir -p -- "$runtime_root/home/plugins/tester.clock"
printf '%s\n' 'user-owned collision sentinel' >"$runtime_root/home/plugins/tester.clock/sentinel"

clock_output="$(clone_command aurelia.clock)"
clock_target="$runtime_root/home/plugins/tester.clock.1"
if [[ -f "$clock_target/manifest.json" && -f "$clock_target/Clock.qml" &&
      -f "$clock_target/Model.js" && -f "$clock_target/nested/Panel.qml" &&
      -f "$runtime_root/home/plugins/tester.clock/sentinel" ]]; then
    pass "[isolated-runtime] clone copies the complete first-party tree and leaves collisions untouched"
else
    fail "[isolated-runtime] complete clone or collision preservation failed"
fi

if jq -e '
    .id == "tester.clock.1" and
    .name == "My Clock" and
    .barWidget.displayName == "My Clock" and
    .aurelia.clonedFrom == "aurelia.clock" and
    (.aurelia.clonePaths? == null) and
    (.aurelia.capabilities? == null)
  ' "$clock_target/manifest.json" >/dev/null &&
   grep -qF 'aurelia.clock' "$clock_target/Clock.qml" &&
   grep -q '^enable .*tester.clock.1' "$calls" &&
   [[ "$clock_output" == *"switched to tester.clock.1"* ]]; then
    pass "[isolated-runtime] clone rewrites identity/provenance while preserving stable source IPC ids"
else
    fail "[isolated-runtime] clone manifest, stable id, or enablement contract failed"
fi

multi_output="$(clone_command aurelia.multi)"
multi_target="$runtime_root/home/plugins/tester.multi"
if [[ -f "$multi_target/manifest.json" && -f "$multi_target/Menu.qml" &&
      -f "$multi_target/Widget.qml" && -f "$multi_target/copied/Helper.js" &&
      ! -e "$multi_target/shared" ]] &&
   grep -qF 'copied/Helper.js' "$multi_target/Widget.qml" &&
   jq -e '
       .id == "tester.multi" and
       .kinds == ["menu", "bar-widget"] and
       .entryPoints.menu == "Menu.qml" and
       .entryPoints.barWidget == "Widget.qml" and
       .aurelia.clonedFrom == "aurelia.multi" and
       (.aurelia.clonePaths? == null)
     ' "$multi_target/manifest.json" >/dev/null &&
   [[ "$multi_output" == *"switched to tester.multi"* ]]; then
    pass "[isolated-runtime] sibling manifests copy declared dependencies and preserve all plugin kinds"
else
    fail "[isolated-runtime] sibling-manifest dependency clone failed"
fi

source_hash_after="$(sha256sum "$runtime_root/first-party/aurelia.clock/Clock.qml" | awk '{print $1}')"
if [[ "$source_hash_before" == "$source_hash_after" ]]; then
    pass "[isolated-runtime] cloning never edits packaged first-party source"
else
    fail "[isolated-runtime] first-party source changed during cloning"
fi

if clone_command aurelia.multi custom.multi >/dev/null 2>&1; then
    fail "[isolated-runtime] clone accepts a caller-supplied custom id"
else
    [[ ! -e "$runtime_root/home/plugins/custom.multi" ]] &&
        pass "[isolated-runtime] clone derives a user-owned id and rejects custom ids" ||
        fail "[isolated-runtime] rejected custom clone id left a target behind"
fi

if clone_command acme.example >/dev/null 2>&1; then
    fail "[isolated-runtime] clone accepts a third-party source id"
else
    pass "[isolated-runtime] clone is restricted to the first-party aurelia namespace"
fi

if clone_command >/dev/null 2>&1; then
    fail "[isolated-runtime] clone accepts a missing source id"
else
    pass "[isolated-runtime] clone requires an explicit source id"
fi

if EDITOR="$runtime_root/bin/fake-editor" clone_command aurelia.clock --edit >/dev/null 2>&1 &&
   grep -qF "editor $runtime_root/home/plugins/tester.clock.2" "$calls"; then
    pass "[isolated-runtime] clone --edit opens the collision-safe clone through argv"
else
    fail "[isolated-runtime] clone --edit did not open the expected target"
fi

remove_output="$(plugin_command remove tester.clock.2 --yes)"
if [[ ! -e "$runtime_root/home/plugins/tester.clock.2" ]] &&
   grep -q 'set .*tester.clock.2 false' "$calls" &&
   [[ "$remove_output" == *"Removed tester.clock.2."* ]]; then
    pass "[isolated-runtime] removal disables an active clone before deleting its source"
else
    fail "[isolated-runtime] clone removal did not use the disable-before-delete boundary"
fi

mkdir -p -- "$runtime_root/first-party/aurelia.invalid"
printf '%s\n' '{"schemaVersion":1,"id":"aurelia.invalid","name":"Invalid","version":"1.0.0","description":"Invalid","kinds":["bar-widget"],"entryPoints":{"barWidget":"../unsafe.qml"},"barWidget":{"displayName":"Invalid","description":"Invalid","category":"Testing","allowMultiple":false,"defaultSection":"center"}}' \
    >"$runtime_root/first-party/aurelia.invalid/manifest.json"
if clone_command aurelia.invalid >/dev/null 2>&1; then
    fail "[isolated-runtime] clone accepts an invalid first-party manifest"
else
    [[ ! -e "$runtime_root/home/plugins/tester.invalid" ]] &&
        pass "[isolated-runtime] invalid source validation fails before publication" ||
        fail "[isolated-runtime] invalid source left a clone target behind"
fi

if clone_command aurelia.missing >/dev/null 2>&1; then
    fail "[isolated-runtime] clone succeeds with a missing declared dependency"
else
    if [[ ! -e "$runtime_root/home/plugins/tester.missing" ]]; then
        pass "[isolated-runtime] missing dependency failure cleans staged clone state"
    else
        fail "[isolated-runtime] missing dependency left a partial clone"
    fi
fi

mkdir -p -- "$runtime_root/first-party/aurelia.symlink"
jq -n '{schemaVersion:1,id:"aurelia.symlink",name:"Symlink",version:"1.0.0",description:"Symlink",kinds:["bar-widget"],entryPoints:{barWidget:"Widget.qml"},barWidget:{displayName:"Symlink",description:"Symlink",category:"Testing",allowMultiple:false,defaultSection:"center"}}' \
    >"$runtime_root/first-party/aurelia.symlink/manifest.json"
cp -- "$runtime_root/first-party/aurelia.clock/Clock.qml" "$runtime_root/first-party/aurelia.symlink/Widget.qml"
ln -s -- Clock.qml "$runtime_root/first-party/aurelia.symlink/Link.qml"
if clone_command aurelia.symlink >/dev/null 2>&1; then
    fail "[isolated-runtime] clone accepts a symlinked first-party source tree"
else
    [[ ! -e "$runtime_root/home/plugins/tester.symlink" ]] &&
        pass "[isolated-runtime] symlinked source failure is rejected before publication" ||
        fail "[isolated-runtime] symlinked source left a target behind"
fi

if FAKE_NO_DISCOVERY=1 clone_command aurelia.clock >/dev/null 2>&1; then
    fail "[isolated-runtime] clone succeeds when resident discovery does not report it"
else
    [[ ! -e "$runtime_root/home/plugins/tester.clock.2" ]] &&
        pass "[isolated-runtime] discovery failure removes the published clone" ||
        fail "[isolated-runtime] discovery failure left a partial clone"
fi

if FAKE_ENABLE_FAIL=1 clone_command aurelia.multi >/dev/null 2>&1; then
    fail "[isolated-runtime] clone succeeds after resident enablement failure"
else
    if [[ ! -e "$runtime_root/home/plugins/tester.multi.1" ]] &&
       grep -q 'set .*tester.multi.1' "$calls"; then
        pass "[isolated-runtime] enablement failure confirms rollback before clone cleanup"
    else
        fail "[isolated-runtime] enablement failure did not cleanly roll back"
    fi
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] clone state and facade QuickShell fixtures (qs or timeout unavailable)"
    pass "[skipped:isolated-runtime] clone source-ID facade alias fixture (qs or timeout unavailable)"
    return 0
fi

state_runtime="$runtime_root/state-runtime"
mkdir -p -- "$state_runtime/config" "$state_runtime/runtime" "$state_runtime/state" "$state_runtime/cache"
state_result="$state_runtime/result.json"
state_status=0
AURELIA_CLONE_STATE_CONFIG_SOURCE="$state_source" \
AURELIA_CLONE_STATE_RESULT="$state_result" \
AURELIA_SHELL_CONFIG="$state_runtime/config/shell.json" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$state_runtime/runtime" XDG_STATE_HOME="$state_runtime/state" \
XDG_CONFIG_HOME="$state_runtime/config" XDG_CACHE_HOME="$state_runtime/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$clone_root/state.qml" >"$state_runtime/state.log" 2>&1 || state_status=$?
if [[ "$state_status" -eq 0 ]] && jq -e '
    .clockEnable and .clockCloneId == "tester.clock" and .clockSettings == "HH:mm" and
    .clockRecordSource == "aurelia.clock" and .clockSourceBarPresent and .clockDisable and
    .clockRestoredId == "aurelia.clock" and .clockRestoredSettings == "HH:mm" and
    .clockRestoresCleared and .notificationsEnable and .notificationsSourceDisabled and
    .notificationsRecordSource == "aurelia.notifications" and .notificationsDisable and
    .notificationsRestoredId == "aurelia.clock" and .notificationsPluginRemoved and
    .notificationsRestoresCleared and .barEnable and .activeCloneBar == "tester.bar" and
    .barRecordSource == "aurelia.bar" and .barDisable and .activeRestoredBar == "aurelia.bar"
  ' "$state_result" >/dev/null; then
    pass "[isolated-runtime] clone enable/disable preserves settings, placement, active bar, and source restoration"
else
    details="$(tail -n 25 "$state_runtime/state.log" 2>/dev/null || true)"
    fail "[isolated-runtime] clone state fixture failed (status=$state_status): $details"
fi

facade_runtime="$runtime_root/facade-runtime"
mkdir -p -- "$facade_runtime/runtime" "$facade_runtime/state" "$facade_runtime/config" "$facade_runtime/cache"
facade_result="$facade_runtime/result.json"
facade_status=0
AURELIA_CLONE_REGISTRY_API_SOURCE="$ROOT/services/PluginRegistryApi.qml" \
AURELIA_CLONE_SHELL_API_SOURCE="$ROOT/services/PluginShellApi.qml" \
AURELIA_CLONE_BAR_API_SOURCE="$ROOT/services/PluginBarApi.qml" \
AURELIA_CLONE_FACADES_RESULT="$facade_result" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$facade_runtime/runtime" XDG_STATE_HOME="$facade_runtime/state" \
XDG_CONFIG_HOME="$facade_runtime/config" XDG_CACHE_HOME="$facade_runtime/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$clone_root/facades.qml" >"$facade_runtime/facade.log" 2>&1 || facade_status=$?
if [[ "$facade_status" -eq 0 ]] && jq -e '
    .registrySourceKnown and .registrySourceEnabled and .registryForeignRejected and
    .shellSourceOwns and .shellForeignRejected and .barSourceAccepted and .barForeignRejected
  ' "$facade_result" >/dev/null; then
    pass "[isolated-runtime] cloned source IPC aliases remain owner-scoped in every facade"
else
    details="$(tail -n 25 "$facade_runtime/facade.log" 2>/dev/null || true)"
    fail "[isolated-runtime] clone facade alias fixture failed (status=$facade_status): $details"
fi
