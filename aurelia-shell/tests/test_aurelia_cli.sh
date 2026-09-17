#!/usr/bin/env bash

# Aurelia unified CLI (omarchy-style `aurelia <group> <command>`) test suite.
# The dispatcher only re-executes bounded backends; every forwarding path is
# exercised in a disposable fake shell root with recording stubs.

set -Eeuo pipefail

section "Aurelia Unified CLI"

cli="$ROOT/bin/aurelia"
keybind_lua="$ROOT/dotfiles/hypr/keybind.lua"
effective_lua="$ROOT/dotfiles/hypr/effective_bindings.lua"
manifest_lua="$ROOT/dotfiles/hypr/keybindings_manifest.lua"
desktop_sh="$(cd -- "$ROOT/.." && pwd -P)/modules/desktop.sh"

# ---------------------------------------------------------------------------
# Static invariants
# ---------------------------------------------------------------------------
if [[ -x "$cli" && -f "$cli" ]] &&
   grep -q 'Aurelia command center' "$cli" &&
   grep -q 'run_backend' "$cli"; then
    pass "[static] unified aurelia CLI exists, is executable, and dispatches to bounded backends"
else
    fail "[static] aurelia CLI entry point is missing or incomplete"
fi

missing_group=0
for group in bar plugin theme settings shell keybindings display capture audio wallpaper commands; do
    if ! grep -q "cmd_${group}\b\|cmd_${group}()" "$cli" && [[ "$group" != "commands" ]]; then
        fail "[static] aurelia CLI group missing: $group"
        missing_group=1
    fi
done
if [[ "$missing_group" -eq 0 ]]; then
    pass "[static] aurelia CLI declares the omarchy-style groups"
fi

if grep -q 'resolve_shell_ipc' "$keybind_lua" &&
   grep -q 'desktop_settings' "$keybind_lua" &&
   grep -q 'ipc .. " shell toggle aurelia.settings"' "$keybind_lua" &&
   grep -q 'action_id == "desktop_settings"' "$effective_lua" &&
   grep -q 'toggle", "aurelia.settings"' "$effective_lua"; then
    pass "[static] desktop_settings resolves the shell IPC client absolutely (no PATH dependence)"
else
    fail "[static] desktop_settings PATH-independent resolution is incomplete"
fi

if grep -q 'command = "aurelia settings toggle"' "$manifest_lua" &&
   grep -q '"aurelia", "settings", "toggle"' "$manifest_lua"; then
    pass "[static] desktop_settings manifest uses the canonical aurelia CLI form"
else
    fail "[static] desktop_settings manifest does not target the aurelia settings group"
fi

if grep -q 'install_aurelia_cli()' "$desktop_sh" &&
   grep -q '"/usr/local/bin/aurelia"' "$desktop_sh" &&
   grep -q '"/usr/local/bin/aurelia-shell"' "$desktop_sh"; then
    pass "[static] installer deploys aurelia CLI + IPC client to /usr/local/bin"
else
    fail "[static] installer CLI deployment step is missing"
fi

# ---------------------------------------------------------------------------
# Sandbox forwarding (recording stubs, disposable fake shell root)
# ---------------------------------------------------------------------------
sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox" || true' RETURN
mkdir -p -- "$sandbox/root/bin" "$sandbox/bin"

cat >"$sandbox/bin/workstation-hypr-settings" <<'STUB_HYPR'
#!/usr/bin/env bash
printf 'workstation-hypr-settings|%s\n' "$*" >>"${AURCLI_LOG:?}"
STUB_HYPR
chmod +x "$sandbox/bin/workstation-hypr-settings"

for tool in aurelia-bar aurelia-plugin aurelia-theme aurelia-theme-bg aurelia-shell \
    aurelia-screenshot aurelia-restart-shell aurelia-shell-keybindings \
    aurelia-display-text-size; do
    cat >"$sandbox/root/bin/$tool" <<STUB
#!/usr/bin/env bash
printf '$tool|%s\n' "\$*" >>"\${AURCLI_LOG:?}"
STUB
    chmod +x "$sandbox/root/bin/$tool"
done
cp "$cli" "$sandbox/root/bin/aurelia"
chmod +x "$sandbox/root/bin/aurelia"

export AURELIA_SHELL_ROOT="$sandbox/root"
export AURCLI_LOG="$sandbox/forward.log"
: >"$AURCLI_LOG"

forward_ok=1
expect_line() {
    local expected="$1"
    if ! grep -Fxq "$expected" "$AURCLI_LOG"; then
        fail "[sandbox] forwarding missing: $expected"
        forward_ok=0
    fi
}

"$sandbox/root/bin/aurelia" bar transparent toggle
"$sandbox/root/bin/aurelia" bar position bottom
"$sandbox/root/bin/aurelia" bar move aurelia.clock --section center --index 0
"$sandbox/root/bin/aurelia" bar set aurelia.clock format HH:mm
"$sandbox/root/bin/aurelia" bar defaults
"$sandbox/root/bin/aurelia" plugin disable aurelia.weather
"$sandbox/root/bin/aurelia" plugin enable example.plugin --section center
"$sandbox/root/bin/aurelia" settings toggle
"$sandbox/root/bin/aurelia" settings hypr set general.gaps_in 6
"$sandbox/root/bin/aurelia" theme list
"$sandbox/root/bin/aurelia" theme bg next
"$sandbox/root/bin/aurelia" shell ping
"$sandbox/root/bin/aurelia" capture screenshot region --delay 2

expect_line "aurelia-bar|transparent toggle"
expect_line "aurelia-bar|position bottom"
expect_line "aurelia-bar|move aurelia.clock --section center --index 0"
expect_line "aurelia-bar|set aurelia.clock format HH:mm"
expect_line "aurelia-bar|defaults"
expect_line "aurelia-plugin|disable aurelia.weather"
expect_line "aurelia-plugin|enable example.plugin --section center"
expect_line "aurelia-shell|shell toggle aurelia.settings {}"
expect_line "workstation-hypr-settings|set general.gaps_in 6"
expect_line "aurelia-theme|list"
expect_line "aurelia-theme-bg|next"
expect_line "aurelia-shell|shell ping"
expect_line "aurelia-screenshot|capture region --delay 2"
if [[ "$forward_ok" -eq 1 ]]; then
    pass "[sandbox] bar/plugin/theme/settings/shell/capture arguments forward exactly"
fi

if "$sandbox/root/bin/aurelia" commands --json | python3 -c '
import json, sys
names = [e["name"] for e in json.load(sys.stdin)]
assert "bar" in names and "plugin" in names and "settings" in names and "commands" in names
' >/dev/null; then
    pass "[sandbox] aurelia commands --json is valid machine-readable output"
else
    fail "[sandbox] aurelia commands --json failed"
fi

if "$sandbox/root/bin/aurelia" commands --check >/dev/null; then
    pass "[sandbox] aurelia commands --check resolves every first-party backend"
else
    fail "[sandbox] aurelia commands --check failed in the fake shell root"
fi
