section "Workspace Persistence & Noctalia Workspaces Config"

workspaces_lua="$ROOT/dotfiles/hypr/workspaces.lua"
if [[ -f "$workspaces_lua" ]]; then
    pass "dotfiles/hypr/workspaces.lua exists"
else
    fail "dotfiles/hypr/workspaces.lua is missing"
fi

if grep -q 'hl.workspace_rule' "$workspaces_lua" &&
   grep -q 'persistent = true' "$workspaces_lua"; then
    pass "workspaces.lua declaratively registers persistent = true via hl.workspace_rule"
else
    fail "workspaces.lua missing declarative persistent workspace rules"
fi

if grep -q 'require("workspaces")' "$ROOT/dotfiles/hypr/hyprland.lua"; then
    pass "hyprland.lua loads workspaces module at session initialization"
else
    fail "hyprland.lua does not load workspaces module"
fi

# Ensure monitor names are not hardcoded in workspace definitions
if grep -E 'monitor[[:space:]]*=' "$workspaces_lua"; then
    fail "workspaces.lua hardcodes monitor-specific workspace bindings"
else
    pass "persistent workspaces avoid hardcoding monitor names"
fi

noctalia_config="$ROOT/config/noctalia/config.toml"
if [[ -f "$noctalia_config" ]]; then
    pass "config/noctalia/config.toml exists"
else
    fail "config/noctalia/config.toml is missing"
fi

if grep -q '\[widget\.workspaces\]' "$noctalia_config" &&
   grep -q 'hide_when_empty = false' "$noctalia_config" &&
   grep -q 'show_labels = true' "$noctalia_config"; then
    pass "noctalia config.toml configures persistent workspaces widget (hide_when_empty = false, show_labels = true)"
else
    fail "noctalia config.toml missing persistent workspaces widget configuration"
fi

if command -v noctalia >/dev/null 2>&1; then
    tmp_validate_home="$(mktemp -d)"
    if HOME="$tmp_validate_home" noctalia config validate "$noctalia_config" >/dev/null 2>&1; then
        pass "noctalia config validate confirms config/noctalia/config.toml is strictly valid"
    else
        fail "noctalia config validate rejected config/noctalia/config.toml"
    fi
    rm -rf "$tmp_validate_home"
fi

if ! grep -q '\[shell\.launcher\]' "$noctalia_config"; then
    pass "noctalia config.toml excludes unneeded shell.launcher overrides"
else
    fail "noctalia config.toml contains unexpected shell.launcher overrides"
fi
