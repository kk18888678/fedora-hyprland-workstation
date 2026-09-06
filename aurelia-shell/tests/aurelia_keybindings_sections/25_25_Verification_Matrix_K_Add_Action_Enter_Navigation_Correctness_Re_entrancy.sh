section "25. Verification Matrix K: Add Action Enter Navigation Correctness & Re-entrancy"

# 25.1: activateSelected centralizes row activation and prevents Enter fall-through to runSelected
qml_win="$ROOT/components/keybindings/KeybindingsWindow.qml"
if grep -q "function activateSelected(): bool" "$qml_win" && \
   (grep -q 'windowController.activateSelected("keyboard")' "$qml_action_list" || grep -q 'windowController.activateSelected("keyboard")' "$qml_header") && \
   grep -q "event.accepted = true" "$qml_action_list"; then
    pass "25.1 activateSelected centralizes row activation and explicitly consumes event"
else
    fail "25.1 activateSelected missing or incomplete in KeybindingsWindow.qml"
fi

# 25.2: add_action_type + Application switches view to add_app without closing palette
act_app_check="$(python3 -c "
with open(\"$qml_win\") as f:
    c = f.read()
idx_fn = c.find(\"function activateSelected(): bool\")
if idx_fn != -1:
    body = c[idx_fn:idx_fn+4000]
    if \"keybindingsModel.switchView(\\\"add_app\\\")\" in body and \"action_type_kind === \\\"application\\\"\" in body:
        idx_app = body.find(\"keybindingsModel.switchView(\\\"add_app\\\")\")
        app_branch = body[idx_app-100:idx_app+200]
        if \"visible = false\" not in app_branch:
            print(\"APP_NAV_SAFE\")
        else:
            print(\"APP_NAV_CLOSES_PALETTE\")
    else:
        print(\"MISSING_APP_BRANCH\")
else:
    print(\"MISSING_FN\")
")"
if [[ "$act_app_check" == "APP_NAV_SAFE" ]]; then
    pass "25.2 add_action_type + Application switches view to add_app while palette remains open"
else
    fail "25.2 application navigation check failed: $act_app_check"
fi

# 25.3: add_action_type + Executable switches view to add_exec without closing palette
act_exec_check="$(python3 -c "
with open(\"$qml_win\") as f:
    c = f.read()
idx_fn = c.find(\"function activateSelected(): bool\")
if idx_fn != -1:
    body = c[idx_fn:idx_fn+4000]
    if \"keybindingsModel.switchView(\\\"add_exec\\\")\" in body and \"action_type_kind === \\\"executable\\\"\" in body:
        idx_exec = body.find(\"keybindingsModel.switchView(\\\"add_exec\\\")\")
        exec_branch = body[idx_exec-100:idx_exec+200]
        if \"visible = false\" not in exec_branch:
            print(\"EXEC_NAV_SAFE\")
        else:
            print(\"EXEC_NAV_CLOSES_PALETTE\")
    else:
        print(\"MISSING_EXEC_BRANCH\")
else:
    print(\"MISSING_FN\")
")"
if [[ "$act_exec_check" == "EXEC_NAV_SAFE" ]]; then
    pass "25.3 add_action_type + Executable switches view to add_exec while palette remains open"
else
    fail "25.3 executable navigation check failed: $act_exec_check"
fi

# 25.4: Structural event ownership with synchronous re-entrancy protection (isActivating) and zero arbitrary timing suppression
if grep -q "property bool isActivating: false" "$qml_win" && \
   grep -q "if (isActivating)" "$qml_win" && \
   grep -q "isActivating = true" "$qml_win" && \
   grep -q "isActivating = false" "$qml_win" && \
   ! grep -q "lastActivationTime" "$qml_win" && \
   ! grep -q "200" "$qml_win"; then
    pass "25.4 structural event ownership: synchronous isActivating flag guards activateSelected with zero arbitrary timing suppression"
else
    fail "25.4 structural re-entrancy protection missing or arbitrary timing suppression found in KeybindingsWindow.qml"
fi

# 25.5: Mouse type selection and keyboard Enter use the centralized activation path
qml_row="$ROOT/components/keybindings/KeybindingRow.qml"
if grep -q 'windowRoot.activateSelected("mouse")' "$qml_row" && \
   (grep -q 'windowController.activateSelected("keyboard")' "$qml_action_list" || grep -q 'windowController.activateSelected("keyboard")' "$qml_header"); then
    pass "25.5 mouse Add Action type selection and keyboard Enter share centralized activation semantics"
else
    fail "25.5 mouse Add Action selection does not delegate to activateSelected"
fi
