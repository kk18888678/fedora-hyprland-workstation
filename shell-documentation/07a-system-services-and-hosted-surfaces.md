# System services and hosted surfaces

This file covers the host-level services and surfaces that are not ordinary
bar device panels.

## Background renderer

### Ownership and state

The background capability is a first-party `service` plugin. It reads the
current background from a state symlink:

```text
STATE_HOME/current/background -> selected image or video
```

`readlink -f` resolves the link. The service has one logical current path and
one per-screen layer-shell surface. A background change increments a version
counter; when the path is unchanged but its file was replaced, the version
cache-busts still images.

### Per-screen rendering

Every screen receives a full-screen `PanelWindow`:

```text
layer = Background
keyboardFocus = None
exclusionMode = Ignore
updatesEnabled = true
```

Playback is disabled if any of these is true:

- native session lock is active;
- an idle screensaver window is visible;
- the power-saver profile is active on battery;
- the active workspace on that screen contains a fullscreen window.

Only the first detected screen enables background audio. This prevents one
video player per monitor from layering the same soundtrack.

### Transition behavior

Still-to-still changes use two `Image` layers with `PreserveAspectCrop`,
asynchronous loading, no cache, smoothing, and mipmaps. The incoming image is
revealed through a `QtQuick.Shapes` mask with:

```text
slant = -0.18
reach = width/2 + abs(slant) × height/2 + 4
duration = 420 ms, InOutCubic
```

The mask is a diagonal band expanding from the center. Video changes are
instant so two full decoders never overlap. A theme transition can carry
base64 palette/surface payloads; the payload is applied at reveal start or
after a `300 ms` fallback timer if the incoming image never reaches the ready
state.

`BackgroundMedia` selects an image or video Loader by file extension. Images
are cache-busted with `?v=<version>`; videos keep a plain local URL because
FFmpeg would treat a query as part of the filename. `BackgroundVideo` uses a
bare `MediaPlayer` + `VideoOutput`, loops forever, creates an `AudioOutput`
only when the output is the designated first screen and the source has audio,
and primes paused video for a first frame before pausing.

Double-left-click on the background opens the image picker; double-right-click
opens the theme selector. These calls are detached external actions.

## Session-lock service

The lock capability is a `service` plugin with `keepLoaded: true`. It uses the
native Wayland session-lock protocol, not an ordinary overlay, and owns two PAM
contexts:

```text
password PAM service       <namespace>-lock-password
fingerprint PAM service    <namespace>-lock-fingerprint
```

Fingerprint authentication is attempted only when the PAM file exists,
`fprintd-list` exists, and the user has an enrolled fingerprint. The lock
service probes this state after startup and before locking.

### Lock state machine

```text
idle
  -> lock requested
  -> 500 ms screen-stabilization window
  -> retry every 100 ms until real screen exists
  -> native sessionLock.locked = true
  -> secure state
  -> fingerprint PAM loop or password field
  -> success -> unlock + wake
  -> failure -> clear input, increment failure count, wake/keep lock
```

It refuses to lock when the password PAM configuration is not known good. It
also checks for a stranded compositor lock after startup and can recover it
only when PAM is configured. Lock status is exposed as JSON with requested,
session-locked, secure, screen count, PAM/fingerprint state, and last event.

### Exact lock field geometry

`LockView` preserves these literal dimensions:

```text
password field       381 × 67 px
outline thickness    3 px
field side margins   18 px plus border and fingerprint reserve
fingerprint reserve  icon implicit width + 12 px on each side
password font        round(heading × 1.125)
password dot font    round(heading × 1.33)
dot letter spacing   round(heading × 0.19)
fingerprint glyph    round(fieldFontSize × 1.1)
```

The wallpaper is loaded behind the field. Still backgrounds use
`MultiEffect` blur `1.0`, `blurMax 128`, `blurMultiplier 1.25`, and contrast
`-0.08`. Video backgrounds bypass the effect and receive a fixed `#22000000`
dark overlay. The field uses the lock surface background, active/error border
roles, centered placeholder, zero password-mask delay, and a 2 px cursor.

### Display blanking and recovery

After `5000 ms` of a locked idle state without a password check, the service
runs the keyboard/display brightness-off helpers. It wakes on pointer/input
activity and on native screen changes. For video lock wallpapers it polls
`hyprctl monitors -j` every `3000 ms` to reconcile per-monitor DPMS state.

The blank timer checks wall-clock drift after suspend; a timer that fired late
is re-armed instead of blanking a freshly woken unlock screen. Stranded-lock
recovery retries every `500 ms` for at most 20 attempts while screens settle.

## Notification service

The notification capability is a kept service. It enables the freedesktop
notification server with actions, body markup, hyperlinks, images, and
persistence. Notifications are snapshots, not live QObject references, in the
UI model; live notification objects are held separately by original id so
server destruction cannot leave dangling model pointers.

### Persistent layout

```text
STATE/notifications.json              # version + DND boolean
STATE/notifications/<timestamp-id>.json
                                      # one file per live toast
STATE/notifications/history/*.json    # archived newest history
STATE/notifications/images/*          # copied file-backed images
```

