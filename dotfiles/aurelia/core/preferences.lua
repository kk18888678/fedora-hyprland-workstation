-- Module: aurelia.core.preferences
-- Single authoritative source of truth for Aurelia Desktop Shell Core preferences,
-- strict schema registry, layered configuration resolution (Shipped Defaults + User Overrides = Effective Preferences),
-- atomic writes, component/shell reset, schema-driven allowlisted portable export,
-- and lightweight bounded diagnostics logging.

local M = {}

-- 1. Explicit Schema Registry for all supported Aurelia preferences
-- Invariant: Unknown keys fail closed. Arbitrary keys outside the schema are strictly rejected.
M.SCHEMA = {
    ["aurelia.motion.enabled"] = {
        canonical_key = "aurelia.motion.enabled",
        type = "boolean",
        default = true,
        portable = true,
        scope = "shell",
        description = "Global motion enable switch for Aurelia Shell components",
    },
    ["aurelia.motion.scale"] = {
        canonical_key = "aurelia.motion.scale",
        type = "number",
        min = 0.0,
        max = 10.0,
        default = 1.0,
        portable = true,
        scope = "shell",
        description = "Global motion animation duration multiplier",
    },
    ["components.keybindings.motion.enabled"] = {
        canonical_key = "components.keybindings.motion.enabled",
        type = "boolean",
        default = true,
        portable = true,
        scope = "component",
        component = "keybindings",
        inherits_from = "aurelia.motion.enabled",
        description = "Motion enable switch for Keybindings component",
    },
    ["components.keybindings.motion.scale"] = {
        canonical_key = "components.keybindings.motion.scale",
        type = "number",
        min = 0.0,
        max = 10.0,
        default = 1.0,
        portable = true,
        scope = "component",
        component = "keybindings",
        inherits_from = "aurelia.motion.scale",
        description = "Motion duration multiplier for Keybindings component",
    },
    ["components.keybindings.default_view"] = {
        canonical_key = "components.keybindings.default_view",
        type = "string",
        enum = { "bound", "unbound" },
        default = "bound",
        portable = true,
        scope = "component",
        component = "keybindings",
        description = "Initial active view when opening Keybindings palette",
    },
    ["components.keybindings.shortcuts.add_action"] = {
        canonical_key = "components.keybindings.shortcuts.add_action",
        type = "string",
        default = "ALT + A",
        portable = true,
        scope = "component",
        component = "keybindings",
        description = "Component UI shortcut for Add Action",
    },
    ["components.keybindings.shortcuts.back"] = {
        canonical_key = "components.keybindings.shortcuts.back",
        type = "string",
        default = "ALT + B",
        portable = true,
        scope = "component",
        component = "keybindings",
        description = "Component UI shortcut for Back navigation",
    },
    ["components.keybindings.shortcuts.set_binding"] = {
        canonical_key = "components.keybindings.shortcuts.set_binding",
        type = "string",
        default = "S",
        portable = true,
        scope = "component",
        component = "keybindings",
        description = "Component UI shortcut for Set / Change binding",
    },
    ["components.keybindings.shortcuts.unset_binding"] = {
        canonical_key = "components.keybindings.shortcuts.unset_binding",
        type = "string",
        default = "U",
        portable = true,
        scope = "component",
        component = "keybindings",
        description = "Component UI shortcut for Unset binding",
    },
}

-- Shipped Defaults derived authoritatively from the schema registry
function M.get_shipped_defaults()
    return {
        schema_version = 1,
        aurelia = {
            motion = {
                enabled = M.SCHEMA["aurelia.motion.enabled"].default,
                scale = M.SCHEMA["aurelia.motion.scale"].default,
            },
        },
        components = {
            keybindings = {
                motion = {
                    enabled = M.SCHEMA["components.keybindings.motion.enabled"].default,
                    scale = M.SCHEMA["components.keybindings.motion.scale"].default,
                },
                default_view = M.SCHEMA["components.keybindings.default_view"].default,
                shortcuts = {
                    add_action = M.SCHEMA["components.keybindings.shortcuts.add_action"].default,
                    back = M.SCHEMA["components.keybindings.shortcuts.back"].default,
                    set_binding = M.SCHEMA["components.keybindings.shortcuts.set_binding"].default,
                    unset_binding = M.SCHEMA["components.keybindings.shortcuts.unset_binding"].default,
                },
            },
        },
    }
