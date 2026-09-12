#!/usr/bin/env bash

# T10 unified shell-state migration checks.

set -Eeuo pipefail

section "Aurelia Unified Shell State Migration"

config_root="$ROOT/services/ShellConfig.qml"
shell_root="$ROOT/shell.qml"

if grep -q 'property bool migrationNeeded' "$config_root" &&
   grep -q 'property Process migrationBackupProcess' "$config_root" &&
   grep -q 'function normalizePluginEntries' "$config_root" &&
   grep -q 'function migrate()' "$config_root" &&
   grep -q 'function migrateConfig(): string' "$shell_root"; then
    pass "[static] ShellConfig owns explicit canonical migration with recoverable backup state"
else
    fail "[static] unified shell-state migration boundary is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] shell-state migration QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

state_root="$(mktemp -d)"
trap 'rm -rf -- "$state_root" 2>/dev/null || true' RETURN
config_dir="$state_root/config/aurelia"
mkdir -p -- "$config_dir"
config_path="$config_dir/shell.json"
backup_path="$config_path.pre-migration.bak"
fixture_result="$state_root/first-result.json"
fixture_log="$state_root/first.log"

jq -n ' {
    version: 1,
    idle: {screensaver: 150, lock: "bad", customIdleValue: "preserve"},
    plugins: [
        "fixture.panel",
        {id: "fixture.settings", settings: {mode: "fast"}, customPluginValue: 7}
    ],
    disabledPlugins: ["aurelia.clock"],
    bar: {
        id: "aurelia.bar",
        position: "top",
        transparent: false,
        centerAnchor: "aurelia.clock",
        customBarValue: "preserve",
        layout: {
            left: ["aurelia.workspaces"],
            center: [{id: "aurelia.clock", settings: {format: "HH:mm"}, customEntryValue: true}],
            right: []
        }
    },
    userOwnedState: {keep: true, nested: {value: 42}},
    userOwnedNull: null
}' >"$config_path"
original_hash="$(sha256sum "$config_path" | awk '{print $1}')"

run_state_fixture() {
    local result_path="$1"
    local log_path="$2"
    local status=0
    AURELIA_STATE_CONFIG_SOURCE="$config_root" \
    AURELIA_STATE_RESULT="$result_path" \
    AURELIA_SHELL_CONFIG="$config_path" \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$state_root/runtime-$RANDOM" \
    XDG_STATE_HOME="$state_root/state" \
    XDG_CONFIG_HOME="$state_root/config" \
    XDG_CACHE_HOME="$state_root/cache-$RANDOM" \
        /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
        --path "$ROOT/tests/fixtures/state-migration/shell.qml" \
        >"$log_path" 2>&1 || status=$?
    return "$status"
}

first_status=0
run_state_fixture "$fixture_result" "$fixture_log" || first_status=$?
first_backup_hash=""
if [[ -f "$backup_path" ]]; then first_backup_hash="$(sha256sum "$backup_path" | awk '{print $1}')"; fi
config_mode="$(stat -c '%a' "$config_path" 2>/dev/null || true)"

if [[ "$first_status" -eq 0 ]] && [[ -s "$fixture_result" ]] && [[ -f "$backup_path" ]] &&
   [[ "$first_backup_hash" == "$original_hash" ]] &&
   [[ "$config_mode" == "600" ]] &&
   jq -e '
        .migrationNeededBefore == true and
        .migrationReturn == "pending" and
        .migrationResult == "migrated" and
        .migrationNeededAfter == false and
        .config.plugins[0].id == "fixture.panel" and
        .config.plugins[1].id == "fixture.settings" and
        .config.plugins[1].mode == "fast" and
        .config.plugins[1].customPluginValue == 7 and
        .config.idle.screensaver == 150 and
        .config.idle.customIdleValue == "preserve" and
        .config.bar.layout.center[0].format == "HH:mm" and
        .config.bar.layout.center[0].customEntryValue == true and
        .config.bar.customBarValue == "preserve" and
        .config.userOwnedState.nested.value == 42 and
        .config.userOwnedNull == null and
        (.config.plugins[1].settings == null)
    ' "$fixture_result" >/dev/null; then
    pass "[isolated-runtime] first migration normalizes legacy entries, preserves unknown state, and creates one recoverable backup"
else
    details="$(tr '\n' ' ' <"$fixture_log")"
    if [[ -s "$fixture_result" ]]; then
        details="$details result=$(tr '\n' ' ' <"$fixture_result")"
    fi
    fail "[isolated-runtime] first shell-state migration failed (status=$first_status mode=$config_mode backup=$first_backup_hash original=$original_hash): $details"
fi

canonical_hash=""
backup_hash_before=""
if [[ -f "$config_path" ]]; then canonical_hash="$(sha256sum "$config_path" | awk '{print $1}')"; fi
if [[ -f "$backup_path" ]]; then backup_hash_before="$(sha256sum "$backup_path" | awk '{print $1}')"; fi
second_result="$state_root/second-result.json"
second_log="$state_root/second.log"
second_status=0
run_state_fixture "$second_result" "$second_log" || second_status=$?
backup_hash_after=""
if [[ -f "$backup_path" ]]; then backup_hash_after="$(sha256sum "$backup_path" | awk '{print $1}')"; fi
second_canonical_hash=""
if [[ -f "$config_path" ]]; then second_canonical_hash="$(sha256sum "$config_path" | awk '{print $1}')"; fi

if [[ "$second_status" -eq 0 ]] && [[ -s "$second_result" ]] &&
   [[ "$canonical_hash" == "$second_canonical_hash" ]] &&
   [[ "$backup_hash_before" == "$backup_hash_after" ]] &&
   jq -e '.migrationNeededBefore == false and .migrationReturn == "ok" and .migrationResult == "not-needed" and .migrationNeededAfter == false' \
       "$second_result" >/dev/null; then
    pass "[isolated-runtime] second migration run is byte-stable and does not create backup pollution"
else
    details="$(tr '\n' ' ' <"$second_log")"
    if [[ -s "$second_result" ]]; then details="$details result=$(tr '\n' ' ' <"$second_result")"; fi
    fail "[isolated-runtime] second shell-state migration was not idempotent (status=$second_status): $details"
fi

malformed_path="$state_root/malformed-shell.json"
malformed_backup="$malformed_path.pre-migration.bak"
printf '%s\n' '{ this is not valid JSON' >"$malformed_path"
malformed_hash_before="$(sha256sum "$malformed_path" | awk '{print $1}')"
config_path="$malformed_path"
backup_path="$malformed_backup"
malformed_result="$state_root/malformed-result.json"
malformed_log="$state_root/malformed.log"
malformed_status=0
run_state_fixture "$malformed_result" "$malformed_log" || malformed_status=$?
malformed_hash_after="$(sha256sum "$malformed_path" | awk '{print $1}')"

if [[ "$malformed_status" -eq 0 ]] && [[ -s "$malformed_result" ]] &&
   [[ "$malformed_hash_before" == "$malformed_hash_after" ]] &&
   [[ ! -e "$malformed_backup" && ! -L "$malformed_backup" ]] &&
   jq -e '.migrationNeededBefore == false and .migrationReturn == "ok" and .config.plugins == []' \
       "$malformed_result" >/dev/null; then
    pass "[isolated-runtime] malformed source state falls back safely without rewriting or deleting the original"
else
    details="$(tr '\n' ' ' <"$malformed_log")"
    if [[ -s "$malformed_result" ]]; then details="$details result=$(tr '\n' ' ' <"$malformed_result")"; fi
    fail "[isolated-runtime] malformed shell-state source was not preserved (status=$malformed_status): $details"
fi
