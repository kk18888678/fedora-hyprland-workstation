-- Module: effective_bindings
-- Single source of truth for resolving effective keybindings by combining
-- the declarative manifest (defaults) with user-owned overrides.
-- Consumed by both Hyprland runtime session (keybind.lua) and workstation-hotkeys.

local M = {}

-- Determine user override file location
function M.get_overrides_path()
    local env_path = os.getenv("HOTKEYS_OVERRIDES")
    if env_path and env_path ~= "" then
        return env_path
    end
    local config_home = os.getenv("XDG_CONFIG_HOME")
    if not config_home or config_home == "" then
        local home = os.getenv("HOME") or ""
        config_home = home .. "/.config"
    end
    return config_home .. "/hypr/keybindings_overrides.json"
end

-- Pure Lua lightweight JSON decoder for shallow key-value maps
function M.json_decode(str)
    if not str or str:match("^%s*$") then return {} end
    local result = {}
    local content = str:match("^%s*{%s*(.-)%s*}%s*$")
    if not content then return nil, "Invalid JSON: missing enclosing braces" end
    if content:match("^%s*$") then return result end

    local pos = 1
    while pos <= #content do
        local _, next_start = content:find("^[%s,]*", pos)
        if next_start and next_start >= pos then pos = next_start + 1 end
        if pos > #content then break end

        local key_start, key_end, key = content:find("\"([^\"\\]-)\"", pos)
        if not key_start or key_start ~= pos then break end
        pos = key_end + 1

        local col_start, col_end = content:find("^%s*:%s*", pos)
        if not col_start then break end
        pos = col_end + 1

        local val_str_start, val_str_end, val_str = content:find("\"([^\"\\]-)\"", pos)
        if val_str_start and val_str_start == pos then
            result[key] = val_str
            pos = val_str_end + 1
        elseif content:sub(pos, pos + 4) == "false" then
            result[key] = false
            pos = pos + 5
        elseif content:sub(pos, pos + 3) == "true" then
            result[key] = true
            pos = pos + 4
        elseif content:sub(pos, pos + 3) == "null" then
            result[key] = false
            pos = pos + 4
        else
            break
        end
    end
    return result
end

