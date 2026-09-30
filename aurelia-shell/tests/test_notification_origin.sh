#!/usr/bin/env bash

# Notification-origin capture and navigation contract.
#
# Deterministic and hermetic: the correlation state machine is fed recorded
# tuples with no bus, and the resolver runs against PATH-injected fake
# hyprctl/herdr/tmux plus a fake /proc root and a private herdr socket.  No live
# workstation state is read or mutated.

set -Eeuo pipefail

section "Notification Origin Capture and Navigation"

HELPER="$ROOT/bin/workstation-notification-focus"
SHIM="$ROOT/bin/workstation-herdr-focus"
UNIT="$ROOT/systemd/user/workstation-notification-origin.service"
INSTALLER_DESKTOP="$ROOT/../modules/desktop.sh"
INSTALLER_ENTRY="$ROOT/../install.sh"

announce_checks() {
    local label="$1"
    local output="$2"
    while IFS= read -r line; do
        case "$line" in
            "CHECK PASS "*) pass "[$label] ${line#CHECK PASS }" ;;
            "CHECK FAIL "*) fail "[$label] ${line#CHECK FAIL }" ;;
        esac
    done <<<"$output"
    if [[ "$output" != *"CHECK DONE"* ]]; then
        fail "[$label] check harness did not complete"
    fi
}

# ---------------------------------------------------------------------------
# Static ownership and packaging contract
# ---------------------------------------------------------------------------

if [[ -x "$HELPER" ]] && head -n 1 "$HELPER" | grep -q 'python3'; then
    pass "[static] the single origin owner is an executable Python 3 helper"
else
    fail "[static] the origin helper is missing or not executable"
fi

if grep -q 'def resolve_tool(' "$HELPER" &&
   grep -q 'def resolve_tool_path(' "$HELPER" &&
   grep -q 'def tool_environment(' "$HELPER" &&
   grep -q 'AURELIA_TOOL_' "$HELPER" &&
   ! grep -q 'shutil.which' "$HELPER"; then
    pass "[static] the helper resolves every external tool through the deterministic resolver, never shutil.which"
else
    fail "[static] the helper still resolves tools through the inherited environment"
fi

if [[ -x "$SHIM" ]] &&
   grep -q 'workstation-notification-focus' "$SHIM" &&
   grep -q '"navigate"' "$SHIM" &&
   ! grep -q 'hyprctl' "$SHIM"; then
    pass "[static] the herdr focus compatibility shim delegates to navigate with no duplicate focus logic"
else
    fail "[static] the herdr focus shim is missing or still owns focus logic"
fi

if grep -q 'BecomeMonitor' "$HELPER" &&
   grep -q "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" "$HELPER" &&
   grep -q "type='method_return',sender='org.freedesktop.Notifications'" "$HELPER" &&
   grep -q 'GetConnectionUnixProcessID' "$HELPER" &&
   grep -q 'timeout=2.0' "$HELPER" &&
   grep -q 'timeout=5.0' "$HELPER" &&
   ! grep -q 'eavesdrop' "$HELPER"; then
    pass "[static] capture uses BecomeMonitor with exactly the two scoped rules and kernel-backed pid resolution"
else
    fail "[static] capture does not use the approved scoped monitoring mechanism"
fi

if grep -q 'herdr_pane_focus' "$HELPER" && grep -q 'herdr_focus_cli("agent"' "$HELPER"; then
    pass "[static] navigation supports the raw arbitrary-pane focus path and the agent fallback"
else
    fail "[static] navigation pane focus path is incomplete"
fi

if [[ -f "$UNIT" ]] &&
   grep -Fq 'ExecStart=/usr/local/bin/workstation-notification-focus serve' "$UNIT" &&
   grep -Fq 'After=dbus-broker.service' "$UNIT" &&
   grep -Fq 'WantedBy=graphical-session.target' "$UNIT" &&
   grep -Fq 'Restart=on-failure' "$UNIT" &&
   ! grep -Eq '^User=|^Group=|^PermissionsStartOnly=|^AmbientCapabilities=|^CapabilityBoundingSet=' "$UNIT"; then
    pass "[static] the monitor unit is an unprivileged graphical-session user service"
else
    fail "[static] the monitor unit is missing or requests privileges"
fi

if grep -q 'retire_notification_origin_unit()' "$INSTALLER_DESKTOP" &&
   ! grep -q 'validate_notification_origin_installation' "$INSTALLER_DESKTOP" &&
   ! grep -q 'validate_notification_origin_unit' "$INSTALLER_DESKTOP" &&
   grep -q 'graphical-session.target.wants/workstation-notification-origin.service' "$INSTALLER_DESKTOP" &&
   grep -q "rm -f -- \"\$unit_target\"" "$INSTALLER_DESKTOP" &&
   grep -q "rm -f -- \"\$wants_link\"" "$INSTALLER_DESKTOP" &&
   ! grep -q 'chown -R' "$INSTALLER_DESKTOP"; then
    pass "[static] the installer retires a stale notification-origin unit and never installs or enables it"
