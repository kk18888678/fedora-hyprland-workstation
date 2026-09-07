# Build and acceptance blueprint

This is the implementation order for a clean 1:1 port. It is intentionally
boring: preserve the narrow contracts first, then add feature behavior behind
them.

## 1. Establish the host environment

Provide, before the graphical session starts:

- Fedora/Arch-style system package containing Quickshell with Qt 6;
- `qt6-imageformats`;
- `qt6-multimedia` plus the FFmpeg backend;
- Wayland compositor with layer-shell and native session-lock support;
- compositor control CLI and IPC/event stream;
- PipeWire/WirePlumber, MPRIS, UPower, BlueZ, NetworkManager, polkit, PAM;
- fontconfig, JetBrains Mono Nerd Font, Liberation Sans, Noto emoji/CJK;
- `bash`, GNU coreutils, `find`, `awk`, `sed`, `grep`, `jq`, `perl`, Python 3;
- `inotifywait`, `flock`, `setpriv`, `timeout`, `fc-match`, `xkbcli`;
- Wayland clipboard tools, image thumbnailer, desktop file manager, UWSM-like
  application launcher, and the feature-specific CLIs;
- all distribution helper commands called by the feature plugins.

Do not make the shell install its own plugin dependencies at runtime. A
missing optional binary must produce an unavailable feature state or a
collapsed widget, not a crash or a host-wide failure.

## 2. Create the QML modules

Create `Commons/qmldir` with exactly four singletons:

```text
module qs.Commons
singleton Border 1.0 Border.qml
singleton Color 1.0 Color.qml
singleton Style 1.0 Style.qml
singleton Util 1.0 Util.qml
```

Create `Ui/qmldir` with the types listed in
[05-ui-kit-and-measurements.md](05-ui-kit-and-measurements.md). The module must
export the shared base, surface, button, panel, input, selector, background,
and gauge types. Test importing `qs.Commons` and `qs.Ui` from a standalone
minimal ShellRoot before adding feature plugins.

## 3. Implement the shared visual layer

Implement in this order:

1. `Util`: clamp/alpha, wheel accumulation, file URL encoding, safe shell
   quoting, argv execution, JSON cloning, module-output parsing, filter edits,
   and layout normalization.
2. `BorderGeometry.js`: color/alpha parsing, CSS width expansion, side
   overrides, gradients, radii normalization, ring paths, and endpoints.
3. `Color`: foundational palette, surface roles, theme/user shell TOML parsing,
   and merge semantics.
4. `Style`: compositor-derived rounding/gaps, control states, spacing scale,
   typography, bar dimensions, theme application, and fontconfig resolution.
5. `Border`, `BorderSurface`, and `BorderOverlay`.
6. `OpticalGlyph`, `WidgetButton`, `BarWidget`, and `BarIconButton`.
7. panel rows, cursor chrome, buttons, selectors, sliders, text fields,
   keyboard dispatcher, popup card, keyboard panel, confirmation dialog,
   background media, and speed dials.

The global default table is not optional. Test at base-size 12 and then at a
larger base-size; type, spacing, bar size, and controls must scale together
unless a token is explicitly pinned.

## 4. Implement the host before features

The host must own:

```text
PluginRegistry instance
BarWidgetRegistry instance
AppLibrary instance
default/user config FileViews
active bar Loader(s)
service map
panel/overlay/menu loader map
pending summon payload queues
shell and image-selector IPC handlers
```

The host startup must wire `firstPartyDir`, config provider, and config mutator
before asking the registry to rescan. The host must not create separate
relative singleton instances for the registries.

Implement these fail-closed checks before any component Loader is activated:

- schema number exactly `1`;
- required manifest fields present;
- plugin ids cannot escape or collide;
- entry-point values are relative and contain no `..`;
- user manifests cannot use the reserved first-party namespace;
- each kind has the corresponding entry-point key;
- each entry-point file exists and is regular;
- symlink-free user plugin tree.

Keep the reference's two scan domains: first-party nested/sibling manifests
and immediate user plugin roots. Use one framed scan or an equivalent structured
transport that cannot concatenate one plugin's JSON into the next.

## 5. Implement configuration and IPC

Implement the canonical JSON shape in
[03-state-and-ipc.md](03-state-and-ipc.md). The default file must be shipped
with the release; the in-QML fallback must still render the minimal bar when
the file is absent.

Implement layout mutation before writing any feature panel. The mutation path
must deep-clone, normalize, compare, atomically write, and notify/reload. The
bar must own placement mutations while it is live.

Implement and test every host IPC method in the table in
[03-state-and-ipc.md](03-state-and-ipc.md), including error strings and the
literal-string rule for the enabled argument.

## 6. Implement the bar engine

Build the default bar as a normal `bar` plugin so the built-in and custom bar
options use the same loader boundary. Then add:

- per-screen `PanelWindow` variants;
- edge anchors and `Top` layer;
- center anchor split layout;
- tray inner-edge pinning;
- registry/custom command/custom QML resolution;
- settings injection and in-place settings delta;
- single-popout ownership;
- shared tooltip broker;
- bar/widget drag ghosts and insertion marker;
- empty-center edge move gesture;
- transparent foreground sampling;
- focused-monitor panel routing;
- panel open mark geometry;
- indicator active/inactive reveal.

