#!/usr/bin/env bash

# T32 source descriptor, relocation, and dynamic-loader checks.

set -Eeuo pipefail

section "Aurelia Dynamic Source Boundary"

forbidden_local_file_prefix='file://'"/"
resolver_qml="$ROOT/services/PluginSourceResolver.qml"
resolver_js="$ROOT/services/SourceUrl.js"
registry_root="$ROOT/services/PluginRegistry.qml"
host_root="$ROOT/services/PluginHost.qml"
bar_registry_root="$ROOT/services/BarWidgetRegistry.qml"
fixture_root="$ROOT/tests/fixtures/source-boundary"

if [[ -f "$resolver_qml" && -f "$resolver_js" ]] &&
   grep -Fq 'PluginSourceResolver 1.0 PluginSourceResolver.qml' "$ROOT/services/qmldir" &&
   grep -Fq 'function sourceDescriptor(id, kind)' "$registry_root" &&
   grep -Fq 'function sourceDescriptor(id, kind)' "$host_root" &&
   grep -Fq 'function sourceDescriptorFor(id)' "$bar_registry_root"; then
    pass "[static] source descriptors are owned by the resolver, registry, host, and bar registry"
else
    fail "[static] host-owned source descriptor wiring is incomplete"
fi

if ! /usr/bin/rg -n -F --glob '*.qml' --glob '*.js' --glob '*.sh' \
       '"file://" +' "$ROOT" \
       --glob '!**/tests/**' --glob '!**/examples/**' \
       --glob '!**/services/SourceUrl.js' --glob '!**/services/PluginSourceResolver.qml' >/dev/null 2>&1 &&
   ! /usr/bin/rg -n --glob '*.qml' --glob '*.js' --glob '*.sh' \
       '/home/user/Projects' "$ROOT" --glob '!**/tests/**' --glob '!**/examples/**' >/dev/null 2>&1; then
    pass "[static] production has no ad-hoc file-URL concatenation or developer checkout path"
else
    fail "[static] production source path construction still contains an ad-hoc or fixed checkout path"
fi

if ! /usr/bin/rg -n --hidden --glob '!.git/**' -F "$forbidden_local_file_prefix" \
       "$ROOT/.." >/dev/null 2>&1; then
    pass "[static] no repository file embeds the forbidden local file-URL prefix"
else
    fail "[static] forbidden local file-URL prefix is still embedded in the repository"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$resolver_js" <<'NODE_SOURCE'
const source = require(process.argv[2]);
const path = '/tmp/alternate root/Δ files/#capture?.png%';
const url = source.fileUrl(path);
if (!url.startsWith('file://')) process.exit(1);
if (source.pathFromUrl(url) !== path) process.exit(1);
if (source.pathFromUrl('file://localhost/tmp/example') !== '/tmp/example') process.exit(1);
if (source.pathFromUrl('file://remote/tmp/example') !== '') process.exit(1);
if (source.pathFromUrl('file://%ZZ') !== '') process.exit(1);
if (!source.isSafeRelativePath('ui/Panel.qml')) process.exit(1);
if (source.isSafeRelativePath('../Panel.qml')) process.exit(1);
if (source.isSafeRelativePath('/tmp/Panel.qml')) process.exit(1);
if (source.isSafeRelativePath('ui\\Panel.qml')) process.exit(1);
const resolved = source.resolvePath('/tmp/alternate root/Δ files', 'ui/Panel.qml');
if (resolved !== '/tmp/alternate root/Δ files/ui/Panel.qml') process.exit(1);
if (source.resolvePath('/tmp/root', '../outside.qml') !== '') process.exit(1);
if (source.resolveUrl('relative-root', 'Panel.qml') !== '') process.exit(1);
if (!source.isDescendant(resolved, '/tmp/alternate root/Δ files')) process.exit(1);
if (source.isDescendant('/tmp/alternate root-other/Panel.qml', '/tmp/alternate root')) process.exit(1);
NODE_SOURCE
    then
        pass "[isolated-runtime] source path/URL round trips, local authority checks, encoding, and root containment pass"
    else
        fail "[isolated-runtime] source path/URL contract failed"
    fi
else
    skip "[isolated-runtime] source URL model checks (node unavailable)"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] dynamic source loader fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN

run_relocation_case() {
    local case_name="$1"
    local destination="$runtime_root/$case_name/unchanged tree/Δ source"
    local result="$runtime_root/$case_name/result.json"
    local log="$runtime_root/$case_name/runtime.log"
    local runtime_status=0
    mkdir -p -- "$destination" "$runtime_root/$case_name/runtime" "$runtime_root/$case_name/state" \
        "$runtime_root/$case_name/config" "$runtime_root/$case_name/cache"
    cp -- "$fixture_root/Healthy.qml" "$destination/Healthy.qml"

    AURELIA_SOURCE_BOUNDARY_ROOT="$destination" \
    AURELIA_SOURCE_BOUNDARY_RESULT="$result" \
    AURELIA_SOURCE_BOUNDARY_RESOLVER="file://$ROOT/services/PluginSourceResolver.qml" \
    AURELIA_SHELL_ROOT="$ROOT" \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$runtime_root/$case_name/runtime" \
    XDG_STATE_HOME="$runtime_root/$case_name/state" \
    XDG_CONFIG_HOME="$runtime_root/$case_name/config" \
    XDG_CACHE_HOME="$runtime_root/$case_name/cache" \
        /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
        --path "$fixture_root/shell.qml" --no-color >"$log" 2>&1 || runtime_status=$?

    if [[ "$runtime_status" -ne 0 || ! -s "$result" ]]; then
        fail "[isolated-runtime] relocation case failed to finish: $case_name (status=$runtime_status)"
        sed -n '1,160p' "$log" >&2 || true
        sed -n '1,40p' "$result" >&2 || true
        return
    fi
    if jq -e --arg root "$destination" '
        .healthyLoaded == true and
        .healthyMarker == "healthy-source" and
        .sourceRoot == $root and
        .descriptorValid == true and
        .descriptorSourceRoot == $root and
        .descriptorEntryPoint == "Healthy.qml" and
        .sourcePath == ($root + "/Healthy.qml") and
        .roundTripPath == ($root + "/Healthy.qml") and
        .invalidEntryUrl == "" and
        .remotePath == ""
    ' "$result" >/dev/null; then
        pass "[isolated-runtime] unchanged source tree loads from dynamic relocated root: $case_name"
    else
        fail "[isolated-runtime] dynamic source relocation result was unsafe or not loadable: $case_name"
        sed -n '1,120p' "$log" >&2 || true
        sed -n '1,40p' "$result" >&2 || true
    fi
}

run_relocation_case first
run_relocation_case second

run_registry_case() {
    local case_name="$1"
    local source_root="$runtime_root/$case_name/registry tree/Δ source"
    local plugin_root="$source_root/aurelia.source-fixture"
    local result="$runtime_root/$case_name/registry-result.json"
    local log="$runtime_root/$case_name/registry.log"
    local runtime_status=0
    mkdir -p -- "$plugin_root" "$runtime_root/$case_name/runtime" "$runtime_root/$case_name/state" \
        "$runtime_root/$case_name/config" "$runtime_root/$case_name/cache"
    jq -n '{schemaVersion:1,id:"aurelia.source-fixture",name:"Source Fixture",version:"1.0.0",description:"T32 source fixture",kinds:["panel"],entryPoints:{panel:"Panel.qml"}}' \
        >"$plugin_root/manifest.json"
    cp -- "$fixture_root/Healthy.qml" "$plugin_root/Panel.qml"

    AURELIA_SOURCE_REGISTRY_SOURCE="file://$ROOT/services/PluginRegistry.qml" \
    AURELIA_SOURCE_REGISTRY_FIRST_PARTY="$source_root" \
    AURELIA_SOURCE_REGISTRY_RESULT="$result" \
    AURELIA_SHELL_ROOT="$ROOT" \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$runtime_root/$case_name/runtime" \
    XDG_STATE_HOME="$runtime_root/$case_name/state" \
    XDG_CONFIG_HOME="$runtime_root/$case_name/config" \
    XDG_CACHE_HOME="$runtime_root/$case_name/cache" \
        /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
        --path "$fixture_root/registry.qml" --no-color >"$log" 2>&1 || runtime_status=$?

    if [[ "$runtime_status" -ne 0 || ! -s "$result" ]]; then
        fail "[isolated-runtime] registry descriptor case failed: $case_name (status=$runtime_status)"
        sed -n '1,160p' "$log" >&2 || true
        sed -n '1,40p' "$result" >&2 || true
        return
    fi
    if jq -e --arg root "$source_root" --arg plugin "$plugin_root" '
        .scanState == "success" and
        .descriptorValid == true and
        .descriptorId == "aurelia.source-fixture" and
        .descriptorKind == "panel" and
        .descriptorSourceRoot == $plugin and
        .descriptorEntryPoint == "Panel.qml" and
        .descriptorSourcePath == ($plugin + "/Panel.qml") and
        (.descriptorUrl | startswith("file://")) and
        .legacyUrl == .descriptorUrl and
        .invalidUrl == "" and
        (.invalidError | length > 0)
    ' "$result" >/dev/null; then
        pass "[isolated-runtime] real PluginRegistry emits a validated dynamic source descriptor: $case_name"
    else
        fail "[isolated-runtime] registry descriptor was invalid or unsafe: $case_name"
        sed -n '1,160p' "$log" >&2 || true
        sed -n '1,40p' "$result" >&2 || true
    fi
}

run_registry_case registry
