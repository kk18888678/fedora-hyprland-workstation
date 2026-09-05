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

-- Media and hardware keys intentionally supported without requiring Super/Ctrl/Alt
local MEDIA_KEYS = {
    ["PRINT"] = true,
    ["PRINTSCREEN"] = true,
    ["XF86AUDIOMUTE"] = true,
    ["XF86AUDIOLOWERVOLUME"] = true,
    ["XF86AUDIOEFFECTS"] = true,
    ["XF86AUDIOMICMUTE"] = true,
    ["XF86AUDIOPREV"] = true,
    ["XF86AUDIONEXT"] = true,
    ["XF86AUDIOPAUSE"] = true,
    ["XF86AUDIOPLAY"] = true,
    ["XF86AUDIOSTOP"] = true,
    ["XF86AUDIORAISEVOLUME"] = true,
    ["XF86MONBRIGHTNESSUP"] = true,
    ["XF86MONBRIGHTNESSDOWN"] = true,
    ["XF86SEARCH"] = true,
    ["XF86HOMEPAGE"] = true,
    ["XF86CALCULATOR"] = true,
    ["XF86MAIL"] = true,
    ["XF86SLEEP"] = true,
    ["XF86WAKEUP"] = true,
}

-- Centralized workstation shortcut policy validation:
-- Returns: valid (bool), invalid_reason (string or nil), normalized_shortcut (string or nil)
function M.validate_shortcut_policy(k)
    if not k or type(k) ~= "string" or k:match("^%s*$") then
        return false, "malformed-combination", nil
    end
    -- Reject shell metacharacters and control characters
    if k:find("[;&|`$><\"'\\]") or k:find("[%c]") then
        return false, "malformed-combination", nil
    end

    local has_super = false
    local has_ctrl = false
    local has_alt = false
    local has_shift = false
    local main_keys = {}

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
                table.insert(main_keys, upper)
            end
        end
    end

    -- Standalone modifier keys alone
    if #main_keys == 0 then
        return false, "reserved-capture-control", nil
    end

    -- Multiple non-modifier keys (e.g. SUPER + A + B)
    if #main_keys > 1 then
        return false, "malformed-combination", nil
    end

    local key = main_keys[1]

    -- Reserved capture control keys: bare ESC / ESCAPE alone
    if (key == "ESC" or key == "ESCAPE") and not has_super and not has_ctrl and not has_alt then
        return false, "reserved-capture-control", nil
    end

    -- Function keys (F1 .. F24) are allowed alone or with modifiers
    local f_num = key:match("^F(%d+)$")
    if f_num then
        local fn = tonumber(f_num)
        if fn and fn >= 1 and fn <= 24 then
            local norm = M.normalize_key(k)
            return true, nil, norm
        end
    end

    -- Media / hardware keys are allowed alone or with modifiers
    if MEDIA_KEYS[key] then
        local norm = M.normalize_key(k)
        return true, nil, norm
    end

    -- For ordinary global workstation actions (printable alphanumeric, punctuation,
    -- navigation/editing keys like Return, Tab, Backspace, Delete, Arrows, Space):
    -- MUST have at least one global workstation modifier: SUPER, CTRL, or ALT.
    -- SHIFT alone is NOT sufficient.
    local has_global_modifier = (has_super or has_ctrl or has_alt)
    if not has_global_modifier then
        return false, "printable-key-requires-global-modifier", nil
    end

    local norm = M.normalize_key(k)
    if not norm or #norm == 0 then
        return false, "malformed-combination", nil
    end

    return true, nil, norm
end

-- Validate key syntax and workstation policy
function M.validate_key(k)
    local ok, reason, norm = M.validate_shortcut_policy(k)
    if not ok then
        if reason == "malformed-combination" then
            return false, "Key combination is invalid or dangerous: " .. tostring(reason)
        end
        return false, reason
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

