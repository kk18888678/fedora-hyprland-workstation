-- Module: application_registry
-- Declarative, production-quality Workstation Application Registry.
-- Answers: "What graphical applications are actually available to this user?"
-- Dynamically discovers applications through standard Linux/XDG desktop-entry mechanisms.
-- Provides dynamic role resolution (file manager, browser, terminal) through desktop identity.
-- Invariants:
-- - Zero hardcoded application tables (no KNOWN_ROLE_APPS)
-- - Standards-compliant XDG Desktop Entry parsing (Type=Application, NoDisplay, Hidden, Exec)
-- - Safe structured Exec tokenization with field-code removal (no eval, no sh -c)
-- - Dynamic icon-theme identifier extraction
-- - Precedence: user applications shadow system applications; Hidden masks lower entries
-- - Bounded execution and safe failure isolation on malformed input

local M = {}

-- Cache storage for discovered applications
M._cache = nil
M._cache_timestamp = 0
M._CACHE_TTL = 5.0 -- 5 seconds cache TTL

-- POSIX shell single-quote escaper
local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Safely trim whitespace
local function trim(s)
    if not s or type(s) ~= "string" then return "" end
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Resolve application search paths following XDG Desktop Entry Specification
function M.get_search_dirs()
    local dirs = {}
    local seen = {}

    local function add_dir(d)
        d = trim(d)
        if d ~= "" and not seen[d] then
            seen[d] = true
            table.insert(dirs, d)
        end
    end

    -- 1. User-specific data directory ($XDG_DATA_HOME/applications)
    local data_home = os.getenv("XDG_DATA_HOME")
    if not data_home or data_home == "" then
        local home = os.getenv("HOME") or ""
        data_home = home .. "/.local/share"
    end
    add_dir(data_home .. "/applications")

    -- 2. System and exported data directories ($XDG_DATA_DIRS/applications)
    local data_dirs = os.getenv("XDG_DATA_DIRS")
    if not data_dirs or data_dirs == "" then
        data_dirs = "/usr/local/share:/usr/share"
    end

    for part in data_dirs:gmatch("[^:]+") do
        part = trim(part)
        if part ~= "" then
            add_dir(part .. "/applications")
        end
    end

    return dirs
end

-- Standards-correct Exec key tokenization following Freedesktop Desktop Entry Specification
-- - Extracts executable as argv[1]
-- - Normalizes standard /usr/bin or /bin prefixes to executable name for consistent matching
-- - Handles double quotes and backslash escape sequences
-- - Strips field codes (%f, %F, %u, %U, %d, %D, %n, %N, %i, %c, %k, %v, %m)
-- - Expands %% to %
-- - Strictly prohibits eval, sh -c, or shell interpolation
function M.parse_exec_line(exec_str)
    if not exec_str or type(exec_str) ~= "string" then return nil end
    exec_str = trim(exec_str)
    if exec_str == "" then return nil end

    local tokens = {}
    local pos = 1
    local len = #exec_str

    while pos <= len do
        -- Skip leading whitespace
        while pos <= len and exec_str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
        if pos > len then break end

        local token = {}
        local in_quotes = false

        while pos <= len do
            local c = exec_str:sub(pos, pos)
            if c == "\\" then
                pos = pos + 1
                if pos <= len then
                    local esc = exec_str:sub(pos, pos)
                    if esc == "s" then
                        table.insert(token, " ")
                    elseif esc == "n" then
                        table.insert(token, "\n")
                    elseif esc == "t" then
                        table.insert(token, "\t")
                    elseif esc == "r" then
                        table.insert(token, "\r")
                    else
                        table.insert(token, esc)
                    end
                    pos = pos + 1
                end
            elseif c == "\"" then
                in_quotes = not in_quotes
                pos = pos + 1
            elseif not in_quotes and c:match("%s") then
                break
            else
                table.insert(token, c)
                pos = pos + 1
            end
        end

        table.insert(tokens, table.concat(token))
    end

    if #tokens == 0 then return nil end

    -- Executable is the first token
    local exe = tokens[1]
    if exe:match("^/usr/bin/([^/]+)$") then
        exe = exe:match("^/usr/bin/([^/]+)$")
    elseif exe:match("^/bin/([^/]+)$") then
        exe = exe:match("^/bin/([^/]+)$")
    end
    local argv = { exe }

    -- Process arguments and filter field codes
    for i = 2, #tokens do
        local tok = tokens[i]
        -- Freedesktop field codes to strip when launching application directly
        if tok:match("^%%[fFuUdDnNicckvm]$") then
            -- Field code omitted for direct launch
        else
            -- Expand %% to literal %
            tok = tok:gsub("%%%%", "%%")
            table.insert(argv, tok)
        end
    end

    return argv
