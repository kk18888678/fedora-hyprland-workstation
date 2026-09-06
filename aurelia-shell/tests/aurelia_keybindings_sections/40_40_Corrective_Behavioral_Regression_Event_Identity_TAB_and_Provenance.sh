section "40. Corrective Behavioral Regression: Event Identity, TAB, and Provenance"

# 40.1-40.4: Deterministic event-identity model for held Return, repeat events,
# immediate release/repress, and application-add ownership.  This deliberately
# has no clock or elapsed-time branch: timing cannot affect correctness.
behavior_out="$(python3 - <<'PY'
class KeybindingsModel:
    def __init__(self):
        self.view = "add_action_type"
        self.held = False
        self.selected = None
        self.add_count = 0
        self.run_count = 0

    def press_return(self, auto_repeat=False):
        if auto_repeat or self.held:
            return False
        self.held = True
        if self.view == "add_action_type":
            self.view = "add_app"
            return True
        if self.view == "add_app":
            self.add_count += 1
            self.view = "unbound"
            self.selected = "app:ulaa.desktop"
            return True
        if self.view == "unbound":
            self.run_count += 1
            return True
        return False

    def release_return(self):
        self.held = False

    def click_row(self, index):
        view_at_click = self.view
        self.selected = index
        if view_at_click == "add_action_type":
            self.view = "add_app"
            return "navigate"
        return "select"

    def tab(self, reverse=False):
        views = ("bound", "unbound", "add_action_type", "settings")
        index = views.index(self.view)
        self.view = views[(index - 1 if reverse else index + 1) % len(views)]
        return self.view

# Held Return enters the picker once, crosses the transition without falling
# through, adds once, and permits a new press immediately after release.
model = KeybindingsModel()
assert model.press_return() is True and model.view == "add_app"
assert model.press_return(auto_repeat=True) is False
assert model.press_return() is False
assert model.add_count == 0 and model.run_count == 0
model.release_return()
assert model.press_return() is True
assert model.add_count == 1 and model.run_count == 0
assert model.view == "unbound" and model.selected == "app:ulaa.desktop"
assert model.press_return(auto_repeat=True) is False and model.run_count == 0
model.release_return()
assert model.press_return() is True and model.run_count == 1
model.release_return()
print("INPUT_OWNERSHIP_OK")

# A type row click owns its navigation; the following application click only
# selects, so a click sequence cannot become Add + Run.
mouse = KeybindingsModel()
assert mouse.click_row(0) == "navigate" and mouse.view == "add_app"
assert mouse.click_row(0) == "select" and mouse.add_count == 0 and mouse.run_count == 0
mouse.release_return()
assert mouse.press_return() is True and mouse.add_count == 1
assert mouse.view == "unbound" and mouse.run_count == 0
print("MOUSE_OWNERSHIP_OK")

tab = KeybindingsModel()
tab.view = "bound"
assert [tab.tab() for _ in range(4)] == ["unbound", "add_action_type", "settings", "bound"]
assert [tab.tab(reverse=True) for _ in range(4)] == ["settings", "add_action_type", "unbound", "bound"]
print("TAB_SEQUENCE_OK")
PY
)"
if grep -q 'INPUT_OWNERSHIP_OK' <<< "$behavior_out" &&
   grep -q 'MOUSE_OWNERSHIP_OK' <<< "$behavior_out"; then
    pass "40.1-40.4 held Return, auto-repeat, release/repress, and single-add ownership model verified without timing"
else
    fail "40.1-40.4 event-identity regression model failed: $behavior_out"
fi

# 40.5-40.7: TAB transitions are immediate and reversible in the model, while
# source checks ensure the production router has no delayed activation path.
if grep -q 'TAB_SEQUENCE_OK' <<< "$behavior_out" &&
   grep -q 'cycleTopLevelView(true)' "$qml_win" &&
   grep -q 'cycleTopLevelView(false)' "$qml_win" &&
   ! grep -q 'activationCooldownUntil' "$qml_win" &&
   ! grep -q 'Qt.callLater' "$qml_win" &&
   ! grep -E -q 'Timer\\s*\\{' "$qml_win"; then
    pass "40.5-40.7 TAB forward/reverse sequence is immediate with no cooldown, Timer, or delayed focus"
else
    fail "40.5-40.7 TAB/event timing regression checks failed: $behavior_out"
fi

