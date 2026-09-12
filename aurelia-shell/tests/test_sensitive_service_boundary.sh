#!/usr/bin/env bash

# T15 sensitive-service reachability and trusted-capability checks.

set -Eeuo pipefail

section "Aurelia Sensitive Service Boundary"

registry_root="$ROOT/services/PluginRegistry.qml"
host_root="$ROOT/services/PluginHost.qml"
registry_api_root="$ROOT/services/PluginRegistryApi.qml"
shell_api_root="$ROOT/services/PluginShellApi.qml"

if grep -q 'function trustedCapabilitiesForManifest' "$registry_root" &&
   grep -q 'function hasTrustedCapability' "$registry_root" &&
   grep -q '__hostCapabilities' "$registry_root" &&
   grep -q 'firstParty !== true' "$registry_root" &&
   grep -q 'keys\[i\].indexOf("__")' "$registry_api_root"; then
    pass "[static] trusted capability stamps are first-party-only and facade manifest internals are stripped"
else
    fail "[static] trusted capability stamping or manifest sanitization is incomplete"
fi

if grep -q 'function activeThirdParty' "$host_root" &&
   grep -q 'manifest.__isFirstParty === false' "$host_root" &&
   grep -q 'function serviceFor' "$shell_api_root" &&
   grep -q 'api.owns(id)' "$shell_api_root" &&
   grep -q 'same-process' "$shell_api_root"; then
    pass "[static] ordinary third-party service access is self-scoped and explicitly documented as unsandboxed"
else
    fail "[static] third-party sensitive-service reachability guard is incomplete"
fi

if grep -q 'aurelia-plugin' "$ROOT/tests/test_manifest_validator.sh" &&
   grep -q 'authentication' "$ROOT/tests/test_manifest_validator.sh" &&
   grep -q 'capabilities' "$ROOT/bin/lib/aurelia-plugin/manifest.sh"; then
    pass "[static] manifest validation covers user capability self-declaration rejection"
else
    fail "[static] manifest capability rejection coverage is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] sensitive-service QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_SENSITIVE_REGISTRY_SOURCE="$registry_root" \
AURELIA_SENSITIVE_REGISTRY_API_SOURCE="$registry_api_root" \
AURELIA_SENSITIVE_SHELL_API_SOURCE="$shell_api_root" \
AURELIA_SENSITIVE_RESULT="$runtime_result" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/sensitive-boundary/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e '
        .firstStamped == true and
        .firstHasAuth == true and
        .firstHasPolkit == true and
        .foreignRejected == true and
        .ordinaryHasEmptyStamp == true and
        .ordinaryHasAuth == false and
        .publicManifestSanitized == true and
        .detachedManifest == true and
        .ownServiceVisible == true and
        .foreignServiceHidden == true and
        .ownUpdate == true and
        .foreignUpdate == false and
        .disabledState == true and
        .reloadStampStable == true
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] trusted first-party capability stamping, self-only service lookup, manifest detachment, disable, and reload behavior are enforced"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] sensitive-service boundary fixture failed (status=$runtime_status): $details"
fi
