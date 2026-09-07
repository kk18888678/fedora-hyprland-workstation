# Plugin management and runtime lifecycle

This document traces the complete lifecycle of shipped, cloned, hand-authored,
and Git-installed plugins. It complements 02-plugin-system.md,
12-full-plugin-lifecycle.md, and 19-plugin-facade-api-reference.md by joining
the CLI, filesystem, registry, host loader, live surface, reload, update, and
removal transitions.

## Trust and ownership boundary

Plugin QML and JavaScript run as arbitrary unsandboxed code inside the
long-lived shell process. The add command warns about this before cloning and
enabling. A manifest and safe relative entry point prevent path escape; they do
not sandbox the plugin or make its author trusted.

The source has two validators:

| Validator | Role |
|---|---|
| CLI omarchy-plugin-validate | author/install gate; checks files exist, required kind entry points, no symlinks, and reserved ids |
| QML PluginRegistry.validateManifest | runtime gate; checks manifest shape, required fields, safe relative entry-point values, and valid barWidget.defaultSection |

They are intentionally not identical. The QML validator does not prove entry
point existence, kind/entry-point correspondence, or recursive symlink absence;
the CLI validator does. A source-faithful implementation must not document the
runtime validator as stronger than it is.

## Lifecycle overview

~~~text
source selection
    -> transport check
    -> user confirmation
    -> isolated clone/copy stage
    -> CLI manifest/file validation
    -> collision check
    -> atomic move into user plugin directory
    -> host rescan
    -> enable decision and placement
    -> registry validation/merge
    -> component/service/panel loader
    -> host facade injection
    -> user interaction
    -> file watcher or explicit rescan
    -> serialized teardown/reload
    -> disable/remove/update/backup
~~~

## Add a Git plugin

### Request and URL check

The add command accepts one optional URL, --enable, and --yes. Without a URL it
requires an interactive terminal and asks for one. Without --yes it confirms
that the repository should be cloned and warns that plugin code is unsandboxed.

Before cloning, the shared URL checker rejects:

~~~text
leading dash
<helper>::<address> transport-helper form
unknown scheme://<address>
~~~

The allowed schemes are ssh, git, git+ssh, ssh+git, http, https, ftp, ftps,
and file. A missing checker is a failure; the command does not clone.

### Stage, validate, and install

The source add flow:

1. creates the user plugin directory;
2. removes its own previous process-id staging path;
3. runs git clone with an explicit end-of-options separator;
4. runs the CLI validator on the staging directory;
5. reads the manifest id;
6. compares that id against the catalog of installed ids;
7. rejects an existing id or path;
8. moves the stage into the final user plugin directory;
9. asks the running shell to rescan.

The manifest must have schemaVersion 1, id, name, version, non-empty kinds,
entryPoints, safe relative entry-point files, and no reserved omarchy.* id.
Kinds requiring entry points are:

~~~text
bar        -> entryPoints.bar
bar-widget -> entryPoints.barWidget
menu       -> entryPoints.menu
overlay    -> entryPoints.overlay
panel      -> entryPoints.panel
service    -> entryPoints.service
~~~

### Enable after add

If --enable was supplied, or interactive confirmation chooses enable, a
bar-widget-only plugin can ask for a section. Its defaultSection is used as the
initial choice unless the user chooses left, center, or right. The command waits
up to 40 attempts of 50 ms for the shell catalog to discover the new id before
calling enable.

Without enable, the plugin remains installed but is not active. A later enable
call chooses:

~~~text
bar option      -> bar.id
bar widget      -> insert/move in bar.layout section
other user kind -> append to plugins[]
~~~

Placement can specify section, index, before, or after. A bar option cannot be
placed in a section; enabling it selects the active bar.

## Registry rescan

### Directory scan

The registry creates the user plugin directory at startup. Its scan process
emits framed manifest records:

~~~text
===firstparty::<absolute source>===
manifest JSON
=== EOM ===
===thirdparty::<absolute source>===
manifest JSON
=== EOM ===
~~~

First-party manifests are found two or three levels below the shipped shell
plugin directory, including sibling *.manifest.json files for grouped bar
widgets. Third-party plugins are only top-level directories under the user
plugin directory, each with manifest.json.

### Parse and merge

Each frame is parsed, stamped with sourceDir and first-party status, and passed
through the runtime validator. Host capabilities are declared only for
first-party manifests. A third-party clone inherits the source plugin's
declared host capability list only when its omarchy.clonedFrom points to that
first-party id.

The merge order is:

