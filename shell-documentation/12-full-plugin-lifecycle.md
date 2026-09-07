# Full plugin lifecycle, trust, and extensibility

This is the complete lifecycle for both shipped plugins and user-installed
plugins. The runtime contract is file-based: a host scans directories, reads a
manifest, validates it, creates a QML component for a declared kind, injects a
capability-scoped API, and records enablement in one JSON state file.

That separation is why adding a visual plugin does not require editing host
source. The host knows the kind and entry-point key; the plugin owns its QML,
models, and assets.

## Plugin classes

| Class | Source directory | Discovery | Enablement | Trust/input boundary |
|---|---|---|---|---|
| shipped plugin | `<root>/shell/plugins/` | nested/sibling manifest scan | infrastructure enabled by default; bar/widget state is special | trusted host API |
| local third-party plugin | `~/.config/<namespace>/plugins/<id>/` | one directory level, root `manifest.json` | id must be referenced in effective state | scoped facade, but same user process |
| built-in clone | local plugin directory, with `omarchy.clonedFrom` | same as third-party | replaces its source id and routes old calls to clone | third-party facade plus narrow clone compatibility |
| custom bar module | `~/.config/<namespace>/bar/modules/` or explicit source | referenced by bar layout, not manifest registry | presence in bar layout | bar module API |

A custom bar module is not a shell plugin in the registry sense. It is an
additional escape hatch inside the bar configuration. It must not be confused
with a manifest-backed `bar-widget` plugin.

## Kinds and loading behavior

The schema supports six kinds. A single manifest may declare several:

| Kind | Entry-point key | Host owner | Loading lifetime |
|---|---|---|---|
| `bar` | `entryPoints.bar` | one active complete bar loader | mounted at startup; only one active |
| `bar-widget` | `entryPoints.barWidget` | bar widget registry and configured slots | component catalog while enabled; slot exists only when in layout |
| `panel` | `entryPoints.panel` | panel loader | on demand unless `keepLoaded` |
| `overlay` | `entryPoints.overlay` | panel/overlay loader | on demand unless `keepLoaded` |
| `menu` | `entryPoints.menu` | menu loader | on demand unless `keepLoaded` |
| `service` | `entryPoints.service` | service synchronizer | enabled services are created as host services; `keepLoaded` protects them during reload |

`keepLoaded: true` is a lifetime instruction, not a hot-swap promise. A kept
service or panel survives a plugin rescan; edited code takes effect after a
fresh shell process. This is necessary for session-lock and similar resources
whose destruction during a reload would strand the session.

## Manifest contract

The runtime schema version is the JSON number `1`.

```json
{
  "schemaVersion": 1,
  "id": "author.example-widget",
  "name": "Example widget",
  "version": "1.0.0",
  "author": "Author",
  "license": "MIT",
  "description": "Short description",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "keepLoaded": false,
  "barWidget": {
    "displayName": "Example widget",
    "description": "Shown in the widget catalogue",
    "category": "Status",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": {},
    "settingsForm": "",
    "schema": []
  }
}
```

Required fields are `schemaVersion`, `id`, `name`, `version`, `kinds`, and
`entryPoints`. Runtime validation requires a plain object, schema version 1, a
non-empty kinds array, a plain entry-point object, and safe entry-point values.
Every entry point must be a non-empty relative string with no leading `/` and
no `..` substring. A `defaultSection`, when present, must be exactly `left`,
`center`, or `right`.

For a `bar-widget`, the registry and CLI only validate `barWidget.defaultSection`
when that object/key is present; they do not require a `barWidget` object,
non-empty `displayName`/`description`/`category`, or a Boolean `allowMultiple`.
The runtime bar-widget registry normalizes missing metadata to
display-name/name, description, category `Plugin`, `allowMultiple: false`, empty
defaults/schema, and empty settings form. A source-faithful port must preserve
this permissive validator behavior even if an authoring UI chooses to require
richer metadata.

The supported kind-to-entry-point table is fixed:

```text
bar         -> entryPoints.bar
bar-widget  -> entryPoints.barWidget
menu        -> entryPoints.menu
overlay     -> entryPoints.overlay
panel       -> entryPoints.panel
service     -> entryPoints.service
```

The reference CLI validator enforces the kind table and entry-point file
existence. The QML registry validator in the audited source performs a narrower
check and does not itself require the file to exist or the kind table to match.
It also does not recursively reject symlinks; the CLI/install validator does.
Therefore a hand-dropped directory can have different acceptance behavior from
one passed through the command, which is a source quirk to either preserve or
close explicitly.
An implementation intended to be safe should retain the CLI checks in the
runtime as well, but that is a deliberate hardening choice if strict 1:1
behavior is required.

## First-party catalog at the audited source

The full repository contains 37 manifest files. The table below is the source
catalog; a generic implementation may rename the ids, but must preserve the
same roles, kinds, and load topology if it is claiming 1:1 behavior.

| Source id | Kinds | Entry point(s) | Default load role |
|---|---|---|---|
| `omarchy.agents` | bar-widget | `agents/Panel.qml` | bar catalog, self-hiding until usage exists |
| `omarchy.background` | service | `background/Background.qml` | wallpaper service |
| `omarchy.bar` | bar | `bar/Bar.qml` | default complete bar |
| `omarchy.active-window` | bar-widget | `bar/widgets/ActiveWindow.qml` | bar widget |
| `omarchy.indicators` | bar-widget | `bar/widgets/Indicators.qml` | bar widget |
| `omarchy.keyboard-layout` | bar-widget | `bar/widgets/KeyboardLayout.qml` | bar widget |
| `omarchy.microphone` | bar-widget | `bar/widgets/Microphone.qml` | available, not in shipped layout |
| `omarchy.spacer` | bar-widget | `bar/widgets/Spacer.qml` | available, not in shipped layout |
| `omarchy.system-update` | bar-widget | `bar/widgets/SystemUpdate.qml` | bar widget |
| `omarchy.tray` | bar-widget | `bar/widgets/Tray.qml` | bar widget |
| `omarchy.workspaces` | bar-widget | `bar/widgets/Workspaces.qml` | bar widget |
| `omarchy.clipboard` | overlay | `clipboard/Clipboard.qml` | kept overlay |
| `omarchy.dev-gallery` | panel | `dev-gallery/GalleryPanel.qml` | on demand |
| `omarchy.emojis` | overlay | `emojis/Emojis.qml` | kept overlay |
| `omarchy.image-picker` | overlay | `image-picker/ImagePicker.qml` | kept overlay |
| `omarchy.lock` | service | `lock/Service.qml` | kept authentication service |
| `omarchy.menu` | menu, bar-widget | `menu/Menu.qml`, `menu/BarWidget.qml` | kept menu plus bar launcher |
| `omarchy.notifications` | service | `notifications/Service.qml` | kept notification server |
| `omarchy.osd` | panel | `osd/Osd.qml` | kept OSD panel |
| `omarchy.audio` | bar-widget | `panels/audio/Panel.qml` | bar widget/popup |
| `omarchy.bluetooth` | bar-widget | `panels/bluetooth/Panel.qml` | bar widget/popup |
| `omarchy.clock` | bar-widget | `panels/clock/BarWidget.qml` | bar widget/popup |
| `omarchy.disk-speedtest` | panel | `panels/disk-speedtest/Panel.qml` | on demand |
| `omarchy.dropbox` | bar-widget | `panels/dropbox/Panel.qml` | optional bar widget |
| `omarchy.monitor` | bar-widget | `panels/monitor/Panel.qml` | bar widget/popup |
| `omarchy.network` | bar-widget | `panels/network/Panel.qml` | bar widget/popup |
| `omarchy.power` | bar-widget | `panels/power/Panel.qml` | bar widget/popup |
| `omarchy.speedtest` | panel | `panels/speedtest/Panel.qml` | on demand |
| `omarchy.tailscale` | bar-widget | `panels/tailscale/Panel.qml` | optional bar widget |
| `omarchy.weather` | bar-widget | `panels/weather/BarWidget.qml` | bar widget/popup |
| `omarchy.wifiqr` | panel | `panels/wifiqr/Panel.qml` | on demand |
| `omarchy.polkit` | service | `polkit/PolkitAgent.qml` | kept authentication service |
| `omarchy.reminders` | overlay | `reminders/ReminderFlow.qml` | kept overlay |
| `omarchy.battery` | service | `services/battery/Service.qml` | low-battery service |
| `omarchy.idle` | service | `services/idle/Service.qml` | kept idle service |
| `omarchy.media` | service, bar-widget | `services/media/Service.qml`, `services/media/BarWidget.qml` | kept service plus center widget |
| `omarchy.nightlight` | service | `services/nightlight/Service.qml` | night-light service |

