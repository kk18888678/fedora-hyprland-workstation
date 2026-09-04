-- Module: effective_bindings
-- Single source of truth for resolving effective keybindings by combining
-- the declarative manifest (defaults) with user-owned overrides and user-created actions.
-- Consumed by both Hyprland runtime session (keybind.lua) and workstation-keybindings.

local M = {}

-- Require the decoupled Workstation Application Registry
local app_reg = require("application_registry")

-- Determine user override file location
function M.get_overrides_path()
    local env_path = os.getenv("KEYBINDINGS_OVERRIDES")
    if not env_path or env_path == "" then
        env_path = os.getenv("HOTKEYS_OVERRIDES")
    end
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

-- Determine user-created actions file location (~/.config/hypr/user_actions.json)
function M.get_user_actions_path()
    local env_path = os.getenv("KEYBINDINGS_USER_ACTIONS") or os.getenv("USER_ACTIONS_PATH")
    if env_path and env_path ~= "" then
        return env_path
    end
    local config_home = os.getenv("XDG_CONFIG_HOME")
    if not config_home or config_home == "" then
        local home = os.getenv("HOME") or ""
        config_home = home .. "/.config"
    end
    return config_home .. "/hypr/user_actions.json"
end

-- Determine desktop config file location (~/.config/workstation/desktop.conf)
function M.get_desktop_config_path()
    local config_home = os.getenv("XDG_CONFIG_HOME")
    if not config_home or config_home == "" then
        local home = os.getenv("HOME") or ""
        config_home = home .. "/.config"
    end
    return config_home .. "/workstation/desktop.conf"
end

-- Dynamically delegate app_reg desktop config path to M.get_desktop_config_path
app_reg.get_desktop_config_path = function()
    return M.get_desktop_config_path()
end

-- Read key-value pairs from desktop.conf
function M.read_desktop_config()
    return app_reg.read_desktop_config()
end

-- Forward command info requests through the Application Registry
function M.get_app_command_info(app)
    if not app or type(app) ~= "string" then return nil end
    local info = app_reg.find_application(app)
    if info then
        return {
            name = info.name,
            command = info.command,
            command_argv = info.command_argv,
            desktop_id = info.desktop_id,
            icon = info.icon,
        }
    end
    return nil
end

-- Dynamically resolve active application for a generic workstation role
-- Returns canonical name and app_info table
function M.resolve_role_default(role)
    if not role or type(role) ~= "string" then return nil end
    local canon, info = app_reg.resolve_role(role)
    return canon, info
end

