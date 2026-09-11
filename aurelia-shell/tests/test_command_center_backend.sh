#!/usr/bin/env bash

# Isolated execution tests for the Command Center backend boundary. These tests
# never launch a real application: a fixture PATH records the final argv that
# the backend would detach.

set -Eeuo pipefail

section "Aurelia Command Center Backend"

fixture="$(mktemp -d)"
mock_bin="$fixture/bin"
data_home="$fixture/data"
system_data="$fixture/system"
home_dir="$fixture/home"
state_home="$fixture/state"
mock_log="$fixture/launch.log"
mkdir -p "$mock_bin" "$data_home/applications" "$system_data/applications" \
    "$home_dir/Projects/demo" "$home_dir/.config/aurelia" "$state_home" "$fixture/runtime"

cleanup_command_center_fixture() {
    rm -rf -- "$fixture"
}
trap cleanup_command_center_fixture EXIT

cat >"$data_home/applications/foot.desktop" <<'EOF_FOOT'
[Desktop Entry]
Type=Application
Name=Foot
Exec=foot
Icon=foot
Categories=System;TerminalEmulator;
EOF_FOOT

cat >"$data_home/applications/btop.desktop" <<'EOF_BTOP'
[Desktop Entry]
Type=Application
Name=btop++
Exec=btop
Terminal=true
Icon=utilities-system-monitor
Categories=System;Monitor;ConsoleOnly;
EOF_BTOP

printf '%s\n' 'fixture' >"$home_dir/Projects/demo/README.md"

cat >"$mock_bin/setsid" <<'EOF_SETSID'
#!/usr/bin/env bash
printf 'setsid' >> "$AURELIA_COMMAND_CENTER_MOCK_LOG"
for value in "$@"; do printf '\t%s' "$value" >> "$AURELIA_COMMAND_CENTER_MOCK_LOG"; done
printf '\n' >> "$AURELIA_COMMAND_CENTER_MOCK_LOG"
exit 0
EOF_SETSID

cat >"$mock_bin/uwsm-app" <<'EOF_UWSM'
#!/usr/bin/env bash
printf 'uwsm-app' >> "$AURELIA_COMMAND_CENTER_MOCK_LOG"
for value in "$@"; do printf '\t%s' "$value" >> "$AURELIA_COMMAND_CENTER_MOCK_LOG"; done
printf '\n' >> "$AURELIA_COMMAND_CENTER_MOCK_LOG"
exit 0
EOF_UWSM

cat >"$mock_bin/kitty" <<'EOF_KITTY'
#!/usr/bin/env bash
exit 0
EOF_KITTY

cat >"$mock_bin/xdg-open" <<'EOF_XDG_OPEN'
#!/usr/bin/env bash
exit 0
EOF_XDG_OPEN

chmod 0755 "$mock_bin/setsid" "$mock_bin/uwsm-app" "$mock_bin/kitty" "$mock_bin/xdg-open"

backend="$ROOT/bin/aurelia-shell-keybindings"
common_env=(
    "KEYBINDINGS_MANIFEST=$ROOT/dotfiles/hypr/keybindings_manifest.lua"
    "XDG_DATA_HOME=$data_home"
    "XDG_DATA_DIRS=$system_data"
    "XDG_CONFIG_HOME=$home_dir/.config"
    "XDG_STATE_HOME=$state_home"
    "HOME=$home_dir"
    "XDG_RUNTIME_DIR=$fixture/runtime"
    "PATH=$mock_bin:$PATH"
    "AURELIA_COMMAND_CENTER_MOCK_LOG=$mock_log"
    "WORKSTATION_TEST_MODE=1"
)

rm -f -- "$mock_log"
if env "${common_env[@]}" UWSM_FINALIZE_VARNAMES=WAYLAND_DISPLAY \
   "$backend" launch-app foot.desktop >"$fixture/foot.out" 2>"$fixture/foot.err" &&
   env "${common_env[@]}" UWSM_FINALIZE_VARNAMES=WAYLAND_DISPLAY \
   "$backend" launch-app btop.desktop >"$fixture/btop.out" 2>"$fixture/btop.err" &&
   grep -q $'^setsid\t-f\t.*/uwsm-app\t--\tfoot.desktop$' "$mock_log" &&
   grep -q $'^setsid\t-f\t.*/uwsm-app\t--\tkitty\t--\tbtop$' "$mock_log" &&
   ! grep -q 'gtk-launch' "$mock_log"; then
    pass "UWSM scopes graphical entries natively and uses the verified terminal argv for Terminal=true apps"
else
    fail "UWSM desktop-entry launch resolution did not produce the expected argv"
fi