Simple bar widgets use sibling files such as
`bar/widgets/Workspaces.manifest.json`; grouped feature plugins use a directory
manifest. The runtime scans both forms, which is why a one-directory-per-plugin
rule is not enough for a faithful first-party port.

### Exact shipped bar state crosswalk

The generic state example in 03-state-and-ipc.md uses role labels. The exact
source IDs and order in config/omarchy/shell.json at the audit anchor are:

~~~text
idle: screensaver=150, lock=300
bar.position=top
bar.transparent=false
bar.centerAnchor=omarchy.clock
bar.layout.left:
  omarchy.menu
  omarchy.workspaces
bar.layout.center:
  omarchy.indicators
  omarchy.clock { format: "dddd HH:mm", formatAlt: "d MMMM 'W'ww yyyy", verticalFormat: "HH\n—\nmm" }
  omarchy.keyboard-layout
  omarchy.weather
  omarchy.system-update
bar.layout.right:
  omarchy.tray
  omarchy.agents
  omarchy.bluetooth
  omarchy.network
  omarchy.audio
  omarchy.monitor
  omarchy.power
plugins=[]
~~~

There is no shipped disabledPlugins or cloneSourceRestores field in the fresh
file. Those fields appear only as later user-state deviations when applicable.

## Enablement semantics

The state file has four relevant locations: `bar.id`, three
`bar.layout.<section>` arrays, `plugins[]`, and `disabledPlugins[]`.

| Plugin type | Enabled when | What disable does |
|---|---|---|
| complete bar | `bar.id` equals its id; omitted id selects the built-in bar | a bar cannot be disabled, only replaced by another bar option |
| first-party bar widget | component is cataloged; its visible presence is whether its id is in a layout array | removes its layout entry, leaving the component available to add back |
| first-party non-widget | id is not in `disabledPlugins[]` | adds id to `disabledPlugins[]` |
| third-party widget | id is in a layout array | removes its layout entry and unloads it when no other kind keeps it active |
| third-party panel/overlay/menu/service | id is in `plugins[]` | removes the plugin entry and unloads it |

The registry’s `isEnabled()` question and the list command’s user-facing
`enabled` column are intentionally different for first-party bar widgets:
`isEnabled()` keeps their component available, while the list reports whether
the widget is actually in the bar. A clone or mixed-kind plugin can therefore
be loadable even when its bar button is absent.

The registry does not enforce `allowMultiple` against hand-edited JSON. The
field describes intended UI behavior; if duplicate entries are present, the
bar can receive them. A faithful settings UI should honor the field, while a
runtime that claims strict source behavior must not pretend the registry itself
rejects duplicates.

## Add lifecycle for third-party repositories

The reference command sequence is:

```text
receive URL
  -> reject option-shaped URL or git remote helper
  -> warn that code is arbitrary and unsandboxed
  -> confirm unless --yes
  -> clone into a temporary user-plugin directory
  -> validate manifest and entry points
  -> reject duplicate/reserved id
  -> move staged tree to plugins/<manifest-id>/
  -> request shell rescan
  -> optionally wait for discovery and enable/place it
```

