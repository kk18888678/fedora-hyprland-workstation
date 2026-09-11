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

if is_component_migrated "noctalia" && is_component_migrated "desktop.environment.noctalia"; then
    pass "30b. Noctalia package alias resolves to its qualified reconciler component"
else
    fail "30b. Noctalia package alias created a second mutation owner"
fi

# 30c. The migrated desktop package group owns the greeter RPM; the activation
# stage must validate presence rather than invoke a second DNF mutation.
greeter_ownership_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
SCRIPT_DIR="$ROOT"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/status.sh"
source "$ROOT/modules/desktop.sh"

greeter_dnf_called=0
package_installed() {
    [[ "${1:-}" == "noctalia-greeter" ]]
}
install_dnf_packages() {
    greeter_dnf_called=1
    return 0
}
command_exists() {
    [[ "${1:-}" == "noctalia-greeter-session" ]]
}
INSTALL_GREETER=true
greeter_validation_status=0
install_noctalia_greeter >/dev/null 2>&1 || greeter_validation_status=$?
printf 'status=%s dnf=%s\n' "$greeter_validation_status" "$greeter_dnf_called"
EOS
)"
if grep -q 'status=0 dnf=0' <<< "$greeter_ownership_output"; then
    pass "30c. migrated desktop group supplies noctalia-greeter without duplicate DNF mutation"
else
    fail "30c. migrated desktop group triggered duplicate greeter installation: $greeter_ownership_output"
fi
