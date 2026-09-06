section "Metadata-Driven Order, Key Capture, and App Shortcuts"

order_sandbox="$(mktemp -d)"
order_overrides="$order_sandbox/overrides.json"
echo "{}" > "$order_overrides"

# 1. Deterministic ordering verification
ordered_list="$(HOTKEYS_OVERRIDES="$order_overrides" HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys")"
top_action_ids=()
while IFS=$'\t' read -r id _rest; do
    top_action_ids+=("$id")
done <<< "$ordered_list"

if [[ "${top_action_ids[0]}" == "launcher" &&
      "${top_action_ids[1]}" == "terminal" &&
      "${top_action_ids[2]}" == "file_manager" &&
      "${top_action_ids[3]}" == "browser" &&
      ( "${top_action_ids[4]}" == "keybindings" || "${top_action_ids[4]}" == "hotkeys" ) &&
      "${top_action_ids[5]}" == "desktop_settings" &&
      "${top_action_ids[6]}" == "lock_screen" ]]; then
    pass "workstation-hotkeys presents items in explicit deterministic metadata-driven priority order"
else
    fail "workstation-hotkeys ordering mismatch: ${top_action_ids[*]:0:7}"
fi

# 2. Legacy fzf provider removal and rejection
leg_rc=0
leg_err="$("$ROOT/bin/workstation-keybindings" --provider=legacy 2>&1)" || leg_rc=$?
if [[ "$leg_rc" -ne 0 && "$leg_err" == *"Legacy provider has been removed"* ]]; then
    pass "legacy fzf provider is removed and fails closed with actionable error"
else
    fail "legacy fzf provider was not rejected: rc=$leg_rc err=$leg_err"
fi

# 3. Application shortcut assignment
if HOTKEYS_OVERRIDES="$order_overrides" HOTKEYS_TEST_ACTION=assign_app HOTKEYS_TEST_ID="chatgpt.desktop" HOTKEYS_TEST_INPUT="SUPER + SHIFT + C" "$ROOT/bin/workstation-hotkeys" >/dev/null; then
    pass "assign_application_shortcut successfully assigns shortcut to desktop_id"
else
    fail "assign_application_shortcut failed"
fi

app_list="$(HOTKEYS_OVERRIDES="$order_overrides" HOTKEYS_TEST_ACTION=list "$ROOT/bin/workstation-hotkeys")"
if grep -q "app:chatgpt.desktop" <<< "$app_list" && grep -q "Super + Shift + C" <<< "$app_list"; then
    pass "assigned application shortcut appears in workstation-hotkeys manifest listing with friendly formatting"
else
    fail "assigned application shortcut missing from hotkeys listing: $app_list"
fi

app_argv="$(HOTKEYS_OVERRIDES="$order_overrides" HOTKEYS_TEST_ACTION=run_argv HOTKEYS_TEST_ID="app:chatgpt.desktop" "$ROOT/bin/workstation-hotkeys")"
if [[ "$app_argv" == $'gtk-launch\n--\nchatgpt.desktop' ]]; then
    pass "application shortcut produces structured argv [gtk-launch -- chatgpt.desktop]"
else
    fail "unexpected app shortcut argv: $app_argv"
fi

# Rejection of leading dash option injection
leaddash_exit=0
leaddash_out="$(HOTKEYS_OVERRIDES="$order_overrides" HOTKEYS_TEST_ACTION=assign_app HOTKEYS_TEST_ID="-option.desktop" HOTKEYS_TEST_INPUT="SUPER + SHIFT + Z" "$ROOT/bin/workstation-hotkeys" 2>&1)" || leaddash_exit=$?
if [[ "$leaddash_exit" -ne 0 && "$leaddash_out" == *"Invalid desktop ID"* ]]; then
    pass "assign_application_shortcut rejects leading dash desktop ID injection"
else
    fail "leading dash injection was not rejected: code=$leaddash_exit out=$leaddash_out"
fi

# Conflict detection against assigned application shortcut and modifier permutations
perm_exit=0
perm_out="$(HOTKEYS_OVERRIDES="$order_overrides" HOTKEYS_TEST_ACTION=assign_app HOTKEYS_TEST_ID="brave-origin.desktop" HOTKEYS_TEST_INPUT="SHIFT + SUPER + C" "$ROOT/bin/workstation-hotkeys" 2>&1)" || perm_exit=$?

if [[ "$perm_exit" -ne 0 && "$perm_out" == *"Conflict"* && "$perm_out" == *"chatgpt.desktop"* ]]; then
    pass "conflict detection catches collisions across modifier permutations (SHIFT + SUPER + C vs SUPER + SHIFT + C)"
else
    fail "app collision check failed: code=$perm_exit out=$perm_out"
fi

# 4. Display row format: ONE ROW = HOTKEY + APP/ACTION without metadata leaks
first_display_row="$(head -n 1 <<< "$ordered_list" | cut -f 2)"
second_display_row="$(head -n 2 <<< "$ordered_list" | tail -n 1 | cut -f 2)"
meta_leak_col="$(head -n 1 <<< "$ordered_list" | cut -f 10)"

