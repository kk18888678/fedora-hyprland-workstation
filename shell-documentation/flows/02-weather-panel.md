# Weather detail-panel flow

This is the complete source-traced scenario for the reference weather widget:

~~~
left click the weather item
    -> weather detail card opens
    -> card owns the keyboard
press Escape
    -> weather panel closes
    -> keyboard and popout ownership are released
    -> card fades away
~~~

The implementation vocabulary is generic. The exact reference plugin id is
omarchy.weather and the checked files are:

~~~
shell/plugins/panels/weather/manifest.json
shell/plugins/panels/weather/BarWidget.qml
shell/plugins/panels/weather/Panel.qml
shell/plugins/panels/weather/Model.js
shell/Ui/BarWidget.qml
shell/Ui/BarIconButton.qml
shell/Ui/WidgetButton.qml
shell/Ui/Panel.qml
shell/Ui/KeyboardPanel.qml
shell/Ui/PanelKeyCatcher.qml
shell/plugins/bar/Bar.qml
shell/shell.qml
~~~

They were read from the full quattro source at commit
e989b5b3ee1ee1babb2614655649341f80b7b323.

## Important terminology

The apparent popup is not an ordinary Qt Popup, PopupWindow, or xdg-popup. It
is a full-screen Wayland layer-shell PanelWindow with a visible card placed
inside it. Reproducing only the card and attaching it as a normal desktop
popup changes keyboard focus, bar handoff, multi-monitor dismissal, and close
timing.

## Preconditions

The left-click path exists only when all of these source conditions hold:

| Condition | Exact behavior |
|---|---|
| Manifest | The plugin declares kind bar-widget and entryPoints.barWidget points to BarWidget.qml. |
| Configuration | Its id occurs in a live bar layout section. |
| Widget loaded | The bar registry has resolved the component and the slot has loaded it. |
| Label | The widget root is visible only when the nested panel label is not empty. The slot has zero effective extent while the label is empty. |
| Injection | The host has injected bar and settings; the widget has injected the nested panel's bar, settings, anchor button, and host widget. |
| Pointer | The click is a left-button click that does not cross the bar's Style.space(4) Manhattan drag threshold. |
| Target | The registered button target is visible, interactive, pressable, not concealed, and exposes triggerPress(). |

The widget's nested panel Loader is active even though the Loader itself is
visually hidden. Weather refresh can therefore run before the bar label has
become non-empty. Network success is not required to begin the panel open
transition after the widget is visible.

## Construction and ownership

The bar creates the Weather BarWidget in a ModuleSlot. Its root has:

~~~
moduleName = omarchy.weather
~~~

The root creates a nested Panel.qml Loader with active true and visible false.
After load it injects:

~~~
panel.bar        = widget.bar
panel.settings   = widget.settings
panel.anchorItem = button
panel.hostWidget = widget root
~~~

The nested panel computes:

~~~
barIdentity = hostWidget || panel
~~~

Because the panel is nested inside the item mounted in the bar slot,
barIdentity is the BarWidget root. The bar's active popout reference, panel
open indicator, and panel-navigation lookup must all use this same identity.

The visible button is a BarIconButton:

~~~
anchors.fill  = widget root
text          = panel.label, or empty before a usable result
slotSize      = Style.bar.statusSlot
tooltipText   = empty string
~~~

BarIconButton inherits WidgetButton. WidgetButton's local MouseArea accepts
left, right, and middle buttons. Its triggerPress(button) first hides the
widget tooltip and emits pressed(button). The bar slot also has a host-owned
left-click path that resolves the registered target and calls the same
triggerPress method. These paths are deliberately convergent.

## Left-click trace

### A. Hit testing and drag discrimination

The live ModuleSlot owns a left-button MouseArea enabled only while the slot is
visible and has positive width and height. On press it records the pointer
position and clears any prior drag state.

On movement it computes:

~~~
distance = abs(mouse.x - pressedX) + abs(mouse.y - pressedY)
threshold = Style.space(4)
~~~

