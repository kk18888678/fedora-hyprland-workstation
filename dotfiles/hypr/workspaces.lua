-- Declarative persistent workspace rules for Fedora Hyprland Workstation.
-- Baseline workspaces {1, 2, 3} are permanently pinned.
-- Workspaces 4+ are dynamic (created on demand when occupied, destroyed when empty).

local M = {}

M.persistent_workspaces = { 1, 2, 3 }

if hl and type(hl.workspace_rule) == "function" then
    for _, ws in ipairs(M.persistent_workspaces) do
        hl.workspace_rule({
            workspace = tostring(ws),
            persistent = true,
        })
    end
end

return M
