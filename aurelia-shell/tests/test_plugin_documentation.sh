#!/usr/bin/env bash

# T26 authoring-guide, example-plugin, and documentation synchronization checks.

set -Eeuo pipefail

section "Aurelia Plugin Authoring Documentation"

guide="$ROOT/docs/aurelia-plugin-authoring.md"
contract="$ROOT/docs/aurelia-plugin-contract-v1.md"
plugins_readme="$ROOT/plugins/README.md"
shell_readme="$ROOT/README.md"
example_root="$ROOT/examples/plugins/example.panel"
example_manifest="$example_root/manifest.json"
example_entry="$example_root/Panel.qml"

if [[ -f "$guide" && -f "$contract" && -f "$plugins_readme" && -f "$shell_readme" ]] &&
   grep -q 'aurelia-plugin-contract-v1.md' "$guide" &&
   grep -q 'AURELIA-OMARCHY-PLUGIN-PARITY-TRACKER.md' "$guide" &&
   grep -q 'aurelia-plugin-authoring.md' "$plugins_readme" &&
   grep -q 'aurelia-plugin-authoring.md' "$shell_readme"; then
    pass "[static] authoring guide, normative contract, tracker, and both Aurelia README surfaces are linked"
else
    fail "[static] plugin documentation links are incomplete"
fi

if grep -q 'schemaVersion' "$guide" &&
   grep -q 'entryPoints' "$guide" &&
   grep -q 'barWidget' "$guide" &&
   grep -q 'keepLoaded' "$guide" &&
   grep -q 'PluginRegistryApi' "$guide" &&
   grep -q 'PluginShellApi' "$guide" &&
   grep -q 'PluginBarApi' "$guide" &&
   grep -q 'unsandboxed' "$guide" &&
   grep -q 'AURELIA_DEVELOPMENT_MODE' "$guide" &&
   grep -q 'AURELIA_HOT_RELOAD' "$guide" &&
   grep -q 'aurelia-shell/tests' "$guide"; then
    pass "[static] guide documents schema, kinds, lifecycle, facades, trust, reload, and testing boundaries"
else
    fail "[static] authoring guide is missing a required contract topic"
fi

if [[ -f "$example_manifest" && -f "$example_entry" &&
      "$example_root" != "$ROOT/plugins/"* ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "example.panel" and
       .kinds == ["panel"] and
       (.entryPoints | length == 1) and
       .entryPoints.panel == "Panel.qml"
   ' "$example_manifest" >/dev/null &&
   grep -q 'function open(payloadJson)' "$example_entry" &&
   grep -q 'function close()' "$example_entry" &&
   ! grep -Eq '\b(sudo|pkexec|systemctl|install\.sh)\b' "$example_entry" &&
   ! find -P "$example_root" -type l -print -quit | grep -q .; then
    pass "[static] minimal example is isolated from production plugins and remains hook-free"
else
    fail "[static] minimal example plugin shape or safety boundary is incomplete"
fi

validation_output=""
validation_status=0
validation_output="$("$ROOT/bin/aurelia-plugin" validate "$example_root" 2>&1)" || validation_status=$?
if [[ "$validation_status" -eq 0 &&
      "$validation_output" == *"Valid Aurelia plugin: example.panel"* ]]; then
    pass "[isolated-cli] minimal example validates through the canonical author-facing CLI"
else
    fail "[isolated-cli] minimal example validation failed: $validation_output"
fi

if grep -q 'validate' "$guide" &&
   grep -q 'list \[--json\]' "$guide" &&
   grep -q 'catalog \[--json\]' "$guide" &&
   grep -q 'rescan' "$guide" &&
   grep -q 'enable' "$guide" &&
   grep -q 'disable' "$guide" &&
   grep -q 'add' "$guide" &&
   grep -q 'update' "$guide" &&
   grep -q 'clone' "$guide" &&
   grep -q 'remove' "$guide" &&
   grep -q 'rollback' "$guide"; then
    pass "[static] guide covers validation, discovery, activation, maintenance, clone, removal, and rollback commands"
else
    fail "[static] authoring and maintenance command documentation is incomplete"
fi
