# Runtime architecture

## Core shape

The shell is a single long-lived Quickshell process. The compositor starts one
instance for each graphical session. The bar, background renderer, menus,
notifications, lock client, OSD, pickers, panels, and headless services are
components inside that process.

The key performance and ownership decision is:

```text
compositor session start
        |
        v
  shell launcher/supervisor
        |
        v
  Quickshell -p <distribution-root>/shell
        |
        +-- ShellRoot host
        |     +-- PluginRegistry
        |     +-- BarWidgetRegistry
        |     +-- AppLibrary
        |     +-- shell IPC target
        |     +-- stable image-selector IPC target
        |
        +-- one active complete bar implementation
        +-- enabled service instances
        +-- on-demand panel/overlay/menu loaders
        +-- per-monitor bar windows
```

Summoning an existing surface is an IPC call into the already-running host;
it does not launch a second Quickshell process. This gives shared services one
owner and makes a panel appear without a cold-start penalty.

## Generic directory layout

Use this shape. The names are roles; the reference uses the same separation
between common code, UI primitives, registries, and feature plugins.

```text
<distribution-root>/
  shell/
    shell.qml                         # ShellRoot host and IPC boundary
    Commons/
      qmldir                          # singleton module registration
      Color.qml                        # palette and surface roles
      Style.qml                        # geometry, typography, state tokens
      Border.qml                       # border-spec factory
      BorderGeometry.js                # path/gradient/width math
      Util.qml                         # pure shared helpers
    Ui/
      qmldir                          # reusable UI component registration
      ... reusable controls and surfaces
    services/
      PluginRegistry.qml               # scan, validate, enable, resolve
      BarWidgetRegistry.qml            # runtime bar component catalogue
      AppLibrary.qml                   # desktop entry and icon integration
      AppSearch.js                     # pure application search
      hidden-entries.sh                # XDG desktop visibility scan
    plugins/
      <feature>/
        manifest.json
        <entry-point>.qml
        optional Model.js, assets, scripts, README
      bar/
        Bar.qml
        BarModel.js
        widgets/
          <Widget>.qml
          <Widget>.manifest.json
        indicators/
          <Indicator>.qml
      services/
        <service>/Service.qml
```

First-party directories may be grouped one level deeper (`panels/<name>` or
`services/<name>`). A simple bar widget may use a sibling
`<Widget>.manifest.json` beside its QML instead of a wrapper directory.
Third-party plugins use one directory per plugin at the top level of the user
plugin directory and must contain `manifest.json` at that directory root.

## Imports and runtime libraries

The source uses these layers:

| Layer | Required modules/role |
|---|---|
| QML base | `QtQuick` for `Item`, `Rectangle`, `Text`, `MouseArea`, timers, animations, loaders, repeaters, `TextMetrics` |
| Qt controls | `QtQuick.Controls` for `TextField`, `SpinBox`, `ToolTip`, `Popup`, scroll bars |
| Qt layouts | `QtQuick.Layouts` for `RowLayout`, `ColumnLayout`, `GridLayout` |
| Qt geometry/effects | `QtQuick.Shapes` for custom borders, arcs, masks; `QtQuick.Effects` for blur/masking; `QtQuick.Window` for device-pixel ratio |
| Qt media | `QtMultimedia` for a bare `MediaPlayer`, `VideoOutput`, and lazy `AudioOutput` |
| Quickshell base | `Quickshell`, `Quickshell.Io` for environment, `Process`, `FileView`, `StdioCollector`, `SplitParser`, `PersistentProperties`, `ShellRoot` |
| Quickshell Wayland | `Quickshell.Wayland` for `PanelWindow`, `PopupWindow`, layer-shell properties, regions, focus modes, session-lock surfaces |
| Quickshell compositor | `Quickshell.Hyprland` for workspace/monitor/toplevel state, active borders, focus grabs, raw events |
| Quickshell services | `Quickshell.Services.UPower`, `.Pipewire`, `.Mpris`, `.Notifications`, `.Polkit`, `.SystemTray`, `.Pam`; `Quickshell.Bluetooth`; `Quickshell.Networking` |
| local QML modules | `qs.Commons` singleton module and `qs.Ui` reusable component module |
| host utilities | Bash, `find`, `mkdir`, `readlink`, `inotifywait`, `jq`, `timeout`, `flock`, `awk`, `sed`, `stat`, `fc-match`, `hyprctl`, `xkbcli`, plus feature-specific CLIs |
| packaging | A system package providing Quickshell, Qt 6 image formats, Qt 6 multimedia, and the FFmpeg multimedia backend is required by the reference package list |

