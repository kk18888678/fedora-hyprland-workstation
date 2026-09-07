# End-to-end behavior coverage

The earlier architecture documents described the pieces of the shell, but a
1:1 build also needs the transitions between those pieces. This document is
the index for those transitions. Each row below has a dedicated flow document
or an explicit existing source document; a feature is not considered covered
merely because its QML file was listed.

The source anchor is the full quattro tree at commit
e989b5b3ee1ee1babb2614655649341f80b7b323. The primary runtime path is:

~~~
external trigger / pointer / key
    -> host IPC or live surface
    -> plugin resolution and injection
    -> open-state transition
    -> focus and input ownership
    -> asynchronous work and state update
    -> user action / error / cancellation
    -> close-state transition
    -> focus release, process cleanup, persistence, and host state repair
~~~

## Evidence rule

The flow documents distinguish three different statements:

| Statement | Evidence required |
|---|---|
| Source-defined behavior | The exact source path and transition were inspected at the pinned commit. |
| Blueprint requirement | The source-defined transition is written as an implementation invariant. |
| Runtime-proven behavior | A live Quickshell/Wayland test exercised the transition and recorded the result. |

This repository task performed source inspection and documentation QA. It did
not run a live Quickshell session or alter the workstation. Therefore the flow
documents are implementation-grade source specifications, while their runtime
acceptance sections remain tests that a completed implementation must execute.
No document in this folder may turn static source inspection into a promise of
failure-free behavior on an untested target machine.

## Coverage matrix

