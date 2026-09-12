#!/usr/bin/env bash

# T22 all-first-party canonical manifest and preservation matrix.

set -Eeuo pipefail

section "Aurelia Existing Plugin Canonical Migration"

plugin_root="$ROOT/plugins"
manifest_count=0
matrix_failures=0
while IFS= read -r manifest; do
    manifest_count=$((manifest_count + 1))
    plugin_dir="${manifest%/manifest.json}"
    plugin_id="$(jq -r '.id' "$manifest")"
    if ! jq -e '
        (.kinds | index("bar-widget")) == null or
        (.entryPoints | has("barWidget") and (has("bar-widget") | not)) and
        (.barWidget | type == "object")
      ' "$manifest" >/dev/null; then
        printf 'Non-canonical bar manifest: %s\n' "$manifest" >&2
        matrix_failures=$((matrix_failures + 1))
    fi
    if ! "$ROOT/bin/aurelia-plugin" validate --first-party "$plugin_dir" >/dev/null 2>&1; then
        printf 'Manifest validation failed: %s\n' "$manifest" >&2
        matrix_failures=$((matrix_failures + 1))
    fi
    while IFS= read -r kind; do
        entry_key="$kind"
        [[ "$kind" == "bar-widget" ]] && entry_key="barWidget"
        entry_point="$(jq -r --arg key "$entry_key" '.entryPoints[$key] // empty' "$manifest")"
        if [[ -z "$entry_point" || ! -f "$plugin_dir/$entry_point" || -L "$plugin_dir/$entry_point" ]]; then
            printf 'Missing safe entry point: %s %s\n' "$plugin_id" "$entry_point" >&2
            matrix_failures=$((matrix_failures + 1))
        fi
    done < <(jq -r '.kinds[]' "$manifest")
done < <(find -P "$plugin_root" -mindepth 2 -maxdepth 2 -type f -name manifest.json -print | LC_ALL=C sort)

if [[ "$manifest_count" -eq 22 && "$matrix_failures" -eq 0 ]]; then
    pass "[static] every shipped first-party plugin has a canonical validated manifest and safe declared entry points"
else
    fail "[static] first-party canonical migration matrix failed (manifests=$manifest_count failures=$matrix_failures)"
fi

if grep -q 'entryPointUrl(id, kind)' "$ROOT/services/PluginRegistry.qml" &&
   grep -q 'configurePluginTarget' "$ROOT/services/PluginHost.qml" &&
   grep -q 'settingsForEntry' "$ROOT/services/PluginHost.qml" &&
   grep -q 'barWidgetRegistry' "$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml" &&
   grep -q 'aureliaPath' "$ROOT/services/PluginHost.qml"; then
    pass "[static] all migrated plugins retain generic registry loading, canonical settings injection, and host-owned backend path injection"
else
    fail "[static] generic migrated-plugin host boundary is incomplete"
fi

if [[ "$manifest_count" -eq 22 ]] &&
   jq -e '[.plugins[] | select(.kinds | index("bar-widget"))] | length == 11' \
       "$ROOT/tests/fixtures/plugin-preservation.json" >/dev/null &&
   grep -q 'defaultBar' "$ROOT/tests/fixtures/plugin-preservation.json" &&
   grep -q 'Theme' "$ROOT/plugins/aurelia.bar/Bar.qml"; then
    pass "[static] canonical migration preserves the feature inventory, default bar contract, and Aurelia design-token owner"
else
    fail "[static] canonical migration preservation fixture is incomplete"
fi
