# Services, notifications, OSD, lock, and modal surfaces

These components are host-owned services or transient surfaces. They are not
all opened by a bar click, but they still have complete lifecycles:

~~~text
service event or IPC
    -> normalize/validate state
    -> create/update surface
    -> external side effect or user response
    -> timeout/dismissal/completion
    -> persistence and cleanup
~~~

The feature geometry is in 07a-system-services-and-hosted-surfaces.md. This
document records the source-defined state transitions.

## Background renderer and theme transition

### Initial and requested background

The background service is loaded as a first-party service and constructs one
rendering PanelWindow per screen. On completion it reads the resolved current
background symlink. The same read is requested after the background switcher or
theme switcher process exits.

The background path transition:

~~~text
readlink -f current/background
    -> trim path
    -> if changed, increment backgroundVersion
    -> choose instant or image reveal
    -> update displayed background
~~~

An empty path or an unchanged final path is ignored unless a forced theme
transition requires the file behind an unchanged path to be reloaded.

### Image/video transition branches

The source uses a 420 ms InOutCubic reveal for an image-to-image transition
when both old and incoming paths are images and a displayed background exists.
The reveal sequence is:

~~~text
oldBackground = current displayed path
incomingBackground = new path
revealProgress = 0
per-screen mask becomes ready
apply pending theme payload
animate revealProgress 0 -> 1 over 420 ms
displayedBackground = final path
finishingTransition = true
~~~

A video path, an absent prior background, or an instant request bypasses the
image reveal and swaps immediately. The service does not decode two full videos
during a transition.

### Theme payload

When a theme command supplies base64 colors and shell tokens, the service stores
the decoded payload with the current background version and arms a 300 ms
fallback timer. If an image reveal is available, the payload is applied at the
start of that reveal; otherwise it is applied immediately. The latest payload
is applied even if background polling advances the version.

Applying the payload loads Color, reloads Style, and clears the pending payload.
The background file and theme values are therefore synchronized at a defined
transition boundary instead of each repainting independently.

### Covering surfaces

The renderer obtains lock, screensaver, and battery service state. Video
playback is disabled when the session is obscured by lock/screensaver, when a
per-screen fullscreen surface covers the output, or when power-saver state
requires it. A locked/covered video must not continue decoding indefinitely.

## Notification lifecycle

### Receive and normalize

The notification server supports images, actions, body markup, hyperlinks, and
persistence. On notification:

1. mark the server object tracked so it survives the signal callback;
2. snapshot all card fields and timestamp;
3. store the live object by original id outside ListModel;
4. connect replacement/update signals;
5. apply DND and ephemeral rules;
6. persist a popup file;
7. defer model insertion until the Repeater is safe;
8. refresh the row once it exists.

Live notification QObjects are never stored directly in ListModel roles. A
replaces_id update mutates the tracked object in place; the service copies the
new card fields into the row and rewrites the same popup file.

### DND branch

With DND on, a notification bypasses DND only when the source rules match:
omarchy-action, or critical urgency from app_name notify-send. A silenced
non-ephemeral notification is written directly to history; a silenced
ephemeral notification is discarded after untracking. DND does not mean
silently dropping every notification.

### Popup presentation

The service builds one full-screen overlay PanelWindow per screen with
keyboard focus None. The input Region contains only the toast column, so the
transparent full-screen surface remains click-through elsewhere.

Cards are stacked top-right with Style.space(8) spacing. The bar clearance is
added only when the bar occupies the top or right edge. A card click invokes its
default action or focuses the sender application and then dismisses. A right
click or hover close calls dismiss.

Durations are exact:

~~~text
critical -> 0 (no expiry)
low      -> max(5000, requested), capped at 30000
normal   -> max(8000, requested), capped at 30000
~~~

Each live card ticks its remaining lifetime every 50 ms. Hover pauses the
countdown. A changed summary/body/image resets the card's remaining lifetime.

### File and history terminal states

Each live popup has one JSON file under the popup state directory. When it
expires, is dismissed, or its action is invoked:

~~~text
popup file -> serialized file queue -> history directory
             -> popup row removed
             -> live server object dismissed/expired when still live
~~~

The queue serializes writes, copies, moves, deletes, and history reads. Image
files are copied with a five-second, 5 MiB per-file bound before the JSON
references the copy. Broken or torn JSON lines are skipped on restore.