-- Pure Lua lightweight JSON encoder
function M.json_encode(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do
        local v = tbl[k]
        if type(v) == "string" then
            table.insert(lines, string.format("  %q: %q", k, v))
        elseif v == false or v == nil then
            table.insert(lines, string.format("  %q: false", k))
        elseif v == true then
            table.insert(lines, string.format("  %q: true", k))
        end
    end
    return "{\n" .. table.concat(lines, ",\n") .. "\n}\n"
end

-- Load overrides from disk safely
function M.load_overrides(path)
    path = path or M.get_overrides_path()
    local f = io.open(path, "r")
    if not f then
        return {}
    end
    local content = f:read("*a")
    f:close()
    local parsed, err = M.json_decode(content)
    if not parsed then
        return {}
    end
    return parsed
end

-- Save overrides atomically
function M.save_overrides(overrides, path)
    path = path or M.get_overrides_path()
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
        os.execute(string.format("mkdir -p %q", dir))
    end
    local tmp_path = string.format("%s.tmp.%d", path, os.time())
    local f, err = io.open(tmp_path, "w")
    if not f then
        return false, "Failed to open temporary file for writing: " .. tostring(err)
    end
    f:write(M.json_encode(overrides))
    f:flush()
    f:close()

    local ok, ren_err = os.rename(tmp_path, path)
    if not ok then
        -- Fallback to shell mv if os.rename fails across filesystems
        local mv_ret = os.execute(string.format("mv -f %q %q", tmp_path, path))
        if mv_ret ~= 0 and mv_ret ~= true then
            os.remove(tmp_path)
            return false, "Failed to atomically rename overrides file: " .. tostring(ren_err)
        end
    end
    return true
end

-- Normalize key string for consistent display and matching
function M.normalize_key(k)
    if not k or type(k) ~= "string" then return nil end
    k = k:gsub("^%s+", ""):gsub("%s+$", "")
    if k == "" then return nil end

    local parts = {}
    for part in k:gmatch("[^%+]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then
            local upper = part:upper()
            if upper == "SUPER" or upper == "MOD4" or upper == "WIN" then
                table.insert(parts, "SUPER")
            elseif upper == "SHIFT" then
                table.insert(parts, "SHIFT")
            elseif upper == "CTRL" or upper == "CONTROL" then
                table.insert(parts, "CTRL")
            elseif upper == "ALT" or upper == "MOD1" then
                table.insert(parts, "ALT")
            else
                table.insert(parts, part)
            end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " + ")
end

-- Validate key syntax
function M.validate_key(k)
    if not k or type(k) ~= "string" or k:match("^%s*$") then
        return false, "Keybinding cannot be empty"
    end
    -- Reject shell metacharacters and control characters
    if k:find("[;&|`$><\"'\\]") or k:find("[%c]") then
        return false, "Keybinding contains invalid or dangerous characters"
    end
    local norm = M.normalize_key(k)
    if not norm or #norm == 0 then
        return false, "Invalid key combination format"
    end
    return true, norm
end

-- Canonical key for conflict comparison (case-insensitive parts)
function M.canonical_key(k)
    if not k or type(k) ~= "string" then return nil end
    local norm = M.normalize_key(k)
    if not norm then return nil end
    return norm:lower():gsub("%s+", "")
end

-- Resolve effective bindings by applying overrides onto manifest defaults
function M.resolve_bindings(manifest, overrides)
    manifest = manifest or require("keybindings_manifest")
    overrides = overrides or M.load_overrides()

    local effective = {
        mainMod = manifest.mainMod or "SUPER",
        terminal = manifest.terminal or "kitty",
        explorer = manifest.explorer or "thunar",
        categories = manifest.categories or {},
        bindings = {},
        overrides = overrides,
    }

    for _, orig in ipairs(manifest.bindings or {}) do
        local item = {}
        for k, v in pairs(orig) do
            item[k] = v
        end

        local action_id = item.id
        if action_id and overrides[action_id] ~= nil then
            local ov = overrides[action_id]
            if ov == false or ov == "" or ov == "none" then
                item.key = nil
                item.display_key = "None (Unbound)"
                item.unbound = true
                item.user_overridden = true
            elseif type(ov) == "string" then
                local norm = M.normalize_key(ov)
                item.key = norm
                item.display_key = norm
                item.unbound = false
                item.user_overridden = true
            end
        end

        table.insert(effective.bindings, item)
    end

    return effective
end

-- Find conflict if candidate_key is assigned to action_id
function M.find_conflict(action_id, candidate_key, manifest, overrides)
    if not candidate_key or candidate_key == "" or candidate_key == false then
        return nil
    end
    local candidate_canon = M.canonical_key(candidate_key)
    if not candidate_canon then return nil end

    local effective = M.resolve_bindings(manifest, overrides)
    for _, item in ipairs(effective.bindings) do
        if item.id ~= action_id and item.key then
            local existing_canon = M.canonical_key(item.key)
            if existing_canon == candidate_canon then
                return item
            end
        end
    end
    return nil
end

-- Set, unset, or reset override for an action
function M.set_action_binding(action_id, new_key_input, manifest_path, overrides_path)
    overrides_path = overrides_path or M.get_overrides_path()
    local manifest
    if manifest_path then
        manifest = dofile(manifest_path)
    else
        manifest = require("keybindings_manifest")
    end

    -- Verify action_id exists in manifest
    local target_item = nil
    for _, item in ipairs(manifest.bindings or {}) do
        if item.id == action_id then
            target_item = item
            break
        end
    end
    if not target_item then
        return false, "Action ID not found in manifest: " .. tostring(action_id)
    end

    local overrides = M.load_overrides(overrides_path)

    -- Case 1: Reset to default
    if new_key_input == "default" then
        overrides[action_id] = nil
        local ok, save_err = M.save_overrides(overrides, overrides_path)
        if not ok then return false, save_err end
        return true, "Reset to default"
    end

    -- Case 2: Unset / unbind
    if new_key_input == false or new_key_input == nil or new_key_input == "none" or new_key_input == "-" then
        overrides[action_id] = false
        local ok, save_err = M.save_overrides(overrides, overrides_path)
        if not ok then return false, save_err end
        return true, "Unbound shortcut"
    end

    -- Case 3: Set new keybinding
    local valid, norm_or_err = M.validate_key(new_key_input)
    if not valid then
        return false, norm_or_err
    end
    local norm_key = norm_or_err

    local conflict = M.find_conflict(action_id, norm_key, manifest, overrides)
    if conflict then
        local conflict_desc = conflict.description or conflict.id or "another action"
        return false, string.format("Conflict: '%s' is already assigned to %s (%s). Cannot reassign without unbinding first.",
            norm_key, conflict_desc, conflict.id or "unnamed")
    end

    overrides[action_id] = norm_key
    local ok, save_err = M.save_overrides(overrides, overrides_path)
    if not ok then return false, save_err end
    return true, norm_key
end

return M
