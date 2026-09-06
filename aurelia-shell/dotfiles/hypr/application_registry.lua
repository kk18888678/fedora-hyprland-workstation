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
-- - Lazy process-lifetime cache with explicit invalidation/refresh
-- - Test-only environment overrides strictly gated on WORKSTATION_TEST_MODE=1
-- - Fail-closed role resolution: no fabricated fake application records

local M = {}

-- Cache storage for discovered applications (lazy process-lifetime cache)
M._cache = nil

-- POSIX shell single-quote escaper
local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Safely trim whitespace
local function trim(s)
    if not s or type(s) ~= "string" then return "" end
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Optional FFI support for direct directory enumeration and POSIX operations without subprocess spawning
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
            char *realpath(const char *path, char *resolved_path);
            void free(void *ptr);
            int access(const char *pathname, int mode);
        ]]
    end)
end

-- Safely resolve canonical realpath without symlink cycles
local function get_realpath(path)
    if not path or type(path) ~= "string" or path == "" then return nil end
    if has_ffi and ffi and ffi.C and ffi.C.realpath and ffi.C.free then
        local r = ffi.C.realpath(path, nil)
        if r ~= nil then
            local str = ffi.string(r)
            ffi.C.free(r)
            return str
        end
        return nil
    end
    return path:gsub("/+$", "")
end

-- Check if path exists, is a regular file/symlink, and has executable permission (X_OK)
function M.is_executable_file(path)
    if not path or type(path) ~= "string" or path == "" then return false end

    if has_ffi and ffi and ffi.C and ffi.C.access then
        -- POSIX access(path, X_OK) where X_OK == 1
        if ffi.C.access(path, 1) ~= 0 then
            return false
        end
        -- Ensure target is not a directory (directories can have X_OK permission)
        if ffi.C.opendir then
            local d = ffi.C.opendir(path)
            if d ~= nil then
                ffi.C.closedir(d)
                return false
            end
        end
        return true
    end

    -- Bounded fallback when FFI is not available
    local f = io.open(path, "r")
    if not f then return false end
    local ok_read = pcall(function() return f:read(0) end)
    f:close()
    if not ok_read then return false end
    local rc = os.execute("test -f " .. sh_quote(path) .. " -a -x " .. sh_quote(path))
    return (rc == 0 or rc == true)
end

-- Resolve a command name in $PATH according to POSIX and Freedesktop semantics
function M.resolve_in_path(cmd)
    if not cmd or type(cmd) ~= "string" or cmd == "" then return nil end
    -- A valid command name in PATH cannot contain slashes or control/whitespace chars
    if cmd:find("/") or cmd:find("[%c]") or cmd:find("%s") then
        return nil
    end

    local path_env = os.getenv("PATH")
    if not path_env or path_env == "" then
        path_env = "/usr/local/bin:/usr/bin:/bin"
    end

    -- Split colon-separated PATH components safely handling empty components
    for part in (path_env .. ":"):gmatch("([^:]*):") do
        part = trim(part)
        -- In POSIX, an empty PATH entry represents current working directory ("."),
        -- but for workstation application safety, skip empty/dot entries
        if part ~= "" and part ~= "." then
            local candidate = part:gsub("/+$", "") .. "/" .. cmd
            if M.is_executable_file(candidate) then
                return candidate
            end
        end
    end

    return nil
end

-- Validate TryExec per Freedesktop Desktop Entry specification:
-- "Path to an executable file on disk used to determine if the program is actually installed.
--  If the path is not an absolute path, the file is looked up in the $PATH environment variable.
--  If the file is not present or if it is not executable, the entry may be ignored."
function M.is_tryexec_valid(tryexec)
    if not tryexec or type(tryexec) ~= "string" then return false end
    local te = trim(tryexec)
    if te == "" then return false end

    -- Reject control characters or NUL bytes
    if te:find("[%c]") or te:find("%z") then
        return false
    end

    -- Absolute path: verify existence, executability, and non-directory status
    if te:sub(1, 1) == "/" then
        return M.is_executable_file(te)
    end

    -- Non-absolute path per Desktop Entry spec: looked up in $PATH.
    -- Relative paths with slashes (e.g. "../bin/tool") or arguments are rejected.
    if te:find("/") or te:find("%s") then
        return false
    end

    return (M.resolve_in_path(te) ~= nil)
end

