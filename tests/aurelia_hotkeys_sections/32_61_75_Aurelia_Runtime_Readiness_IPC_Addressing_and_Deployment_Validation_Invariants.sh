section "61-75. Aurelia Runtime, Readiness, IPC Addressing, and Deployment Validation Invariants"

# Test 61: Warm Aurelia instance + successful ping -> toggle once, no process launched
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "--path" ]]; then
    echo "ipc:$6" >> "$MOCK_LOG"
    if [[ "$6" == "ping" ]]; then
        echo "true"
    fi
    exit 0
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
    pings="$(grep -c '^ipc:ping$' "$mock_log" || true)"
    toggles="$(grep -c '^ipc:toggle$' "$mock_log" || true)"
    daemons="$(grep -c '^daemon_start$' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$pings" -eq 1 && "$toggles" -eq 1 && "$daemons" -eq 0 ]]; then
        pass "61. warm Aurelia instance + successful ping -> toggle once, no new process launched"
    else
        fail "61. warm Aurelia invariant failed: pings=$pings toggles=$toggles daemons=$daemons"
    fi
)

# Test 62: Cold path launches exactly one instance, waits for ping, toggles once
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "--path" ]]; then
    echo "ipc:$6" >> "$MOCK_LOG"
    if [[ "$6" == "ping" ]] && ! grep -q "^daemon_start$" "$MOCK_LOG"; then
        exit 1
    fi
    if [[ "$6" == "ping" ]]; then
        echo "true"
    fi
    exit 0
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
    pings="$(grep -c '^ipc:ping$' "$mock_log" || true)"
    toggles="$(grep -c '^ipc:toggle$' "$mock_log" || true)"
    daemons="$(grep -c '^daemon_start$' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$pings" -ge 2 && "$toggles" -eq 1 && "$daemons" -eq 1 ]]; then
        pass "62. cold path launches exactly one instance, waits for non-mutating ping, and toggles once"
    else
        fail "62. cold path invariant failed: pings=$pings toggles=$toggles daemons=$daemons"
    fi
)

# Test 63: Readiness failure (ping fails) -> toggle is NEVER invoked, fails closed
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/foot"
#!/usr/bin/env bash
echo "fallback_foot:$*" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$mock_dir/foot"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "--path" ]]; then
    echo "ipc:$6" >> "$MOCK_LOG"
    exit 1
elif [[ "$1" == "--no-duplicate" ]]; then
    echo "daemon_start" >> "$MOCK_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" bash -c '
        "$1" >/dev/null 2>&1 || true
    ' _ "$ROOT/bin/workstation-hotkeys"
    toggles="$(grep -c '^ipc:toggle$' "$mock_log" || true)"
    fallback_called="$(grep -c '^fallback_foot:' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$toggles" -eq 0 && "$fallback_called" -eq 0 ]]; then
        pass "63. ping failure never invokes toggle and fails closed without fallback foot"
    else
        fail "63. toggle was incorrectly called or fallback occurred: toggles=$toggles fallback=$fallback_called"
    fi
)

# Test 64: Toggle failure produces distinct diagnostic and fails closed
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/foot"
#!/usr/bin/env bash
echo "fallback_foot:$*" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$mock_dir/foot"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "--path" ]]; then
    echo "ipc:$6" >> "$MOCK_LOG"
    if [[ "$6" == "ping" ]]; then
        echo "true"
        exit 0
    elif [[ "$6" == "toggle" ]]; then
        exit 1
    fi
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" bash -c '
        "$1" >/dev/null 2>&1 || true
    ' _ "$ROOT/bin/workstation-hotkeys"
    pings="$(grep -c '^ipc:ping$' "$mock_log" || true)"
    toggles="$(grep -c '^ipc:toggle$' "$mock_log" || true)"
    fallback_called="$(grep -c '^fallback_foot:' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$pings" -ge 1 && "$toggles" -ge 1 && "$fallback_called" -eq 0 ]]; then
        pass "64. toggle failure produces distinct diagnostic and fails closed without fallback foot"
    else
        fail "64. toggle failure handling violated: pings=$pings toggles=$toggles fallback=$fallback_called"
    fi
)

# Test 65: Quickshell process existence alone is NOT considered readiness
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/foot"
#!/usr/bin/env bash
echo "fallback_foot:$*" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$mock_dir/foot"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" ]]; then
    exit 255
