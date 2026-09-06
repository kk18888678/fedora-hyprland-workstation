section "11. First Visible Actions Hierarchy"

first_5_ids="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
print(" ".join([item["id"] for item in data[:5]]))
' <<< "$json_output")"
if [[ "$first_5_ids" == "launcher terminal file_manager browser keybindings" || "$first_5_ids" == "launcher terminal file_manager browser hotkeys" ]]; then
    pass "11. first visible actions are App Launcher, Terminal, Files, Browser, Keybindings/Hotkeys when available"
else
    fail "11. First visible actions mismatch: $first_5_ids"
fi
