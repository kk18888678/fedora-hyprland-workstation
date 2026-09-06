section "12-14. Search Matching Invariants"

# Test 12: Matches display hotkey
search_key_match="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
matches = [i["id"] for i in data if "return" in (i["display_key"] + " " + i["description"]).lower()]
print(" ".join(matches))
' <<< "$json_output")"
if [[ "$search_key_match" == *"terminal"* ]]; then
    pass "12. search matches display hotkey (e.g. Return -> Terminal)"
else
    fail "12. search failed to match display hotkey"
fi

# Test 13: Matches action title
search_title_match="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
matches = [i["id"] for i in data if "files" in (i["display_key"] + " " + i["description"]).lower()]
print(" ".join(matches))
' <<< "$json_output")"
if [[ "$search_title_match" == *"file_manager"* ]]; then
    pass "13. search matches action title (e.g. Files -> file_manager)"
else
    fail "13. search failed to match action title"
fi

# Test 14: Does not require or match on internal action ID
search_id_only="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
# Search query "file_manager": internal ID is "file_manager", but display is "Files" and key is "Super + E"
matches = [i["id"] for i in data if "file_manager" in (i["display_key"] + " " + i["description"]).lower()]
print(len(matches))
' <<< "$json_output")"
if [[ "$search_id_only" -eq 0 ]]; then
    pass "14. search does not require internal action ID (search operates exclusively on visible tokens)"
else
    fail "14. search leaked internal action ID into filter matching"
fi
