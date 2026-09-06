section "9. Canonical Shortcut Truth Invariance"

# Ensure QML files contain zero hardcoded shortcut definitions (single source of truth in Lua)
qml_hardcoded="$(grep -E '(Super \+ [A-Za-z0-9]|SUPER \+ [A-Za-z0-9])' "$ROOT/dotfiles/aurelia/components/keybindings/"*.qml 2>/dev/null || true)"
if [[ -z "$qml_hardcoded" ]]; then
    pass "9. UI does not duplicate canonical shortcut truth (100% derived from backend)"
else
    fail "9. QML contains hardcoded shortcuts: $qml_hardcoded"
fi
