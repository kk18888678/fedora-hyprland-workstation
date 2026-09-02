-- Workspace state model and persistent workspace configuration.
-- Baseline workspaces {1, 2, 3} are permanently pinned.
-- Workspaces 4+ are dynamic (visible only when active or occupied).

local M = {}

M.pinned_workspaces = { 1, 2, 3 }

-- Pure helper to compute the ordered list of visible workspaces given active and occupied IDs
function M.compute_visible_workspaces(active_id, occupied_ids)
    local seen = {}
    local result = {}

    -- 1. Always include pinned baseline workspaces {1, 2, 3}
    for _, id in ipairs(M.pinned_workspaces) do
        local nid = tonumber(id)
        if nid and not seen[nid] then
            seen[nid] = true
            table.insert(result, nid)
        end
    end

    -- 2. Include currently active workspace
    local act = tonumber(active_id)
    if act and not seen[act] then
        seen[act] = true
        table.insert(result, act)
    end

    -- 3. Include occupied / window-containing workspaces
    for _, id in ipairs(occupied_ids or {}) do
        local oid = tonumber(id)
        if oid and not seen[oid] then
            seen[oid] = true
            table.insert(result, oid)
        end
    end

    -- 4. Sort numerically ascending
    table.sort(result)

    return result
end

-- Format workspace indicator string for presentation or tests (e.g. "[1]  2   3" or "1  [2]  3  5")
function M.format_indicator(active_id, occupied_ids)
    local visible = M.compute_visible_workspaces(active_id, occupied_ids)
    local act = tonumber(active_id) or 1
    local parts = {}

    for _, id in ipairs(visible) do
        if id == act then
            table.insert(parts, string.format("[%d]", id))
        else
            table.insert(parts, string.format(" %d ", id))
        end
    end

    return table.concat(parts, " ")
end

-- Declaratively apply persistent workspace rules in Hyprland
function M.apply_hyprland_rules()
    if not hl or type(hl.workspace_rule) ~= "function" then
        return
    end

    for _, ws in ipairs(M.pinned_workspaces) do
        hl.workspace_rule({
            workspace = tostring(ws),
            persistent = true,
        })
    end
end

M.apply_hyprland_rules()

return M
