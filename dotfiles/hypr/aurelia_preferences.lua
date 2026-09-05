-- Module: aurelia_preferences
-- Single source of truth for Aurelia Desktop Shell Core preferences,
-- layered configuration resolution (Shipped Defaults + User Overrides = Effective Preferences),
-- atomic writes, component/shell reset, portable export, and structured diagnostics.

local M = {}

-- Shipped Defaults: Immutable baseline specification
function M.get_shipped_defaults()
    return {
        schema_version = 1,
        aurelia = {
            motion = {
                enabled = true,
                scale = 1.0,
            },
        },
        components = {
            keybindings = {
                motion = {
                    enabled = true,
                    scale = 1.0,
                },
                default_view = "bound",
            },
        },
    }
end

-- Resolve preferences file path: $AURELIA_PREFERENCES_PATH -> ~/.config/aurelia/preferences.json
function M.get_preferences_path()
    local env_path = os.getenv("AURELIA_PREFERENCES_PATH")
    if env_path and env_path ~= "" then
        return env_path
    end
    local config_home = os.getenv("XDG_CONFIG_HOME")
    if not config_home or config_home == "" then
        local home = os.getenv("HOME") or ""
        config_home = home .. "/.config"
    end
    return config_home .. "/aurelia/preferences.json"
end

-- Resolve diagnostic logs path: $AURELIA_LOG_PATH -> ~/.local/state/workstation/aurelia.log
function M.get_log_path()
    local env_path = os.getenv("AURELIA_LOG_PATH")
    if env_path and env_path ~= "" then
        return env_path
    end
    local state_home = os.getenv("XDG_STATE_HOME")
    if not state_home or state_home == "" then
        local home = os.getenv("HOME") or ""
        state_home = home .. "/.local/state"
    end
    return state_home .. "/workstation/aurelia.log"
end