| Flow family | User-visible entry | Host/state owner | Required terminal behavior | Detailed document |
|---|---|---|---|---|
| Session and shell startup | graphical session autostart | one shell process, watched files, plugin registry | all enabled surfaces are either loaded or explicitly reported failed | 01-runtime-architecture.md; flows/01-session-and-host.md |
| Bar construction | session startup, bar option change | bar loader and per-screen Bar instances | one active bar option, deterministic three-section layout | 06-bar-engine.md; flows/01-session-and-host.md |
| Bar pointer routing | left/right/middle click, wheel, drag | ModuleSlot, registered WidgetButton target, widget | one resolved action; drag must suppress click | flows/01-session-and-host.md |
| Simple bar widgets and indicators | pointer, wheel, compositor/service event | widget, indicator group, tray, first-party service | visibility, action dispatch, and optional dependency branches remain source-defined | flows/12-bar-widgets-and-indicators.md |
| Shared bar-owned panel | bar click, host summon, panel hotkey | bar widget root, panel, KeyboardPanel | focus prime, one popout owner, Escape/outside close, fade and release | flows/02-weather-panel.md; flows/03-bar-panel-contract.md |
| Weather detail | Weather bar click or weather summon | weather widget/panel, location file, forecast processes | card appears before/after data; edit Escape differs from panel Escape | flows/02-weather-panel.md |
| Clock calendar | clock click/hotkey | clock widget/panel, inline format/week-start state | calendar opens, navigates, edits life dates, closes without stale edit state | flows/04-information-panels.md |
| Device panels | audio, Bluetooth, monitor, power bar actions | panel plus PipeWire/Bluetooth/UPower/helper commands | live model refresh, action feedback, cursor state, close cleanup | flows/05-device-and-connectivity-panels.md |
| Connectivity panels | network, Wi-Fi QR, speed tests | network panel/services and standalone panel loaders | scans/tests are cancellable; credentials and child processes do not leak | flows/05-device-and-connectivity-panels.md; flows/06-auxiliary-panels.md |
| Cloud/tunnel panels | Dropbox/Tailscale bar widget | panel plus service singleton and external CLI | login/auth/action state is visible; stale action state cannot overwrite a newer request | flows/06-auxiliary-panels.md |
| Agent dashboard | agent bar click/hotkey | agent panel plus usage/status processes and files | scan/update/retry state settles; panel remains usable when providers are absent | 13-ai-first-platform.md; flows/04-information-panels.md |
| Command menu | menu button, keybinding, shell summon payload | menu plugin, JSONC providers, app library, result files | route or dmenu mode opens; search/navigation/action/cancel updates host state correctly | flows/07-menu-and-overlays.md |
| Clipboard history | keybinding or host summon | capture watchers, history file, overlay | filter/delete/confirm/paste/copy/open each closes or retains state exactly | flows/07-menu-and-overlays.md; 07c-overlays-data-contracts-and-assets.md |
| Emoji picker | keybinding or host summon | emoji asset, overlay filter/cursor | filter clears before dismissal; selection invokes insertion command | flows/07-menu-and-overlays.md |
| Image picker | image-selector IPC request | host special IPC, selector loader, selection/done files | request serial prevents stale results; apply/cancel completes the done file | flows/07-menu-and-overlays.md; 15-theme-wallpaper-and-cross-app-sync.md |
| Reminder form | menu route or indicator | overlay state machine and reminder command | minutes -> message -> command, invalid input remains open, Escape clears filter before close | flows/07-menu-and-overlays.md |
| Developer gallery | developer command/payload | floating window and common controls | window close reports host hide; embedded controls block parent cursor while focused | flows/07-menu-and-overlays.md |
| OSD | helper command / IPC | transient OSD state and timer | latest value replaces prior value; empty input region never blocks desktop | 07a-system-services-and-hosted-surfaces.md; flows/08-services-and-modal-surfaces.md |
| Notifications | notification daemon events | notification service, card model, DND/persistence | event is normalized, rendered, acted on/dismissed, and timed out without secret leakage | 07a-system-services-and-hosted-surfaces.md; flows/08-services-and-modal-surfaces.md |
| Lock/unlock | idle service, explicit lock, session lock | PAM, lock service, lock view, DPMS/background | lock request waits for usable outputs; authentication success/failure and wake/blank paths converge | 07a-system-services-and-hosted-surfaces.md; flows/08-services-and-modal-surfaces.md |
| Policy authentication | polkit request | private authentication service object plus PAM-like dialog | request queue, password submit/cancel, timeout/error, and response ownership remain isolated | 07a-system-services-and-hosted-surfaces.md; flows/08-services-and-modal-surfaces.md |
| Background/theme switch | theme command or wallpaper selection | background service, staged files, image/video renderer | state file and renderer converge; transition/caching failure leaves last-good background | 15-theme-wallpaper-and-cross-app-sync.md; flows/09-theme-capture-and-platform.md |
| Capture and dictation | keybinding/menu/indicator | helper scripts, indicator state, Voxtype | picker/recorder/OCR/QR/color/dictation processes are explicitly stopped or completed | 14-capture-recording-and-dictation.md; flows/09-theme-capture-and-platform.md |
| Media/battery/idle/night-light | bar widget, service event, timer | first-party service host and command helpers | service singleton state drives every monitor's widget and transient OSD | 07a-system-services-and-hosted-surfaces.md; flows/08-services-and-modal-surfaces.md |
| Plugin install and reload | CLI command, file watcher, shell IPC | plugin command scripts, registry, loaders | validate -> install/enable -> rescan -> load/inject -> disable/remove; no stale instance survives | 12-full-plugin-lifecycle.md; flows/10-plugin-lifecycle.md |
| Platform update/recovery | installer/update command | package ownership, migration, state files, session | prepare/validate/activate ordering, classified failures, safe rerun, and recovery | 11-full-platform-lifecycle.md; flows/09-theme-capture-and-platform.md |

## Manifest-to-flow reconciliation

The 37 manifest ids at the pinned source anchor are explicitly assigned below.
This prevents a grouped feature heading from hiding an unassigned plugin.

