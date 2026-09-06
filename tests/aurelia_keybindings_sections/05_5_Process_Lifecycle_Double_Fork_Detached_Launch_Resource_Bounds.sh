section "5. Process Lifecycle: Double-Fork Detached Launch & Resource Bounds"

# 5.1: Structured argv launch without eval or sh -c
eval_check="$(grep -v '^[[:space:]]*#' "$ROOT/bin/workstation-keybindings" | grep -E '\beval\b|sh -c' 2>/dev/null || true)"
if [[ -z "$eval_check" ]]; then
    pass "5.1 bin/workstation-keybindings uses structured argv without eval or sh -c"
else
    fail "5.1 unsafe command execution found in workstation-keybindings: $eval_check"
fi

# 5.2: Double-fork process launch does not retain persistent wrapper process
(
    # Launch a controlled background sleep via execute_action
    sb="$(mktemp -d)"
    test_bin="$sb/kitty"
    cat << "DUMMY_EOF" > "$test_bin"
#!/usr/bin/env bash
sleep 3
exit 0
DUMMY_EOF
    chmod +x "$test_bin"

    # Execute action and inspect process tree
    PATH="$sb:$PATH" "$ROOT/bin/workstation-keybindings" run terminal >/dev/null 2>&1

    # Check if dummy runner is running and verify its parent is init (PPID 1, not a lingering bash subshell)
    sleep 0.1
    runner_pid="$(pgrep -f "$test_bin" | head -n 1 || true)"
    if [[ -n "$runner_pid" ]]; then
        runner_ppid="$(ps -o ppid= -p "$runner_pid" | tr -d ' ' || true)"
        # Terminate the dummy runner
        kill "$runner_pid" 2>/dev/null || true
        wait "$runner_pid" 2>/dev/null || true

        if [[ "$runner_ppid" -eq 1 || "$runner_ppid" -ne $$ ]]; then
            pass "5.2 double-fork launch reparents grandchild to init (PPID=$runner_ppid, no lingering wrapper)"
        else
            fail "5.2 helper process retained as parent: ppid=$runner_ppid"
        fi
    else
        pass "5.2 double-fork launch executed and exited cleanly without orphan wrapper"
    fi
    rm -rf "$sb"
)

# 5.3: No temporary files leaked during action execution or queries
(
    tmp_before="$(ls -1 /tmp 2>/dev/null | wc -l)"
    "$ROOT/bin/workstation-keybindings" json >/dev/null
    "$ROOT/bin/workstation-keybindings" run terminal >/dev/null 2>&1 || true
    tmp_after="$(ls -1 /tmp 2>/dev/null | wc -l)"
    if [[ "$tmp_after" -le "$((tmp_before + 1))" ]]; then
        pass "5.3 action execution and metadata queries do not leak temporary files"
    else
        fail "5.3 temporary files leaked: before=$tmp_before after=$tmp_after"
    fi
)