A live file exists exactly while its popup is on screen. Dismissal, expiry, or
action invocation moves it to history and trims history to the newest 10 files.
The file queue serializes writes, copies, moves, reads, deletes, and clears so
a later delete cannot race ahead of an earlier write.

File-backed notification images are copied before the JSON reference is
written. The source copy is bounded to 5,242,880 bytes; a temporary read may
read at most 5,242,881 bytes to detect overflow. Non-file `image://` values
are dropped from persistence. Orphan image cleanup runs through the same queue.

### Durations and placement

```text
low urgency      minimum 5,000 ms
normal urgency   minimum 8,000 ms
critical         0 ms (persistent)
all noncritical  maximum 30,000 ms
history limit    10
```

The popup surface is full-screen per monitor, `Overlay`, `keyboardFocus None`,
`Ignore` exclusion, and masked to only the toast column. Cards are:

```text
implicit width          380 px
icon slot               40 × 40 px
single-line top/bottom  7 px each
multi-line top/bottom   10 px each
left/right card padding 12 px each
icon/text gap            12 px (8 px compact glyph)
summary/body gap         2 px
close target             18 × 18 px, inset 3 px from border
column gap               8 px
```

Toasts sit at the top-right. The top/right margin is the live bar clearance
(`bar size + gapsOut`) when the bar occupies those edges; otherwise it is the
outer gap. The popup column remains on a fixed full-screen surface, so adding
or removing cards never briefly stretches a stale compositor buffer.

### DND, markup, and actions

Do-not-disturb silences ordinary notifications into history. Only intentional
action confirmations and critical CLI notifications from the designated
notification sender bypass DND. Transient notifications and designated
ephemeral senders are not recorded when silenced.

Summaries are always plain text. Bodies may use styled markup, but image tags
are stripped in a conservative single pass before Qt parses the body, including
after newline-to-`<br/>` rewriting. This prevents unauthenticated remote image
loads and avoids manufacturing a new tag by substring deletion.

Notification action argv is persisted as JSON, structurally validated, and run
with an argv-preserving `exec "$@"` shell wrapper. A live third-party default
action may be invoked while its sender exists; restored rows fall back to
focusing the sender application. These semantics preserve clickable toasts
across shell restarts without treating arbitrary notification text as shell
source.

## Command menu

The menu is a kept `menu` plugin plus a bar widget launcher. Its definition is
outside host code:

```text
<distribution-root>/default/<namespace>/<menu>.jsonc
<user-config>/<namespace>/extensions/<menu>.jsonc
```

Both files are watched. JSONC comments and trailing commas are stripped by a
small parser. Dotted ids define parent/child hierarchy; `action` makes a leaf,
`target` makes a link, otherwise the item is a submenu. Optional fields are
`icon`, `iconFont`, `label`, `title`, `description`, `aliases`, `provider`,
`when`, `checked`, and `disabled`.

User entries merge over defaults per key, preserving the default item order
and appending new user ids. Exact ids outrank aliases. Application rows are
never routes, so desktop-entry keywords cannot shadow a menu command.

### Provider model

The menu has a fixed in-code provider map. The audited providers are:

- desktop applications from the shared `AppLibrary`;
- font choices;
- power-profile choices.

Each shell provider emits tab-delimited `label`, `value`, `current` rows. A
provider submenu loads lazily on entry; volatile providers refresh when entered
again. Provider ids are slugified, collision-suffixed, and swapped as one
batch. New provider names cannot be declared by JSONC alone; adding one is a
source-level host extension.

### Guards and search

`when`, `checked`, and `disabled` fields are Bash expressions. The menu batches
all guard expressions into one subprocess per source rebuild and reports
`id:w:0|1`, `id:c:0|1`, or `id:d:0|1` lines. Common package/command checks are
precomputed. Guard results are replaced only after a complete successful
batch; a killed/partial run does not make unanswered `when` rows disappear.

Search is case-insensitive, all-terms, and hierarchical. It separates direct
children from deeper descendants with a divider, scores exact/prefix/name/id/
description matches, and omits disabled rows from search while retaining them
in normal submenus as dimmed checked rows. The cursor skips disabled rows and
wraps among selectable rows.

### Menu geometry

```text
content margin        18 px
header height         max(34 px, title + 2×controlPaddingY)
content spacing       6 px
base row height       max(50 px, body + 2×rowPaddingX)
detail row height     max(58 px, body + caption + 2×rowPaddingX)
row peek              55% of base row height
row spacing           3 px
divider height        17 px
default card width    300 px
special card width    520 px for long capture/font routes
card width cap        panel width - 2×gapsOut
card height cap       panel height - 2×gapsOut and 70% row ceiling
dmenu default width   300 px
```

The full-screen menu is an `Overlay` with exclusive keyboard focus and a
themed scrim. The card initially centers. On the first search/submenu change,
its top edge and starting row ceiling freeze so later growth occurs downward
instead of jumping under the pointer. Overflow intentionally ends mid-row;
the clipped row is the fold affordance. Scroll scrims are at most 28 px high.

