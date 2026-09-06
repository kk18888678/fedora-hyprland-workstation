section "Workspaces Discoverability"

workspaces_lua="$ROOT/dotfiles/hypr/workspaces.lua"
if [[ -f "$workspaces_lua" ]]; then
    pass "dotfiles/hypr/workspaces.lua exists"
else
    fail "dotfiles/hypr/workspaces.lua is missing"
fi

if grep -q 'hl.workspace_rule' "$workspaces_lua" &&
   grep -q 'persistent = true' "$workspaces_lua"; then
    pass "workspaces.lua registers persistent workspaces declaratively via hl.workspace_rule"
else
    fail "workspaces.lua missing declarative persistent workspace rules"
fi

# Ensure monitor names are not hardcoded in workspace definitions
if grep -E 'monitor[[:space:]]*=' "$workspaces_lua"; then
    fail "workspaces.lua hardcodes monitor-specific workspace bindings"
else
    pass "persistent workspaces avoid hardcoding monitor names"
fi
