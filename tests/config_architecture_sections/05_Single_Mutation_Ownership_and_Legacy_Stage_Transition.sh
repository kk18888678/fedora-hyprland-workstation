section "Single Mutation Ownership and Legacy Stage Transition"

# 27. Migrated REMOVE cannot be undone by legacy install stage
test_rem_called=0
install_dnf_packages() {
    for pkg in "$@"; do
        if [[ "$pkg" == "chromium" ]]; then test_rem_called=1; fi
    done
    return 0
}
BROWSER_CHROMIUM=true
install_chromium
if [[ "$test_rem_called" -eq 0 ]]; then
    pass "27. migrated component (chromium) is skipped by legacy stage; cannot be reinstalled"
else
    fail "27. legacy stage reinstalled migrated component"
fi

# 28. Migrated unmanaged remains untouched by legacy stage
test_unm_called=0
install_dnf_packages() {
    for pkg in "$@"; do
        if [[ "$pkg" == "firefox" ]]; then test_unm_called=1; fi
    done
    return 0
}
BROWSER_FIREFOX=true
install_firefox
if [[ "$test_unm_called" -eq 0 ]]; then
    pass "28. migrated unmanaged component (firefox) is skipped by legacy stage"
else
    fail "28. legacy stage touched unmanaged migrated component"
fi

# 29. Migrated INSTALL executes once through reconciler adapter
test_reconciler_installs=0
install_dnf_packages() {
    for pkg in "$@"; do
        if [[ "$pkg" == "chromium" ]]; then test_reconciler_installs=$(( test_reconciler_installs + 1 )); fi
    done
    return 0
}
rpm() { return 0; }
# Reconciler installs it via adapter
perform_install_chromium
# Legacy stage runs
BROWSER_CHROMIUM=true
install_chromium
if [[ "$test_reconciler_installs" -eq 1 ]]; then
    pass "29. migrated INSTALL executes exactly once through reconciler; legacy stage does not duplicate"
else
    fail "29. migrated component was installed $test_reconciler_installs times"
fi

# 30. Non-migrated legacy functionality remains owned
# brave-origin is not registered in the Component Registry
if ! is_component_migrated "brave-origin"; then
    pass "30. non-migrated component (brave-origin) remains owned by legacy stage"
else
    fail "30. non-migrated component was mistakenly classified as migrated"
fi