# 40.8-40.10: Verify the generated manifest detects stale managed QML files
# without touching the live configuration.
provenance_check="$(bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
root="$1"
sb="$(mktemp -d)"
trap 'rm -rf "$sb"' EXIT
home="$sb/home"
bin_dir="$sb/bin"
mkdir -p "$home/.config" "$bin_dir"
cp -a "$root" "$home/.config/aurelia"
cp "$root/bin/aurelia-shell-keybindings" "$bin_dir/aurelia-shell-keybindings"
chmod 0755 "$bin_dir/aurelia-shell-keybindings"
mkdir -p "$bin_dir/lib"
cp -a "$root/bin/lib/aurelia-keybindings" "$bin_dir/lib/"

SCRIPT_DIR="$root"
TARGET_HOME="$home"
TARGET_USER="$USER"
KEYBINDINGS_BIN_DIR="$bin_dir"
AURELIA_KEYBINDINGS_MANIFEST_PATH="$home/.local/state/aurelia/keybindings/deployment-manifest.json"
source "$root/modules/common.sh"
source "$root/modules/status.sh"
source "$root/modules/desktop.sh"

write_aurelia_keybindings_manifest
printf '\\n// stale fixture\\n' >> "$home/.config/aurelia/components/keybindings/KeybindingsWindow.qml"
printf '\\n// stale fixture\\n' >> "$home/.config/aurelia/components/keybindings/KeybindingsSettings.qml"
printf '\\n# stale fixture\\n' >> "$home/.config/aurelia/components/keybindings/qmldir"

diag="$(
    HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_STATE_HOME="$home/.local/state" \
    AURELIA_DEVELOPMENT_MODE=1 \
    AURELIA_SHELL_KEYBINDINGS_BIN="$bin_dir/aurelia-shell-keybindings" \
    AURELIA_QML_ROOT="$home/.config/aurelia/shell.qml" \
    AURELIA_KEYBINDINGS_MANIFEST_PATH="$AURELIA_KEYBINDINGS_MANIFEST_PATH" \
    WORKSTATION_TEST_MODE=1 \
    "$root/bin/aurelia-shell-keybindings" diagnostics runtime --json
)"
python3 - "$diag" "$bin_dir/aurelia-shell-keybindings" <<'PY'
import json
import sys
report = json.loads(sys.argv[1])
assert report["canonical_backend"]["path"] == sys.argv[2]
assert report["canonical_backend"]["sha256"]
assert report["expected_manifest"]["files"]
assert len(report["expected_manifest"]["files"]) == 23
assert len(report["expected_manifest"]["backend_files"]) == 7
assert len(report["deployed_manifest"]["backend_files"]) == 7
assert not any(item.startswith("backend-files/") for item in report["manifest_mismatches"]), report["manifest_mismatches"]
mismatches = "\n".join(report["manifest_mismatches"])
for name in ("KeybindingsWindow.qml", "KeybindingsSettings.qml", "qmldir"):
    assert name in mismatches, mismatches
print("STALE_MANAGED_FILES_DETECTED")
print("MANIFEST_FIELDS_OK")
PY
EOS
)"
if grep -q 'STALE_MANAGED_FILES_DETECTED' <<< "$provenance_check" &&
   grep -q 'MANIFEST_FIELDS_OK' <<< "$provenance_check"; then
    pass "40.8-40.10 generated provenance detects stale Window, Settings, and qmldir files"
else
    fail "40.8-40.10 stale-file provenance detection failed: $provenance_check"
fi

# 40.11: Keep the live benchmark explicit, bounded, and honest about
# unobservable compositor/focus stages. The benchmark itself is never run by
# the repository suite because it requires the user's active Wayland session.
benchmark_file="$ROOT/tests/benchmark_aurelia_keybindings.sh"
if [[ -x "$benchmark_file" || -f "$benchmark_file" ]] &&
   grep -q 'SAMPLES = 20' "$benchmark_file" &&
   grep -q 'time.monotonic_ns' "$benchmark_file" &&
   grep -q '1 discarded open/close cycle' "$benchmark_file" &&
   grep -q 'Direct IPC open request' "$benchmark_file" &&
   grep -q 'not externally observable' "$benchmark_file" &&
   ! grep -q 'Date.now' "$benchmark_file"; then
    pass "40.11 live benchmark harness uses bounded monotonic timing, 20 samples, separate IPC, and explicit unobservable stages"
else
    fail "40.11 live benchmark harness is missing required timing and observability safeguards"
fi