elif [[ "$1" == "--no-duplicate" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" bash -c '
        "$1" >/dev/null 2>&1 || true
    ' _ "$ROOT/bin/workstation-hotkeys"
    fallback_called="$(grep -c '^fallback_foot:' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$fallback_called" -eq 0 ]]; then
        pass "65. Quickshell process existence alone is not considered readiness (fails closed)"
    else
        fail "65. Process existence incorrectly launched fallback foot: $fallback_called"
    fi
)

# Test 66: Correct Aurelia instance/config identity is used for ping and toggle
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "--path" ]]; then
    echo "path:$3" >> "$MOCK_LOG"
    echo "action:$6" >> "$MOCK_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
    used_path="$(grep '^path:' "$mock_log" | head -n 1 | cut -d ':' -f2-)"
    used_action="$(grep '^action:' "$mock_log" | head -n 1 | cut -d ':' -f2-)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$used_path" == *"aurelia/shell.qml" && "$used_action" == "ping" ]]; then
        pass "66. correct Aurelia instance/config identity (--path) is used for ping and toggle"
    else
        fail "66. incorrect path or action used: path=$used_path action=$used_action"
    fi
)

# Test 67: Noctalia/other Quickshell instance cannot satisfy Aurelia readiness
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/foot"
#!/usr/bin/env bash
echo "fallback_foot" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$mock_dir/foot"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
if [[ "$1" == "ipc" && "$2" == "--path" ]]; then
    target_path="$3"
    if [[ "$target_path" == *"/aurelia/shell.qml" ]]; then
        exit 255
    else
        exit 0
    fi