else
    fail "[static] the installer does not retire the notification-origin unit safely"
fi

if grep -q 'install_notification_origin' "$INSTALLER_DESKTOP" "$INSTALLER_ENTRY"; then
    fail "[static] the retired notification-origin install step is still referenced by the installer"
else
    pass "[static] the retired notification-origin install step is gone from the installer path"
fi

if grep -Eq 'run_classified_step optional "Retiring notification origin monitor unit" retire_notification_origin_unit' "$INSTALLER_ENTRY" &&
   ! grep -Eq 'run_classified_step login .*retire_notification_origin_unit' "$INSTALLER_ENTRY"; then
    pass "[static] notification-origin retirement is a non-blocking installer step, never login-critical"
else
    fail "[static] notification-origin retirement is not classified as a non-blocking installer step"
fi

# ---------------------------------------------------------------------------
# Correlation state machine (no bus required)
# ---------------------------------------------------------------------------

correlation_out="$(python3 - "$HELPER" <<'PY_CORRELATION' || true
import importlib.machinery
import importlib.util
import sys

helper = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("wnf", helper)
spec = importlib.util.spec_from_loader("wnf", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)


def check(name, condition):
    print(("CHECK PASS " if condition else "CHECK FAIL ") + name)


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


# Normal case: a call is correlated to its reply id.
clock = Clock()
table = m.CorrelationTable(ttl_seconds=100, clock=clock)
table.begin_call(":1.5", 9, {"appName": "App", "summary": "s", "body": "b"})
origin = table.complete_call(":1.5", 9, 50)
check(
    "normal call/reply maps the exact sender to the reply id",
    origin is not None
    and table.get(50) is not None
    and table.get(50)["sender"]["uniqueName"] == ":1.5"
    and table.get(50)["notifyId"] == 50,
)

# A reply that never arrives produces no origin and expires from pending.
clock2 = Clock()
table2 = m.CorrelationTable(ttl_seconds=10, clock=clock2)
table2.begin_call(":1.6", 3, {"appName": "X"})
check("a reply that never arrives yields no origin", table2.get(3) is None and table2.pending_count() == 1)
clock2.t = 11.0
check("pending correlation state expires with its TTL", table2.pending_count() == 0)

# Id reuse via a replacement: the newest mapping wins.
clock3 = Clock()
table3 = m.CorrelationTable(ttl_seconds=100, clock=clock3)
table3.begin_call(":1.7", 1, {"appName": "A"})
table3.complete_call(":1.7", 1, 7)
table3.begin_call(":1.8", 2, {"appName": "B"})
table3.complete_call(":1.8", 2, 7)
check(
    "an id reused by a replacement resolves to the newest sender",
    table3.get(7) is not None
    and table3.get(7)["sender"]["uniqueName"] == ":1.8"
    and table3.origin_count() == 1,
)

# Two byte-identical concurrent notifications that share a serial number but
# have different senders must not collide.
clock4 = Clock()
table4 = m.CorrelationTable(ttl_seconds=100, clock=clock4)
table4.begin_call(":1.10", 9, {"appName": "same", "summary": "s", "body": "b"})
table4.begin_call(":1.11", 9, {"appName": "same", "summary": "s", "body": "b"})
table4.complete_call(":1.10", 9, 100)
table4.complete_call(":1.11", 9, 101)
check(
    "identical concurrent notifications with a shared serial resolve distinctly",
    table4.get(100) is not None
    and table4.get(100)["sender"]["uniqueName"] == ":1.10"
    and table4.get(101) is not None
    and table4.get(101)["sender"]["uniqueName"] == ":1.11"
    and table4.origin_count() == 2,
)

# Many interleaved calls and replies.
clock5 = Clock()
table5 = m.CorrelationTable(ttl_seconds=100, max_entries=1000, clock=clock5)
count = 100
for index in range(count):
    table5.begin_call(":1.%d" % (1000 + index), index, {"appName": "app%d" % index})
for index in range(count):
    table5.complete_call(":1.%d" % (1000 + index), index, index)
ok = all(
    table5.get(index) is not None
    and table5.get(index)["sender"]["uniqueName"] == ":1.%d" % (1000 + index)
    and table5.get(index)["notify"]["appName"] == "app%d" % index
    for index in range(count)
)
check("many interleaved notifications correlate without loss", ok and table5.origin_count() == count)

