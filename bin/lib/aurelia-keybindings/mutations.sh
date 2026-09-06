#!/usr/bin/env bash
# User-data mutations and bounded desktop helpers.
#
# All persistent edits are delegated to effective_bindings.lua. Python is used
# only for the bounded file chooser/path-completion adapters.

validate_shortcut() {
    local key_input="$1"
    if [[ -z "$key_input" ]]; then
        printf '%s\n' "INVALID: missing-shortcut" >&2
        return 1
    fi
    local output
    if output="$("$lua_bin" - "$manifest_dir" "$key_input" <<'LUA_VALIDATE'
local manifest_dir = arg[1]
local key_input = arg[2]
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local ok, reason, normalized = eff.validate_shortcut_policy(key_input)
if not ok then
    io.stderr:write(tostring(reason) .. "\n")
    os.exit(1)
end
print(tostring(normalized))
LUA_VALIDATE
)"; then
        printf 'VALID: %s\n' "$output"
    else
        printf 'INVALID: %s\n' "$output" >&2
        return 1
    fi
}

add_application() {
    local desktop_id="$1"
    if [[ -z "$desktop_id" ]]; then
        printf '%s\n' "Error: Missing desktop ID for add-app" >&2
        return 1
    fi
    if [[ ! "$desktop_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*\.desktop$ ]]; then
        printf '%s\n' "Error: Invalid desktop ID: $desktop_id" >&2
        return 1
    fi

    local user_actions_path
    user_actions_path="$(get_user_actions_path)"
    local error_message
    if error_message="$("$lua_bin" - "$manifest_path" "$manifest_dir" "$desktop_id" "$user_actions_path" <<'LUA_ADD_APP'
local manifest_path = arg[1]
local manifest_dir = arg[2]
local desktop_id = arg[3]
local user_actions_path = arg[4]
if user_actions_path == "" then user_actions_path = nil end
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local ok, result = eff.add_user_application_action(desktop_id, user_actions_path)
if not ok then
    io.stderr:write(tostring(result) .. "\n")
    os.exit(1)
end
print(tostring(result))
LUA_ADD_APP
)"; then
        log_event "INFO" "Successfully added application action '$desktop_id'" "add-app"
        printf '%s\n' "ADD_APP_OK"
    else
        log_event "ERROR" "Failed to add application action '$desktop_id': $error_message" "add-app"
        printf 'ADD_APP_FAIL: %s\n' "$error_message" >&2
        return 1
    fi
}

add_executable() {
    local action_id="$1"
    local name="$2"
    local executable_path="$3"
    shift 3
    if [[ -z "$action_id" || -z "$name" || -z "$executable_path" ]]; then
        printf '%s\n' "Error: add-exec requires <id> <name> <executable_path>" >&2
        return 1
    fi
    if [[ ! "$action_id" =~ ^exec: ]]; then action_id="exec:$action_id"; fi
    if [[ ! "$action_id" =~ ^exec:[a-zA-Z0-9_.:-]+$ ]]; then
        printf '%s\n' "Error: Invalid action ID: $action_id" >&2
        return 1
    fi

    local user_actions_path
    user_actions_path="$(get_user_actions_path)"
    local argv_raw="$executable_path"$'\n'
    local arg
    for arg in "$@"; do argv_raw+="$arg"$'\n'; done

    local error_message
    if error_message="$("$lua_bin" - "$manifest_path" "$manifest_dir" "$action_id" "$name" "$executable_path" "$user_actions_path" "$argv_raw" <<'LUA_ADD_EXEC'
local manifest_path = arg[1]
local manifest_dir = arg[2]
local id = arg[3]
local name = arg[4]
local executable_path = arg[5]
local user_actions_path = arg[6]
local argv_raw = arg[7]
if user_actions_path == "" then user_actions_path = nil end
local argv = nil
if argv_raw and argv_raw ~= "" then
    argv = {}
    for line in argv_raw:gmatch("[^\r\n]+") do table.insert(argv, line) end
end
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local ok, result = eff.add_user_executable_action({
    id = id,
    name = name,
    executable_path = executable_path,
    argv = argv,
}, user_actions_path)
if not ok then
    io.stderr:write(tostring(result) .. "\n")
    os.exit(1)
end
print(tostring(result))
LUA_ADD_EXEC
)"; then
        log_event "INFO" "Successfully added executable action '$action_id' ($name)" "add-exec"
        printf '%s\n' "ADD_EXEC_OK"
    else
        log_event "ERROR" "Failed to add executable action '$action_id': $error_message" "add-exec"
        printf 'ADD_EXEC_FAIL: %s\n' "$error_message" >&2
        return 1
    fi
}