The URL checker rejects a leading dash, every `<helper>::...` form, and unknown
`scheme://...` transports. It allowlists `ssh`, `git`, `git+ssh`, `ssh+git`,
`http`, `https`, `ftp`, `ftps`, and `file`. It is a transport-surface check,
not repository authenticity or code safety.

The add command exports noninteractive Git settings (`GIT_TERMINAL_PROMPT=0`
and batch SSH), validates before the plugin reaches its final directory, and
never executes plugin files, plugin install hooks, or sudo. A bare interactive
add asks twice: clone confirmation, then enable confirmation. `--yes` bypasses
both prompts and leaves the plugin disabled unless `--enable` was supplied.
The interactive bar-widget placement picker uses a 520 px width and 520 px
maximum height; default placement comes from `barWidget.defaultSection` or the
center section.

The scanned plugin is not automatically trusted merely because its manifest is
valid. The manifest only describes loading and UI metadata.

## Update lifecycle

An installed Git plugin is updated as its own checkout:

```text
git fetch origin HEAD
  -> compare HEAD and FETCH_HEAD
  -> show diff and ask, unless --yes
  -> git merge --ff-only FETCH_HEAD
  -> validate new checkout
  -> on validation failure: reset to ORIG_HEAD
  -> rescan shell if at least one plugin changed
```

The update command can target one id or every directory containing `.git`. It
does not update hand-made directories, branches, or arbitrary refs. A local
change that prevents a fast-forward is an error; the command does not overwrite
it. `delta` is optional for display only. Network failure, non-fast-forward
state, and validation failure remain distinguishable user-facing errors.

## Remove lifecycle

Removal first determines whether the id is enabled and whether the manifest
declares `omarchy.clonedFrom`. It disables an enabled plugin through shell IPC,
then:

- unlinks a symlink plugin directory;
- deletes a Git checkout, leaving the upstream repository untouched;
- moves a non-Git hand-made directory to a unique timestamped hidden backup
  instead of deleting it.

Removing an active clone restores the source id before removing the clone. For
a cloned bar widget, the source entry replaces the clone entry with its prior
settings and position. For a cloned non-widget, the clone is removed from
`plugins[]`, the source is re-enabled when the clone had disabled it, and old
IPC callers continue to resolve correctly.

The reference uses interactive confirmation unless `--yes` is supplied. A
noninteractive call without `--yes` refuses rather than guessing.

## Clone lifecycle for first-party code

`plugin clone <source-id>` is the supported way to customize shipped code:

1. Resolve the source only from first-party catalog metadata.
2. Derive `<username>.<source-id-without-omarchy-prefix>`.
3. Copy the complete source plugin for a directory manifest.
4. For a sibling manifest, copy the manifest, every declared entry point, and
   every `omarchy.clonePaths` source into the destination target paths.
5. Rewrite local references when a clone path changes.
6. Set the new manifest id/name/display name, add
   `omarchy.clonedFrom`, and remove `omarchy.clonePaths` from the clone.
7. Move the staged copy into the user plugin directory.
8. Rescan, wait up to 2 seconds for discovery, then enable the clone.

Built-in ids embedded in QML are intentionally not rewritten. The host resolves
an old source id to the enabled clone, so existing bar layout, keybindings, and
IPC callers keep working. Enabling the source again restores the source and
turns off the active clone. Removing a clone restores the source automatically.

If `--edit` is supplied, the clone directory is handed to `$EDITOR` after the
state switch. Saving any file below the user plugin directory triggers a reload.

## Scan, load, and reload lifecycle

The first-party scan walks `shell/plugins/` for files named `manifest.json` or
`*.manifest.json` at the supported nested depths, sorts them, and emits framed
manifest records. The user scan walks only immediate child directories and
accepts a root `manifest.json`. The QML registry parses the frames, stamps each
manifest with source directory and first-party status, stamps trusted
capabilities, rejects reserved-id collisions, and replaces the installed map
atomically.

User plugin directory creation happens before the first scan. An `inotifywait`
process recursively watches `close_write,create,delete,move`, reports the top
plugin id, and restarts one second after watcher exit. A 150 ms timer coalesces
multiple file events into one reload.

