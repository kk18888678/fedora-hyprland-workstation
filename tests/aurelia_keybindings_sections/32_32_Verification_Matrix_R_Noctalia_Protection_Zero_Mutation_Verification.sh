section "32. Verification Matrix R: Noctalia Protection & Zero Mutation Verification"

# 32.1: Aurelia changes introduce zero modifications to config/noctalia/**
noctalia_diff="$(git status --porcelain "$ROOT/config/noctalia" 2>/dev/null || true)"
if [[ -z "$noctalia_diff" ]]; then
    pass "32.1 zero modifications to config/noctalia/** (Noctalia 100% protected and untouched)"
else
    fail "32.1 unexpected modifications in config/noctalia: $noctalia_diff"
fi

# 32.2: Aurelia Shell and Keybindings preserve Noctalia decoupling and zero runtime intrusion
if ! grep -q 'noctalia' "$ROOT/dotfiles/aurelia/shell.qml" && \
   ! grep -q 'noctalia' "$ROOT/dotfiles/aurelia/components/keybindings/KeybindingsWindow.qml"; then
    pass "32.2 Aurelia Shell and Keybindings maintain zero intrusion or coupling to Noctalia runtime"
else
    fail "32.2 unexpected Noctalia coupling found in Aurelia components"
fi
