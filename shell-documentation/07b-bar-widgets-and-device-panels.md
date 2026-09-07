# Bar widgets and device panels

These capabilities are the reference bar composition. Every panel uses the
shared `KeyboardPanel` and a single root-owned cursor state. The tables preserve
the feature-specific constants that sit above the global tokens.

## Simple widgets

### Active-window label

Reads the compositor's active toplevel title, falling back to app id. It is
hidden on vertical bars and when there is no title. The label is clipped,
ellipsized, opacity `0.85`, body font, and bounded by a `maxWidth` setting
(default `280 px`). It has `8 px` left/right content margins. Left click
activates the window; middle/right click closes it.

### Workspace switcher

The default list is workspaces `1–5`; positive live workspaces up to `10` are
added and sorted. Workspace `10` displays as `0`. Horizontal cells are `20 px`
wide with `1 px` column spacing and bar-height fixed height; a vertical bar
uses one column, `2 px` row spacing, and bar-width fixed width. Occupied and
focused workspaces have opacity `1`; empty non-focused workspaces have
opacity `0.5`. Clicking dispatches compositor focus.

### Keyboard-layout indicator

It runs `xkbcli list --load-exotic` once for layout descriptions and polls
`hyprctl -j devices` every `600 ms` after layout/config events. It excludes
virtual, power-button, sleep-button, lid-switch, and video-bus keyboards,
selects the keyboard named by the latest active-layout event or the furthest
advanced layout, and displays a three-character uppercase language label. The
widget hides until there are multiple layouts (unless the list cannot be
resolved). A 5 s query watchdog and a 10 s ambiguity poll prevent stale labels.
Click cycles the selected keyboard; wheel is not used.

### Microphone

Reads the default PipeWire source and active capture streams. It uses a
fixed-status icon slot and maps left click to mute, middle click to the audio
panel, and wheel notches to ±`0.05` source volume. “In use” means at least one
unmuted capture stream and an unmuted default source.

### Spacer

An invisible bar widget with `size` setting (default `12`). Horizontal size is
the span and height is bar size; vertical size is bar size and height is span.
It is visible only for a positive span and permits multiple instances.

### Update indicator

Runs the update probe immediately and every `21,600,000 ms` (6 hours). It is
hidden unless the probe exits zero. Refresh/clear are broadcast to every
monitor instance through its widget target. Left click launches the update
flow.

## Indicator group

The indicator group loads six first-party indicator QML files by relative name:

```text
dictation, screen recording, reminder, night light,
do-not-disturb, stay-awake
```

Default order is exactly that list. Settings may supply `items` or
`indicators`; an empty list means all defaults. The active block is closest to
the center; newly active indicators are inserted at its inner side. Inactive
items are hidden until the group/host is hovered, `alwaysShow=true`, or an
indicator item is hovered. Reveal collapse waits `120 ms` so a moving neighbor
does not steal a stationary pointer.

Each indicator extends `BarIndicator`, which uses a `21 px` status slot,
`5 px` horizontal margin, `5 px` vertical padding, and active/inactive tooltip
text. Indicator IPC refresh broadcasts to all live instances. This directory
is not manifest-driven; adding an indicator requires host/tree code, not only
a third-party plugin manifest.

## System tray

The tray consumes Quickshell's system-tray model. Passive items are omitted;
the tray also hides entries owned by the distribution's own menu/optional
service. User settings store `pinned` and `hidden` id arrays inline on the tray
entry.

### Layout and motion

```text
tray item extent       Style.bar.iconSlot = 27 px
tray item gap          0 px
tray join gap          0 px
tray icon in slot      12 × 12 px
drawer animation       600 ms, OutCubic
```

The drawer reveals inward from a chevron. Horizontal and vertical layouts use
the same geometry rotated through a Loader. The containment mask includes only
the chevron/revealed drawer and pinned icons; collapsed empty drawer space is
click-through. Pinned icons sit after the drawer block.

Hovering the drawer expands it. Right-clicking the chevron opens a management
popup; the management popup is capped at `300 px` content width. Rows are
`28 px` high, icon `16 × 16 px`, and use Pin/Hide buttons with 8 px horizontal
and 3 px vertical padding.

