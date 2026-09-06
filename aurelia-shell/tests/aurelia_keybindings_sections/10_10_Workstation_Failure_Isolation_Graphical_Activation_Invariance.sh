section "10. Workstation Failure Isolation & Graphical Activation Invariance"

# 10.1: Keybindings failure does not block graphical login activation
validation_sh="$ROOT/modules/validation.sh"
if grep -q 'validate_keybindings' "$validation_sh" || grep -q 'validate_hotkeys' "$validation_sh"; then
    if ! grep -E 'record_activation_failure.*keybindings' "$validation_sh" >/dev/null; then
        pass "10.1 Keybindings failure does not record activation-critical failure (greetd unaffected)"
    else
        fail "10.1 Keybindings failure incorrectly blocks graphical login activation"
    fi
else
    pass "10.1 Keybindings is decoupled from login-critical validation path"
fi
