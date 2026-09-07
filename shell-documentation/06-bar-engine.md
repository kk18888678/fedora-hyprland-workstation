# Bar engine and widget layout

## Surface topology

The active bar implementation is loaded once by the shell host, but it creates
one `PanelWindow` per `Quickshell.screens` entry. Every layout entry therefore
has one live widget instance per monitor. Shared data/services remain singletons
or injected objects; visual surfaces are per-output.

Each bar window is a Wayland layer-shell surface:

```text
layer       = Top
namespace   = <bar namespace>
keyboard    = none
exclusion   = Auto unless hidden
```

Position geometry:

| Position | Anchors | Cross-axis size | Outer module placement |
|---|---|---:|---|
| top | top/left/right | 26 px height | left/right groups 8 px from edges; center centered |
| bottom | bottom/left/right | 26 px height | same; popups open upward |
| left | top/bottom/left | 28 px width | top group 8 px from top; bottom group 8 px from bottom; center vertical |
| right | top/bottom/right | 28 px width | same; popups open leftward |

When the bar is hidden, the window remains mapped and its cross-axis margin is
negative one bar size. Exclusion becomes `Ignore`. This preserves the scene
graph/textures and makes showing the bar a margin change rather than a full
surface rebuild. `ScreenMoveRemap` still pulses visibility when a monitor's
global origin changes.

## Three-section layout

The bar consumes normalized arrays:

```text
bar.layout.left
bar.layout.center
bar.layout.right
```

Horizontal sections are `Row`s; vertical sections are `Column`s. Each module
slot's implicit cross-axis size follows the active item. Center is special:

```text
centerAnchor absent
  -> one centered module list

centerAnchor present
  -> list before anchor, anchored to anchor's leading edge
  -> anchor widget exactly centered in the bar window
  -> list after anchor, anchored to anchor's trailing edge
```

Only the visible anchored/unanchored arrangement is loaded. Keeping both
arrangements alive would create duplicate timers and IPC handlers.

The tray is normalized to the inner edge of its section after generic layout
normalization: first in the right section, last in left/center. This is a
behavioral rule, not a cosmetic sort.

## Module resolution order

For each `ModuleSlot`:

1. Normalize the entry id and copy all fields other than `id` as settings.
2. If a registry component exists for the id, load it from the
   `BarWidgetRegistry` component.
3. Else, if `type: "qml"`, load the custom QML source.
4. Else, if `type: "command"` or an `exec` field exists, load the command
   module wrapper.
5. Else, use a zero-sized invisible component.

The active item receives these properties when it declares them:

```text
bar          -> active Bar object
moduleName   -> canonical layout id
settings     -> entry fields excluding id
```

Registry and custom Loaders call injection both on `onLoaded` and one deferred
Qt turn later. This covers bindings that are not ready during initial Loader
construction.

## Custom command modules

An arbitrary bar entry can be command-driven:

```json
{
  "id": "vpn",
  "type": "command",
  "exec": "~/.config/<namespace>/bar/scripts/vpn-status",
  "interval": 5,
  "tooltip": "VPN",
  "onClick": "open-vpn",
  "onRightClick": "disconnect-vpn",
  "onMiddleClick": "cycle-vpn"
}
```

The wrapper executes `bash -lc` on a repeating timer (default interval `5 s`,
minimum `1 s`, triggered immediately). It parses the last output line as
Waybar-style JSON:

```json
{"text":"…","tooltip":"…","class":"active"}
```

Non-JSON output becomes `{text: raw}`. `class` or `alt` equal to `"active"`,
or an array containing `active`, selects the active color. Default
command-module geometry
uses `horizontalMargin = 7.5`, `verticalPadding = 6`, and `fontSize = 12`.
`keepSpace: true` keeps a zero-output module's slot; otherwise it collapses.

Custom QML entries use `type: "qml"` and load:

```text
source explicit -> expanded ~ or $HOME path
source absent  -> <user-config>/<namespace>/bar/modules/<id>.qml
```

The reference safe-name test rejects a generated module name containing `..`
or beginning with `/`. A custom QML item should provide `implicitWidth` and
`implicitHeight`, and may consume `bar`, `moduleName`, and `settings`. It may
call `bar.run(command)`, `bar.showTooltip(target,text)`,
`bar.hideTooltip(target)`, `bar.requestPopout(owner)`, and
`bar.releasePopout(owner)`.

## Widget contract

First-party and third-party widgets share the same base contract. The bar
exposes:

```text
foreground / barForeground
background
urgent
fontFamily
position: top|bottom|left|right
vertical: bool
barSize: 26|28 by default
run(command): detached command
showTooltip / hideTooltip
requestPopout / releasePopout
moduleWidgets(id): all per-monitor live instances
```

The widget chooses whether to be text, icon, hidden, or a composite
bar-button. Text modules must have a deliberate vertical form. The source
examples include stacked clock glyphs, icon-only media, and fixed-slot status
icons rather than rotating long text into a side bar.

## Panel indicators

Each bar widget that exposes `open()`, `close()`, and `opened` can own an
anchored keyboard panel. The slot displays a small accent open mark when its
panel owner is the active popout:

```text
extent hint = openPanelIndicatorWidth/Height when supplied
otherwise   = max(10 px, round(55% of slot's along-bar size))
thickness   = 2 px
inset       = 2 px from the inner desktop-facing edge
opacity     = 0.9 while open, 0 while closed/dragging
```

The clock supplies a text-width extent horizontally and a `55%` icon-slot
extent vertically. The power widget supplies its painted glyph width when a
percentage label is visible.

## Popout coordination

The bar stores one `activePopout` identity. A new panel:

1. closes the previous owner through `closeForPopoutSwitch` when available;
2. otherwise calls `close`;
3. sets itself as the active owner.

This prevents overlapping cards and makes clicking a second bar icon transfer
the popout. A panel's logical `open` state—not its fading `visible` state—owns
the transfer, so focus and keyboard ownership do not remain stuck during the
140 ms fade.

## Tooltip system

Widgets do not create independent bar tooltips. They register click targets and
ask the bar to show a shared tooltip:

```text
hover target
  -> clear prior request
  -> verify target is visible, interactive, and tooltip-hovered
  -> defer one Qt turn
  -> wait 400 ms
  -> display one tooltip bubble
```

The bar polls the target every `100 ms` while shown. A tooltip bubble has
implicit width `label width + 20 px`, height `label height + 14 px`, themed
background/border, and a `6 px` gap from the target. It follows the bar edge
and clamps through the popup anchor.

## Drag reorder

Dragging is implemented in the bar, not in the widget. The module pointer:

- accepts left button;
- waits for a Manhattan movement of `Style.space(4)` (`4 px`) before entering
  drag mode;
- captures the widget into a visual ghost;
- never assigns `drag.target` because positioners own the slot coordinates;
- computes a nearest insertion edge among visible modules on the same output;
- writes the move through the shell configuration mutator on release.

The ghost is an overlay with an empty input `Region`, a 1 px padding, a themed
surface, a 1 px foreground border, and an accent circular drop marker. Empty
space around a centered group is a dead zone; the pointer must resolve against
another visible widget. Releasing with no target leaves the config unchanged.

The pure placement helper compares pointer distance to each candidate's start
and end along the bar axis and chooses the closest edge. Same-section moves
adjust the target index after removal so the moved item does not shift by one.

## Move the bar to another edge

The empty center gesture area accepts left-button press-and-hold
(`pressAndHoldInterval = 200 ms`) or movement beyond the same 4 px threshold.
The cursor position is normalized to screen width/height and the nearest
diagonal triangle selects `top`, `bottom`, `left`, or `right`. The candidate
edge is previewed by four fixed slabs; only opacity crossfades (`140 ms`) so a
single resized slab never flickers mid-transition.

Release commits only if the candidate differs from the current position. A
drag suppresses the subsequent click. Double-left-click on empty center space
toggles transparency instead of moving the bar.

## Transparency

Transparency is persisted in `bar.transparent`. When requested, the bar waits
`120 ms` and invokes the distribution's text-color sampler with:

```text
position, barSize, themed foreground RGB, contrast/background RGB
```

The first valid `#RRGGBB` line becomes `transparentForeground`; the bar then
uses a transparent background and the sampled foreground. Theme/background
changes re-trigger the sampler. While sampling, foreground animation is
disabled; after the sample, the source schedules two deferred Qt turns before
restoring color animation. Disabling transparency resets to the themed
foreground and restores animation through the same deferred path.

## Multi-monitor panel routing

Because the bar has one slot per output, every panel action resolves candidates
with these priorities:

```text
1. an already-open copy (so hide/toggle reaches the visible card)
2. the copy on Hyprland's focused monitor
3. a drawn slot rather than a zero-size center-anchor placeholder
```

If a panel is summoned by a hotkey while no focused monitor is available, the
first drawn candidate is used. `togglePanelAt(section,index)` counts only
visible widgets that expose panel lifecycle methods and uses one-based indexes.

## Built-in widget catalog

The source ships these families; a generic 1:1 port should preserve the
interaction grammar even if the labels are renamed:

| Widget role | Default behavior |
|---|---|
| menu launcher | left opens menu, right opens terminal |
| workspace switcher | left focuses workspace; occupied/focused states affect opacity |
| clock/calendar | left opens calendar, right cycles persisted format, middle opens timezone picker |
| media | left play/pause, middle next, wheel previous/next, right opens cover popup |
| indicator group | active/inactive state icons with hover reveal |
| update indicator | periodic update check; left launches update flow |
| system tray | hover reveals inward drawer; right action manages tray |
| weather | left opens forecast, right posts a notification, middle refreshes |
| microphone | left mute, middle audio panel, wheel volume |
| audio | left/middle panel, right mute, wheel output volume |
| network | left network panel |
| VPN/tunnel | left panel, right toggle, middle refresh |
| agents/usage | left dashboard, right agent launcher, middle subscription cycle |
| power | left panel, right percentage toggle |
| Bluetooth | left panel, right radio toggle |
| display | left panel |

The exact feature implementations and external commands are catalogued in
[07-feature-catalog.md](07-feature-catalog.md).
