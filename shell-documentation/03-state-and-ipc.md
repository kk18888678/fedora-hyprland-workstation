# Persisted state and IPC

## One configuration file

The shell intentionally has one user-owned JSON file. It records the complete
customization state rather than a collection of per-feature fragments.

```text
<user-config>/<namespace>/shell.json       # user authority after first edit
<distribution-root>/config/<namespace>/shell.json
                                             # shipped fresh-install defaults
<user-config>/<namespace>/plugins/<id>/     # plugin source, not settings
```

When the user file is missing, empty, invalid JSON, or does not contain the
numeric top-level `version: 1`, the host uses the bundled default object (or
its small in-QML fallback). When a valid user file exists, it replaces the
defaults as a whole. There is no deep merge. This is important: removing a
field from the user file does not cause the shipped field to reappear.

The host reads both files with watched `FileView`s. The user file uses atomic
writes. Writes serialize a deep-cloned object as two-space-indented JSON plus a
final newline and force `version` back to `1`.

## Canonical shape

```json
{
  "version": 1,
  "idle": {
    "screensaver": 150,
    "lock": 300
  },
  "bar": {
    "id": "<built-in-bar-id>",
    "position": "top",
    "transparent": false,
    "centerAnchor": "<clock-like-widget-id>",
    "layout": {
      "left": [
        { "id": "<menu-widget-id>" },
        { "id": "<workspace-widget-id>" }
      ],
      "center": [
        { "id": "<clock-widget-id>", "format": "dddd HH:mm" }
      ],
      "right": [
        { "id": "<audio-widget-id>" }
      ]
    }
  },
  "plugins": []
}
```

The shipped reference configuration expands the center and right sections with
status widgets and optional integrations. The essential shape above is the
fallback that permits the shell to render a usable bar even if the default
file cannot be read.

## Fresh-install baseline

The audited shipped default uses this layout. The ids below are role labels so
the blueprint stays generic; use one stable namespaced id per capability in a
real port.

```text
idle:
  screensaver = 150 s
  lock        = 300 s

bar:
  position      = top
  transparent   = false
  centerAnchor  = clock widget

  left:
    menu launcher
    workspace switcher

  center:
    indicator group
    clock/calendar (format "dddd HH:mm",
                    alternate "d MMMM 'W'ww yyyy",
                    vertical "HH\n—\nmm")
    keyboard layout
    weather
    system update

  right:
    system tray
    agent usage
    Bluetooth
    network
    audio
    display
    power

plugins = []
```

An empty `plugins` array is intentional: first-party non-bar infrastructure is
enabled by default. Optional first-party integrations are self-hiding when
their data/utility is absent; the configuration still ships their widget
entries so they can appear without a manual add step.