# The table is bounded.
clock6 = Clock()
table6 = m.CorrelationTable(ttl_seconds=100, max_entries=3, clock=clock6)
for index in range(5):
    table6.begin_call(":1.%d" % index, index, {})
    table6.complete_call(":1.%d" % index, index, index)
check("the origin table is bounded", table6.origin_count() == 3 and table6.get(0) is None)

# Bounded focus-relevant hints only.
hints = m.bounded_hints(
    {
        "desktop-entry": "chromium-browser",
        "urgency": 1,
        "image-data": [1, 2, 3],
        "sender-pid": 4242,
        "unrelated": "secret",
    }
)
check(
    "notify hints are bounded to focus-relevant keys",
    set(hints.keys()) == {"desktop-entry", "urgency", "sender-pid"},
)

# A reply destination that the bus did not expose resolves only when the
# serial is unambiguous.
clock7 = Clock()
table7 = m.CorrelationTable(ttl_seconds=100, clock=clock7)
table7.begin_call(":1.20", 4, {})
check(
    "a missing reply destination resolves only when the serial is unambiguous",
    table7.complete_call(None, 4, 200) is not None and table7.get(200) is not None,
)
clock8 = Clock()
table8 = m.CorrelationTable(ttl_seconds=100, clock=clock8)
table8.begin_call(":1.21", 4, {})
table8.begin_call(":1.22", 4, {})
check(
    "a missing reply destination with an ambiguous serial resolves nothing",
    table8.complete_call(None, 4, 201) is None,
)

print("CHECK DONE")
PY_CORRELATION
)"
announce_checks "unit" "$correlation_out"

# ---------------------------------------------------------------------------
# /proc parsing contract
# ---------------------------------------------------------------------------

proc_out="$(python3 - "$HELPER" <<'PY_PROC' || true
import importlib.machinery
import importlib.util
import os
import sys
import tempfile

helper = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("wnf", helper)
spec = importlib.util.spec_from_loader("wnf", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)


def check(name, condition):
    print(("CHECK PASS " if condition else "CHECK FAIL ") + name)


root = tempfile.mkdtemp(prefix="aurelia-proc-")


def write_proc(pid, name, data, binary=False):
    directory = os.path.join(root, str(pid))
    os.makedirs(directory, exist_ok=True)
    if binary:
        mode = "wb"
        if isinstance(data, str):
            data = data.encode("utf-8")
    else:
        mode = "w"
    with open(os.path.join(directory, name), mode) as handle:
        handle.write(data)


write_proc(100, "comm", "notify-send\n")
write_proc(100, "cmdline", "notify-send\0--app-name\0Chromium\0", binary=True)
write_proc(100, "stat", "100 (notify-send) S 90 100 100 0 -1 4194304 0 0 0 0\n")
write_proc(100, "cgroup", "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-org.chromium.Chromium-5878.scope\n")
write_proc(
    100,
    "environ",
    "HERDR_WORKSPACE_ID=w21\0HERDR_TAB_ID=w21:t2\0HERDR_PANE_ID=w21:p2\0PATH=/usr/bin\0",
    binary=True,
)
try:
    os.symlink("/usr/bin/notify-send", os.path.join(root, "100", "exe"))
except OSError:
    pass
write_proc(90, "comm", "foot\n")
write_proc(90, "cmdline", "foot\0", binary=True)
write_proc(90, "stat", "90 (foot) S 1 90 90 0 -1 4194304 0 0 0 0\n")
write_proc(100, "status", "Name:\tnotify-send\nUid:\t1000\t1000\t1000\t1000\n")

cgroup = m.read_cgroup(100, root)
check("cgroup is read", cgroup is not None and "app-org.chromium.Chromium" in cgroup)
check("systemd scope app id is derived", m.derive_app_id(cgroup) == "org.chromium.Chromium")
flatpak = m.derive_app_id("0::/user.slice/app-flatpak-com.ulaa.Ulaa-1234.scope")
check("flatpak scope app id is derived", flatpak == "flatpak-com.ulaa.Ulaa")
check("flatpak id is derived", m.derive_flatpak_id(flatpak) == "com.ulaa.Ulaa")
check("pid source uid is read", m.read_uid(100, root) == 1000)
env = m.read_focus_env(100, root)
check(
    "focus environment is captured and bounded",
    env == {"HERDR_WORKSPACE_ID": "w21", "HERDR_TAB_ID": "w21:t2", "HERDR_PANE_ID": "w21:p2"},
)
tab = m.tab_from_focus_env(env)
check(
    "herdr focus environment yields the tab identity",
    tab["kind"] == "herdr" and tab["tabId"] == "w21:t2" and tab["paneId"] == "w21:p2",
)
ancestry = m.walk_ancestry(100, root, limit=4)
check(
    "ancestry walks up to the terminal ancestor",
    any(entry["comm"] == "notify-send" for entry in ancestry)
    and any(entry["comm"] == "foot" for entry in ancestry),
)
check("cmdline is read as argv", "notify-send" in m.read_cmdline(100, root))