-- Normalize key string with strict canonical modifier ordering (SUPER -> CTRL -> ALT -> SHIFT -> KEY)
function M.normalize_key(k)
    if not k or type(k) ~= "string" then return nil end
    k = k:gsub("^%s+", ""):gsub("%s+$", "")
    if k == "" then return nil end

    local has_super = false
    local has_ctrl = false
    local has_alt = false
    local has_shift = false
    local key_parts = {}

    for part in k:gmatch("[^%+]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then
            local upper = part:upper()
            if upper == "SUPER" or upper == "MOD4" or upper == "WIN" then
                has_super = true
            elseif upper == "CTRL" or upper == "CONTROL" then
                has_ctrl = true
            elseif upper == "ALT" or upper == "MOD1" then
                has_alt = true
            elseif upper == "SHIFT" then
                has_shift = true
            else
                table.insert(key_parts, upper)
            end
        end
    end

    if not has_super and not has_ctrl and not has_alt and not has_shift and #key_parts == 0 then
        return nil
    end

    local canonical_parts = {}
    if has_super then table.insert(canonical_parts, "SUPER") end
    if has_ctrl  then table.insert(canonical_parts, "CTRL") end
    if has_alt   then table.insert(canonical_parts, "ALT") end
    if has_shift then table.insert(canonical_parts, "SHIFT") end
    for _, kp in ipairs(key_parts) do
        table.insert(canonical_parts, kp)
    end

    return table.concat(canonical_parts, " + ")
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

local FRIENDLY_NAMES = {
    ["SUPER"] = "Super",
    ["CTRL"] = "Ctrl",
    ["CONTROL"] = "Ctrl",
    ["ALT"] = "Alt",
    ["SHIFT"] = "Shift",
    ["RETURN"] = "Return",
    ["ENTER"] = "Return",
    ["SPACE"] = "Space",
    ["TAB"] = "Tab",
    ["ESC"] = "Esc",
    ["ESCAPE"] = "Esc",
    ["BACKSPACE"] = "Backspace",
    ["LEFT"] = "Left",
    ["RIGHT"] = "Right",
    ["UP"] = "Up",
    ["DOWN"] = "Down",
    ["DELETE"] = "Delete",
    ["INSERT"] = "Insert",
    ["HOME"] = "Home",
    ["END"] = "End",
    ["PAGEUP"] = "PageUp",
    ["PAGEDOWN"] = "PageDown",
}

-- Separate internal canonical representation from presentation
function M.format_friendly_key(k)
    if not k or type(k) ~= "string" or k == "" then return "None (Unbound)" end
    if k == "None (Unbound)" or k == "none" or k == "NONE" then return "None (Unbound)" end
    if k:find("Swipe") or k:find("Key") or k:find("Drag") or k:find("%.%.") then return k end

    local parts = {}
    for part in k:gmatch("[^%+]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then
            local upper = part:upper()
            if FRIENDLY_NAMES[upper] then
                table.insert(parts, FRIENDLY_NAMES[upper])
            elseif #part == 1 then
                table.insert(parts, part:upper())
            else
                table.insert(parts, part:sub(1,1):upper() .. part:sub(2):lower())
            end
        end
    end
    if #parts == 0 then return k end
    return table.concat(parts, " + ")
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
                    if not hex:match("^%x%x%x%x$") then
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

        local is_app_action = key:match("^app:[a-zA-Z0-9][%w%-%._]*%.desktop$")
        if manifest and not valid_actions[key] and not (key == "hotkeys" and valid_actions["keybindings"]) and not is_app_action then
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

-- UTF-8 encoding helper for unicode escapes
local function utf8_encode(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
    else
        return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + (math.floor(code / 0x1000) % 0x40), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
    end
end

-- Strict, fail-closed JSON and schema decoder for user_actions.json:
-- Schema:
-- {
--   "version": 1,
--   "actions": [ "foo.desktop", ... ]
-- }
function M.parse_strict_user_actions(str)
    if not str or type(str) ~= "string" or str:match("^%s*$") then
        return { version = 1, actions = {} }
    end

    if #str > 65536 then
        return nil, "user_actions.json exceeds maximum size of 64KB"
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
                    if not hex:match("^%x%x%x%x$") then
                        return nil, "Invalid unicode escape \\u" .. hex
                    end
                    local code = tonumber(hex, 16)
                    table.insert(chars, utf8_encode(code))
                    pos = pos + 4
                else
                    return nil, "Invalid escape sequence \\" .. esc
                end
                pos = pos + 1
            elseif c:byte() < 32 then
                return nil, "Unescaped control character in string at byte " .. pos
            else
                table.insert(chars, c)
                pos = pos + 1
            end
        end
        return nil, "Unterminated string literal"
    end

    local function parse_number()
        local start_pos = pos
        if str:sub(pos, pos) == "-" then pos = pos + 1 end
        while pos <= len and str:sub(pos, pos):match("[0-9]") do
            pos = pos + 1
        end
        local num_str = str:sub(start_pos, pos - 1)
        local n = tonumber(num_str)
        if not n then return nil, "Invalid number at byte " .. start_pos end
        return n
    end

    skip_ws()
    if pos > len or str:sub(pos, pos) ~= "{" then
        return nil, "Invalid JSON: root must be an object beginning with {"
    end
    pos = pos + 1

    local version = nil
    local actions = nil
    local seen_keys = {}

    skip_ws()
    if pos <= len and str:sub(pos, pos) == "}" then
        pos = pos + 1
        skip_ws()
        if pos <= len then
            return nil, "Trailing garbage after JSON object at byte " .. pos
        end
        return nil, "Invalid user_actions schema: missing version and actions fields"
    end

    while pos <= len do
        skip_ws()
        if pos > len then return nil, "Unexpected EOF inside JSON object" end

        local key, k_err = parse_string()
        if not key then return nil, k_err end

        if seen_keys[key] then
            return nil, "Duplicate key in user_actions: " .. tostring(key)
        end
        seen_keys[key] = true

        skip_ws()
        if pos > len or str:sub(pos, pos) ~= ":" then
            return nil, "Expected \":\" after key \"" .. key .. "\" at byte " .. pos
        end
        pos = pos + 1
        skip_ws()

        if key == "version" then
            local v_num, n_err = parse_number()
            if not v_num then return nil, n_err end
            if v_num ~= 1 then
                return nil, "Unsupported user_actions schema version: " .. tostring(v_num) .. " (expected 1)"
            end
            version = v_num
        elseif key == "actions" then
            if pos > len or str:sub(pos, pos) ~= "[" then
                return nil, "Invalid actions field: expected array beginning with [ at byte " .. pos
            end
            pos = pos + 1
            actions = {}
            local seen_actions = {}

            skip_ws()
            if pos <= len and str:sub(pos, pos) == "]" then
                pos = pos + 1
            else
                while pos <= len do
                    skip_ws()
                    local act_str, a_err = parse_string()
                    if not act_str then return nil, a_err end

                    -- Validate desktop ID syntax: must start with alphanumeric, contain only valid chars, end with .desktop, no traversal, no leading dash
                    if not act_str:match("^[a-zA-Z0-9][%w%-%._]*%.desktop$") or act_str:find("%.%./") or act_str:sub(1, 1) == "-" then
                        return nil, "Invalid desktop ID in actions array: " .. tostring(act_str)
                    end

                    if not seen_actions[act_str] then
                        seen_actions[act_str] = true
                        table.insert(actions, act_str)
                    end

                    skip_ws()
                    if pos <= len and str:sub(pos, pos) == "]" then
                        pos = pos + 1
                        break
                    elseif pos <= len and str:sub(pos, pos) == "," then
                        pos = pos + 1
                    else
                        return nil, "Expected \",\" or \"]\" in actions array at byte " .. pos
                    end
                end
            end
        else
            return nil, "Unknown field in user_actions: \"" .. key .. "\""
        end

        skip_ws()
        if pos <= len and str:sub(pos, pos) == "}" then
            pos = pos + 1
            break
        elseif pos <= len and str:sub(pos, pos) == "," then
            pos = pos + 1
        else
            return nil, "Expected \",\" or \"}\" inside JSON object at byte " .. pos
        end
    end

    skip_ws()
    if pos <= len then
        return nil, "Trailing garbage after JSON object at byte " .. pos
    end

    if not version then
        return nil, "Missing required \"version\" field in user_actions"
    end
    if not actions then
        return nil, "Missing required \"actions\" field in user_actions"
    end

    return { version = version, actions = actions }
end

-- Load user-created actions safely using strict fail-closed JSON parser
function M.load_user_actions(path)
    path = path or M.get_user_actions_path()
    local f = io.open(path, "r")
    if not f then
        return { version = 1, actions = {} }
    end
    -- Bounded read to 64KB
    local content = f:read(65536)
    f:close()

    if not content or content:match("^%s*$") then
        return { version = 1, actions = {} }
    end

    return M.parse_strict_user_actions(content)
end

-- Serialize user-created actions
function M.encode_user_actions(tbl)
    local actions = (tbl and tbl.actions) or {}
    table.sort(actions)
    local lines = {}
    for _, did in ipairs(actions) do
        table.insert(lines, string.format("    %q", did))
    end
    return "{\n  \"version\": 1,\n  \"actions\": [\n" .. table.concat(lines, ",\n") .. "\n  ]\n}\n"
end

-- Save user-created actions atomically
function M.save_user_actions(data, path)
    path = path or M.get_user_actions_path()
    return atomic_write_file(path, M.encode_user_actions(data))
end

-- Add a user-created application action
function M.add_user_application_action(desktop_id, user_actions_path, overrides_path, reload_fn)
    if not desktop_id or type(desktop_id) ~= "string" or not desktop_id:match("^[a-zA-Z0-9][%w%-%._]*%.desktop$") then
        return false, "Invalid desktop ID: must start with alphanumeric character and end with .desktop"
    end

    user_actions_path = user_actions_path or M.get_user_actions_path()
    reload_fn = reload_fn or M.reload_session

    local app_info = app_reg.find_application(desktop_id)
    if not app_info then
        return false, "Desktop application not found in Application Registry: " .. desktop_id
    end

    local current, err = M.load_user_actions(user_actions_path)
    if not current then
        return false, "Failed to load user actions: " .. tostring(err)
    end

    local exists = false
    for _, did in ipairs(current.actions) do
        if did == desktop_id then
            exists = true
            break
        end
    end

    if not exists then
        table.insert(current.actions, desktop_id)
        local ok_save, save_err = M.save_user_actions(current, user_actions_path)
        if not ok_save then
            return false, "Failed to save user actions: " .. tostring(save_err)
        end
    end

    reload_fn()
    return true, "Application action added: " .. (app_info.name or desktop_id)
end

-- Remove a user-created application action
function M.remove_user_application_action(desktop_id, user_actions_path, overrides_path, reload_fn)
    if not desktop_id or type(desktop_id) ~= "string" or not desktop_id:match("^[a-zA-Z0-9][%w%-%._]*%.desktop$") then
        return false, "Invalid desktop ID: must start with alphanumeric character and end with .desktop"
    end

    user_actions_path = user_actions_path or M.get_user_actions_path()
    overrides_path = overrides_path or M.get_overrides_path()
    reload_fn = reload_fn or M.reload_session

    local current, err = M.load_user_actions(user_actions_path)
    if not current then
        return false, "Failed to load user actions: " .. tostring(err)
    end

    local new_actions = {}
    for _, did in ipairs(current.actions) do
        if did ~= desktop_id then
            table.insert(new_actions, did)
        end
    end
    current.actions = new_actions

    local ok_save, save_err = M.save_user_actions(current, user_actions_path)
    if not ok_save then
        return false, "Failed to save user actions: " .. tostring(save_err)
    end

    -- Also remove override for app:<desktop_id> if present
    local overrides = M.load_overrides(overrides_path)
    local action_id = "app:" .. desktop_id
    if overrides and overrides[action_id] ~= nil then
        overrides[action_id] = nil
        M.save_overrides(overrides, overrides_path)
    end

    reload_fn()
    return true, "Application action removed: " .. desktop_id
end

-- Forward legacy desktop entry functions through the Application Registry
function M.parse_desktop_file(filepath)
    return app_reg.parse_desktop_file(filepath)
end

function M.find_desktop_app(desktop_id)
    return app_reg.find_application(desktop_id)
end

function M.get_truthful_default_roles()
    return app_reg.get_truthful_default_roles()
end

function M.list_installed_applications(options)
    return app_reg.list_applications(options)
end

-- Resolve effective bindings by applying overrides and user actions onto manifest defaults
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
        explorer = manifest.explorer or "nautilus",
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
            -- Role-based dynamic resolution through Application Registry
            if action_id == "terminal" or action_id == "terminal.default" then
                local canon, info = M.resolve_role_default("terminal")
                if canon and type(info) == "table" then
                    item.command = info.command
                    item.command_argv = info.command_argv
                    item.desktop_id = info.desktop_id
                    item.icon = info.icon
                else
                    item.runnable = false
                    item.command = nil
                    item.command_argv = nil
                    item.description = item.description .. " (unavailable)"
                end
            elseif action_id == "file_manager" or action_id == "files.default" or action_id == "files" or action_id == "explorer" then
                local canon, info = M.resolve_role_default("file-manager")
                if canon and type(info) == "table" then
                    item.command = info.command
                    item.command_argv = info.command_argv
                    item.desktop_id = info.desktop_id
                    item.icon = info.icon
                else
                    item.runnable = false
                    item.command = nil
                    item.command_argv = nil
                    item.description = item.description .. " (unavailable)"
                end
            elseif action_id == "browser" or action_id == "browser.default" then
                local canon, info = M.resolve_role_default("browser")
                if canon and type(info) == "table" then
                    item.command = info.command
                    item.command_argv = info.command_argv
                    item.desktop_id = info.desktop_id
                    item.icon = info.icon
                else
                    item.runnable = false
                    item.command = nil
                    item.command_argv = nil
                    item.description = item.description .. " (unavailable)"
                end
            else
                -- Check legacy specific app shortcuts (e.g. terminal.kitty, files.nautilus)
                local role_prefix, specific_app = tostring(action_id):match("^(%w+)%.([%w%-_]+)$")
                if role_prefix and specific_app then
                    local app_info = app_reg.find_application(specific_app)
                    if app_info then
                        item.command = app_info.command
                        item.command_argv = app_info.command_argv
                        item.desktop_id = app_info.desktop_id
                        item.icon = app_info.icon
                    else
                        item.runnable = false
                        item.command = nil
                        item.command_argv = nil
                    end
                end
            end

            known_ids[action_id] = true
            local ov = overrides[action_id]
            if ov == nil and action_id == "keybindings" then
                ov = overrides["hotkeys"]
            end
            if ov ~= nil then
                if ov == false or ov == "" or ov == "none" then
                    item.key = nil
                    item.display_key = "None (Unbound)"
                    item.unbound = true
                    item.user_overridden = true
                elseif type(ov) == "string" then
                    local norm = M.normalize_key(ov)
                    item.key = norm
                    item.display_key = M.format_friendly_key(norm)
                    item.unbound = false
                    item.user_overridden = true
                end
            else
                if item.display_key then
                    item.display_key = M.format_friendly_key(item.display_key)
                    item.unbound = (item.display_key == "None (Unbound)" or item.unbound == true)
                elseif item.key then
                    item.display_key = M.format_friendly_key(item.key)
                    item.unbound = false
                else
                    item.display_key = "None (Unbound)"
                    item.unbound = true
                end
            end
        end

        table.insert(effective.bindings, item)
    end

    -- Process user-created application actions from user_actions.json
    local user_actions_data = M.load_user_actions()
    if user_actions_data and user_actions_data.actions then
        for _, did in ipairs(user_actions_data.actions) do
            local action_id = "app:" .. did
            if not known_ids[action_id] then
                known_ids[action_id] = true
                local app_info = app_reg.find_application(did)
                local app_name = (app_info and app_info.name) or did:gsub("%.desktop$", "")
                local app_icon = (app_info and app_info.icon) or ""
                local is_runnable = (app_info ~= nil)
                local desc = app_name
                if not is_runnable then
                    desc = desc .. " (unavailable)"
                end
                local item = {
                    id = action_id,
                    priority = 100,
                    editable = true,
                    runnable = is_runnable,
                    category = "Applications & Launchers",
                    desktop_id = did,
                    description = desc,
                    icon = app_icon,
                    action_type = "exec",
                    command = is_runnable and ("gtk-launch -- " .. did) or nil,
                    command_argv = is_runnable and { "gtk-launch", "--", did } or nil,
                    user_created = true,
                }
                local ov = overrides[action_id]
                if ov == false or ov == "" or ov == "none" then
                    item.key = nil
                    item.display_key = "None (Unbound)"
                    item.unbound = true
                    item.user_overridden = true
                elseif type(ov) == "string" then
                    local norm = M.normalize_key(ov)
                    item.key = norm
                    item.display_key = M.format_friendly_key(norm)
                    item.unbound = false
                    item.user_overridden = true
                else
                    -- Default unassigned application action
                    item.key = nil
                    item.display_key = "None (Unbound)"
                    item.unbound = true
                end
                table.insert(effective.bindings, item)
            end
        end
    end

    -- Process any remaining application-specific overrides (e.g. "app:foo.desktop") for backwards compatibility
    for action_id, ov in pairs(overrides) do
        if not known_ids[action_id] then
            local app_desktop = action_id:match("^app:([a-zA-Z0-9][%w%-%._]*%.desktop)$")
            if app_desktop then
                known_ids[action_id] = true
                local app_info = app_reg.find_application(app_desktop)
                local app_name = (app_info and app_info.name) or app_desktop:gsub("%.desktop$", "")
                local app_icon = (app_info and app_info.icon) or ""
                local is_runnable = (app_info ~= nil)
                local desc = app_name
                if not is_runnable then
                    desc = desc .. " (unavailable)"
                end
                local item = {
                    id = action_id,
                    priority = 100,
                    editable = true,
                    runnable = is_runnable,
                    category = "Applications & Launchers",
                    desktop_id = app_desktop,
                    description = desc,
                    icon = app_icon,
                    action_type = "exec",
                    command = is_runnable and ("gtk-launch -- " .. app_desktop) or nil,
                    command_argv = is_runnable and { "gtk-launch", "--", app_desktop } or nil,
                    user_overridden = true,
                    user_created = true,
                }
                if ov == false or ov == "" or ov == "none" then
                    item.key = nil
                    item.display_key = "None (Unbound)"
                    item.unbound = true
                elseif type(ov) == "string" then
                    local norm = M.normalize_key(ov)
                    item.key = norm
                    item.display_key = M.format_friendly_key(norm)
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

    -- 1. Verify action_id exists in manifest, user_actions, or is a valid desktop application
    local target_item = nil
    for _, item in ipairs(manifest.bindings or {}) do
        if item.id == action_id or (item.id == "keybindings" and action_id == "hotkeys") or (item.id == "hotkeys" and action_id == "keybindings") then
            target_item = item
            action_id = item.id
            break
        end
    end
    if not target_item then
        local app_desktop = action_id:match("^app:([a-zA-Z0-9][%w%-%._]*%.desktop)$")
        if app_desktop then
            local app_info = app_reg.find_application(app_desktop)
            if app_info then
                target_item = {
                    id = action_id,
                    priority = 100,
                    editable = true,
                    runnable = true,
                    category = "Applications & Launchers",
                    desktop_id = app_desktop,
                    description = "Launch " .. (app_info.name or app_desktop),
                    action_type = "exec",
                    command = "gtk-launch -- " .. app_desktop,
                    command_argv = { "gtk-launch", "--", app_desktop },
                }
                -- Also ensure user action is recorded
                M.add_user_application_action(app_desktop, nil, nil, function() return true end)
            else
                return false, "Desktop application not found: " .. app_desktop
            end
        else
            return false, "Action ID not found in manifest: " .. tostring(action_id)
        end
    end

    -- 2. Verify action is editable
    if not target_item.editable or target_item.immutable then
        local reason = "This action is not editable as an individual keyboard shortcut."
        if target_item.immutable then
            reason = "This shortcut is an immutable core system binding and cannot be modified."
        elseif target_item.generator then
            reason = "Generated aggregate workspace bindings cannot be edited as a single shortcut."
        elseif target_item.action_type == "gesture" then
            reason = "Hardware touchpad gestures cannot be edited as keyboard shortcuts."
        elseif target_item.mouse then
            reason = "Mouse button bindings cannot be edited through the keyboard hotkey manager."
        end
        if target_item.immutable then
            return false, string.format("Action '%s' is immutable: %s", action_id, reason)
        else
            return false, string.format("Action '%s' is not editable: %s", action_id, reason)
        end
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
    if not desktop_id or type(desktop_id) ~= "string" or not desktop_id:match("^[a-zA-Z0-9][%w%-%._]*%.desktop$") then
        return false, "Invalid desktop ID: must start with alphanumeric character and end with .desktop"
    end

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

    -- Check direct aliases for role actions
    if action_id == "terminal" or action_id == "terminal.default" then
        local canon, info = M.resolve_role_default("terminal")
        if not canon or type(info) ~= "table" or not info.command_argv then
            return nil, "Application for role 'terminal' is not available"
        end
        return info.command_argv
    elseif action_id == "file_manager" or action_id == "files.default" or action_id == "files" or action_id == "explorer" then
        local canon, info = M.resolve_role_default("file-manager")
        if not canon or type(info) ~= "table" or not info.command_argv then
            return nil, "Application for role 'file-manager' is not available"
        end
        return info.command_argv
    elseif action_id == "browser" or action_id == "browser.default" then
        local canon, info = M.resolve_role_default("browser")
        if not canon or type(info) ~= "table" or not info.command_argv then
            return nil, "Application for role 'browser' is not available"
        end
        return info.command_argv
    end

    -- Check specific app shortcuts (e.g. files.nautilus, terminal.kitty, browser.firefox)
    local role_prefix, specific_app = tostring(action_id):match("^(%w+)%.([%w%-_]+)$")
    if role_prefix and specific_app then
        local app_info = app_reg.find_application(specific_app)
        if app_info and app_info.command_argv then
            return app_info.command_argv
        end
        return nil, "Application not found or not runnable: " .. tostring(specific_app)
    end

    for _, item in ipairs(manifest.bindings or {}) do
        if item.id == action_id or (item.id == "keybindings" and action_id == "hotkeys") or (item.id == "hotkeys" and action_id == "keybindings") then
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

    local app_desktop = tostring(action_id):match("^app:([a-zA-Z0-9][%w%-%._]*%.desktop)$")
    if app_desktop then
        local app_info = app_reg.find_application(app_desktop)
        if not app_info then
            return nil, "Desktop application not found in Application Registry: " .. app_desktop
        end
        return { "gtk-launch", "--", app_desktop }
    end
    return nil, "Action ID not found in manifest: " .. tostring(action_id)
end

-- Serialize effective bindings into structured JSON consumed by modern UIs (e.g. Aurelia Quickshell)
function M.serialize_bindings_json(effective)
    effective = effective or M.resolve_bindings()
    local json_parts = {}
    table.insert(json_parts, "[\n")
    local count = #(effective.bindings or {})
    for i, b in ipairs(effective.bindings or {}) do
        local is_unbound = (b.unbound == true or b.key == nil or b.key == false or b.key == "")
        local fields = {
            string.format('    "id": %q', b.id or ""),
            string.format('    "display_key": %q', b.display_key or (is_unbound and "None (Unbound)" or b.key)),
            string.format('    "key": %s', b.key and string.format('%q', b.key) or "null"),
            string.format('    "description": %q', b.description or ""),
            string.format('    "category": %q', b.category or ""),
            string.format('    "runnable": %s', b.runnable == true and "true" or "false"),
            string.format('    "editable": %s', b.editable ~= false and "true" or "false"),
            string.format('    "priority": %d', b.priority or 999),
            string.format('    "unbound": %s', is_unbound and "true" or "false")
        }
        if b.desktop_id then
            table.insert(fields, string.format('    "desktop_id": %q', b.desktop_id))
        end
        if b.icon and b.icon ~= "" then
            table.insert(fields, string.format('    "icon": %q', b.icon))
        end
        local item_str = "  {\n" .. table.concat(fields, ",\n") .. "\n  }"
        if i < count then
            item_str = item_str .. ","
        end
        table.insert(json_parts, item_str .. "\n")
    end
    table.insert(json_parts, "]\n")
    return table.concat(json_parts)
end

return M