-- Expand declarative aggregate generators into concrete individual actions.
-- Must occur BEFORE effective bindings resolution, overrides validation, or registration.
function M.expand_manifest_bindings(manifest)
    if not manifest then return nil end
    local expanded = {}
    local mainMod = manifest.mainMod or "SUPER"
    local mainMod_friendly = FRIENDLY_NAMES[mainMod] or "Super"

    for _, orig in ipairs(manifest.bindings or {}) do
        if orig.generator == "workspaces_1_10" then
            for i = 1, 9 do
                local item = {
                    id = "workspace_" .. i,
                    priority = 200 + i,
                    editable = true,
                    category = orig.category or "Workspaces",
                    key = mainMod .. " + " .. i,
                    display_key = mainMod_friendly .. " + " .. i,
                    description = "Workspace " .. i,
                    action_type = "focus_workspace",
                    workspace = i,
                    runnable = false,
                }
                table.insert(expanded, item)
            end
            local item10 = {
                id = "workspace_10",
                priority = 210,
                editable = true,
                category = orig.category or "Workspaces",
                key = mainMod .. " + 0",
                display_key = mainMod_friendly .. " + 0",
                description = "Workspace 10",
                action_type = "focus_workspace",
                workspace = 10,
                runnable = false,
            }
            table.insert(expanded, item10)
        elseif orig.generator == "workspaces_move_1_10" then
            for i = 1, 9 do
                local item = {
                    id = "workspace_move_" .. i,
                    priority = 210 + i,
                    editable = true,
                    category = orig.category or "Workspaces",
                    key = mainMod .. " + SHIFT + " .. i,
                    display_key = mainMod_friendly .. " + Shift + " .. i,
                    description = "Move to Workspace " .. i,
                    action_type = "move_to_workspace",
                    workspace = i,
                    runnable = false,
                }
                table.insert(expanded, item)
            end
            local item10 = {
                id = "workspace_move_10",
                priority = 220,
                editable = true,
                category = orig.category or "Workspaces",
                key = mainMod .. " + SHIFT + 0",
                display_key = mainMod_friendly .. " + Shift + 0",
                description = "Move to Workspace 10",
                action_type = "move_to_workspace",
                workspace = 10,
                runnable = false,
            }
            table.insert(expanded, item10)
        else
            table.insert(expanded, orig)
        end
    end

    local expanded_manifest = {}
    for k, v in pairs(manifest) do
        expanded_manifest[k] = v
    end
    expanded_manifest.bindings = expanded
    return expanded_manifest
end

-- Strict, fail-closed JSON decoder for keybindings overrides schema:
-- {
--   "<stable-action-id>": "<normalized-key>",
--   "<stable-action-id>": false
-- }
function M.parse_strict_overrides(str, manifest)
    if not str or str:match("^%s*$") then return {} end

    local valid_actions = {}
    if manifest then
        manifest = M.expand_manifest_bindings(manifest)
        if manifest.bindings then
            for _, b in ipairs(manifest.bindings) do
                if b.id and b.editable ~= false then
                    valid_actions[b.id] = b
                end
            end
        end
    end
    -- Also include user-created actions from user_actions.json
    local user_acts = M.load_user_actions()
    if user_acts and user_acts.actions then
        for _, act in ipairs(user_acts.actions) do
            if type(act) == "table" then
                if act.type == "application" and act.desktop_id then
                    valid_actions["app:" .. act.desktop_id] = true
                elseif act.type == "executable" and act.id then
                    valid_actions[act.id] = true
                end
            elseif type(act) == "string" then
                valid_actions["app:" .. act] = true
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
        local is_custom_action = key:match("^exec:[a-zA-Z0-9_.:-]+$") or key:match("^custom:[a-zA-Z0-9_.:-]+$")
        if manifest and not valid_actions[key] and not (key == "hotkeys" and valid_actions["keybindings"]) and not is_app_action and not is_custom_action then
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

