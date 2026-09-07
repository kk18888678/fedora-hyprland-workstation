# Auxiliary panel and secondary-surface flows

This document covers the panels that start external account, tunnel, file,
network-test, or QR work. The source-specific dimensions remain in 07b and
07c; the lifecycle and cancellation paths are defined here.

## Dropbox

### Open and service refresh

The Dropbox plugin is a direct Panel bar widget with a matching service object.
The button dispatches:

~~~text
LeftButton   -> Panel.toggle()
RightButton  -> dropbox.refresh()
MiddleButton -> dropbox.login()
~~~

When opened changes true, the panel clears cursor state, scrolls to the top,
calls dropbox.refresh, and defers focus to the KeyboardPanel catcher. The
service independently performs a triggered-on-start periodic refresh using its
configured interval, clamped to 10 through 3600 seconds. Its status helper is:

~~~text
python3 <repository>/shell/plugins/panels/dropbox/status.py 25
~~~

The parsed status controls installed, running, authenticated, account, plan,
quota, files, and error state. Invalid status preserves the prior usable fields
and reports an error instead of pretending the service is absent.

### Login, pause, and file open

If not authenticated, cursor activation or the login row calls dropbox-cli
start. Output from stdout and stderr is scanned for the first URL. That URL is
opened externally once, and the process exit determines whether an error is
shown. A delayed refresh follows completion.

For an authenticated service:

~~~text
header activation -> toggle pause/resume
p/P              -> toggle pause/resume
file row          -> uwsm-app -- nautilus --select file://<encoded path>
r/R               -> service refresh
Escape            -> panel close
~~~

Pause/resume is optimistic: a desired value remains in memory until the status
refresh catches up. A failed control process removes the optimistic override
and publishes the error. File rows use primitive service snapshots but launch
only the selected path.

## Tailscale

### Open and service state

The Tailscale plugin is a direct Panel widget backed by a service singleton.
The button dispatches:

~~~text
LeftButton   -> Panel.toggle()
RightButton  -> tailscale.toggleTailscale()
MiddleButton -> tailscale.refresh()
~~~

When opened changes true, the panel resets cursor and scroll, calls
tailscale.refresh, and defers focus to its KeyboardPanel catcher. The service
first checks whether the executable is installed; when installed it launches
status JSON, exit-node listing, and accounts listing as needed. A watchdog is
armed only when a new request was launched and is not continuously restarted by
short refresh intervals.

Unavailable or unparseable status clears live peers, accounts, exit nodes, and
authentication state through the service's resetUnavailable path. The panel
then renders the source-defined unavailable state rather than stale peers.

### Header and account actions

The current cursor section is one of header, authentication, accounts, peers,
or exit nodes. Activation maps to:

~~~text
header      -> login/up or down according to installed/active/needs-login
auth        -> authorize the operator
accounts    -> switch to selected account
peers       -> open the peer copy chooser
exit nodes  -> connect or disconnect selected exit node
~~~

The service's login plan may open an authorization URL in the browser. If the
device is active, down runs tailscale down with optimistic state until status
confirms it. Account switching, operator authorization, and exit-node
selection each have their own running guard and completion/error parser.

### Peer actions and nested copy popup

On a peer row:

~~~text
send-files action -> service sendFile(peer), then panel close
copy action       -> open nested Popup
keyboard s        -> send selected peer
keyboard c/n/d    -> copy peer IP/name/DNS name
~~~

The copy popup is a Qt Popup with width Style.space(280), non-modal focus, and
CloseOnEscape plus CloseOnPressOutside. While it is open, the parent
PanelKeyCatcher is blocked. The popup key handler moves with j/k or Up/Down,
activates with Return/Enter/Space, and Escape closes only the popup. When the
popup closes while the panel remains open, focus returns to the parent catcher.

### Exit-node and Mullvad chooser

Clicking an exit-node row invokes the service selection. A synthetic Add
Mullvad row opens the inline region chooser. The chooser search field owns
focus; j/k, Up/Down, and Enter operate the filtered region list; Escape closes
the chooser and returns focus to the main catcher without closing the Tailscale
panel.

## Internet speed test

### Open

The speed-test plugin is a standalone panel, not a bar-widget panel. The
network panel summons it with an optional connection label. A direct host
summon may pass:

~~~text
{ "connection": "display name" }
~~~