Reload is serialized:

```text
file event
  -> debounce 150 ms
  -> unload non-kept panels, services, widgets
  -> preserve kept services/authentication clients
  -> clear QML component cache
  -> rescan manifests
  -> synchronize services, panel entries, widget registry, and facades
```

If a scan is already running, reload sets a pending flag and runs again after
the scan finishes. A widget component is claimed before asynchronous creation
starts so repeated scans cannot create two loaders for one URL. Load errors drop
the claim and emit a failure signal so a later rescan can retry.

Summon calls that arrive before an asynchronous panel loader resolves are queued
per plugin and delivered in arrival order. Hide calls invoke `close()` when
loaded and clear the open set. Bar-widget panels route through the active bar’s
per-monitor slot rather than through the generic panel loader.

## Capability and authentication boundaries

All plugin code still runs in one same-user Quickshell process. The facades are
API boundaries, not operating-system sandboxes.

The host behavior is:

- first-party entry points receive the host objects;
- ordinary third-party plugins receive a scoped shell facade that can look up,
  summon, hide, toggle, and update only their own service/entry;
- menu plugins receive an application-library facade;
- plugins can read detached scalar bar state and detached bar configuration;
- a full replacement bar receives detached configuration and widget-catalog
  snapshots, plus narrow proxies for approved non-authentication services and
  host lifecycle access for known non-authentication UI-kind targets;
- replacement-bar widgets receive a service-less entry facade and cannot
  manufacture a generic lookup for another plugin’s service;
- built-in clones receive narrow source-specific compatibility, including the
  explicitly allowed auxiliary UI targets needed by the original feature;
- authentication capabilities are stamped only from trusted first-party
  manifests, and authentication services are retained in a private store with
  no QObject parent or public service-map entry.

The source explicitly warns that visual QML objects share the host scene and can
traverse ordinary parent objects. Do not place credentials, PAM state, polkit
secrets, or other sensitive objects in that reachable visual graph and do not
describe same-process facades as a security sandbox.

### Concrete facade contracts

The current full snapshot implements these facades as separate Qt objects. They
are created by the host with closed-over callbacks; they are not independent
plugin registries.

The complete signatures, scope rules, scalar values, ownership records, and
cache/revocation behavior are in
[19-plugin-facade-api-reference.md](19-plugin-facade-api-reference.md).

| Facade | Public properties | Public methods/signals |
|---|---|---|
| `PluginShellApi` | `pluginId`, `appLibrary`, `bar`, `barConfig`, `idleConfig` | `serviceFor`, `firstPartyServiceFor`, `pluginShellForBarEntry`, `summon`, `hide`, `toggle`, `isPluginOpen`, `updateEntryInline`, `mutateShellConfig` |
| `PluginRegistryApi` | `pluginId`, self-only `manifest`, `enabled`, self-only `installedPlugins` | `isEnabled`, self-only `resolveEnabledId`, self-only `entryPointUrl` |
| `PluginAppLibraryApi` | `ownerPluginId`; `appsChanged` signal | `entryName`, `entrySubtext`, `sortedEntries`, `iconSource`, `refreshIcons`, `launch`, `remove` |
| `PluginBarStateApi` | `ownerPluginId`, `barHidden`, `barSize`, `fontFamily`, `position` | none |
| `PluginBarWidgetRegistryApi` | detached `widgets` snapshot, `revision` | `metadataFor`, `availableIds`, `has` |
| `PluginFirstPartyServiceApi` | `ownerPluginId`, `serviceId`, `stayAwake`, `enabled`, `doNotDisturb`, `activePlayer`, `sourcePlayers` | `setIdleEnabled`, `setNightlight`, `setDoNotDisturb`, `runAction`, `playerKey`, `selectPlayer` |
| `PluginBarApi` | `pluginId`, `moduleName`, optional `shell`, scalar colors, `fontFamily`, `position`, `vertical`, `barSize`, `transparent`, animation/reveal flags, `activePopout`, detached `clickTargets`, `layoutConfig`, foreign-popout marker | `setCenterHoverRevealSuppressed`, `showTooltip`, `hideTooltip`, `registerClickTarget`, `unregisterClickTarget`, `requestPopout`, `releasePopout`, `switchPanelFrom`, `targetBelongsToWindow`, `moduleWidgets`, `run` |