-- POSIX shell single-quote escaper
local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Check if a filepath exists, is a regular file, and is executable
local function check_executable_file(path)
    if not path or type(path) ~= "string" or #path == 0 or #path > 1024 then
        return false, "Invalid path: must be non-empty and under 1024 characters"
    end
    if path:find("[%c]") or path:find("[;&|`$><\"'\\]") or path:find("%.%./") or path:find("/%.%.$") then
        return false, "Path contains dangerous characters or path traversal"
    end
    local resolved = path
    if resolved:sub(1, 2) == "~/" then
        local home = os.getenv("HOME") or ""
        resolved = home .. resolved:sub(2)
    elseif resolved:sub(1, 1) ~= "/" then
        return false, "Path must be an absolute path or start with ~/"
    end
    local d_ret = os.execute("test -d " .. sh_quote(resolved))
    if d_ret == 0 or d_ret == true then
        return false, "Path is a directory, not an executable file: " .. path
    end
    local e_ret = os.execute("test -e " .. sh_quote(resolved))
    if e_ret ~= 0 and e_ret ~= true then
        return false, "File does not exist: " .. path
    end
    local r_ret = os.execute("test -r " .. sh_quote(resolved))
    if r_ret ~= 0 and r_ret ~= true then
        return false, "File is not readable (permission denied): " .. path
    end
    local x_ret = os.execute("test -x " .. sh_quote(resolved))
    if x_ret ~= 0 and x_ret ~= true then
        return false, "File is not executable (chmod +x required): " .. path
    end
    local f_ret = os.execute("test -f " .. sh_quote(resolved))
    if f_ret ~= 0 and f_ret ~= true then
        return false, "File is not a regular file: " .. path
    end
    return true, resolved
end

