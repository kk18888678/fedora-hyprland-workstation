#!/usr/bin/env bash

# T21 manifest-backed Aurelia menu and provider/action contract checks.

set -Eeuo pipefail

section "Aurelia Manifest-backed Menu"

menu_root="$ROOT/plugins/aurelia.menu"
model_root="$menu_root/MenuModel.qml"
surface_root="$menu_root/Menu.qml"

if [[ -f "$menu_root/manifest.json" && -f "$menu_root/menu.json" &&
      -f "$model_root" && -f "$surface_root" ]] &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$menu_root" >/dev/null 2>&1 &&
   grep -q 'allowedActions' "$model_root" &&
   grep -q 'allowedProviders' "$model_root" &&
   grep -q 'function validateItem' "$model_root" &&
   grep -q 'aurelia.menu' "$surface_root"; then
    pass "[static] aurelia.menu has a validated manifest, shipped data, and a separate bounded model/surface"
else
    fail "[static] manifest-backed Aurelia menu package is incomplete"
fi

if grep -q 'open-command-center' "$model_root" &&
   grep -q 'reload-plugins' "$model_root" &&
   grep -q 'toggle-bar' "$model_root" &&
   grep -q 'plugins-present' "$model_root" &&
   grep -q 'checkedFor' "$model_root" &&
   grep -q 'allowedWhen' "$model_root" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)|bash -c|sh -c|systemctl|sudo|pkexec' \
       "$menu_root"/*.qml "$menu_root"/*.json; then
    pass "[static] menu visibility, checked state, provider rows, and actions are allow-listed without shell strings"
else
    fail "[static] menu/provider safety contract is incomplete"
fi

if grep -q 'userMenuPath' "$model_root" &&
   grep -q 'loadUser' "$model_root" &&
   grep -q 'root.userItems' "$model_root" &&
   grep -q 'root.userFile' "$model_root"; then
    pass "[static] shipped menu data and optional XDG user extensions are separate inputs"
else
    fail "[static] menu extension input boundary is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] manifest-backed menu QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config/aurelia" "$runtime_root/cache"
jq -n '{version:1,items:[
    {id:"user.custom",label:"Custom",description:"User extension",action:"open-command-center",order:5},
    {id:"user.invalid",label:"Invalid",action:"bash -c id",order:6}
]}' >"$runtime_root/config/aurelia/menu.json"
result_path="$runtime_root/result.json"
runtime_status=0
AURELIA_MENU_MODEL_SOURCE="$model_root" \
AURELIA_MENU_MODEL_RESULT="$result_path" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/aurelia-menu/model.qml" \
    >"$runtime_root/menu.log" 2>&1 || runtime_status=$?
if [[ "$runtime_status" -eq 0 ]] && jq -e '
    .commandCenter and .provider and .custom and .invalidRejected and
    .checked and .toggleResult and .lastAction == "toggle:aurelia.bar"
  ' "$result_path" >/dev/null; then
    pass "[isolated-runtime] menu model merges safe user extensions, exposes providers, evaluates checked state, and dispatches approved actions"
else
    details="$(tail -n 24 "$runtime_root/menu.log" 2>/dev/null || true)"
    fail "[isolated-runtime] menu model fixture failed (status=$runtime_status): $details"
fi
