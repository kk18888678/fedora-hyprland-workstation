section "36. Verification Matrix V: Path Auto-Complete, External File Chooser, and Focus Release Invariants"

# 36.1: choose-file simulated accept returns exit code 0 and path
cf_accept_rc=0
cf_accept_out="$(WORKSTATION_TEST_CHOOSE_FILE="accept:/usr/bin/git" "$ROOT/bin/workstation-keybindings" choose-file 2>&1)" || cf_accept_rc=$?
if [[ "$cf_accept_rc" -eq 0 && "$cf_accept_out" == "/usr/bin/git" ]]; then
    pass "36.1 choose-file simulated accept returns exit code 0 and selected path"
else
    fail "36.1 choose-file simulated accept failed: rc=$cf_accept_rc out=$cf_accept_out"
fi

# 36.2: choose-file simulated cancel returns exit code 1 and no path
cf_cancel_rc=0
cf_cancel_out="$(WORKSTATION_TEST_CHOOSE_FILE="cancel" "$ROOT/bin/workstation-keybindings" choose-file 2>&1)" || cf_cancel_rc=$?
if [[ "$cf_cancel_rc" -eq 1 && -z "$cf_cancel_out" ]]; then
    pass "36.2 choose-file simulated cancel returns exit code 1 and empty output"
else
    fail "36.2 choose-file simulated cancel failed: rc=$cf_cancel_rc out=$cf_cancel_out"
fi

# 36.3: choose-file simulated error returns exit code 2
cf_err_rc=0
cf_err_out="$(WORKSTATION_TEST_CHOOSE_FILE="error:simulated portal failure" "$ROOT/bin/workstation-keybindings" choose-file 2>&1)" || cf_err_rc=$?
if [[ "$cf_err_rc" -eq 2 && "$cf_err_out" == *"simulated portal failure"* ]]; then
    pass "36.3 choose-file simulated error returns exit code 2 and logs error"
else
    fail "36.3 choose-file simulated error failed: rc=$cf_err_rc out=$cf_err_out"
fi

# 36.4: complete-path immediate directory only (no recursive traversal)
test_dir="$(mktemp -d)"
mkdir -p "$test_dir/subdir/nested"
touch "$test_dir/file1.sh" "$test_dir/subdir/file2.sh" "$test_dir/subdir/nested/file3.sh"
cp_imm_out="$("$ROOT/bin/workstation-keybindings" complete-path "$test_dir/")"
if jq -e . <<< "$cp_imm_out" >/dev/null 2>&1 && \
   jq -e 'index("'"$test_dir"'/subdir/") != null' <<< "$cp_imm_out" >/dev/null 2>&1 && \
   jq -e 'index("'"$test_dir"'/file1.sh") != null' <<< "$cp_imm_out" >/dev/null 2>&1 && \
   ! grep -q "file2.sh" <<< "$cp_imm_out" && \
   ! grep -q "file3.sh" <<< "$cp_imm_out"; then
    pass "36.4 complete-path enumerates immediate directory only without recursive descent"
else
    fail "36.4 complete-path immediate directory check failed: out=$cp_imm_out"
fi
rm -rf "$test_dir"

# 36.5: complete-path strictly bounded to max 15 entries
test_bound_dir="$(mktemp -d)"
for i in $(seq 1 25); do
    printf -v fname "%02d_item" "$i"
    touch "$test_bound_dir/$fname"
done
cp_bound_out="$("$ROOT/bin/workstation-keybindings" complete-path "$test_bound_dir/")"
bound_len="$(jq '. | length' <<< "$cp_bound_out")"
if [[ "$bound_len" -eq 15 ]]; then
    pass "36.5 complete-path strictly bounded to maximum 15 entries (got 15 from 25 items)"
else
    fail "36.5 complete-path bound check failed: length=$bound_len"
fi
rm -rf "$test_bound_dir"

# 36.6: complete-path deterministic sort (directories first with trailing slash, then files)
test_sort_dir="$(mktemp -d)"
mkdir -p "$test_sort_dir/zebra_dir" "$test_sort_dir/apple_dir"
touch "$test_sort_dir/zebra_file.sh" "$test_sort_dir/apple_file.sh"
cp_sort_out="$("$ROOT/bin/workstation-keybindings" complete-path "$test_sort_dir/")"
first_entry="$(jq -r '.[0]' <<< "$cp_sort_out")"
second_entry="$(jq -r '.[1]' <<< "$cp_sort_out")"
third_entry="$(jq -r '.[2]' <<< "$cp_sort_out")"
fourth_entry="$(jq -r '.[3]' <<< "$cp_sort_out")"
if [[ "$first_entry" == "$test_sort_dir/apple_dir/" && \
      "$second_entry" == "$test_sort_dir/zebra_dir/" && \
      "$third_entry" == "$test_sort_dir/apple_file.sh" && \
      "$fourth_entry" == "$test_sort_dir/zebra_file.sh" ]]; then
    pass "36.6 complete-path orders deterministically: directories first (with /), then files alphabetical"