-- Strict, fail-closed JSON and schema decoder for user_actions.json (supports v1 and v2):
-- Schema v1:
-- {
--   "version": 1,
--   "actions": [ "foo.desktop", ... ]
-- }
-- Schema v2:
-- {
--   "version": 2,
--   "actions": [
--     { "type": "application", "desktop_id": "foo.desktop" },
--     { "type": "executable", "id": "exec:my-script", "name": "Script", "executable_path": "/path/to/bin", "argv": [...] }
--   ]
-- }
function M.parse_strict_user_actions(str)
    if not str or type(str) ~= "string" or str:match("^%s*$") then
        return { version = 2, actions = {} }
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

    local function parse_string_array()
        if pos > len or str:sub(pos, pos) ~= "[" then
            return nil, "Expected array starting with ["
        end
        pos = pos + 1
        local arr = {}
        skip_ws()
        if pos <= len and str:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end
        while pos <= len do
            skip_ws()
            local s, err = parse_string()
            if not s then return nil, err end
            table.insert(arr, s)
            skip_ws()
            if pos <= len and str:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            elseif pos <= len and str:sub(pos, pos) == "," then
                pos = pos + 1
            else
                return nil, "Expected , or ] in string array at byte " .. pos
            end
        end
        return nil, "Unterminated string array"
    end

    local function parse_action_object()
        if pos > len or str:sub(pos, pos) ~= "{" then
            return nil, "Expected object starting with {"
        end
        pos = pos + 1
        local obj = {}
        local seen = {}
        skip_ws()
        if pos <= len and str:sub(pos, pos) == "}" then
            pos = pos + 1
            return nil, "Empty action object not allowed"
        end
        while pos <= len do
            skip_ws()
            local k, k_err = parse_string()
            if not k then return nil, k_err end
            if seen[k] then return nil, "Duplicate key in action object: " .. k end
            seen[k] = true
            skip_ws()
            if pos > len or str:sub(pos, pos) ~= ":" then
                return nil, "Expected : after key in action object"
            end
            pos = pos + 1
            skip_ws()
            if k == "argv" then
                local a_arr, a_err = parse_string_array()
                if not a_arr then return nil, a_err end
                obj[k] = a_arr
            else
                local val, v_err = parse_string()
                if not val then return nil, v_err end
                obj[k] = val
            end
            skip_ws()
            if pos <= len and str:sub(pos, pos) == "}" then
                pos = pos + 1
                break
            elseif pos <= len and str:sub(pos, pos) == "," then
                pos = pos + 1
            else
                return nil, "Expected , or } in action object at byte " .. pos
            end
        end

        local act_type = obj.type
        if act_type ~= "application" and act_type ~= "executable" then
            return nil, "Invalid or missing action type: " .. tostring(act_type)
        end

        if act_type == "application" then
            if not obj.desktop_id then
                return nil, "Missing desktop_id in application action"
            end
            local did = obj.desktop_id
            if not did:match("^[a-zA-Z0-9][%w%-%._]*%.desktop$") or did:find("%.%./") or did:sub(1, 1) == "-" then
                return nil, "Invalid desktop ID in application action: " .. tostring(did)
            end
            for key in pairs(obj) do
                if key ~= "type" and key ~= "desktop_id" and key ~= "description" and key ~= "icon" then
                    return nil, "Unknown field in application action: " .. key
                end
            end
            return {
                type = "application",
                desktop_id = did,
                description = obj.description,
                icon = obj.icon,
            }
        elseif act_type == "executable" then
            if not obj.id or not obj.id:match("^[a-zA-Z0-9_.:-]+$") or #obj.id > 128 then
                return nil, "Invalid or missing id in executable action"
            end
            if not obj.name or #obj.name == 0 or #obj.name > 128 or obj.name:find("[%c]") then
                return nil, "Invalid or missing name in executable action"
            end
            local p = obj.executable_path
            if not p or #p == 0 or #p > 1024 or p:find("[%c]") or p:find("%.%./") or p:find("/%.%.$") or p:find("[;&|`$><\"'\\]") then
                return nil, "Invalid or dangerous executable_path in executable action: " .. tostring(p)
            end
            if p:sub(1, 1) ~= "/" and p:sub(1, 2) ~= "~/" then
                return nil, "executable_path must be absolute or start with ~/: " .. tostring(p)
            end
            if not obj.argv or type(obj.argv) ~= "table" or #obj.argv == 0 or #obj.argv > 32 then
                return nil, "Invalid or missing argv in executable action (must be 1-32 elements)"
            end
            for _, arg in ipairs(obj.argv) do
                if type(arg) ~= "string" or #arg > 1024 or arg:find("[%c]") then
                    return nil, "Invalid element in argv"
                end
            end
            for key in pairs(obj) do
                if key ~= "type" and key ~= "id" and key ~= "name" and key ~= "executable_path" and key ~= "argv" and key ~= "description" and key ~= "icon" then
                    return nil, "Unknown field in executable action: " .. key
                end
            end
            return {
                type = "executable",
                id = obj.id,
                name = obj.name,
                executable_path = obj.executable_path,
                argv = obj.argv,
                description = obj.description or obj.name,
                icon = obj.icon or "utilities-terminal",
            }
        end
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
            if v_num ~= 1 and v_num ~= 2 then
                return nil, "Unsupported user_actions schema version: " .. tostring(v_num) .. " (expected 1 or 2)"
            end
            version = v_num
        elseif key == "actions" then
            if pos > len or str:sub(pos, pos) ~= "[" then
                return nil, "Invalid actions field: expected array beginning with [ at byte " .. pos
            end
            pos = pos + 1
            actions = {}
            local seen_ids = {}

            skip_ws()
            if pos <= len and str:sub(pos, pos) == "]" then
                pos = pos + 1
            else
                while pos <= len do
                    skip_ws()
                    local next_c = str:sub(pos, pos)
                    local act_entry = nil
                    if next_c == "\"" then
                        local act_str, a_err = parse_string()
                        if not act_str then return nil, a_err end
                        if not act_str:match("^[a-zA-Z0-9][%w%-%._]*%.desktop$") or act_str:find("%.%./") or act_str:sub(1, 1) == "-" then
                            return nil, "Invalid desktop ID in actions array: " .. tostring(act_str)
                        end
                        act_entry = { type = "application", desktop_id = act_str }
                    elseif next_c == "{" then
                        local act_obj, o_err = parse_action_object()
                        if not act_obj then return nil, o_err end
                        act_entry = act_obj
                    else
                        return nil, "Expected string or object in actions array at byte " .. pos
                    end

                    local act_id = (act_entry.type == "application") and act_entry.desktop_id or act_entry.id
                    if not seen_ids[act_id] then
                        seen_ids[act_id] = true
                        table.insert(actions, act_entry)
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
        return { version = 2, actions = {} }
    end
    -- Bounded read to 64KB
    local content = f:read(65536)
    f:close()

    if not content or content:match("^%s*$") then
        return { version = 2, actions = {} }
    end

    return M.parse_strict_user_actions(content)
end

