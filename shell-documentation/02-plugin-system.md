# Plugin system

## Why plugins are effortless to add

The extensibility comes from a narrow, file-based contract rather than from
source-code registration:

1. A plugin is a directory with one JSON manifest at its root.
2. The host walks the first-party and user plugin directories.
3. The manifest names the plugin id, kinds, and relative entry-point files.
4. The registry validates and stamps the manifest with its source directory.
5. The host creates a QML `Component` from the requested entry point.
6. The host injects shared objects by capability (`shell`, `manifest`, registry,
   root path, and, for bar widgets, the inline settings object).
7. The user enables the plugin by adding an entry to the existing state file;
   no host source file changes.
8. Saving a user plugin file triggers a coalesced rescan and reload.

The host never needs to know the plugin's implementation class or feature
name. It only knows the manifest kind and the corresponding entry-point key.
That is the central design decision that makes third-party code a drop-in.

## Manifest contract

The runtime contract is JSON, schema version `1` only:

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
  "entryPoints": {
    "barWidget": "Widget.qml"
  },
  "keepLoaded": false,
  "barWidget": {
    "displayName": "Example widget",
    "description": "Shown in the widget catalogue",
    "category": "Status",
    "allowMultiple": false,
    "defaultSection": "center",
    "defaults": {},
    "settingsForm": "",
    "schema": []
  }
}
```

### Required runtime fields

The QML registry requires these fields to exist and have the following shape:

| Field | Runtime rule |
|---|---|
| `schemaVersion` | Must be the JSON number `1` |
| `id` | Non-empty string after coercion; must not contain `/`, `..`, or begin with `/` |
| `name` | Must exist; the runtime does not impose a non-empty string check |
| `version` | Must exist; the runtime does not parse semantic versions |
| `kinds` | Non-empty JSON array |
| `entryPoints` | Plain JSON object |
| every `entryPoints` value | Non-empty relative string, no leading `/`, and no `..` substring |
| `barWidget.defaultSection` | If present, exactly `left`, `center`, or `right` |

The runtime validator does not check that entry-point files exist and does not
enforce the kind-to-entry-point table. The author-facing CLI validator does;
production replicas should keep both checks and make the runtime fail closed
as well.

### Supported kinds

| Kind | Required entry-point key | Runtime owner | State representation |
|---|---|---|---|
| `bar` | `entryPoints.bar` | the single active bar loader | `bar.id` |
| `bar-widget` | `entryPoints.barWidget` | bar widget registry + bar slots | an entry in `bar.layout.left/center/right` |
| `panel` | `entryPoints.panel` | on-demand panel loader | an entry in `plugins[]` |
| `overlay` | `entryPoints.overlay` | on-demand overlay loader | an entry in `plugins[]` |
| `menu` | `entryPoints.menu` | on-demand menu loader | an entry in `plugins[]` |
| `service` | `entryPoints.service` | service host | an entry in `plugins[]` |

A manifest may declare more than one kind. A common composition is a service
plus a bar widget, or a menu plus a bar widget. The host loads a component only
through the entry-point key selected by that kind.

`keepLoaded: true` keeps a panel/overlay/menu loaded while closed, or keeps a
service instance across a plugin rescan. It is for stateful resources that must
survive summons or reloads, not a promise that edited code is hot-swapped in
place.

### Bar-widget metadata

The `barWidget` object is metadata consumed by the bar/settings catalogue. The
host normalizes it to:

```text
displayName    manifest name fallback
description    manifest description fallback
category       "Plugin" fallback
allowMultiple  true only for literal boolean true
defaults       {} fallback
settingsForm   "" fallback
schema         [] fallback
pluginId       manifest id
sourceDir      stamped manifest source directory
source         "plugin"
```

The metadata schema is descriptive: the bar engine passes the whole inline
entry to the widget. It does not automatically coerce settings. A setting
editor may use fields such as `type`, `key`, `label`, `description`,
`defaultValue`, `options`, `min`, `max`, `step`, `placeholderText`,
`emptyText`, and `noSelectionText`; the reference widgets still perform their
own final coercion and defaults.

`allowMultiple` describes the intended catalogue behavior. The registry does
not itself reject duplicate layout entries; an implementation that wants exact
source behavior must preserve that permissiveness and let each widget decide
whether multiple instances are meaningful.

The audited first-party metadata uses these extension patterns:

| Metadata pattern | Observed purpose |
|---|---|
| `allowMultiple: true` | indicator groups and spacers may appear more than once |
| `defaultSection: "right"` | optional cloud-sync and tunnel widgets prefer the right section |
| `settingsForm` | a widget-specific form name for spacer/weather settings |
| `schema` | declarative settings controls for indicators, agents, cloud-sync, and tunnel widgets |
| `clonePaths` | copy local dependencies when cloning a sibling-manifest widget |
| `activation: "on-demand"` | dashboard widget metadata; loading still follows the bar registry |

The source's clone mappings copy an indicator directory, a keyboard-layout
model, and a tray model. A generic clone implementation must copy every
declared entry point plus these explicitly declared local dependencies before
rewriting the manifest id.

Important boundary: in the audited `shell/` tree, `schema` and `settingsForm`
are carried into registry metadata but are not themselves rendered by a
generic settings-form engine. The surrounding CLI/UI outside this tree may
consume them. A 1:1 port must not claim automatic form generation unless it
also implements that separate consumer.

## Discovery algorithm

The runtime runs one generated Bash scan with the first-party directory as
`$0` and the user plugin directory as `$1`.

```text
first-party:
  find <first-party-dir> -mindepth 2 -maxdepth 3
       -type f \( -name manifest.json -o -name '*.manifest.json' \) | sort

