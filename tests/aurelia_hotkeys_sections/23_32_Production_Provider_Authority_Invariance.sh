section "32. Production Provider Authority Invariance"

# Test 32: Arbitrary environment variables must NOT override persisted configuration
sb_auth_test="$(mktemp -d)"
mkdir -p "$sb_auth_test/.config/workstation"
echo "keybindings.provider = custom_mock" > "$sb_auth_test/.config/workstation/desktop.conf"
auth_prov="$(
    XDG_CONFIG_HOME="$sb_auth_test/.config" \
    KEYBINDINGS_PROVIDER="aurelia" \
    WORKSTATION_KEYBINDINGS_PROVIDER="aurelia" \
    KEYBINDINGS_TEST_ACTION="provider" \
    "$ROOT/bin/workstation-keybindings"
)"
rm -rf "$sb_auth_test"
if [[ "$auth_prov" == "custom_mock" ]]; then
    pass "32. production provider authority is persisted config, not arbitrary env override"
else
    fail "32. arbitrary env variable bypassed persisted provider authority: $auth_prov"
fi