-- Serialize user-created actions
function M.encode_user_actions(tbl)
    local actions = (tbl and tbl.actions) or {}
    local sorted = {}
    for _, act in ipairs(actions) do
        table.insert(sorted, act)
    end
    table.sort(sorted, function(a, b)
        local ida = type(a) == "table" and (a.type == "executable" and a.id or ("app:" .. (a.desktop_id or ""))) or ("app:" .. tostring(a))
        local idb = type(b) == "table" and (b.type == "executable" and b.id or ("app:" .. (b.desktop_id or ""))) or ("app:" .. tostring(b))
        return ida < idb
    end)

    local lines = {}
    for _, act in ipairs(sorted) do
        if type(act) == "string" then
            table.insert(lines, string.format('    {\n      "type": "application",\n      "desktop_id": %q\n    }', act))
        elseif type(act) == "table" then
            if act.type == "application" then
                table.insert(lines, string.format('    {\n      "type": "application",\n      "desktop_id": %q\n    }', act.desktop_id))
            elseif act.type == "executable" then
                local argv_lines = {}
                for _, arg in ipairs(act.argv or { act.executable_path }) do
                    table.insert(argv_lines, string.format('        %q', arg))
                end
                local exec_str = string.format('    {\n      "type": "executable",\n      "id": %q,\n      "name": %q,\n      "executable_path": %q,\n      "argv": [\n%s\n      ]\n    }',
                    act.id, act.name, act.executable_path, table.concat(argv_lines, ",\n"))
                table.insert(lines, exec_str)
            end
        end
    end
    return "{\n  \"version\": 2,\n  \"actions\": [\n" .. table.concat(lines, ",\n") .. "\n  ]\n}\n"
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
    for _, act in ipairs(current.actions) do
        local did = (type(act) == "table") and act.desktop_id or act
        if did == desktop_id then
            exists = true
            break
        end
    end

    if not exists then
        table.insert(current.actions, { type = "application", desktop_id = desktop_id })
        local ok_save, save_err = M.save_user_actions(current, user_actions_path)
        if not ok_save then
            return false, "Failed to save user actions: " .. tostring(save_err)
        end
    end

    reload_fn()
    return true, "Application action added: " .. (app_info.name or desktop_id)
end

-- Add a user-created executable or script action
function M.add_user_executable_action(action_def, user_actions_path, overrides_path, reload_fn)
    if not action_def or type(action_def) ~= "table" then
        return false, "action_def must be a table"
    end
    local id = action_def.id
    if not id or type(id) ~= "string" or not id:match("^exec:[a-zA-Z0-9_.:-]+$") or #id > 128 then
        return false, "Invalid action ID: must match ^exec:[a-zA-Z0-9_.:-]+$"
    end
    local name = action_def.name
    if not name or type(name) ~= "string" or #name == 0 or #name > 128 or name:find("[%c]") then
        return false, "Invalid name: must be 1-128 characters without control characters"
    end
    local path = action_def.executable_path or action_def.path
    local ok_file, res_or_err = check_executable_file(path)
    if not ok_file then
        return false, res_or_err
    end

    local argv = action_def.argv
    if not argv or type(argv) ~= "table" or #argv == 0 then
        argv = { path }
    else
        if argv[1] ~= path then
            table.insert(argv, 1, path)
        end
        if #argv > 32 then
            return false, "argv exceeds maximum length of 32 arguments"
        end
        for _, arg in ipairs(argv) do
            if type(arg) ~= "string" or #arg > 1024 or arg:find("[%c]") then
                return false, "Invalid argument in argv"
            end
        end
    end

    user_actions_path = user_actions_path or M.get_user_actions_path()
    reload_fn = reload_fn or M.reload_session

    local current, err = M.load_user_actions(user_actions_path)
    if not current then
        return false, "Failed to load user actions: " .. tostring(err)
    end

    for _, act in ipairs(current.actions) do
        local existing_id = (type(act) == "table") and act.id or nil
        if existing_id == id then
            return false, "Action ID already exists: " .. id
        end
    end

    local new_entry = {
        type = "executable",
        id = id,
        name = name,
        executable_path = path,
        argv = argv,
    }
    table.insert(current.actions, new_entry)

    local ok_save, save_err = M.save_user_actions(current, user_actions_path)
    if not ok_save then
        return false, "Failed to save user actions: " .. tostring(save_err)
    end

    reload_fn()
    return true, "Executable action added: " .. name