origin = m.new_origin(notify_id=7)
m.capture_process(origin, 100, "dbus", hyprctl_path=None, root=root, snapshot=None)
check(
    "capture_process records the sender identity and herdr tab",
    origin["sender"]["pid"] == 100
    and origin["sender"]["appId"] == "org.chromium.Chromium"
    and origin["tab"]["kind"] == "herdr"
    and origin["tab"]["paneId"] == "w21:p2",
)

print("CHECK DONE")
PY_PROC
)"
announce_checks "proc" "$proc_out"

# ---------------------------------------------------------------------------
# Navigation resolver with PATH-injected fakes and a private herdr socket
# ---------------------------------------------------------------------------

resolver_out="$(python3 - "$HELPER" "$SHIM" <<'PY_RESOLVER' || true
import importlib.machinery
import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time

helper = sys.argv[1]
shim = sys.argv[2]
loader = importlib.machinery.SourceFileLoader("wnf", helper)
spec = importlib.util.spec_from_loader("wnf", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)

sandbox = tempfile.mkdtemp(prefix="aurelia-origin-")
bindir = os.path.join(sandbox, "bin")
os.makedirs(bindir, exist_ok=True)
procroot = os.path.join(sandbox, "proc")
os.makedirs(procroot, exist_ok=True)
logpath = os.path.join(sandbox, "calls.log")
clients_file = os.path.join(sandbox, "clients.json")
schema_with = os.path.join(sandbox, "schema-with.json")
schema_without = os.path.join(sandbox, "schema-without.json")
sockpath = os.path.join(sandbox, "herdr.sock")


def check(name, condition):
    print(("CHECK PASS " if condition else "CHECK FAIL ") + name)


def write_exe(name, content):
    path = os.path.join(bindir, name)
    with open(path, "w") as handle:
        handle.write(content)
    os.chmod(path, 0o755)


write_exe(
    "hyprctl",
    "#!/usr/bin/env bash\n"
    "set -euo pipefail\n"
    'printf \'%s\\n\' "hyprctl $*" >> "$FAKE_LOG"\n'
    'case "${1:-}" in\n'
    '  clients) cat "$FAKE_CLIENTS" ;;\n'
    '  activewindow) if [ -n "${FAKE_ACTIVE:-}" ] && [ -f "$FAKE_ACTIVE" ]; then cat "$FAKE_ACTIVE"; else printf \'{}\\n\'; fi ;;\n'
    '  dispatch)\n'
    '    if [ "${FAKE_DISPATCH_MODE:-ok}" = "warn" ]; then\n'
    "      printf 'warning: hl.focus: window not found\\n'\n"
    "    else\n"
    "      printf 'ok\\n'\n"
    "    fi ;;\n"
    "  *) printf '{}\\n' ;;\n"
    "esac\n",
)

write_exe(
    "herdr",
    "#!/usr/bin/env bash\n"
    "set -euo pipefail\n"
    'printf \'%s\\n\' "herdr $*" >> "$FAKE_LOG"\n'
    'if [ "${1:-}" = "api" ] && [ "${2:-}" = "schema" ]; then cat "$FAKE_HERDR_SCHEMA"; exit 0; fi\n'
    'if [ "${1:-}" = "workspace" ] || [ "${1:-}" = "tab" ] || [ "${1:-}" = "agent" ]; then\n'
    '  case ",${FAKE_HERDR_ERROR_KINDS:-}," in *",${1:-},"*)\n'
    '    printf \'{"error":{"code":"%s_not_found","message":"missing"}}\\n\' "$1"\n'
    "    exit 0;;\n"
    "  esac\n"
    '  printf \'{"result":{"focused":true}}\\n\'\n'
    "  exit 0\n"
    "fi\n"
    "printf '{}\\n'\n",
)

write_exe(
    "tmux",
    "#!/usr/bin/env bash\n"
    'printf \'%s\\n\' "tmux $*" >> "$FAKE_LOG"\n'
    'case "${1:-}" in\n'
    '  select-window) [ "${FAKE_TMUX_FAIL_WINDOW:-0}" = "1" ] && exit 1; exit 0 ;;\n'
    '  select-pane) [ "${FAKE_TMUX_FAIL_PANE:-0}" = "1" ] && exit 1; exit 0 ;;\n'
    "esac\n"
    "exit 0\n",
)

with open(schema_with, "w") as handle:
    json.dump(
        {
            "protocol": 22,
            "schema_version": 1,
            "schemas": {"request": {"oneOf": [{"properties": {"method": {"const": "pane.focus"}}}]}},
        },
        handle,
    )
