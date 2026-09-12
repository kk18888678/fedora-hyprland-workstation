#!/usr/bin/env bash

# T05 source-aware catalog checks. Registry discovery remains the sole source
# of plugin metadata; the CLI only formats the resident catalog projection.

set -Eeuo pipefail

section "Aurelia Source-Aware Plugin Catalog"

registry_root="$ROOT/services/PluginRegistry.qml"
projection_root="$ROOT/services/PluginCatalogProjection.qml"
host_root="$ROOT/services/PluginHost.qml"
shell_root="$ROOT/shell.qml"
main_root="$ROOT/bin/lib/aurelia-plugin/main.sh"

if grep -q 'function pluginCatalog' "$registry_root" &&
   grep -q 'sourceRoot' "$projection_root" &&
   grep -q 'manifestPath' "$projection_root" &&
   grep -q 'function catalog()' "$host_root" &&
   grep -q 'function catalogPlugins(): string' "$shell_root" &&
   grep -q 'catalog \[--json\]' "$main_root"; then
    pass "[static] registry, resident host, shell IPC, and CLI expose one source-aware catalog"
else
    fail "[static] source-aware catalog wiring is incomplete"
fi

catalog_root="$(mktemp -d)"
trap 'rm -rf -- "$catalog_root" 2>/dev/null || true' RETURN
cat >"$catalog_root/aurelia-shell" <<'EOF_CATALOG_SHELL'
#!/usr/bin/env bash
if [[ "$1" == "shell" && "$2" == "catalogPlugins" ]]; then
    printf '%s\n' '{"plugins":[{"id":"fixture.catalog","version":"1.0.0","firstParty":false,"kinds":["panel"],"sourceRoot":"/tmp/plugins/fixture.catalog","manifestPath":"/tmp/plugins/fixture.catalog/manifest.json"}],"rejected":[{"manifestPath":"/tmp/plugins/bad/manifest.json","reason":"manifest validation failed"}],"scan":{"state":"partial","failureClass":"rejected-manifests","error":"1 rejected","rejectedCount":1}}'
    exit 0
fi
exit 1
EOF_CATALOG_SHELL
chmod 0755 "$catalog_root/aurelia-shell"

catalog_json=""
catalog_status=0
catalog_json="$(
    script_dir="$catalog_root"
    AURELIA_DEVELOPMENT_MODE=1
    AURELIA_PLUGIN_BIN_DIR="$catalog_root"
    # shellcheck source=/dev/null
    source "$ROOT/bin/lib/aurelia-plugin/common.sh"
    # shellcheck source=/dev/null
    source "$ROOT/bin/lib/aurelia-plugin/main.sh"
    aurelia_plugin_main catalog --json
)" || catalog_status=$?

if [[ "$catalog_status" -eq 0 ]] &&
   jq -e '.plugins[0].id == "fixture.catalog" and (.rejected | length == 1) and .scan.state == "partial"' \
       <<<"$catalog_json" >/dev/null; then
    pass "[static] CLI catalog --json preserves plugin source fields and rejected diagnostics"
else
    fail "[static] CLI catalog --json formatting or validation failed"
fi

catalog_human=""
catalog_status=0
catalog_human="$(
    script_dir="$catalog_root"
    AURELIA_DEVELOPMENT_MODE=1
    AURELIA_PLUGIN_BIN_DIR="$catalog_root"
    # shellcheck source=/dev/null
    source "$ROOT/bin/lib/aurelia-plugin/common.sh"
    # shellcheck source=/dev/null
    source "$ROOT/bin/lib/aurelia-plugin/main.sh"
    aurelia_plugin_main catalog
)" || catalog_status=$?

if [[ "$catalog_status" -eq 0 ]] &&
   grep -q 'fixture.catalog' <<<"$catalog_human" &&
   grep -q 'Rejected manifests:' <<<"$catalog_human" &&
   grep -q '/tmp/plugins/bad/manifest.json' <<<"$catalog_human"; then
    pass "[static] CLI catalog has a bounded human-readable projection"
else
    fail "[static] CLI human-readable catalog formatting failed"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] source-aware catalog QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
printf '%s\n' '[]' >"$runtime_root/matrix.json"
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_MANIFEST_REGISTRY_SOURCE="$ROOT/services/PluginRegistry.qml" \
AURELIA_MANIFEST_MATRIX="$runtime_root/matrix.json" \
AURELIA_MANIFEST_RESULT="$runtime_result" \
AURELIA_SHELL_ROOT="$ROOT" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/manifest-validator/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e --arg root "$ROOT" '
        .catalog.scan.state == "success" and
        .catalog.scan.rejectedCount == 0 and
        (.catalog.plugins | length == 22) and
        ([.catalog.plugins[] | select(.id == "aurelia.clock")][0].sourceRoot == ($root + "/plugins/aurelia.clock")) and
        ([.catalog.plugins[] | select(.id == "aurelia.clock")][0].manifestPath == ($root + "/plugins/aurelia.clock/manifest.json")) and
        ([.catalog.plugins[] | select(.id == "aurelia.clock")][0].entryPoints.barWidget == "ClockBarWidget.qml") and
        ([.catalog.plugins[] | select(.id == "aurelia.bluetooth")][0].barWidget.defaultSection == "right")
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] catalog exposes canonical entry points, source roots, manifest paths, metadata, and scan diagnostics"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] source-aware catalog fixture failed (status=$runtime_status): $details"
fi
