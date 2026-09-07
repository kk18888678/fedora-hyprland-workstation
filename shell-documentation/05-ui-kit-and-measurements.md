# UI kit and exact measurements

The reusable types are a small design system. Feature plugins should compose
these types instead of recreating rectangles, text, hover state, focus rings,
or keyboard dispatchers locally.

All values below are design pixels before the active spacing/font scale unless
the row says “literal”. `Style.space(n)` is the scaling operation; `spaceReal`
is used where a fractional value is intentionally retained.

## Base contracts

### `BarWidget`

Base `Item` for every bar slot. It exposes:

```text
bar: QtObject|null
moduleName: string (default "")
settings: object (default {})
vertical: read-only from bar.vertical, else false
barSize: read-only from bar.barSize, else Style.bar.sizeHorizontal
setting(name, fallback)
broadcast(method)       # calls method on every live instance on every monitor
```

The bar injects `bar`, the canonical module id, and the inline entry settings.
`broadcast` is required for refresh methods because one layout entry creates one
live instance per monitor.

### `PluginBarApi`

`PluginBarApi` is exported from `qs.Ui` in the full Quattro source even though
it is a non-visual facade rather than a painted control. It is injected into a
widget hosted by a replacement bar and exposes detached bar state plus scoped
tooltip, click-target, popout, panel-switch, module-list, and command-running
operations. Its complete property/method contract and ownership rules are in
[12-full-plugin-lifecycle.md](12-full-plugin-lifecycle.md). It must still be
present in `Ui/qmldir`; omitting it breaks replacement-bar widget loading.

The complete full-anchor `qs.Ui` export list is:

~~~text
module qs.Ui
BarIndicator 1.0 BarIndicator.qml
BarIconButton 1.0 BarIconButton.qml
BarWidget 1.0 BarWidget.qml
BackgroundMedia 1.0 BackgroundMedia.qml
BackgroundVideo 1.0 BackgroundVideo.qml
BorderOverlay 1.0 BorderOverlay.qml
BorderSurface 1.0 BorderSurface.qml
Button 1.0 Button.qml
ButtonGroup 1.0 ButtonGroup.qml
ConfirmDialog 1.0 ConfirmDialog.qml
CursorSurface 1.0 CursorSurface.qml
Dropdown 1.0 Dropdown.qml
KeyboardPanel 1.0 KeyboardPanel.qml
MultiSelect 1.0 MultiSelect.qml
NumberField 1.0 NumberField.qml
OpticalGlyph 1.0 OpticalGlyph.qml
Panel 1.0 Panel.qml
PanelActionButton 1.0 PanelActionButton.qml
PanelController 1.0 PanelController.qml
PanelHero 1.0 PanelHero.qml
PanelKeyCatcher 1.0 PanelKeyCatcher.qml
PanelSectionHeader 1.0 PanelSectionHeader.qml
PanelSeparator 1.0 PanelSeparator.qml
PanelSlider 1.0 PanelSlider.qml
PanelToolTip 1.0 PanelToolTip.qml
PluginBarApi 1.0 PluginBarApi.qml
PointerMoveGate 1.0 PointerMoveGate.qml
ScreenMoveRemap 1.0 ScreenMoveRemap.qml
PopupCard 1.0 PopupCard.qml
SearchableDropdown 1.0 SearchableDropdown.qml
SpeedTestOverlay 1.0 SpeedTestOverlay.qml
TextField 1.0 TextField.qml
Toggle 1.0 Toggle.qml
ToggleSwitch 1.0 ToggleSwitch.qml
WidgetButton 1.0 WidgetButton.qml
~~~

### `WidgetButton`

Generic icon/text bar interaction surface:

| Property | Default |
|---|---:|
| `fontFamily` | bar font or Style family |
| `fontSize` | `Style.font.body` |
| `foreground` | bar foreground or Color foreground |
| `activeColor` | bar urgent or Color urgent |
| `horizontalMargin` | `8.5` |
| `verticalPadding` | `6` |
| `fixedWidth`, `fixedHeight` | `-1` (implicit sizing) |
| `keepSpace`, `dimmed`, `concealed`, `interactive`, `pressable` | `false`, `false`, `false`, `true`, `true` |
| `useActiveColor` | `true` |
| `labelVisible` | `true` |

Implicit sizing is:

```text
horizontal: max(12, labelWidth + 2 × scaledHorizontalMargin), height = barSize
vertical:   width = barSize, max(12, labelHeight + 2 × scaledVerticalPadding)
```

It accepts left/right/middle mouse buttons, enables hover, uses a pointing-hand
cursor when `pressable`, sends `pressed(button)` and `wheelMoved(delta)`, and
owns tooltip show/hide through the bar. Opacity is `0` when there is no visual
content or the item is concealed, `0.45` when dimmed, otherwise `1`. Opacity
transitions are `140 ms`, OutCubic; foreground color transitions are `160 ms`.