third-party:
  for each immediate child directory of <user-plugin-dir>:
    accept only <child>/manifest.json
```

Each accepted file is framed as:

```text
===firstparty::<absolute-source-directory>===
<raw manifest JSON>
=== EOM ===
```

or `thirdparty` in the marker. The QML parser collects frames, parses JSON,
stamps `__sourceDir` and `__isFirstParty`, validates, and inserts the result
into a map keyed by manifest id. First-party entries are inserted first.

Third-party ids are rejected when the id already belongs to first-party code or
when it begins with the reserved built-in namespace. Thus the namespace is a
collision boundary, not merely a naming convention.

The resulting `installedPlugins` map is the runtime catalogue. A
`registryRevision` integer is incremented on every scan and registry change so
QML bindings that read through a `var` map reliably reevaluate.

## Author-facing validation

The CLI validator mirrors the registry and adds safety checks before a plugin
is moved into the user directory:

- manifest must be valid JSON;
- `schemaVersion` is the JSON number `1`;
- required fields must exist;
- id must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`, contain no `..`, and not use the
  reserved first-party namespace;
- every entry point must be an existing regular file under the plugin folder;
- a kind that needs a loader must have its corresponding key:
  `bar → bar`, `bar-widget → barWidget`, `menu → menu`, `overlay → overlay`,
  `panel → panel`, `service → service`;
- any `barWidget.defaultSection` must be one of the three bar sections;
- no symlink may occur inside the plugin folder (the `.git` directory is
  pruned from this check).

The CLI validator also requires user ids to be stricter than the runtime's
generic first-party validator. This is intentional: built-in ids are allowed
to use the reserved namespace, user ids are not.

## Runtime loading

### Bar option

There is always a safe bar path:

```text
configured bar.id missing or built-in id
        -> built-in bar Component
other id + valid bar manifest + safe entry point
        -> asynchronous plugin bar Loader
load error or unavailable id
        -> record failed id and fall back to built-in bar
```

Only one `bar` kind is active. Selecting a new one changes `bar.id`; disabling
the selected custom bar restores the built-in bar or its clone source. The
custom Loader is disabled while a plugin reload is in progress.

### Bar-widget registry

For every enabled manifest containing `bar-widget`, the host:

1. resolves `entryPoints.barWidget` to a `file://` URL;
2. normalizes metadata;
3. records an in-flight claim keyed by plugin id before asynchronous creation;
4. creates a QML `Component` asynchronously;
5. registers `{ component, metadata }` in `BarWidgetRegistry` when ready;
6. removes the claim and emits `pluginLoadFailed` on an error.

The in-flight claim prevents repeated scans from creating two components for
one URL. If the URL is unchanged but metadata changed, the existing component
is retained and metadata is refreshed in place.

`BarWidgetRegistry` is a single injected instance with:

```text
widgets: { id: { component, metadata } }
revision: integer
register(id, component, metadata)
unregister(id)
metadataFor(id)
availableIds()
has(id)
```

### Panel, overlay, and menu loaders

The host computes one loader entry for every enabled manifest declaring any of
`panel`, `overlay`, or `menu`. If multiple such kinds are declared, precedence
is `panel`, then `overlay`, then `menu`. The loader is active when either the
manifest says `keepLoaded: true` or `openPanelIds[id]` is true.

After load, the host injects the shared properties and, when the item exposes a
`service` property, passes the service with the same plugin id. A loader error
logs the detailed error and hides the plugin rather than leaving a phantom
open state.

The plugin entry point is expected to expose `open(payload)`, `close()`, and
usually `opened`; the host itself owns the logical open set and payload queue.

### Service loaders

