section "8. Aurelia Design System Foundation & Theme Independence"

theme_qml="$ROOT/dotfiles/aurelia/theme/Theme.qml"

# 8.1: Theme works independently without Noctalia files
(
    if ! grep -q 'noctalia.conf' "$theme_qml"; then
        pass "8.1 Theme.qml does not depend on Noctalia-generated configuration"
    else
        fail "8.1 Theme.qml contains coupling to noctalia.conf"
    fi
)

# 8.2: Rosé Pine Moon tokens defined natively in Aurelia
if grep -q '_base: "#232136"' "$theme_qml" &&
   grep -q '_surface: "#2a273f"' "$theme_qml" &&
   grep -q '_foam: "#9ccfd8"' "$theme_qml" &&
   grep -q '_gold: "#f6c177"' "$theme_qml"; then
    pass "8.2 canonical Rosé Pine Moon tokens defined natively inside Aurelia design system"
else
    fail "8.2 native Rosé Pine Moon tokens missing in Theme.qml"
fi

# 8.3: Semantic design tokens exist for Colors, Typography, Geometry, Motion
if grep -q 'readonly property color bgBase:' "$theme_qml" &&
   grep -q 'readonly property string fontFamily:' "$theme_qml" &&
   grep -q 'readonly property int spacingMd:' "$theme_qml" &&
   grep -q 'readonly property int durationFast:' "$theme_qml"; then
    pass "8.3 semantic design tokens established for Colors, Typography, Geometry, and Motion"
else
    fail "8.3 semantic tokens incomplete in Theme.qml"
fi

# 8.4: Shared design decisions use tokens instead of unexplained literals
if grep -q 'Theme.bgBase' "$qml_window" &&
   grep -q 'KeybindingsConfig.palettePreferredWidth' "$qml_window" &&
   grep -q 'Theme.spacingMd' "$qml_window"; then
    pass "8.4 KeybindingsWindow consumes semantic design system tokens"
else
    fail "8.4 KeybindingsWindow missing design token usage"
fi

# 8.5: Central configuration file theme.conf defines geometry, dimensions, colors, typography
theme_conf="$ROOT/dotfiles/aurelia/theme.conf"
if [[ -f "$theme_conf" ]] &&
   grep -q '^paletteWidth = ' "$theme_conf" &&
   grep -q '^colShortcutWidth = ' "$theme_conf" &&
   grep -q '^background = ' "$theme_conf" &&
   grep -q '^fontFamily = ' "$theme_conf"; then
    pass "8.5 central theme.conf defines variables for geometry, dimensions, colors, and typography"
else
    fail "8.5 central theme.conf missing or incomplete"
fi

# 8.6: Zero hardcoded hex colors in KeybindingsWindow/KeybindingRow
hex_leaks="$(grep -E '#[0-9a-fA-F]{3,8}' "$ROOT/dotfiles/aurelia/components/keybindings/"*.qml || true)"
if [[ -z "$hex_leaks" ]]; then
    pass "8.6 zero hardcoded hex colors in Keybindings QML components (100% theme token driven)"
else
    fail "8.6 hardcoded hex colors detected in QML components: $hex_leaks"
fi

# 8.7: Dynamic token parsing in Theme.qml handles typed geometry, dimensions, and color aliases
if grep -q 'function _getInt(' "$theme_qml" &&
   grep -q 'function _getString(' "$theme_qml" &&
   grep -q 'function _getColor(' "$theme_qml" &&
   grep -q '_getInt("colShortcutWidth"' "$theme_qml" &&
   grep -q '_getInt("paletteWidth"' "$theme_qml"; then
    pass "8.7 Theme.qml dynamically parses typed variables from theme.conf with safe fallbacks"
else
    fail "8.7 dynamic typed variable parsing missing in Theme.qml"
fi
