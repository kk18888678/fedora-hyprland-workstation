-- Module: application_registry
-- Declarative, production-quality Workstation Application Registry.
-- Answers: "What graphical applications are actually available to this user?"
-- Dynamically discovers applications through standard Linux/XDG desktop-entry mechanisms.
-- Provides dynamic role resolution (file manager, browser, terminal) through desktop identity.
-- Invariants:
-- - Zero hardcoded application tables
-- - Standards-compliant XDG Desktop Entry parsing (Type=Application, NoDisplay, Hidden, TryExec)
-- - Zero custom Exec parser: execution delegated strictly to trusted platform launcher (gtk-launch)
-- - Dynamic icon-theme identifier extraction
-- - Strict precedence: user applications shadow system applications; Hidden masks lower entries
-- - Subdirectory desktop ID derivation per XDG specification (foo/bar.desktop -> foo-bar.desktop)
-- - Process-lifetime cache with explicit invalidation and wall-clock timestamp (no os.clock)
-- - Test-only environment overrides strictly gated on WORKSTATION_TEST_MODE=1
-- - Fail-closed role resolution: no fabricated fake application records

local M = {}

-- Cache storage for discovered applications
M._cache = nil
M._cache_timestamp = 0

-- POSIX shell single-quote escaper
local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Safely trim whitespace
local function trim(s)
    if not s or type(s) ~= "string" then return "" end
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Optional FFI support for direct directory enumeration without subprocess spawning
local has_ffi, ffi = pcall(require, "ffi")
if has_ffi then
    pcall(function()
        ffi.cdef[[
            typedef struct DIR DIR;
            struct dirent {
                unsigned long  d_ino;
                long           d_off;
                unsigned short d_reclen;
                unsigned char  d_type;
                char           d_name[256];
            };
            DIR *opendir(const char *name);
            struct dirent *readdir(DIR *dirp);
            int closedir(DIR *dirp);
        ]]
    end)
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

    -- 2. User-specific Flatpak export directory
    local home = os.getenv("HOME") or ""
    if home ~= "" then
        add_dir(home .. "/.local/share/flatpak/exports/share/applications")
    end

    -- 3. System and exported data directories ($XDG_DATA_DIRS/applications)
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

    -- 4. Host-global Flatpak export directory
    add_dir("/var/lib/flatpak/exports/share/applications")

    return dirs
end

