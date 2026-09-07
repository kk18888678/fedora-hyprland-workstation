# Bar-owned panel contract

This document specifies the common end-to-end behavior for bar widgets that
open a detail panel. It is separate from the Weather trace because the
reference uses two different ownership shapes and several button-specific
open paths.

## Two valid ownership shapes

### Direct panel widget

The bar registry loads a component whose root extends the shared Panel. The
same object is mounted in the ModuleSlot, owns its BarIconButton, owns its
KeyboardPanel, and exposes opened/close/open lifecycle through the Panel base.

The reference uses this shape for:

~~~text
omarchy.agents
omarchy.audio
omarchy.bluetooth
omarchy.dropbox
omarchy.monitor
omarchy.network
omarchy.power
omarchy.tailscale
~~~

### Nested panel widget

The bar registry loads a BarWidget root. That root owns the visible button and
an active-but-hidden Loader for Panel.qml. The nested panel gets the real
button as anchorItem and the mounted widget as hostWidget. The root forwards
opened, open, close, and closeForPopoutSwitch to the nested panel.

The reference uses this shape for:

~~~text
omarchy.clock
omarchy.weather
~~~

The nested form is not interchangeable with the direct form. The popout
coordinator compares its owner to the ModuleSlot activeItem. A nested panel
must therefore use the outer widget root as barIdentity.

The media bar widget is a separate exception: it owns a PopupCard-style media
control surface through popupOpen and a shared media service rather than the
KeyboardPanel detail-panel contract. The menu has both menu and bar-widget
kinds and follows the menu-specific route documented in
07-menu-and-overlays.md.

## Reference bar-panel inventory

| Plugin id | Mounted shape | Bar click default | Right click | Middle click | panel surface |
|---|---|---|---|---|---|
| omarchy.agents | direct Panel | inherited Panel open/toggle | panel-defined action branch | panel-defined action branch | KeyboardPanel |
| omarchy.audio | direct Panel | inherited Panel toggle | panel-defined action branch | panel-defined action branch | KeyboardPanel |
| omarchy.bluetooth | direct Panel | inherited Panel toggle | power Bluetooth | inherited toggle | KeyboardPanel |
| omarchy.clock | nested BarWidget | calendar toggle | cycle format | timezone menu command | KeyboardPanel |
| omarchy.dropbox | direct Panel | inherited Panel toggle | panel-defined action branch | panel-defined action branch | KeyboardPanel |
| omarchy.monitor | direct Panel | inherited Panel toggle | panel-defined action branch | panel-defined action branch | KeyboardPanel |
| omarchy.network | direct Panel | inherited Panel toggle | panel-defined action branch | panel-defined action branch | KeyboardPanel |
| omarchy.power | direct Panel | inherited Panel toggle | panel-defined action branch | panel-defined action branch | KeyboardPanel |
| omarchy.tailscale | direct Panel | inherited Panel toggle | panel-defined action branch | panel-defined action branch | KeyboardPanel |
| omarchy.weather | nested BarWidget | detail-panel toggle | notification status command | refresh | KeyboardPanel |

The table identifies the route shape; the feature documents own the exact
right/middle action and device command for each panel. Never infer a missing
branch from another row.

## Direct click-to-open sequence

For a direct Panel widget:

~~~text
bar ModuleSlot
    -> resolve click target or activeItem
    -> target.triggerPress(button)
    -> panel Button.onPressed(button)
    -> Panel.toggle()
    -> Panel.open() when closed
    -> PanelController.show()
    -> Panel.opened becomes true
    -> KeyboardPanel.open becomes true
~~~

The base Panel.open method calls controller.show. A panel may override open or
close to refresh data, clear state, or start/stop a helper; those overrides are
part of the feature's source contract.

Most direct panel files set manageIpc false and create one explicit IpcHandler
because they need panel-specific methods. The base Panel automatic handler is
disabled in that case to prevent duplicate IPC targets. The explicit handler
must map open/show to open, close/hide to close, toggle to toggle, and preserve
any feature-specific methods.

## Nested click-to-open sequence

For a nested widget:

~~~text
bar ModuleSlot
    -> Weather or Clock BarWidget button target
    -> target.triggerPress(LeftButton)
    -> widget.onPressed(LeftButton)
    -> widget.togglePanel()
    -> nested Panel.toggle()
    -> nested Panel.open() or openFromHotkey(), as defined by that panel
    -> PanelController.show()
    -> nested Panel.opened becomes true
    -> KeyboardPanel.open becomes true
~~~

The source difference is material:

| Widget | Closed click calls |
|---|---|
| clock | nested Panel.toggle, whose closed branch calls Panel.open |
| weather | nested Panel.toggle, whose closed branch calls Weather.openFromHotkey |

Weather therefore sets openedFromHotkey before the controller is shown; clock
refreshes and then uses the normal open path. Both eventually request shared
popout ownership, but the feature-specific reveal state is not interchangeable.

## Open-state and host summon sequence

The shell classifies a manifest as bar-widget-only when it has kind bar-widget
and none of panel, overlay, or menu. Agents, audio, Bluetooth, clock, Dropbox,
monitor, network, power, Tailscale, and Weather use this bar route.

For a host summon:

~~~text
shell.summon(id, payload)
    -> resolve enabled id
    -> reject unknown or disabled id
    -> classify bar-widget-only
    -> bar.summonBarWidget(id)
    -> choose live widget copy using focused monitor
    -> item.open()
    -> feature-specific open path
~~~