The newest ten history entries are retained. showHistory queues a directory
read as a barrier, carries live rows already on screen, restores newest-first
rows, and shows No recent notifications when no rows exist. Restored rows are
marked so their old server ids cannot dismiss an unrelated notification from a
new server generation.

The settings file stores version 3 and the DND boolean. Loading old legacy
arrays schedules a rewrite that removes the obsolete payload.

### Notification IPC

The notifications target provides:

~~~text
dndState/isDnd -> on/off
toggleDnd      -> flip and return new state
setDnd(value)  -> parse true/1/on/yes or false
showHistory    -> replay history
clear          -> clear recorded history but leave current toasts
dismissAll     -> dismiss current toasts
dismissOne     -> dismiss newest
invokeLast     -> invoke newest default action then dismiss
dismiss(text)  -> dismiss rows whose summary contains substring
~~~

## OSD lifecycle

The OSD is a transient, no-focus overlay with an empty input Region. A show
request parses icon/message/value/max/progress text/duration, maps icon aliases,
updates all visual fields before setting opened true, and restarts the hide
timer when duration is positive.

~~~text
osd.show(payload)
    -> stateForShow normalization
    -> opened = true
    -> hide timer = requested duration, default 1200 ms
    -> timer expiry -> opened = false
~~~

Duration zero stops the hide timer and leaves the OSD open until an explicit
close. A subsequent show replaces the current values; it does not queue a
second OSD. The card is measured from icon/message/progress content and is
anchored at the bottom with the source-defined 67 px margin.

The OSD IPC target exposes show, close, state, and ping. It must never take
keyboard focus or block desktop clicks behind the visual card.

## Session lock and unlock

### Lock request

The lock service refuses to begin when the password PAM configuration is not
known good. A valid request:

~~~text
reset authentication state
lockRequested = true
arm five-second blank timer
queue session lock stabilization
defer background and fingerprint refresh
~~~

Session lock is requested only after a real screen exists. A 500 ms stabilization
timer and a repeating 100 ms pending timer retry the request while outputs are
not yet meaningful. Once WlSessionLock becomes locked, pending timers stop.

### Idle and explicit lock

The idle service starts an idle cycle after the configured first-idle timeout.
It separately schedules screensaver and lock delays. Screensaver launch is
guarded by an isLocked check and a three-second launch grace. If no screensaver
window appears and the compositor reports activity, the cycle is cancelled as
screensaver-not-running. If the user dismisses the screensaver before the lock
deadline, the idle cycle is cancelled and wake is run.

An explicit lock request uses the lock service IPC target. status and isLocked
report requested, session-locked, secure, PAM, fingerprint, screen, timer, and
process state.

### Lock surface

The session lock surface is a WlSessionLockSurface. It injects the current
background, version, fingerprint configuration, authentication state, blank
state, battery power-saver state, and password text into LockView.

The LockView contract includes:

~~~text
password field = 381 x 67
outline        = 3 px
password text  = centered masked dots with no delay
background     = image/video with blur/darken behavior
fingerprint    = hint at field's right edge when configured
~~~

Any click or pointer movement wakes the display and focuses the password field.
Text entry wakes it too. Escape or Ctrl+U clears the entered password; it does
not unlock or destroy the lock.

### Password path

Submitting a non-empty password while not already authenticating:

~~~text
runWake
pendingPassword = submitted value
failureMessage = empty
authenticatingPassword = true
start PAM context
wait for response request
respond with pendingPassword
~~~

The input is cleared before submission. PAM success calls finishUnlock.
Failure clears authentication/password state, increments failedAttempts, sets
Authentication failed (n), and wakes the display. A PAM error takes the same
failure path.

finishUnlock clears lockRequested, pending lock state, authentication state,
blank timer, and sessionLock.locked, logs unlocked, and runs wake.

### Fingerprint path

When the fingerprint PAM configuration is present, the lid is open, and the
session is secure, fingerprint authentication starts if not already active.
Success calls finishUnlock. A non-success result schedules a 250 ms retry while
the lock remains requested. A closed laptop disables fingerprint mode and
leaves password authentication.

### Blanking and video recovery

The lock blank timer is exactly 5000 ms. A wall-clock suspend gap longer than
the timer plus 2000 ms rearms it instead of blanking immediately after resume.
Only an active password check holds the display up; a long-running fingerprint
attempt does not.

