# Bar widget, tray, and indicator flows

This document closes the lifecycle gap between a generic bar click contract
and the individual built-in widgets that do not own a full detail panel.
Dimensions are in 04-design-language.md, 05-ui-kit-and-measurements.md, and
07b-bar-widgets-and-device-panels.md. The source-defined input and side-effect
routes are recorded here.

## Visibility and placement rule

The bar mounts a widget only from the normalized layout entry. The widget's
own visible binding then controls effective slot extent. A hidden widget has
zero effective width/height and cannot be clicked through the ModuleSlot
pointer path.

Every WidgetButton:

~~~text
hover enter -> bar tooltip request
hover exit  -> bar tooltip clear
click       -> triggerPress(button) when pressable
triggerPress -> tooltip clear -> pressed(button)
wheel       -> wheelMoved(delta)
~~~

The parent slot may forward the same event to a registered target. The
implementation must keep one action per physical click.

## Active-window label

### State and visibility

The widget reads ToplevelManager.activeToplevel. Its label is the toplevel
title or app id, is hidden when empty or on a vertical bar, and is capped by
the maxWidth setting with default 280. The horizontal widget width animates for
180 ms with OutCubic when the label changes.

### Actions

~~~text
left click   -> active toplevel.activate()
middle click -> active toplevel.close()
right click  -> active toplevel.close()
~~~

If the toplevel disappears between hit-test and click, the action is ignored.

## Workspace switcher

The widget always presents ids 1 through 5, adds positive live ids through 10,
sorts numerically, and paints workspace 10 as 0. Horizontal cells are
Style.space(20) wide with 1 px column spacing; vertical layout uses one column
and 2 px row spacing. Cells are transparent bar slots rather than full-height
cards, so the number or dot stays visually inside the bar. Occupied or active
cells have opacity 1; empty non-focused cells have opacity 0.5. Occupied
workspaces show their number; empty workspaces show a theme-aware dot. The
active workspace replaces its number (or dot) with the theme-aware active glyph
instead of using a separate filled highlight.

Clicking a cell runs:

~~~text
hyprctl dispatch hl.dsp.focus({ workspace = "<id>" })
~~~

The workspace object is resolved at click-time. A vanished workspace does not
cause a stale dispatch.

## Keyboard-layout indicator

The widget loads layout descriptions once with xkbcli list --load-exotic,
polls hyprctl -j devices every 600 ms, and refreshes after activelayout or
configreloaded events. It excludes virtual, power-button, sleep-button,
lid-switch, and video-bus keyboards.

Selection is based on the keyboard named by the latest activelayout event or
the furthest advanced layout. A query already running sets refreshPending and
is repeated after completion. A five-second query watchdog and ten-second
ambiguity poll prevent a stale device label.

Visibility is false when the system has one resolved layout; it remains visible
when the list cannot be resolved. The displayed language is a three-character
uppercase label derived from xkb descriptions.

~~~text
left click -> hyprctl switchxkblayout <last-reading-keyboard> next
             -> refresh timer
~~~

The target keyboard is the one that supplied the current label. The seat is not
switched indiscriminately.

## Microphone

The widget follows Pipewire.defaultAudioSource. It is visible when a default
source exists. In-use means at least one unmuted capture stream and an unmuted
default source.

~~~text
left click   -> toggle default source mute
right click  -> toggle default source mute
middle click -> shell toggle omarchy.audio
wheel        -> source volume plus/minus 0.05, clamped 0..1
~~~

The icon and active state are derived from the source object, not from a
separate persisted flag. PwObjectTracker follows the current source.

## Spacer

Spacer is a non-interactive layout widget. Its configured size defaults to 12.
It contributes a span only when positive:

~~~text
horizontal -> width = configured size, height = bar size
vertical   -> width = bar size, height = configured size
~~~

It has no click, focus, process, or close lifecycle.

## System-update indicator

The update widget runs omarchy-update-available on construction and every
21,600,000 ms. It is visible only when the process exits zero. Its refresh and
clear IPC methods broadcast to every live monitor instance.

~~~text
left click -> launch floating terminal with omarchy-update
~~~

The click does not clear updateAvailable locally; the update lifecycle or
explicit clear broadcast owns that state.

## Indicator group

The group is a host-built family rather than a manifest-discovered extension
point. Default order is:

~~~text
Dictation, ScreenRecording, Reminder, NightLight, Dnd, StayAwake
~~~

Non-empty settings.items wins over settings.indicators; otherwise the defaults
are used. Entries may be strings or objects with id plus inline settings.

Each indicator loader resolves a relative QML file, injects bar, moduleName,
settings, indicatorBlock, indicatorHost, and activeOverride, then watches its
active property. Active state is observed before removing a formerly active
indicator so a just-loaded component does not disappear before its first
state report.

### Active/inactive order

The active block is closest to the center. When an indicator becomes active it
is inserted at the inner side of the active block. Inactive indicators are
hidden unless:

~~~text
alwaysShow is true
indicator group hovered
indicator item hovered
center reveal held and not center-hover-suppressed
~~~

Leaving the area waits 120 ms before collapsing inactive indicators. The
indicator group broadcasts refresh IPC to every live indicator instance.

### Dictation indicator

When the voxtype status command exists, the indicator follows
omarchy-voxtype-status:

~~~text
idle         -> inactive microphone glyph
recording    -> active microphone glyph
transcribing -> source assigns a transcribing glyph, but active is false
               and BarIndicator renders the inactive microphone glyph
~~~

Click launches omarchy-voxtype-config. Absence of the command leaves the
optional indicator non-operational without breaking the group.

### Screen-recording indicator

The indicator probes:

~~~text
pgrep --quiet -f ^gpu-screen-recorder
~~~

It refreshes on bar change, construction, and indicator-host refresh. Click
dispatches the stop command when recording, otherwise opens the capture menu's
screen-record route. Status exit code zero means recording.

### Reminder indicator

The indicator runs omarchy-reminder show --json. Successful JSON supplies count
and tooltip; a non-zero exit clears both. Click:

~~~text
count > 0 -> omarchy-reminder show
count == 0 -> omarchy-reminder -i
~~~

The indicator does not itself open the reminder overlay; the input command
does.

### Night-light indicator

The indicator uses the scoped first-party night-light service. Click calls
setNightlight with the inverse of the current service enabled state. The
service queues the newest temperature if hyprsunset application is busy.

### Do-not-disturb indicator

The indicator reads the notification service's DND boolean. Click calls
setDoNotDisturb with its inverse. Notification persistence and DND bypass rules
remain in the notification service.

### Stay-awake indicator

The indicator reads the idle service's stayAwake boolean. Click calls
setIdleEnabled with the current active state, which inverts the service's
stay-awake meaning and persists the marker file. An active idle cycle is
cancelled when stay-awake is enabled.

## System tray

### Item buckets

The tray reads Quickshell system-tray items and excludes passive items and items
owned by the shell's own menu/optional service. It classifies the remainder
into pinned, hidden, and drawer buckets from inline pinned/hidden id arrays.

The tray is visible only when pinned or drawer items exist. Each tray icon has
Style.space(12) paint size inside a Style.bar.iconSlot extent. The drawer
animation is 600 ms OutCubic; collapsed empty drawer space is outside the
containment mask and passes input through.

### Drawer and management

Hovering the drawer area changes expanded. The chevron is interactive only for
its right-click management action:

~~~text
right-click chevron -> toggle management popup
hover drawer       -> expanded true/false
~~~

The management popup rows persist pin/hide changes through one inline bar entry:

~~~text
Pin  -> add id to pinned, remove from hidden
Hide -> add id to hidden, remove from pinned
~~~

Rows are 28 px high, icons 16 px, Pin/Show/Hide buttons use 8 px horizontal
and 3 px vertical padding. The management popup caps content width at 300 px.

### Tray item actions

Each item MouseArea accepts left, right, and middle buttons:

~~~text
right click  -> display item menu
middle click -> modelData.secondaryActivate()
left + onlyMenu -> display item menu
left otherwise -> modelData.activate()
wheel        -> modelData.scroll(angleDelta.y, false)
~~~

If the item has a QsMenuEntry menu, the tray owns and renders the menu. If it
has no menu object, it calls the item's native display method at the mapped
pointer position.

### Nested menu lifecycle

Entering a submenu creates a new QsMenuOpener owned by the tray root and pushes
it onto submenuStack. Leaving pops and destroys the deepest opener. Every level
change sets menuLevelSettling and ignores row clicks for 250 ms.

The tray menu PopupCard:

~~~text
content width  = fitted Style.space(232)
maximum height = Style.space(420)
popup padding  = Style.space(8)
~~~

When the popup becomes invisible it resets scroll, clears the stack, and
destroys openers deepest-first. Switching to another tray item resets the old
stack before assigning the new model so a child opener never references a
destroyed parent entry.

## Shared terminal behavior

Simple widgets have no generic close state. Indicator clicks either mutate a
first-party service, launch a command, or open a separate host surface. Tray
menus own their PopupCard state. The system-update and layout widgets broadcast
refresh/status to all monitor instances when their source contract requires it.

## Acceptance checks

1. Activate and close an active window; click each workspace and verify the
   compositor dispatch id.
2. Change keyboard layouts on multiple physical keyboards and verify the
   selected device, refresh-pending, unresolved, and ambiguity behavior.
3. Toggle/middle-click/wheel the microphone and verify the audio panel handoff.
4. Trigger update available, clear, and update-launch paths on two monitors.
5. Exercise every indicator in active, inactive, hovered, always-show, and
   optional-dependency-absent states.
6. Pin, hide, reveal, secondary-activate, open submenus, rapidly switch tray
   items, and close tray menus; verify 250 ms settling and deepest-first
   destruction.
