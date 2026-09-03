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

-- Strict, fail-closed JSON decoder for keybindings overrides schema:
-- {
--   "<stable-action-id>": "<normalized-key>",
--   "<stable-action-id>": false
-- }
function M.parse_strict_overrides(str, manifest)
    if not str or str:match("^%s*$") then return {} end

    local valid_actions = {}
    if manifest and manifest.bindings then
        for _, b in ipairs(manifest.bindings) do
            if b.id and b.editable ~= false then
                valid_actions[b.id] = b
            end
        end
    end

    local pos = 1
    local len = #str

    local function skip_ws()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end

    skip_ws()
    if pos > len or str:sub(pos, pos) ~= "{" then
        return nil, "Invalid JSON: root must be an object beginning with {"
    end
    pos = pos + 1

    local result = {}
    local seen_keys = {}

    skip_ws()
    if pos <= len and str:sub(pos, pos) == "}" then
        pos = pos + 1
        skip_ws()
        if pos <= len then
            return nil, "Trailing garbage after JSON object at byte " .. pos
        end
        return result
    end

    local function parse_string()
        if pos > len or str:sub(pos, pos) ~= "\"" then
            return nil, "Expected string starting with \" at byte " .. pos
        end
        pos = pos + 1
        local chars = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == "\"" then
                pos = pos + 1
                return table.concat(chars)
            elseif c == "\\" then
                pos = pos + 1
                if pos > len then return nil, "Unterminated escape in string" end
                local esc = str:sub(pos, pos)
                if esc == "\"" or esc == "\\" or esc == "/" then
                    table.insert(chars, esc)
                elseif esc == "b" then table.insert(chars, "\b")
                elseif esc == "f" then table.insert(chars, "\f")
                elseif esc == "n" then table.insert(chars, "\n")
                elseif esc == "r" then table.insert(chars, "\r")
                elseif esc == "t" then table.insert(chars, "\t")
                elseif esc == "u" then
                    if pos + 4 > len then return nil, "Incomplete unicode escape" end
                    local hex = str:sub(pos + 1, pos + 4)
                    if not hex:match("^[0-9a-fA-F]{4}$") then
                        return nil, "Invalid unicode escape \\u" .. hex
                    end
                    local code = tonumber(hex, 16)
                    if code < 128 then
                        table.insert(chars, string.char(code))
                    else
                        table.insert(chars, "?")
                    end
                    pos = pos + 4
                else
                    return nil, "Invalid escape sequence \\" .. esc
                end
                pos = pos + 1
            elseif c:byte() < 32 then
                return nil, "Unescaped control character in string"
            else
                table.insert(chars, c)
                pos = pos + 1
            end
        end
        return nil, "Unterminated string literal"
    end

    while pos <= len do
        skip_ws()
        if pos > len then return nil, "Unexpected EOF inside JSON object" end

        -- Parse key
        local key, k_err = parse_string()
        if not key then return nil, k_err end

        local is_app_action = key:match("^app:[%w%-%._]+%.desktop$")
        if manifest and not valid_actions[key] and not is_app_action then
            return nil, "Unknown or uneditable action ID in overrides: " .. tostring(key)
        end

        if seen_keys[key] then
            return nil, "Duplicate key in overrides: " .. tostring(key)
        end
        seen_keys[key] = true

        skip_ws()
        if pos > len or str:sub(pos, pos) ~= ":" then
            return nil, "Expected \":\" after key \"" .. key .. "\" at byte " .. pos
        end
        pos = pos + 1
        skip_ws()

        -- Parse value: strictly string or false
        local val
        local next_c = str:sub(pos, pos)
        if next_c == "\"" then
            local val_str, v_err = parse_string()
            if not val_str then return nil, v_err end
            local valid_k, norm_or_err = M.validate_key(val_str)
            if not valid_k then
                return nil, "Invalid key syntax for key \"" .. key .. "\": " .. tostring(norm_or_err)
            end
            val = norm_or_err
        elseif str:sub(pos, pos + 4) == "false" then
            val = false
            pos = pos + 5
            local follow = str:sub(pos, pos)
            if follow ~= "" and not follow:match("^[%s,%}]$") then
                return nil, "Invalid token starting with false at byte " .. pos
            end
        else
            return nil, "Invalid value for key \"" .. key .. "\": only string or false allowed"
        end

        result[key] = val

        skip_ws()
        if pos > len then return nil, "Unexpected EOF after value for key \"" .. key .. "\"" end
        local delim = str:sub(pos, pos)
        if delim == "," then
            pos = pos + 1
            skip_ws()
            if pos <= len and str:sub(pos, pos) == "}" then
                return nil, "Trailing comma before } is not allowed in JSON"
            end
        elseif delim == "}" then
            pos = pos + 1
            break
        else
            return nil, "Expected \",\" or \"}\" after value, found \"" .. delim .. "\" at byte " .. pos
        end
    end

    skip_ws()
    if pos <= len then
        return nil, "Trailing garbage after JSON object at byte " .. pos
    end

    return result