end

-- Remove a user-created action (application or executable)
function M.remove_user_action(action_id, user_actions_path, overrides_path, reload_fn)
    if not action_id or type(action_id) ~= "string" then
        return false, "Invalid action ID"
    end

    user_actions_path = user_actions_path or M.get_user_actions_path()
    overrides_path = overrides_path or M.get_overrides_path()
    reload_fn = reload_fn or M.reload_session

    local current, err = M.load_user_actions(user_actions_path)
    if not current then
        return false, "Failed to load user actions: " .. tostring(err)
    end

    local target_desktop_id = nil
    if action_id:match("^app:") then
        target_desktop_id = action_id:sub(5)
    elseif action_id:match("%.desktop$") then
        target_desktop_id = action_id
    end

    local new_actions = {}
    local found = false
    for _, act in ipairs(current.actions) do
        local match = false
        if type(act) == "table" then
            if act.type == "executable" and act.id == action_id then
                match = true
            elseif act.type == "application" and (act.desktop_id == target_desktop_id or ("app:" .. act.desktop_id) == action_id) then
                match = true
            end
        elseif type(act) == "string" then
            if act == target_desktop_id or ("app:" .. act) == action_id then
                match = true
            end
        end

        if match then
            found = true
        else
            table.insert(new_actions, act)
        end
    end

    if not found then
        return false, "Action not found in user actions: " .. action_id
    end

    current.actions = new_actions
    local ok_save, save_err = M.save_user_actions(current, user_actions_path)
    if not ok_save then
        return false, "Failed to save user actions: " .. tostring(save_err)
    end

    -- Also remove override for action_id if present
    local overrides = M.load_overrides(overrides_path)
    if overrides then
        local changed = false
        if overrides[action_id] ~= nil then
            overrides[action_id] = nil
            changed = true
        end
        if target_desktop_id and overrides["app:" .. target_desktop_id] ~= nil then
            overrides["app:" .. target_desktop_id] = nil
            changed = true
        end
        if changed then
            M.save_overrides(overrides, overrides_path)
        end
    end

    reload_fn()
    return true, "Action removed: " .. action_id
end