else
    fail "36.6 complete-path sorting failed: out=$cp_sort_out"
fi
rm -rf "$test_sort_dir"

# 36.7: complete-path permission errors and non-existent directories fail safe to empty list
test_perm_dir="$(mktemp -d)"
mkdir -p "$test_perm_dir/locked"
chmod 0000 "$test_perm_dir/locked"
cp_locked_out="$("$ROOT/bin/workstation-keybindings" complete-path "$test_perm_dir/locked/")"
cp_nonexist_out="$("$ROOT/bin/workstation-keybindings" complete-path "/non/existent/path/12345/")"
if [[ "$cp_locked_out" == "[]" && "$cp_nonexist_out" == "[]" ]]; then
    pass "36.7 complete-path fails safe to empty list on permission denial or missing directory"
else
    fail "36.7 complete-path error handling failed: locked=$cp_locked_out nonexist=$cp_nonexist_out"
fi
chmod 0755 "$test_perm_dir/locked"
rm -rf "$test_perm_dir"

# 36.8: complete-path strictly rejects shell injection and metacharacters
cp_inj_tested=true
for payload in '$PATH' '`whoami`' '/tmp/test*' '/tmp/test?' '/tmp/[a-z]' '/tmp/a;rm' '/tmp/a&&b' '/tmp/a|b' '/tmp/(a)'; do
    out="$("$ROOT/bin/workstation-keybindings" complete-path "$payload")"
    if [[ "$out" != "[]" ]]; then
        cp_inj_tested=false
        break
    fi
done
if [[ "$cp_inj_tested" == true ]]; then
    pass "36.8 complete-path rejects shell metacharacters and expansion characters without execution"
else
    fail "36.8 complete-path allowed shell metacharacters: payload=$payload out=$out"
fi

# 36.9: complete-path explicitly expands ~ to target user home
cp_tilde_out="$("$ROOT/bin/workstation-keybindings" complete-path "~/")"
if jq -e . <<< "$cp_tilde_out" >/dev/null 2>&1 && \
   ! grep -q '"~/' <<< "$cp_tilde_out" && \
   grep -q "\"$HOME" <<< "$cp_tilde_out"; then
    pass "36.9 complete-path expands ~ to absolute home directory without shell evaluation"
else
    fail "36.9 complete-path tilde expansion failed: out=$cp_tilde_out"
fi

# 36.10: complete-path empty or whitespace-only input returns []
cp_empty_out="$("$ROOT/bin/workstation-keybindings" complete-path "")"
cp_white_out="$("$ROOT/bin/workstation-keybindings" complete-path "   ")"
if [[ "$cp_empty_out" == "[]" && "$cp_white_out" == "[]" ]]; then
    pass "36.10 complete-path empty and whitespace prefix returns empty array"
else
    fail "36.10 complete-path empty check failed: empty=$cp_empty_out white=$cp_white_out"
fi

# 36.11: workstation-keybindings CLI argument parsing routes choose-file and complete-path
cmd_help_out="$("$ROOT/bin/workstation-keybindings" --help 2>&1 || true)"
if grep -q "choose-file" <<< "$cmd_help_out" && grep -q "complete-path" <<< "$cmd_help_out"; then
    pass "36.11 CLI help documents choose-file and complete-path commands"
else
    fail "36.11 CLI help missing choose-file or complete-path: $cmd_help_out"
fi

# 36.12: QML static check: KeybindingsWindow.qml does NOT import QtQuick.Dialogs
if ! grep -q 'import QtQuick\.Dialogs' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml"; then
    pass "36.12 KeybindingsWindow.qml does NOT import QtQuick.Dialogs (prevents modal layer-shell deadlock)"
else
    fail "36.12 KeybindingsWindow.qml still imports QtQuick.Dialogs!"
fi

# 36.13: QML static check: KeybindingsWindow.qml contains no FileDialog element
if ! grep -q 'FileDialog {' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml"; then
    pass "36.13 KeybindingsWindow.qml contains no in-process FileDialog element"
