# Information panels: clock and agent usage

This document traces the end-to-end behavior of the information surfaces that
are not covered by the device/connectivity or Weather-specific flow files.
Their dimensions and data schemas remain in 07b-bar-widgets-and-device-panels.md
and 13-ai-first-platform.md; this document records how a user reaches and
leaves those states.

## Clock/calendar panel

### Ownership and construction

The clock is a nested bar widget:

~~~text
bar slot
    -> clock BarWidget.qml
    -> nested Panel.qml Loader, active but visually hidden
    -> Calendar KeyboardPanel
~~~

The outer widget injects the live bar, inline settings, the visible button as
anchorItem, and the outer widget root as hostWidget. The nested panel uses the
outer widget root as barIdentity so the slot open indicator and active-popout
owner match.

The button uses:

~~~text
horizontal text       = configured date/time format
vertical text         = configured vertical lines
horizontal margin    = 8.75
vertical padding     = 8.75
tooltip              = Right-click to toggle format
horizontal slot      = normal WidgetButton sizing
vertical height      = number of lines * Style.bar.iconSlot
~~~

### Bar trigger branches

The clock button dispatches:

~~~text
LeftButton   -> nested Panel.toggle()
RightButton  -> cycleFormat()
MiddleButton -> bar.run("omarchy-menu-timezone")
~~~

The outer widget's host lifecycle methods are:

~~~text
open()  -> nested Panel.open()
close() -> nested Panel.close()
toggle -> nested Panel.toggle()
~~~

The nested Panel.toggle calls its open method only when closed. It does not use
the Weather openFromHotkey path.

### Format cycling

cycleFormat obtains the current configured format, asks Model.nextClockFormat
for the next member of the orientation-specific ring, and returns if there is
no change. Otherwise it:

1. copies the current settings excluding the id field;
2. writes the next format key, horizontal or vertical as appropriate;
3. assigns the new entry locally so the label changes immediately;
4. calls the shell updateEntryInline method when available.

The shell persists only if the inline entry is found and the serialized value
actually changes. The next bar rebuild must therefore receive the same format
that was shown on the click.

### Open sequence

The clock Panel.open method performs:

~~~text
refresh()
    -> today = new Date()
    -> goToToday()
controller.show()
Qt.callLater:
    if still opened, set center hover-reveal suppression true
~~~

The Calendar KeyboardPanel binds open to the panel controller and passes:

~~~text
contentWidth  = fittedContentWidth(Style.space(560))
contentHeight = fittedContentHeight(calendarColumn.implicitHeight)
centerOnBar   = true
anchorItem    = clock button
owner         = outer clock widget root
focusTarget   = PanelKeyCatcher
~~~

The shared 75 ms focus prime, screen selection, position clamp, active-popout
handoff, 140 ms close fade, and outside-click behavior are defined in
03-bar-panel-contract.md and apply here without alteration.

### Calendar state and keyboard path

The panel is a read-only month grid. It stores:

~~~text
today
viewYear
viewMonth
weekStart
editingLife
~~~

SystemClock runs at minute precision. When the date changes, the panel updates
today. If the user was viewing the current month, it follows today; if the
user intentionally browsed another month, it does not jump away.

When the panel key catcher is unblocked:

~~~text
Up/Down       -> move year by the semantic cursor delta
Left/Right    -> move month by the semantic cursor delta
[/]           -> previous/next month
{/}           -> previous/next year
t/T           -> return to today
w/W           -> toggle week-start setting
Enter/Space   -> return to today
Tab           -> switch to the neighboring bar panel
Escape        -> close panel
~~~

The source maps j/k/h/l through the common PanelKeyCatcher before the
feature-specific semantic callbacks. The calendar does not maintain a
per-day cursor.

### Life-date editor exception

Double-tapping the life-progress bar starts the editor only when the editor is
not already active. The panel sets editingLife true, populates the birth-year
and expectancy fields, selects the birth field, and focuses it.

While editing:

~~~text
PanelKeyCatcher.blocked = true
field Escape          -> cancelEditingLife(); accept event
field Enter           -> commitLife(); accept event
field Tab/Backtab      -> select and focus the other field
~~~

The first Escape therefore cancels the edit and leaves the calendar panel open.
commitLife parses the birth year and expectancy, persists only changed values,
then cancels edit mode. Closing through any ordinary panel close also cancels
the editor before hiding the controller.

