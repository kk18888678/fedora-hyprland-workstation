#!/usr/bin/env bash

# T11 operational bar-widget metadata checks.

set -Eeuo pipefail

section "Aurelia Operational Bar Widget Metadata"

bar_root="$ROOT/plugins/aurelia.bar"
registry_root="$ROOT/services/BarWidgetRegistry.qml"
config_root="$ROOT/services/ShellConfig.qml"

if grep -q 'function defaultsFor' "$registry_root" &&
   grep -q 'function displayNameFor' "$registry_root" &&
   grep -q 'function descriptionFor' "$registry_root" &&
   grep -q 'function categoryFor' "$registry_root" &&
   grep -q 'function defaultSectionFor' "$registry_root" &&
   grep -q 'function allowMultipleFor' "$registry_root" &&
   grep -q 'function schemaFor' "$registry_root" &&
   grep -q 'function settingsFormFor' "$registry_root" &&
   grep -q 'function settingsFor' "$registry_root"; then
    pass "[static] BarWidgetRegistry consumes defaults, section, multiplicity, schema, and settings metadata"
else
    fail "[static] operational bar-widget metadata projection is incomplete"
fi

if grep -q 'barWidgetRegistry.allowMultipleFor' "$config_root" &&
   grep -q 'barWidgetRegistry: root.barWidgetRegistry' "$bar_root/BarWidgetRow.qml" &&
   grep -q 'barWidgetRegistry: root.barWidgetRegistry' "$bar_root/BarCenter.qml" &&
   grep -q 'function instanceIdFor' "$registry_root" &&
   grep -q 'ambiguous' "$bar_root/Bar.qml"; then
    pass "[static] configuration, rows, and bar routing enforce metadata and explicit duplicate addressing"
else
    fail "[static] metadata/default or duplicate-instance routing boundary is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] bar metadata QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_BAR_METADATA_REGISTRY_SOURCE="$ROOT/services/BarWidgetRegistry.qml" \
AURELIA_BAR_METADATA_CONFIG_SOURCE="$ROOT/services/ShellConfig.qml" \
AURELIA_BAR_METADATA_RESULT="$runtime_result" \
AURELIA_SHELL_CONFIG="$runtime_root/config/aurelia/shell.json" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-metadata/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e '
        .defaultFormat == "default" and
        .explicitFormat == "custom" and
        .nestedUserValue == 7 and
        .unknownUserValue == "keep" and
        .defaultOnly == 1 and
        .displayName == "Defaulted" and
        .description == "Defaulted fixture" and
        .category == "Testing" and
        .settingsForm == "fixtureSettings" and
        .defaultSection == "right" and
        .singleAllowMultiple == false and
        .multiAllowMultiple == true and
        .schemaLength == 1 and
        .normalizedEntryCount == 3 and
        .firstEntryId == "fixture.defaulted" and
        .multiInstanceIds == ["multi-a", "multi-b"] and
        .widgetCount == 2
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] defaults, explicit settings, unknown values, allowMultiple, schema, and instance addressing behave correctly"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] operational bar-widget metadata fixture failed (status=$runtime_status): $details"
fi
