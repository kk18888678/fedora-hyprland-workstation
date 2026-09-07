# External tools, frameworks, and integration contract

The QML is not a self-contained desktop. It is a composition layer over Qt,
Quickshell, the compositor, system services, and small helper commands. A 1:1
port must provide the same capabilities and timing/error behavior. Command
names below describe roles; rename the product-specific names as a unit.

## QML framework surface

### Qt modules imported

```text
QtQuick
QtQml.Models
QtQuick.Controls
QtQuick.Layouts
QtQuick.Shapes
QtQuick.Effects
QtQuick.Window
QtMultimedia
```

The implementation depends on more than basic rectangles: `TextMetrics` for
optical glyph measurement, `Shape`/`ShapePath`/`PathSvg`/`PathAngleArc` for
custom border rings and speed dials, `MultiEffect` for lock/background masking,
`MediaPlayer`/`VideoOutput`/lazy `AudioOutput` for video backgrounds, and
Qt Quick Controls for popups, fields, spin boxes, tooltips, and scroll bars.

### Quickshell modules imported

```text
Quickshell
Quickshell.Io
Quickshell.Wayland
Quickshell.Hyprland
Quickshell.Bluetooth
Quickshell.Networking
Quickshell.Services.UPower
Quickshell.Services.Pam
Quickshell.Services.Polkit
Quickshell.Services.Notifications
Quickshell.Services.Mpris
Quickshell.Services.Pipewire
Quickshell.Services.SystemTray
```

The important framework objects are:

| Object | Role |
|---|---|
| `ShellRoot` | one process-level shell host |
| `PanelWindow` | full-screen/per-output layer-shell surface |
| `PopupWindow` | anchor-relative popup surface |
| `WlrLayershell` | layer, namespace, keyboard focus, output surface control |
| `Region` | Wayland input-region geometry; bar click forwarding is handled by the panel's mouse logic |
| `IpcHandler` | named IPC target/method contract |
| `FileView` | watched/read/atomic-write file binding |
| `Process` | asynchronous external child process |
| `StdioCollector` | full stdout/stderr capture |
| `SplitParser` | line/stream parsing |
| `PersistentProperties` | in-process reload persistence |
| `Variants` | one component/window per screen |
| `Instantiator` | dynamic model-backed object creation |
| `IdleMonitor` | compositor idle/inhibitor-aware idle state |
| `WlSessionLock` | native session-lock client |
| `NotificationServer` | freedesktop notification server |
| `PolkitAgent` | native polkit authentication flow |
| `PamContext` | password/fingerprint PAM conversation |
| `DesktopEntries` | XDG application entry model |
| `ToplevelManager` | live compositor windows and active window |
| `Hyprland` | workspaces, monitors, raw events, focused monitor |
| `Pipewire`/`PwNodePeakMonitor` | audio nodes, default devices, peaks |
| `Mpris` | media players and capabilities |
| `Bluetooth` | adapter, discovery, paired/device state |
| `Networking` | NetworkManager backend, Wi-Fi networks, connectivity |
| `UPower` | battery, AC/battery state, power device state |
| `SystemTray`/`QsMenuOpener` | status notifier items and nested menus |

## Session and process tools

| Tool/capability | Used for | Required behavior |
|---|---|---|
| Wayland compositor control CLI | rounding/gaps, output state, workspace/device events, focus/dispatch | JSON output must be parseable; event names/data must match the panel parsers |
| `quickshell -p <shell-dir>` | start the host | one process per graphical session |
| `quickshell ipc -n -p <shell-dir> call ...` | direct IPC | stable target/method/string-argument behavior |
| user systemd manager | import session env and retain launcher context | root path must be session-owned |
| journal logger / `systemd-cat` | retain host logs | tag host logs; never log secrets |
| `inotifywait` | recursive user-plugin reload | watch close-write/create/delete/move; restart after watcher exit |
| `timeout --kill-after` | IPC/download/process bounds | distinguish timeout from ordinary nonzero failure |
| `find` | plugin/app/icon/image discovery | sort results; use NUL-safe mode for arbitrary paths |
| `mkdir`, `mv`, `rm`, `readlink`, `stat`, `head`, `awk`, `sed`, `grep` | state/persistence/staging | quote paths, stage safely, keep cleanup narrow |
| `jq` | JSON manifests/config/provider rows | parse strictly; never concatenate untrusted JSON into shell source |
| `flock` | thumbnail/serialized operation exclusion | lock scopes must not block future runs after process death |
| `setpriv --pdeathsig TERM` | clipboard watcher lifetime | watcher dies with host |
| `pkill`/`pgrep` | stale watcher/status detection | match narrow, product-owned patterns |
| `fc-match` | resolve system monospace alias | return concrete family for diagnostics |
| `xkbcli` | layout descriptions/briefs | load exotic layouts too |

## Bar and application tools

The bar uses these role helpers:

```text
bar text-color sampler       sample readable foreground over wallpaper
desktop-entry launcher       launch by desktop id, preserving .desktop
application remover          remove/hide a launcher entry
terminal/browser launcher    start actions in the user's graphical session
```

The concrete reference flow is `uwsm-app -- gtk-launch <id>.desktop`, with a
launch OSD triggered after 2 s and timed out after 15 s. A generic port needs a
desktop-entry resolver with equivalent behavior, not merely `exec <binary>`.

