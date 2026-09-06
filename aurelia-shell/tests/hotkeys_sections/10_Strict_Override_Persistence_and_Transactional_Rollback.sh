section "Strict Override Persistence and Transactional Rollback"

# 1. Truncated JSON is rejected entirely
printf '{"terminal": "SUPER + RETURN"' > "$sandbox_overrides"
trunc_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || trunc_ret=$?
if [[ "$trunc_ret" -ne 0 ]]; then
    pass "truncated JSON override file is rejected entirely"
else
    fail "truncated JSON override was accepted"
fi

# 2. Trailing garbage after JSON object is rejected
printf '{"terminal": "SUPER + RETURN"} trailing_garbage' > "$sandbox_overrides"
trail_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || trail_ret=$?
if [[ "$trail_ret" -ne 0 ]]; then
    pass "trailing garbage after JSON object is rejected"
else
    fail "trailing garbage after JSON object was accepted"
fi

# 3. Malformed value in overrides is rejected
printf '{"terminal": 123}' > "$sandbox_overrides"
val_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || val_ret=$?
if [[ "$val_ret" -ne 0 ]]; then
    pass "malformed number value in overrides is rejected"
else
    fail "malformed number value was accepted"
fi

# 4. Unsupported boolean true in overrides is rejected
printf '{"terminal": true}' > "$sandbox_overrides"
true_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true_ret=$?
if [[ "$true_ret" -ne 0 ]]; then
    pass "unsupported boolean true in overrides is rejected"
else
    fail "unsupported boolean true was accepted"
fi

# 5. Unsupported null in overrides is rejected
printf '{"terminal": null}' > "$sandbox_overrides"
null_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || null_ret=$?
if [[ "$null_ret" -ne 0 ]]; then
    pass "unsupported null in overrides is rejected"
else
    fail "unsupported null was accepted"
fi

# 6. Unknown action ID in overrides is rejected
printf '{"unknown_action_xyz": "SUPER + A"}' > "$sandbox_overrides"
unk_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || unk_ret=$?
if [[ "$unk_ret" -ne 0 ]]; then
    pass "unknown action ID in overrides is rejected"
else
    fail "unknown action ID was accepted"
fi

# 7. Malformed override does not partially apply earlier valid entries
printf '{\n  "file_manager": "SUPER + ALT + E",\n  "terminal": 123\n}\n' > "$sandbox_overrides"
partial_ret=0
HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || partial_ret=$?
# Verify via Lua that resolve_bindings returns nil error and does not yield partial table
partial_lua_ok=0
partial_check="$(
    "$lua_bin" - "$ROOT" "$sandbox_overrides" <<'LUA_CHECK'
package.path = arg[1] .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")
local res, err = eff.resolve_bindings(manifest, eff.load_overrides(arg[2], manifest))
if res == nil and err then
    print("FAIL_CLOSED_OK")
end
LUA_CHECK
)"
if [[ "$partial_ret" -ne 0 && "$partial_check" == *"FAIL_CLOSED_OK"* ]]; then
    pass "malformed override does not partially apply earlier valid entries"
else
    fail "malformed override was partially applied"
fi

# 8. Simulated successful reload commits candidate override
printf '{\n  "file_manager": "SUPER + ALT + M"\n}\n' > "$sandbox_overrides"
tx_commit_ret=0
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + N" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || tx_commit_ret=$?
if [[ "$tx_commit_ret" -eq 0 ]] && grep -q "SUPER + ALT + N" "$sandbox_overrides"; then
    pass "simulated successful reload commits candidate override"
else
    fail "simulated successful reload failed to commit candidate"
fi

# 9. Simulated reload failure restores exact previous override content
pre_content="$(cat "$sandbox_overrides")"
tx_fail_ret=0
HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || tx_fail_ret=$?
post_content="$(cat "$sandbox_overrides")"
if [[ "$tx_fail_ret" -ne 0 && "$pre_content" == "$post_content" ]]; then
    pass "simulated reload failure restores exact previous override content"
else
    fail "simulated reload failure did not restore previous content: ret=$tx_fail_ret"
fi

# 10. Simulated reload failure when no previous override existed restores absence
rm -f "$sandbox_overrides"
tx_noprev_ret=0
HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || tx_noprev_ret=$?
if [[ "$tx_noprev_ret" -ne 0 && ! -f "$sandbox_overrides" ]]; then
    pass "simulated reload failure when no previous override existed restores absence"
else
    fail "simulated reload failure failed to restore absence of override file: ret=$tx_noprev_ret exists=$(test -f "$sandbox_overrides" && echo 1 || echo 0)"
fi

# 11. Rollback failure is surfaced as a hard failure
tx_rb_fail_out="$(HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_SIMULATE_ROLLBACK_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" 2>&1)" || true
if [[ "$tx_rb_fail_out" == *"FATAL:"* ]]; then
    pass "rollback failure is surfaced as a hard failure"
else
    fail "rollback failure did not surface FATAL error: $tx_rb_fail_out"
fi