with open(schema_without, "w") as handle:
    json.dump(
        {
            "protocol": 22,
            "schema_version": 1,
            "schemas": {"request": {"oneOf": [{"properties": {"method": {"const": "workspace.focus"}}}]}},
        },
        handle,
    )


class FakeHerdrServer(threading.Thread):
    def __init__(self, path, responder):
        super().__init__(daemon=True)
        self.path = path
        self.responder = responder
        self.requests = []
        self._stop = threading.Event()
        self._sock = None

    def run(self):
        if os.path.exists(self.path):
            os.unlink(self.path)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock = server
        server.bind(self.path)
        server.listen(8)
        server.settimeout(0.3)
        while not self._stop.is_set():
            try:
                conn, _ = server.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            data = b""
            try:
                conn.settimeout(1.0)
                while b"\n" not in data:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                request = json.loads(data.split(b"\n", 1)[0].decode("utf-8"))
                self.requests.append(request)
                conn.sendall((json.dumps(self.responder(request)) + "\n").encode("utf-8"))
            except Exception:
                pass
            finally:
                try:
                    conn.close()
                except Exception:
                    pass

    def stop(self):
        self._stop.set()
        if self._sock is not None:
            try:
                self._sock.close()
            except Exception:
                pass
        try:
            if os.path.exists(self.path):
                os.unlink(self.path)
        except Exception:
            pass


base_env = dict(os.environ)
base_env["PATH"] = bindir + ":" + base_env.get("PATH", "")
base_env["FAKE_LOG"] = logpath
base_env["AURELIA_PROC_ROOT"] = procroot
base_env["AURELIA_NOTIFICATION_ORIGIN_SOCKET"] = os.path.join(sandbox, "absent.sock")
# Pin the deterministic resolver to the sandbox fakes and an empty shell/home so
# no assertion can pass because a real host tool happened to be on PATH.
base_env["HOME"] = os.path.join(sandbox, "home")
os.makedirs(base_env["HOME"], exist_ok=True)
base_env["AURELIA_SHELL_ROOT"] = os.path.join(sandbox, "shell")
os.makedirs(base_env["AURELIA_SHELL_ROOT"], exist_ok=True)
base_env["AURELIA_TOOL_HYPRCTL_BIN"] = os.path.join(bindir, "hyprctl")
base_env["AURELIA_TOOL_HERDR_BIN"] = os.path.join(bindir, "herdr")
base_env["AURELIA_TOOL_TMUX_BIN"] = os.path.join(bindir, "tmux")


def set_clients(clients):
    with open(clients_file, "w") as handle:
        json.dump(clients, handle)
    base_env["FAKE_CLIENTS"] = clients_file


def reset_log():
    with open(logpath, "w"):
        pass


def read_log():
    try:
        with open(logpath) as handle:
            return handle.read()
    except Exception:
        return ""


def navigate(origin, extra_env=None, dry_run=False):
    env = dict(base_env)
    if extra_env:
        env.update(extra_env)
    argv = [sys.executable, helper, "navigate", "--origin", json.dumps(origin)]
    if dry_run:
        argv.append("--dry-run")
    result = subprocess.run(argv, capture_output=True, text=True, timeout=20, env=env)
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    try:
        return json.loads(lines[-1]), result
    except Exception:
        return None, result


# 1. hyprctl exits 0 while printing a warning: that is not success.
set_clients([])
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "exact",
    "compositor": {"address": "0xdead", "workspaceId": 1, "workspaceName": "1"},
    "tab": {"kind": None},
}
out, result = navigate(origin, {"FAKE_DISPATCH_MODE": "warn"})
check(
    "hyprctl warning output is not success despite exit 0",
    result.returncode == 0 and out is not None and out["outcome"] == "unavailable",
)

# 2. Address beats an ambiguous shared pid.
clients = [
    {
        "address": "0xaaa",
        "class": "code",
        "initialClass": "code",
        "title": "a",
        "pid": 777,
        "workspace": {"id": 1, "name": "1"},
        "focusHistoryID": 1,
        "mapped": True,
    },
    {
        "address": "0xbbb",
        "class": "code",
        "initialClass": "code",
        "title": "b",
        "pid": 777,
        "workspace": {"id": 2, "name": "2"},
        "focusHistoryID": 0,
        "mapped": True,
    },
]
set_clients(clients)
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "exact",
    "compositor": {"address": "0xbbb", "pid": 777, "class": "code"},
    "tab": {"kind": None},
}
out, _ = navigate(origin, {"FAKE_DISPATCH_MODE": "ok"})
log = read_log()
check(
    "address beats an ambiguous shared pid",
    out is not None and out["outcome"] == "focused" and out["window"]["address"] == "0xbbb",
)
check(
    "the address selector was used, not the shared pid",
    "address:0xbbb" in log and "address:0xaaa" not in log and "pid:777" not in log,
)