end

-- Resolve production and test preferences file path:
-- Production: $XDG_CONFIG_HOME/aurelia/preferences.json -> ~/.config/aurelia/preferences.json
-- Test override allowed via $AURELIA_PREFERENCES_PATH
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

-- Resolve diagnostic logs path:
-- Production: $XDG_STATE_HOME/workstation/aurelia.log -> ~/.local/state/workstation/aurelia.log
-- Test override allowed via $AURELIA_LOG_PATH
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
            for i = 1, count do
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

-- Validate destination path safety
local function validate_destination_path(path)
    if not path or type(path) ~= "string" or path:match("^%s*$") then
        return false, "Destination path cannot be empty"
    end

    -- 1. Must be an absolute path
    if not path:match("^/") then
        return false, "Destination path must be an absolute path: " .. tostring(path)
    end
    -- 2. Reject path traversal
    if path:match("/%.%./") or path:match("/%.%.$") or path:match("^%.%./") or path:match("^%.%.$") then
        return false, "Directory traversal rejected in destination path: " .. tostring(path)
    end

    -- 3. In production mode: reject privileged system paths (/etc, /usr, /var)
    if not (os.getenv("WORKSTATION_TEST_MODE") == "1" or os.getenv("AURELIA_TEST_MODE") == "1") then
        if path:match("^/etc/") or path:match("^/usr/") or path:match("^/var/") then
            return false, "Privileged system paths rejected for user preferences: " .. tostring(path)
        end
    end

    return true
end

-- Safely and atomically write file with exclusive mktemp and 0600 mode
local function atomic_write_file(path, content)
    local ok_path, path_err = validate_destination_path(path)
    if not ok_path then
        return false, path_err
    end

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

    os.execute("chmod 0600 " .. sh_quote(tmp_path) .. " 2>/dev/null")

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
        io.stderr:write("[WARN] aurelia.core.preferences: Malformed preferences file at " .. path .. "; failing safe to shipped defaults: " .. tostring(err) .. "\n")
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

-- Normalization and validation helper for Keybindings UI control shortcuts
local function normalize_ui_shortcut(k)
    if not k or type(k) ~= "string" then return nil end
    k = k:gsub("^%s+", ""):gsub("%s+$", "")
    if k == "" then return nil end

    local has_super = false
    local has_ctrl = false
    local has_alt = false
    local has_shift = false
    local main_key = ""

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
                main_key = upper
            end
        end
    end

    if not has_super and not has_ctrl and not has_alt and not has_shift and main_key == "" then
        return nil
    end

    local parts = {}
    if has_super then table.insert(parts, "SUPER") end
    if has_ctrl  then table.insert(parts, "CTRL") end
    if has_alt   then table.insert(parts, "ALT") end
    if has_shift then table.insert(parts, "SHIFT") end
    if main_key ~= "" then table.insert(parts, main_key) end

    local norm = table.concat(parts, " + ")
    local has_mod = has_super or has_ctrl or has_alt
    return norm, has_mod, main_key
end

-- Validate preference key and value strictly against Schema Registry
function M.validate_key_and_value(key_path, value)
    if not key_path or type(key_path) ~= "string" then
        return false, "Preference key must be a non-empty string"
    end

    local spec = M.SCHEMA[key_path]
    if not spec then
        return false, "Unknown preference key: '" .. key_path .. "'. Supported keys are strictly defined in schema registry."
    end

    local norm_val
    if spec.type == "boolean" then
        if type(value) == "boolean" then
            norm_val = value
        elseif value == "true" or value == 1 or value == "1" then
            norm_val = true
        elseif value == "false" or value == 0 or value == "0" then
            norm_val = false
        else
            return false, "Invalid boolean value for " .. key_path .. ": expected true/false, got " .. tostring(value)
        end
    elseif spec.type == "number" then
        local n = tonumber(value)
        if not n or (n ~= n) or (n == math.huge) or (n == -math.huge) then
            return false, "Invalid numeric value for " .. key_path .. ": expected finite number, got " .. tostring(value)
        end
        if spec.min and n < spec.min then
            return false, string.format("Value %.2f below minimum %.2f for %s", n, spec.min, key_path)
        end
        if spec.max and n > spec.max then
            return false, string.format("Value %.2f exceeds maximum %.2f for %s", n, spec.max, key_path)
        end
        norm_val = n
    elseif spec.type == "string" then
        if type(value) ~= "string" then
            return false, "Invalid string value for " .. key_path .. ": expected string, got " .. tostring(value)
        end
        if key_path:find("^components%.keybindings%.shortcuts%.") then
            local norm, has_mod, main_key = normalize_ui_shortcut(value)
            if not norm or norm == "" then
                return false, "Invalid shortcut format for " .. key_path .. ": " .. tostring(value)
            end
            if key_path == "components.keybindings.shortcuts.add_action" or key_path == "components.keybindings.shortcuts.back" then
                if not has_mod then
                    return false, "Unsafe shortcut: " .. key_path .. " requires a modifier key (e.g. ALT) to prevent text input conflicts."
                end
            end
            norm_val = norm
        elseif spec.enum then
            local valid = false
            for _, allowed in ipairs(spec.enum) do
                if value == allowed then
                    valid = true
                    break
                end
            end
            if not valid then
                return false, "Invalid value '" .. value .. "' for " .. key_path .. " (expected one of: " .. table.concat(spec.enum, ", ") .. ")"
            end
            norm_val = value
        else
            norm_val = value
        end
    else
        return false, "Unsupported schema type: " .. tostring(spec.type)
    end

    return true, norm_val