Tray application submenus use nested live menu openers rather than platform
menus. Each submenu level owns its opener; deepest-first destruction avoids
invalidating a child entry. Level changes settle for `250 ms` to ignore a
synthetic second click. The popup menu defaults to `232 px` content width,
`420 px` maximum height, `8 px` popup padding, `30 px` normal rows, `11 px`
separator rows, `22 px` icon/check columns, and `16 × 16 px` menu icons.

## Audio panel

The audio widget/panel owns PipeWire outputs, inputs, streams, and MPRIS
cross-labeling. It excludes stream-like capture nodes, the shell's own source,
and the speaker-tuning processing stream. A helper resolves a DSP/default sink
to the physical volume sink so changing volume does not merely change the
level into a processing chain.

### Data and actions

- output devices: select default, mute, scroll/drag volume `0–1`;
- input devices: select default, mute, scroll/drag volume `0–1`;
- playback streams: per-application volume `0–1.5`, mute, inline slider;
- PipeWire/MPRIS objects are tracked, but display lists are primitive snapshots;
- sink availability is refreshed every `5 s` while open;
- physical volume-sink resolution runs every `15 s` even when closed;
- list refresh is debounced `75 ms` after PipeWire churn;
- every wheel notch changes volume by `0.05` after delta accumulation.

The panel's virtual cursor sections are header, output, input, and streams.
The output/input slider row uses selected index `-1`; device rows are
zero-based. h/l adjusts a slider only when the cursor is on that slider. m or
Enter/Space mutes the current target. Tab cycles neighboring bar panels.

### Geometry

```text
KeyboardPanel content width      380 px fitted
KeyboardPanel max content height 560 px fitted
panel section gap                14 px
header icon                      Style.font.display
device icon column               22 px
device row side inset             6 px
device row inner gap              8 px
device/stream row bottom reserve  Style.spacing.xl = 10 px
section header/value right inset  6 px
```

The hero contains a display icon, “Audio” title, mood status line, and a bare
toggle. The output/input sections have a caption header, percentage, slider,
and device rows. Input adds a peak meter: height `max(5 px, xs)` and a live
foreground fill. Streams have a label, mute icon, percentage width `36 px`,
and an inline slider.

## Bluetooth panel

The panel consumes the native Bluetooth adapter/device model and groups rows
as connected, paired/known, and discovered. UUID/address-only names are
filtered out. Rows carry primitive projections keyed by address; actions resolve
the live device object at activation time.

```text
content width               380 px fitted
maximum device ListView     400 px
panel column gap            14 px
section gap                 10 px
row gap                     10 px
row side inset              10 px
device icon/info gap        10 px
```

Opening an enabled adapter starts discovery with a retry every `1000 ms`.
Closing uses a declarative stop debt: it ticks every `1000 ms`, issues at most
three stop writes, then abandons the debt on the fourth tick, and transfers the
debt to a surviving per-monitor sibling when needed.
The panel never stops a discovery session it did not start. Pending connect,
disconnect, and forget states expire after `20,000 ms`. A newly connected
Bluetooth audio device is matched to a PipeWire sink every `500 ms`, for at
most eight attempts, then made the preferred audio sink.

The hero status phrase rotates every `2800 ms` with `180 ms` fade-out and
`260 ms` fade-in. The header switch changes the persistent radio block through
the external power helper, not a transient BlueZ powered flag. Keyboard h/l
can move from a device row to its forget action; x/Right-click forgets known
devices, while normal activation connects/disconnects.

## Clock/calendar

The clock is a bar widget with an always-loaded nested calendar panel. The bar
uses a minute `SystemClock`, or seconds precision only when the configured
format contains an unquoted `s`. Right click walks the exact format ring; the
new format is persisted inline. Middle click opens a timezone flow.

Horizontal format ring:

```text
dddd HH:mm
dddd h:mm AP
dddd HH:mm:ss
dddd h:mm:ss AP
HH:mm
h:mm AP
ddd d MMM HH:mm
ddd d MMM h:mm AP
d MMMM 'W'ww yyyy
yyyy-MM-dd HH:mm
```

Vertical ring:

```text
HH / em-dash / mm
h / em-dash / mm / AP
dd / MMM / Www / 'yy
HH / mm
```

The panel is centered on the bar and uses:

```text
content width cap        560 px
hero icon                literal 48 px
hero date                literal 52 px bold
hero icon/date gap       22 px
calendar cell            52 × 34 px
cell spacing             2 px
week-number column       32 px
week gutter              14 px
grid top offset          18 px
grid row spacing         3 px
weekday/header height    16 px
month label width        130 px
month label row extra    10 px
```

The grid is always six rows of seven days. Today is outlined with a hairline,
not filled. Adjacent-month days are darker; weekends are moderately darker.
The “W” week column heading toggles Monday/Sunday start and has a tooltip. The
year rail is a 6 px progress bar with 12 px left/right margins. An optional
life rail appears after a valid birth year; it uses the same 6 px bar and a
default life expectancy of 90 years.

## Display/monitor panel

The display panel consumes a helper state record for brightness, internal/
external/focused monitor, scale, and enabled displays. It offers four cursor
sections: brightness, text size, scale, and monitors.

```text
scale presets       1, 1.25, 1.6, 2, 3, 4
text-size stops     9, 10, 11, 12, 14, 16, 20 px
brightness range    1–100, keyboard step 5
panel width         380 px fitted
max panel height    560 px fitted
panel section gap   14 px
display list cap    content-driven; row visibility keeps cursor in view
poll interval       5000 ms while open
brightness debounce 180 ms
```

Scale options are cleaned against the focused display's physical mode using a
120-unit divisor. Duplicate effective scales are removed. Display toggling is
blocked when it would leave zero enabled displays. Text-size changes call the
external text-scale helper; the shell's watched font base size then reflows
both type and spacing. Hover is suppressed for `300 ms` during that reflow.

Brightness changes update the local value immediately, queue behind an active
set process, and show an OSD; they do not immediately re-read hardware, which
would visibly bounce a just-written value to zero.

## Network panel

The network panel consumes Quickshell's NetworkManager backend and shells out
only for consolidated details and selected policy helpers. It prefers a
connected wired device when both wired and Wi-Fi exist. The hero represents
the Wi-Fi radio only when a Wi-Fi station is present; a wired-only system does
not show a misleading Wi-Fi switch.

### Data and timings

```text
details poll                  1500 ms while open
band poll                     4000 ms while open
Wi-Fi scan deferral           100 ms before enabling scanner
scan completion               1500 ms after scan
network list maximum height   240 px
ping history                  24 samples
ping average                  5 samples
connection action timeout     30000 ms
restricted connectivity poll  10000 ms
```

The top-level sections are optional header actions, captive-portal action,
band selection, DNS provider selection, and Wi-Fi rows. DNS always has four
choices: DHCP, Cloudflare, Google, Custom. Band choices are hidden under
Automatic unless a band is pinned; a pinned band keeps the selector available
even if only one band is currently visible. The band automatic switch is
derived from the header caption's font size (`trackHeight = round(font × 1.2)`,
cursor pad `3 px`).

Connection details keep their grid rows mounted before the first probe so late
data reads `--` without moving the panel. They show ping, packet loss,
receiving/sending rate, downloaded/uploaded totals, IP, and gateway.

Network rows are primitive snapshots sorted connected first, known second,
signal descending. Each row has a network icon, SSID, status line, protection
lock/forget action, and optional inline credentials editor. Unknown security is
treated as credentialed. Open and OWE bypass the password prompt; enterprise
WPA-EAP asks for identity plus passphrase and sends the passphrase on stdin
to the profile-creation process. The password prompt's submit button is a
22 px action target and the inline status field uses `Style.spacing.controlHeight`
(`28 px`).

Captive portal opening is explicit and uses a fixed known HTTP probe URL; the
panel never trusts an arbitrary redirect or Location header.

## Weather panel

The weather widget/panel uses a location state file and two bounded HTTP
sources. Stored coordinates use Open-Meteo; otherwise wttr supplies the
detected location and forecast. Open-Meteo's current conditions are normalized
to the wttr shape. The location editor geocodes after `300 ms` debounce, shows
up to five suggestions, and writes a name plus coordinates or clears to
auto-detect.