remove_user_action() {
    local action_id="$1"
    local result_name="${2:-remove-action}"
    if [[ -z "$action_id" ]]; then
        printf '%s\n' "Error: Missing action ID for remove-action" >&2
        return 1
    fi
    local user_actions_path
    user_actions_path="$(get_user_actions_path)"
    local error_message
    if error_message="$("$lua_bin" - "$manifest_dir" "$action_id" "$user_actions_path" <<'LUA_REMOVE'
local manifest_dir = arg[1]
local action_id = arg[2]
local user_actions_path = arg[3]
if user_actions_path == "" then user_actions_path = nil end
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local ok, result = eff.remove_user_action(action_id, user_actions_path)
if not ok then
    io.stderr:write(tostring(result) .. "\n")
    os.exit(1)
end
print(tostring(result))
LUA_REMOVE
    )"; then
        log_event "INFO" "Successfully removed action '$action_id'" "remove-action"
        if [[ "$result_name" == "remove-app" ]]; then
            printf '%s\n' "REMOVE_APP_OK"
        else
            printf '%s\n' "REMOVE_ACTION_OK"
        fi
    else
        log_event "ERROR" "Failed to remove action '$action_id': $error_message" "remove-action"
        printf 'REMOVE_ACTION_FAIL: %s\n' "$error_message" >&2
        return 1
    fi
}

choose_file() {
    if [[ -n "${WORKSTATION_TEST_CHOOSE_FILE:-}" ]]; then
        case "$WORKSTATION_TEST_CHOOSE_FILE" in
            cancel) return 1 ;;
            error*) printf '%s\n' "${WORKSTATION_TEST_CHOOSE_FILE#error:}" >&2; return 2 ;;
            accept:*) printf '%s\n' "${WORKSTATION_TEST_CHOOSE_FILE#accept:}"; return 0 ;;
            *) printf '%s\n' "$WORKSTATION_TEST_CHOOSE_FILE"; return 0 ;;
        esac
    fi

    python3 - <<'PY_CHOOSER'
import sys
import urllib.parse

def try_portal():
    try:
        import gi
        from gi.repository import Gio, GLib
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        result = bus.call_sync(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.FileChooser",
            "OpenFile",
            GLib.Variant("(ssa{sv})", ("", "Select Executable or Script", {
                "multiple": GLib.Variant("b", False),
            })),
            None,
            Gio.DBusCallFlags.NONE,
            2500,
            None,
        )
        handle = result.unpack()[0] if result else None
        if not handle:
            return None
        loop = GLib.MainLoop()
        response = {"code": 1, "path": None}

        def on_response(_conn, _sender, _path, _iface, _signal, params):
            code, data = params.unpack()
            response["code"] = code
            if code == 0 and data.get("uris"):
                response["path"] = urllib.parse.unquote(
                    urllib.parse.urlparse(data["uris"][0]).path
                )
            loop.quit()

        subscription = bus.signal_subscribe(
            "org.freedesktop.portal.Desktop",
            "org.freedesktop.portal.Request",
            "Response",
            handle,
            None,
            Gio.DBusSignalFlags.NONE,
            on_response,
        )
        loop.run()
        bus.signal_unsubscribe(subscription)
        return response["code"], response["path"]
    except Exception:
        return None

def try_gtk():
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
        dialog = Gtk.FileChooserDialog(
            title="Select Executable or Script",
            parent=None,
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_button("_Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("_Select", Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        response = dialog.run()
        selected = dialog.get_filename() if response == Gtk.ResponseType.OK else None
        dialog.destroy()
        while Gtk.events_pending():
            Gtk.main_iteration()
        return (0, selected) if selected else (1, None)
    except Exception as error:
        sys.stderr.write("File chooser error: " + str(error) + "\n")
        return (2, None)

portal = try_portal()
code, path = portal if portal is not None else try_gtk()
if code == 0 and path:
    print(path)
sys.exit(0 if code == 0 and path else code)
PY_CHOOSER
}

complete_path() {
    local raw_input="${1:-}"
    python3 - "$raw_input" <<'PY_COMPLETE'
import json
import os
import sys

raw_input = sys.argv[1] if len(sys.argv) > 1 else ""

def complete_path(value, max_results=15):
    unsafe = ['$', chr(96), '*', '?', '[', ';', '&', '|', '(', ')']
    if not value or any(char in value for char in unsafe):
        return []
    home = os.path.expanduser('~')
    if value == '~':
        expanded, base_display = home + '/', home + '/'
    elif value.startswith('~/'):
        expanded = home + value[1:]
        base_display = os.path.dirname(expanded) + '/'
    else:
        expanded = value
        if value.endswith('/'):
            base_display = value
        else:
            base_display = os.path.dirname(value)
            if base_display and not base_display.endswith('/'):
                base_display += '/'
    if expanded.endswith('/'):
        search_dir, prefix = expanded[:-1] or '/', ''
    else:
        search_dir, prefix = os.path.dirname(expanded) or '/', os.path.basename(expanded)
    if not os.path.isdir(search_dir):
        return []
    try:
        entries = []
        with os.scandir(search_dir) as directory:
            for entry in directory:
                if not prefix.startswith('.') and entry.name.startswith('.'):
                    continue
                if entry.name.startswith(prefix):
                    try:
                        is_dir = entry.is_dir(follow_symlinks=True)
                    except OSError:
                        is_dir = False
                    entries.append((entry.name + ('/' if is_dir else ''), is_dir))
    except (PermissionError, OSError):
        return []
    entries.sort(key=lambda item: (not item[1], item[0]))
    result = []
    for name, _ in entries[:max_results]:
        if base_display:
            result.append(base_display + name)
        else:
            result.append(('/' if value.startswith('/') else '') + name)
    return result

print(json.dumps(complete_path(raw_input)))
PY_COMPLETE
}
