# Device and connectivity panel flows

This document records the user-to-system transitions for audio, Bluetooth,
display, power, and network panels. The detailed visual measurements are in
07b-bar-widgets-and-device-panels.md. The rules here describe how a click,
keyboard action, helper process, native model change, or cancellation reaches a
terminal state.

All five bar panels use the shared bar-panel contract:

~~~text
bar target -> feature button -> feature open/toggle
    -> PanelController.opened
    -> KeyboardPanel focus/popout lifecycle
    -> feature refresh and model projection
    -> user action or Escape
    -> feature cleanup -> shared focus/popout release
~~~

## Audio panel

### Open and initial state

The audio plugin is a direct Panel bar widget. Its button dispatches:

~~~text
RightButton -> toggleAllMuted()
otherwise   -> Panel.toggle()
wheel       -> accumulate wheel steps; change output volume by 0.05 per step
              and summon the OSD with the resulting percentage
~~~

When opened changes to true, the panel:

1. snapshots the current eligible sinks, sources, and streams;
2. selects the output section;
3. sets selectedIndex to -1, the output-slider sentinel;
4. clears cursorActive until hover or keyboard navigation;
5. schedules scroll reset.

When opened changes to false, it stops the 75 ms model-refresh debounce and
clears the projected display lists. PipeWire's live nodes remain owned by the
native model; the panel does not destroy them.

The KeyboardPanel arguments are:

~~~text
contentWidth  = fittedContentWidth(Style.space(380))
contentHeight = fittedContentHeight(panelColumn.implicitHeight, Style.space(560))
anchorItem    = audio button
owner         = audio Panel root
focusTarget   = PanelKeyCatcher
~~~

### Model and external boundaries

The candidate lists are filtered before projection:

~~~text
sink list    -> sink nodes that are sinks and not streams
source list  -> non-sink, non-stream capture nodes, excluding quickshell
stream list  -> playback-like stream nodes
~~~

The volume sink helper runs every 15 seconds even when the panel is closed.
This resolves a DSP/default sink to the physical sink so bar volume changes do
not stop at a processing node. Sink availability is refreshed every 5 seconds
while the panel is open. PipeWire churn schedules one display snapshot after
75 ms; every snapshot clamps the cursor to the remaining rows.

An open input peak monitor is enabled only while the panel is open and a
default source exists. MPRIS players are used to cross-label streams but the
display lists are primitive snapshots.

### Actions

The single cursor model uses sections header, output, input, and streams:

~~~text
header, Enter/Space -> toggle output and input mute together
output, index -1   -> toggle resolved physical output mute
output, row        -> set PipeWire preferred default and helper default
input, index -1    -> toggle default source mute
input, row         -> set PipeWire preferred default and helper default
streams, row       -> toggle stream mute
h/l on output/input sentinel -> volume by 0.05
h/l on stream row              -> stream volume by 0.05, clamped to 1.5
m/M                           -> mute the current target
Tab                             -> switch neighboring bar panel
Escape                          -> Panel.close()
~~~

Device row clicks update the root cursor and set the selected default. The
inline stream mute icon toggles only that stream. No row action may mutate a
stale primitive snapshot without resolving the corresponding live node.

## Bluetooth panel

### Open and discovery ownership

The Bluetooth plugin is a direct Panel widget. Its button dispatches:

~~~text
RightButton -> toggleBluetooth()
otherwise   -> Panel.toggle()
~~~

toggleBluetooth runs omarchy-bluetooth-power with off or on based on the
current adapter state. It does not optimistically flip the adapter object.

On open, the panel:

1. adopts an already-discovering adapter as a stop debt;
2. chooses the first connected device, otherwise first known device, otherwise
   first discovered device, otherwise the header;
3. clears action-focused and cursor-active state.

When open and the adapter is enabled but not discovering, a 1000 ms retry timer
sets adapter.discovering true and records that this instance owes the stop.

Closing does not blindly write false once. The close debt timer runs only when
this instance owns a discovery stop and the adapter confirms discovering true.
It:

~~~text
find a surviving open sibling
    -> transfer the debt to that sibling and clear local debt
otherwise
    -> attempt adapter.discovering = false at most three times
    -> abandon after the fourth timer tick
~~~

When BlueZ reports discovering false, the debt is cleared. A destroyed instance
transfers debt to a sibling or stops the adapter only when it is the last
instance. A session started by another client is never treated as this panel's
stop debt.

### Device actions

The panel projects connected, known, and discovered groups. UUID-like and
address-like labels are filtered. Row actions resolve the live device by
address at activation time:

~~~text
connected row, left/Enter -> disconnect
known row, left/Enter      -> connect
discovered row, left/Enter -> connect
right on connected         -> disconnect
right on known             -> forget
x/X on connected/known    -> forget
header, Enter/Space/b      -> toggle adapter
~~~

Connect, disconnect, and forget actions are tracked by address with a 20,000 ms
pending-action expiry. Completion is accepted only when the live object's
connected, known, or state-changing flags prove the intended transition.
Connecting an audio device may trigger a 500 ms retry that matches it to a
PipeWire sink.

The first cursor is selected by current live data, not by a fixed row index.
Tab switches neighboring panel widgets; Escape uses the shared close path.

### Surface

~~~text
contentWidth  = fittedContentWidth(Style.space(380))
contentHeight = fittedContentHeight(column.implicitHeight)
anchorItem    = Bluetooth button
owner         = Bluetooth Panel root
focusTarget   = PanelKeyCatcher
panel spacing = Style.space(14)
~~~

## Monitor/display panel

### Open and refresh

The monitor plugin is a direct Panel widget. Its button toggles the panel and
its wheel changes brightness by 5 percentage points per completed wheel step,
then summons the OSD. It refreshes once on construction and every 5 seconds
while open.

When opened changes to true:

~~~text
refresh state
if brightness is available:
    focusSection = brightness
    selectedIndex = -1
else:
    focusSection = scale
    selectedIndex = 0
cursorActive = false
~~~

The state process omarchy-monitor-state supplies, in order, brightness,
internal monitor, external monitor, internal-enabled state, mirror state,
focused monitor, scale, and display JSON. Invalid/unavailable brightness
selects the scale section instead of manufacturing a brightness control.

### Brightness transaction

The brightness slider updates the local percentage immediately, places the
pending percentage beside it, and starts:

~~~text
omarchy-brightness-display --no-osd --monitor <focused> <percent>%
~~~

If another adjustment arrives while the process is running, only the latest
pending percentage is retained. When the process becomes idle, that latest
value is sent. The panel deliberately does not refresh hardware state after a
set because an empty driver response would appear as a false zero. The
five-second poll remains the external-change reconciliation path.

### Scale and display actions

~~~text
scale h/l or pointer -> choose one of 1, 1.25, 1.6, 2, 3, 4
scale Enter/Space    -> omarchy-hyprland-monitor-scaling <scale>
monitor row click     -> hyprctl keyword monitor <name>,disable
                         or <name>,preferred,auto,auto
~~~

The last enabled display cannot be disabled. Display rows and scale values are
clamped when live state changes. The panel uses a fitted width of
Style.space(380) and a fitted height capped at Style.space(560).

## Power panel

### Open and visibility guard

The power plugin is a direct Panel widget. The button dispatches:

~~~text
RightButton -> togglePercentage()
otherwise   -> Panel.toggle()
~~~

togglePercentage changes the inline showPercentage setting locally and asks
the bar to persist it with updateEntryInline. It changes the bar button width
on horizontal bars; the open indicator uses the painted glyph width in that
state.

When opened changes true, the panel checks for a present UPower display device.
If none exists it immediately closes again. Otherwise it refreshes battery,
power-profile, and system information, chooses the active profile, and clears
cursor-active state. A 5-second timer repeats refresh while open.

Transient empty key/value or profile payloads are ignored so sections do not
collapse during AC transitions. Last-good data remains visible until a
non-empty replacement arrives.

### Profile action

The profile cursor moves through the parsed profile list. Activating a profile
runs:

~~~text
omarchy-powerprofiles-set battery|ac <profile>
~~~

The first argument is selected from the current discharging state. The panel
does not invent a success state before the helper completes. Escape closes
through the shared Panel contract; no profile editor is left active.

The surface uses a fitted content width of Style.space(380) and the panel's
measured content height. If no battery is present, KeyboardPanel.open is also
guarded by batteryPresent, so an unavailable device cannot leave a visible
empty card.

## Network panel

### Open, scan, and close

The network plugin is a direct Panel widget with a centralized close method.
Its button does exactly:

~~~text
if opened: close()
else:      open()
~~~

On open, the PanelController changes opened and the onOpenedChanged handler:

1. calls refresh(true);
2. selects the first Wi-Fi row, or -1 when none exists;
3. sets wifi action focus false;
4. selects portal, Wi-Fi, or DNS as the initial section;
5. synchronizes DNS/band selection;
6. makes the cursor active only when a captive portal is present.