| Manifest id | Flow owner |
|---|---|
| omarchy.agents | flows/04-information-panels.md |
| omarchy.background | flows/08-services-and-modal-surfaces.md and flows/09-theme-capture-and-platform.md |
| omarchy.bar | flows/01-session-and-host.md and flows/10-plugin-lifecycle.md |
| omarchy.active-window | flows/12-bar-widgets-and-indicators.md |
| omarchy.indicators | flows/12-bar-widgets-and-indicators.md |
| omarchy.keyboard-layout | flows/12-bar-widgets-and-indicators.md |
| omarchy.microphone | flows/12-bar-widgets-and-indicators.md |
| omarchy.spacer | flows/12-bar-widgets-and-indicators.md |
| omarchy.system-update | flows/12-bar-widgets-and-indicators.md |
| omarchy.tray | flows/12-bar-widgets-and-indicators.md |
| omarchy.workspaces | flows/12-bar-widgets-and-indicators.md |
| omarchy.clipboard | flows/07-menu-and-overlays.md |
| omarchy.dev-gallery | flows/07-menu-and-overlays.md |
| omarchy.emojis | flows/07-menu-and-overlays.md |
| omarchy.image-picker | flows/07-menu-and-overlays.md and flows/09-theme-capture-and-platform.md |
| omarchy.lock | flows/08-services-and-modal-surfaces.md |
| omarchy.menu | flows/07-menu-and-overlays.md and flows/12-bar-widgets-and-indicators.md |
| omarchy.notifications | flows/08-services-and-modal-surfaces.md |
| omarchy.osd | flows/08-services-and-modal-surfaces.md |
| omarchy.audio | flows/05-device-and-connectivity-panels.md |
| omarchy.bluetooth | flows/05-device-and-connectivity-panels.md |
| omarchy.clock | flows/04-information-panels.md |
| omarchy.disk-speedtest | flows/06-auxiliary-panels.md |
| omarchy.dropbox | flows/06-auxiliary-panels.md |
| omarchy.monitor | flows/05-device-and-connectivity-panels.md |
| omarchy.network | flows/05-device-and-connectivity-panels.md |
| omarchy.power | flows/05-device-and-connectivity-panels.md |
| omarchy.speedtest | flows/06-auxiliary-panels.md |
| omarchy.tailscale | flows/06-auxiliary-panels.md |
| omarchy.weather | flows/02-weather-panel.md |
| omarchy.wifiqr | flows/06-auxiliary-panels.md |
| omarchy.polkit | flows/08-services-and-modal-surfaces.md |
| omarchy.reminders | flows/07-menu-and-overlays.md |
| omarchy.battery | flows/08-services-and-modal-surfaces.md |
| omarchy.idle | flows/08-services-and-modal-surfaces.md |
| omarchy.media | flows/08-services-and-modal-surfaces.md and flows/12-bar-widgets-and-indicators.md |
| omarchy.nightlight | flows/08-services-and-modal-surfaces.md |

## Required scenario coverage

### Every open path

For every plugin that exposes a surface, document and implement:

~~~
trigger
-> id/alias resolution
-> enabled check
-> loader or bar-slot resolution
-> injection
-> open-state write
-> focus acquisition (or deliberate no-focus OSD)
-> initial data/process action
-> visible/loading/error state
~~~

The trigger may be a bar pointer event, keyboard binding, host IPC, menu row,
service event, or a file-driven request. These are not interchangeable: the
Weather bar click, for example, enters the panel's openFromHotkey path, while
its direct panel open path has a different reveal flag assignment.

### Every close path

For every surface, document separately:

~~~
Escape
outside click / scrim
card-internal action
bar-widget handoff
host hide
window-manager close (where applicable)
process completion / timeout
~~~

Each close path must state whether it first clears a search field, cancels an
editor, writes a result file, stops a child process, tells the host to hide,
releases layer-shell focus, and removes the instance. “The popup closes” is not
an adequate contract.

### Every asynchronous boundary

For each Process, FileView, watcher, timer, helper command, and external service
request, record:

~~~
start condition -> output parser -> success state -> non-zero/empty state
-> cancellation state -> stale-result guard -> retry/next action
~~~

The source frequently uses request serials, expected-stop flags, pending-run
flags, or last-good state. A port that omits those guards can look correct in
the happy path and still be behaviorally different.

## Folder organization

The existing numbered documents remain the authoritative component, geometry,
dependency, and source-map references. The flow documents are the
cross-component lifecycle traces. They intentionally do not repeat every
measurement table; each trace links to the document that owns the exact
dimensions and data contract.

~~~
shell-documentation/
    01..19-*.md                 architecture, components, data, dependencies
    20-end-to-end-flow-coverage.md
    flows/
        01-session-and-host.md
        02-weather-panel.md
        03-bar-panel-contract.md
        04-information-panels.md
        05-device-and-connectivity-panels.md
        06-auxiliary-panels.md
        07-menu-and-overlays.md
        08-services-and-modal-surfaces.md
        09-theme-capture-and-platform.md
        10-plugin-lifecycle.md
        11-ai-first-lifecycle.md
        12-bar-widgets-and-indicators.md
~~~

## Current honesty statement

Before this flow audit, the folder was not strong enough to claim that a user
journey such as “click Weather, see its card, press Escape, card disappears”
was documented as one end-to-end contract. The component facts existed in
separate files, but the transition and its editing exception were not indexed
as a trace.

The acceptance bar is now explicit: the folder may be called source-complete
only after every matrix row links to a flow or source document and every flow
ends in a terminal state with cleanup and error branches. It still cannot be
called runtime-proven until the implementation exercises the acceptance checks
in the flow documents.