### `BarIconButton`

Specializes `WidgetButton` for a 16 px optical canvas:

```text
slotSize    = Style.bar.iconSlot       # 27 px default
opticalSize = Style.bar.iconCanvas     # 16 px default
fontSize    = Style.bar.iconFont       # 13 px default
horizontal fixedWidth = slotSize
vertical   fixedHeight = slotSize
```

It either renders a text glyph through `OpticalGlyph` or a supplied
`iconComponent`, and exposes painted glyph width, baseline, font size, and
horizontal-center error for debugging. `SHELL_DEBUG_BAR_ICONS=1` in the
reference draws a blue optical-bound box and red slot-bound box.

### `BarIndicator`

An icon button with active/inactive text and tooltip pairs. The default layout
is `indicatorBlock = "single"`, `keepSpace = true`, horizontal margin `5`,
vertical padding `5`, font `Style.font.caption`, and a fixed status slot of
`21 px` on the horizontal axis (or vertical axis for a vertical bar).

Inactive indicators are hidden at opacity `0` unless the host reveals them; a
revealed inactive indicator is opacity `0.45`. An active indicator is opacity
`1`. `indicatorBlock` can be `active`, `inactive`, or `single`.

## Surfaces, buttons, and panels

### `BorderSurface` and `BorderOverlay`

`BorderSurface` is a `Rectangle` with a `borderSpec`, independent directional
padding, and computed content insets:

```text
borderTop/Right/Bottom/Left
contentInset = borderSide + matchingPadding
```

Flat uniform borders use the native rectangle border. Gradients or asymmetric
side widths instantiate `BorderOverlay`, which draws a shape ring at `z =
100000` with a winding fill. See the border algorithm in
[04-design-language.md](04-design-language.md).

### `Button`

The only general-purpose button. It contains an icon/text row and a full-size
mouse area. Defaults:

```text
fontFamily = Style.font.family
fontSize = Style.font.body
iconSize = Style.font.icon
horizontalPadding = 10 px
verticalPadding = 6 px
radius = Style.cornerRadius
bordered = false
focusable = false
```

`selected`, `active`, `hasCursor`, `focusable`, and `bordered` are independent
flags. Paint priority is pressed → focus → hot (mouse or cursor) → selected →
active → background. The component reserves the maximum top/right/bottom/left
border any enabled visual state can draw so neighboring layout does not jump
on hover/focus. It accepts Return, Enter, and Space when focusable. Tooltips
use a `400 ms` delay and the tooltip body uses body-small text plus control
padding.

### `ButtonGroup`

A mutually-exclusive-style choice row of `Button`s. `options` can mix strings
and objects with `value`, `label`, `icon`, and `tooltip`; the caller owns the
`value` and the component does not enforce exclusivity itself. Spacing is
`Style.spacing.md` (`6 px`) and the group is one Tab stop. Focus enters at the
selected option; h/l or left/right moves inside the group, Enter/Space emits
`changed(value)`.

### `CursorSurface`

The shared panel row chrome. It never reads `containsMouse` for paint. The
panel root owns `hasCursor` and `current`; the surface paints:

```text
hasCursor -> hover-cursor fill + hover-cursor border
current   -> selected fill + selected border (if enabled)
otherwise -> transparent, or normal border when bordered=true
```

The radius is `Style.cornerRadius`, and color transitions last `60 ms`.

### `Panel`, `PanelController`, `PanelKeyCatcher`

`Panel` is the light lifecycle base for bar-attached popup plugins:

```text
bar, moduleName, settings, ipcTarget, manageIpc=true
opened = controller.open
open(), close(), toggle(), switchPanel(direction)
```

When `manageIpc` is true, it registers `open`, `close`, `show`, `hide`, and
`toggle` on `ipcTarget`. Plugins that need extra methods set it false and own
the one handler themselves. `PanelController` only stores `open: bool` and
provides show/hide/toggle; it has no UI policy.

`PanelKeyCatcher` is a semantic dispatcher with `focus: true` and
`Keys.BeforeItem`. It emits:

```text
Escape -> closeRequested
Tab/Backtab -> tabRequested(-1|+1)
j/k or Down/Up -> moveRequested(0,+/-1)
h/l or Left/Right -> moveRequested(+/-1,0)
Enter/Return -> returnRequested and activateRequested
Space -> activateRequested
x/X -> deleteRequested
other one-character text -> textKey(text)
```

`blocked=true` forwards all keys to descendants, which is required while an
inline `TextField`, dropdown, or nested popup owns input.

### `PanelActionButton`

Right-edge row action button. Its default size is:

```text
size = max(22 px, fontSize + 2 × Style.spacing.sm)
```