# 3. A shared pid is not an identity.
set_clients(clients)
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "identity",
    "compositor": {"pid": 777},
    "tab": {"kind": None},
}
out, _ = navigate(origin, {"FAKE_DISPATCH_MODE": "ok"})
check("a shared pid is never used as an identity", out is not None and out["outcome"] == "unavailable")

# 4. A unique pid is used.
set_clients(
    [
        {
            "address": "0xccc",
            "class": "foot",
            "initialClass": "foot",
            "pid": 888,
            "workspace": {"id": 3, "name": "3"},
            "focusHistoryID": 0,
            "mapped": True,
        }
    ]
)
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "identity",
    "compositor": {"pid": 888},
    "tab": {"kind": None},
}
out, _ = navigate(origin, {"FAKE_DISPATCH_MODE": "ok"})
check(
    "pid is used only when exactly one client matches",
    out is not None and out["outcome"] == "focused" and "pid:888" in read_log(),
)

# 5. A window that moved workspaces follows the live address.
set_clients(
    [
        {
            "address": "0xddd",
            "class": "foot",
            "initialClass": "foot",
            "pid": 900,
            "workspace": {"id": 5, "name": "5"},
            "focusHistoryID": 0,
            "mapped": True,
        }
    ]
)
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "exact",
    "compositor": {"address": "0xddd", "workspaceId": 2, "workspaceName": "2", "pid": 900},
    "tab": {"kind": None},
}
out, _ = navigate(origin, {"FAKE_DISPATCH_MODE": "ok"})
log = read_log()
check(
    "a window that moved workspaces resolves as focused",
    out is not None and out["outcome"] == "focused" and out["window"]["workspaceId"] == 5,
)
check("the moved window is focused by address", "address:0xddd" in log)
check(
    "the stale recorded workspace is not used",
    'workspace = "2"' not in log and "dispatch workspace 2" not in log,
)

# 6. A closed window degrades honestly.
set_clients([])
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "exact",
    "compositor": {"address": "0xclosed", "workspaceId": 1, "workspaceName": "1"},
    "tab": {"kind": None},
}
out, _ = navigate(origin, {"FAKE_DISPATCH_MODE": "ok"})
check(
    "a closed window degrades to the recorded workspace",
    out is not None and out["outcome"] == "routed" and out["confidence"] == "identity",
)
out, _ = navigate(origin, {"FAKE_DISPATCH_MODE": "warn"})
check(
    "a missing target with a refused workspace stays unavailable, never success",
    out is not None and out["outcome"] == "unavailable",
)

# 7. herdr error JSON is not success despite exit 0.
set_clients([])
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "identity",
    "compositor": {},
    "tab": {"kind": "herdr", "workspaceId": "w1", "tabId": "w1:t1", "paneId": None},
}
out, _ = navigate(
    origin,
    {
        "FAKE_HERDR_SCHEMA": schema_without,
        "FAKE_HERDR_ERROR_KINDS": "workspace,tab",
    },
)
check(
    "herdr error JSON is not success despite exit 0",
    out is not None and out["outcome"] == "unavailable" and out["tab"]["applied"] is False,
)

# 8. Arbitrary non-agent pane via the raw API.
server = FakeHerdrServer(sockpath, lambda request: {"id": request.get("id"), "result": {"focused": True}})
server.start()
time.sleep(0.1)
set_clients([])
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "identity",
    "compositor": {},
    "tab": {"kind": "herdr", "workspaceId": "w1", "tabId": "w1:t1", "paneId": "w1:p2"},
}
out, _ = navigate(
    origin,
    {
        "FAKE_HERDR_SCHEMA": schema_with,
        "HERDR_SOCKET": sockpath,
    },
)
check(
    "an arbitrary non-agent pane is focused via the raw API",
    out is not None and out["outcome"] == "focused" and out["tab"]["exact"] is True,
)
check(
    "the raw pane.focus used the exact captured pane id",
    bool(server.requests)
    and server.requests[-1].get("method") == "pane.focus"
    and server.requests[-1].get("params", {}).get("pane_id") == "w1:p2",
)

# 9. Missing pane.focus degrades fail-closed to tab level.
set_clients([])
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "identity",
    "compositor": {},
    "tab": {"kind": "herdr", "workspaceId": "w1", "tabId": "w1:t1", "paneId": "w1:p2"},
}
out, _ = navigate(
    origin,
    {
        "FAKE_HERDR_SCHEMA": schema_without,
        "FAKE_HERDR_ERROR_KINDS": "agent",
        "HERDR_SOCKET": sockpath,
    },
)
check(
    "a genuinely unavailable pane.focus degrades to tab level without claiming focus",
    out is not None
    and out["outcome"] == "routed"
    and out["tab"]["applied"] is True
    and out["tab"]["exact"] is False,
)
server.stop()

