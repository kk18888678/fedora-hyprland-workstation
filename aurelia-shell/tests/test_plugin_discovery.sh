#!/usr/bin/env bash

# T04 discovery-model checks against the real PluginRegistry scan process.

set -Eeuo pipefail

section "Aurelia Plugin Discovery Parity"

registry_root="$ROOT/services/PluginRegistry.qml"
manifest_root="$ROOT/bin/lib/aurelia-plugin/manifest.sh"
main_root="$ROOT/bin/lib/aurelia-plugin/main.sh"

if grep -Fq -- "-name '*.manifest.json'" "$registry_root" &&
   grep -q 'scanTimeoutPath' "$registry_root" &&
   grep -q 'AURELIA_PLUGIN_EMPTY' "$registry_root" &&
   grep -q 'scanState = "malformed-output"' "$registry_root" &&
   grep -q 'tooling-unavailable' "$registry_root"; then
    pass "[static] discovery supports sibling manifests and explicit empty, malformed, timeout, and unavailable states"
else
    fail "[static] discovery state or sibling-manifest support is incomplete"
fi

if grep -q 'local manifest_name=' "$manifest_root" &&
   grep -q -- '--manifest-file' "$main_root" &&
   grep -q 'source_kind.*firstparty' "$registry_root" &&
   grep -q 'source_kind.*thirdparty' "$registry_root"; then
    pass "[static] the canonical validator accepts a selected sibling manifest while user plugins remain top-level"
else
    fail "[static] discovery source-shape wiring is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] discovery QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

discovery_root="$(mktemp -d)"
trap 'rm -rf -- "$discovery_root" 2>/dev/null || true' RETURN
first_party="$discovery_root/first-party"
user_plugins="$discovery_root/config/aurelia/plugins"
mkdir -p -- \
    "$first_party/aurelia.primary" \
    "$first_party/grouped/status" \
    "$first_party/bar/widgets" \
    "$first_party/aurelia.duplicate" \
    "$first_party/duplicates" \
    "$first_party/grouped/invalid" \
    "$user_plugins/fixture.third" \
    "$user_plugins/aurelia.primary"

printf '%s\n' 'import QtQuick' 'Item {}' >"$first_party/aurelia.primary/Panel.qml"
cp -- "$first_party/aurelia.primary/Panel.qml" "$first_party/grouped/status/Panel.qml"
cp -- "$first_party/aurelia.primary/Panel.qml" "$first_party/aurelia.duplicate/Panel.qml"
cp -- "$first_party/aurelia.primary/Panel.qml" "$first_party/duplicates/Duplicate.qml"
cp -- "$first_party/aurelia.primary/Panel.qml" "$first_party/bar/widgets/Sibling.qml"
cp -- "$first_party/aurelia.primary/Panel.qml" "$user_plugins/fixture.third/Panel.qml"
cp -- "$first_party/aurelia.primary/Panel.qml" "$user_plugins/aurelia.primary/Panel.qml"

jq -n '{
    schemaVersion: 1, id: "aurelia.primary", name: "Primary", version: "1.0.0",
    description: "Primary fixture", kinds: ["panel"], entryPoints: {panel: "Panel.qml"}
}' >"$first_party/aurelia.primary/manifest.json"
jq -n '{
    schemaVersion: 1, id: "aurelia.grouped", name: "Grouped", version: "1.0.0",
    description: "Grouped fixture", kinds: ["panel"], entryPoints: {panel: "Panel.qml"}
}' >"$first_party/grouped/status/manifest.json"
jq -n '{
    schemaVersion: 1, id: "aurelia.sibling", name: "Sibling", version: "1.0.0",
    description: "Sibling fixture", kinds: ["bar-widget"],
    entryPoints: {barWidget: "Sibling.qml"},
    barWidget: {displayName: "Sibling", description: "Sibling fixture", category: "Testing", allowMultiple: false}
}' >"$first_party/bar/widgets/Sibling.manifest.json"
jq -n '{
    schemaVersion: 1, id: "aurelia.duplicate", name: "Duplicate", version: "1.0.0",
    description: "First duplicate fixture", kinds: ["panel"], entryPoints: {panel: "Panel.qml"}
}' >"$first_party/aurelia.duplicate/manifest.json"
jq -n '{
    schemaVersion: 1, id: "aurelia.duplicate", name: "Duplicate sibling", version: "1.0.0",
    description: "Second duplicate fixture", kinds: ["panel"], entryPoints: {panel: "Duplicate.qml"}
}' >"$first_party/duplicates/Duplicate.manifest.json"
jq -n '{
    schemaVersion: 1, id: "aurelia.invalid", name: "Invalid", version: "1.0.0",
    description: "Rejected fixture", kinds: ["unknown"], entryPoints: {unknown: "Panel.qml"}
}' >"$first_party/grouped/invalid/manifest.json"
jq -n '{
    schemaVersion: 1, id: "fixture.third", name: "Third party", version: "1.0.0",
    description: "Third-party fixture", kinds: ["panel"], entryPoints: {panel: "Panel.qml"}
}' >"$user_plugins/fixture.third/manifest.json"
jq -n '{
    schemaVersion: 1, id: "aurelia.primary", name: "Shadow attempt", version: "1.0.0",
    description: "Reserved namespace shadow attempt", kinds: ["panel"], entryPoints: {panel: "Panel.qml"}
}' >"$user_plugins/aurelia.primary/manifest.json"