### Clock terminal states

| Trigger | Terminal state |
|---|---|
| Escape while browsing | controller hidden, KeyboardPanel focus None, popout released, card fades |
| Escape in life editor | editor cancelled, panel remains open, focus returns to catcher |
| outside card | same close method as Escape |
| another bar panel | closeForPopoutSwitch path and new owner |
| format cycle | label and inline shell state change; calendar open state is not required |
| timezone middle click | detached/menu command is launched; no calendar open is implied |

## Agent usage panel

### Ownership and visibility

The agent plugin is a direct Panel bar widget. Its manifest declares one
bar-widget entry point, on-demand activation, an AI category, and a
non-multiple instance policy. The visible icon is present only when the usage
service has at least one enabled provider.

The panel root owns:

~~~text
selectedProviderId
cursorActive
nowMs
usage service
~~~

Provider selection follows provider id, not the visual row position. If a scan
adds or removes a provider while the panel is open, the current provider id is
retained when possible.

### Bar trigger branches

The agent bar button dispatches:

~~~text
LeftButton   -> Panel.toggle()
RightButton  -> launchAgent(); close()
MiddleButton -> selectProvider(current index + 1)
~~~

launchAgent calls the bar command omarchy-agent --pick and closes the panel.
The middle action changes provider without opening or closing the panel.

### Open sequence

The inherited Panel.open calls controller.show. When opened changes true, the
agent panel:

1. clears cursorActive;
2. refreshes nowMs;
3. resets the vertical panel flick position;
4. asks the usage service to refresh limits;
5. defers focus to the KeyboardPanel key catcher.

The shared surface passes:

~~~text
contentWidth  = fittedContentWidth(Style.space(380))
contentHeight = fittedContentHeight(column.implicitHeight, Style.space(640))
anchorItem    = agent button
owner         = direct agent panel root
focusTarget   = PanelKeyCatcher
~~~

The explicit IpcHandler at omarchy.agents maps open/show to open, close/hide to
close, toggle to toggle, refresh to refreshNow, and next to provider selection.
The base handler is disabled by the panel's manageIpc false setting.

### Usage refresh and live display

Opening requests a forced limits refresh. The usage service and Main.qml
normalize provider-specific output into the shared provider/window/model
structures. The panel does not require a provider to be present to open; when
the list is empty it renders the no-subscription message and keeps the
navigation surface usable.

The open panel updates nowMs every 30 seconds so reset countdown text does not
become stale. Provider scans, credential/config file reads, sync scans, and
provider-specific retries are owned by Main.qml and its service model; a
failed provider must not destroy data belonging to another provider.

### Keyboard path

The agent key catcher is not blocked in its normal dashboard state:

~~~text
Left/Right or h/l -> select adjacent provider
Up/Down or j/k   -> scroll by Style.space(56) per semantic step
Enter/Space      -> force refresh
r/R              -> force refresh
Tab              -> switch neighboring bar panel
Escape           -> close panel
~~~

The current provider id is the stable selection key. The panel resets vertical
scroll to zero when the provider index changes.

### Agent terminal states

| Trigger | Terminal state |
|---|---|
| Escape | inherited close, KeyboardPanel releases focus/popout, card fades |
| right click | launch picker command and close |
| middle click | provider index changes; panel remains in its prior state |
| refresh key/button | provider data refreshes; panel remains open |
| provider disappears | selection falls back to first available provider or empty state |
| host hide | direct Panel close path; no hidden host open state is left |

## Acceptance checks

1. Exercise clock left/right/middle buttons independently and verify that only
   the source-defined branch runs.
2. Cycle a clock format, restart the host, and verify the shown format matches
   the persisted inline entry.
3. Open the calendar, browse away from the current month, cross midnight in a
   test clock, and verify the source follow-today rule.
4. Enter the life editor, press Escape once, and verify the panel remains open;
   press Escape again and verify panel close.
5. Open the agent panel with zero, one, and multiple providers. Verify the
   empty state, stable provider selection, 30-second now refresh, and focus
   behavior.
6. Trigger the agent right-click launch and confirm that the panel closes after
   dispatch; trigger middle-click provider selection and confirm it does not
   close the panel.