## Desktop application library

The shared application library reads `DesktopEntries.applications` and filters
hidden/no-display entries. It also scans XDG desktop directories for
`Hidden=true`, `NoDisplay=true`, `OnlyShowIn`, and `NotShowIn` semantics.

Search uses application name, generic name, comment, keywords, id, acronym,
and fuzzy score. Ties sort alphabetically. Icons use a context-limited index of
`apps`/`devices` SVG and PNG files, preferring SVG, then themed lookup, then a
generic executable icon. The index refresh is debounced `750 ms` after desktop
entry changes.

Launching uses `uwsm-app -- gtk-launch <desktop-id>.desktop`. A launch feedback
OSD waits `2 s` before appearing and closes when the toplevel set/active window
changes, with a hard `15 s` timeout. Removing an application delegates to an
existing launcher-entry helper.

## Media service and widget

The media capability is a kept service plus a bar widget. The service consumes
MPRIS players and PipeWire playback streams, tracks live player objects, and
chooses an active player using this precedence:

```text
preferred playing player
oldest playing player with a playback stream
oldest playing player
stream-backed player
preferred/track/controllable/identity fallback
```

Proxy players are deprioritized behind real players. Source switching can
transfer playback by starting the next player before pausing the current one.
Next/previous OSD feedback waits up to ten 120 ms checks for the track
signature to change, then shows the result anyway.

The bar widget hides when no title/artist exists. Its compact row has a play
glyph, a scrolling title/artist field capped at `180 px`, and a `6 px` gap.
The popup uses a 64×64 cover-art square, `2 px` image inset, 10 px row gaps,
and previous/play-next controls separated by 6 px. Vertical bars suppress the
scrolling text. Clicks map to play/pause, next, previous, and popup actions;
wheel movement maps to previous/next.

## Battery, idle, and night-light services

### Battery service

The battery service reads UPower, stores a one-bit low-battery notification
state in `PersistentProperties`, and warns at `10%` while discharging. It
checks every `30 s`, reacts immediately to `onBattery` changes, and polls the
active power profile every `2 s`. The `powerSaverOnBattery` property is true
only for on-battery + `power-saver`.

### Idle service

The idle service reads top-level shell timings, default screensaver `150 s` and
lock `300 s`. It creates one `IdleMonitor` with `respectInhibitors: true` and
uses the first idle timeout as the monitor timeout; the screen-saver and lock
timers then use the difference between each configured deadline and the first
timeout.

```text
idle monitor -> idle cycle
screensaver timer -> launch screensaver
lock timer -> request system lock
activity/screensaver close -> cancel cycle + wake
```

The screensaver launch has a `3 s` grace period. A user-controlled stay-awake
flag lives at `STATE/indicators/stay-awake`; state writes are serialized and
re-read through a watched directory. Idle event logging records ISO timestamps,
timer/process state, screensaver-window count, and last event.

### Night-light service

Night-light reads the compositor temperature. Temperatures below `6000 K` count
as enabled; enabling applies `4000 K`, disabling applies `6500 K`. If an apply
is already running, the latest requested temperature is queued and applied
afterward. The service can start the compositor night-light process when absent
and exposes status/refresh/enable/disable/toggle IPC.

## Authentication agent

The authentication capability runs the native polkit agent in a kept service.
It monitors the polkit PAM file for `pam_fprintd.so`, probes a clamshell/lid
state, and shows fingerprint mode only when the sensor is available, the lid is
open, no password response is required, and the request is not submitted/error
flashing.

Geometry:

```text
field height = max(Style.space(42), controlHeight) = 42 px default
card height  = min(field height + 2×content margin,
                    panel height - 2×gapsOut) when panel height is known
password card width = min(312 px, max(260 px, panel width - 2×gapsOut))
fingerprint card width = card height (square)
lock icon column = 26 px
card row gap = 14 px
justification strip height = 28 px, bottom gap 10 px
```

Fingerprint mode centers one optical glyph sized at `70%` of field height.
Password mode uses a 2 px caret, normal/failed placeholder, an error shake of
`-8 → +8 → 0` over `35/50/55 ms`, and a `1200 ms` red error flash. The dialog
is a full-screen exclusive overlay with themed scrim and immediate refocus on
card click.

## OSD panel

The OSD service is a kept panel and passive full-screen layer. Its card is
bottom-centered with a `67 px` bottom margin, themed popup background at
`0.97` alpha, and no input mask. Content is measured rather than fixed:

```text
pad = 16 px
gap = 16 px
message gap = round(gap × 2/3) = 11 px
progress width = 142 px
non-media max message = 190 px
media max message = 325 px
card height = border insets + 2×pad + displayLarge line
```

The icon column measures painted ink and reserves the widest volume glyph so
percentages/icons do not shift the bar. Progress fill uses accent and animates
`140 ms`; the OSD auto-hides after `1200 ms` unless a caller supplies duration
`0`, in which case it stays until close.