# 10. tmux window and pane selection.
set_clients([])
reset_log()
origin = {
    "originVersion": 1,
    "captureQuality": "identity",
    "compositor": {},
    "tab": {"kind": "tmux", "tabId": "@1", "paneId": "%2"},
}
out, _ = navigate(origin, {})
log = read_log()
check(
    "tmux window and pane are selected",
    out is not None and out["outcome"] == "focused" and out["tab"]["exact"] is True,
)
check(
    "tmux commands target the captured window and pane",
    "tmux select-window -t @1" in log and "tmux select-pane -t %2" in log,
)

# 11. tmux pane failure degrades to routed.
out, _ = navigate(origin, {"FAKE_TMUX_FAIL_PANE": "1"})
check(
    "a tmux pane failure degrades to routed, never a silent success",
    out is not None and out["outcome"] == "routed" and out["tab"]["exact"] is False,
)

# 12. A missing origin is an explicit none, not a silent no-op.
set_clients([])
out, _ = navigate({})
check(
    "a missing origin reports none",
    out is not None and out["outcome"] == "none" and out["confidence"] == "none",
)

# 13. capture identity fallback with no monitor.
capture_env = dict(base_env)
capture_env["AURELIA_NOTIFICATION_ORIGIN_SOCKET"] = os.path.join(sandbox, "absent.sock")
result = subprocess.run(
    [sys.executable, helper, "capture", "--id", "5", "--app", "X", "--summary", "s"],
    capture_output=True,
    text=True,
    timeout=10,
    env=capture_env,
)
data = json.loads(result.stdout.strip().splitlines()[-1])
check(
    "capture with an absent monitor falls back to identity and never fails",
    result.returncode == 0 and data["captureQuality"] == "identity" and data["notifyId"] == 5,
)

# 14. A body-recovered page origin is labeled origin, never exact.
result = subprocess.run(
    [
        sys.executable,
        helper,
        "capture",
        "--id",
        "6",
        "--body",
        '<a href="http://127.0.0.1:8899/page?x=1">127.0.0.1:8899</a>',
    ],
    capture_output=True,
    text=True,
    timeout=10,
    env=capture_env,
)
data = json.loads(result.stdout.strip().splitlines()[-1])
check(
    "a body-recovered origin is labeled origin, never exact",
    result.returncode == 0
    and data["captureQuality"] == "origin"
    and data["originUrl"] == "http://127.0.0.1:8899",
)

# 15. The capture wait is bounded even when the monitor never answers.
hang_path = os.path.join(sandbox, "hang.sock")
hanger = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
hanger.bind(hang_path)
hanger.listen(4)
hang_env = dict(base_env)
hang_env["AURELIA_NOTIFICATION_ORIGIN_SOCKET"] = hang_path
started = time.monotonic()
result = subprocess.run(
    [sys.executable, helper, "capture", "--id", "7", "--timeout-ms", "150"],
    capture_output=True,
    text=True,
    timeout=10,
    env=hang_env,
)
elapsed = time.monotonic() - started
hanger.close()
data = json.loads(result.stdout.strip().splitlines()[-1])
check(
    "the capture wait is bounded and returns identity",
    elapsed < 2.0 and result.returncode == 0 and data["captureQuality"] == "identity",
)

# 16. The compatibility shim delegates to the single focus owner.
set_clients([])
reset_log()
result = subprocess.run(
    [sys.executable, shim, "2"], capture_output=True, text=True, timeout=20, env=base_env
)
data = json.loads(result.stdout.strip().splitlines()[-1])
check(
    "the herdr compatibility shim delegates to navigate",
    data.get("action") == "navigate" and "herdr workspace focus 2" in read_log(),
)

print("CHECK DONE")
PY_RESOLVER
)"
announce_checks "resolver" "$resolver_out"

# ---------------------------------------------------------------------------
# Deterministic external-tool resolver (pure, no live tool execution)
# ---------------------------------------------------------------------------

resolver_order_out="$(python3 - "$HELPER" <<'PY_TOOL_RESOLVER' || true
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

helper = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("wnf", helper)
spec = importlib.util.spec_from_loader("wnf", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)


def check(name, condition):
    print(("CHECK PASS " if condition else "CHECK FAIL ") + name)


root = tempfile.mkdtemp(prefix="aurelia-tool-resolver-")
home = os.path.join(root, "home")
shell = os.path.join(root, "shell")
repo_bin_dir = os.path.join(root, "bin")  # == shell/../bin
path_dir = os.path.join(root, "path-bin")
for directory in (
    os.path.join(shell, "bin"),
    repo_bin_dir,
    os.path.join(home, ".local/bin"),
    os.path.join(home, ".nix-profile/bin"),
    path_dir,
):
    os.makedirs(directory, exist_ok=True)