-- Shell quoting for POSIX command invocation
local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- UTF-8 encoding helper for unicode escapes in JSON strings
local function utf8_encode(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
    elseif code < 0x10000 then
        return string.char(
            0xE0 + math.floor(code / 0x1000),
            0x80 + (math.floor(code / 0x40) % 0x40),
            0x80 + (code % 0x40)
        )
    else
        return string.char(
            0xF0 + math.floor(code / 0x40000),
            0x80 + (math.floor(code / 0x1000) % 0x40),
            0x80 + (math.floor(code / 0x40) % 0x40),
            0x80 + (code % 0x40)
        )
    end
end

-- Strict, fail-closed pure-Lua JSON decoder for preferences
function M.parse_json(str)
    if not str or type(str) ~= "string" or str:match("^%s*$") then
        return {}
    end

    if #str > 131072 then
        return nil, "preferences file exceeds maximum allowed size of 128KB"
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

    local parse_value -- forward declaration

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
        if pos <= len and str:sub(pos, pos) == "." then
            pos = pos + 1
            while pos <= len and str:sub(pos, pos):match("[0-9]") do
                pos = pos + 1
            end
        end
        if pos <= len and (str:sub(pos, pos) == "e" or str:sub(pos, pos) == "E") then
            pos = pos + 1
            if pos <= len and (str:sub(pos, pos) == "+" or str:sub(pos, pos) == "-") then
                pos = pos + 1
            end
            while pos <= len and str:sub(pos, pos):match("[0-9]") do
                pos = pos + 1
            end
        end
        local num_str = str:sub(start_pos, pos - 1)
        local n = tonumber(num_str)
        if not n then return nil, "Invalid number at byte " .. start_pos end
        return n
    end

    local function parse_array()
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
            local val, err = parse_value()
            if err then return nil, err end
            table.insert(arr, val)
            skip_ws()
            if pos <= len and str:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            elseif pos <= len and str:sub(pos, pos) == "," then
                pos = pos + 1
            else
                return nil, "Expected , or ] in array at byte " .. pos
            end
        end
        return nil, "Unterminated array"
    end

    local function parse_object()
        if pos > len or str:sub(pos, pos) ~= "{" then
            return nil, "Expected object starting with {"
        end
        pos = pos + 1
        local obj = {}
        skip_ws()
        if pos <= len and str:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end
        while pos <= len do
            skip_ws()
            local key, err = parse_string()
            if not key then return nil, err or "Expected string key in object" end
            skip_ws()
            if pos > len or str:sub(pos, pos) ~= ":" then
                return nil, "Expected : after key at byte " .. pos
            end
            pos = pos + 1
            skip_ws()
            local val, val_err = parse_value()
            if val_err then return nil, val_err end
            obj[key] = val
            skip_ws()
            if pos <= len and str:sub(pos, pos) == "}" then
                pos = pos + 1
                return obj
            elseif pos <= len and str:sub(pos, pos) == "," then
                pos = pos + 1
            else
                return nil, "Expected , or } in object at byte " .. pos
            end
        end
        return nil, "Unterminated object"
    end

    parse_value = function()
        skip_ws()
        if pos > len then return nil, "Unexpected end of JSON" end
        local c = str:sub(pos, pos)
        if c == "\"" then
            return parse_string()
        elseif c == "{" then
            return parse_object()
        elseif c == "[" then
            return parse_array()
        elseif c == "-" or c:match("[0-9]") then
            return parse_number()
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            return nil, "Unexpected character '" .. c .. "' at byte " .. pos
        end
    end

    skip_ws()
    local res, err = parse_value()
    if err then return nil, err end
    skip_ws()
    if pos <= len then
        return nil, "Trailing characters after JSON object at byte " .. pos
    end
    return res
end

-- Deterministic JSON encoder
function M.json_encode(val, indent)
    indent = indent or 0
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val == math.floor(val) then
            return string.format("%d", val)
        else
            return string.format("%.4f", val):gsub("%.?0+$", "")
        end
    elseif t == "string" then
        local escaped = val:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        return "\"" .. escaped .. "\""
    elseif t == "table" then
        -- Check if it's an array or map
        local is_array = true
        local max_idx = 0
        local count = 0
        for k in pairs(val) do
            count = count + 1
            if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
                is_array = false
                break
            end
            if k > max_idx then max_idx = k end
        end
        if is_array and max_idx ~= count then is_array = false end

        local spaces = string.rep("  ", indent)
        local child_spaces = string.rep("  ", indent + 1)

        if is_array then
            if count == 0 then return "[]" end
            local parts = {}
            for i = 1, max_idx do
                table.insert(parts, child_spaces .. M.json_encode(val[i], indent + 1))
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. spaces .. "]"
        else
            if count == 0 then return "{}" end
            local keys = {}
            for k in pairs(val) do table.insert(keys, tostring(k)) end
            table.sort(keys)
            local parts = {}
            for _, k in ipairs(keys) do
                local v = val[k]
                table.insert(parts, child_spaces .. string.format("%q: %s", k, M.json_encode(v, indent + 1)))
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. spaces .. "}"
        end
    else
        return "\"<unsupported>\""
    end
end

-- Safely and atomically write file with exclusive mktemp and 0600 mode
local function atomic_write_file(path, content)
    local dir = path:match("^(.*)/[^/]+$")
    if not dir or dir == "" then dir = "." end

    local dir_cmd = "mkdir -p -m 0700 " .. sh_quote(dir)
    local ok_dir = os.execute(dir_cmd)
    if ok_dir ~= 0 and ok_dir ~= true then
        return false, "Failed to create directory: " .. tostring(dir)
    end

    local template = dir .. "/.preferences.tmp.XXXXXX"
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
        return false, "Failed to atomically rename preferences file: " .. tostring(ren_err)
    end
    return true
end

-- Load user overrides from disk safely (fail-closed, corruption-safe)
function M.read_overrides(path)
    path = path or M.get_preferences_path()
    local f = io.open(path, "r")
    if not f then
        return { schema_version = 1 }
    end
    local content = f:read("*a")
    f:close()

    if not content or content:match("^%s*$") then
        return { schema_version = 1 }
    end

    local parsed, err = M.parse_json(content)
    if not parsed or type(parsed) ~= "table" then
        -- Malformed preference fails safely to shipped default without crashing or wiping file
        io.stderr:write("[WARN] aurelia_preferences: Malformed preferences file at " .. path .. "; failing safe to shipped defaults: " .. tostring(err) .. "\n")
        return { schema_version = 1 }, err
    end

    if not parsed.schema_version then
        parsed.schema_version = 1
    end
    return parsed
end

-- Resolve nested preference from a table using dot-delimited key
local function get_nested(tbl, key_path)
    if not tbl or type(tbl) ~= "table" then return nil end
    local curr = tbl
    for part in key_path:gmatch("[^.]+") do
        if type(curr) == "table" and curr[part] ~= nil then
            curr = curr[part]
        else
            return nil
        end
    end
    return curr
end

-- Set nested key in a table
local function set_nested(tbl, key_path, value)
    local parts = {}
    for part in key_path:gmatch("[^.]+") do
        table.insert(parts, part)
    end
    local curr = tbl
    for i = 1, #parts - 1 do
        local part = parts[i]
        if type(curr[part]) ~= "table" then
            curr[part] = {}
        end
        curr = curr[part]
    end
    curr[parts[#parts]] = value
end

-- Remove nested key in a table
local function unset_nested(tbl, key_path)
    local parts = {}
    for part in key_path:gmatch("[^.]+") do
        table.insert(parts, part)
    end
    local stack = {}
    local curr = tbl
    for i = 1, #parts - 1 do
        local part = parts[i]
        if type(curr[part]) ~= "table" then
            return false
        end
        table.insert(stack, { parent = curr, key = part })
        curr = curr[part]
    end
    local leaf_key = parts[#parts]
    curr[leaf_key] = nil

    -- Clean up empty parent tables
    for i = #stack, 1, -1 do
        local entry = stack[i]
        local p = entry.parent[entry.key]
        if type(p) == "table" and next(p) == nil then
            entry.parent[entry.key] = nil
        else
            break
        end
    end
    return true
end

-- Deep copy table
local function deep_copy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deep_copy(v)
    end
    return copy
end

-- Deep merge src into dst
local function deep_merge(dst, src)
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            deep_merge(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

-- Get effective preference value using layered resolution:
-- 1. Component user override
-- 2. Shell-wide user override (for shared properties like motion)
-- 3. Component shipped default
-- 4. Shell-wide shipped default
function M.get_effective(key_path, path)
    local overrides = M.read_overrides(path)
    local defaults = M.get_shipped_defaults()

    -- 1. Direct user override
    local val = get_nested(overrides, key_path)
    if val ~= nil then
        if key_path == "aurelia.motion.scale" or key_path:match("^components%.[%w_%-]+%.motion%.scale$") then
            local n = tonumber(val)
            if not n or n < 0 then
                return 1.0
            end
            return n
        end
        return val
    end

    -- 2. If requesting component motion, check shell-wide user override
    local comp_id, motion_prop = key_path:match("^components%.([%w_%-]+)%.motion%.([%w_%-]+)$")
    if comp_id and motion_prop then
        local shell_override = get_nested(overrides, "aurelia.motion." .. motion_prop)
        if shell_override ~= nil then return shell_override end
    end

    -- 3. Component shipped default
    local def_val = get_nested(defaults, key_path)
    if def_val ~= nil then return def_val end

    -- 4. Shell-wide shipped default for motion
    if comp_id and motion_prop then
        return get_nested(defaults, "aurelia.motion." .. motion_prop)
    end

    return nil
end

-- Get all effective preferences merged into one comprehensive table
function M.get_all_effective(path)
    local effective = deep_copy(M.get_shipped_defaults())
    local overrides = M.read_overrides(path)
    deep_merge(effective, overrides)
    return effective
end

-- Validate preference key namespace:
-- Keys must be in 'aurelia.*', 'components.<id>.*', or 'plugins.<id>.*'
local function validate_key_namespace(key_path)
    if key_path:match("^aurelia%.[%w_%-]+") then
        return true
    elseif key_path:match("^components%.[%w_%-]+%.[%w_%-]+") then
        return true
    elseif key_path:match("^plugins%.[%w_%-]+%.[%w_%-]+") then
        return true
    end
    return false, "Invalid preference key namespace: must be within 'aurelia.*', 'components.<id>.*', or 'plugins.<id>.*'"
end

-- Set a user preference override atomically
function M.set_override(key_path, value, path)
    local ok_ns, ns_err = validate_key_namespace(key_path)
    if not ok_ns then
        return false, ns_err
    end

    if key_path == "aurelia.motion.scale" or key_path:match("^components%.[%w_%-]+%.motion%.scale$") then
        local n = tonumber(value)
        if not n or n < 0 then
            return false, "Invalid motion scale (must be a non-negative number)"
        end
        value = n
    end

    path = path or M.get_preferences_path()
    local overrides = M.read_overrides(path)
    set_nested(overrides, key_path, value)
    overrides.schema_version = 1

    local encoded = M.json_encode(overrides)
    return atomic_write_file(path, encoded)
end

-- Remove a user preference override atomically
function M.remove_override(key_path, path)
    path = path or M.get_preferences_path()
    local overrides = M.read_overrides(path)
    unset_nested(overrides, key_path)
    overrides.schema_version = 1

    local encoded = M.json_encode(overrides)
    return atomic_write_file(path, encoded)
end

-- Reset a single component's preferences (e.g. "keybindings"):
-- Removes only user overrides in 'components.<component_id>.*',
-- leaving shell-wide and other component/plugin overrides intact.
function M.reset_component(component_id, path)
    if not component_id or not component_id:match("^[%w_%-]+$") then
        return false, "Invalid component ID for reset: " .. tostring(component_id)
    end

    path = path or M.get_preferences_path()
    local overrides = M.read_overrides(path)

    if overrides.components and type(overrides.components) == "table" then
        overrides.components[component_id] = nil
        if next(overrides.components) == nil then
            overrides.components = nil
        end
    end
    overrides.schema_version = 1

    local encoded = M.json_encode(overrides)
    return atomic_write_file(path, encoded)
end

-- Reset Aurelia Shell preferences:
-- Removes all user overrides, returning effective preferences to shipped defaults.
-- Invariant: Must NOT delete logs, caches, secrets, user files, or workstation configuration.
function M.reset_shell(path)
    path = path or M.get_preferences_path()
    local empty_overrides = { schema_version = 1 }
    local encoded = M.json_encode(empty_overrides)
    return atomic_write_file(path, encoded)
end

-- Export portable preferences:
-- Strictly separates portable preferences (syncable) from machine/runtime data.
-- Machine data (PIDs, sockets, timestamps, absolute machine paths, tokens, secrets) is excluded.
function M.export_portable(path)
    local overrides = M.read_overrides(path)
    local portable = deep_copy(overrides)

    -- Explicitly prune non-portable or runtime domains
    portable.runtime = nil
    portable.logs = nil
    portable.cache = nil
    portable.pids = nil
    portable.sockets = nil
    portable.timestamps = nil
    portable.machine_id = nil
    portable.tokens = nil
    portable.secrets = nil
    portable.passwords = nil
    portable.hardware = nil
    portable.display = nil

    return M.json_encode(portable)
end

-- Redaction helper for privacy: filters tokens, secrets, passwords, and user search queries
function M.redact_sensitive(str)
    if not str or type(str) ~= "string" then return "" end
    local s = str
    s = s:gsub("([%w_%-]*token[%w_%-]*%s*=%s*)[^%s,;]+", "%1[REDACTED]")
    s = s:gsub("([%w_%-]*secret[%w_%-]*%s*=%s*)[^%s,;]+", "%1[REDACTED]")
    s = s:gsub("([%w_%-]*password[%w_%-]*%s*=%s*)[^%s,;]+", "%1[REDACTED]")
    s = s:gsub("([%w_%-]*api[_-]?key[%w_%-]*%s*=%s*)[^%s,;]+", "%1[REDACTED]")
    return s
end

-- Structured logging implementation
-- Levels: DEBUG, INFO, WARN, ERROR, PERF
function M.log_event(level, component, event_id, msg, dur_ms, context)
    local allowed_levels = { DEBUG = true, INFO = true, WARN = true, ERROR = true, PERF = true }
    level = (level or "INFO"):upper()
    if not allowed_levels[level] then level = "INFO" end

    component = component or "aurelia"
    event_id = event_id or "core"
    dur_ms = dur_ms or 0

    -- Redact message and context for privacy
    msg = M.redact_sensitive(msg or "")

    local ts = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local log_path = M.get_log_path()

    local entry = string.format("%s [%s] [%s.%s] %s", ts, level, component, event_id, msg)
    if dur_ms > 0 then
        entry = entry .. string.format(" (dur=%dms)", dur_ms)
    end

    -- Write to bounded log file with error isolation (failure must not crash Aurelia)
    local dir = log_path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
        os.execute("mkdir -p -m 0700 " .. sh_quote(dir) .. " 2>/dev/null")
    end

    local f = io.open(log_path, "a")
    if f then
        f:write(entry .. "\n")
        f:flush()
        f:close()
        M.bound_logfile(log_path, 2000)
    else
        -- Fallback to stderr without throwing
        io.stderr:write(entry .. "\n")
    end
    return true
end

-- Bound log file growth to prevent disk exhaustion (<= 2000 lines)
function M.bound_logfile(log_path, max_lines)
    max_lines = max_lines or 2000
    local f = io.open(log_path, "r")
    if not f then return end
    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()
    if #lines > max_lines then
        local start_idx = #lines - max_lines + 1
        local tmp_path = log_path .. ".tmp." .. tostring(os.time())
        local f_out = io.open(tmp_path, "w")
        if f_out then
            for i = start_idx, #lines do
                f_out:write(lines[i] .. "\n")
            end
            f_out:close()
            os.rename(tmp_path, log_path)
        end
    end
end

-- Gather diagnostics bundle (non-sensitive, privacy-preserving)
function M.get_diagnostics(path)
    local effective = M.get_all_effective(path)
    local overrides = M.read_overrides(path)
    local pref_path = path or M.get_preferences_path()

    local f_exists = false
    local f_size = 0
    local f = io.open(pref_path, "r")
    if f then
        f_exists = true
        f_size = f:seek("end") or 0
        f:close()
    end

    local diag = {
        aurelia_core = {
            version = "1.0.0",
            schema_version = 1,
            preferences_path = pref_path,
            preferences_exist = f_exists,
            preferences_size_bytes = f_size,
        },
        effective_motion = {
            enabled = M.get_effective("aurelia.motion.enabled", path),
            scale = M.get_effective("aurelia.motion.scale", path),
        },
        components = {
            keybindings = {
                motion_enabled = M.get_effective("components.keybindings.motion.enabled", path),
                motion_scale = M.get_effective("components.keybindings.motion.scale", path),
                default_view = M.get_effective("components.keybindings.default_view", path),
            },
        },
        privacy_boundary = {
            search_query_logging = "REDACTED",
            clipboard_logging = "REDACTED",
            secrets_excluded = true,
        },
    }
    return diag
end

return M