The exact source IDs and order for this role-oriented baseline are preserved in
the [shipped bar state crosswalk](12-full-plugin-lifecycle.md#exact-shipped-bar-state-crosswalk).

### Field rules

| Field | Rule |
|---|---|
| `version` | Required numeric `1`; unknown versions fall back to defaults |
| `idle.screensaver` | Seconds since the idle cycle begins; default `150` |
| `idle.lock` | Seconds since the idle cycle begins; default `300` |
| `bar.id` | Missing or built-in id selects the built-in bar; another valid `bar` plugin replaces it |
| `bar.position` | `top`, `bottom`, `left`, or `right`; invalid values normalize to `top` |
| `bar.transparent` | Literal JSON boolean controls transparent mode |
| `bar.centerAnchor` | Widget id pinned to the exact center; empty disables anchoring |
| `bar.layout.left/center/right` | Arrays of entries; all other layout values normalize to empty arrays |
| layout entry | String becomes `{ "id": string }`; object is deep-cloned and requires a truthy `id` |
| `plugins[]` | Array of `{ "id": string, ...inline settings }` entries for non-bar plugin kinds |
| `disabledPlugins[]` | User record of disabled first-party non-widget ids |
| `cloneSourceRestores[]` | Internal clone bookkeeping for restoring a previously active source |

Settings are inline. There is no `config` child object, no separate settings
file, and no merge layer. Every field beside `id` in a layout/plugin entry is
passed as that component's `settings` object.

Multiple entries with the same id are allowed by the raw JSON shape. A widget
whose manifest allows multiple instances receives each entry independently;
the bar's live in-place settings optimization refuses to treat duplicate ids
as unambiguous.

### Enablement is presence-based

For a user plugin, “enabled” means that its id appears in the right place:

```text
full bar       -> bar.id
bar widget     -> any bar.layout section
panel/overlay/menu/service
               -> plugins[]
```

For first-party non-bar plugins, the default is enabled and an id in
`disabledPlugins[]` is the exception. For a first-party bar widget, removing it
from the bar only removes its layout entry; its component remains available to
be placed again. Deselection is not removal and never deletes the plugin
source, personal data, or system package.

## Configuration mutation ownership

Only the shell host owns the in-memory canonical object. A mutation helper:

```text
copy = deepClone(currentConfig or builtinConfig)
mutator(copy)
copy.version = 1
shellConfig = copy
atomicWrite(userConfig, prettyJSON(copy) + newline)
```

CLI helpers use the same semantic pipeline through `jq`: normalize the source
into an object with version `1`, a bar object, three layout arrays, and a
plugins array; write to a `mktemp` file; rename into the user path; ask the
running shell to reload. Bar placement is sent to the shell rather than
editing the file behind its back, because the shell owns the object currently
being rendered.

Inline settings use a more conservative path. The host clones the config,
finds the entry in a bar section or top-level plugin list, constructs a new
entry with the same id and supplied settings, compares JSON strings, and
persists only if something actually changed. This prevents a reactive write
from needlessly rebuilding the bar.

## Layout operations

### Placement resolution

An insertion request can specify:

```text
section: left | center | right
index: non-negative integer
before: existing widget id
after: existing widget id
```

`before` and `after` are mutually exclusive. A target id is resolved in the
requested section when one was provided; without a section the lookup spans
all sections. An explicit index is clamped to the target section's length.

When no explicit target is given, the reference uses one semantic anchor per
section and inserts immediately after it:

```text
left   -> workspace-like anchor
center -> weather-like anchor
right  -> tray-like anchor
```

If the anchor is absent, insertion appends. The system-tray widget is then
normalized to the inner edge of its section: the right-section tray is first;
left/center trays are last. This keeps its reveal drawer next to the desktop
rather than stranded in the middle of a section.

`put` is idempotent: if the widget (or its active clone) is already in the bar,
it leaves its position untouched. A missing `before`/`after` target falls back
to the widget's ordinary location. `move` removes the existing entry, resolves
the new target, and reinserts the same object; a failed target restores the
original position.

### Live settings vs structural reload

The bar compares normalized ids and order in all three sections. If only one
unambiguous non-custom entry's inline settings changed, it updates the live
widget's `settings` property. Any structural change, custom module, or repeated
id rebuilds the layout. The distinction preserves popup/service state while
still making layout edits deterministic.

## Host IPC target

The host exposes a stable target named `shell`. IPC arguments are strings; JSON
is passed explicitly where a structured value is needed.

| Method | Arguments | Return | Behavior |
|---|---|---|---|
| `ping` | none | `ok` | health check |
| `applyTheme` | base64 colors, base64 shell tokens | `ok` | decode and apply palette/geometry; schedule compositor refresh |
| `rescanPlugins` | none | void | unload/reload replaceable plugin objects and rescan |
| `reloadConfig` | none | `ok` | reload user JSON |
| `toggleBarTransparency` | none | `ok`/`no-bar` | persist the inverse of requested transparency |
| `setPluginEnabled` | id, enabled string | `ok`/`unknown` | only literal string `true` enables; every other value disables |
| `enablePlugin` | id, placement JSON | `ok`/error text | enable and optionally place; validates JSON placement |
| `putBarWidget` | id, placement JSON | `ok`/error text | idempotently place a bar widget |
| `moveBarWidget` | id, placement JSON | `ok`/error text | move an existing widget |
| `setBarWidget` | id, key, value JSON, selector JSON | `ok`/error text | write one inline value |
| `listPlugins` | none | JSON array | all discovered plugins, sorted by name then id |
| `listShellConfig` | none | JSON object | effective in-memory config |
| `debugBarGeometry` | none | JSON array | live slot coordinates/sizes and visibility |
| `summon` | id, payload JSON | `ok`/`unknown` | resolve clone, verify enabled, open or queue payload |
| `hide` | id | void | close and clear logical open state |
| `toggle` | id, payload JSON | void | hide if open, otherwise summon |
| `togglePanelAt` | section, one-based index | id/`unknown` | toggle the nth visible panel in a section |
| `call` | id, method, one argument | string | call a method on an already-loaded plugin |

`listPlugins` reports `enabled`, `active`, `canDisable`, `firstParty`, and
clone-source metadata. A full bar reports `canDisable: false`.

## Panel routing and payload queue

The host resolves a caller id through the enabled clone map first. Then:

```text
unknown id                  -> false / unknown
known but disabled          -> false / unknown
enabled bar-widget panel    -> route to the selected per-monitor bar instance
enabled panel/overlay/menu  -> mark openPanelIds[id] = true
                              queue payloadJson[id]
                              deliver immediately if already loaded
not-yet-loaded component    -> Loader becomes active and receives all queued
                              payloads in arrival order
```

`hide` invokes `close` when available, removes the id from the open set, and
returns success even when a panel was not loaded. `call` returns `unknown` when
the target is not loaded or lacks the method; a thrown method returns `error`.

Bar-widget panels are special because a bar exists once per monitor. A single
fixed IPC handler must not accidentally refresh only whichever monitor
registered first. The bar chooses an already-open instance first, otherwise
the instance on Hyprland's focused monitor, otherwise the drawn slot rather
than an anchored zero-size placeholder.

## Image-selector IPC target

A stable secondary target bridges older shell callers that need positional
arguments:

```text
open(imageDirs, imageRowsBase64, selectedImage,
     selectionFile, doneFile, showLabels, filterable) -> ok/unknown
preload(imageRowsBase64, selectedImage, showLabels, filterable) -> ok
cancel(doneFile) -> ok
ping() -> ok
```

Rows are base64-encoded so tabs/newlines survive the shell/argv boundary. A
caller creates temporary `selectionFile` and `doneFile`; the picker writes the
selected path and touches the done file. Cancellation clears/touches the done
file without writing a selection. The image picker keeps its window loaded
between summons.

## CLI wrapper behavior

The generic `shell-ipc` wrapper should mirror these source decisions:

- require a configured distribution root and a readable shell entry point;
- recover `WAYLAND_DISPLAY` from the newest session socket for callers outside
  the graphical environment;
- add `{}` for a shell-level summon/toggle missing a payload;
- run the IPC command under a bounded timeout (reference default: `2s`, with
  `1s` kill-after);
- distinguish timeout/not responding, no shell, target/method errors, and
  “not ready” startup output;
- offer quiet best-effort mode for indicator refreshes; quiet failures return
  success and emit no output.

The wrapper forwards calls and never starts the host. Startup/restart is owned
by the session launcher and supervisor.

## Popout contract

Every bar-attached panel requests ownership from the bar before opening. The
bar stores exactly one `activePopout`; opening a new one closes the old owner
through `closeForPopoutSwitch` when available, then transfers ownership.

`PopupCard` is an anchored popup with a click focus grab. `KeyboardPanel` is a
full-screen layer-shell surface whose visible card is positioned inside it:

- top bar: card below the bar, centered under the anchor;
- bottom bar: card above the bar;
- left bar: card to the right;
- right bar: card to the left;
- `centerOnBar`: center along the output axis while staying outside the bar;
- clamp card edges to `margin = Style.gapsOut`.

Keyboard panels briefly use `Exclusive` focus for `75 ms` after mapping, then
settle to `OnDemand`. The prime makes a keyboard summon focusable; the settled
mode prevents the panel from capturing pointer input across every output.
The visible card fades for `140 ms`. The full-screen dismissal surface remains
mapped; its bar-region handler forwards clicks to registered bar targets so the
bar remains usable, and other monitors receive transparent pointer-only
dismissal twins.