def write_exe(directory, name):
    path = os.path.join(directory, name)
    with open(path, "w") as handle:
        handle.write("#!/bin/sh\nexit 0\n")
    os.chmod(path, 0o755)
    return path


shell_bin = write_exe(os.path.join(shell, "bin"), "demo")
repo_bin = write_exe(repo_bin_dir, "demo")
local_bin = write_exe(os.path.join(home, ".local/bin"), "demo")
path_bin = write_exe(path_dir, "demo")
env = {"HOME": home, "PATH": path_dir}

result = m.resolve_tool("demo", shell_root=shell, env=env)
check(
    "the shell-root bin is the first deterministic hit",
    result["available"] is True and result["path"] == shell_bin,
)

os.rename(shell_bin, shell_bin + ".off")
result = m.resolve_tool("demo", shell_root=shell, env=env)
check(
    "the repository-level bin is used when the shell bin has no hit",
    result["available"] is True
    and os.path.realpath(result["path"]) == os.path.realpath(repo_bin),
)
os.rename(shell_bin + ".off", shell_bin)

os.rename(shell_bin, shell_bin + ".off")
os.rename(repo_bin, repo_bin + ".off")
result = m.resolve_tool("demo", shell_root=shell, env=env)
check(
    "~/.local/bin beats the inherited PATH",
    result["available"] is True and result["path"] == local_bin,
)
os.rename(shell_bin + ".off", shell_bin)
os.rename(repo_bin + ".off", repo_bin)

path_only = write_exe(path_dir, "path-only-tool")
result = m.resolve_tool("path-only-tool", shell_root=shell, env=env)
check(
    "the inherited PATH is used only as a last-resort suffix",
    result["available"] is True and result["path"] == path_only,
)

override = write_exe(path_dir, "override-demo")
env_override = dict(env)
env_override[m.tool_override_env_name("demo")] = override
result = m.resolve_tool("demo", shell_root=shell, env=env_override)
check(
    "an explicit override wins over every deterministic candidate",
    result["available"] is True
    and result["path"] == override
    and result["searched"] == [override],
)

result = m.resolve_tool("definitely-missing-tool", shell_root=shell, env=env)
check(
    "a missing tool returns available=false with the searched list, never raising",
    result["available"] is False
    and result["path"] == ""
    and result["failureClass"] == "tooling-unavailable"
    and len(result["searched"]) > 0,
)
check(
    "the searched list is ordered shell-root first and inherited PATH last",
    result["searched"][0] == os.path.join(shell, "bin", "definitely-missing-tool")
    and result["searched"][-1] == os.path.join(path_dir, "definitely-missing-tool"),
)

path_value = m.resolver_path(shell_root=shell, home=home, inherited_path=path_dir)
check(
    "resolver_path places ~/.local/bin before the inherited PATH",
    path_value.split(":").index(os.path.join(home, ".local/bin"))
    < path_value.split(":").index(path_dir),
)

env_bad = dict(env)
env_bad[m.tool_override_env_name("demo")] = os.path.join(root, "no-such-tool")
result = m.resolve_tool("demo", shell_root=shell, env=env_bad)
check(
    "a missing explicit override fails closed instead of falling through",
    result["available"] is False and result["path"] == "",
)

# The helper must name a missing tool instead of silently degrading. The
# resolver is forced to find nothing while the real compositor is only ever
# queried, never dispatched to (the origin carries no compositor identity).
herdr_origin = {
    "originVersion": 1,
    "captureQuality": "identity",
    "compositor": {},
    "tab": {"kind": "herdr", "workspaceId": "w1", "tabId": "w1:t1", "paneId": None},
}
empty_shell = os.path.join(root, "empty-shell")
os.makedirs(empty_shell, exist_ok=True)
unresolved_env = {
    "HOME": home,
    "PATH": "",
    "AURELIA_SHELL_ROOT": empty_shell,
    m.tool_override_env_name("herdr"): os.path.join(root, "absent-herdr"),
}
result = subprocess.run(
    [sys.executable, helper, "navigate", "--origin", json.dumps(herdr_origin)],
    capture_output=True,
    text=True,
    timeout=20,
    env=unresolved_env,
)
data = json.loads(result.stdout.strip().splitlines()[-1])
check(
    "navigate names herdr unavailable when the resolver finds nothing",
    data["outcome"] == "unavailable"
    and "herdr unavailable" in data["reason"]
    and data["tab"]["applied"] is False
    and data["tab"]["exact"] is False,
)

print("CHECK DONE")
PY_TOOL_RESOLVER
)"
announce_checks "tool-resolver" "$resolver_order_out"
