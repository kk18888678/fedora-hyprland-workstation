section "Installer Interactive TUI Frame Rendering and Visible Feedback"

# 53a. wizard_review_plan visibly echoes selection ('a')
plan_echo="PLAN_ECHO"
init_plan "$plan_echo"
finalize_plan "$plan_echo"
tui_tmp="$(mktemp)"
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="a"
echo_action=""
wizard_review_plan "$plan_echo" echo_action > "$tui_tmp"
echo_out="$(cat "$tui_tmp")"
if [[ "$echo_action" == "APPLY" && "$echo_out" == *"Select option [a/e/c]: a"* ]]; then
    pass "53a. wizard_review_plan visibly echoes accepted option 'a' immediately on the prompt line"
else
    fail "53a. wizard_review_plan failed to echo 'a': action=$echo_action out=$echo_out"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS

# 53b. wizard_review_plan visibly echoes cancellation ('c')
WIZARD_MOCK_INPUT=1
WIZARD_MOCK_KEYS="c"
cancel_action=""
wizard_review_plan "$plan_echo" cancel_action > "$tui_tmp"
cancel_out="$(cat "$tui_tmp")"
if [[ "$cancel_action" == "CANCEL" && "$cancel_out" == *"Select option [a/e/c]: c"* ]]; then
    pass "53b. wizard_review_plan visibly echoes cancellation option 'c' immediately on the prompt line"
else
    fail "53b. wizard_review_plan failed to echo 'c': action=$cancel_action out=$cancel_out"
fi
unset WIZARD_MOCK_INPUT WIZARD_MOCK_KEYS
rm -f "$tui_tmp"

# 53c. _wizard_render_frame calculates line count and clear escape sequence correctly
tui_render_tmp="$(mktemp)"
_wizard_supports_cursor() { return 0; }
lines_ref=0
_wizard_render_frame lines_ref $'Line 1\nLine 2\nLine 3\n' > /dev/null
first_count=$lines_ref
_wizard_render_frame lines_ref $'Updated 1\nUpdated 2\n' > "$tui_render_tmp"
second_count=$lines_ref
render_body="$(cat "$tui_render_tmp")"
rm -f "$tui_render_tmp"
unset -f _wizard_supports_cursor

if [[ "$render_body" == *$'\r\033[3A\033[JUpdated 1'* && "$first_count" -eq 3 && "$second_count" -eq 2 ]]; then
    pass "53c. _wizard_render_frame emits cursor rollback and clear sequence for in-place redraw"
else
    fail "53c. _wizard_render_frame did not emit correct escape sequence: first=$first_count second=$second_count body=$render_body"
fi