end

-- Get effective preference value using layered resolution:
-- 1. Component user override
-- 2. Shell-wide user override (if property inherits from shell-wide setting)
-- 3. Component shipped default
-- 4. Shell-wide shipped default
function M.get_effective(key_path, path)
    local spec = M.SCHEMA[key_path]
    if not spec then
        return nil, "Unknown preference key: " .. tostring(key_path)
    end

    local overrides = M.read_overrides(path)
    local defaults = M.get_shipped_defaults()

    -- 1. Direct user override
    local val = get_nested(overrides, key_path)
    if val ~= nil then
        local ok, norm = M.validate_key_and_value(key_path, val)
        if ok then return norm end
    end

    -- 2. Inheritance: if component setting inherits from a shell-wide setting, check shell-wide override
    if spec.inherits_from then
        local shell_override = get_nested(overrides, spec.inherits_from)
        if shell_override ~= nil then
            local ok, norm = M.validate_key_and_value(spec.inherits_from, shell_override)
            if ok then return norm end
        end
    end

    -- 3. Component shipped default
    local def_val = get_nested(defaults, key_path)
    if def_val ~= nil then return def_val end

    -- 4. Inherited shipped default
    if spec.inherits_from then
        return get_nested(defaults, spec.inherits_from)
    end

    return spec.default
end

-- Get all effective preferences merged into one comprehensive table
function M.get_all_effective(path)
    local effective = deep_copy(M.get_shipped_defaults())
    local overrides = M.read_overrides(path)

    -- Apply valid overrides strictly
    for key_path, spec in pairs(M.SCHEMA) do
        local val = get_nested(overrides, key_path)
        if val ~= nil then
            local ok, norm = M.validate_key_and_value(key_path, val)
            if ok then
                set_nested(effective, key_path, norm)
            end
        end
    end

    return effective
end

-- Set a user preference override atomically with strict validation
function M.set_override(key_path, value, path)
    local ok_val, norm_val = M.validate_key_and_value(key_path, value)
    if not ok_val then
        return false, norm_val
    end

    path = path or M.get_preferences_path()

    -- Conflict check for keybindings component UI shortcuts
    if key_path:find("^components%.keybindings%.shortcuts%.") then
        local shortcut_keys = {
            "components.keybindings.shortcuts.add_action",
            "components.keybindings.shortcuts.back",
            "components.keybindings.shortcuts.set_binding",
            "components.keybindings.shortcuts.unset_binding",
        }
        for _, other_k in ipairs(shortcut_keys) do
            if other_k ~= key_path then
                local other_val = M.get_effective(other_k, path)
                if other_val and other_val == norm_val then
                    return false, string.format("Conflict: Shortcut '%s' is already assigned to %s", norm_val, other_k)
                end
            end
        end
    end

    local overrides = M.read_overrides(path)
    set_nested(overrides, key_path, norm_val)
    overrides.schema_version = 1

    local encoded = M.json_encode(overrides)
    return atomic_write_file(path, encoded)
end