The bar chooses a live instance by plugin id and focused screen. The payload is
dropped on this bar-widget route. A direct bar panel's item.open normally calls
the inherited open method; Weather's outer BarWidget.open explicitly calls
openFromHotkey. The host toggle calls isBarWidgetOpen first and then hide or
summon.

Host hide follows:

~~~text
shell.hide(id)
    -> resolve enabled id
    -> bar.hideBarWidget(id)
    -> choose the same focused-screen live widget
    -> item.close()
    -> feature cleanup
    -> opened false
~~~

If no live widget exists, the route returns failure and logs the missing
widget. It does not create an invisible open state.

## KeyboardPanel contract

Every bar-owned panel that uses this contract passes:

~~~text
anchorItem  = visible bar button
owner       = mounted widget root or direct panel root
bar         = live bar or scoped facade as permitted
open        = feature opened state
focusTarget = feature PanelKeyCatcher
centerOnBar = true for the reference bar panels
~~~

The shared window is a full-screen layer-shell Overlay PanelWindow on the
anchor screen. Its visible card is positioned inside the window. It uses:

~~~text
exclusionMode = Ignore
open false -> keyboard focus None
open true and focusPrimed false -> keyboard focus Exclusive
open true and focusPrimed true -> keyboard focus OnDemand
focus prime interval = 75 ms
card opacity close animation = 140 ms, OutCubic
~~~

The card is not the input window. The full-screen window receives outside
input, the card swallows inside clicks, and the bar region forwards clicks to
registered bar targets after the focus prime. Other screens get transparent
no-focus dismissal twins.

## Keyboard command sequence

PanelKeyCatcher is the standard dispatcher. It has focus true and
Keys.priority Keys.BeforeItem. Unless blocked:

~~~text
Escape       -> closeRequested
Tab/Backtab  -> tabRequested(-1 or +1)
Down/j       -> moveRequested(0, +1)
Up/k         -> moveRequested(0, -1)
Right/l      -> moveRequested(+1, 0)
Left/h       -> moveRequested(-1, 0)
Return/Enter -> returnRequested then activateRequested
Space        -> activateRequested
x/X          -> deleteRequested
other text   -> textKey
~~~

The feature decides what each semantic signal means. An inline editor must set
blocked true while it owns keyboard input, and its own TextField/choice control
must implement the editor-specific Escape or commit behavior. Weather's
location editor is the canonical two-stage Escape example.

## Escape close sequence

For a normal direct or nested panel:

~~~text
focused PanelKeyCatcher
    -> Keys.BeforeItem sees Escape
    -> closeRequested
    -> feature close()
    -> feature cleanup / controller.hide()
    -> opened false
    -> KeyboardPanel.open false
    -> focus-prime timer stopped
    -> keyboard focus None
    -> bar.releasePopout(owner)
    -> dismissal surfaces disabled
    -> card opacity fades to zero over 140 ms
    -> window visibility false
~~~

The feature close method may do more before controller.hide:

| Feature state | Required close behavior |
|---|---|
| inline editor | cancel the editor before hiding |
| discovery session | settle or transfer only the discovery stop debt owned by that instance |
| child process | mark expected stop, stop timers, then stop the child |
| password/credential field | clear in-memory secret if the source does so |
| host open map | call shell.hide when user close must repair generic host state |
| bar-owned panel | release the bar popout through KeyboardPanel |

## Popout handoff sequence

When a second bar panel opens:

1. New KeyboardPanel.open becomes true.
2. It records whether another activePopout exists.
3. Bar.requestPopout calls the previous owner's closeForPopoutSwitch when
   exposed, otherwise close.
4. The previous panel clears its logical open state and releases only if it
   still owns the coordinator.
5. The new owner becomes activePopout.
6. The old card may fade while the new card opens; popoutSwitching controls
   the handoff animation and a 150 ms switch timer.

The source uses the mounted widget root as owner for nested panels and the
direct Panel root for direct panels. Comparing the nested Panel object to the
slot activeItem is a source-level identity error.

## Bar-strip click while a panel is open

The panel's full-screen dismissal handler does not always close on a bar-strip
click. After focusPrimed is true it:

1. checks whether the pointer lies in the bar strip;
2. maps the point into the bar window;
3. scans registered click targets belonging to the anchor window;
4. calls target.triggerPress(button) when a target is found;
5. otherwise closes the current panel.

While the panel is still in the brief Exclusive prime, it does not interpret a
translated click from another output as a bar click. This guard prevents an
incorrect handoff.

## Feature-specific implementation rule

The shared contract is only the shell of the flow. The feature-specific file
must state:

~~~text
which source state makes the widget visible
which button branch opens it
whether open or openFromHotkey is used
what refresh/process starts on open
what the cursor selects first
which controls are blocked from PanelKeyCatcher
what Escape does in every editor/filter/modal state
what outside click does
what host hide does
what process/file/timer cleanup runs on close
what state survives the next open
~~~

If any row is left as “same as the generic panel” without checking the source
override, the implementation is not 1:1.

## Acceptance checks

1. Exercise one direct Panel widget and one nested BarWidget widget through
   bar click, host summon, host hide, and host toggle.
2. Verify the live focused-monitor copy is selected and no other monitor copy
   becomes the active owner.
3. Verify the 75 ms focus prime, the OnDemand transition, and immediate focus
   release before the 140 ms fade ends.
4. Open a second panel during the first panel's fade and verify
   closeForPopoutSwitch and activePopout identity.
5. Click the first panel's card, outside area, bar strip, and another monitor;
   verify swallow, close, handoff, and transparent-twin behavior.
6. For each feature, run its editor/filter branch and press Escape at every
   state. Do not accept a generic “Escape closes” result unless source confirms
   it.