The app library scans:

```text
$HOME/.local/share/applications
$XDG_DATA_DIRS/*/applications
$HOME/.nix-profile/share/applications
```

It applies `Hidden`, `NoDisplay`, `OnlyShowIn`, and `NotShowIn`, plus a shipped
hidden-entry list. Icon discovery searches user icon dirs, XDG icon dirs,
`apps`/`devices` subtrees, and `/usr/share/pixmaps`, preferring SVG before PNG.

## Audio, power, and hardware tools

| Role | QML/native state | Helper operations |
|---|---|---|
| output sink resolution | PipeWire nodes/default sink | resolve a DSP sink to the physical loudness sink |
| default output/source | PipeWire preferred defaults | persist/use selected output/input device |
| audio OSD | host summon | show volume icon/value through OSD IPC |
| battery status | UPower display device | shell-formatted size, percentage, cycles, rate/time/threshold |
| power profiles | UPower on-battery + power profile | list active profiles, apply AC/battery profile |
| display brightness | helper state | read/set focused monitor brightness, no immediate read-back after write |
| monitor outputs | compositor | enumerate displays, toggle only when at least one remains enabled |
| night light | compositor temperature | start/reuse night-light process and set 4000/6500 K |
| Bluetooth power | native adapter | toggle persistent radio block, not an ephemeral powered flag |
| Bluetooth device actions | native adapter rows | pair/connect/disconnect/forget, with pending-state timeout |

The source intentionally mixes native model state and helpers. Native models
provide reactive state and capabilities; helpers encapsulate existing system
policy, persistent rfkill/profile behavior, or a multi-step command.

## Network and internet tools

The network panel needs:

```text
NetworkManager backend
Wi-Fi device/network objects
connectivity-check status (full/limited/portal/none)
verbose interface status helper
DNS selector helper
Wi-Fi band helper
Wi-Fi QR/password helpers
network speed-test helper
```

The reference uses `curl` with explicit max times for weather/geocoding and a
fixed HTTP connectivity-check URL for captive-portal sign-in. The panel does
not execute a URL taken from a redirect or portal response.

Enterprise Wi-Fi connection is a special security path: create the profile
with `nmcli`, then send the password to `nmcli connection edit` through stdin.
Never put that secret in argv because `/proc` exposes command lines.

## Media and video tools

The media service uses MPRIS and PipeWire directly. No CLI is needed for basic
play/pause/next/previous; the host summons the OSD for feedback. The background
video path uses Qt Multimedia's FFmpeg backend. It deliberately avoids the
convenience `Video` type because that creates an audio sink even for muted video.

The image picker additionally requires `ffmpegthumbnailer`. Its exact command
shape is:

```text
ffmpegthumbnailer -i <video> -o <temp-jpg> -s 1536 -q 8
```

under a 10 s timeout, 5 s kill-after, and per-thumbnail `flock`.

## Notification, lock, and authentication files

The system must provide:

```text
/etc/pam.d/<namespace>-lock-password
/etc/pam.d/<namespace>-lock-fingerprint       optional
/etc/pam.d/polkit-1                           fingerprint detection
fprintd-list                                  enrollment detection
```

The lock uses native `WlSessionLock` and `PamContext`; polkit uses native
`PolkitAgent`. Do not replace the native session lock with a visually similar
ordinary overlay: compositor failsafe and authentication semantics differ.

## Clipboard and file tools

The clipboard path needs `wl-paste`/`wl-copy`, `setpriv`, Perl's Encode and
JSON modules, `jq`, `sha256sum`, `mktemp`, and a file manager/browser launcher.
Text/image capture is line-delimited JSON; the plugin preserves full text in
state but caps display work at 8192 characters. Image bytes are de-duplicated
by SHA-256 and staged with `mktemp`.

## Cloud, tunnel, and agent adapters

The cloud-sync adapter runs Python 3 and the cloud CLI. Its Python helper uses
`os`, `pathlib`, `json`, `shutil`, `subprocess`, and `heapq`; every subprocess
status query is bounded to 4 s and file traversal does not follow symlinks.

The tunnel adapter uses the external tunnel CLI's JSON status, account list,
and exit-node table; it may use `pkexec` only for explicit operator
authorization. Clipboard copies use `wl-copy`, and file sends invoke the
external file-transfer helper.

The agent adapter is intentionally an adapter directory rather than a panel
edit. Each executable collector prints a complete JSON record and the updater
atomically replaces `STATE/agents/usage/<id>.json`. New providers require a
collector; an optional `<id>.svg` mark is conventionally discovered by the
panel. Local stats may read provider session files; remote limits/billing use
bounded HTTPS requests and credentials never appear in the display record.

## Packaging and ownership

The reference package manifest explicitly carries Quickshell, Qt image formats,
Qt multimedia/FFmpeg, fonts, clipboard tools, core CLI dependencies, and
feature packages. A generic build should assign one update owner per item:

```text
host package       -> host package manager
native Quickshell  -> host package manager
QML plugin source  -> distribution package or user plugin checkout
collector/helper   -> distribution source tree
theme asset        -> theme package/source
runtime service    -> system/user service manager
```

Do not make a direct upstream plugin binary, Flatpak, host package, and
self-updater all own the same capability.
