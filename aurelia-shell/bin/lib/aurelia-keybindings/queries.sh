#!/usr/bin/env bash
# Read-only keybinding and application projections.
#
# The Lua modules remain the source of truth. These functions only select the
# projection requested by the caller and serialize it for a terminal or QML.

render_output() {
    "$lua_bin" - "$manifest_path" "$manifest_dir" <<'LUA_RENDER'
local manifest_path = arg[1]
local manifest_dir  = arg[2]
local manifest = dofile(manifest_path)

package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local effective, err = eff.resolve_bindings(manifest)
if not effective then
    io.stderr:write("Error: Keybindings overrides file is corrupt or invalid: " .. tostring(err) .. "\n")
    os.exit(1)
end

local C_RESET = "\27[0m"
local C_BOLD  = "\27[1m"
local C_DIM   = "\27[2m"
local C_FOAM  = "\27[38;2;156;207;216m"
local C_GOLD  = "\27[38;2;246;193;119m"
local C_IRIS  = "\27[38;2;196;167;231m"
local C_TEXT  = "\27[38;2;224;222;244m"
local C_MUTED = "\27[38;2;110;106;134m"

print()
print(string.format("%s%s Fedora Hyprland Workstation — Keyboard Shortcuts %s", C_BOLD, C_IRIS, C_RESET))
print(string.format("%s───────────────────────────────────────────────────────────────────%s", C_MUTED, C_RESET))

for _, cat in ipairs(effective.categories or {}) do
    local cat_items = {}
    for _, item in ipairs(effective.bindings or {}) do
        if item.category == cat then
            table.insert(cat_items, item)
        end
    end
    if #cat_items > 0 then
        print(string.format("\n%s%s%s%s", C_BOLD, C_FOAM, cat, C_RESET))
        for _, item in ipairs(cat_items) do
            local key_str = item.display_key or item.key or "None (Unbound)"
            local desc_str = item.description or ""
            local pad = 37 - #key_str
            if pad < 2 then pad = 2 end
            print(string.format("  %s%s%s%s%s%s%s", C_BOLD, C_GOLD, key_str, C_RESET,
                string.rep(" ", pad), C_TEXT, desc_str, C_RESET))
        end
    end
end

print(string.format("\n%s───────────────────────────────────────────────────────────────────%s", C_MUTED, C_RESET))
print(string.format("%sPress %sq%s%s, %sEsc%s%s, or %sCtrl+C%s%s to close.%s", C_DIM, C_BOLD, C_RESET,
    C_DIM, C_BOLD, C_RESET, C_DIM, C_BOLD, C_RESET, C_DIM, C_RESET))
LUA_RENDER
}

# ID \t DISPLAY_ROW \t KEY \t DESCRIPTION \t CATEGORY \t RUNNABLE \t EDITABLE \t COMMAND \t ACTION_TYPE
get_tsv_rows() {
    "$lua_bin" - "$manifest_path" "$manifest_dir" <<'LUA_TSV'
local manifest_path = arg[1]
local manifest_dir  = arg[2]
local manifest = dofile(manifest_path)
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local effective, err = eff.resolve_bindings(manifest)
if not effective then
    io.stderr:write("Error: Keybindings overrides file is corrupt or invalid: " .. tostring(err) .. "\n")
    os.exit(1)
end
for _, item in ipairs(effective.bindings or {}) do
    local id = item.id or ""
    local key = item.display_key or item.key or "None (Unbound)"
    local desc = item.description or ""
    local cat = item.category or ""
    local runnable = (item.runnable == true) and "true" or "false"
    local editable = (item.editable ~= false) and "true" or "false"
    local cmd = item.command or ""
    local act = item.action_type or ""
    local display_col = string.format("  %-28s  %s", key, desc)
    print(string.format("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s", id, display_col,
        key, desc, cat, runnable, editable, cmd, act))
end
LUA_TSV
}

get_action_argv() {
    local target_id="$1"
    "$lua_bin" - "$manifest_path" "$manifest_dir" "$target_id" <<'LUA_ARGV'
local manifest_path = arg[1]
local manifest_dir  = arg[2]
local target_id     = arg[3]
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = dofile(manifest_path)
local argv, err = eff.get_action_argv(target_id, manifest)
if not argv then
    io.stderr:write(tostring(err) .. "\n")
    os.exit(2)
end
for _, value in ipairs(argv) do
    io.write(value, "\0")
end
LUA_ARGV
}

get_action_description() {
    local target_id="$1"
    "$lua_bin" - "$manifest_path" "$manifest_dir" "$target_id" <<'LUA_DESCRIPTION'
local manifest_path = arg[1]
local manifest_dir  = arg[2]
local target_id     = arg[3]
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = dofile(manifest_path)
local effective, err = eff.resolve_bindings(manifest)
if not effective then os.exit(1) end
for _, item in ipairs(effective.bindings or {}) do
    if item.id == target_id then
        print(item.description or item.id)
        os.exit(0)
    end
end
os.exit(1)
LUA_DESCRIPTION
}

