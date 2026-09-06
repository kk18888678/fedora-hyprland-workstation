section "11. Role-Based Action Resolution & Dynamic Application Intent"

lua_bin="$(command -v luajit 2>/dev/null || command -v lua 2>/dev/null || true)"

# 11.1: File manager role resolves dynamically without mutating shortcut declaration
role_fm_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")

-- Default resolution
local def_fm = eff.resolve_role_default("file-manager")
local argv_def = eff.get_action_argv("file_manager", manifest)

-- Thunar override via role resolution
eff.resolve_role_default = function() return "thunar.desktop", { command_argv = { "gtk-launch", "--", "thunar.desktop" }, desktop_id = "thunar.desktop" } end
local argv_thunar = eff.get_action_argv("file_manager", manifest)

print(string.format("FM: def=%s def_launcher=%s def_target=%s thunar_launcher=%s thunar_target=%s", def_fm, argv_def[1], argv_def[3], argv_thunar[1], argv_thunar[3]))
LUA_CHECK
)"
if grep -q "FM: def=nautilus def_launcher=gtk-launch def_target=org.gnome.Nautilus.desktop thunar_launcher=gtk-launch thunar_target=thunar.desktop" <<< "$role_fm_out"; then
    pass "11.1 file manager role resolves dynamically (Nautilus vs Thunar) via gtk-launch without mutating shortcut declaration"
else
    fail "11.1 file manager dynamic resolution failed: $role_fm_out"
fi

# 11.2: Terminal role resolves dynamically (Kitty vs Foot) without mutating shortcut declaration
role_term_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")

local def_term = eff.resolve_role_default("terminal")
local argv_def = eff.get_action_argv("terminal", manifest)

eff.resolve_role_default = function() return "foot.desktop", { command_argv = { "gtk-launch", "--", "foot.desktop" }, desktop_id = "foot.desktop" } end
local argv_foot = eff.get_action_argv("terminal", manifest)

print(string.format("TERM: def=%s def_launcher=%s def_target=%s foot_launcher=%s foot_target=%s", def_term, argv_def[1], argv_def[3], argv_foot[1], argv_foot[3]))
LUA_CHECK
)"
if grep -q "TERM: def=kitty def_launcher=gtk-launch def_target=kitty.desktop foot_launcher=gtk-launch foot_target=foot.desktop" <<< "$role_term_out"; then
    pass "11.2 terminal role resolves dynamically (Kitty vs Foot) via gtk-launch without mutating shortcut declaration"
else
    fail "11.2 terminal dynamic resolution failed: $role_term_out"
fi

# 11.3: Browser role resolves dynamically (Chromium vs Firefox) without mutating shortcut declaration
role_browser_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")

local def_browser = eff.resolve_role_default("browser")
local argv_def = eff.get_action_argv("browser", manifest)

eff.resolve_role_default = function() return "firefox.desktop", { command_argv = { "gtk-launch", "--", "firefox.desktop" }, desktop_id = "firefox.desktop" } end
local argv_ff = eff.get_action_argv("browser", manifest)

print(string.format("BROWSER: def=%s def_launcher=%s def_target=%s ff_launcher=%s ff_target=%s", def_browser, argv_def[1], argv_def[3], argv_ff[1], argv_ff[3]))
LUA_CHECK
)"
if grep -q "BROWSER: def=chromium-browser def_launcher=gtk-launch def_target=chromium-browser.desktop ff_launcher=gtk-launch ff_target=firefox.desktop" <<< "$role_browser_out"; then
    pass "11.3 browser role resolves dynamically (Chromium vs Firefox) via gtk-launch without mutating shortcut declaration"
else
    fail "11.3 browser dynamic resolution failed: $role_browser_out"
fi

# 11.4: Discovered applications do not pollute the action catalogue into fake unbound actions; static catalogue actions eliminated
cat_elim_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")
eff.get_user_actions_path = function() return "/nonexistent/user_actions.json" end

-- Verify static catalogue actions are absent from manifest
local legacy_actions = { "terminal.kitty", "terminal.foot", "files.nautilus", "files.thunar", "browser.chromium", "browser.firefox" }
local present_count = 0
for _, b in ipairs(manifest.bindings or {}) do
    for _, leg in ipairs(legacy_actions) do
        if b.id == leg then present_count = present_count + 1 end
    end
end

-- Verify resolving effective bindings does not include un-added installed apps as unbound actions
local effective = eff.resolve_bindings(manifest, {})
local unadded_app_present = false
for _, b in ipairs(effective.bindings or {}) do
    if b.id and b.id:match("^app:") then
        unadded_app_present = true
    end
end

print(string.format("CATALOGUE: legacy_present=%d unadded_present=%s", present_count, tostring(unadded_app_present)))
LUA_CHECK
)"
if grep -q "CATALOGUE: legacy_present=0 unadded_present=false" <<< "$cat_elim_out"; then
    pass "11.4 static application catalogue eliminated; discovered apps do not pollute unbound actions"
else
    fail "11.4 catalogue elimination check failed: $cat_elim_out"
fi

# 11.5: desktop.conf drives role default resolution when env is not set
conf_drive_out="$("$lua_bin" - "$ROOT" <<'LUA_CHECK'
local root = arg[1]
local tmp = os.tmpname()
local f = io.open(tmp, "w")
f:write("terminal.default = foot\nfile-manager.default = thunar\nbrowser.default = firefox\n")
f:close()

package.path = root .. "/dotfiles/hypr/?.lua;" .. package.path
local eff = require("effective_bindings")
local manifest = require("keybindings_manifest")
eff.get_desktop_config_path = function() return tmp end

local r_term = eff.resolve_role_default("terminal")
local r_fm   = eff.resolve_role_default("file-manager")
local r_br   = eff.resolve_role_default("browser")

os.remove(tmp)
print(string.format("CONF: term=%s fm=%s br=%s", r_term, r_fm, r_br))
LUA_CHECK
)"
if grep -q "CONF: term=foot fm=thunar br=firefox" <<< "$conf_drive_out"; then
    pass "11.5 desktop.conf drives role default resolution without environment overrides"
else
    fail "11.5 desktop.conf driven resolution failed: $conf_drive_out"
fi
