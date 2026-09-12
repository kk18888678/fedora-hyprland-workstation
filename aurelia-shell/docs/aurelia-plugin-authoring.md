# Aurelia Shell Plugin Authoring and Maintenance

Status: operational guide for the canonical Aurelia Shell plugin contract.

This guide is the author-facing companion to
aurelia-plugin-contract-v1.md. There is one manifest schema and one host
lifecycle model. The contract document is normative; this guide explains how
to build, validate, install, test, reload, update, clone, and remove a plugin.
Execution progress and parity evidence are tracked in the
[Omarchy parity tracker](../../docs/AURELIA-OMARCHY-PLUGIN-PARITY-TRACKER.md).

## Design goals

Aurelia follows the Omarchy plugin architecture at the structural level:

- a manifest describes identity, kinds, and entry points;
- discovery validates metadata before construction;
- one resident host owns loading and lifecycle;
- bar widgets register through a dedicated bar catalogue;
- configuration, settings, and placement are host-owned;
- plugins can be resident or on demand;
- failures are contained per plugin;
- source lifecycle is managed by the aurelia-plugin CLI;
- generic and feature-specific tests are centralized under aurelia-shell/tests.

Aurelia retains its existing feature implementations, backend ownership,
design tokens, plugin IDs, IPC compatibility aliases, and workstation safety
rules. Plugin architecture parity does not mean replacing those features.

## Directory layout and source roots

The repository-owned first-party source root is:

~~~text
aurelia-shell/plugins/<aurelia.plugin-id>/
~~~

The user-owned third-party source root is:

~~~text
$XDG_CONFIG_HOME/aurelia/plugins/<plugin-id>/
~~~

When XDG_CONFIG_HOME is unset, the user root is
$HOME/.config/aurelia/plugins. The aurelia. namespace is reserved for
first-party plugins. A user plugin must use another namespace and may not
shadow a first-party ID.

The repository also contains a non-loadable example under:

~~~text
aurelia-shell/examples/plugins/example.panel/
~~~

Examples are deliberately outside aurelia-shell/plugins, so copying or
validating one does not change the shipped first-party inventory.

A normal plugin directory contains:

~~~text
<plugin-id>/
├── manifest.json
├── entry-point files declared by the manifest
└── optional private QML, JavaScript, image, or data files
~~~

First-party grouped source directories may use sibling files named
*.manifest.json when a group contains multiple small plugins. Third-party
plugins use one manifest.json in their top-level plugin directory.

## Canonical manifest

The required shape is:

~~~json
{
  "schemaVersion": 1,
  "id": "author.example-panel",
  "name": "Example Panel",
  "version": "1.0.0",
  "author": "Author",
  "license": "MIT",
  "description": "A short human-readable description.",
  "kinds": ["panel"],
  "entryPoints": {
    "panel": "Panel.qml"
  },
  "keepLoaded": false
}
~~~

Required fields:

| Field | Rule |
| --- | --- |
| schemaVersion | JSON number 1. |
| id | Non-empty safe identifier; no path traversal or path interpretation. |
| name | Non-empty display name. |
| version | Non-empty plugin version, not a host API version. |
| description | Non-empty human-readable description. |
| kinds | Non-empty array with no duplicate supported kinds. |
| entryPoints | Object with one safe existing file for each declared kind. |

Supported kinds and their canonical entry-point keys:

| Kind | Key | Host meaning |
| --- | --- | --- |
| bar | bar | Complete replacement bar; one active owner. |
| bar-widget | barWidget | Component registered with the active bar. |
| panel | panel | On-demand floating panel. |
| overlay | overlay | On-demand overlay surface. |
| menu | menu | On-demand menu surface. |
| service | service | Resident service owner. |

The old entryPoints["bar-widget"] spelling is accepted as a read-compatible
legacy input during migration. New manifests must use entryPoints.barWidget.
Do not declare both keys for one bar-widget.

Every entry-point path must be relative, non-empty, free of absolute prefixes,
.. components, backslashes, colons, and unsupported control characters. The
target must be an existing regular file, and the plugin tree must contain no
symlinks. Discovery rejects the whole plugin before QML construction when
these conditions fail.

## Bar widgets

A bar-widget manifest includes validated operational metadata:

~~~json
{
  "schemaVersion": 1,
  "id": "author.example-widget",
  "name": "Example Widget",
  "version": "1.0.0",
  "description": "A compact status widget.",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "Widget.qml"
  },
  "barWidget": {
    "displayName": "Example Widget",
    "description": "Shown in the bar catalogue.",
    "category": "Status",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": {},
    "settingsForm": "",
    "schema": []
  }
}
~~~

The metadata controls catalogue presentation, default placement, settings
controls, and whether multiple instances are legal. It is descriptive data;
metadata validation never executes plugin code.

The three bar sections are left, center, and right. The normalized user state
stores widget instances under bar.layout.<section>. A widget's settings are
inline on its instance entry. The centered widget is selected by the
bar.centerAnchor value.