-- Backward compatibility alias
function M.remove_user_application_action(desktop_id, user_actions_path, overrides_path, reload_fn)
    return M.remove_user_action("app:" .. desktop_id, user_actions_path, overrides_path, reload_fn)
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
    manifest = M.expand_manifest_bindings(manifest)
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
            -- Derive keyboard_bindable and trigger_type
            if item.keyboard_bindable ~= nil then
                item.keyboard_bindable = (item.keyboard_bindable == true)
            elseif item.trigger_type == "gesture" or item.action_type == "gesture" or item.mouse == true or item.action_type == "mouse_drag" or item.action_type == "mouse_resize" then
                item.keyboard_bindable = false
            else
                item.keyboard_bindable = true
            end

            if not item.trigger_type then
                if item.action_type == "gesture" then
                    item.trigger_type = "gesture"
                elseif item.mouse == true or item.action_type == "mouse_drag" or item.action_type == "mouse_resize" then
                    item.trigger_type = "mouse"
                else
                    item.trigger_type = "keyboard"
                end
            end

            local ov = overrides[action_id]
            if ov == nil and action_id == "keybindings" then
                ov = overrides["hotkeys"]
            end
            if not item.keyboard_bindable then
                item.unbound = false
            elseif ov ~= nil then
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

    -- Process user-created actions from user_actions.json
    local user_actions_data = M.load_user_actions()
    if user_actions_data and user_actions_data.actions then
        for _, act in ipairs(user_actions_data.actions) do
            if type(act) == "table" and act.type == "executable" then
                local action_id = act.id
                if not known_ids[action_id] then
                    known_ids[action_id] = true
                    local ok_exec = false
                    local resolved_path = act.executable_path
                    if resolved_path:sub(1, 2) == "~/" then
                        local home = os.getenv("HOME") or ""
                        resolved_path = home .. resolved_path:sub(2)
                    end
                    local f = io.open(resolved_path, "r")
                    if f then
                        f:close()
                        local cmd = "test -f " .. sh_quote(resolved_path) .. " && test -x " .. sh_quote(resolved_path)
                        local ret = os.execute(cmd)
                        if ret == 0 or ret == true then
                            ok_exec = true
                        end
                    end
                    local desc = act.name or action_id
                    if not ok_exec then
                        desc = desc .. " (unavailable)"
                    end
                    local argv = act.argv or { act.executable_path }
                    local cmd_parts = {}
                    for _, a in ipairs(argv) do
                        table.insert(cmd_parts, sh_quote(a))
                    end
                    local cmd_str = table.concat(cmd_parts, " ")
                    local item = {
                        id = action_id,
                        priority = 150,
                        editable = true,
                        runnable = ok_exec,
                        category = "User Executables & Scripts",
                        description = desc,
                        icon = act.icon or "utilities-terminal",
                        action_type = "exec",
                        command = ok_exec and cmd_str or nil,
                        command_argv = ok_exec and argv or nil,
                        executable_path = act.executable_path,
                        user_created = true,
                        keyboard_bindable = true,
                        trigger_type = "keyboard",
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
                        item.key = nil
                        item.display_key = "None (Unbound)"
                        item.unbound = true
                    end
                    table.insert(effective.bindings, item)
                end
            elseif (type(act) == "table" and act.type == "application") or type(act) == "string" then
                local did = (type(act) == "table") and act.desktop_id or act
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
                        command = is_runnable and ((app_info and app_info.command) or ("gtk-launch -- " .. did)) or nil,
                        command_argv = is_runnable and ((app_info and app_info.command_argv) or { "gtk-launch", "--", did }) or nil,
                        user_created = true,
                        keyboard_bindable = true,
                        trigger_type = "keyboard",
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
                        item.key = nil
                        item.display_key = "None (Unbound)"
                        item.unbound = true
                    end
                    table.insert(effective.bindings, item)
                end
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
                    command = is_runnable and ((app_info and app_info.command) or ("gtk-launch -- " .. app_desktop)) or nil,
                    command_argv = is_runnable and ((app_info and app_info.command_argv) or { "gtk-launch", "--", app_desktop }) or nil,
                    user_overridden = true,
                    user_created = true,
                    keyboard_bindable = true,
                    trigger_type = "keyboard",
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
function M.set_action_binding(action_id, new_key_input, manifest_path, overrides_path, reload_fn, force)
    overrides_path = overrides_path or M.get_overrides_path()
    local manifest
    if manifest_path then
        manifest = dofile(manifest_path)
    else
        manifest = require("keybindings_manifest")
    end
    manifest = M.expand_manifest_bindings(manifest)

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
        -- Check user_actions.json
        local user_acts = M.load_user_actions()
        if user_acts and user_acts.actions then
            for _, act in ipairs(user_acts.actions) do
                if type(act) == "table" and act.type == "executable" and act.id == action_id then
                    target_item = {
                        id = act.id,
                        priority = 150,
                        editable = true,
                        runnable = true,
                        category = "User Executables & Scripts",
                        description = act.name,
                        action_type = "exec",
                        user_created = true,
                    }
                    break
                elseif (type(act) == "table" and act.type == "application" and ("app:" .. act.desktop_id) == action_id) or (type(act) == "string" and ("app:" .. act) == action_id) then
                    local did = (type(act) == "table") and act.desktop_id or act
                    target_item = {
                        id = action_id,
                        priority = 100,
                        editable = true,
                        runnable = true,
                        category = "Applications & Launchers",
                        desktop_id = did,
                        description = did,
                        action_type = "exec",
                        user_created = true,
                    }
                    break
                end
            end
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
            return false, "Action ID not found in manifest or user actions: " .. tostring(action_id)
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
            if force then
                if not conflict.editable or conflict.immutable then
                    return false, string.format("Conflict with immutable system binding '%s' (%s). Cannot reassign.", conflict.id, conflict.description or conflict.id)
                end
                candidate[conflict.id] = false
            else
                local conflict_desc = conflict.description or conflict.id or "another action"
                return false, string.format("Conflict: '%s' is already assigned to %s (%s). To reassign, confirm reassignment or pass --force.",
                    norm_key, conflict_desc, conflict.id or "unnamed")
            end
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

    return M.set_action_binding(action_id, new_key_input, manifest_path, overrides_path, reload_fn, force)
end

-- Retrieve structured command_argv for a runnable action
function M.get_action_argv(action_id, manifest)
    manifest = manifest or require("keybindings_manifest")
    manifest = M.expand_manifest_bindings(manifest)

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
        if not app_info or not app_info.command_argv then
            return nil, "Desktop application not found in Application Registry: " .. app_desktop
        end
        return app_info.command_argv
    end

    -- Check user_actions.json for executable actions
    local user_acts = M.load_user_actions()
    if user_acts and user_acts.actions then
        for _, act in ipairs(user_acts.actions) do
            if type(act) == "table" and act.type == "executable" and act.id == action_id then
                local resolved_path = act.executable_path
                if resolved_path:sub(1, 2) == "~/" then
                    local home = os.getenv("HOME") or ""
                    resolved_path = home .. resolved_path:sub(2)
                end
                local f = io.open(resolved_path, "r")
                if f then
                    f:close()
                    local cmd = "test -f " .. sh_quote(resolved_path) .. " && test -x " .. sh_quote(resolved_path)
                    local ret = os.execute(cmd)
                    if ret == 0 or ret == true then
                        return act.argv or { act.executable_path }
                    end
                end
                return nil, "Executable action is not runnable or missing: " .. tostring(act.executable_path)
            end
        end
    end

    return nil, "Action ID not found in manifest or user actions: " .. tostring(action_id)
end

-- Serialize effective bindings into structured JSON consumed by modern UIs (e.g. Aurelia Quickshell)
function M.serialize_bindings_json(effective)
    effective = effective or M.resolve_bindings()
    local json_parts = {}
    table.insert(json_parts, "[\n")
    local count = #(effective.bindings or {})
    for i, b in ipairs(effective.bindings or {}) do
        local is_kb_bindable = (b.keyboard_bindable ~= false)
        local is_unbound = is_kb_bindable and (b.unbound == true or b.key == nil or b.key == false or b.key == "")
        local trig_type = b.trigger_type or (b.action_type == "gesture" and "gesture" or ((b.mouse == true or (b.action_type and b.action_type:find("^mouse_"))) and "mouse" or "keyboard"))
        local fields = {
            string.format('    "id": %q', b.id or ""),
            string.format('    "display_key": %q', b.display_key or (is_unbound and "None (Unbound)" or b.key)),
            string.format('    "key": %s', b.key and string.format('%q', b.key) or "null"),
            string.format('    "description": %q', b.description or ""),
            string.format('    "category": %q', b.category or ""),
            string.format('    "runnable": %s', b.runnable == true and "true" or "false"),
            string.format('    "editable": %s', b.editable ~= false and "true" or "false"),
            string.format('    "priority": %d', b.priority or 999),
            string.format('    "unbound": %s', is_unbound and "true" or "false"),
            string.format('    "keyboard_bindable": %s', is_kb_bindable and "true" or "false"),
            string.format('    "trigger_type": %q', trig_type)
        }
        if b.desktop_id then
            table.insert(fields, string.format('    "desktop_id": %q', b.desktop_id))
        end
        if b.icon and b.icon ~= "" then
            table.insert(fields, string.format('    "icon": %q', b.icon))
        end
        if b.user_created then
            table.insert(fields, '    "user_created": true')
        end
        if b.action_type then
            table.insert(fields, string.format('    "action_type": %q', b.action_type))
        end
        if b.executable_path then
            table.insert(fields, string.format('    "executable_path": %q', b.executable_path))
        end
        if b.command_argv and type(b.command_argv) == "table" then
            local argv_strs = {}
            for _, a in ipairs(b.command_argv) do
                table.insert(argv_strs, string.format('%q', a))
            end
            table.insert(fields, string.format('    "command_argv": [%s]', table.concat(argv_strs, ", ")))
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