end

-- Pure Lua strict JSON encoder for overrides schema
function M.json_encode(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do
        local v = tbl[k]
        if type(v) == "string" then
            table.insert(lines, string.format("  %q: %q", k, v))
        elseif v == false then
            table.insert(lines, string.format("  %q: false", k))
        end
    end
    return "{\n" .. table.concat(lines, ",\n") .. "\n}\n"
end

-- Load overrides from disk safely (fail-closed)
function M.load_overrides(path, manifest)
    path = path or M.get_overrides_path()
    local f = io.open(path, "r")
    if not f then
        return {}
    end
    local content = f:read("*a")
    f:close()

    if not content or content:match("^%s*$") then
        return {}
    end

    local parsed, err = M.parse_strict_overrides(content, manifest)
    if not parsed then
        return nil, "Malformed keybindings override file: " .. tostring(err)
    end
    return parsed
end

-- POSIX shell single-quote escaper
local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Safely and exclusively create a temporary file in target directory,
-- write content with 0600 permissions, and atomically rename to final destination.
local function atomic_write_file(path, content)
    local dir = path:match("^(.*)/[^/]+$")
    if not dir or dir == "" then dir = "." end

    -- Ensure parent directory with 0700 permissions
    local dir_cmd = "mkdir -p -m 0700 " .. sh_quote(dir)
    local ok_dir = os.execute(dir_cmd)
    if ok_dir ~= 0 and ok_dir ~= true then
        return false, "Failed to create directory: " .. tostring(dir)
    end

    -- Create exclusive temporary file using mktemp with template in target directory.
    -- mktemp uses mkstemp() (O_CREAT | O_EXCL) creating the file with mode 0600 atomically,
    -- eliminating symlink following and permission race windows.
    local template = dir .. "/.tmp.overrides.XXXXXX"
    local p = io.popen("mktemp " .. sh_quote(template) .. " 2>/dev/null", "r")
    if not p then
        return false, "Failed to invoke mktemp for exclusive temporary file"
    end
    local tmp_path = p:read("*l")
    local ok_p = p:close()
    if not ok_p or not tmp_path or tmp_path == "" then
        return false, "Failed to create exclusive temporary file via mktemp"
    end

    local f, err = io.open(tmp_path, "w")
    if not f then
        os.remove(tmp_path)
        return false, "Failed to open temporary file for writing: " .. tostring(err)
    end
    f:write(content)
    f:flush()
    f:close()

    local ok, ren_err = os.rename(tmp_path, path)
    if not ok then
        os.remove(tmp_path)
        return false, "Failed to atomically rename overrides file: " .. tostring(ren_err)
    end
    return true
end

-- Save overrides atomically using exclusive temporary file creation and atomic rename
function M.save_overrides(overrides, path)
    path = path or M.get_overrides_path()
    return atomic_write_file(path, M.json_encode(overrides))
end


-- Standard application search paths
local APP_SEARCH_DIRS = {
    (os.getenv("HOME") or "") .. "/.local/share/applications",
    "/usr/local/share/applications",
    "/usr/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    (os.getenv("HOME") or "") .. "/.local/share/flatpak/exports/share/applications",
}

-- Parse a single desktop entry file safely
function M.parse_desktop_file(filepath)
    local f = io.open(filepath, "r")
    if not f then return nil end
    local in_entry = false
    local data = { path = filepath }
    for line in f:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line:match("^%[Desktop Entry%]$") then
            in_entry = true
        elseif line:match("^%[") then
            in_entry = false
        elseif in_entry then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                k = k:gsub("%s+$", "")
                data[k] = v
            end
        end
    end
    f:close()

    if data.Type ~= "Application" then return nil end
    if data.NoDisplay == "true" or data.Hidden == "true" then return nil end
    if not data.Name or data.Name == "" then return nil end

    return {
        desktop_id = filepath:match("([^/]+)$"),
        name = data.Name,
        generic_name = data.GenericName,
        comment = data.Comment,
        exec = data.Exec,
        icon = data.Icon,
        categories = data.Categories,
        path = filepath,
    }
end

-- Find a specific desktop application by desktop_id
function M.find_desktop_app(desktop_id)
    if not desktop_id or type(desktop_id) ~= "string" or not desktop_id:match("%.desktop$") then
        return nil
    end
    for _, dir in ipairs(APP_SEARCH_DIRS) do
        local path = dir .. "/" .. desktop_id
        local app = M.parse_desktop_file(path)
        if app then return app end
    end
    return nil
end

-- Query truthfully detectable system default roles
function M.get_truthful_default_roles()
    local defaults = {}
    local p_br = io.popen("xdg-mime query default x-scheme-handler/https 2>/dev/null", "r")
    if p_br then
        local br = p_br:read("*l")
        p_br:close()
        if br and br ~= "" then defaults[br] = "Default Browser" end
    end
    local p_fm = io.popen("xdg-mime query default inode/directory 2>/dev/null", "r")
    if p_fm then
        local fm = p_fm:read("*l")
        p_fm:close()
        if fm and fm ~= "" then defaults[fm] = "Default File Manager" end
    end
    local p_te = io.popen("xdg-mime query default text/plain 2>/dev/null", "r")
    if p_te then
        local te = p_te:read("*l")
        p_te:close()
        if te and te ~= "" then defaults[te] = "Default Text Editor" end
    end
    return defaults
end

-- List all installed desktop applications
function M.list_installed_applications()
    local seen = {}
    local apps = {}
    local default_roles = M.get_truthful_default_roles()

    for _, dir in ipairs(APP_SEARCH_DIRS) do
        local p = io.popen("ls -1 " .. sh_quote(dir) .. "/*.desktop 2>/dev/null", "r")
        if p then
            for f in p:lines() do
                local base = f:match("([^/]+)$")
                if base and not seen[base] then
                    seen[base] = true
                    local info = M.parse_desktop_file(f)
                    if info then
                        info.default_role = default_roles[base]
                        table.insert(apps, info)
                    end
                end
            end
            p:close()
        end
    end

    table.sort(apps, function(a, b)
        local na = (a.name or ""):lower()
        local nb = (b.name or ""):lower()
        if na ~= nb then return na < nb end
        return a.desktop_id < b.desktop_id
    end)

    return apps
end

-- Resolve effective bindings by applying overrides onto manifest defaults
function M.resolve_bindings(manifest, overrides)
    manifest = manifest or require("keybindings_manifest")
    if overrides == nil then
        local loaded, err = M.load_overrides(nil, manifest)
        if not loaded then
            return nil, err
        end
        overrides = loaded
    end

    local effective = {
        mainMod = manifest.mainMod or "SUPER",
        terminal = manifest.terminal or "kitty",
        explorer = manifest.explorer or "thunar",
        categories = manifest.categories or {},
        bindings = {},
        overrides = overrides,
    }

    local known_ids = {}

    for _, orig in ipairs(manifest.bindings or {}) do
        local item = {}
        for k, v in pairs(orig) do
            item[k] = v
        end

        local action_id = item.id
        if action_id then
            known_ids[action_id] = true
            if overrides[action_id] ~= nil then
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
        end

        table.insert(effective.bindings, item)
    end

    -- Process application-specific overrides (e.g. "app:foo.desktop")
    for action_id, ov in pairs(overrides) do
        if not known_ids[action_id] then
            local app_desktop = action_id:match("^app:([%w%-%._]+%.desktop)$")
            if app_desktop then
                local app_info = M.find_desktop_app(app_desktop)
                local app_name = (app_info and app_info.name) and app_info.name or app_desktop:gsub("%.desktop$", "")
                local item = {
                    id = action_id,
                    priority = 45,
                    editable = true,
                    runnable = true,
                    category = "Applications & Launchers",
                    desktop_id = app_desktop,
                    description = "Launch " .. app_name,
                    action_type = "exec",
                    command = "gtk-launch " .. app_desktop,
                    command_argv = { "gtk-launch", app_desktop },
                    user_overridden = true,
                }
                if ov == false or ov == "" or ov == "none" then
                    item.key = nil
                    item.display_key = "None (Unbound)"
                    item.unbound = true
                elseif type(ov) == "string" then
                    local norm = M.normalize_key(ov)
                    item.key = norm
                    item.display_key = norm
                    item.unbound = false
                end
                table.insert(effective.bindings, item)
            end
        end
    end

    -- Deterministic, metadata-driven sort prioritizing discoverability:
    -- 1. Explicit priority (ascending)
    -- 2. Category order rank in manifest (ascending)
    -- 3. Description (alphabetical)
    -- 4. Action ID (tiebreaker)
    local cat_rank = {}
    for idx, c in ipairs(effective.categories or {}) do
        cat_rank[c] = idx
    end

    table.sort(effective.bindings, function(a, b)
        local pa = a.priority or 999
        local pb = b.priority or 999
        if pa ~= pb then
            return pa < pb
        end
        local ca = cat_rank[a.category] or 999
        local cb = cat_rank[b.category] or 999
        if ca ~= cb then
            return ca < cb
        end
        local da = a.description or ""
        local db = b.description or ""
        if da ~= db then
            return da < db
        end
        return (a.id or "") < (b.id or "")
    end)

    return effective
end

-- Find conflict if candidate_key is assigned to action_id
function M.find_conflict(action_id, candidate_key, manifest, overrides)
    if not candidate_key or candidate_key == "" or candidate_key == false then
        return nil
    end
    local candidate_canon = M.canonical_key(candidate_key)
    if not candidate_canon then return nil end

    local effective, err = M.resolve_bindings(manifest, overrides)
    if not effective then return nil, err end

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

-- Reload Hyprland session safely (single owner of reload execution)
function M.reload_session()
    local log_file = os.getenv("HOTKEYS_RELOAD_LOG")
    if log_file and log_file ~= "" then
        local f = io.open(log_file, "a")
        if f then
            f:write("RELOAD\n")
            f:close()
        end
    end
    if os.getenv("HOTKEYS_SIMULATE_RELOAD_FAIL") == "1" then
        return false, "Simulated reload failure"
    end
    if os.getenv("HYPRLAND_INSTANCE_SIGNATURE") and os.getenv("HYPRLAND_INSTANCE_SIGNATURE") ~= "" then
        local ret = os.execute("hyprctl reload config-only >/dev/null 2>&1 || hyprctl reload >/dev/null 2>&1")
        if ret ~= 0 and ret ~= true then
            return false, "hyprctl reload exited with failure status"
        end
    end
    return true
end


-- Transactional set/edit binding with rollback on reload failure
function M.set_action_binding(action_id, new_key_input, manifest_path, overrides_path, reload_fn)
    overrides_path = overrides_path or M.get_overrides_path()
    local manifest
    if manifest_path then
        manifest = dofile(manifest_path)
    else
        manifest = require("keybindings_manifest")
    end

    reload_fn = reload_fn or M.reload_session

    -- 1. Verify action_id exists in manifest or is a valid desktop application
    local target_item = nil
    for _, item in ipairs(manifest.bindings or {}) do
        if item.id == action_id then
            target_item = item
            break
        end
    end
    if not target_item then
        local app_desktop = action_id:match("^app:([%w%-%._]+%.desktop)$")
        if app_desktop then
            local app_info = M.find_desktop_app(app_desktop)
            if app_info then
                target_item = {
                    id = action_id,
                    priority = 45,
                    editable = true,
                    runnable = true,
                    category = "Applications & Launchers",
                    desktop_id = app_desktop,
                    description = "Launch " .. (app_info.name or app_desktop),
                    action_type = "exec",
                    command = "gtk-launch " .. app_desktop,
                    command_argv = { "gtk-launch", app_desktop },
                }
            else
                return false, "Desktop application not found: " .. app_desktop
            end
        else
            return false, "Action ID not found in manifest: " .. tostring(action_id)
        end
    end

    -- 2. Verify action is editable
    if not target_item.editable then
        local reason = "This action is not editable as an individual keyboard shortcut."
        if target_item.generator then
            reason = "Generated aggregate workspace bindings cannot be edited as a single shortcut."
        elseif target_item.action_type == "gesture" then
            reason = "Hardware touchpad gestures cannot be edited as keyboard shortcuts."
        elseif target_item.mouse then
            reason = "Mouse button bindings cannot be edited through the keyboard hotkey manager."
        end
        return false, string.format("Action '%s' is not editable: %s", action_id, reason)
    end

    -- 3. Capture previous state for rollback
    local prev_exists = false
    local prev_raw = nil
    local f_prev = io.open(overrides_path, "r")
    if f_prev then
        prev_exists = true
        prev_raw = f_prev:read("*a")
        f_prev:close()
    end

    -- 4. Load current overrides (fails closed if existing file is corrupt)
    local overrides, load_err = M.load_overrides(overrides_path, manifest)
    if not overrides then
        return false, "Cannot modify corrupt overrides file: " .. tostring(load_err)
    end

    -- 5. Prepare candidate modification
    local candidate = {}
    for k, v in pairs(overrides) do candidate[k] = v end

    local action_result_msg = ""
    if new_key_input == "default" then
        candidate[action_id] = nil
        action_result_msg = "Reset to default"
    elseif new_key_input == false or new_key_input == nil or new_key_input == "none" or new_key_input == "-" then
        candidate[action_id] = false
        action_result_msg = "Unbound shortcut"
    else
        local valid, norm_or_err = M.validate_key(new_key_input)
        if not valid then
            return false, norm_or_err
        end
        local norm_key = norm_or_err

        local conflict = M.find_conflict(action_id, norm_key, manifest, candidate)
        if conflict then
            local conflict_desc = conflict.description or conflict.id or "another action"
            return false, string.format("Conflict: '%s' is already assigned to %s (%s). Cannot reassign without unbinding first.",
                norm_key, conflict_desc, conflict.id or "unnamed")
        end

        candidate[action_id] = norm_key
        action_result_msg = norm_key
    end

    -- 6. Atomically persist candidate
    local ok_save, save_err = M.save_overrides(candidate, overrides_path)
    if not ok_save then
        return false, save_err
    end

    -- 7. Apply activation (reload)
    local ok_reload, reload_err = reload_fn()
    if ok_reload then
        return true, action_result_msg
    end

    -- 8. Transaction failed -> ROLLBACK!
    if os.getenv("HOTKEYS_SIMULATE_ROLLBACK_FAIL") == "1" then
        return false, "FATAL: Activation failed (" .. tostring(reload_err) .. ") AND rollback failed: simulated rollback error"
    end

    local rollback_ok = true
    local rollback_err = nil
    if prev_exists and prev_raw then
        -- Atomically restore previous content using exclusive atomic writer
        local ok_restore, err_restore = atomic_write_file(overrides_path, prev_raw)
        if not ok_restore then
            rollback_ok = false
            rollback_err = err_restore
        end
    else
        -- File did not exist: remove candidate file to restore absence
        local rem_ok, rem_err = os.remove(overrides_path)
        if not rem_ok and prev_exists then
            rollback_ok = false
            rollback_err = rem_err
        end
    end


    if not rollback_ok then
        return false, string.format("FATAL: Activation failed (%s) AND rollback failed: %s",
            tostring(reload_err), tostring(rollback_err))
    end

    -- Trigger reload again to restore previous runtime state
    reload_fn()

    return false, string.format("Activation failed: %s (transaction rolled back to previous state)",
        tostring(reload_err))
end

-- Unified application shortcut assignment
function M.assign_application_shortcut(desktop_id, new_key_input, manifest_path, overrides_path, reload_fn)
    manifest_path = manifest_path or nil
    local manifest
    if manifest_path then
        manifest = dofile(manifest_path)
    else
        manifest = require("keybindings_manifest")
    end

    local action_id = nil
    for _, item in ipairs(manifest.bindings or {}) do
        if item.desktop_id == desktop_id then
            action_id = item.id
            break
        end
    end
    if not action_id then
        action_id = "app:" .. desktop_id
    end

    return M.set_action_binding(action_id, new_key_input, manifest_path, overrides_path, reload_fn)
end

-- Retrieve structured command_argv for a runnable action
function M.get_action_argv(action_id, manifest)
    manifest = manifest or require("keybindings_manifest")
    for _, item in ipairs(manifest.bindings or {}) do
        if item.id == action_id then
            if item.runnable == true and type(item.command_argv) == "table" and #item.command_argv > 0 then
                for _, a in ipairs(item.command_argv) do
                    if type(a) ~= "string" then
                        return nil, "Invalid command_argv: elements must be strings"
                    end
                end
                return item.command_argv
            else
                return nil, "Action is not runnable or lacks structured command_argv"
            end
        end
    end
    local app_desktop = action_id:match("^app:([%w%-%._]+%.desktop)$")
    if app_desktop then
        return { "gtk-launch", app_desktop }
    end
    return nil, "Action ID not found in manifest: " .. tostring(action_id)
end

return M