rm -f -- "$mock_log"
plain_env=("${common_env[@]}")
if env -u UWSM_FINALIZE_VARNAMES -u UWSM_WAIT_VARNAMES -u IN_UWSM_ENV_PRELOADER \
   "${plain_env[@]}" "$backend" launch-app btop.desktop >"$fixture/plain.out" 2>"$fixture/plain.err" &&
   grep -q $'^setsid\t-f\tkitty\t--\tbtop$' "$mock_log" &&
   ! grep -q 'gtk-launch' "$mock_log"; then
    pass "Plain Hyprland falls back to the configured terminal without requiring UWSM"
else
    fail "Plain-session terminal fallback did not produce a safe structured argv: $(tr '\n' ' ' <"$mock_log" 2>/dev/null || true)"
fi

mkdir -p "$home_dir/.config/workstation"
printf '%s\n' 'terminal.default = footclient.desktop' >"$home_dir/.config/workstation/desktop.conf"
rm -f -- "$mock_log"
if env "${common_env[@]}" UWSM_FINALIZE_VARNAMES=WAYLAND_DISPLAY \
   "$backend" launch-app btop.desktop >"$fixture/configured.out" 2>"$fixture/configured.err" &&
   grep -q $'^setsid\t-f\t.*/uwsm-app\t--\tfoot\t--\tbtop$' "$mock_log" &&
   ! grep -q 'footclient' "$mock_log"; then
    pass "A footclient preference is normalized to the real Foot executable"
else
    fail "Configured footclient preference still produced an unusable terminal argv: $(tr '\n' ' ' <"$mock_log" 2>/dev/null || true)"
fi

if env "${common_env[@]}" "$backend" files readme >"$fixture/files.json" 2>"$fixture/files.err" &&
   jq -e 'length >= 1 and any(.[]; .name == "README.md" and .kind == "file" and (.path | endswith("/Projects/demo/README.md")))' \
       "$fixture/files.json" >/dev/null; then
    pass "File search returns bounded JSON rows with absolute paths"
else
    fail "File search did not return the expected structured row"
fi

rm -f -- "$mock_log"
path="$home_dir/Projects/demo/README.md"
if env -u UWSM_FINALIZE_VARNAMES -u UWSM_WAIT_VARNAMES -u IN_UWSM_ENV_PRELOADER \
   "${common_env[@]}" "$backend" open-path "$path" >"$fixture/path.out" 2>"$fixture/path.err" &&
   grep -q $'^setsid\t-f\t.*/xdg-open\t.*/Projects/demo/README.md$' "$mock_log"; then
    pass "File activation uses the standard opener through the same session wrapper"
else
    fail "File activation did not preserve the validated absolute path argv: $(tr '\n' ' ' <"$mock_log" 2>/dev/null || true)"
fi

if env "${common_env[@]}" "$backend" launch-app 'not valid.desktop' >"$fixture/invalid.out" 2>"$fixture/invalid.err"; then
    fail "Invalid desktop IDs were accepted by launch-app"
else
    pass "Invalid desktop IDs fail closed before process launch"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$ROOT/plugins/aurelia.launcher/ui/Calculator.js" "$ROOT/services/AureliaAppSearch.js" <<'NODE_LOGIC'
const calculator = require(process.argv[2]);
const search = require(process.argv[3]);

if (!calculator.evaluateQuery("2 * (3 + 4)").ok || calculator.evaluateQuery("2 * (3 + 4)").display !== "14") process.exit(1);
if (!calculator.evaluateQuery("calc 9 % 4").ok || calculator.evaluateQuery("calc 9 % 4").display !== "1") process.exit(1);
if (calculator.evaluateQuery("1 / 0").ok || calculator.isExpressionQuery("launch foot")) process.exit(1);

const rows = search.sortedEntries([
    { id: "foot", name: "Foot", genericName: "Terminal" },
    { id: "hidden", name: "Hidden", noDisplay: true },
], "ft");
if (rows.length !== 1 || rows[0].entry.id !== "foot") process.exit(1);

const globalRows = search.sortRowsWithFilesLast([
    { id: "file:readme", kind: "file", label: "README", detail: "/home/README" },
    { id: "app:readme", kind: "app", label: "README Viewer", detail: "Applications" },
    { id: "action:readme", kind: "action", label: "Readme Action", detail: "Actions" },
    { id: "module:package-manager", kind: "module", label: "Package Manager", keywords: "readme" },
], "readme");
if (globalRows.length !== 4 || globalRows[globalRows.length - 1].kind !== "file" ||
    globalRows.slice(0, -1).some(row => row.kind === "file")) process.exit(1);
NODE_LOGIC
    then
        pass "Calculator/native app helpers and global file-last search ordering pass without eval"
    else
        fail "Command Center pure logic helpers returned an unexpected result"
    fi
else
    pass "SKIP calculator/search logic runtime check (node unavailable)"
fi
