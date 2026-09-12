# Aurelia Shell Plugins

aurelia.background is a resident service plugin, not a bar widget. It owns one
WlrLayer.Background surface per screen with updatesEnabled kept true so
switching to an empty or dynamic Hyprland workspace cannot reveal a black
desktop. It reads the active wallpaper from Aurelia XDG state and uses a solid
themed fallback until an image or video is ready.

aurelia.theme is an on-demand selector panel. Theme changes are staged through
aurelia-theme and aurelia-theme-bg; palette data is applied to Aurelia's
existing Theme.qml singleton and wallpapers are applied through the resident
background service. Theme directories are data-only: Aurelia never executes
Lua, shell hooks, or arbitrary application configuration supplied by a theme.

This directory contains first-party Aurelia Shell plugins. First-party and
user plugins share the same manifest contract; only their source roots differ.

For the complete authoring, testing, lifecycle, reload, and maintenance guide,
see [aurelia-plugin-authoring.md](../docs/aurelia-plugin-authoring.md).

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
`appLibrary`, `manifest`, and `pluginRegistry` after URL loading. These
properties must have safe defaults because URL-loaded QML is constructed before
`Loader.onLoaded`.
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

The `aurelia.notifications` plugin demonstrates a multi-kind plugin. Its
resident `service` entry point owns the Freedesktop notification server,
bounded toast snapshots, XDG-state history, and Do Not Disturb. Its separate
`bar-widget` entry point is only the notification-center affordance; it routes
actions to the resident service through shell IPC. The registry deliberately
selects `service` as the host entry point when a manifest declares both kinds.

## Popup design language

The Screenshot popup is the compact reference surface for Aurelia popups.
Reuse `ui/AureliaActionButton.qml` and the shared `Theme` tokens for action
hierarchy, restrained radii, borders, spacing, and typography. Keep the
primary action set small and expose additional behavior through compact
customization controls or a dedicated settings surface instead of multiplying
near-duplicate action cards.

Bar affordances use `ui/AureliaToolTip.qml`, an anchored `PopupWindow` with
explicit top/bottom placement and screen clamping. This keeps tooltip geometry
outside the short bar layer and prevents the clipped half-tooltip behavior of
an in-bar controls overlay.

## Current desktop slices

- aurelia.background: resident per-screen image/video wallpaper service with
  safe solid-color fallback and live XDG-state reload.
- aurelia.theme: on-demand theme/background selector backed by the data-only
  aurelia-theme and aurelia-theme-bg commands.
- aurelia.screenshot: bar-only camera widget with an internal capture surface,
  backed by Fedora-owned grim, slurp, and wl-copy tools. It supports
  full-screen and region capture with configurable delay, pointer, file, and
  clipboard behavior. Its plugin-owned `SUPER + SHIFT + R` binding opens the
  same quick region flow used by the popup, while `SUPER + SHIFT + S` captures
  the full screen.
- aurelia.notifications: resident Freedesktop notification service with
  theme-aware popups, Inbox/History center views, DND persistence under
  `${XDG_STATE_HOME:-$HOME/.local/state}/aurelia/`, clear-history and
  dismiss-all controls. Successful Aurelia screenshot captures publish a local
  preview through the service API; no second notification backend is used. If
  another session daemon owns the Freedesktop bus name, Aurelia keeps the
  center and in-process previews available without repeatedly attempting a
  conflicting registration. Inbox rows are retained until the user acts on
  that individual notification; passive popup expiry never archives the row.
  ChatGPT completion notifications also keep their passive popup until Open or
  Dismiss so they cannot be missed while the user is away.
- aurelia.clock: lightweight center clock bar widget. Its default format is
  `MMM d, dddd HH:mm`; set `format` inline on its layout entry when needed.
- aurelia.calendar: calendar panel opened by clicking the clock.
- aurelia.launcher: Raycast-style Aurelia Command Center opened by clicking the
  Aurelia logo. It searches native XDG desktop entries, configured actions,
  bounded home files, and safe arithmetic; additional provider modules are
  declared separately and can be enabled as they become implemented. Internal
  terminal helpers such as `footclient` and `foot-server` are kept out of the
  user-facing app list by the shipped Command Center hide policy.
- aurelia.workspaces: Hyprland workspace switcher placed immediately after
  the Aurelia logo.
- aurelia.workspace-switcher: resident Mission Control-inspired overlay opened
  with `SUPER + TAB`. It shows workspaces 1–5 plus occupied live workspaces up
  to 10, renders bounded single-frame Hyprland toplevel previews when the
  compositor export protocol is available, and falls back to app/title cards
  when it is not. Repeated `SUPER + TAB` presses cycle; Enter or a card click
  activates the selected workspace and Escape dismisses the overview.
- aurelia.tray: StatusNotifier system-tray widget for applications such as
  ChatGPT; it is independent from the Noctalia tray.
- aurelia.power: final right-side power widget with lock, logout, suspend,
  reboot, and shutdown actions. Reboot and shutdown require confirmation.
- aurelia.bluetooth: BlueZ-backed bar widget with reboot-persistent rfkill
  power state, paired/available device sections, pair/connect/disconnect/forget
  actions, battery levels, and bounded discovery cleanup. The implementation is
  adapted from the working Omarchy Bluetooth panel. Its manifest exposes only
  `bar-widget`; the keyboard surface is an internal popup owned by the bar
  widget, not a standalone panel plugin. The bar slot collapses when no BlueZ
  adapter is available.
- aurelia.weather: lightweight weather bar widget following Omarchy's default
  automatic IP-based location flow through `wttr.in`. Set `location` to a
  city, or set `latitude`/`longitude` for exact coordinates; `units` and
  `label` are optional inline settings. GPS is not required.
- aurelia.monitor: Display bar widget with bounded brightness, Aurelia text
  size, focused-monitor resolution and scale controls, and multi-display
  enable/disable actions. It shows the current mode and compositor-advertised
  modes reported by Hyprland, applies only compositor-validated resolutions,
  uses Fedora's `brightnessctl` for laptop backlights, and keeps external DDC
  control optional. Runtime display changes do not rewrite the repository-owned
  Hyprland monitor configuration.
- aurelia.network: NetworkManager-backed connectivity bar widget with
  primitive Wi-Fi scan rows, safe credential prompts, Ethernet/Wi-Fi status,
  captive-portal detection, DNS and Wi-Fi-band controls, QR sharing, and a
  bounded speed-test handoff. The implementation is adapted from the working
  Omarchy network panel and keeps QR/speed-test surfaces as separate plugins.
- aurelia.bar: resident top bar host with left/center/right manifest-backed
  widget slots, an exact center anchor, and a theme-aware camera action that
  opens the Screenshot panel below the bar. It is independent from the
  Noctalia greeter; the VM profile selects Aurelia as the active post-login
  desktop shell while the physical-workstation profile keeps Noctalia active.