if [[ "$first_display_row" =~ ^[[:space:]]+Super[[:space:]]\+[[:space:]]D[[:space:]]+App[[:space:]]Launcher$ ]] &&
   [[ "$first_display_row" != *"["* && "$first_display_row" != *"launcher"* && "$first_display_row" != *"Applications"* && "$first_display_row" != *$'\e'* ]]; then
    pass "workstation-hotkeys formats display row strictly as friendly HOTKEY + APP/ACTION"
else
    fail "display row violates clean one-row format: $first_display_row"
fi

if [[ "$second_display_row" =~ ^[[:space:]]+Super[[:space:]]\+[[:space:]]Return[[:space:]]+Terminal$ ]] &&
   [[ "$second_display_row" != *"kitty"* && "$second_display_row" != *"terminal"* ]]; then
    pass "workstation-hotkeys renders [Super + Return        Terminal] cleanly"
else
    fail "second display row format unexpected: $second_display_row"
fi

if ! grep -q 'fzf' "$ROOT/bin/workstation-keybindings" &&
   ! grep -q 'foot --app-id=workstation-hotkeys' "$ROOT/bin/workstation-keybindings"; then
    pass "workstation-keybindings has zero fzf UI or terminal fallback dependencies"
else
    fail "workstation-keybindings still contains fzf execution or terminal fallback references"
fi

# Verification of format_friendly_key and canonical invariance
lua_friendly_check="$(luajit -e '
package.path = "dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
assert(eff.format_friendly_key("SUPER + D") == "Super + D", "Failed Super + D")
assert(eff.format_friendly_key("SUPER + RETURN") == "Super + Return", "Failed Super + Return")
assert(eff.format_friendly_key("SUPER + SHIFT + T") == "Super + Shift + T", "Failed Super + Shift + T")
assert(eff.format_friendly_key("ALT + TAB") == "Alt + Tab", "Failed Alt + Tab")
assert(eff.format_friendly_key("CTRL + ALT + X") == "Ctrl + Alt + X", "Failed Ctrl + Alt + X")

-- Canonical invariance
assert(eff.canonical_key("SUPER + SHIFT + T") == eff.canonical_key("Shift + Super + T"), "Canonical mismatch")
assert(eff.canonical_key("SUPER + RETURN") == "super+return", "Canonical return mismatch")
print("OK")
')"
if [[ "$lua_friendly_check" == "OK" ]]; then
    pass "friendly display formatting and canonical internal representation invariance verified"
else
    fail "friendly formatting / canonical invariance check failed: $lua_friendly_check"
fi

# 5. Physical key capture mock mode
mock_cap_out="$(HOTKEYS_CAPTURE_MOCK_INPUT="SUPER + SHIFT + T" "$ROOT/bin/workstation-hotkey-capture")"
if [[ "$mock_cap_out" == "KEY:SUPER + SHIFT + T" ]]; then
    pass "workstation-hotkey-capture returns formatted key combination in test capture mode"
else
    fail "key capture mock failed: $mock_cap_out"
fi

mock_unbind_out="$(HOTKEYS_CAPTURE_MOCK_INPUT="unbind" "$ROOT/bin/workstation-hotkey-capture")"
if [[ "$mock_unbind_out" == "UNBIND" ]]; then
    pass "workstation-hotkey-capture handles unbind input safely"
else
    fail "unbind capture mock failed: $mock_unbind_out"
fi

mock_cancel_code=0
mock_cancel_out="$(HOTKEYS_CAPTURE_MOCK_INPUT="cancel" "$ROOT/bin/workstation-hotkey-capture" 2>&1)" || mock_cancel_code=$?
if [[ "$mock_cancel_code" -eq 1 && "$mock_cancel_out" == "CANCEL" ]]; then
    pass "workstation-hotkey-capture handles cancellation safely with non-zero exit code"
else
    fail "cancel capture mock failed: code=$mock_cancel_code out=$mock_cancel_out"
fi

# 6. Capture stdout purity and fail-closed non-interactive behavior
clean_cap_out="$(python3 -c '
import subprocess
out = subprocess.check_output(["'"$ROOT/bin/workstation-hotkey-capture"'"], stdin=subprocess.DEVNULL)
assert out == b"MANUAL\n", f"Expected b\"MANUAL\\n\", got {out}"
print("STDOUT_CLEAN")
')"
if [[ "$clean_cap_out" == "STDOUT_CLEAN" ]]; then
    pass "workstation-hotkey-capture emits clean stdout with zero escape sequences in non-interactive mode"
else
    fail "capture stdout polluted: $clean_cap_out"
fi

# 7. Kitty protocol parser with shifted sub-arguments and bare key fail-closed
parser_test_out="$(python3 -c '
with open("'"$ROOT/bin/workstation-hotkey-capture"'") as f:
    code = f.read()
ns = {}
exec(code, ns)
ok1, res1 = ns["parse_kitty_sequence"]("\x1b[116:84;9u")
assert ok1 and res1 == "SUPER + T", f"Failed shifted: {res1}"
ok2, res2 = ns["parse_kitty_sequence"]("\x1b[116;16u")
assert ok2 and res2 == "SUPER + CTRL + ALT + SHIFT + T", f"Failed all mods: {res2}"
print("PARSER_OK")
')"
if [[ "$parser_test_out" == "PARSER_OK" ]]; then
    pass "Kitty protocol parser handles shifted key sub-arguments and canonical modifier sorting"
else
    fail "Kitty protocol parser failed: $parser_test_out"
fi

rm -rf "$order_sandbox"