# 12. Reload failure is never swallowed
tx_swallow_ret=0
HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || tx_swallow_ret=$?
if [[ "$tx_swallow_ret" -ne 0 ]]; then
    pass "reload failure is never swallowed"
else
    fail "reload failure was swallowed (returned 0)"
fi

# 13. Normal save creates override file with restrictive 0600 permissions
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + M" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
perm_check="$(stat -c %a "$sandbox_overrides" 2>/dev/null || true)"
if [[ "$perm_check" == "600" ]]; then
    pass "override file is created with restrictive 0600 permissions via exclusive mktemp"
else
    fail "override file permissions are not 0600: $perm_check"
fi

# 14. Exclusive creation does not follow or overwrite pre-existing symlinks
decoy_file="$sandbox_dir/decoy.txt"
printf "DO_NOT_CORRUPT_DECOY\n" > "$decoy_file"
ln -s "$decoy_file" "$sandbox_dir/.tmp.overrides.123456"
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + N" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
decoy_after="$(cat "$decoy_file")"
if [[ "$decoy_after" == "DO_NOT_CORRUPT_DECOY" ]]; then
    pass "exclusive temporary file creation avoids following or corrupting symlinks"
else
    fail "exclusive temporary creation followed or corrupted symlink"
fi
rm -f "$sandbox_dir/.tmp.overrides.123456" "$decoy_file"

# 15. Failed write/replace does not leave leftover temporary files
leftover_tmp="$(find "$sandbox_dir" -maxdepth 1 -name ".tmp.overrides.*")"
if [[ -z "$leftover_tmp" ]]; then
    pass "no leftover temporary files remain after normal save operations"
else
    fail "leftover temporary files remained after normal save: $leftover_tmp"
fi

HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
leftover_fail_tmp="$(find "$sandbox_dir" -maxdepth 1 -name ".tmp.overrides.*")"
if [[ -z "$leftover_fail_tmp" ]]; then
    pass "no leftover temporary files remain after failed reload transactions"
else
    fail "leftover temporary files remained after failed reload transaction: $leftover_fail_tmp"
fi

# 16. Single owner reload: successful edit causes exactly one transactional reload attempt
reload_audit_log="$sandbox_dir/reload_audit.log"
export HOTKEYS_RELOAD_LOG="$reload_audit_log"

: > "$reload_audit_log"
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + E" "$ROOT/bin/workstation-hotkeys" >/dev/null
edit_reload_count="$(wc -l < "$reload_audit_log")"
if [[ "$edit_reload_count" -eq 1 ]]; then
    pass "successful edit causes exactly one transactional reload attempt with single owner"
else
    fail "successful edit triggered unexpected number of reload attempts: $edit_reload_count"
fi

# 17. Single owner reload: successful unset causes exactly one transactional reload attempt
: > "$reload_audit_log"
HOTKEYS_TEST_ACTION=unset HOTKEYS_TEST_ID="file_manager" "$ROOT/bin/workstation-hotkeys" >/dev/null
unset_reload_count="$(wc -l < "$reload_audit_log")"
if [[ "$unset_reload_count" -eq 1 ]]; then
    pass "successful unset causes exactly one transactional reload attempt"
else
    fail "successful unset triggered unexpected number of reload attempts: $unset_reload_count"
fi

# 18. Single owner reload: successful reset causes exactly one transactional reload attempt
: > "$reload_audit_log"
HOTKEYS_TEST_ACTION=reset HOTKEYS_TEST_ID="file_manager" "$ROOT/bin/workstation-hotkeys" >/dev/null
reset_reload_count="$(wc -l < "$reload_audit_log")"
if [[ "$reset_reload_count" -eq 1 ]]; then
    pass "successful reset causes exactly one transactional reload attempt"
else
    fail "successful reset triggered unexpected number of reload attempts: $reset_reload_count"
fi

# 19. Reload failure causes rollback, reports failure rather than UI success, and preserves old content
HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + M" "$ROOT/bin/workstation-hotkeys" >/dev/null
pre_fail_content="$(cat "$sandbox_overrides")"
: > "$reload_audit_log"
fail_exit_code=0
fail_out="$(HOTKEYS_SIMULATE_RELOAD_FAIL=1 HOTKEYS_TEST_ACTION=edit HOTKEYS_TEST_ID="file_manager" HOTKEYS_TEST_INPUT="SUPER + ALT + Z" "$ROOT/bin/workstation-hotkeys" 2>&1)" || fail_exit_code=$?
post_fail_content="$(cat "$sandbox_overrides")"

if [[ "$fail_exit_code" -ne 0 && "$fail_out" == *"EDIT_FAIL"* && "$fail_out" == *"rolled back"* ]]; then
    pass "reload failure is reported as failure rather than UI success"
else
    fail "reload failure was incorrectly reported: code=$fail_exit_code out=$fail_out"
fi

if [[ "$pre_fail_content" == "$post_fail_content" ]]; then
    pass "previous valid override content survives transaction rollback intact"
else
    fail "override content was altered despite transaction rollback"
fi

rm -rf "$sandbox_dir"
unset HOTKEYS_OVERRIDES
unset HOTKEYS_MANIFEST
unset HOTKEYS_RELOAD_LOG