if "$ROOT/bin/aurelia-plugin" validate --first-party --manifest-file Sibling.manifest.json \
    "$first_party/bar/widgets" >/dev/null 2>&1; then
    pass "[static] sibling manifest validates through the author-facing canonical validator"
else
    fail "[static] sibling manifest was rejected by the canonical validator"
fi

runtime_result="$discovery_root/result.json"
runtime_log="$discovery_root/runtime.log"
runtime_status=0
AURELIA_DISCOVERY_REGISTRY_SOURCE="$ROOT/services/PluginRegistry.qml" \
AURELIA_DISCOVERY_FIRST_PARTY="$first_party" \
AURELIA_DISCOVERY_RESULT="$runtime_result" \
AURELIA_SHELL_ROOT="$ROOT" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$discovery_root/runtime" \
XDG_STATE_HOME="$discovery_root/state" \
XDG_CONFIG_HOME="$discovery_root/config" \
XDG_CACHE_HOME="$discovery_root/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-discovery/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e --arg first "$first_party/aurelia.duplicate" \
      --arg grouped "$first_party/grouped/status" \
      --arg sibling "$first_party/bar/widgets" \
      --arg third "$user_plugins/fixture.third" '
        .scanState == "partial" and
        .scanFailureClass == "rejected-manifests" and
        .rejectedCount >= 3 and
        (.ids | length == 5) and
        (.ids | index("aurelia.primary")) and
        (.ids | index("aurelia.grouped")) and
        (.ids | index("aurelia.sibling")) and
        (.ids | index("aurelia.duplicate")) and
        (.ids | index("fixture.third")) and
        .sources["aurelia.duplicate"] == $first and
        .sources["aurelia.grouped"] == $grouped and
        .sources["aurelia.sibling"] == $sibling and
        .sources["fixture.third"] == $third and
        (.catalog.plugins | length == 5) and
        ([.catalog.plugins[] | select(.id == "aurelia.sibling")][0].entryPoints.barWidget == "Sibling.qml") and
        ([.catalog.plugins[] | select(.id == "aurelia.sibling")][0].manifestPath == ($sibling + "/Sibling.manifest.json")) and
        (.catalog.rejected | length >= 3)
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] grouped, sibling, duplicate, first-party precedence, third-party, and rejected discovery cases pass"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] discovery parity fixture failed (status=$runtime_status): $details"
fi

malformed_result="$discovery_root/malformed-result.json"
malformed_log="$discovery_root/malformed.log"
malformed_status=0
AURELIA_DISCOVERY_REGISTRY_SOURCE="$ROOT/services/PluginRegistry.qml" \
AURELIA_DISCOVERY_FIRST_PARTY="$first_party" \
AURELIA_DISCOVERY_RESULT="$malformed_result" \
AURELIA_DISCOVERY_MALFORMED=1 \
AURELIA_SHELL_ROOT="$ROOT" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$discovery_root/malformed-runtime" \
XDG_STATE_HOME="$discovery_root/malformed-state" \
XDG_CONFIG_HOME="$discovery_root/malformed-config" \
XDG_CACHE_HOME="$discovery_root/malformed-cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-discovery/shell.qml" \
    >"$malformed_log" 2>&1 || malformed_status=$?

if [[ "$malformed_status" -eq 0 ]] && [[ -s "$malformed_result" ]] &&
   jq -e '.scanState == "malformed-output" and .scanFailureClass == "malformed-output"' \
       "$malformed_result" >/dev/null; then
    pass "[isolated-runtime] malformed scanner output fails closed with an explicit registry state"
else
    fail "[isolated-runtime] malformed scanner output state was not recorded"
fi

empty_root="$discovery_root/empty-first-party"
empty_config="$discovery_root/empty-config"
mkdir -p -- "$empty_root" "$empty_config/aurelia/plugins"
empty_result="$discovery_root/empty-result.json"
empty_log="$discovery_root/empty.log"
empty_status=0
AURELIA_DISCOVERY_REGISTRY_SOURCE="$ROOT/services/PluginRegistry.qml" \
AURELIA_DISCOVERY_FIRST_PARTY="$empty_root" \
AURELIA_DISCOVERY_RESULT="$empty_result" \
AURELIA_SHELL_ROOT="$ROOT" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$discovery_root/empty-runtime" \
XDG_STATE_HOME="$discovery_root/empty-state" \
XDG_CONFIG_HOME="$empty_config" \
XDG_CACHE_HOME="$discovery_root/empty-cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-discovery/shell.qml" \
    >"$empty_log" 2>&1 || empty_status=$?

if [[ "$empty_status" -eq 0 ]] && [[ -s "$empty_result" ]] &&
   jq -e '.scanState == "empty" and .scanFailureClass == "empty-valid-catalog" and (.ids | length == 0)' \
       "$empty_result" >/dev/null; then
    pass "[isolated-runtime] an empty valid catalog is explicitly distinguished from malformed discovery"
else
    fail "[isolated-runtime] empty catalog state was not recorded"
fi