The exact feature CLIs are listed in [07-feature-catalog.md](07-feature-catalog.md).
They are not interchangeable with QML module imports: a component may use a
native Quickshell service for live state and a small host CLI for an operation
that needs existing system policy or persistence.

## Environment and paths

The host receives one canonical distribution root from the graphical session:

```text
ROOT = $SHELL_DISTRIBUTION_PATH
HOME = $HOME
SHELL_DIR = ROOT + /shell
FIRST_PARTY_DIR = SHELL_DIR + /plugins
DEFAULT_CONFIG = ROOT + /config/<namespace>/shell.json
USER_CONFIG = HOME + /.config/<namespace>/shell.json
USER_PLUGINS = HOME + /.config/<namespace>/plugins
STATE_HOME = $XDG_STATE_HOME or HOME + /.local/state
CACHE_HOME = $XDG_CACHE_HOME or HOME + /.cache
```

A generic implementation should choose one environment variable and one
namespace, export them from the session environment, and use them everywhere.
Do not let a terminal's transient value override the session-owned value when
restarting the shell.

## Startup sequence

The effective order is:

1. Import compositor/session environment into the user systemd manager.
2. Start the shell launcher/supervisor from the compositor session.
3. Construct `ShellRoot` and instantiate the three shared service objects.
4. Load the bundled default JSON configuration; if it is absent/invalid, use
   an in-QML minimal fallback configuration.
5. Load the user JSON configuration; a valid version is authoritative and
   replaces the defaults as a whole.
6. Ensure the user plugin directory exists.
7. Scan first-party manifests and immediate user plugin manifests.
8. Stamp each accepted manifest with its source directory and first-party bit.
9. Mirror enabled bar-widget manifests into the bar widget registry.
10. Load enabled services; load panels/overlays/menus on demand unless
    `keepLoaded: true` is declared.
11. Create one bar window for every detected screen.
12. Start the optional file watcher for local plugin changes.

The shell logs its resolved paths at startup. A separate launcher writes the
Quickshell log to the user journal, disables Quickshell's own file watcher, and
supervises abnormal exits. It retries only while the compositor is still alive
and gives up after more than five relaunches in a one-minute window. A clean
exit is treated as deliberate.

## Reload sequence

Local plugin files are watched recursively with `inotifywait` for
`close_write,create,delete,move`. The watcher maps a changed path back to the
first directory below the user plugin root, ignores hidden entries and `.git`,
and schedules a 150 ms coalesced reload.

Reloading is deliberately destructive for replaceable objects:

```text
reload requested
   -> if scan/reload already active, mark pending
   -> unload panels and non-kept services/widgets
   -> keep lock/idle/polkit/image-picker-style instances when declared kept
   -> clear component cache
   -> rescan manifests
   -> rebuild service, panel, and widget registries
   -> deliver any queued summon payloads to newly loaded items
```

`keepLoaded` is a lifetime guarantee, not a hot-code guarantee. A kept
instance survives a rescan and receives the fresh manifest, but its own code
does not replace itself until a complete shell restart. This prevents a lock
client from being destroyed while the compositor still considers the session
locked.

## Shared instance rule

`PluginRegistry`, `BarWidgetRegistry`, and `AppLibrary` are instantiated once
by the host and injected into children. They are not re-imported as relative
singletons. Relative imports can create separate singleton state in QML; the
reference explicitly avoids that class of invisible split-brain bug.

Every dynamically loaded component receives properties when present:

```text
distributionPath/root path
shell host object
manifest object
barWidgetRegistry
pluginRegistry
bar configuration (bar implementations/widgets)
service (when a panel has a same-id service companion)
```

The generic contract should use capability detection (`"property" in item`)
so a plugin can implement only the properties it needs.

## Window ownership

Use separate windows for separate compositor concerns:

- top-layer per-screen bar windows;
- full-screen overlay `PanelWindow`s for menus, pickers, OSD, notifications,
  and authentication surfaces;
- anchored `PopupWindow`s for ordinary bar flyouts;
- full-screen keyboard panels with a transparent dismissal layer and a card
  placed at an anchor-derived origin;
- native session-lock surfaces for lock authentication;
- transparent per-other-monitor dismissal twins when a keyboard panel must
  catch clicks outside its own output.

Passive surfaces set `keyboardFocus: None` and, where appropriate, an empty
`Region` mask. Interactive surfaces use `Overlay` and `Exclusive`/`OnDemand`
focus according to the interaction contract described in [03-state-and-ipc.md](03-state-and-ipc.md).