At or beyond the threshold, the slot enters bar-reorder mode, captures its
drag ghost, updates the drop target, hides the tooltip, and suppresses the
later click. A release below the threshold remains a click.

### B. Target resolution

For a click, the bar scans click targets in reverse registration order. A
target is eligible only if:

~~~
target exists
target.visible is not false
target.opacity is not zero
target.interactive is not false
target.pressable is not false
target.concealed is not true
target.triggerPress is a function
~~~

The bar maps the slot-local pointer coordinate into each target and requires
the mapped point to lie inside that target's width and height. If none matches,
the slot's active item is tried with the same target contract.

The effective ordinary left-click chain is:

~~~
ModuleSlot.modulePointer.onClicked(mouse)
    -> Bar.pressModuleClickTarget(slot, LeftButton, x, y)
    -> BarIconButton.triggerPress(LeftButton)
    -> WidgetButton.pressed(LeftButton)
    -> Weather BarWidget.onPressed(LeftButton)
~~~

If the reusable button's own MouseArea receives the event directly, its
onClicked handler also calls triggerPress(mouse.button); it reaches the same
Weather onPressed signal and must not be replaced by a second action.

### C. Button branch

The Weather button dispatches exactly:

~~~
RightButton  -> bar.run("omarchy-notification-send $(omarchy-weather-status)")
MiddleButton -> widget.refresh()
otherwise    -> widget.togglePanel()
~~~

The left-click trace therefore calls togglePanel. The widget forwards to the
nested panel's toggle method.

### D. Closed-to-open branch

The nested panel derives opened from the shared PanelController.open property.
When closed, toggle calls openFromHotkey. The source does not call the normal
open method for this click.

openFromHotkey performs, in order:

1. Set openedFromHotkey to true.
2. Call controller.show().
3. Reload the weather location FileView.
4. Call refresh().
5. Schedule a deferred callback that enables center hover-reveal suppression
   only if the panel remains open.

controller.show changes opened to true. KeyboardPanel.open is bound to that
state, so the panel surface starts opening from the same logical transition.

The deferred reveal flag is set after show because show requests popout
ownership and can close the previously active panel. Setting it after the
handoff prevents the previous panel's close from clearing the new panel's
flag.

## Weather data side of the open transition

Opening the card and obtaining weather data are separate phases.

The reference location state is watched at:

~~~
HOME/.local/state/omarchy/settings/weather.json
~~~

The generic port must preserve the equivalent state location and file schema:
name, latitude, and longitude. A missing or invalid file yields an empty
location state.

refresh resets both retry counters, starts the main forecast process if it is
not running, starts the location probe when coordinates are not configured,
and starts the daily forecast path when coordinates or a resolved area are
available.

The source-defined external requests are:

| Work | Command/request | Timeout and result rule |
|---|---|---|
| auto location | curl -fsS --max-time 4 against wttr.in with format %l | non-empty output supplies the provisional location |
| current/full forecast | curl -fsS --max-time 10 against wttr.in with format j1 | parsed JSON replaces report; empty/invalid output schedules retry |
| daily/current coordinates | curl -fsS --max-time 5 against Open-Meteo | parsed JSON replaces daily report and updates the bar label |
| retry | same process after a 2500 ms timer | each forecast family retries at most three times per refresh cycle |

Last-good reports are retained on parsing failure. If no current report exists,
the detail card renders Fetching forecast… instead of refusing to open. A
successful response updates the label, which also controls bar-widget
visibility.

## KeyboardPanel opening

Weather creates KeyboardPanel with:

~~~
anchorItem  = weather button
owner       = weather barIdentity, normally the BarWidget root
bar         = live bar
open        = weather.opened
centerOnBar = true
focusTarget = PanelKeyCatcher
~~~

The window is:

~~~
type             = PanelWindow
layer namespace  = omarchy-keyboard-panel
layer            = Overlay
exclusionMode    = Ignore
screen           = anchor button's screen
anchors          = top, bottom, left, right
color            = transparent
~~~

The window is full-screen. Only the card is painted visibly:

~~~
card.width       = fittedContentWidth(Style.space(480))
card.height      = fittedContentHeight(weatherColumn.implicitHeight)
card.color       = Color.popups.background
card.border      = popup border spec with max(1, Style.space(2)) width
card.padding     = Style.spacing.popupPadding
card.radius      = Style.cornerRadius
~~~

The card's content is inset by border widths plus padding on each side.

## Card sizing and position

KeyboardPanel computes:

~~~
verticalContentInset = padding * 2 + borderTop + borderBottom
desiredWidth         = max(1, requested width)
desiredHeight        = max(verticalContentInset,
                           weatherColumn implicit height + verticalContentInset)
availableWidth       = screen width minus bar clearance and margins
availableHeight      = screen height minus bar clearance and margins
contentWidth         = round(min(desiredWidth, availableWidth))
contentHeight        = round(min(desiredHeight, availableHeight))
~~~

The available dimension is never allowed below 120 before fitting. Weather
does not pass an explicit height cap; its height is the measured weather
column plus the shared insets, constrained by available height.

With centerOnBar true, the un-clamped card origin is:

~~~
top bar:
    x = screenWidth / 2 - contentWidth / 2
    y = barHeight + gap

bottom bar:
    x = screenWidth / 2 - contentWidth / 2
    y = screenHeight - barHeight - contentHeight - gap

left bar:
    x = barWidth + gap
    y = screenHeight / 2 - contentHeight / 2

right bar:
    x = screenWidth - barWidth - contentWidth - gap
    y = screenHeight / 2 - contentHeight / 2
~~~

Then:

~~~
x = max(margin, min(x, screenWidth  - contentWidth  - margin))
y = max(margin, min(y, screenHeight - contentHeight - margin))
return round(x), round(y)
~~~

Both gap and margin default to Style.gapsOut. The anchor still determines the
screen and bar position even when centerOnBar causes the card to be centered
relative to the whole bar.

## Focus and popout sequence

When KeyboardPanel.open changes to true:

1. focusPrimed becomes false.
2. The focus-prime timer starts when the backing window is visible.
3. A Qt.callLater callback asks PanelKeyCatcher to forceActiveFocus while open.
4. KeyboardPanel asks the bar to own the popout for coordinatorKey.
5. If another owner existed, the bar calls its closeForPopoutSwitch when
   available, otherwise close.
6. activePopout becomes the Weather bar-widget root.

While open, keyboard focus is:

~~~
focusPrimed false -> WlrKeyboardFocus.Exclusive
focusPrimed true  -> WlrKeyboardFocus.OnDemand
closed             -> WlrKeyboardFocus.None
~~~

The prime timer is exactly 75 ms. Once it fires and the panel is still open,
focusPrimed becomes true. Exclusive reliably acquires focus on map/reopen;
OnDemand prevents the surface from capturing pointer events across all
outputs.

The panel's visible binding is:

~~~
open || card.opacity > 0 || popoutSwitching
~~~

This binding is why close cannot immediately destroy the visual surface.

## Escape-to-close sequence

The following is the normal path when the location editor is not active.

### A. Escape dispatch

KeyboardPanel focuses PanelKeyCatcher. The catcher has focus true and
Keys.priority Keys.BeforeItem. Its first guard is:

~~~
if blocked:
    return without emitting or accepting a panel command
~~~

Weather sets:

~~~
PanelKeyCatcher.blocked = editingLocation
~~~

In the normal state blocked is false. The catcher's first key branch is:

~~~
if event.key == Qt.Key_Escape:
    emit closeRequested()
    event.accepted = true
    return
~~~

Weather connects onCloseRequested directly to root.close().

### B. Weather logical close

Weather close performs exactly:

1. Clear center hover-reveal suppression.
2. If editingLocation is true, call cancelEditingLocation().
3. Call controller.hide().

controller.hide makes opened false. KeyboardPanel.open therefore becomes
false from the same state transition.

### C. Immediate ownership release

KeyboardPanel.onOpenChanged false:

| State | Result |
|---|---|
| focus-prime timer | stopped |
| focusPrimed | reset false |
| layer-shell keyboard focus | WlrKeyboardFocus.None |
| bar ownership | releasePopout(coordinatorKey), if this surface owns it |
| outside dismissal | disabled because it is enabled only while open |
| other-monitor twins | invisible because they are bound to open |

The surface remains visible while card.opacity is greater than zero. The card
animates from opacity 1 to 0 for 140 ms with OutCubic. During this fade it
must not own focus or swallow input. After the opacity reaches zero, the
full-screen PanelWindow becomes invisible.

### D. User-visible terminal state

The weather card is gone. The bar widget remains mounted with its last valid
label/report state. The same nested panel is available for the next open; no
second shell process is launched by this interaction.

## Location-editor Escape exception

The first Escape has a different terminal state when the location editor has
focus.

Starting the editor sets editingLocation true and schedules focus on the
location TextField. Because Weather binds PanelKeyCatcher.blocked to that
state, the parent key catcher returns without handling Escape. The TextField's
own key handler handles Qt.Key_Escape:

~~~
TextField Escape
    -> cancelEditingLocation()
    -> accept event
    -> editingLocation false
    -> clear suggestions and debounce
    -> schedule focus back to PanelKeyCatcher
    -> panel remains open
~~~

The second Escape, now delivered to the unblocked PanelKeyCatcher, follows the
normal close sequence.

Closing the panel while editing is also safe: Weather.close explicitly calls
cancelEditingLocation before hiding the controller.

## Other end-to-end exits for the same surface

### Outside-card click

KeyboardPanel's full-screen dismissal MouseArea is enabled only while open.
The card owns a swallowing MouseArea, so a click inside the card is not
interpreted as outside dismissal. A click outside the card calls root.close().

On each other screen, a transparent overlay twin is created while open. It has
keyboard focus None and its MouseArea calls root.close on press. This is how a
click on another monitor dismisses the panel.

### Bar-strip click and panel handoff

After the focus prime, a click in the bar strip is resolved against registered
bar targets and forwarded through triggerPress. It is not automatically
dismissed. If another panel opens, Bar.requestPopout first closes Weather via
closeForPopoutSwitch and then assigns the new owner.

### Host summon/hide/toggle

The host classifies Weather as a bar-widget-only plugin. summon, hide, and
toggle therefore use the live bar's summonBarWidget, hideBarWidget, and
isBarWidgetOpen methods rather than the generic panel loader map. BarWidget.open
calls Panel.openFromHotkey, so a host summon uses the same focus/reveal path.
Payload JSON is discarded on this bar-widget route.

The nested panel owns an explicit IpcHandler at target omarchy.weather and sets
manageIpc false so the base Panel does not add another handler. Its methods
are:

~~~
open/show -> openFromHotkey()
close/hide -> close()
toggle    -> toggle()
edit      -> openFromHotkey(); startEditingLocation()
~~~

## Source-derived acceptance checks

These are required tests for a faithful implementation:

1. With Weather visible, left-click below the drag threshold and verify one
   button action, opened true, and the nested panel using openFromHotkey.
2. Verify the visible result is a card inside a full-screen Overlay
   PanelWindow on the anchor screen.
3. Verify the width is the fitted Style.space(480) request and the height is
   the measured content plus shared border/padding insets.
4. Verify the 75 ms Exclusive-to-OnDemand focus transition and deferred focus
   on the key catcher.
5. Verify activePopout is the mounted Weather BarWidget root.
6. Press Escape in the normal state and verify opened false, focus None,
   activePopout released, dismissal areas disabled, and the 140 ms fade.
7. Start location editing, press Escape once, and verify the panel stays open;
   press Escape again and verify normal close.
8. Click inside the card, outside it, on another monitor, and on another bar
   widget while open; verify swallow, close, twin close, and handoff paths.
9. Repeat while forecast requests return empty/invalid data and verify the card
   still opens, shows the loading state or last-good data, retries as defined,
   and leaves no focus/popout ownership after Escape.