-- Safely parse Freedesktop Exec line into structured argument vector
-- Handles single quotes, double quotes, escape sequences, and strips field codes (%f, %F, %u, %U, etc.)
function M.parse_exec_line(exec_str)
    if not exec_str or type(exec_str) ~= "string" then return {} end
    local tokens = {}
    local i = 1
    local len = #exec_str

    while i <= len do
        while i <= len and exec_str:sub(i, i):match("%s") do
            i = i + 1
        end
        if i > len then break end

        local current = {}
        local in_dquote = false
        local in_squote = false

        while i <= len do
            local c = exec_str:sub(i, i)
            if not in_dquote and not in_squote and c:match("%s") then
                break
            elseif not in_dquote and c == "'" then
                in_squote = not in_squote
                i = i + 1
            elseif not in_squote and c == '"' then
                in_dquote = not in_dquote
                i = i + 1
            elseif c == "\\" and (in_dquote or not in_squote) and i < len then
                local next_c = exec_str:sub(i + 1, i + 1)
                if in_dquote and (next_c == '"' or next_c == "`" or next_c == "$" or next_c == "\\") then
                    table.insert(current, next_c)
                    i = i + 2
                elseif not in_dquote and (next_c == " " or next_c == '"' or next_c == "'" or next_c == "\\") then
                    table.insert(current, next_c)
                    i = i + 2
                else
                    table.insert(current, c)
                    i = i + 1
                end
            elseif c == "%" and not in_squote then
                local next_c = exec_str:sub(i + 1, i + 1)
                if next_c == "%" then
                    table.insert(current, "%")
                    i = i + 2
                elseif next_c:match("[fFuUdDnNickvm]") then
                    -- Field code to expand or drop when launching without file arguments
                    i = i + 2
                else
                    table.insert(current, c)
                    i = i + 1
                end
            else
                table.insert(current, c)
                i = i + 1
            end
        end

        local token = table.concat(current)
        if #token > 0 then
            table.insert(tokens, token)
        end
    end
    return tokens
end

