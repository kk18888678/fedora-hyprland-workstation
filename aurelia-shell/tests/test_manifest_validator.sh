#!/usr/bin/env bash

# T03 canonical manifest contract tests. The CLI matrix and the real QML
# registry matrix use the same cases so drift between authoring and runtime
# validation becomes an explicit failure.

set -Eeuo pipefail

section "Aurelia Canonical Manifest Validator"

validator="$ROOT/bin/aurelia-plugin"
manifest_root="$ROOT/bin/lib/aurelia-plugin/manifest.sh"
registry_root="$ROOT/services/PluginRegistry.qml"

if [[ -x "$validator" ]] &&
   grep -q 'manifestValidatorPath' "$registry_root" &&
   grep -q 'validator.*validate' "$registry_root" &&
   grep -q '"barWidget"' "$registry_root" &&
   grep -q 'function entryPointKeyForKind' "$registry_root"; then
    pass "[static] CLI validator is wired into runtime discovery with canonical and legacy bar-widget entry-point support"
else
    fail "[static] canonical validator is not wired into both authoring and runtime discovery"
fi

if [[ ! -x "$validator" || ! -f "$manifest_root" ]]; then
    fail "[static] Aurelia plugin validator entry point is missing"
    return 0
fi

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root" 2>/dev/null || true' RETURN
mkdir -p -- "$test_root/cli" "$test_root/state" "$test_root/config" "$test_root/cache" "$test_root/runtime"
printf '%s\n' 'import QtQuick' 'Item {}' >"$test_root/Panel.qml"
printf '%s\n' 'import QtQuick' 'Item {}' >"$test_root/Service.qml"
cp -- "$test_root/Panel.qml" "$test_root/PanelCopy.qml"

jq -n '
    def base($id): {
        schemaVersion: 1,
        id: $id,
        name: "Fixture",
        version: "1.0.0",
        description: "A valid fixture plugin",
        kinds: ["panel"],
        entryPoints: {panel: "Panel.qml"}
    };
    def canonical($id):
        base($id)
        | .kinds = ["bar-widget"]
        | .entryPoints = {barWidget: "Panel.qml"}
        | .barWidget = {
            displayName: "Fixture widget",
            description: "A valid fixture widget",
            category: "Testing",
            allowMultiple: false,
            defaultSection: "center",
            defaults: {format: "compact"},
            settingsForm: "fixtureSettings",
            schema: [{key: "format", type: "string", label: "Format", defaultValue: "compact"}]
        };
    [
        {name: "valid-canonical", firstParty: false, expected: true, manifest: canonical("fixture.canonical")},
        {name: "valid-legacy", firstParty: false, expected: true,
            manifest: (base("fixture.legacy") | .kinds = ["bar-widget"] | .entryPoints = {"bar-widget": "Panel.qml"})},
        {name: "valid-aurelia-namespace", firstParty: true, expected: true,
            manifest: (base("aurelia.capability") | .aurelia = {
                icon: "capability",
                clonePaths: [{source: "Panel.qml", target: "PanelCopy.qml"}],
                capabilities: ["diagnostics"],
                compatibility: {hostApi: "1"}
            })},
        {name: "bad-schema", firstParty: false, expected: false, manifest: (base("fixture.schema") | .schemaVersion = 2)},
        {name: "missing-description", firstParty: false, expected: false, manifest: (base("fixture.description") | del(.description))},
        {name: "blank-description", firstParty: false, expected: false, manifest: (base("fixture.blank") | .description = "   ")},
        {name: "unknown-kind", firstParty: false, expected: false,
            manifest: (base("fixture.kind") | .kinds = ["sidecar"] | .entryPoints = {sidecar: "Panel.qml"})},
        {name: "duplicate-kind", firstParty: false, expected: false,
            manifest: (base("fixture.duplicate") | .kinds = ["panel", "panel"] | .entryPoints = {panel: "Panel.qml"})},
        {name: "missing-entry-point", firstParty: false, expected: false,
            manifest: (base("fixture.missing") | .entryPoints = {})},
        {name: "extra-entry-point", firstParty: false, expected: false,
            manifest: (base("fixture.extra") | .entryPoints = {panel: "Panel.qml", service: "Service.qml"})},
        {name: "canonical-metadata-missing", firstParty: false, expected: false,
            manifest: (base("fixture.metadata") | .kinds = ["bar-widget"] | .entryPoints = {barWidget: "Panel.qml"})},
        {name: "bad-default-section", firstParty: false, expected: false,
            manifest: (canonical("fixture.section") | .barWidget.defaultSection = "north")},
        {name: "bad-allow-multiple", firstParty: false, expected: false,
            manifest: (canonical("fixture.multiple") | .barWidget.allowMultiple = "false")},
        {name: "bad-schema-item", firstParty: false, expected: false,
            manifest: (canonical("fixture.control") | .barWidget.schema[0].type = "unsupported")},
        {name: "unsafe-entry-point", firstParty: false, expected: false,
            manifest: (base("fixture.unsafe") | .entryPoints.panel = "../Panel.qml")},
        {name: "unknown-public-field", firstParty: false, expected: false,
            manifest: (base("fixture.public") | .hostApi = "1")},
        {name: "foreign-namespace-field", firstParty: false, expected: false,
            manifest: (base("fixture.foreign") | .omarchy = {capabilities: ["authentication"]})},
        {name: "third-party-capability", firstParty: false, expected: false,
            manifest: (base("fixture.capability") | .aurelia = {capabilities: ["authentication"]})},
        {name: "bad-compatibility", firstParty: true, expected: false,
            manifest: (base("aurelia.compat") | .aurelia = {compatibility: {hostApi: 1}})},
        {name: "bad-icon", firstParty: false, expected: false,
            manifest: (base("fixture.icon") | .icon = "../icon")},
        {name: "duplicate-icon-namespace", firstParty: true, expected: false,
            manifest: (base("aurelia.icons") | .icon = "one" | .aurelia = {icon: "two"})},
        {name: "bad-keep-loaded", firstParty: false, expected: false,
            manifest: (base("fixture.keep") | .keepLoaded = "true")},
        {name: "bad-activation", firstParty: false, expected: false,
            manifest: (base("fixture.activation") | .activation = "always")},
        {name: "duplicate-clone-path", firstParty: true, expected: false,
            manifest: (base("aurelia.clones") | .aurelia = {clonePaths: [
                {source: "Panel.qml", target: "PanelCopy.qml"},
                {source: "Panel.qml", target: "PanelCopy.qml"}
            ]})},
        {name: "unsafe-clone-path", firstParty: true, expected: false,
            manifest: (base("aurelia.unsafe-clone") | .aurelia = {clonePaths: [
                {source: "../Panel.qml", target: "PanelCopy.qml"}
            ]})}
    ]