-- Derive desktop file ID relative to base applications directory per XDG specification:
-- "If the file is in a subdirectory of a desktop file directory, the ID is formed by
--  joining the subdirectory names and the desktop file name with dashes (-) instead of directory separators (/)."
function M.derive_desktop_id(base_dir, file_path)
    if not file_path or type(file_path) ~= "string" then return "" end
    if not base_dir or type(base_dir) ~= "string" then
        return file_path:match("([^/]+)$") or file_path
    end

    local norm_base = base_dir:gsub("/+$", "") .. "/"
    if file_path:sub(1, #norm_base) == norm_base then
        local rel = file_path:sub(#norm_base + 1)
        return rel:gsub("/", "-")
    end
    return file_path:match("([^/]+)$") or file_path
end

-- Scan desktop files within a directory supporting 1-level subdirectories
function M.scan_desktop_files_in_dir(dir_path)
    local results = {}
    if not dir_path or type(dir_path) ~= "string" or dir_path == "" then
        return results
    end

    -- Direct C library opendir/readdir via LuaJIT FFI if available
    if has_ffi and ffi and ffi.C and ffi.C.opendir then
        local ok, _ = pcall(function()
            local d = ffi.C.opendir(dir_path)
            if d ~= nil then
                local subdirs = {}
                while true do
                    local ent = ffi.C.readdir(d)
                    if ent == nil then break end
                    local name = ffi.string(ent.d_name)
                    if name ~= "." and name ~= ".." and not name:match("^%.") then
                        if name:match("%.desktop$") then
                            table.insert(results, {
                                path = dir_path .. "/" .. name,
                                desktop_id = name
                            })
                        elseif ent.d_type == 4 or ent.d_type == 0 then
                            -- Subdirectory (or unknown d_type on some filesystems)
                            table.insert(subdirs, name)
                        end
                    end
                end
                ffi.C.closedir(d)

                for _, sub in ipairs(subdirs) do
                    local sub_path = dir_path .. "/" .. sub
                    local sub_d = ffi.C.opendir(sub_path)
                    if sub_d ~= nil then
                        while true do
                            local sub_ent = ffi.C.readdir(sub_d)
                            if sub_ent == nil then break end
                            local sub_name = ffi.string(sub_ent.d_name)
                            if sub_name:match("%.desktop$") then
                                table.insert(results, {
                                    path = sub_path .. "/" .. sub_name,
                                    desktop_id = sub .. "-" .. sub_name
                                })
                            end
                        end
                        ffi.C.closedir(sub_d)
                    end
                end
            end
        end)
        if ok and #results > 0 then
            return results
        end
    end

    -- Safe bounded fallback using find without shell wildcard expansion
    local p = io.popen("find " .. sh_quote(dir_path) .. " -maxdepth 2 -name '*.desktop' 2>/dev/null", "r")
    if p then
        for line in p:lines() do
            line = trim(line)
            if line ~= "" and line:match("%.desktop$") then
                local did = M.derive_desktop_id(dir_path, line)
                table.insert(results, {
                    path = line,
                    desktop_id = did
                })
            end
        end
        p:close()
    end

    return results
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
function M.parse_desktop_file(filepath, explicit_desktop_id)
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

    local desktop_id = explicit_desktop_id or filepath:match("([^/]+)$")
    if not desktop_id or not desktop_id:match("^[a-zA-Z0-9][%w%-%._]*%.desktop$") then
        return nil
    end

    -- Check if marked Hidden (equivalent to deleted at this precedence level per XDG spec)
    if data.Hidden == "true" then
        return {
            desktop_id = desktop_id,
            hidden = true,
            path = filepath,
        }
    end

    -- Strictly require Type=Application and non-empty Name
    if data.Type ~= "Application" then return nil end
    if not data.Name or data.Name == "" then return nil end

    -- Check TryExec if specified per Freedesktop spec:
    -- "Path to an executable file on disk used to determine if the program is actually installed."
    if data.TryExec and data.TryExec ~= "" then
        local te = trim(data.TryExec)
        if te:sub(1, 1) == "/" then
            local f_te = io.open(te, "r")
            if not f_te then return nil end
            f_te:close()
        else
            -- Check common binary paths
            local found = false
            local bin_paths = { "/usr/bin/" .. te, "/usr/local/bin/" .. te, "/bin/" .. te }
            local home = os.getenv("HOME") or ""
            if home ~= "" then
                table.insert(bin_paths, home .. "/.local/bin/" .. te)
            end
            for _, bp in ipairs(bin_paths) do
                local f_bp = io.open(bp, "r")
                if f_bp then
                    f_bp:close()
                    found = true
                    break
                end
            end
            if not found then return nil end
        end
    end

    local nodisplay = (data.NoDisplay == "true")
    local exec_str = data.Exec or ""

    -- Check OnlyShowIn / NotShowIn against current desktop
    local current_desktop = (os.getenv("XDG_CURRENT_DESKTOP") or "Hyprland"):lower()
    if data.NotShowIn then
        for env_id in data.NotShowIn:gmatch("[^;]+") do
            if trim(env_id):lower() == current_desktop then
                nodisplay = true
                break
            end
        end
    end
    if data.OnlyShowIn and not nodisplay then
        local shown = false
        for env_id in data.OnlyShowIn:gmatch("[^;]+") do
            if trim(env_id):lower() == current_desktop then
                shown = true
                break
            end
        end
        if not shown then
            nodisplay = true
        end
    end

    -- Sanitize icon identifier: reject path traversal and control characters
    local icon = data.Icon or ""
    if icon:find("[%c\"';`$><]") or icon:find("%.%./") then
        icon = ""
    end

    -- Safe structured launcher: trusted Freedesktop platform launch via gtk-launch
    -- Avoids custom Exec tokenization, shell interpretation, or eval.
    local launch_cmd = "gtk-launch -- " .. desktop_id
    local launch_argv = { "gtk-launch", "--", desktop_id }

    return {
        desktop_id = desktop_id,
        name = data.Name,
        generic_name = data.GenericName or "",
        comment = data.Comment or "",
        exec = exec_str,
        exec_raw = exec_str,
        command = launch_cmd,
        command_argv = launch_argv,
        icon = icon,
        categories = data.Categories or "",
        keywords = data.Keywords or "",
        terminal = (data.Terminal == "true"),
        nodisplay = nodisplay,
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

    -- Process-lifetime cache with wall-clock timestamp (no os.clock CPU time bug)
    if M._cache and not options.bypass_cache and not options.refresh then
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
        local files = M.scan_desktop_files_in_dir(dir)
        for _, entry in ipairs(files) do
            local did = entry.desktop_id
            if did and not seen[did] then
                seen[did] = true
                local info = M.parse_desktop_file(entry.path, did)
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
    M._cache_timestamp = os.time()

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
            local app = M.parse_desktop_file(candidate_path, query_with_ext)
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
-- Precedence:
-- 1. Explicit workstation desired role (desktop.conf)
-- 2. Test-only environment override (ONLY when WORKSTATION_TEST_MODE=1)
-- 3. Standard desktop/XDG default (xdg-mime query default)
-- 4. Stable Recommended fallback
-- Policy B: If explicit desired role cannot be resolved, log drift and use verified Recommended fallback.
-- If neither desired nor recommended fallback exists, fail closed with error (zero fake application records).
function M.resolve_role(role)
    if not role or type(role) ~= "string" then return nil end
    local r = role:lower():gsub("_", "-")
    local conf = M.read_desktop_config()
    local is_test_mode = (os.getenv("WORKSTATION_TEST_MODE") == "1")

    local explicit_target = nil
    local mime_target = nil
    local recommended_target = nil

    if r == "terminal" or r == "terminal.default" then
        -- 1. Explicit workstation desired role
        local cfg_val = conf["terminal.default"] or conf["terminal_default"] or conf["terminal"]
        if cfg_val and cfg_val ~= "" then
            explicit_target = cfg_val
        end

        -- 2. Test-only environment override (strictly gated on WORKSTATION_TEST_MODE=1)
        if not explicit_target and is_test_mode then
            local test_val = os.getenv("DEFAULT_TERMINAL") or os.getenv("TERMINAL")
            if test_val and test_val ~= "" then
                explicit_target = test_val
            end
        end

        -- 3. Recommended fallback
        recommended_target = "kitty.desktop"

    elseif r == "file-manager" or r == "file_manager" or r == "files" or r == "files.default" or r == "explorer" then
        -- 1. Explicit workstation desired role
        local cfg_val = conf["file-manager.default"] or conf["file_manager.default"] or conf["file-manager"] or conf["files.default"] or conf["files"]
        if cfg_val and cfg_val ~= "" then
            explicit_target = cfg_val
        end

        -- 2. Test-only environment override (strictly gated on WORKSTATION_TEST_MODE=1)
        if not explicit_target and is_test_mode then
            local test_val = os.getenv("DEFAULT_FILE_MANAGER") or os.getenv("DEFAULT_EXPLORER") or os.getenv("FILE_MANAGER")
            if test_val and test_val ~= "" then
                explicit_target = test_val
            end
        end

        -- 3. Standard desktop/XDG default via xdg-mime
        if not explicit_target then
            local ok, p = pcall(io.popen, "xdg-mime query default inode/directory 2>/dev/null")
            if ok and p then
                local res = trim(p:read("*l") or "")
                pcall(function() p:close() end)
                if res ~= "" then
                    mime_target = res
                end
            end
        end

        -- 4. Recommended fallback
        recommended_target = "org.gnome.Nautilus.desktop"

    elseif r == "browser" or r == "browser.default" then
        -- 1. Explicit workstation desired role
        local cfg_val = conf["browser.default"] or conf["browser_default"] or conf["browser"]
        if cfg_val and cfg_val ~= "" then
            explicit_target = cfg_val
        end

        -- 2. Test-only environment override (strictly gated on WORKSTATION_TEST_MODE=1)
        if not explicit_target and is_test_mode then
            local test_val = os.getenv("DEFAULT_BROWSER") or os.getenv("BROWSER")
            if test_val and test_val ~= "" then
                explicit_target = test_val
            end
        end

        -- 3. Standard desktop/XDG default via xdg-mime
        if not explicit_target then
            local ok, p = pcall(io.popen, "xdg-mime query default x-scheme-handler/https 2>/dev/null")
            if ok and p then
                local res = trim(p:read("*l") or "")
                pcall(function() p:close() end)
                if res ~= "" then
                    mime_target = res
                end
            end
        end

        -- 4. Recommended fallback
        recommended_target = "chromium-browser.desktop"
    else
        return nil, "Unknown workstation role: " .. tostring(role)
    end

    -- Resolution sequence:
    -- A. If explicit target set:
    if explicit_target then
        local app_info = M.find_application(explicit_target)
        if app_info then
            local canon = M.canonical_app_name(app_info.desktop_id)
            return canon, app_info
        end

        -- Explicit target not discoverable: report drift, attempt recommended fallback
        if recommended_target then
            local rec_info = M.find_application(recommended_target)
            if rec_info then
                rec_info.drifted = true
                local canon = M.canonical_app_name(rec_info.desktop_id)
                return canon, rec_info
            end
        end

        -- Fail closed: do not synthesize fake application record
        return nil, string.format("Cannot resolve application for role '%s': configured '%s' is not installed and fallback is unavailable", role, explicit_target)
    end

    -- B. If MIME default detected:
    if mime_target then
        local app_info = M.find_application(mime_target)
        if app_info then
            local canon = M.canonical_app_name(app_info.desktop_id)
            return canon, app_info
        end
    end

    -- C. Recommended workstation fallback:
    if recommended_target then
        local rec_info = M.find_application(recommended_target)
        if rec_info then
            local canon = M.canonical_app_name(rec_info.desktop_id)
            return canon, rec_info
        end
    end

    -- Fail closed
    return nil, string.format("Cannot resolve application for role '%s': no installed application matches role", role)
end

return M