`PluginRegistryApi.installedPlugins` contains only the caller’s own public
manifest. The bar-widget registry facade contains component references and
detached metadata snapshots, but no host registry mutation method. The
first-party service facade exposes only the explicitly named properties and
operations; it has no generic property/method forwarding. A full replacement
bar may receive proxies only for `omarchy.idle`, `omarchy.media`,
`omarchy.nightlight`, and `omarchy.notifications`; the source does not expose
lock or polkit through this proxy list.

The ordinary third-party shell facade permits own-service lifecycle and own
settings updates. A full-bar facade additionally receives the detached bar
configuration/widget snapshot and narrow first-party service proxies. A
third-party widget hosted by that replacement bar receives `PluginBarApi`, not
the host `Bar` object. This distinction is required to prevent a replacement
bar from manufacturing a generic cross-plugin service lookup.

The idle-service clone is the one source-specific configuration exception:
when a clone declares `omarchy.clonedFrom: "omarchy.idle"`, its scoped shell
facade receives a detached copy of the top-level idle object through
`idleConfig`. Other third-party plugins receive an empty idle-config object.
The idle service uses this fallback when the full host shell config is not
available through the scoped facade.

Facade lifetime is part of the lifecycle. The host caches facades by plugin or
owner/entry key; registry, application-library, and widget-catalog changes
refresh their detached properties. Disabling/removing a plugin destroys its
cached facades. A replacement bar facade is also revoked when its capability
profile changes or when no live module slot uses it. A fresh facade is created
after the plugin becomes active again. Third-party manifests passed through
the public facade have the host-only source-directory, first-party, and
trusted-capability fields removed; first-party entry points retain the trusted
host objects.

## Authoring checklist

Before publishing a plugin, verify:

1. id is globally unique, starts with a non-reserved character, and does not
   contain `/` or `..`;
2. schema version is numeric `1`;
3. every declared kind has exactly its supported entry-point key;
4. every entry point is a regular file reached by a safe relative path;
5. user plugins contain no symlinks;
6. `barWidget` metadata is complete for a bar widget;
7. settings are JSON values on the inline state entry, not hidden global files;
8. IPC calls name the plugin’s stable id and handle `unknown`/load failures;
9. a missing optional external binary collapses or reports unavailable state;
10. the plugin does not expect its edited service code to hot-swap while kept;
11. the plugin has a source review and a documented trust decision;
12. tests cover malformed manifests, traversal, duplicate ids, reload, disable,
    removal, and partial discovery.

## Source cross-check

```text
shell/services/PluginRegistry.qml
shell/shell.qml
shell/services/AuthServiceStore.js
shell/services/*Api.qml
shell/plugins/README.md
shell/plugins/bar/README.md
bin/omarchy-plugin-add
bin/omarchy-plugin-catalog
bin/omarchy-plugin-clone
bin/omarchy-plugin-disable
bin/omarchy-plugin-enable
bin/omarchy-plugin-list
bin/omarchy-plugin-remove
bin/omarchy-plugin-update
bin/omarchy-plugin-validate
bin/omarchy-git-url-check
test/shell.d/plugin-add-test.sh
test/shell.d/plugin-clone-test.sh
test/shell.d/plugin-enable-test.sh
test/shell.d/plugin-validate-test.sh
test/shell.d/plugins-test.sh
test/shell.d/plugin-registry-contract-test.sh
test/shell.d/plugin-auth-boundary-test.sh
```

The source proves the lifecycle and API decisions above. It does not make
third-party code safe, authenticate an arbitrary Git repository, or prove
runtime behavior on every Quickshell/Qt release.