Entry points should expose implicitWidth and implicitHeight. Optional injected
properties must have safe defaults because a URL-loaded QML component is
constructed before PluginHost.onLoaded can inject host objects. Rich panels
should be opened through the shell boundary rather than creating a second
bar or a second host.

The bar facade exposes scalar state and owner-scoped operations:

- position, vertical, barSize, and barHidden;
- requestPopout and releasePopout for one owner;
- invoke for the owner's bar instance;
- registerClickTarget and unregisterClickTarget;
- activePopoutId for read-only state.

Only one bar-owned popout is active at a time. A widget must release its
popout when it is destroyed or no longer owns the interaction.

## Lifecycle and loading

The host lifecycle is:

~~~text
scan
  -> validate manifest and entry-point tree
  -> build source-aware catalogue
  -> resolve enabled state
  -> load resident services and keepLoaded surfaces
  -> register configured bar widgets
  -> load panel, overlay, and menu surfaces on demand
~~~

The host owns Loader activation. Plugin UI does not install packages, edit
shell.json, rescan the registry, or invoke privileged commands.

Service and keepLoaded rules:

- a service has one resident instance per enabled plugin ID;
- keepLoaded true keeps the eligible surface mounted across close and reload;
- a bar-widget is loaded for configured bar instances, not merely because its
  manifest exists;
- a bar plugin participates in active-bar selection and exactly one full bar
  remains active;
- panels, overlays, and menus are on demand unless keepLoaded is true;
- queued open payloads are delivered in order after construction;
- disable unloads runtime ownership without purging user data;
- removal is separate from disablement and from purging user-owned files.

A multi-kind plugin has distinct owners. A service kind is the resident
primary owner when present; a separate barWidget entry point remains a bar
owner. This is the same design used by aurelia.notifications.

## Host APIs and third-party facades

First-party plugins may receive trusted internal objects where existing Aurelia
features require them. Third-party plugins receive detached, owner-scoped
facades only:

- PluginRegistryApi: self-scoped identity, enablement, entry-point, and failure
  information;
- PluginShellApi: self-scoped summon, hide, toggle, open-state, settings, and
  service lookup;
- PluginBarApi: scalar bar state and operations for the owner's instance;
- PluginBarWidgetRegistryApi: detached read-only widget metadata snapshots;
- PluginAppLibraryApi: read-only application rows and icon resolution where
  the host allows it.

Facade callbacks close over the owning plugin ID and instance ID. A plugin
cannot use a facade to address another plugin, mutate raw ShellConfig, obtain
the active bar object, or read host-internal manifest fields. Facades are
revoked when a plugin is disabled, removed, rescanned, or its capability
profile changes.

Facades are an ownership boundary, not a process or security sandbox. Plugin
code still runs in the resident Quickshell process with the same process
privileges as the shell. Deliberately malicious code can still terminate or
crash that process; true process isolation would not be 1:1 with Omarchy.

## Failure behavior and trust model

Discovery never executes plugin code. Invalid JSON, invalid metadata, unsafe
paths, symlinks, duplicate IDs, and missing files are rejected before a
Loader sees them.

Runtime failures are per plugin and per kind. QML load/import errors,
initialization exceptions, missing entry points, service construction errors,
bar-widget construction/callback errors, and reload failures are recorded
with bounded diagnostics. The failing owner is quarantined or unloaded while
the host, healthy plugins, shell ping/listPlugins, and built-in bar fallback
remain available.

A failure is not automatically retried in an unbounded loop. Explicit reload
or rescan is the retry boundary.

Third-party plugins are unsandboxed code. Review all source before enabling it.
The plugin CLI never executes an install hook, install.sh, sudo, pkexec, or
systemctl from plugin source. Network Git operations are HTTPS-only, bounded,
non-interactive, staged, provenance-recorded, and validated before publication.

## Configuration and settings

The user-owned canonical state is:

~~~text
$XDG_CONFIG_HOME/aurelia/shell.json
~~~

It contains the active bar object, bar widget instances, plugin instances,
settings, and explicit disabled-plugin state. Presence and defaults are
separate: an installed or discovered plugin is not automatically a bar
instance, and deselection does not imply removal.

Use manifest barWidget.defaults only when the instance has no user value.
Declare controls in barWidget.schema with bounded types such as string,
integer, number, boolean, enum, path, or multiselect. Update settings through
the injected shell facade or the host-owned CLI; do not parse or mutate the
shared state file directly.

State writes are atomic, idempotent, recoverable, and compatibility-aware.
Older Aurelia string plugin entries and the legacy bar-widget entry-point key
remain readable during the migration window.

## Validation and installation workflow

Validate the example without touching the live plugin directory:

~~~bash
./aurelia-shell/bin/aurelia-plugin validate \
    aurelia-shell/examples/plugins/example.panel
~~~

Install a reviewed local example manually into a test-owned or user-selected
plugin root, then ask the resident host to discover it:

~~~bash
mkdir -p "$XDG_CONFIG_HOME/aurelia/plugins"
cp -a aurelia-shell/examples/plugins/example.panel \
    "$XDG_CONFIG_HOME/aurelia/plugins/example.panel"