Enabled first-party, non-authentication service manifests with
`entryPoints.service` are created under one hidden `serviceHost` item. The host
stores ordinary services in a map keyed by id and injects the same shared
objects as other plugin kinds. Third-party services and authentication services
are deliberately created without a visual QObject parent; they must not become
reachable through the host object graph, because that graph can expose
credential-bearing objects. Existing kept instances receive the fresh manifest
after a scan; they are not recreated. Services that are no longer present, no
longer declare a service entry point, or are no longer enabled are destroyed
and removed from the map. This parent distinction is source behavior, not an
implementation recommendation.

## Enablement model

Enablement is deliberately not one boolean with one meaning:

| Plugin type | Enabled when |
|---|---|
| full bar | `bar.id` is its id; missing `bar.id` means the built-in bar |
| bar widget | its id is present in one layout section; first-party component code remains loadable even when its widget is absent from the bar |
| first-party non-widget | true unless its id is in `disabledPlugins[]` |
| third-party non-widget | its id is present in `plugins[]` |

The CLI display reports a bar widget as enabled when it is on the bar, while
the runtime can still keep a first-party widget component available for a
future `put`. A full bar has `canDisable: false`: it is replaced by enabling a
successor, not turned off into an empty bar.

Removal is represented by deleting the user-owned layout/plugin entry. A
first-party non-widget is represented by adding its id to `disabledPlugins[]`.
There is no automatic uninstall or purge of personal data.

## Install, update, remove

### Add

The add flow is:

```text
parse args / prompt for URL
 -> reject git options and unapproved remote-helper schemes
 -> warn that code is unsandboxed
 -> confirm unless --yes
 -> clone into a temporary staging directory
 -> run plugin validator
 -> read id and compare against the complete catalogue
 -> reject duplicate id or existing target
 -> move staging directory into <user-plugins>/<id>
 -> request host rescan
 -> optionally wait for discovery, choose bar placement, enable
```

The installer does not run plugin code, install hooks, or sudo. It only clones,
validates, moves files, rescans, and toggles persisted state over IPC. Bare
interactive use prompts with terminal UI; `--yes` is the script/agent path.

The URL checker rejects command-like `-option` inputs and `helper::address`
transport-helper syntax. URL schemes are allowlisted to `ssh`, `git`,
`git+ssh`, `ssh+git`, `http`, `https`, `ftp`, `ftps`, and `file`.

### Update

An installed git plugin is updated by fetching `origin HEAD`, showing a diff
when interactive, and accepting only a fast-forward merge. Local changes block
the update. The updated checkout is validated after the merge; a failed
validation is rolled back to `ORIG_HEAD`. Updating all plugins iterates only
directories containing `.git`. A rescan is requested only if at least one
plugin changed.

### Remove

The remove flow first asks the running shell whether the plugin is enabled and
disables it before filesystem removal. A symlink is unlinked; a git checkout is
deleted; a non-git folder is moved to a uniquely timestamped hidden backup
instead of deleted. Removing an active clone also lets the registry restore
the source plugin and its previous state.

## Clone-and-customize path

Built-in code is not edited in place. The clone operation:

1. finds a first-party plugin by catalogue id;
2. copies the complete directory when it has a normal manifest, or copies the
   manifest plus every entry point and declared `clonePaths` mapping;
3. rejects unsafe clone target paths;
4. rewrites references when a copied dependency is renamed;
5. changes the id to `<username>.<source-id-without-prefix>`;
6. changes the display name to `My <source name>`;
7. writes `clonedFrom` metadata;
8. removes clone instructions from the copied manifest;
9. moves the staged copy into the user plugin directory;
10. rescans, waits for discovery, and enables the clone.

The registry routes calls naming the original id to an enabled clone. If the
clone is a bar widget, it replaces the source entry in the same section and
preserves its settings. If it is a non-widget first-party plugin, the source
is disabled and a restore marker is recorded. Removing the active clone
restores the source, including its prior bar position/settings or enabled
state.

## Hot reload and lifetime safety

The local plugin watcher observes recursively:

```text
close_write, create, delete, move
```

It ignores hidden staging/backup names and `.git`. Events are coalesced for
150 ms. A reload unloads ordinary panels, services, and widget components,
preserves `keepLoaded` services, clears the QML component cache, rescans, and
rebuilds. A summon arriving before a Loader is ready is queued per plugin id;
multiple payloads are preserved in arrival order.

The host explicitly disables Quickshell's own file watcher in the launcher.
This avoids a package upgrade reloading a half-written distribution tree. The
reference watcher is for user plugin files; a generic implementation should
make first-party development reload an explicit operation as well.

## Trust boundary

Plugins are unsandboxed in-process code. They can access everything available
to the user running the shell and can call external programs. The installer
warning and “review before enabling” state are therefore part of the product
contract, not optional UX. Manifest/path validation prevents accidental path
escape and collision; it does not make a plugin trustworthy or sandbox it.
