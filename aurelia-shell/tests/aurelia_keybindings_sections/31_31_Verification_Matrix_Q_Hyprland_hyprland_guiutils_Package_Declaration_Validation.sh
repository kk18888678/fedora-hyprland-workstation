section "31. Verification Matrix Q: Hyprland hyprland-guiutils Package Declaration & Validation"

# 31.1: hyprland-guiutils is declared in packages/desktop.txt
pkg_file="$ROOT/packages/desktop.txt"
if grep -q '^hyprland-guiutils$' "$pkg_file"; then
    pass "31.1 hyprland-guiutils is declared in packages/desktop.txt"
else
    fail "31.1 hyprland-guiutils missing in packages/desktop.txt"
fi

# 31.2: validation.sh validates hyprland-guiutils as a deferred capability without blocking login
val_file="$ROOT/modules/validation.sh"
val_def_test="$(python3 -c "
with open(\"$val_file\") as f:
    c = f.read()
idx = c.find(\"hyprland-guiutils\")
if idx != -1 and \"record_deferred\" in c[idx-100:idx+100]:
    print(\"DEFERRED_CHECK_OK\")
else:
    print(\"FAIL\")
")"
if [[ "$val_def_test" == "DEFERRED_CHECK_OK" ]]; then
    pass "31.2 validation.sh validates hyprland-guiutils as a deferred capability without blocking login"
else
    fail "31.2 hyprland-guiutils capability validation missing or blocks login in validation.sh"
fi

# 31.3: hyprland-guiutils absence does not record activation-critical failure
val_test="$(python3 -c "
with open(\"$val_file\") as f:
    c = f.read()
idx = c.find(\"hyprland-guiutils\")
if idx != -1:
    surrounding = c[idx-200:idx+400]
    if \"record_activation_failure\" not in surrounding:
        print(\"NON_BLOCKING_OK\")
    else:
        print(\"INCORRECTLY_BLOCKS_ACTIVATION\")
else:
    print(\"MISSING_CHECK\")
")"
if [[ "$val_test" == "NON_BLOCKING_OK" ]]; then
    pass "31.3 hyprland-guiutils absence strictly preserves graphical activation path"
else
    fail "31.3 hyprland-guiutils validation records activation failure: $val_test"
fi