refresh starts details, DNS, and band processes if idle, requests the native
NetworkManager connectivity check, and enables the scanner. A requested scan
temporarily disables scanning, waits 100 ms, re-enables it, and settles rows
after 1500 ms. Details poll every 1500 ms; band availability polls every 4 s.

On close, the panel:

~~~text
controller.hide()
cancelPasswordPrompt()
stop pending scan-restart timer
reset throughput samples and ping histories
disable the scanner owned by this instance
~~~

The passphrase prompt is therefore not allowed to remain visible or retain
password state after the network card closes.

### Header actions

The header exposes only actions supported by current state:

~~~text
Show QR -> hide network controller, clear password prompt,
           summon omarchy.wifiqr with known iface/SSID unless forced detection
Speed   -> hide network controller, clear password prompt,
           summon omarchy.speedtest with current connection name
Wi-Fi   -> flip Networking.wifiEnabled, then refresh(true) next event turn
DNS     -> choose DHCP, Cloudflare, Google, or Custom
Band    -> choose Automatic or an available band
Portal  -> launch fixed captive-portal URL and close
~~~

Custom DNS launches the floating-terminal helper with a quoted command and
closes the panel. Other DNS changes run the action process, close the panel,
and publish the requested provider only after successful exit.

### Wi-Fi row state machine

Each visible row is a primitive snapshot. On click it first resolves its live
NetworkManager object by SSID:

~~~text
connected                  -> disconnect
requires credentials/not known -> open inline passphrase prompt
known/passwordless        -> connect directly
~~~

Connected rows disconnect. Forget is a separate right-side action when the
source permits it; keyboard h/l moves from the row to that action.

The inline prompt sets passwordSsid and blocks PanelKeyCatcher. The identity
field is visible for enterprise security and its Enter moves focus to the
passphrase field. The passphrase Enter submits:

~~~text
ordinary network -> live connectWithPsk(passphrase)
enterprise       -> enterprise helper; secret is written to stdin, not argv
~~~

Escape in either prompt field calls cancelPasswordPrompt and keeps the network
panel open. When the prompt closes while the panel remains open, focus returns
to the main key catcher.

Connect/disconnect/forget actions set actionKind and actionSsid, show a
transient status, and arm a 30,000 ms timeout. Live NetworkManager signals
clear a successful action only when the intended state is proven. A failure
stores the matching SSID and reason, refreshes the panel, and may reopen the
passphrase prompt only for a connect initiated by this panel. A stale row or a
different SSID cannot clear or overwrite another action.

### Connectivity and captive portal

The panel uses NetworkManager's native connectivity result. It distinguishes
portal, limited, full, and none. When restricted and checks are enabled, it
polls every 10 seconds even if the panel was closed so the bar can continue to
show that sign-in is needed.

The portal action is explicit only. It invokes the fixed captive portal URL
through the browser launcher and closes the panel. No URL from network content
is executed as a shell command.

## Shared terminal behavior

Audio, Bluetooth, monitor, power, and network use the shared
KeyboardPanel/PanelKeyCatcher focus and popout rules. A normal Escape therefore
means:

~~~text
feature close override, if any
    -> controller.hide
    -> opened false
    -> KeyboardPanel focus None
    -> active popout released
    -> outside/twin dismissal disabled
    -> card fade completes
~~~

Network and editor states are exceptions: Escape in a passphrase field cancels
the field, Bluetooth discovery close settles a stop debt, and any action
process must preserve its source-defined stale-result guard.

## Acceptance checks

1. Exercise each bar button's left, right, middle, and wheel branches exactly
   as defined above; do not reuse a neighboring panel's mapping.
2. Open and close Audio while PipeWire nodes change. Verify snapshot debounce,
   cursor repair, peak-monitor lifetime, and physical-sink resolution.
3. Open Bluetooth with an existing discovery session, close it, reopen it on a
   second monitor, and verify stop-debt transfer and bounded attempts.
4. Change brightness repeatedly while the helper is busy and verify only the
   latest queued value is sent and no false zero refresh occurs.
5. Open Power without a battery and verify it closes without a visible empty
   panel; with a battery, verify profile actions use the correct AC/battery
   argument.
6. Connect to an open, known, secured, and enterprise Wi-Fi row. Verify
   direct connect, prompt, prompt Escape, stdin-only enterprise secret, action
   completion, wrong-password reprompt, and 30-second timeout.
7. Open QR, speed-test, DNS, and captive-portal actions from Network and verify
   the network panel closes before the secondary surface opens.
8. Press Escape in every normal and inline-editor state and verify the correct
   terminal state rather than assuming one universal close.