./aurelia-shell/bin/aurelia-plugin rescan
./aurelia-shell/bin/aurelia-plugin list
./aurelia-shell/bin/aurelia-plugin list --json
~~~

Third-party plugins remain disabled until explicit enablement:

~~~bash
./aurelia-shell/bin/aurelia-plugin enable example.panel
~~~

Enable placement for a bar-widget with one of the structured forms:

~~~bash
./aurelia-shell/bin/aurelia-plugin enable example.widget \
    --section right --index 0
./aurelia-shell/bin/aurelia-plugin enable example.widget \
    --after aurelia.network
~~~

The CLI uses the resident shell IPC boundary. It does not start a second
Quickshell process and does not execute plugin installation code.

## Development reload

Development launches may set AURELIA_DEVELOPMENT_MODE=1 or
AURELIA_HOT_RELOAD=1. The watcher observes only first-party and user plugin
trees, debounces changes, rescans manifests, and requests targeted reloads.

Saving a plugin QML, JavaScript, manifest, or related data file may reload that
plugin entry point in place. Resident services and keepLoaded owners are
retained when the change is unrelated. Core host files, services, shared
theme files, and Hyprland Lua remain an explicit host-restart boundary:

~~~bash
./aurelia-shell/bin/aurelia-restart-shell
~~~

If the watcher is unavailable or exits, the registry reports the condition and
explicit rescan remains available. A development reload is not a live system
configuration operation.

## Testing

There are no plugin-local test directories in the shipped Omarchy or Aurelia
architecture. Aurelia keeps one centralized test command:

~~~bash
./aurelia-shell/tests/run.sh
~~~

The test tree includes:

- generic manifest, discovery, catalogue, lifecycle, and failure contracts;
- every supported entry-point kind and first-party manifest inventory;
- bar placement, settings, multiple instances, popup ownership, and active
  replacement fallback;
- third-party facade scope, revocation, and sensitive-service isolation;
- local Git add, update, remove, clone, and rollback fixtures;
- development reload and preservation tests;
- focused feature tests for existing Aurelia behavior and design language.

Use temporary directories and isolated QuickShell fixtures. Do not run the
production installer or mutate a live Wayland workstation for ordinary plugin
testing. Live visual checks are a separately authorized phase.

When adding a plugin, the generic matrix must continue to pass and the plugin
must add focused tests for behavior that the generic contract cannot express.
Do not claim live or end-to-end behavior from static inspection alone.

## Maintenance commands

The supported user-level lifecycle commands are:

~~~text
validate [--first-party] [--manifest-file <name>] <directory>
list [--json]
catalog [--json]
rescan
enable <plugin-id> [placement options]
disable <plugin-id>
add <https-git-url> [--enable] [--yes]
update <plugin-id> [--yes]
update --all [--yes]
clone <aurelia.plugin-id> [--edit]
remove <plugin-id> [--yes]
~~~

Use --yes for non-interactive network or destructive lifecycle operations.
add is disabled by default; --enable is an explicit activation request.

Update flow:

1. Inspect catalog and current provenance.
2. Refuse local modifications rather than overwrite them.
3. Stage a bounded HTTPS Git checkout in a temporary directory.
4. Validate the staged manifest, tree, and entry points.
5. Show a diff/review path when applicable.
6. Publish atomically and rescan.
7. Restore the last known-good tree when validation or rescan fails.

Clone flow is restricted to first-party aurelia.* sources. It copies a
validated source tree into a user-owned ID, records clonedFrom provenance,
preserves declared safe clone paths, and does not edit packaged first-party
source. Removing a clone disables it first and leaves recoverable state where
the lifecycle policy requires it.

## Omarchy parity and Aurelia-retained behavior

Omarchy parity includes the manifest-driven plugin tree, supported kinds,
resident host, dedicated bar catalogue, source-aware registry, lifecycle
semantics, settings/placement model, explicit enablement, reload policy,
failure containment, plugin management, clone/update/remove workflow, and
centralized contract tests.

Aurelia intentionally retains its own feature-level behavior: the Aurelia
design-token system, notification service and DND/history model, image/video
background service, Command Center modules, keybindings ownership, network
and display backends, package-provider boundaries, Hyprland provider bridge,
and existing IPC aliases.

The following are deliberate differences or safety constraints, not a second
plugin architecture: centralized tests instead of plugin-local test folders,
the reserved aurelia. namespace, explicit no-hook lifecycle, untrusted
third-party warning, scoped facades, bounded operations, and compatibility
reads during migration.

## Minimal example source

The complete minimal example is in
aurelia-shell/examples/plugins/example.panel. Its Panel.qml:

- is an Item with safe defaults for optional injected properties;
- declares implicit dimensions;
- exposes open(payloadJson) and close();
- changes only its own in-memory visible state;
- performs no shell command, package mutation, privilege escalation, or
  install-hook execution.

Copy that directory for a starting point, change the ID and description, add
only the kinds and entry points you need, validate it, and add tests before
enabling it.
