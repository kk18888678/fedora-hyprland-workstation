# Aurelia Shell Plugin Contract v1

Status: normative target contract for the Omarchy-parity migration.

This document defines the plugin contract that future Aurelia implementation
tasks must satisfy. It does not claim that the current runtime already
implements every item. Migration is governed by
[`AURELIA-OMARCHY-PLUGIN-PARITY-TRACKER.md`](../../docs/AURELIA-OMARCHY-PLUGIN-PARITY-TRACKER.md).

## Goals and boundaries

Aurelia adopts Omarchy's plugin architecture as the structural reference while
preserving Aurelia's existing features, identifiers, design language, backend
ownership, and safety rules.

The contract covers:

- first-party and user plugin packages;
- manifest discovery and validation;
- kind-specific entry points;
- resident and on-demand lifecycle;
- bar registration, placement, and settings;
- user configuration and cloning;
- scoped third-party APIs;
- failure containment and observability;
- CLI, development reload, and test requirements.

Plugins remain user-owned code. A plugin is never trusted merely because it has
a valid manifest.

## Package layout

First-party source lives under:

```text
aurelia-shell/plugins/<plugin-source>/
```

User plugins live under:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/aurelia/plugins/<plugin-id>/
```

A normal plugin source directory contains one `manifest.json` and all files
required by its declared entry points. First-party grouped directories may
also contain sibling `*.manifest.json` files for simple bar widgets, matching
the Omarchy layout where that is useful.

The `aurelia.` namespace is reserved for first-party plugins. User plugins must
use a different namespace and must not shadow a first-party ID.

## Canonical manifest

The canonical manifest shape is:

```json
{
  "schemaVersion": 1,
  "id": "author.example-widget",
  "name": "Example widget",
  "version": "1.0.0",
  "author": "Author",
  "license": "MIT",
  "description": "A short description",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "Widget.qml"
  },
  "keepLoaded": false,
  "barWidget": {
    "displayName": "Example widget",
    "description": "Shown in the bar catalogue",
    "category": "Status",
    "allowMultiple": false,
    "defaultSection": "center",
    "defaults": {},
    "settingsForm": "",
    "schema": []
  }
}
```

### Required fields

| Field | Contract |
|---|---|
| `schemaVersion` | JSON number `1` only. |
| `id` | Non-empty safe identifier; no `/`, `..`, or path interpretation. |
| `name` | Non-empty display name. |
| `version` | Non-empty plugin release version; not a host API version. |
| `description` | Non-empty human-readable description. |
| `kinds` | Non-empty array of supported kinds, with no duplicates. |
| `entryPoints` | Object containing the required entry point for every declared kind. |

### Kind-to-entry-point mapping

The canonical public mapping follows Omarchy:

| Kind | Required entry-point key | Meaning |
|---|---|---|
| `bar` | `bar` | Complete replacement bar; only one is active. |
| `bar-widget` | `barWidget` | Component registered with the active bar. |
| `panel` | `panel` | On-demand floating panel. |
| `overlay` | `overlay` | On-demand fullscreen/overlay surface. |
| `menu` | `menu` | On-demand menu surface. |
| `service` | `service` | Resident/headless service. |

The current Aurelia `entryPoints["bar-widget"]` spelling is a legacy input
form. It remains readable during migration, but canonical writes use
`entryPoints.barWidget` after the migration gate.

### Entry-point safety

Every entry-point value must be:

- a non-empty relative path;
- contained within the plugin source directory;
- free of absolute prefixes, `..` components, backslashes, colons, and
  unsupported control characters;
- an existing regular file at validation time;
- free of symlink traversal under the plugin-owned tree.

Discovery validates metadata and files before a loader can construct plugin
code. Discovery never executes plugin code.

### Bar metadata

Every `bar-widget` declares an operational `barWidget` object. Its metadata is
used by the bar registry and management UI:

- `displayName` and `description` identify the widget;
- `category` groups it in catalogues;
- `allowMultiple` controls duplicate instances;
- `defaultSection` selects `left`, `center`, or `right` when no placement is
  supplied;
- `defaults` provides values only when an instance has no user value;
- `schema` describes bounded settings controls;
- `settingsForm` optionally identifies a plugin-owned form adapter.

The metadata is descriptive and validated. It must not cause arbitrary code to
run during discovery.

### Optional metadata

- `keepLoaded` controls lifecycle persistence and must be boolean.
- `activation` may describe `on-demand` behavior when a host feature consumes
  it; it must not silently override kind lifecycle rules.
- `aurelia.clonePaths` may declare safe local files/directories needed when a
  first-party plugin is cloned. Clone sources and targets must stay inside the
  plugin tree and may not be duplicated.
- `aurelia` metadata may describe Aurelia-specific compatibility only. It must
  not grant a user plugin trusted capabilities.

## Runtime lifecycle

The resident Aurelia host owns one registry, one lifecycle host, one active bar,
and the shared service/component catalogues.

```text
scan -> validate -> catalogue -> resolve enabled state
     -> load services and kept surfaces
     -> register bar widgets
     -> load panels/overlays/menus on demand
