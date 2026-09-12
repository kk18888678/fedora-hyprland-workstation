#!/usr/bin/env bash

# T27 compatibility-cutover invariants. Legacy reads remain enabled; only
# isolated temporary state is migrated or written by this test.

set -Eeuo pipefail

section "Aurelia Plugin Compatibility Cutover"

config_root="$ROOT/services/ShellConfig.qml"
registry_root="$ROOT/services/PluginRegistry.qml"
manifest_root="$ROOT/bin/lib/aurelia-plugin/manifest.sh"
host_root="$ROOT/services/PluginHost.qml"

if grep -q 'function normalize(candidate)' "$config_root" &&
   grep -q 'function normalizePluginEntries' "$config_root" &&
   grep -q 'function migrate()' "$config_root" &&
   grep -q 'sourceWasCanonicalVersion' "$config_root" &&
   grep -q 'atomicWrites: true' "$config_root" &&
   grep -q 'entryPointKeyForKind' "$registry_root" &&
   grep -q 'bar-widget' "$manifest_root"; then
    pass "[static] legacy state and legacy bar-widget manifest reads remain enabled through the canonical cutover"
else
    fail "[static] compatibility read boundary is incomplete"
fi

if grep -q 'function serializeConfig' "$config_root" &&
   grep -q 'function persistConfig' "$config_root" &&
   grep -q 'migrationBackupPath' "$config_root" &&
   grep -q 'defaultBarConfig' "$config_root" &&
   grep -q 'defaultBarId: "aurelia.bar"' "$host_root" &&
   [[ -f "$ROOT/config/bar-default.json" ]]; then
    pass "[static] canonical writes, recoverable migration backup, and built-in bar ownership are explicit"
else
    fail "[static] canonical write or built-in fallback boundary is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] compatibility cutover QuickShell fixtures (qs or timeout unavailable)"
    return 0
fi

cutover_root="$(mktemp -d)"
trap 'rm -rf -- "$cutover_root" 2>/dev/null || true' RETURN
cutover_result="$cutover_root/probe-result.json"
cutover_log="$cutover_root/probe.log"
cutover_status=0
AURELIA_CUTOVER_CONFIG_SOURCE="$config_root" \
AURELIA_CUTOVER_RESULT="$cutover_result" \
AURELIA_SHELL_CONFIG="$cutover_root/empty-shell.json" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$cutover_root/probe-runtime" \
XDG_STATE_HOME="$cutover_root/probe-state" \
XDG_CONFIG_HOME="$cutover_root/probe-config" \
XDG_CACHE_HOME="$cutover_root/probe-cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-cutover/shell.qml" \
    >"$cutover_log" 2>&1 || cutover_status=$?

if [[ "$cutover_status" -eq 0 ]] && [[ -s "$cutover_result" ]] &&
   jq -e '
       .defaultThirdPartyDisabled == true and
       .defaultFirstPartyEnabled == true and
       .explicitThirdPartyEnabled == true and
       .explicitlyDisabledThirdParty == true and
       .builtInBarDefault == true and
       .serializedDefaultVersion == 1 and
       .serializedDefaultBar == "aurelia.bar"
   ' "$cutover_result" >/dev/null 2>&1; then
    pass "[isolated-runtime] first-party defaults, explicit third-party enablement, disablement, canonical serialization, and built-in bar default converge"
else
    details="$(tail -n 32 "$cutover_log" 2>/dev/null || true)"
    if [[ -s "$cutover_result" ]]; then details="$details result=$(tr '\n' ' ' <"$cutover_result")"; fi
    fail "[isolated-runtime] enablement/default cutover probe failed (status=$cutover_status): $details"
fi

legacy_config="$cutover_root/legacy-shell.json"
legacy_backup="$legacy_config.pre-migration.bak"
legacy_result="$cutover_root/legacy-result.json"
legacy_log="$cutover_root/legacy.log"
jq -n '{
    version: 1,
    plugins: [
        "example.panel",
        {id: "example.settings", settings: {mode: "fast"}, customValue: 7}
    ],
    disabledPlugins: ["aurelia.clock"],
    bar: {
        id: "aurelia.bar",
        position: "top",
        transparent: false,
        centerAnchor: "aurelia.clock",
        layout: {
            left: ["aurelia.workspaces"],
            center: [{id: "aurelia.clock", settings: {format: "HH:mm"}}],
            right: []
        }
    },
    userOwned: {preserve: true}
}' >"$legacy_config"
legacy_original_hash="$(sha256sum "$legacy_config" | awk '{print $1}')"
legacy_status=0
AURELIA_STATE_CONFIG_SOURCE="$config_root" \
AURELIA_STATE_RESULT="$legacy_result" \
AURELIA_SHELL_CONFIG="$legacy_config" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$cutover_root/legacy-runtime" \
XDG_STATE_HOME="$cutover_root/legacy-state" \
XDG_CONFIG_HOME="$cutover_root/legacy-config" \
XDG_CACHE_HOME="$cutover_root/legacy-cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/state-migration/shell.qml" \
    >"$legacy_log" 2>&1 || legacy_status=$?