else
    fail "36.13 KeybindingsWindow.qml still contains FileDialog element!"
fi

# 36.14: QML static check: KeybindingsWindow.qml implements browseActive property
if grep -q 'property bool browseActive:' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml"; then
    pass "36.14 KeybindingsWindow.qml implements browseActive property"
else
    fail "36.14 KeybindingsWindow.qml missing browseActive property"
fi

# 36.15: QML static check: keyboard focus released to None during external browse
if grep -q 'windowRoot\.browseActive ? WlrKeyboardFocus\.None' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml"; then
    pass "36.15 KeybindingsWindow.qml releases keyboard focus to WlrKeyboardFocus.None during browse"
else
    fail "36.15 KeybindingsWindow.qml missing WlrKeyboardFocus.None release during browse"
fi

# 36.16: QML static check: ShortcutInhibitor disabled during external browse
if grep -q '!windowRoot\.browseActive && windowRoot\.isRecording' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml"; then
    pass "36.16 KeybindingsWindow.qml disables ShortcutInhibitor while browse is active"
else
    fail "36.16 KeybindingsWindow.qml does not disable ShortcutInhibitor during browse"
fi

# 36.17: QML static check: triggerBrowse guards against shortcut capture
if grep -q 'function triggerBrowse()' "$qml_form" && \
   grep -q 'if (windowController\.isRecording' "$qml_form"; then
    pass "36.17 triggerBrowse guards against shortcut recording state"
else
    fail "36.17 triggerBrowse missing shortcut recording guard"
fi

# 36.18: QML static check: structured lifecycle logging for browse events
if grep -q 'keybindings\.browse\.request' "$qml_form" && \
   grep -q 'keybindings\.browse\.focus_release' "$qml_form" && \
   grep -q 'keybindings\.browse\.focus_restore' "$qml_form"; then
    pass "36.18 KeybindingsWindow.qml logs structured browse lifecycle events"
else
    fail "36.18 KeybindingsWindow.qml missing structured browse lifecycle logging"
fi

# 36.19: QML static check: Path Auto-Complete UI component exists
if grep -q 'id: suggestionPopup' "$qml_form" && \
   grep -q 'modelController\.fetchPathCompletions' "$qml_form"; then
    pass "36.19 KeybindingsWindow.qml declares suggestionPopup with keybindingsModel.fetchPathCompletions"
else
    fail "36.19 suggestionPopup or fetchPathCompletions call missing in KeybindingsWindow.qml"
fi

# 36.20: QML static check: visible key labels standardized to uppercase
if grep -q 'Theme\.shortcutAddAction' "$qml_footer" && \
   grep -q 'Theme\.shortcutBack' "$qml_footer" && \
   grep -q 'Theme\.shortcutSet' "$qml_footer" && \
   grep -q 'Theme\.shortcutUnset' "$qml_footer" && \
   grep -q 'text: "TAB"' "$qml_footer" && \
   grep -q 'text: "ESC"' "$qml_footer"; then
    pass "36.20 visible navigation shortcuts standardized to uppercase display typography"
else
    fail "36.20 visible navigation shortcuts uppercase standardization check failed"
fi

# 36.21: QML static check: Return glyph ↵ preserved
if grep -q 'text: "↵"' "$qml_footer"; then
    pass "36.21 Return shortcut glyph ↵ preserved across UI hints"
else
    fail "36.21 Return shortcut glyph ↵ missing in KeybindingsWindow.qml"
fi

# 36.22: QML static check: production uses canonical path; development override is explicit
if grep -q 'AURELIA_DEVELOPMENT_MODE' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsModel.qml" && \
   grep -q 'AURELIA_SHELL_KEYBINDINGS_BIN' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsModel.qml" && \
   grep -q '/usr/local/bin/aurelia-shell-keybindings' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsModel.qml" && \
   ! grep -q '/\.local/bin/' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsModel.qml"; then
    pass "36.22 KeybindingsModel.qml uses canonical production binary with explicit development override"
else
    fail "36.22 KeybindingsModel.qml production/development binary authority check failed"
fi

# 36.23: QML static check: KeybindingsModel.qml provides pathCompletions and fetchPathCompletions
if grep -q 'property var pathCompletions:' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsModel.qml" && \
   grep -q 'function fetchPathCompletions(' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsModel.qml"; then
    pass "36.23 KeybindingsModel.qml implements pathCompletions model and fetchPathCompletions"
else
    fail "36.23 KeybindingsModel.qml missing pathCompletions or fetchPathCompletions"
fi
