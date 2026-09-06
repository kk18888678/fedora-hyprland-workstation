section "8. Structured Backend Data Consumption"

json_output="$("$ROOT/bin/workstation-hotkeys" json)"
json_count="$(python3 -c 'import sys, json; data = json.loads(sys.stdin.read()); print(len(data))' <<< "$json_output")"
if [[ "$json_count" -ge 30 ]]; then
    pass "8. Aurelia Hotkeys consumes structured backend data ($json_count items exported)"
else
    fail "8. Failed to export structured backend JSON: count=$json_count"
fi