The default font is `Style.font.icon` and the default size is therefore 22 px.
It is borderless, has a transparent rest fill, uses foreground on hover, and
can switch to an urgent hover color for forget/unpair/delete actions. It is
not a panel cursor target unless `hasCursor=true`. It can be made a Tab stop
with `focusable=true`.

### `PanelHero`

Two-line title/meta composition with an optional detail pill and trailing
control. Defaults:

```text
iconSize = Style.font.display (24 px)
title = Style.font.title (14 px), bold
meta = Style.font.caption (10 px), bold, letterSpacing 1.2
icon-to-label gap = 14 px
title-to-meta gap = 2 px
detail pill horizontal padding = 10 px total (5 each side)
detail pill vertical padding = 4 px total (2 each side)
trailing-control reserve = control width + 12 px
```

The hero takes its parent's width, vertically centers icon/labels/control,
and elides the title/meta rather than changing the layout.

### `PanelSectionHeader` and `PanelSeparator`

`PanelSectionHeader` is a bold caption-like small-caps label with color
`Qt.darker(foreground, 1.4)`, default font caption, and top padding
`ceil(fontSize × 0.15)` to protect Nerd Font overshoot at a clipping boundary.

`PanelSeparator` is a full-width, literal `1 px` rectangle with height `1` and
default foreground alpha `0.12`; its fallback implicit width is `100 px`.

### `PanelToolTip`

Styled Qt Quick Controls `ToolTip`: delay `400 ms`, zero built-in padding, and
a `BorderSurface` background using the tooltip surface role. Text is
body-small by default; each side adds its border width plus the 10 px/6 px
control padding defaults.

## Inputs and choice controls

### `TextField`

Inherits Qt Quick Controls `TextField`. Default geometry is driven by the
font and padding; vertical padding is `7 px`, horizontal padding `10 px`.
The background uses normal/hover/focus control states, the shared corner
radius, and border-side insets. It supports `password=true`, native validator,
accepted/editingFinished behavior, and text selection tint from the shared
selection token.

### `NumberField`

Column containing an optional body-small label and an editable `SpinBox`:

```text
field width = Style.spacing.numberFieldWidth = 120 px
field height = max(Style.spacing.controlHeight, fontSize + 2 × 6 px)
column spacing = Style.spacing.md = 6 px
```

It emits `modified(int)` and `hovered(bool)` and accepts `from`, `to`, and
`stepSize`.

### `Dropdown`

Single-select control:

```text
width = 240 px
row height = 28 px
label gap = 4 px
popup opens at y = trigger.height + 2 px
popup rows = at most 8
popup padding = 1 px plus border insets
```

Strings or `{value,label}` objects are supported. Tab focuses the trigger;
Enter/Space/Down opens; j/k or Up/Down moves; Enter selects; Escape closes.
The trigger uses the same focus/hover state tokens as every other control.

### `SearchableDropdown`

The same trigger geometry, with a `260 px` default width, a popup minimum
height of `220 px`, and a search header of `popupRowHeight + controlPaddingX`
(`28 + 10 = 38 px` at defaults). A 1 px divider separates search from the
result list. The popup height is bounded by both `6` rows and an extra `50 px`
header allowance. Filtering is case-insensitive substring matching against
label and optional description. Opening clears/focuses the search; Down moves
to the first result; Up from the first result returns to search.

### `MultiSelect`

Searchable multi-select with the same `260 px` trigger width, `220 px` minimum
popup height, `28 px` rows, and a `1 px` divider. Each row has a checkbox:

```text
checkbox = 16 × 16 px
checkbox radius = max(2 px, cornerRadius / 2)
row horizontal padding = 10 px each side
row gap = 8 px
```

Static options or an argv `optionsCommand` are accepted. A command's stdout is
strict JSON-array data when it begins with `[`, otherwise one non-empty value
per line. Dynamic commands time out after `6000 ms`; stale process results are
discarded with a monotonic refresh sequence. Selection changes emit an array
of strings. The popup refresh button is square, equal to the popup row/header
height, and is present only when `optionsCommand` is configured.

### `Toggle` and `ToggleSwitch`

`Toggle` is a full labeled row:

```text
implicit width = 240 px
implicit height = max(54 px, content height + 18 px)
row horizontal padding = 12 px each side
label/description gap = 3 px / Style.spacing.xs
```

It is stateless about the value: the caller changes `checked` after
`clicked()`. `ToggleSwitch` is the bare track:

```text
trackHeight = max(22 px, round(controlHeight × 0.55)) = 22 px default
trackWidth = round(trackHeight × 1.9) = 42 px default
knobSize = max(6 px, round(trackHeight × 0.72)) = 16 px default
knobInset = max(1 px, round((trackHeight - knobSize) / 2)) = 3 px default
cursorPad = 6 px when cursor ring is active
```