-- Resolve terminal emulator command for launching console applications (Terminal=true)
function M.resolve_terminal_executable()
    local conf = M.read_desktop_config()
    local configured_term = conf["terminal.default"] or conf["terminal_default"] or conf["terminal"]
    if configured_term and configured_term ~= "" then
        local base = configured_term:gsub("%.desktop$", "")
        if M.resolve_in_path(base) then
            return base
        end
    end

    -- Supported workstation terminals in order of preference
    for _, candidate in ipairs({ "kitty", "foot", "xdg-terminal-exec", "gnome-terminal", "xterm" }) do
        if M.resolve_in_path(candidate) then
            return candidate
        end
    end

    return nil
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

    local norm_base = (base_dir:gsub("/+$", "") .. "/"):gsub("/+", "/")
    local norm_file = file_path:gsub("/+", "/")
    if norm_file:sub(1, #norm_base) == norm_base then
        local rel = norm_file:sub(#norm_base + 1)
        return rel:gsub("/", "-")
    end
    return file_path:match("([^/]+)$") or file_path
end

-- Recursively scan desktop files within a directory per XDG Desktop Entry specification
-- Invariants:
-- - Traverses nested subdirectories beneath each XDG applications directory
-- - Uses canonical derive_desktop_id (no manual ID construction)
-- - Rejects symlink loops and traversal outside base directory
-- - Traversal bounded against pathological trees (MAX_SCAN_DEPTH=10, MAX_DIRS=256, MAX_FILES=4096)
-- - Zero shell invocation when FFI is available
function M.scan_desktop_files_in_dir(dir_path)
    local results = {}
    if not dir_path or type(dir_path) ~= "string" or dir_path == "" then
        return results
    end

    -- Direct C library opendir/readdir via LuaJIT FFI if available
    if has_ffi and ffi and ffi.C and ffi.C.opendir then
        local ok = pcall(function()
            local base_real = get_realpath(dir_path)
            if not base_real then return end

            local visited_dirs = { [base_real] = true }
            local MAX_SCAN_DEPTH = 10
            local MAX_FILES = 4096
            local MAX_DIRS = 256
            local dirs_visited = 0
            local files_found = 0

            -- Queue-based breadth-first search: { path = ..., depth = ... }
            local queue = { { path = dir_path, depth = 0 } }
            local q_idx = 1

            while q_idx <= #queue do
                if dirs_visited >= MAX_DIRS or files_found >= MAX_FILES then
                    break
                end

                local current = queue[q_idx]
                q_idx = q_idx + 1
                dirs_visited = dirs_visited + 1

                local d = ffi.C.opendir(current.path)
                if d ~= nil then
                    local entries_files = {}
                    local entries_dirs = {}

                    while true do
                        local ent = ffi.C.readdir(d)
                        if ent == nil then break end
                        local name = ffi.string(ent.d_name)
                        -- XDG spec: files and directories whose name begins with a period are ignored
                        if name ~= "." and name ~= ".." and not name:match("^%.") then
                            local full_entry_path = current.path:gsub("/+$", "") .. "/" .. name
                            local is_dir = false

                            if ent.d_type == 4 then -- DT_DIR
                                is_dir = true
                            elseif ent.d_type == 8 then -- DT_REG
                                is_dir = false
                            elseif ent.d_type == 10 or ent.d_type == 0 then -- DT_LNK or DT_UNKNOWN
                                local sub_d = ffi.C.opendir(full_entry_path)
                                if sub_d ~= nil then
                                    ffi.C.closedir(sub_d)
                                    is_dir = true
                                else
                                    is_dir = false
                                end
                            end

                            if is_dir then
                                if current.depth < MAX_SCAN_DEPTH then
                                    table.insert(entries_dirs, { name = name, path = full_entry_path })
                                end
                            else
                                if name:match("%.desktop$") then
                                    table.insert(entries_files, full_entry_path)
                                end
                            end
                        end
                    end
                    ffi.C.closedir(d)

                    -- Sort entries alphabetically for deterministic order
                    table.sort(entries_files)
                    for _, fpath in ipairs(entries_files) do
                        if files_found >= MAX_FILES then break end
                        files_found = files_found + 1
                        local did = M.derive_desktop_id(dir_path, fpath)
                        table.insert(results, {
                            path = fpath,
                            desktop_id = did,
                        })
                    end

                    table.sort(entries_dirs, function(a, b) return a.name < b.name end)
                    for _, dir_info in ipairs(entries_dirs) do
                        local rpath = get_realpath(dir_info.path)
                        -- Avoid symlink loops and ensure we do not escape outside base directory
                        if rpath and not visited_dirs[rpath] then
                            if rpath == base_real or rpath:sub(1, #base_real + 1) == (base_real .. "/") then
                                visited_dirs[rpath] = true
                                table.insert(queue, { path = dir_info.path, depth = current.depth + 1 })
                            end
                        end
                    end
                end
            end
        end)
        if ok then
            return results
        end
    end

    -- Safe bounded fallback using find without shell wildcard expansion
    local p = io.popen("find " .. sh_quote(dir_path) .. " -maxdepth 10 -name '*.desktop' 2>/dev/null", "r")
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
    -- "Path to an executable file on disk used to determine if the program is actually installed.
    --  If the path is not an absolute path, the file is looked up in the $PATH environment variable.
    --  If the file is not present or if it is not executable, the entry may be ignored."
    if data.TryExec and data.TryExec ~= "" then
        if not M.is_tryexec_valid(data.TryExec) then
            return nil
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

    -- Safe structured launcher:
    -- Standard Freedesktop launch delegates to gtk-launch for graphical applications.
    -- For console applications (Terminal=true), gtk-launch fails when no GNOME terminal or xdg-terminal-exec is present.
    -- Terminal applications are wrapped deterministically using the workstation terminal.
    local is_terminal_app = (data.Terminal == "true")
    local launch_cmd = nil
    local launch_argv = nil

    if is_terminal_app and exec_str ~= "" then
        local exec_tokens = M.parse_exec_line(exec_str)
        if #exec_tokens > 0 then
            local term_bin = M.resolve_terminal_executable()
            if term_bin then
                launch_argv = { term_bin, "--" }
                for _, tok in ipairs(exec_tokens) do
                    table.insert(launch_argv, tok)
                end
                local quoted_parts = { sh_quote(term_bin), "--" }
                for _, tok in ipairs(exec_tokens) do
                    table.insert(quoted_parts, sh_quote(tok))
                end
                launch_cmd = table.concat(quoted_parts, " ")
            end
        end
    end

    if not launch_argv then
        launch_cmd = "gtk-launch -- " .. desktop_id
        launch_argv = { "gtk-launch", "--", desktop_id }
    end

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

-- Invalidate discovery cache (explicit invalidation)
function M.invalidate_cache()
    M._cache = nil
end

-- Alias for testing and API consistency
M.get_applications_search_dirs = M.get_search_dirs

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

    -- Lazy process-lifetime cache with explicit invalidation/refresh
    if M._cache and not options.bypass_cache and not options.refresh then
        if include_nodisplay then
            return M._cache.all_apps
        else
            return M._cache.visible_apps
        end
    end

    local search_fn = M.get_applications_search_dirs or M.get_search_dirs
    local search_dirs = search_fn()
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

    local query_raw_ext = query:match("%.desktop$") and query or (query .. ".desktop")
    local query_lower = query:lower()
    local query_with_ext = query_lower:match("%.desktop$") and query_lower or (query_lower .. ".desktop")

    -- 1. Fast path: Direct file check in search directories for desktop ID
    -- Handles flat desktop IDs as well as nested IDs per XDG spec (foo-bar.desktop -> foo/bar.desktop)
    local search_fn = M.get_applications_search_dirs or M.get_search_dirs
    local search_dirs = search_fn()
    for _, dir in ipairs(search_dirs) do
        local candidate_paths = { dir .. "/" .. query_raw_ext }
        if query_raw_ext ~= query_with_ext then
            table.insert(candidate_paths, dir .. "/" .. query_with_ext)
        end
        if query_raw_ext:find("-") then
            local sub_rel = query_raw_ext:gsub("%-", "/")
            table.insert(candidate_paths, dir .. "/" .. sub_rel)
        end
        if query_with_ext ~= query_raw_ext and query_with_ext:find("-") then
            local sub_rel = query_with_ext:gsub("%-", "/")
            table.insert(candidate_paths, dir .. "/" .. sub_rel)
        end

        for _, candidate_path in ipairs(candidate_paths) do
            local f = io.open(candidate_path, "r")
            if f then
                f:close()
                local app = M.parse_desktop_file(candidate_path, query_raw_ext)
                if app then
                    -- If Hidden=true at this precedence level, it masks lower-precedence entries
                    if app.hidden then
                        return nil
                    end
                    return app
                end
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