-- Remove a user preference override atomically
function M.remove_override(key_path, path)
    local spec = M.SCHEMA[key_path]
    if not spec then
        return false, "Unknown preference key: " .. tostring(key_path)
    end

    path = path or M.get_preferences_path()
    local overrides = M.read_overrides(path)
    unset_nested(overrides, key_path)
    overrides.schema_version = 1

    local encoded = M.json_encode(overrides)
    return atomic_write_file(path, encoded)
end

-- Reset a single component's preferences (e.g. "keybindings"):
-- Removes only user overrides in 'components.<component_id>.*',
-- leaving shell-wide and other component overrides intact.
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
-- Invariant: Preserves user files, workstation configuration, caches, and logs.
function M.reset_shell(path)
    path = path or M.get_preferences_path()
    local empty_overrides = { schema_version = 1 }
    local encoded = M.json_encode(empty_overrides)
    return atomic_write_file(path, encoded)
end

-- Export portable preferences using strict schema allowlist:
-- Invariant: ONLY schema keys explicitly marked portable=true may be exported.
-- Machine data (tokens, secrets, passwords, sockets, PIDs, timestamps, machine IDs, absolute paths)
-- cannot enter export because they are strictly absent from the allowlist.
function M.export_portable(path)
    local overrides = M.read_overrides(path)
    local portable_export = { schema_version = 1 }

    for key_path, spec in pairs(M.SCHEMA) do
        if spec.portable then
            local val = get_nested(overrides, key_path)
            if val ~= nil then
                local ok, norm = M.validate_key_and_value(key_path, val)
                if ok then
                    set_nested(portable_export, key_path, norm)
                end
            end
        end
    end

    return M.json_encode(portable_export)
end

-- Redaction helper for privacy: filters tokens, secrets, passwords
function M.redact_sensitive(str)
    if not str or type(str) ~= "string" then return "" end
    local s = str
    s = s:gsub("([%w_%-]*token[%w_%-]*%s*=%s*)[^%s,;]+", "%1[REDACTED]")
    s = s:gsub("([%w_%-]*secret[%w_%-]*%s*=%s*)[^%s,;]+", "%1[REDACTED]")
    s = s:gsub("([%w_%-]*password[%w_%-]*%s*=%s*)[^%s,;]+", "%1[REDACTED]")
    s = s:gsub("([%w_%-]*api[_-]?key[%w_%-]*%s*=%s*)[^%s,;]+", "%1[REDACTED]")
    return s
end

-- Bounded log file truncation via tail (only called when file size exceeds bound)
function M.bound_logfile(log_path, max_lines)
    max_lines = max_lines or 2000
    local p = io.popen("tail -n " .. tonumber(max_lines) .. " " .. sh_quote(log_path) .. " 2>/dev/null", "r")
    if not p then return end
    local content = p:read("*a")
    p:close()
    if content and #content > 0 then
        local tmp = log_path .. ".tmp." .. tostring(os.time())
        local f = io.open(tmp, "w")
        if f then
            f:write(content)
            f:flush()
            f:close()
            os.rename(tmp, log_path)
        end
    end
end

-- Lightweight structured logging:
-- Invariant: Does not read the entire log into memory on every event. Writes directly, checks size via seek.
function M.log_event(level, component, event_id, msg, dur_ms, context)
    local allowed_levels = { DEBUG = true, INFO = true, WARN = true, ERROR = true, PERF = true }
    level = (level or "INFO"):upper()
    if not allowed_levels[level] then level = "INFO" end

    component = component or "aurelia"
    event_id = event_id or "core"
    dur_ms = dur_ms or 0

    -- Redact sensitive payloads
    msg = M.redact_sensitive(msg or "")

    local ts = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local log_path = M.get_log_path()

    local entry = string.format("%s [%s] [%s.%s] %s", ts, level, component, event_id, msg)
    if dur_ms > 0 then
        entry = entry .. string.format(" (dur=%dms)", dur_ms)
    end

    local dir = log_path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
        os.execute("mkdir -p -m 0700 " .. sh_quote(dir) .. " 2>/dev/null")
    end

    -- Append directly without reading file into memory
    local f = io.open(log_path, "a")
    if f then
        f:write(entry .. "\n")
        f:flush()
        local sz = f:seek("end") or 0
        f:close()

        -- Bounded log check: only truncate if file exceeds 256KB (~2500 lines)
        if sz > 262144 then
            M.bound_logfile(log_path, 2000)
        end
    else
        io.stderr:write(entry .. "\n")
    end
    return true
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