```

The host, not plugin UI, owns loader activation and persisted state mutation.

### Lifecycle rules

- `service` plugins have one resident service instance per enabled ID.
- `keepLoaded: true` keeps an eligible panel, overlay, menu, or service mounted
  across close/rescan according to its declared kind.
- `bar-widget` components are registered independently from the full bar and
  are instantiated only for configured bar instances.
- `bar` plugins participate in active-bar selection; exactly one full bar is
  active at a time.
- `panel`, `overlay`, and `menu` instances are loaded on demand and receive
  queued payloads in order.
- Disabling removes active runtime ownership without purging user data.
- Removing a plugin source is distinct from disabling it and from purging any
  user-owned files.

## Host survivability contract

A faulty plugin must not make the Aurelia shell unusable.

For malformed manifests, missing/unsafe entry points, QML syntax/import errors,
initialization failures, service construction failures, bar-widget failures,
callback exceptions, and reload-time failures, the required result is:

```text
faulty plugin
  -> reject, contain, unload, or quarantine only that plugin
  -> record bounded diagnostics
  -> keep Aurelia host alive
  -> keep shell ping/listPlugins available
  -> keep healthy plugins available
  -> keep the built-in bar fallback available
```

Host-to-plugin calls (`open`, `close`, `toggle`, `call`, and bar-widget
invocation) are guarded at the boundary. A repeatedly failing plugin must not
enter an uncontrolled retry/reload loop.

This behavior is the P0 requirement in T02A. It requires isolated runtime
fixtures, not only source inspection.

### Same-process limitation

Plugins execute as unsandboxed QML in the resident Quickshell process, matching
Omarchy's architecture. Loader and callback containment protects against
ordinary faulty plugin behavior but cannot guarantee survival if deliberately
malicious code calls `Qt.quit()`, triggers a native crash, or corrupts the QML
engine. A true process-level guarantee would require an out-of-process sandbox
and would not be 1:1 with Omarchy.

This limitation must be visible in user documentation and must never be called
a security sandbox.

## Persisted state

The canonical state document is one user-owned `shell.json`:

```json
{
  "version": 1,
  "idle": {},
  "bar": {
    "id": "aurelia.bar",
    "position": "top",
    "transparent": false,
    "centerAnchor": "aurelia.clock",
    "layout": {
      "left": [{ "id": "aurelia.workspaces" }],
      "center": [{ "id": "aurelia.clock" }],
      "right": []
    }
  },
  "plugins": [
    { "id": "author.example-panel" }
  ],
  "disabledPlugins": []
}
```

Rules:

- the active full bar is `bar.id`;
- bar-widget instances are entries in `bar.layout.<section>`;
- other plugin instances are objects in `plugins[]`;
- settings are inline on the instance object;
- first-party plugins are enabled by default unless disabled explicitly;
- third-party plugins are enabled only when explicitly present;
- `allowMultiple` is enforced at the instance boundary;
- old Aurelia string IDs and legacy bar-widget entry-point keys remain readable
  until T27;
- state writes are atomic, idempotent, recoverable, and preserve user-owned
  values outside the managed namespace.

## Plugin API boundary

First-party plugins may receive trusted host objects where existing internal
behavior requires them. Third-party plugins receive only owner-scoped facades:

- self-scoped plugin registry view;
- self-scoped lifecycle and settings API;
- scalar/detached bar API;
- read-only application-library API where explicitly allowed;
- detached bar-widget catalogue for replacement bars;
- explicitly allowlisted non-sensitive service projections.

Third-party plugins do not receive raw `PluginRegistry`, `ShellConfig`, active
bar objects, unrestricted shell IPC objects, or host-internal manifest fields.
Facade callbacks enforce ownership in the host closure and are revoked when
plugin state or capability profiles change.

## CLI and development workflow

The plugin CLI owns user-level source lifecycle only:

```text
validate
catalog/list
rescan
enable/disable
add
update [id|all]
clone
remove
```

The CLI must:

- validate before activation;
- keep plugins disabled until explicit enablement;
- use bounded, non-interactive Git transport for automation;
- provide human review and diff paths for interactive operations;
- stage updates before replacing installed source;
- reject duplicate IDs before installation;
- refuse updates over local modifications;
- roll back failed validation/rescan transitions;
- make manual plugin removal recoverable;
- record source and commit/ref provenance;
- never run plugin install hooks or sudo.

Development reload watches only plugin trees, debounces saves, preserves
stateful services, and never replaces the explicit restart boundary for the
host core, shared services, theme core, or Hyprland Lua.

## Testing contract

Every supported kind and lifecycle path has both generic contract tests and
focused feature tests. Required test domains are:

- manifest enumeration and validation;
- discovery/catalogue and duplicate resolution;
- runtime entry-point construction;
- host survivability under each T02A failure class;
- service, panel, overlay, menu, bar-widget, and replacement-bar lifecycle;
- bar placement, settings, and multiple instances;
- third-party facade scope and revocation;
- CLI add/update/remove/clone/rollback using local Git fixtures;
- development reload;
- preservation of every existing Aurelia feature and design-language invariant.

Static tests may support these claims but cannot replace isolated runtime tests
where loader or process survivability is being asserted.

## Migration rule

Migration is additive and compatibility-first:

1. read old Aurelia forms;
2. validate and normalize into the canonical model in memory;
3. prove the normalized result in isolated tests;
4. write canonical state only after the cutover gate;
5. preserve a recoverable pre-migration state;
6. verify a second run is byte-stable and produces no unnecessary backup;
7. remove compatibility code only in a separately reviewed cleanup.

No migration may alter Aurelia's visual defaults, feature availability, backend
ownership, login architecture, or user-owned data.
