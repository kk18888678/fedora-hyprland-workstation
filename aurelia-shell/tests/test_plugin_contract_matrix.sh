#!/usr/bin/env bash

# T24 generic plugin contract matrix. Feature-specific suites remain the
# detailed regression owners; this suite makes the cross-cutting contract
# executable across the complete first-party inventory.

set -Eeuo pipefail

section "Aurelia Generic Plugin Contract Matrix"

plugins_root="$ROOT/plugins"
validator="$ROOT/bin/aurelia-plugin"
matrix_manifests=()
mapfile -d '' matrix_manifests < <(
    find -P "$plugins_root" -mindepth 2 -maxdepth 2 -type f -name manifest.json -print0 |
        LC_ALL=C sort -z
)
matrix_manifest_count="$(find -P "$plugins_root" -mindepth 2 -maxdepth 2 -type f -name manifest.json | wc -l)"

if [[ "$matrix_manifest_count" -eq 22 ]]; then
    pass "[static] first-party manifest enumeration finds all 22 Aurelia plugins"
else
    fail "[static] first-party manifest enumeration expected 22 plugins, found $matrix_manifest_count"
fi

matrix_manifest_failures=0
matrix_entry_failures=0
declare -A matrix_seen_kinds=()

matrix_safe_entry_point() {
    local value="$1"
    [[ -n "$value" && "$value" != /* && "$value" != *..* &&
       "$value" != *\\* && "$value" != *:* ]] || return 1
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]]
}

for manifest_path in "${matrix_manifests[@]}"; do
    plugin_dir="${manifest_path%/manifest.json}"
    plugin_id="$(jq -r '.id // empty' "$manifest_path")"
    if [[ "$(basename -- "$plugin_dir")" == "$plugin_id" ]] &&
       "$validator" validate --first-party "$plugin_dir" >/dev/null 2>&1; then
        pass "[static] first-party manifest validates: $plugin_id"
    else
        fail "[static] first-party manifest validation failed: $manifest_path"
        matrix_manifest_failures=$((matrix_manifest_failures + 1))
    fi

    matrix_tree_has_symlink=0
    if find -P "$plugin_dir" -type l -print -quit | grep -q .; then
        matrix_tree_has_symlink=1
    fi
    if [[ "$matrix_tree_has_symlink" -eq 0 ]]; then
        pass "[static] plugin tree has no symlinked code or manifest: $plugin_id"
    else
        fail "[static] plugin tree contains a symlink: $plugin_id"
        matrix_entry_failures=$((matrix_entry_failures + 1))
    fi

    while IFS=$'\t' read -r matrix_kind matrix_key matrix_entry; do
        [[ -n "$matrix_kind" ]] || continue
        matrix_seen_kinds["$matrix_kind"]=1
        entry_path="$plugin_dir/$matrix_entry"
        if matrix_safe_entry_point "$matrix_entry" &&
           [[ -f "$entry_path" && ! -L "$entry_path" ]]; then
            pass "[static] $plugin_id declares an existing safe $matrix_kind entry point"
        else
            fail "[static] $plugin_id declares an unsafe or missing $matrix_kind entry point"
            matrix_entry_failures=$((matrix_entry_failures + 1))
        fi
    done < <(
        jq -r '
            . as $manifest |
            .kinds[] as $kind |
            (if $kind == "bar-widget" then "barWidget" else $kind end) as $key |
            [$kind, $key, $manifest.entryPoints[$key]] | @tsv
        ' "$manifest_path"
    )
done

matrix_expected_kinds=(bar-widget bar panel overlay menu service)
matrix_missing_kinds=0
for matrix_kind in "${matrix_expected_kinds[@]}"; do
    if [[ "${matrix_seen_kinds[$matrix_kind]:-0}" -eq 1 ]]; then
        pass "[static] first-party inventory exercises supported kind: $matrix_kind"
    else
        fail "[static] first-party inventory has no supported kind: $matrix_kind"
        matrix_missing_kinds=$((matrix_missing_kinds + 1))
    fi
done

if [[ "$matrix_manifest_failures" -eq 0 && "$matrix_entry_failures" -eq 0 &&
      "$matrix_missing_kinds" -eq 0 ]]; then
    pass "[static] every declared first-party kind has a validated, safe, existing entry point"
else
    fail "[static] first-party manifest/entry-point matrix has contract failures"
fi

matrix_coverage=(
    "test_plugin_discovery.sh|duplicate"
    "test_plugin_survivability.sh|badMissingReported"
    "test_bar_widget_registry.sh|multi-kind"
    "test_bar_widget_metadata.sh|allowMultiple"
    "test_bar_operations.sh|placement"
    "test_plugin_settings.sh|settings"
    "test_active_bar.sh|fallback"
    "test_plugin_facades.sh|revocation"
    "test_sensitive_service_boundary.sh|capability"
    "test_plugin_lifecycle_management.sh|rollback"
    "test_plugin_watcher.sh|targeted"
    "test_plugin_migration.sh|migration"
)
matrix_coverage_failures=0
for matrix_coverage_item in "${matrix_coverage[@]}"; do
    matrix_coverage_file="${matrix_coverage_item%%|*}"
    matrix_coverage_marker="${matrix_coverage_item#*|}"
    if [[ -f "$ROOT/tests/$matrix_coverage_file" ]] &&
       grep -q "$matrix_coverage_marker" "$ROOT/tests/$matrix_coverage_file"; then
        :
    else
        fail "[static] generic matrix coverage owner is missing: $matrix_coverage_file"
        matrix_coverage_failures=$((matrix_coverage_failures + 1))
    fi
done
if [[ "$matrix_coverage_failures" -eq 0 ]]; then
    pass "[static] generic matrix retains first-party, registry, bar, lifecycle, facade, isolation, rollback, and reload coverage"
fi

matrix_invalid_root="$(mktemp -d)"
trap 'rm -rf -- "$matrix_invalid_root" 2>/dev/null || true' RETURN

matrix_write_manifest() {
    local target="$1"
    local id="$2"
    local kind="$3"
    local entry="$4"
    mkdir -p -- "$target"
    jq -n --arg id "$id" --arg kind "$kind" --arg entry "$entry" '
        {
            schemaVersion: 1,
            id: $id,
            name: ("Fixture " + $id),
            version: "0.0.1",
            description: "Generic contract fixture",
            kinds: [$kind],
            entryPoints: {($kind): $entry}
        }
    ' >"$target/manifest.json"
}

mkdir -p -- "$matrix_invalid_root/malformed" \
    "$matrix_invalid_root/namespace/aurelia.forbidden" \
    "$matrix_invalid_root/unsafe/aurelia.unsafe" \
    "$matrix_invalid_root/symlink/fixture.symlink"
printf '%s\n' '{"schemaVersion":1,"id":"fixture.malformed"' \
    >"$matrix_invalid_root/malformed/manifest.json"
printf '%s\n' 'import QtQuick' 'Item {}' >"$matrix_invalid_root/malformed/Entry.qml"

matrix_write_manifest "$matrix_invalid_root/namespace/aurelia.forbidden" \
    "aurelia.forbidden" panel Entry.qml
printf '%s\n' 'import QtQuick' 'Item {}' \
    >"$matrix_invalid_root/namespace/aurelia.forbidden/Entry.qml"

matrix_write_manifest "$matrix_invalid_root/unsafe/aurelia.unsafe" \
    "aurelia.unsafe" panel ../outside.qml
printf '%s\n' 'import QtQuick' 'Item {}' \
    >"$matrix_invalid_root/unsafe/outside.qml"

matrix_write_manifest "$matrix_invalid_root/symlink/fixture.symlink" \
    "fixture.symlink" panel Entry.qml
printf '%s\n' 'import QtQuick' 'Item {}' \
    >"$matrix_invalid_root/outside.qml"
ln -s -- "$matrix_invalid_root/outside.qml" \
    "$matrix_invalid_root/symlink/fixture.symlink/Entry.qml"

matrix_expect_reject() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "[isolated-cli] unsafe fixture was accepted: $label"
    else
        pass "[isolated-cli] unsafe fixture rejected before publication: $label"
    fi
}

matrix_expect_reject "malformed JSON" \
    "$validator" validate "$matrix_invalid_root/malformed"
matrix_expect_reject "reserved namespace" \
    "$validator" validate "$matrix_invalid_root/namespace/aurelia.forbidden"
matrix_expect_reject "unsafe entry-point path" \
    "$validator" validate --first-party "$matrix_invalid_root/unsafe/aurelia.unsafe"
matrix_expect_reject "symlinked entry point" \
    "$validator" validate "$matrix_invalid_root/symlink/fixture.symlink"

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] generic plugin contract QuickShell fixtures (qs or timeout unavailable)"
    return 0
fi

matrix_duplicate_root="$matrix_invalid_root/duplicate-first-party"
mkdir -p -- "$matrix_duplicate_root/aurelia.duplicate" \
    "$matrix_duplicate_root/widgets"
printf '%s\n' 'import QtQuick' 'Item {}' \
    >"$matrix_duplicate_root/aurelia.duplicate/Entry.qml"
printf '%s\n' 'import QtQuick' 'Item {}' \
    >"$matrix_duplicate_root/widgets/Entry.qml"
jq -n '{
    schemaVersion: 1, id: "aurelia.duplicate", name: "Duplicate",
    version: "1.0.0", description: "Duplicate fixture", kinds: ["panel"],
    entryPoints: {panel: "Entry.qml"}
}' >"$matrix_duplicate_root/aurelia.duplicate/manifest.json"
jq -n '{
    schemaVersion: 1, id: "aurelia.duplicate", name: "Duplicate sibling",
    version: "1.0.0", description: "Duplicate sibling fixture", kinds: ["panel"],
    entryPoints: {panel: "Entry.qml"}
}' >"$matrix_duplicate_root/widgets/AureliaDuplicate.manifest.json"

matrix_duplicate_result="$matrix_invalid_root/duplicate-result.json"
matrix_duplicate_log="$matrix_invalid_root/duplicate.log"
matrix_duplicate_status=0
mkdir -p -- "$matrix_invalid_root/empty-config/aurelia/plugins"
AURELIA_DISCOVERY_REGISTRY_SOURCE="$ROOT/services/PluginRegistry.qml" \
AURELIA_DISCOVERY_FIRST_PARTY="$matrix_duplicate_root" \
AURELIA_DISCOVERY_RESULT="$matrix_duplicate_result" \
AURELIA_SHELL_ROOT="$ROOT" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$matrix_invalid_root/duplicate-runtime" \
XDG_STATE_HOME="$matrix_invalid_root/duplicate-state" \
XDG_CONFIG_HOME="$matrix_invalid_root/empty-config" \
XDG_CACHE_HOME="$matrix_invalid_root/duplicate-cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-discovery/shell.qml" \
    >"$matrix_duplicate_log" 2>&1 || matrix_duplicate_status=$?

if [[ "$matrix_duplicate_status" -eq 0 ]] &&
   jq -e '
       .scanState == "partial" and
       .scanFailureClass == "rejected-manifests" and
       (.ids | length == 1) and
       (.ids | index("aurelia.duplicate")) and
       (.catalog.rejected | any(.reason | contains("duplicated")))
   ' "$matrix_duplicate_result" >/dev/null 2>&1; then
    pass "[isolated-runtime] duplicate IDs are rejected while the first valid registry entry remains available"
else
    matrix_duplicate_details="$(tail -n 24 "$matrix_duplicate_log" 2>/dev/null || true)"
    fail "[isolated-runtime] duplicate-ID registry fixture failed (status=$matrix_duplicate_status): $matrix_duplicate_details"
fi

matrix_runtime_root="$matrix_invalid_root/runtime"
mkdir -p -- "$matrix_runtime_root"
matrix_fixture_kinds=(bar-widget panel overlay menu service)
for matrix_kind in "${matrix_fixture_kinds[@]}"; do
    matrix_id="matrix.$matrix_kind"
    mkdir -p -- "$matrix_runtime_root/$matrix_id"
    if [[ "$matrix_kind" == "bar-widget" ]]; then
        jq -n --arg id "$matrix_id" '{
            schemaVersion: 1, id: $id, name: "Matrix bar widget",
            version: "1.0.0", description: "Matrix bar widget",
            kinds: ["bar-widget"], entryPoints: {barWidget: "Entry.qml"}
        }' >"$matrix_runtime_root/$matrix_id/manifest.json"
    else
        jq -n --arg id "$matrix_id" --arg kind "$matrix_kind" '{
            schemaVersion: 1, id: $id, name: $id,
            version: "1.0.0", description: "Matrix entry point",
            kinds: [$kind], entryPoints: {($kind): "Entry.qml"}
        }' >"$matrix_runtime_root/$matrix_id/manifest.json"
    fi
    printf '%s\n' \
        'import QtQuick' \
        'Item {' \
        '    property string moduleName: ""' \
        '    property bool initialized: false' \
        '    function aureliaInitialize() { initialized = true }' \
        '    function health() { return "healthy-" + moduleName }' \
        '    function open(payload) { return "opened" }' \
        '    function close() { return "closed" }' \
        '    function explode(payload) { throw "intentional matrix callback failure" }' \
        '}' >"$matrix_runtime_root/$matrix_id/Entry.qml"
done
mkdir -p -- "$matrix_runtime_root/aurelia.bar" "$matrix_runtime_root/matrix.bar"
printf '%s\n' \
    'import QtQuick' \
    'Item {' \
    '    property bool initialized: false' \
    '    function aureliaInitialize() { initialized = true }' \
    '    function health() { return "healthy-bar" }' \
    '}' >"$matrix_runtime_root/aurelia.bar/Entry.qml"
cp -- "$matrix_runtime_root/aurelia.bar/Entry.qml" \
    "$matrix_runtime_root/matrix.bar/Entry.qml"

matrix_runtime_result="$matrix_invalid_root/runtime-result.json"
matrix_runtime_log="$matrix_invalid_root/runtime.log"
matrix_runtime_status=0
AURELIA_CONTRACT_MATRIX_HOST_SOURCE="$ROOT/services/PluginHost.qml" \
AURELIA_CONTRACT_MATRIX_ROOT="$matrix_runtime_root" \
AURELIA_CONTRACT_MATRIX_RESULT="$matrix_runtime_result" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$matrix_invalid_root/runtime-dir" \
XDG_STATE_HOME="$matrix_invalid_root/runtime-state" \
XDG_CONFIG_HOME="$matrix_invalid_root/runtime-config" \
XDG_CACHE_HOME="$matrix_invalid_root/runtime-cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-contract-matrix/shell.qml" \
    >"$matrix_runtime_log" 2>&1 || matrix_runtime_status=$?

if [[ "$matrix_runtime_status" -eq 0 ]] && [[ -s "$matrix_runtime_result" ]] &&
   jq -e '
       .hostStillAlive == true and
       .pingResponded == true and
       .listPluginsResponded == true and
       .initialKindsLoaded == true and
       .openResult == "ok" and
       .closeResult == "ok" and
       .callbackResult == "error" and
       .callbackQuarantined == true and
       .callbackHealthyService == true and
       .reloadRestored == true and
       .reloadClearedFailure == true and
       .replacementBarFailed == true and
       .builtInBarFallback == true and
       .healthyServiceAfterBarFailure == true and
       .healthyWidgetAfterBarFailure == true and
       .reloadedPanel == true
   ' "$matrix_runtime_result" >/dev/null 2>&1; then
    pass "[isolated-runtime] every supported kind loads through PluginHost and contained callback/reload/bar failures preserve host health"
else
    matrix_runtime_details="$(tail -n 40 "$matrix_runtime_log" 2>/dev/null || true)"
    if [[ -s "$matrix_runtime_result" ]]; then
        matrix_runtime_details="$matrix_runtime_details result=$(tr '\n' ' ' <"$matrix_runtime_result")"
    fi
    fail "[isolated-runtime] generic PluginHost contract fixture failed (status=$matrix_runtime_status): $matrix_runtime_details"
fi