' >"$test_root/matrix.json"

cli_failures=0
while IFS= read -r encoded_case; do
    case_name="$(jq -r '.name' <<<"$encoded_case")"
    case_id="$(jq -r '.manifest.id' <<<"$encoded_case")"
    first_party="$(jq -r 'if .firstParty then "--first-party" else "" end' <<<"$encoded_case")"
    expected="$(jq -r '.expected' <<<"$encoded_case")"
    case_dir="$test_root/cli/$case_id"
    mkdir -p -- "$case_dir"
    cp -- "$test_root/Panel.qml" "$case_dir/Panel.qml"
    cp -- "$test_root/Service.qml" "$case_dir/Service.qml"
    cp -- "$test_root/PanelCopy.qml" "$case_dir/PanelCopy.qml"
    jq '.manifest' <<<"$encoded_case" >"$case_dir/manifest.json"
    actual="false"
    if [[ -n "$first_party" ]]; then
        "$validator" validate --first-party "$case_dir" >/dev/null 2>&1 && actual="true"
    else
        "$validator" validate "$case_dir" >/dev/null 2>&1 && actual="true"
    fi
    if [[ "$actual" == "$expected" ]]; then
        pass "[static] CLI matrix: $case_name"
    else
        fail "[static] CLI matrix: $case_name (expected=$expected actual=$actual)"
        cli_failures=$((cli_failures + 1))
    fi
done < <(jq -c '.[]' "$test_root/matrix.json")

runtime_result="$test_root/runtime-result.json"
runtime_log="$test_root/runtime.log"
runtime_status=0
AURELIA_MANIFEST_REGISTRY_SOURCE="$registry_root" \
AURELIA_MANIFEST_MATRIX="$test_root/matrix.json" \
AURELIA_MANIFEST_RESULT="$runtime_result" \
AURELIA_SHELL_ROOT="$ROOT" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$test_root/runtime" \
XDG_STATE_HOME="$test_root/state" \
XDG_CONFIG_HOME="$test_root/config" \
XDG_CACHE_HOME="$test_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/manifest-validator/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e '.discoveryScanFinished == true and .discoveredCount == 22 and .discoveryError == "" and
       (.results | length == 25 and all(.[]; .accepted == .expected and .inputUnchanged == true))' \
       "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] QML registry accepts/rejects the same 25 manifest cases as the CLI and does not mutate input"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] QML registry manifest matrix diverged (status=$runtime_status): $details"
fi

if (( cli_failures > 0 )); then
    return 0
fi