~~~text
all valid first-party ids
    -> valid third-party ids not colliding with first-party
    -> reject every third-party id beginning omarchy.
~~~

On completion the registry replaces installedPlugins, increments
registryRevision, clears scanning, emits pluginsChanged, and emits scanFinished.
Invalid manifests are skipped with a diagnostic; one bad plugin does not erase
valid registry entries.

### Enablement

The registry answers several different questions:

~~~text
isEnabled(id)      -> should its component/service be loaded?
inBar(id)          -> is its widget present in a bar layout?
resolveEnabledId  -> should a built-in id route to an active clone?
~~~

Exact enablement:

| Plugin | Enabled when |
|---|---|
| selected bar option | bar.id equals id, with built-in fallback |
| first-party non-bar kind | enabled by default unless disabledPlugins contains id |
| first-party bar widget | component remains available; visible only when placed in bar layout |
| third-party bar widget | id is in a bar layout |
| third-party panel/overlay/menu/service | id is in plugins[] |

An empty plugins array therefore does not disable first-party infrastructure.
Removing a first-party widget from the bar removes placement, not the component
source. Normal deselection is not removal.

## Runtime loading

### Bar options

The selected replacement bar loads asynchronously. Before becoming live, the
host injects repository path, scoped shell facade, public manifest, widget
registry, plugin registry, and bar configuration. A failure logs and falls
back to the built-in bar.

### Bar widgets

Every enabled manifest with kind bar-widget is registered from its barWidget
entry point. The normalized metadata includes display name, description,
category, allowMultiple, defaults, settingsForm, schema, source directory,
first-party status, and plugin id.

The registry claims an in-flight URL before creating its asynchronous Component.
If the same URL is encountered during another scan, the second load is not
started. A matching ready component receives refreshed metadata in place. An
error removes the claim and emits pluginLoadFailed.

A live bar slot then injects:

~~~text
bar          -> first-party Bar object, or scoped PluginBarApi
moduleName   -> canonical layout id
settings     -> inline layout entry settings
~~~

### Panels, overlays, and menus

The host computes enabled panel entries from kinds panel, overlay, and menu.
Each gets one Loader whose active condition is keepLoaded or
openPanelIds[id]. When loaded, the host injects:

~~~text
omarchyPath
shell facade
public manifest
bar-widget registry facade
plugin registry facade
matching first-party service, if present
~~~

The loader is registered only after these injections. A loader error logs the
detail and calls shell.hide(id). Generic summon queues payload JSON until the
asynchronous loader is ready, then calls plugin.open(payload).

### Services

Enabled service plugins are loaded into a hidden service host. First-party
normal services are parented to that hidden host. Third-party and
authentication-capable service objects are created without a visual QObject
parent and are retained in the relevant private JavaScript store. This keeps
headless service lifetime separate from visual surface lifetime.

## Host IPC and scoped facades

The shell IPC target resolves ids, enforces enabled/unknown checks, and routes:

~~~text
summon(id,payload) -> bar widget route or generic panel queue
hide(id)           -> bar widget close or loaded item close
toggle(id,payload) -> is open ? hide : summon
call(id,method,arg) -> loaded item method, with ok/unknown/error result
~~~

Plugin code does not receive the unrestricted host object by default. It gets
scoped facades with owner checks:

~~~text
PluginShellApi
PluginRegistryApi
PluginBarWidgetRegistryApi
PluginAppLibraryApi
PluginBarStateApi
PluginFirstPartyServiceApi
PluginBarApi
~~~

The exact properties, methods, ownership tests, cached instances, and allowed
first-party service proxies are in 19-plugin-facade-api-reference.md. A facade
created for one owner must reject another plugin's target id. Cached facade
objects are invalidated when the owning plugin disappears or changes source.

## Clone a first-party plugin

### Copy and rename

The clone command accepts a first-party source id and optional --edit. It reads
the first-party catalog, creates a username-prefixed id, and derives display
name My <source name>. It refuses an existing target.

The clone is staged under the user plugin directory using mktemp. It copies:

~~~text
all entry-point files
all manifest-declared clone paths
~~~

Each clone target must be relative and must not contain .. . Copying uses
cp -aL. The clone manifest changes id/name/barWidget display name, adds
omarchy.clonedFrom, and removes clonePaths. References to the source path/id
are replaced in copied files when the source and target names differ.

The completed stage is moved to the final target. The command rescans, waits
up to 40 × 50 ms for discovery, then enables the clone. If the clone fails
before completion, its cleanup removes the stage and target.

### Clone replacement

Enabling a clone of a first-party plugin replaces the source's effective
placement:

~~~text
bar clone        -> bar.id selects clone
bar-widget clone -> source layout entry is replaced by clone entry
other clone      -> source plugin is disabled and clone is added
~~~

cloneSourceRestores records whether the source was disabled so removal can
restore it. A caller naming the built-in id is resolved to the active enabled
clone through clonedFrom.

The cloned idle service is the special case that receives a scoped copy of the
idle configuration. The clone may control only the source-defined allowed
targets and capabilities; it does not receive unrestricted service access.

## Update lifecycle

The update command can target one Git checkout or all installed Git checkouts.
It:

1. disables terminal prompting and uses batch-mode SSH;
2. fetches origin HEAD;
3. reports up-to-date when HEAD equals FETCH_HEAD;
4. shows the diff and asks for confirmation unless --yes;
5. fast-forwards only;
6. validates the updated checkout;
7. hard-resets to ORIG_HEAD if validation fails;
8. reports the updated ids;
9. asks the shell to rescan only when at least one update succeeded.

Non-Git directories are not treated as update candidates. Local changes that
prevent fast-forward fail rather than being overwritten.

## Disable and remove lifecycle

### Disable

Disable sends setPluginEnabled(id, false). For a bar option it returns to the
source bar or built-in default. For a bar widget it removes only its layout
entry. For other first-party plugins it adds the id to disabledPlugins. For a
third-party plugin it removes the plugins[] entry.

The underlying unknown disable path can return success after a no-op config
rewrite; unknown summon still fails. This is a source quirk, not a reason to
invent an imaginary error response.

### Remove

The remove command reads whether the plugin is enabled and whether it is a
clone. It asks for confirmation unless --yes:

~~~text
symlink -> ask to unlink
Git checkout -> ask to delete repository
other folder -> ask to remove and back it up
~~~

If enabled, it disables/unloads first. Then:

~~~text
symlink      -> rm -f link
Git checkout -> rm -rf plugin directory
other folder -> mv to .<id>.bak.<UTC timestamp>, adding numeric suffix on collision
~~~

The non-Git folder is recoverable through the backup path; Git removal is
destructive to the local checkout but the upstream repository remains. A
rescan follows. If an enabled clone was removed, the source placement and
disabled state are restored according to cloneSourceRestores.

## File-watcher reload

The registry watches the top-level user plugin tree recursively for
close_write, create, delete, and move. It maps a changed path to the first
non-hidden plugin directory and emits localPluginChanged.

The host debounces local changes for 150 ms. Reload:

~~~text
if scanning/reloading -> set reload pending
else
    -> pluginReloading = true
    -> unload panel loaders
    -> unload service objects
    -> unregister bar widget Components
    -> next event turn
    -> clear Qt component cache when available
    -> rescan
    -> rebuild services/panels/widgets
~~~

When the scan finishes during a pending reload, the host clears the current
reload and schedules another serialized cycle. No second scan/teardown may
overlap.

keepLoaded preserves an enabled panel instance across ordinary open/close; it
does not hot-swap QML code. A source change goes through the full teardown.

## Terminal failure behavior

| Failure point | Required result |
|---|---|
| URL transport check | reject before clone |
| confirmation cancelled | no filesystem mutation |
| clone failure | remove only the command's own stage |
| manifest validation | remove stage; do not install |
| id collision | retain existing plugin; remove stage |
| registry invalid manifest | skip one plugin, keep other registry entries |
| QML component error | remove component claim and log |
| panel loader error | log and hide plugin |
| update fast-forward conflict | leave local checkout unchanged |
| update validation error | roll back to ORIG_HEAD |
| reload during scan | queue one later reload |
| remove ordinary folder | move to recoverable backup |

## Acceptance checks

1. Add a valid third-party bar widget without enabling it, then enable it with
   each placement form and verify registry/slot/injection state.
2. Reject malformed ids, reserved ids, unsafe entry points, missing files,
   missing kind entry points, symlinks, URL helpers, and duplicate ids.
3. Install a plugin with panel, overlay, menu, service, and bar-widget kinds
   and verify the correct loader/enablement branch for each.
4. Clone one bar option, one bar widget, and one service; verify source
   replacement, clonedFrom routing, configuration exposure, and removal
   restoration.
5. Edit a local plugin repeatedly during a scan and verify serialized reload,
   no duplicate handlers, and no stale facades.
6. Update a clean Git checkout, a locally modified checkout, and a checkout
   that fails post-merge validation.
7. Remove a symlink, Git checkout, and ordinary folder and verify their
   distinct cleanup/backup outcomes.

