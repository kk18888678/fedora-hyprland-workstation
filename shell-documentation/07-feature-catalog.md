# Feature catalog and dependency matrix

The shell is a host plus a collection of independent capability plugins. The
feature list below is the minimum source-level inventory needed to reproduce
the reference composition. Details are split so individual implementations do
not become a single “god feature” module:

- [07a-system-services-and-hosted-surfaces.md](07a-system-services-and-hosted-surfaces.md)
- [07b-bar-widgets-and-device-panels.md](07b-bar-widgets-and-device-panels.md)
- [07c-overlays-data-contracts-and-assets.md](07c-overlays-data-contracts-and-assets.md)

## First-party manifest inventory

The source-discovered first-party capabilities are:

| Capability role | Kind(s) | Entry point role |
|---|---|---|
| default bar | bar | `bar/Bar.qml` |
| background renderer | service | `background/Background.qml` |
| agent usage dashboard | bar-widget | `agents/Panel.qml` |
| clipboard history | overlay | `clipboard/Clipboard.qml` |
| developer gallery | panel | `dev-gallery/GalleryPanel.qml` |
| emoji picker | overlay | `emojis/Emojis.qml` |
| image carousel | overlay | `image-picker/ImagePicker.qml` |
| session lock | service | `lock/Service.qml` |
| command menu | menu + bar-widget | `menu/Menu.qml`, `menu/BarWidget.qml` |
| notification daemon | service | `notifications/Service.qml` |
| OSD | panel | `osd/Osd.qml` |
| audio panel | bar-widget | `panels/audio/Panel.qml` |
| Bluetooth panel | bar-widget | `panels/bluetooth/Panel.qml` |
| clock/calendar | bar-widget | `panels/clock/BarWidget.qml` |
| disk speed test | panel | `panels/disk-speedtest/Panel.qml` |
| cloud-sync panel | bar-widget | `panels/dropbox/Panel.qml` |
| display panel | bar-widget | `panels/monitor/Panel.qml` |
| network panel | bar-widget | `panels/network/Panel.qml` |
| power panel | bar-widget | `panels/power/Panel.qml` |
| internet speed test | panel | `panels/speedtest/Panel.qml` |
| tunnel/VPN panel | bar-widget | `panels/tailscale/Panel.qml` |
| weather panel | bar-widget | `panels/weather/BarWidget.qml` |
| Wi-Fi QR panel | panel | `panels/wifiqr/Panel.qml` |
| authentication agent | service | `polkit/PolkitAgent.qml` |
| reminder flow | overlay | `reminders/ReminderFlow.qml` |
| battery service | service | `services/battery/Service.qml` |
| idle service | service | `services/idle/Service.qml` |
| media service/widget | service + bar-widget | `services/media/Service.qml`, `BarWidget.qml` |
| night-light service | service | `services/nightlight/Service.qml` |

The bar also scans these sibling first-party widget manifests: active-window,
indicators, keyboard-layout, microphone, spacer, system-update, tray, and
workspaces. The indicator directory contains six subcomponents used by the
indicator widget: dictation, do-not-disturb, night-light, reminders, screen
recording, and stay-awake.

## External dependency matrix

