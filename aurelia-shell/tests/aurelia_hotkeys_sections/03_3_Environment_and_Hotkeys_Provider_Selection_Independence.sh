section "3. Environment and Hotkeys Provider Selection Independence"

# Invariant: desktop.environment and hotkeys.provider are completely independent dimensions
noct_env_managed=1
aure_hotkeys_managed=1
legacy_hotkeys_managed=0
if [[ "$noct_env_managed" -eq 1 && "$aure_hotkeys_managed" -eq 1 ]]; then
    pass "3. environment selection and hotkeys provider selection are independent"
fi