get_app_rows() {
    "$lua_bin" - "$manifest_path" "$manifest_dir" <<'LUA_APP_ROWS'
local manifest_path = arg[1]
local manifest_dir  = arg[2]
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = dofile(manifest_path)
local apps = eff.list_installed_applications()
local effective = eff.resolve_bindings(manifest)
local assigned_keys = {}
for _, item in ipairs(effective.bindings or {}) do
    if item.desktop_id then
        assigned_keys[item.desktop_id] = item.display_key or item.key or "Unbound"
    end
end
for _, app in ipairs(apps) do
    local desktop_id = app.desktop_id
    local name = app.name or desktop_id
    local role = app.default_role or ""
    local shortcut = assigned_keys[desktop_id] or "None"
    local pad = 35 - #name
    if pad < 2 then pad = 2 end
    local role_badge = (role ~= "") and (" [" .. role .. "]") or ""
    local display_col = string.format("%s%s%-24s%s", name, string.rep(" ", pad),
        "[" .. shortcut .. "]", role_badge)
    print(string.format("%s\t%s\t%s\t%s\t%s", desktop_id, display_col, name, shortcut, role))
end
LUA_APP_ROWS
}

get_json_rows() {
    "$lua_bin" - "$manifest_path" "$manifest_dir" <<'LUA_JSON'
local manifest_path = arg[1]
local manifest_dir  = arg[2]
local manifest = dofile(manifest_path)
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local effective, err = eff.resolve_bindings(manifest)
if not effective then
    io.stderr:write("Error: " .. tostring(err) .. "\n")
    os.exit(1)
end
io.write(eff.serialize_bindings_json(effective))
LUA_JSON
}

get_apps_json() {
    "$lua_bin" - "$manifest_dir" <<'LUA_APPS_JSON'
local manifest_dir = arg[1]
package.path = manifest_dir .. "/?.lua;" .. package.path
local reg = require("application_registry")
local apps = reg.list_applications()
local parts = {"[\n"}
for index, app in ipairs(apps) do
    local fields = {
        string.format('    "desktop_id": %q', app.desktop_id or ""),
        string.format('    "name": %q', app.name or ""),
        string.format('    "generic_name": %q', app.generic_name or ""),
        string.format('    "comment": %q', app.comment or ""),
        string.format('    "icon": %q', app.icon or ""),
        string.format('    "categories": %q', app.categories or ""),
        string.format('    "default_role": %q', app.default_role or ""),
        string.format('    "source": %q', app.source or "")
    }
    local item = "  {\n" .. table.concat(fields, ",\n") .. "\n  }"
    if index < #apps then item = item .. "," end
    table.insert(parts, item .. "\n")
end
table.insert(parts, "]\n")
io.write(table.concat(parts))
LUA_APPS_JSON
}

get_application_launch_argv() {
    local desktop_id="$1"
    "$lua_bin" - "$manifest_dir" "$desktop_id" <<'LUA_APPLICATION_LAUNCH'
local manifest_dir = arg[1]
local desktop_id = arg[2]
package.path = manifest_dir .. "/?.lua;" .. package.path
local reg = require("application_registry")
local argv, info_or_error = reg.resolve_application_launch_argv(desktop_id)
if not argv then
    io.stderr:write(tostring(info_or_error) .. "\n")
    os.exit(2)
end
for _, value in ipairs(argv) do
    io.write(value, "\0")
end
LUA_APPLICATION_LAUNCH
}

get_path_launch_argv() {
    local path="$1"
    "$lua_bin" - "$manifest_dir" "$path" <<'LUA_PATH_LAUNCH'
local manifest_dir = arg[1]
local path = arg[2]
package.path = manifest_dir .. "/?.lua;" .. package.path
local reg = require("application_registry")
local executable = reg.resolve_in_path("xdg-open")
if not executable then
    io.stderr:write("xdg-open is not installed or executable\n")
    os.exit(2)
end
local argv, err = reg.wrap_session_argv({ executable, path })
if not argv then
    io.stderr:write(tostring(err) .. "\n")
    os.exit(2)
end
for _, value in ipairs(argv) do
    io.write(value, "\0")
end
LUA_PATH_LAUNCH
}

get_application_description() {
    local desktop_id="$1"
    "$lua_bin" - "$manifest_dir" "$desktop_id" <<'LUA_APPLICATION_DESCRIPTION'
local manifest_dir = arg[1]
local desktop_id = arg[2]
package.path = manifest_dir .. "/?.lua;" .. package.path
local reg = require("application_registry")
local info = reg.find_application(desktop_id)
if not info then os.exit(1) end
print(info.name or desktop_id)
LUA_APPLICATION_DESCRIPTION
}

get_files_json() {
    local query="$1"
    "$lua_bin" - "$manifest_dir" "$query" <<'LUA_FILES_JSON'
local manifest_dir = arg[1]
local query = arg[2]
package.path = manifest_dir .. "/?.lua;" .. package.path
local search = require("file_search")
local rows = search.search(query)
local parts = {"[\n"}
for index, row in ipairs(rows) do
    local fields = {
        string.format('    "path": %q', row.path or ""),
        string.format('    "name": %q', row.name or ""),
        string.format('    "display_path": %q', row.display_path or ""),
        string.format('    "kind": %q', row.kind or "file")
    }
    local item = "  {\n" .. table.concat(fields, ",\n") .. "\n  }"
    if index < #rows then item = item .. "," end
    table.insert(parts, item .. "\n")
end
table.insert(parts, "]\n")
io.write(table.concat(parts))
LUA_FILES_JSON
}