| Capability | Native/runtime dependency | External commands/data |
|---|---|---|
| all QML | Qt 6 + Quickshell + Wayland layer-shell | `bash`, coreutils, user systemd |
| compositor geometry | Quickshell Hyprland + Hyprland | `hyprctl` |
| bar/desktop launch | UWSM, desktop entry service, icon theme | `gtk-launch`, `uwsm-app`, XDG desktop files |
| fonts/icons | fontconfig, JetBrains Mono Nerd Font, Liberation Sans, emoji fallback | `fc-match`, `xkbcli` |
| backgrounds | layer-shell, Qt effects/shapes, Qt multimedia/FFmpeg for video | `readlink`, theme/background commands |
| network | NetworkManager backend, Wi-Fi station, connectivity checks | `nmcli` through helper scripts, `curl` for weather/geocoding |
| audio | PipeWire, WirePlumber, MPRIS | helper commands for physical sink/default source and OSD IPC |
| Bluetooth | BlueZ/Quickshell Bluetooth, PipeWire | device/power helper commands |
| power | UPower, power-profiles-daemon | battery/profile/system-stat helper commands |
| lock | native session-lock protocol, PAM, optional fprintd | PAM service files, `fprintd-list`, wake/brightness helpers |
| notifications | freedesktop notification server, Wayland panels | `awk`, `mkdir`, focus helper, `wl-copy` for actions that need it |
| menu/apps | QML desktop entries, XDG icon dirs | `jq`, `pacman`, `find`, `command -v`, provider CLIs |
| clipboard | Wayland clipboard | `wl-paste`, `wl-copy`, `setpriv`, `perl`, `jq`, `sha256sum` |
| image carousel | Qt Image/Effects/Shapes | `find`, `stat`, `md5sum`, `ffmpegthumbnailer`, `flock`, `nproc`, `timeout` |
| QR | native rasterized matrix | QR/network/password helper; no image renderer |
| speed tests | layer-shell + shapes | network/disk test helper commands |
| tunnel/VPN | external tunnel CLI | `tailscale`, optional `pkexec`, `wl-copy`, file picker/send helper |
| cloud sync | external sync CLI + Python 3 | `dropbox-cli`, Python `os`, `pathlib`, `subprocess`, `heapq` |
| agent dashboard | file-backed usage records | Python collectors, `curl`, OAuth/API clients, app session files |
| authentication | native polkit backend | PAM config, optional lid-state helper |

The shell code does not install these dependencies itself. The host package
layer must provide them, and each plugin should self-hide or render a clear
unavailable state when its optional dependency is missing.

The complete command/framework boundary is collected in
[10-external-tool-contract.md](10-external-tool-contract.md), including the
native Quickshell types and the external process expectations.

## Shared feature rules

Across the catalog, these rules recur and must be retained:

- live native objects are tracked with Quickshell trackers but list delegates
  receive primitive snapshots when backend-object churn can invalidate a
  QObject wrapper;
- external process stdout is parsed into a small primitive model before UI
  bindings consume it;
- asynchronous work has a timeout, a stale-result guard, or a bounded retry;
- action state is optimistic only when it is safe and is reconciled against
  the native/backend state;
- a panel keeps its layout mounted through delayed data arrivals when a late
  sample would otherwise move the cursor or buttons;
- a process failure leaves the last known good data visible where possible;
- secrets enter process stdin or in-memory fields, not command-line argv;
- all feature panels use the shared `PanelKeyCatcher` and cursor ownership
  model;
- normal user actions mutate only user-owned state or call existing helpers;
- feature code never turns optional UI absence into a host-wide failure.

## State ownership by feature

| State | Location/owner |
|---|---|
| bar layout and widget settings | user shell JSON; shell host mutator |
| plugin source | user plugin directory; git or manual file ownership |
| theme colors/surfaces | active theme files + watched user shell TOML override |
| current background | state symlink resolved by background/lock services |
| idle and lock timings | top-level shell JSON |
| notifications/DND | XDG state notification files + settings JSON |
| clipboard history | XDG state history JSON and image directory |
| weather location | feature-owned XDG state JSON; display preferences inline in widget settings |
| agent usage | XDG state usage records written by collectors |
| tray pinned/hidden ids | tray widget's inline settings |
| tunnel recent regions | tunnel widget's inline settings |
| stay-awake | XDG state flag file |
| font family | fontconfig user file; shell resolves `monospace` |

## Where third-party code can extend

Third-party plugins can add:

- a bar widget, with a manifest-backed `barWidget` entry point;
- a complete bar option, with a manifest-backed `bar` entry point;
- an on-demand panel, overlay, or menu;
- a headless service, optionally paired with a bar widget in one manifest;
- local QML/JavaScript/assets/scripts within the plugin directory.

They cannot, through the manifest alone, add a new host provider to the command
menu, add a new built-in indicator file, register a new native Quickshell
singleton, or change the host's security policy. Those are intentionally
source-level extension points. A plugin may still expose its own IPC target
from its QML entry point and may call the host target if it knows the contract.