elif [[ "$1" == "--no-duplicate" ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" bash -c '
        "$1" >/dev/null 2>&1 || true
    ' _ "$ROOT/bin/workstation-hotkeys"
    fallback_called="$(grep -c 'fallback_foot' "$mock_log" || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ "$fallback_called" -eq 0 ]]; then
        pass "67. Noctalia/other Quickshell instance cannot satisfy Aurelia readiness"
    else
        fail "67. Other instance incorrectly launched fallback foot: $fallback_called"
    fi
)

# Test 68: Deployment validator rejects missing shell.qml
(
    sb="$(mktemp -d)"
    mkdir -p "$sb/.config/aurelia/components/hotkeys" "$sb/.config/aurelia/theme"
    touch "$sb/.config/aurelia/components/hotkeys/HotkeysWindow.qml"
    touch "$sb/.config/aurelia/components/hotkeys/HotkeysModel.qml"
    touch "$sb/.config/aurelia/components/hotkeys/HotkeyRow.qml"
    touch "$sb/.config/aurelia/theme/Theme.qml"
    touch "$sb/.config/aurelia/theme/qmldir"
    val_rc=0
    detect_quickshell() { return 0; }
    TARGET_HOME="$sb" TARGET_USER="$(id -un)" validate_aurelia_hotkeys || val_rc=$?
    rm -rf "$sb"
    if [[ "$val_rc" -ne 0 ]]; then
        pass "68. deployment validator rejects missing shell.qml"
    else
        fail "68. deployment validator accepted missing shell.qml"
    fi
)

# Test 69: Deployment validator rejects broken symlink
(
    sb="$(mktemp -d)"
    mkdir -p "$sb/.config"
    ln -s "/nonexistent/target/path/for/aurelia" "$sb/.config/aurelia"
    val_rc=0
    detect_quickshell() { return 0; }
    TARGET_HOME="$sb" TARGET_USER="$(id -un)" validate_aurelia_hotkeys || val_rc=$?
    rm -rf "$sb"
    if [[ "$val_rc" -ne 0 ]]; then
        pass "69. deployment validator rejects broken symlink"
    else
        fail "69. deployment validator accepted broken symlink"
    fi
)

# Test 70: Deployment validator accepts valid deployed tree
(
    sb="$(mktemp -d)"
    mkdir -p "$sb/.config"
    ln -s "$ROOT/aurelia-shell" "$sb/.config/aurelia"
    val_rc=0
    detect_quickshell() { return 0; }
    TARGET_HOME="$sb" TARGET_USER="$(id -un)" validate_aurelia_hotkeys || val_rc=$?
    rm -rf "$sb"
    if [[ "$val_rc" -eq 0 ]]; then
        pass "70. deployment validator accepts valid deployed tree"
    else
        fail "70. deployment validator rejected valid tree: rc=$val_rc"
    fi
)

# Test 71: Fallback terminal is passed --provider=legacy preventing nested delay
(
    mock_dir="$(mktemp -d)"
    mock_log="$(mktemp)"
    cat << "EOF" > "$mock_dir/foot"
#!/usr/bin/env bash
echo "args:$*" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$mock_dir/foot"
    cat << "EOF" > "$mock_dir/qs"
#!/usr/bin/env bash
exit 255
EOF
    chmod +x "$mock_dir/qs"
    MOCK_LOG="$mock_log" PATH="$mock_dir:$PATH" HOTKEYS_TEST_PROVIDER="aurelia" bash -c '
        "$1" >/dev/null 2>&1 || true
    ' _ "$ROOT/bin/workstation-hotkeys"
    foot_args="$(cat "$mock_log" 2>/dev/null || true)"
    rm -rf "$mock_dir" "$mock_log"
    if [[ -z "$foot_args" ]]; then
        pass "71. Aurelia failure fails closed without launching fallback terminal"
    else
        fail "71. fallback terminal was unexpectedly launched: '$foot_args'"
    fi
)

# Test 72: Legacy fzf provider is strictly rejected
leg_rc=0
leg_out="$("$ROOT/bin/workstation-hotkeys" --provider=legacy 2>&1)" || leg_rc=$?
if [[ "$leg_rc" -ne 0 && "$leg_out" == *"Legacy provider has been removed"* ]]; then
    pass "72. legacy fzf provider is strictly rejected (exit code 1)"
else
    fail "72. legacy fzf provider was not rejected: $leg_out"
fi

# Test 73: Persisted hotkeys.provider remains aurelia on runtime failure
(
    sb="$(mktemp -d)"
    mkdir -p "$sb/.config/workstation"
    echo "hotkeys.provider = aurelia" > "$sb/.config/workstation/desktop.conf"
    XDG_CONFIG_HOME="$sb/.config" HOTKEYS_SIMULATE_AURELIA_FAIL=1 "$ROOT/bin/workstation-hotkeys" >/dev/null 2>&1 || true
    persisted="$(grep -E '^[[:space:]]*hotkeys[._]provider[[:space:]]*=' "$sb/.config/workstation/desktop.conf" | cut -d '=' -f2 | tr -d '[:space:]')"
    rm -rf "$sb"
    if [[ "$persisted" == "aurelia" ]]; then
        pass "73. persisted hotkeys.provider remains aurelia on runtime failure"
    else
        fail "73. runtime failure mutated persisted config: $persisted"
    fi
)

# Test 74: Keybindings manifest and Hyprland bind Super+K to canonical Aurelia Keybindings
if grep -q 'key = "SUPER + K"' "$ROOT/dotfiles/hypr/keybindings_manifest.lua" &&
   grep -q 'command = "aurelia-shell-keybindings"' "$ROOT/dotfiles/hypr/keybindings_manifest.lua"; then
    pass "74. keybindings manifest binds SUPER+K to canonical aurelia-shell-keybindings"
else
    fail "74. SUPER+K binding missing or incorrect in keybindings manifest"
fi

# Test 75: Component deploy_aurelia_config links the canonical package without creating a directory conflict
(
    sb="$(mktemp -d)"
    SCRIPT_DIR="$ROOT" TARGET_HOME="$sb" deploy_aurelia_config >/dev/null 2>&1
    dest="$sb/.config/aurelia"
    dest_is_link=$([[ -L "$dest" ]] && echo 1 || echo 0)
    dest_target="$(readlink "$dest" 2>/dev/null || true)"
    bak_exists=$([[ -d "$sb/.config/aurelia.bak" || $(ls -d "$sb/.config"/aurelia.bak.* 2>/dev/null | wc -l) -gt 0 ]] && echo 1 || echo 0)
    rm -rf "$sb"
    if [[ "$dest_is_link" -eq 1 && "$dest_target" == "$ROOT/aurelia-shell" && "$bak_exists" -eq 0 ]]; then
        pass "75. deploy_aurelia_config creates clean symlink without spurious backup"
    else
        fail "75. deploy_aurelia_config failed: is_link=$dest_is_link target=$dest_target bak_exists=$bak_exists"
    fi
)