When the locked background is a video, monitor DPMS state is polled every
3000 ms. Wake and blank state are optimistic until the next poll. Screens
coming back clear displaysBlank and re-request the session lock.

The service also checks for a stranded lock left by an earlier shell process.
It polls every 500 ms for at most 20 attempts, and recovers it only when the
password PAM is configured and the current shell does not already own the lock.

## Policy authentication surface

### Request start

The policy agent listens for authentication requests. When a request starts it
stops a close timer, clears submission state, clears the password field,
refreshes lid state, snapshots the current message/prompt, and focuses either
the fingerprint key catcher or password field.

The displayed card is:

~~~text
fieldHeight = max(Style.space(42), Style.spacing.controlHeight)
cardHeight  = fieldHeight + contentMargin * 2, bounded by screen
cardWidth   = cardHeight in fingerprint mode
              otherwise min(Style.space(312),
                           max(Style.space(260), screen - margins))
~~~

Fingerprint mode shows only the centered sensor glyph. Password mode shows the
lock glyph, field, prompt, and justification label.

### Submit, cancel, failure

Enter in the password field calls submitResponse. It marks submitted, sends
the field value to the live polkit flow, clears the field, and returns focus to
the key catcher. Escape in either the key catcher or password field calls
cancelRequest, clears the field, sets closing true, starts the 300 ms close
timer, and cancels the live authentication request.

Authentication success or cancellation also sets closing and uses the 300 ms
timer to reset the snapshot. Failure clears submitted state, flashes the error
border/text, shakes the card through -8/8/0, restarts a 1200 ms error timer,
and refocuses the appropriate input.

The service reads /etc/pam.d/polkit-1 to detect fingerprint configuration and
checks the lid with omarchy-hw-laptop-closed. If another polkit agent is
registered, registration state is logged and the dialog does not claim that it
owns the request.

## Media, battery, idle, and night-light services

### Media

The media service tracks live MPRIS players and derives active/source player
order reactively. The bar widget is visible only when the active player has a
title or artist.

~~~text
left click       -> active player play/pause
middle click     -> next
right click      -> toggle PopupCard
wheel up         -> previous
wheel down       -> next
popup buttons    -> targeted previous/playPause/next
source row       -> select player
~~~

Actions resolve a targeted player, prefer the active/oldest capable player
according to the source rules, update preferredPlayerKey on success, and may
schedule a 120 ms coalesced OSD for track-changing actions. The media popup
closes on its own close path; the service remains loaded.

### Battery

The battery service reads the active power profile every 2000 ms and checks low
battery every 30000 ms. It warns at or below 10 percent once per persistent
notification cycle. A battery/AC change checks the battery, applies the
appropriate power profile, and refreshes the profile.

If a profile write is running, the newest desired source is queued. Completion
runs the queued source and then rereads the profile. UPower owns battery truth;
the service does not fabricate a profile success before the helper returns.

### Idle/stay-awake

The idle service reads stay-awake state from a marker file under the state
directory. Enabling stay-awake persists the marker, cancels an active idle
cycle, and disables the idle monitor. Disabling it removes the marker and
re-evaluates current idle state. A write already in progress keeps only the
latest desired boolean and applies it after exit.

The idle service logs every stage, exposes status/debug/enable/disable/toggle
IPC, and never starts two copies of the screensaver, lock, or wake process.

### Night light

The night-light service probes hyprsunset temperature on construction and
after each apply. Enable sets 4000 K, disable sets 6500 K. An apply launches
hyprsunset through a guarded detached process if needed and then sets the
temperature. A second request while busy queues the newest temperature. The
service rereads state after the final apply.

## Acceptance checks

1. Change an image background, video background, and theme payload. Verify the
   instant/reveal branches, 420 ms reveal, 300 ms theme fallback, and
   last-good renderer behavior.
2. Send normal, low, critical, transient, DND-silenced, replaces_id, image,
   action, hover, right-click, expiry, and history-replay notifications.
3. Show two OSDs in succession and verify the newest state replaces the old
   timer; verify the OSD input Region is empty.
4. Lock with no real screen, with a screensaver, with password failure,
   fingerprint retry, lid closed, display blanking, and stranded lock state.
5. Cancel policy authentication by Escape, submit success/failure, and verify
   the 300 ms reset and 1200 ms error feedback.
6. Exercise media, battery, idle, and night-light actions while their helper
   processes are delayed; verify the queued-latest and no-duplicate-process
   contracts.