If no name is supplied, the plugin runs omarchy-network-status and maps the
first tab field to Wi-Fi plus SSID, Ethernet, or no title. It then sets opened
true and starts a fresh test.

The test has:

~~~text
phase = down or up
downloadMbps
uploadMbps
running
expectedStop
pendingRun
error
~~~

The down process runs first, followed by the up process after normal
completion. Each phase has a 5000 ms timer that calls stopPhase. A non-zero
unrequested exit publishes stderr or the source fallback error. A dismissal
clears phase and running before stopping the child so the exit handler cannot
mistake a deliberate stop for a failed download and advance to upload.

### Close and rerun

The shared SpeedTestOverlay is a full-screen Overlay layer-shell window with a
fixed near-black scrim, two dials, and no input on the outside card itself.
Escape, scrim click, or the overlay close request calls dismiss, which asks the
host to hide the plugin and then reaches close.

Run Again is enabled only when not running. If a new run is requested while a
previous dismissal's SIGTERM is still in flight, pendingRun is set and the
replacement starts from onExited only when the panel remains open.

## Disk speed test

The disk test follows the same standalone overlay contract but one command
streams both read and write phases:

~~~text
open -> opened true -> phase read -> omarchy-disk-speedtest
output:
    disk <model>  -> diskName
    read <MB/s>   -> read rate and phase read
    write <MB/s>  -> write rate and phase write
normal exit -> clear phase/running
Escape/scrim -> host hide -> close -> expectedStop -> stop process
~~~

The disk overlay uses read/write scale stops
500, 1000, 2500, 5000, 10000, and 15000. Empty or invalid stream lines do not
replace a valid rate. stderr can replace a generic error after the stream
collector finishes because exit and stream-finished order is not guaranteed.

## Wi-Fi QR surface

### Request route

The network panel closes its own controller and password prompt before summoning
the separate Wi-Fi QR plugin. The host special IPC target image-selector is not
used here; the network panel calls shell.summon on omarchy.wifiqr with:

~~~text
{ iface: known interface, ssid: known SSID }
~~~

when it has a current Wi-Fi interface, or an empty object when self-detection
is requested. The standalone panel also accepts a direct payload with iface and
ssid.

### Generation and secure cleanup

open parses the payload, clears an old title when no SSID was passed, starts QR
generation, sets opened true, and defers focus until the layer surface maps.
The command is:

~~~text
omarchy-network-qr --meta [iface]
~~~

The parser extracts QR rows, matrix size, interface, SSID, and security. Until
valid output arrives, the deep scrim remains and the surface displays its
loading/error state. An expectedStop flag suppresses both stdout and stderr
after dismissal, including buffered output that arrives after the child is
stopped. A pendingShow request is replayed after the canceled generation exits.

The password reveal is a second guarded process:

~~~text
password already cached -> reveal locally
no cached password     -> omarchy-network-password <iface>
successful live result -> store only while open, then reveal
close                  -> clear password, visibility, error, QR matrix, title,
                          interface, and security state
~~~

The password process cannot repopulate a closed card. Re-generation cannot
reveal a password belonging to the previous interface.

The QR surface is a full-screen Overlay PanelWindow with a fixed dark scrim
and no card dismissal target over its centered content. Escape and scrim click
call host hide/dismiss; content clicks are swallowed.

## Shared auxiliary terminal rules

All four test/secondary surfaces must distinguish:

~~~text
normal completion
deliberate stop
process failure
stale output after stop
new request while old process exits
~~~

Do not use a generic onExited handler that advances a phase after the user has
closed the panel. The reference uses expectedStop, phase clearing, request
serials, or pending-run flags for this purpose.

## Acceptance checks

1. Exercise Dropbox unauthenticated login, URL opening, failed login, pause,
   resume, failed control, and file selection.
2. Exercise Tailscale unavailable, needs-login, active, account-switch,
   operator-auth, peer-copy, file-send, exit-node, and Mullvad chooser states.
3. Dismiss internet and disk tests during every phase and immediately summon
   again. Verify no old process exit starts an unintended next phase.
4. Open QR with and without a payload, dismiss during generation, re-summon
   for another interface, reveal a password, and close. Verify no stale QR or
   password state survives.
5. Press Escape in the Tailscale copy popup and Mullvad chooser and verify only
   the nested chooser closes; press Escape again and verify the parent panel
   closes.