legacy_backup_hash=""
if [[ -f "$legacy_backup" ]]; then legacy_backup_hash="$(sha256sum "$legacy_backup" | awk '{print $1}')"; fi

if [[ "$legacy_status" -eq 0 ]] && [[ -s "$legacy_result" ]] &&
   [[ "$legacy_backup_hash" == "$legacy_original_hash" ]] &&
   jq -e '
       .migrationNeededBefore == true and
       .migrationReturn == "pending" and
       .migrationResult == "migrated" and
       .migrationNeededAfter == false and
       .config.plugins[0].id == "example.panel" and
       .config.plugins[1].mode == "fast" and
       .config.plugins[1].settings == null and
       .config.bar.layout.center[0].format == "HH:mm" and
       .config.userOwned.preserve == true
   ' "$legacy_result" >/dev/null 2>&1 &&
   jq -e '
       .version == 1 and
       (.plugins | all(.[]; type == "object")) and
       .plugins[1].mode == "fast" and
       (.plugins[1].settings == null) and
       .bar.layout.center[0].format == "HH:mm"
   ' "$legacy_config" >/dev/null 2>&1; then
    pass "[isolated-runtime] representative legacy state migrates to canonical writes with an exact recoverable backup"
else
    details="$(tail -n 32 "$legacy_log" 2>/dev/null || true)"
    if [[ -s "$legacy_result" ]]; then details="$details result=$(tr '\n' ' ' <"$legacy_result")"; fi
    fail "[isolated-runtime] legacy-to-canonical migration failed (status=$legacy_status backup=$legacy_backup_hash original=$legacy_original_hash): $details"
fi

second_result="$cutover_root/second-result.json"
second_log="$cutover_root/second.log"
second_status=0
canonical_hash="$(sha256sum "$legacy_config" | awk '{print $1}')"
backup_hash_before="$legacy_backup_hash"
AURELIA_STATE_CONFIG_SOURCE="$config_root" \
AURELIA_STATE_RESULT="$second_result" \
AURELIA_SHELL_CONFIG="$legacy_config" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$cutover_root/second-runtime" \
XDG_STATE_HOME="$cutover_root/second-state" \
XDG_CONFIG_HOME="$cutover_root/second-config" \
XDG_CACHE_HOME="$cutover_root/second-cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/state-migration/shell.qml" \
    >"$second_log" 2>&1 || second_status=$?
second_canonical_hash="$(sha256sum "$legacy_config" | awk '{print $1}')"
backup_hash_after=""
if [[ -f "$legacy_backup" ]]; then backup_hash_after="$(sha256sum "$legacy_backup" | awk '{print $1}')"; fi

if [[ "$second_status" -eq 0 ]] && [[ -s "$second_result" ]] &&
   [[ "$canonical_hash" == "$second_canonical_hash" ]] &&
   [[ "$backup_hash_before" == "$backup_hash_after" ]] &&
   jq -e '.migrationNeededBefore == false and .migrationReturn == "ok" and .migrationNeededAfter == false' \
       "$second_result" >/dev/null 2>&1; then
    pass "[isolated-runtime] second cutover run is byte-stable and does not create backup pollution"
else
    details="$(tail -n 32 "$second_log" 2>/dev/null || true)"
    if [[ -s "$second_result" ]]; then details="$details result=$(tr '\n' ' ' <"$second_result")"; fi
    fail "[isolated-runtime] second cutover run changed canonical state or backup (status=$second_status): $details"
fi

if grep -q 'malformed source state falls back safely' "$ROOT/tests/test_shell_state_migration.sh" &&
   grep -q 'every shipped first-party plugin has a canonical' "$ROOT/tests/test_plugin_migration.sh" &&
   grep -q 'Third-party plugins' "$ROOT/docs/aurelia-plugin-authoring.md"; then
    pass "[static] malformed-state preservation, first-party canonical startup, and third-party opt-in policy remain covered"
else
    fail "[static] remaining compatibility-cutover coverage is not linked"
fi