```text
refresh default               15 minutes
panel width cap               480 px
wttr timeout                  10 s
Open-Meteo timeout            5 s
geocoder timeout              5 s
location detector timeout     4 s
failed fetch retries           3, each after 2500 ms
```

The hero uses literal 64 px weather glyph and literal 56 px temperature, with
16 px left margin, 16 px icon/temperature gap, and 2 px number/unit gap. The
unit is a 24 px display token with a 10 px top offset. The right side has a
20 px right margin, 12 px vertical stat gap, and 36 px between feels/wind/
humidity columns. Location editing uses a 190 px field and an 18×18 px clear/
spinner action.

The forecast shows three future days. Each cell uses a display-sized icon,
10 px icon/detail gap, and a 6 px high/low gap; the row's cells are separated
by 44 px. Units are metric or imperial based on explicit setting, country, or
locale. The bar widget hides until it has a label and uses a status slot.

## Cloud-sync panel

The cloud-sync capability demonstrates a plugin with local QML UI, a companion
service object, a Python status helper, and a custom vector icon. The helper
reads the local account file, runs the CLI status command with a 4 s timeout,
scans local files without following symlinks, calculates total bytes, and
returns the 25 most recently modified files.

```text
refresh default             60 s (clamped 10–3600)
startup ramp                every 2 s, at most 15 ticks
post control refresh        every 1500 ms, at most 4 ticks
action status display       2200 ms
panel width cap             380 px
panel max height            560 px
custom icon box             1.18 × iconSize wide
```

The service uses an optimistic pause/resume state, reconciles it from status,
and opens a detected authentication URL externally. Files open through a
file URI with the desktop file manager. The panel has a hero switch, login
row, stored usage, and recent-file rows; each file row has a glyph, filename,
relative time/folder metadata, and 10 px side insets.

## Tunnel/VPN panel

The tunnel service calls the external tunnel CLI for status JSON, account list,
exit nodes, and optional region data. It filters IPv4 addresses to the tunnel
range and IPv6 to the tunnel prefix, normalizes trailing DNS dots, deprioritizes
proxy players/accounts where applicable, and exposes a service plus bar widget.

```text
refresh default             30 s (clamped 5–3600)
startup ramp                every 2 s, at most 15 ticks
process watchdog            15 s
login fallback timeout      10 s
action status display       2200 ms
panel width cap             380 px
panel max height            560 px
copy popup width            280 px
copy-choice row height      48 px
region row                  content height + Style.spacing.lg
```

The panel sections are header, optional operator authorization, connections,
exit nodes, optional region search, and machines. It supports account switch,
exit-node selection, recent region history (maximum five), copy name/DNS/IPv4/
IPv6, and file sending when the Taildrop capability says the peer is eligible.
The service uses optimistic on/off state; operator authorization is the only
action that uses `pkexec`.

## Agent usage dashboard

The dashboard is deliberately data-driven. A usage collector writes one JSON
record per provider into `STATE/agents/usage/*.json`; the panel discovers any
new record without source edits. Local `FileView`s watch each record, and an
optional sync directory merges device snapshots.

```text
refresh default/minimum     900 s / 30 s
sync debounce               1000 ms
panel width cap             380 px
panel max height            640 px
usage refresh modes         normal, force, limits-only
limits retry                30000 ms when record advises retry
```

The bar icon self-hides when there are no enabled providers with data. The
panel contains provider tabs only when more than one provider has data; a
single provider has no switch row. It shows a mark/title/plan hero, optional
auth/error status, prepaid balance or rate limits, seven day rows, and up to
four model rows.

```text
meter thickness              max(4 px, round(controlHeight × .14))
day label/value width         52 px each
day bar margins               8 px left, 10 px right
model bar row side padding    8 px
day/model row vertical gap    shared sm/lg scale
```

Rate limits alarm at `90%`; funded balances alarm at the final `10%`.
Account-scoped sync stats take the widest value to avoid double-counting;
device-scoped stats add across devices and active dates are unioned. Sync
settings are inline: `refreshIntervalSec`, `syncMode`, `syncDir`,
`syncFileName`, `syncDeviceId`, and a nested `providers` object.
