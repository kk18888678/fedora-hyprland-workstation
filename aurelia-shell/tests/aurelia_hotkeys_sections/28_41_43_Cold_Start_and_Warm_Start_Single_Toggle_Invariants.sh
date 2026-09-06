section "41-43. Cold-Start and Warm-Start Single-Toggle Invariants"

# Test 41: Cold start invokes mutating toggle exactly once after non-mutating ping
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "--path" ]]; then
    echo "ipc_path:$3" >> "$MOCK_LOG"
    if [[ "$4" == "call" && ( "$5" == "keybindings" || "$5" == "hotkeys" ) ]]; then
        if [[ "$6" == "ping" ]]; then
            echo "ping" >> "$MOCK_LOG"
            # Ping fails before daemon is started, succeeds after daemon start
            if ! grep -q "^daemon_start$" "$MOCK_LOG"; then
                exit 1
            fi
            echo "true"
            exit 0
        elif [[ "$6" == "toggle" ]]; then
            echo "toggle" >> "$MOCK_LOG"
            exit 0
        fi
    fi
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
    toggle_count="$(grep -c '^toggle$' "$mock_log" || true)"
    ping_count="$(grep -c '^ping$' "$mock_log" || true)"
    daemon_count="$(grep -c '^daemon_start$' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    # Initial warm probe used ping (1), daemon started (1), cold ping probe succeeded (1), exactly 1 mutating toggle after readiness
    if [[ "$toggle_count" -eq 1 && "$ping_count" -ge 2 && "$daemon_count" -eq 1 ]]; then
        pass "41. cold startup uses non-mutating ping probe and invokes toggle exactly once after readiness"
    else
        fail "41. cold startup toggle/ping invariant violated: toggles=$toggle_count pings=$ping_count daemons=$daemon_count"
    fi
)

# Test 42: Warm start invokes mutating toggle exactly once without starting daemon
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "--path" ]]; then
    echo "ipc_path:$3" >> "$MOCK_LOG"
    if [[ "$4" == "call" && ( "$5" == "keybindings" || "$5" == "hotkeys" ) ]]; then
        if [[ "$6" == "ping" ]]; then
            echo "ping" >> "$MOCK_LOG"
            echo "true"
            exit 0
        elif [[ "$6" == "toggle" ]]; then
            echo "toggle" >> "$MOCK_LOG"
            exit 0
        fi
    fi
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
    toggle_count="$(grep -c '^toggle$' "$mock_log" || true)"
    daemon_count="$(grep -c '^daemon_start$' "$mock_log" || true)"
    ping_count="$(grep -c '^ping$' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$toggle_count" -eq 1 && "$daemon_count" -eq 0 && "$ping_count" -eq 1 ]]; then
        pass "42. warm startup invokes toggle exactly once without starting daemon"
    else
        fail "42. warm startup invariant violated: toggles=$toggle_count daemons=$daemon_count pings=$ping_count"
    fi
)

# Test 43: Startup timeout is bounded around 2s (~40 attempts * 50ms)
timeout_spec="$(grep -E 'for _ in \{1\.\.40\}' "$ROOT/bin/lib/aurelia-keybindings/toggle.sh" 2>/dev/null || true)"
sleep_spec="$(grep -E 'sleep 0\.05' "$ROOT/bin/lib/aurelia-keybindings/toggle.sh" 2>/dev/null || true)"
if [[ -n "$timeout_spec" && -n "$sleep_spec" ]]; then
    pass "43. startup timeout is bounded around 2s (40 * 50ms) without arbitrary long sleeps"
else
    fail "43. startup timeout not bounded around 2s"
fi
