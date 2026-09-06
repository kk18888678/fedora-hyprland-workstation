# Aurelia Shell Plugins

This directory contains first-party Aurelia Shell plugins. First-party and
user plugins share the same manifest contract; only their source roots differ.

## Minimal panel plugin

```json
{
  "schemaVersion": 1,
  "id": "example.weather",
  "name": "Weather",
  "version": "1.0.0",
  "kinds": ["panel"],
  "entryPoints": { "panel": "Panel.qml" }
}
```

The entry-point file is a QML `Item`. The host injects `aureliaPath`, `shell`,
`manifest`, and `pluginRegistry` after URL loading. These properties must have
safe defaults because URL-loaded QML is constructed before `Loader.onLoaded`.
Panel, overlay, and menu entry points should implement `open(payloadJson)` and
`close()`. Use plugin-scoped IPC for direct component operations.

Plugins execute in the resident shell process and are not sandboxed. Review
third-party source before enabling it. Keep plugin code self-contained and use
the shell services/IPC boundary rather than reaching into another plugin's
 internal ids.

## Bar widget contract

The first-party `aurelia.bar` plugin is the resident bar surface. It owns the
layer-shell bar window and reads the normalized `bar` object from
`~/.config/aurelia/shell.json`; it does not decide whether Noctalia should be
replaced. A bar layout entry has this small shape:

```json
{
  "id": "aurelia.clock",
  "icon": "clock",
  "format": "HH:mm"
}
```

Widget settings are inline on the layout entry, matching the Omarchy bar
schema. Aurelia also reads the earlier nested `settings` shape for a safe
transition, but normalized state is written inline.

Manifest metadata may include an optional validated `icon` name. It is a
Freedesktop/Yaru-compatible icon identifier, not a filesystem path; callers
can resolve it with `Quickshell.iconPath()` and supply their own fallback.

The three layout regions are `left`, `center`, and `right`. `centerAnchor`
keeps a named center widget at the exact horizontal center. A plugin that wants
to render in the bar adds a `bar-widget` entry point to its manifest. The bar
injects `bar`, `shell`, `moduleName`, `settings`, `manifest`, and
`pluginRegistry`; the widget should expose `implicitWidth` and
`implicitHeight`, and summon richer panels through the resident shell IPC.

The shipped screenshot plugin demonstrates the bar-only contract: its
`bar-widget` entry point renders the camera action and internally loads the
capture surface. The full-screen panel is therefore an implementation detail
of the bar action, not a second standalone bar or application surface.

## Current desktop slices

- aurelia.screenshot: bar-only camera widget with an internal capture surface,
  backed by Fedora-owned grim, slurp, and wl-copy tools. It supports
  full-screen, region, window, delayed, file, and clipboard capture. Its
  plugin-owned `SUPER + SHIFT + S` binding opens quick region capture and
  captures immediately after selection.
- aurelia.clock: lightweight center clock bar widget. Its default format is
  `MMM d, dddd HH:mm`; set `format` inline on its layout entry when needed.
- aurelia.calendar: calendar panel opened by clicking the clock.
- aurelia.launcher: keyboard-first application launcher opened by clicking the
  Aurelia logo. It discovers XDG desktop entries through the existing
  workstation registry and launches validated desktop IDs with `gtk-launch`.
- aurelia.workspaces: Hyprland workspace switcher placed immediately after
  the Aurelia logo.
- aurelia.tray: StatusNotifier system-tray widget for applications such as
  ChatGPT; it is independent from the Noctalia tray.
- aurelia.power: final right-side power widget with lock, logout, suspend,
  reboot, and shutdown actions. Reboot and shutdown require confirmation.
- aurelia.weather: lightweight weather bar widget following Omarchy's default
  automatic IP-based location flow through `wttr.in`. Set `location` to a
  city, or set `latitude`/`longitude` for exact coordinates; `units` and
  `label` are optional inline settings. GPS is not required.
- aurelia.bar: resident top bar host with left/center/right manifest-backed
  widget slots, an exact center anchor, and a theme-aware camera action that
  opens the Screenshot panel below the bar. It is independent from Noctalia;
  running Aurelia does not switch the active desktop shell.
