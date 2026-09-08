-- Bounded user file/folder search for the Aurelia Command Center.
--
-- The query is never interpolated into the find command. The command only
-- enumerates a bounded, same-filesystem view of HOME; matching happens on
-- NUL-delimited records in Lua so filenames cannot become shell syntax. The
-- external traversal is time-bounded so a large or damaged home directory
-- cannot pin the resident shell.

local M = {}

local MAX_RESULTS = 128
local MAX_BYTES = 1024 * 1024

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function display_name(path)
    local name = path:match("([^/]+)$")
    return name and name ~= "" and name or path
end

function M.search(query)
    local needle = trim(query):lower()
    if #needle < 2 then return {} end

    local home = trim(os.getenv("HOME") or "")
    if home == "" or home:sub(1, 1) ~= "/" or home == "/" then return {} end

    local prune = {
        "-path " .. shell_quote(home .. "/.cache"),
        "-path " .. shell_quote(home .. "/.local/share/Trash"),
        "-path '*/.git'",
        "-path '*/node_modules'",
        "-path '*/target'",
    }
    local command = "timeout --kill-after=1s 3s find " .. shell_quote(home) ..
        " -xdev -mindepth 1 -maxdepth 5 \\( " ..
        table.concat(prune, " -o ") ..
        " \\) -prune -o -printf '%y\\t%p\\0' 2>/dev/null"

    local pipe = io.popen(command, "r")
    if not pipe then return {} end

    local chunks = {}
    local bytes_read = 0
    while bytes_read < MAX_BYTES do
        local chunk = pipe:read(math.min(16384, MAX_BYTES - bytes_read))
        if not chunk or chunk == "" then break end
        table.insert(chunks, chunk)
        bytes_read = bytes_read + #chunk
    end
    pipe:close()

    local rows = {}
    local content = table.concat(chunks)
    for record in content:gmatch("([^%z]+)%z") do
        local kind, path = record:match("^(.)\t(.*)$")
        if (kind == "f" or kind == "d") and path then
            local lower_path = path:lower()
            if lower_path:find(needle, 1, true) then
                local name = display_name(path)
                local display_path = path
                if path:sub(1, #home) == home then
                    display_path = "~" .. path:sub(#home + 1)
                end
                table.insert(rows, {
                    path = path,
                    name = name,
                    display_path = display_path,
                    kind = kind == "d" and "directory" or "file",
                })
                if #rows >= MAX_RESULTS then break end
            end
        end
    end

    table.sort(rows, function(left, right)
        local left_name = left.name:lower()
        local right_name = right.name:lower()
        if left_name ~= right_name then return left_name < right_name end
        return left.path < right.path
    end)
    return rows
end

return M