Rounded mode is automatic when `cornerRadius > 0`; otherwise the track and
knob are square. `busy=true` swallows clicks without removing hover/tooltips.
The cursor ring is outside the track and follows `interactive`.

### `PanelSlider`

Horizontal value slider:

```text
implicit width = 200 px
implicit height = max(22 px, knobSize + 6 px)
trackHeight = max(4 px, round(controlHeight × 0.11)) = 4 px default
knobSize = max(14 px, round(controlHeight × 0.38)) = 14 px default
step = 0.05
range floor = 0.0001
```

Left drag maps x to the range, wheel moves by `step`, integer mode rounds, and
right click emits `rightClicked()` without starting a drag. The knob scales to
`1.15` on hover/drag. Track/fill/knob motion is `140 ms`; knob scale is
`110 ms`. Tick marks, when `tickCount > 1`, are 2 px wide and track-height plus
4 px tall.

## Composite dialog and utility visuals

### `PopupCard`

Anchored `PopupWindow` with defaults:

```text
margin = Style.gapsOut (5 px fallback)
padding = 14 px
contentWidth = 280 px
contentHeight = 200 px
triggerMode = "click"
```

Click mode uses `HyprlandFocusGrab` over the popup and anchor windows; a click
outside clears the grab and closes. Hover mode is passive. Width/height helpers
subtract bar clearance and twice the margin, enforce a minimum available
dimension of `120 px`, and clamp to the screen. The card opacity animation is
`140 ms`.

### `KeyboardPanel`

Full-screen layer-shell replacement for anchored panels. Defaults are the same
280×200 content size, 14 px padding, and 5 px gap/margin fallback. It uses a
75 ms `Exclusive` focus prime, then `OnDemand`; close-switch fade timers are
150 ms/1 ms. The card is clamped to `Style.gapsOut` from each screen edge.

The full-screen surface remains the input surface; its bar-region handler
forwards clicks to registered bar targets instead of treating them as outside
dismissals. Other screens receive transparent pointer-only twins. The card
remains mapped through a 140 ms fade but logical `open=false` releases
keyboard/pointer ownership immediately.

### `ConfirmDialog`

Full-parent scrim, centered card, two fixed buttons:

```text
card width = min(parent.width - 32 px, 370 px)
card padding = 18 px
button width = 88 px
button height = 34 px
button gap = 10 px
scrim default alpha = 0.70
```

The confirm button is index `1` and is treated as destructive: selected fill
urgent alpha `0.22`, unselected urgent border alpha `0.56`. Escape cancels;
left/right/Tab toggles; Enter confirms the current index. Card and buttons use
square button radii (`0`) while the outer card follows the shared corner.

### `PanelHero`-adjacent icons and helpers

`OpticalGlyph` uses a `TextMetrics.tightBoundingRect` correction and exposes
painted center/baseline metrics; it is the canonical icon-centering path.

`PointerMoveGate` filters delegate churn at a `1 px` movement threshold and
supports an explicit initial sample after a pointer-originated transition.

`ScreenMoveRemap` waits `200 ms` for monitor layout settling, then unmaps for
`50 ms` before remapping long-lived surfaces. This is needed when a monitor's
global origin changes.

### `BackgroundMedia` and `BackgroundVideo`

Still images use asynchronous `PreserveAspectCrop`, cache when version `0`,
and versioned URLs/source sizes to invalidate a changed file. Video uses a
separate Loader for a bare `MediaPlayer` + `VideoOutput`; a video path is one
of `mp4,m4v,mov,webm,mkv,avi`. Video loops infinitely, creates `AudioOutput`
only when audio is enabled and a track exists, and primes a paused first frame
for up to `1000 ms`, pausing `50 ms` after the first frame reaches the output.

### `SpeedTestOverlay`

Fixed near-black scrim alpha `0.78`, two centered dials, no card. Cluster
geometry:

```text
dial diameter = 210 px
arc start = 135°
arc sweep = 270° (90° gap at bottom)
tick count = 46
arc width = 4 px
arc radius = diameter/2 - arcWidth = 101 px
dial-to-dial spacing = 48 px
cluster safety margin = 32 px on each screen dimension
error maximum width = 440 px
```

The track is white alpha `0.14`, minor ticks white alpha `0.12`, major ticks
white alpha `0.30`. Major ticks occur every fifth tick; major tick height is
10 px/width 2 px, minor is 6 px/width 1 px. The value arc has a 3× soft
under-glow; the needle is 3 px wide, extends `32%` of the diameter, and uses
an accent-to-transparent gradient. The ignition animation is 550 ms to full
scale followed by 650 ms to zero. Readings under 10 show one decimal using
the locale; larger readings are rounded/grouped.