Use `BarModel.js` for pure layout/search/selection helpers and keep compositor
objects in QML. Never attach `drag.target` to a slot owned by a Row/Column
positioner.

## 7. Add hosted services and common panels

Add first-party manifests and entry points in this order:

1. background service and media abstraction;
2. notification service and OSD;
3. idle, battery, night-light, polkit, and lock services;
4. command menu and application library;
5. bar widgets for workspaces, clock, tray, indicator group, microphone, and
   update status;
6. audio, Bluetooth, display, network, power, weather, tunnel, cloud-sync,
   and agent dashboards;
7. clipboard, emoji, image, QR, reminder, and speed-test overlays;
8. developer component gallery.

Each feature should have a small pure `Model.js` for parsing/formatting when
possible. Avoid holding native backend QObjects in list-model roles if their
lifecycle can overlap delegate incubation; project primitive rows and resolve
the live object by stable id/address at action time.

## 8. Add the session integration

The graphical-session layer must:

```text
import session environment
export the canonical root path
start one shell supervisor
launch Quickshell with the shell directory
```

The supervisor must disable the framework's automatic file watcher, log to the
user journal, terminate its child on HUP/INT/TERM, retry abnormal exits only
while the compositor responds, and bound relaunch attempts. A deliberate
restart command must stop every matching shell instance before starting one
replacement, and it must refuse to restart a secure lock client.

Do not run a second shell for the menu, bar settings, background picker, or
any other feature. Use the host IPC target.

## 9. Provide plugin-management commands

The command group should implement:

```text
plugin add <git-url> [--enable] [--yes]
plugin update [id] [--yes]
plugin remove [id] [--yes]
plugin enable <id> [placement]
plugin disable <id>
plugin list [--json]
plugin validate <folder>
plugin clone <first-party-id> [--edit]
bar use/reset/defaults/position/transparent/put/move/set
shell-ipc [-q] <target> <method> [args...]
```

The add/update/remove lifecycle and trust warning are part of the plugin
contract. The command group must never execute an install hook or plugin code
as part of add/validate/update. Git updates must be fast-forward-only and
post-validated. Non-git user folders must be backed up on removal.

## 10. Test in isolated sandboxes

Keep one command, `./tests/run.sh`, but split its implementation into coherent
test modules. At minimum test:

### Pure model tests

- width-list expansion, gradients, radii/ring paths, and alpha clamping;
- type/spacing/bar-scale formulas;
- plugin id/entry-point validation and reserved namespace;
- scan-frame parsing and collision policy;
- enablement/clone/restore transitions;
- config normalization, no-deep-merge behavior, and idempotent put/move;
- clone target paths and `clonedFrom` routing;
- menu JSONC merge, guards, routes, search scores, provider swaps;
- application, network, weather, clock, power, media, notification, QR, and
  image row parsing;
- exact dial/thumbnail/clipboard state transformations.

### Negative safety tests

- absolute/`..`/empty entry points;
- missing entry-point files and kind/entry-point mismatches;
- symlink inside a plugin;
- reserved or duplicate plugin ids;
- malformed/unknown config versions;
- malformed scan frames and torn persisted JSON;
- stale process output after cancellation or timeout;
- duplicate ids in centered bar placeholders;
- password/secret values appearing in argv or logs;
- image tags/remote URLs in notification bodies;
- screen movement/remap, multi-monitor routing, and lock-preservation paths.

### Visual smoke test

Run the developer gallery in a fake-bar host and verify every exported QML type
at the reference default theme. Test both square (`rounding=0`) and rounded
compositor modes, top/bottom/left/right bars, narrow screens, HiDPI, multiple
monitors, and a larger font base size.

## Acceptance gates

A port is not accepted as 1:1 until all are true:

- `qs.Commons` and `qs.Ui` import with the complete `qmldir` lists;
- the host starts with only the shipped default file and with no default file;
- a malformed user file falls back without a partial merge;
- first-party and third-party discovery produce the same manifest shape;
- adding a valid plugin requires no host source edit;
- invalid plugins are rejected before they enter the user plugin directory;
- enabling/disabling/re-running is idempotent;
- panels receive queued payloads exactly once in order;
- kept services survive plugin reload and code changes require a restart;
- every monitor gets one bar and panel routing picks the correct monitor;
- one popout is visible/active at a time;
- every global and feature measurement matches the tables in these documents;
- keyboard and mouse yield one shared cursor highlight;
- dynamic data cannot move a pointer-selected row unexpectedly;
- timeouts, cancellation, retries, and signals do not leave stuck processes;
- lock, notifications, clipboard, and image data survive the documented
  restart/cleanup paths;
- no plugin file is executed by management commands;
- real graphical integration is tested separately from unit tests.

## What must not be substituted

Do not replace the host with one process per feature, JSON manifests with code
registration, inline settings with arbitrary merge layers, native service
models with polling-only approximations, or shared cursor state with per-row
hover paint. Those substitutions may look close while violating the behavior
that makes the reference feel stable and extensible.
