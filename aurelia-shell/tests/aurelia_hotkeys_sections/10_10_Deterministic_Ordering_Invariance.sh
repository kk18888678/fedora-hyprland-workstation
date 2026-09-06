section "10. Deterministic Ordering Invariance"

order_check="$(python3 -c '
import sys, json
data = json.loads(sys.stdin.read())
priorities = [item["priority"] for item in data]
# Verify ascending priority ordering
if priorities == sorted(priorities):
    print("ORDER_OK")
else:
    print("ORDER_MISMATCH")
' <<< "$json_output")"
if [[ "$order_check" == "ORDER_OK" ]]; then
    pass "10. priority/order is deterministic"
else
    fail "10. ordering is not deterministic"
fi