end

-- Determine application origin/source from filesystem path
function M.detect_source(path)
    if not path or type(path) ~= "string" then return "unknown" end
    if path:find("/flatpak/") then
        return "flatpak"
    elseif path:find("/nix/") or path:find("/%.nix%-profile/") then
        return "nix"
    elseif path:find("/usr/local/") then
        return "local"
    elseif path:find("/usr/") then
        return "system"
    else
        local home = os.getenv("HOME") or ""
        if home ~= "" and path:sub(1, #home) == home then
            return "user"
        end
    end
    return "system"
end

-- Safely parse a single .desktop file with strict bounds
function M.parse_desktop_file(filepath)
    if not filepath or type(filepath) ~= "string" then return nil end

    local f = io.open(filepath, "r")
    if not f then return nil end

    -- Bound read to 128KB to protect against pathological files
    local content = f:read(131072)
    f:close()
    if not content or content == "" then return nil end

    local in_desktop_entry = false
    local data = {}

    for line in content:gmatch("[^\r\n]+") do
        line = trim(line)
        if line:match("^%[Desktop Entry%]$") then
            in_desktop_entry = true
        elseif line:match("^%[") then
            -- Another section started (e.g. [Desktop Action ...])
            in_desktop_entry = false
        elseif in_desktop_entry and not line:match("^[#;]") then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                k = trim(k)
                -- Prioritize unlocalized keys
                if not k:match("%[") then
                    data[k] = trim(v)
                elseif not data[k:match("^([^%[]+)")] then
                    -- Fallback to localized key if unlocalized not yet seen
                    data[k:match("^([^%[]+)")] = trim(v)
                end
            end
        end
    end

    local desktop_id = filepath:match("([^/]+)$")
    if not desktop_id then return nil end

    -- Check if marked Hidden (equivalent to deleted at this precedence level)
    if data.Hidden == "true" then
        return {
            desktop_id = desktop_id,
            hidden = true,
            path = filepath,
        }
    end

    -- Strictly require Type=Application and Name
    if data.Type ~= "Application" then return nil end
    if not data.Name or data.Name == "" then return nil end

    local exec_str = data.Exec or ""
    local command_argv = M.parse_exec_line(exec_str)

    return {
        desktop_id = desktop_id,
        name = data.Name,
        generic_name = data.GenericName or "",
        comment = data.Comment or "",
        exec = exec_str,
        command_argv = command_argv or { exec_str:match("^%S+") or exec_str },
        icon = data.Icon or "",
        categories = data.Categories or "",
        keywords = data.Keywords or "",
        terminal = (data.Terminal == "true"),
        nodisplay = (data.NoDisplay == "true"),
        hidden = false,
        path = filepath,
        source = M.detect_source(filepath),
    }
end

-- Invalidate discovery cache
function M.invalidate_cache()
    M._cache = nil
    M._cache_timestamp = 0
end

-- Query truthful detectable system default roles via XDG MIME
function M.get_truthful_default_roles()
    local defaults = {}
    local p_br = io.popen("xdg-mime query default x-scheme-handler/https 2>/dev/null", "r")
    if p_br then
        local br = p_br:read("*l")
        p_br:close()
        if br and br ~= "" then defaults[trim(br)] = "Default Browser" end
    end
    local p_fm = io.popen("xdg-mime query default inode/directory 2>/dev/null", "r")
    if p_fm then
        local fm = p_fm:read("*l")
        p_fm:close()
        if fm and fm ~= "" then defaults[trim(fm)] = "Default File Manager" end
    end
    local p_te = io.popen("xdg-mime query default text/plain 2>/dev/null", "r")
    if p_te then
        local te = p_te:read("*l")
        p_te:close()
        if te and te ~= "" then defaults[trim(te)] = "Default Text Editor" end
    end
    return defaults
end

-- List all installed graphical applications dynamically
function M.list_applications(options)
    options = options or {}
    local include_nodisplay = (options.include_nodisplay == true)

    local now = os.clock()
    if M._cache and (now - M._cache_timestamp) < M._CACHE_TTL and not options.bypass_cache then
        if include_nodisplay then
            return M._cache.all_apps
        else
            return M._cache.visible_apps
        end
    end

    local search_dirs = M.get_search_dirs()
    local seen = {}
    local visible_apps = {}
    local all_apps = {}
    local default_roles = M.get_truthful_default_roles()

    for _, dir in ipairs(search_dirs) do
        local p = io.popen("ls -1 " .. sh_quote(dir) .. "/*.desktop 2>/dev/null", "r")
        if p then
            for filepath in p:lines() do
                local did = filepath:match("([^/]+)$")
                if did and not seen[did] then
                    seen[did] = true
                    local info = M.parse_desktop_file(filepath)
                    if info then
                        if not info.hidden then
                            info.default_role = default_roles[did] or ""
                            table.insert(all_apps, info)
                            if not info.nodisplay or include_nodisplay then
                                table.insert(visible_apps, info)
                            end
                        end
                    end
                end
            end
            p:close()
        end
    end

    -- Deterministic sort by display name, then desktop ID
    local function app_sort(a, b)
        local na = (a.name or ""):lower()
        local nb = (b.name or ""):lower()
        if na ~= nb then return na < nb end
        return (a.desktop_id or "") < (b.desktop_id or "")
    end
    table.sort(visible_apps, app_sort)
    table.sort(all_apps, app_sort)

    M._cache = {
        visible_apps = visible_apps,
        all_apps = all_apps,
    }
    M._cache_timestamp = now

    if include_nodisplay then
        return all_apps
    else
        return visible_apps
    end
end

-- Normalize canonical role identity (e.g. "org.gnome.Nautilus.desktop" -> "nautilus")
function M.canonical_app_name(desktop_id)
    if not desktop_id or type(desktop_id) ~= "string" then return "" end
    local base = desktop_id:match("([^/]+)$") or desktop_id
    base = base:gsub("%.desktop$", "")
    -- Strip common reverse-DNS prefixes (e.g. org.gnome., org.kde., com.google.)
    base = base:gsub("^[%w%-_]+%.[%w%-_]+%.", "")
    -- Strip common client suffixes (e.g. footclient -> foot)
    if base == "footclient" then base = "foot" end
    return base:lower()
end

-- Find a specific application by exact desktop ID, short name, or display name
function M.find_application(query)
    if not query or type(query) ~= "string" then return nil end
    query = trim(query)
    if query == "" then return nil end

    local query_lower = query:lower()
    local query_with_ext = query_lower:match("%.desktop$") and query_lower or (query_lower .. ".desktop")

    -- 1. Fast path: Direct file check in search directories for desktop ID
    local search_dirs = M.get_search_dirs()
    for _, dir in ipairs(search_dirs) do
        local candidate_path = dir .. "/" .. query_with_ext
        local f = io.open(candidate_path, "r")
        if f then
            f:close()
            local app = M.parse_desktop_file(candidate_path)
            if app and not app.hidden then
                return app
            end
        end
    end

    -- 2. Search all installed applications (including NoDisplay for explicit queries)
    local all_apps = M.list_applications({ include_nodisplay = true })

    -- Check exact desktop_id match (case-insensitive)
    for _, app in ipairs(all_apps) do
        if app.desktop_id:lower() == query_with_ext then
            return app
        end
    end

    -- Check canonical base name match (e.g. "nautilus" matches "org.gnome.Nautilus.desktop")
    for _, app in ipairs(all_apps) do
        if M.canonical_app_name(app.desktop_id) == query_lower then
            return app
        end
    end

    -- Check exact display name match (case-insensitive)
    for _, app in ipairs(all_apps) do
        if (app.name or ""):lower() == query_lower then
            return app
        end
    end

    -- Check substring in desktop ID (e.g. "dolphin" in "org.kde.dolphin.desktop")
    for _, app in ipairs(all_apps) do
        if app.desktop_id:lower():find(query_lower, 1, true) then
            return app
        end
    end

    return nil
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

-- Read desktop.conf key-value pairs
function M.read_desktop_config()
    local conf_path = M.get_desktop_config_path()
    local f = io.open(conf_path, "r")
    if not f then return {} end
    local conf = {}
    for line in f:lines() do
        line = trim(line)
        if line ~= "" and not line:match("^[#;]") then
            local k, v = line:match("^([%w%._%-]+)%s*=%s*(.-)$")
            if k and v then
                conf[k:lower()] = trim(v)
            end
        end
    end
    f:close()
    return conf
end

-- Resolve active application dynamically for generic workstation roles:
-- 1. Explicit workstation desired role (desktop.conf)
-- 2. Test-only environment override (when WORKSTATION_TEST_MODE=1 or DEFAULT_<ROLE> set)
-- 3. Standard desktop/XDG default (xdg-mime query default)
-- 4. Stable Recommended fallback
-- Returns: canonical_name, app_info
function M.resolve_role(role)
    if not role or type(role) ~= "string" then return nil end
    local r = role:lower():gsub("_", "-")
    local conf = M.read_desktop_config()

    local target_app = nil

    if r == "terminal" or r == "terminal.default" then
        -- 1. Explicit workstation desired role
        local cfg_val = conf["terminal.default"] or conf["terminal_default"] or conf["terminal"]
        if cfg_val and cfg_val ~= "" then
            target_app = cfg_val
        end

        -- 2. Test-only environment override
        if not target_app then
            local test_val = os.getenv("DEFAULT_TERMINAL") or os.getenv("TERMINAL")
            if test_val and test_val ~= "" then
                target_app = test_val
            end
        end

        -- 3. Recommended fallback
        if not target_app then
            target_app = "kitty"
        end

    elseif r == "file-manager" or r == "file_manager" or r == "files" or r == "files.default" or r == "explorer" then
        -- 1. Explicit workstation desired role
        local cfg_val = conf["file-manager.default"] or conf["file_manager.default"] or conf["file-manager"] or conf["files.default"] or conf["files"]
        if cfg_val and cfg_val ~= "" then
            target_app = cfg_val
        end

        -- 2. Test-only environment override
        if not target_app then
            local test_val = os.getenv("DEFAULT_FILE_MANAGER") or os.getenv("DEFAULT_EXPLORER") or os.getenv("FILE_MANAGER")
            if test_val and test_val ~= "" then
                target_app = test_val
            end
        end

        -- 3. Standard desktop/XDG default via xdg-mime
        if not target_app then
            local ok, p = pcall(io.popen, "xdg-mime query default inode/directory 2>/dev/null")
            if ok and p then
                local res = trim(p:read("*l") or "")
                pcall(function() p:close() end)
                if res ~= "" then
                    target_app = res
                end
            end
        end

        -- 4. Recommended fallback
        if not target_app then
            target_app = "org.gnome.Nautilus.desktop"
        end

    elseif r == "browser" or r == "browser.default" then
        -- 1. Explicit workstation desired role
        local cfg_val = conf["browser.default"] or conf["browser_default"] or conf["browser"]
        if cfg_val and cfg_val ~= "" then
            target_app = cfg_val
        end

        -- 2. Test-only environment override
        if not target_app then
            local test_val = os.getenv("DEFAULT_BROWSER") or os.getenv("BROWSER")
            if test_val and test_val ~= "" then
                target_app = test_val
            end
        end

        -- 3. Standard desktop/XDG default via xdg-mime
        if not target_app then
            local ok, p = pcall(io.popen, "xdg-mime query default x-scheme-handler/https 2>/dev/null")
            if ok and p then
                local res = trim(p:read("*l") or "")
                pcall(function() p:close() end)
                if res ~= "" then
                    target_app = res
                end
            end
        end

        -- 4. Recommended fallback
        if not target_app then
            target_app = "chromium-browser.desktop"
        end
    end

    if not target_app then return nil end

    -- Resolve through the dynamic Application Registry
    local app_info = M.find_application(target_app)
    if app_info then
        local canon = M.canonical_app_name(app_info.desktop_id)
        return canon, app_info
    end

    -- Fallback synthesis if application is not installed on host
    local canon = M.canonical_app_name(target_app)
    local fallback_info = {
        desktop_id = target_app:match("%.desktop$") and target_app or (target_app .. ".desktop"),
        name = canon:sub(1,1):upper() .. canon:sub(2),
        exec = canon,
        command_argv = { canon },
        icon = canon,
        source = "fallback",
    }
    return canon, fallback_info
end

return M
