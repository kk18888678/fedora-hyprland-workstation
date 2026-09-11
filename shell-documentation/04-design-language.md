# Design language and visual tokens

This is the visual contract. The shell is intentionally quiet: a small
monospace type system, mostly transparent controls, one accent for selected
state, one urgent color for attention, thin borders, and geometry shared with
the compositor.

## Foundational palette

The color singleton starts with these fallbacks before a theme is available:

| Role | Fallback |
|---|---|
| foreground | `#cacccc` |
| background | `#101315` |
| accent | `#cacccc` |
| urgent | `#a55555` |
| muted | `#707880` |

At startup the shell reads the active theme's `colors.toml`. It recognizes
six-digit hexadecimal assignments and uses this precedence:

- explicit `foreground` and `background` win;
- `color7` supplies foreground only when explicit foreground is absent;
- explicit `accent` wins, otherwise `color4` supplies accent;
- explicit `muted` wins, otherwise `color8`, then foreground;
- `red` and `color1` both assign urgent; if both occur, the last recognized
  assignment in file order wins.

The parser is deliberately small and fail-soft. Unknown or malformed values
leave the previous palette value in place. Theme surface roles are read from a
flat dictionary keyed as `section.key`; a user `shell.toml` dictionary is
merged over the theme dictionary, so machine overrides survive theme swaps.

## Surface palette roles

Every role has a base color plus, where appropriate, a separate `-alpha` key.
The color singleton composes them before controls bind to the result.

| Surface | Roles | Default base/fallback | Default alpha |
|---|---|---|---|
| bar | `background`, `text`, `active` | background, foreground, urgent | `1.0` for background |
| popups | `background`, `text`, `border` | background, foreground, accent | `1.0` |
| tooltip | `background`, `text`, `border` | background, foreground, foreground | `0.97` background, `1.0` border |
| notifications | `background`, `text`, `border`, `countdown` | background, foreground, accent | `1.0` |
| menu | `background`, `text`, `border`, `scrim`, `selected-background`, `selected-text`, `selected-border` | background, foreground, foreground, background, foreground, accent, foreground | `1.0`, `1.0`, `0.5`, `0.08`, `0.0` |
| authentication | `background`, `text`, `text-error`, `border`, `border-error`, `accent`, `scrim` | background, foreground, urgent, accent, urgent, accent, background | `1.0`, `1.0`, `0.5` |
| lock | `background`, `text`, `placeholder`, `text-error`, `border`, `border-active`, `border-error`, `selection` | background, foreground, mixed foreground/background, urgent, foreground, accent, urgent, accent | `0.8`, `1.0`, shared border `1.0`, selection `0.45` |
| image picker | `scrim`, `text`, `selected-border`, `unselected-border` | background, foreground, accent, foreground | `0.5`, `1.0`, `0.28` |

Surface tokens accept palette role names, direct colors, or gradient strings.
An alpha companion is clamped to `[0, 1]`. A base gradient's first stop is
used by color-only consumers.

## Theme file grammar

The runtime's `shell.toml` parser accepts one-level sections and these value
forms:

```toml
[section]
quoted = "text"
number = 12.5
widths = 1 2 3 4
role = foreground
```

Inline `#` comments are tolerated. Values are kept as strings until the reader
coerces them. The built-in template defines `[bar]`, `[hyprland]`, `[controls]`,
`[spacing]`, `[font]`, `[popups]`, `[tooltip]`, `[notifications]`, `[launcher]`,
`[menu]`, `[polkit]`/authentication, `[lock]`, and `[image-picker]`.

Theme changes pass base64-encoded `colors.toml` and `shell.toml` over host IPC.
The shell decodes them, updates Color and Style, and re-polls compositor
geometry after a 200 ms settle period. At startup, the shell reads the active
theme files directly; the user override file is watched live.

## Compositor-derived geometry

`Style.cornerRadius` mirrors the compositor's `decoration:rounding`. The
default is `0`, which means square surfaces and square switches. A value above
zero rounds cards, controls, grid cells, switch tracks, and separators where
the component binds the shared radius.

`Style.gapsOut` is half of the compositor's `general:gaps_out`, rounded to an
integer and clamped at zero. It is the shell-to-screen clearance for popup and
panel cards. The compositor value is queried with:

```text
hyprctl -j getoption decoration:rounding
hyprctl -j getoption general:gaps_out
```

If the query fails, the previous value remains; initial fallbacks are
`cornerRadius = 0` and `gapsOut = 5`.

## Interactive state language

All reusable controls use the same state vocabulary and priority:

```text
pressed > actual focus > hover or panel cursor > selected/current > normal
```

The named state tokens are:

| State | Color token default | Fill alpha | Border width | Border alpha |
|---|---|---:|---:|---:|
| normal | foreground | `0.04` | `1` | `0.40` |
| hover-cursor | foreground | `0.08` | `1` | `0.25` |
| focus | foreground | `0.08` | `1` | `0.25` |
| selected | foreground | `0.18` | `0` | `1.00` |
| pressed | hover-cursor color | `0.22` | n/a | n/a |
| text selection | foreground | `0.35` | n/a | n/a |

State color tokens can be palette roles (`foreground`, `accent`, `urgent`,
`background`, `transparent`) or `#RGB`, `#RRGGBB`, or `#RRGGBBAA`. A focus
token of `hover`, `hover-cursor`, or `inherit` resolves to the hover-cursor
color.

Border width is the on/off switch: setting a state width to zero removes that
state's border. Plain buttons are borderless at rest unless `bordered: true`;
hover-cursor and focus still paint their shared border so a keyboard target is
visible. Selected borders are off by default.

## Spacing scale

`Style.space(px)` rounds a positive design pixel value after applying
`effectiveSpacingScale`. `spaceReal(px)` retains fractions. At the defaults,
`spacingScale = 1.0`, `spacingScaleWithFont = true`, and `fontBaseSize = 12`,
so the token table below is also the default pixel table.

| Token | Base px | Token | Base px |
|---|---:|---|---:|
| `hairline` | 1 | `xxs` | 2 |
| `xs` | 3 | `sm` | 4 |
| `md` | 6 | `lg` | 8 |
| `xl` | 10 | `xxl` | 12 |
| `xxxl` | 14 | `huge` | 18 |
| `controlGap` | 8 | `controlPaddingX` | 10 |
| `controlPaddingY` | 6 | `inputPaddingY` | 7 |
| `controlHeight` | 28 | `popupRowHeight` | 28 |
| `rowGap` | 8 | `rowPaddingX` | 12 |
| `labelGap` | 4 | `panelGap` | 14 |
| `panelPadding` | 18 | `popupPadding` | 14 |
| `dropdownWidth` | 240 | `searchableDropdownWidth` | 260 |
| `numberFieldWidth` | 120 | `searchablePopupMinHeight` | 220 |

The shared spacing scale is multiplicative:
`spacingScale * (fontBaseSize / 12)` when `scale-with-font` is true. A spacing
or font-token override is an absolute pixel value and is not re-scaled; bar
dimension overrides still participate in the bar's `scale-with-font` rule.
Invalid scale values fall back to `1.0`; scale cannot be negative.

## Typography

The default family is the system `monospace` alias. The reference distribution
maps that alias to JetBrains Mono Nerd Font through fontconfig and resolves the
concrete family with `fc-match`. Widgets bind to the alias so a font change is
live; diagnostics may display the resolved family. Summoned menu-like surfaces
may use a startup-time environment override, `SHELL_MENU_FONT` in the
reference.

At `base-size = 12 px`, the type scale is:

| Style token | Multiplier/default | Intended use |
|---|---:|---|
| `caption` | `0.833` → 10 px | metadata, section labels, compact status |
| `bodySmall` | `0.917` → 11 px | secondary text |
| `body` | `1.000` → 12 px | normal labels and controls |
| `subtitle` | `1.083` → 13 px | compact headings |
| `title` | `1.167` → 14 px | row titles and card summaries |
| `heading` | `1.333` → 16 px | menu rows and headings |
| `display` | `2.000` → 24 px | hero icons and larger figures |
| `displayLarge` | `2.333` → 28 px | empty states and large marks |
| `iconSmall` | bodySmall → 11 px | small glyphs |
| `icon` | title → 14 px | normal icons |
| `iconLarge` | `1.500` → 18 px | prominent icons |

Only a 1 px floor is enforced. Per-token theme overrides are otherwise not
clamped, so a theme may intentionally choose a very large display token.

## Bar geometry tokens

These dimensions are independent named tokens and scale with font by default:

| Token | Default |
|---|---:|
| horizontal bar cross-axis size | 26 px |
| vertical bar cross-axis size | 28 px |
| icon slot | 27 px |
| icon canvas | 16 px |
| icon font | 13 px |
| status slot | 21 px |

The horizontal bar uses the 26 px cross-axis surface while most fixed icon
slots are 27 px. A vertical bar uses 28 px width. Text-bearing widgets collapse
or switch to icon-only/stacked forms in vertical orientation; a widget should
not rotate an entire card to make text fit.

## Border system

The border factory produces a spec:

```text
{ color, gradient: { colors[], angle, enabled }, widths: { top, right, bottom, left } }
```

Width strings use CSS-style expansion:

```text
N          -> N N N N
Y X        -> Y X Y X
T X B      -> T X B X
T R B L    -> T R B L
```

Invalid/negative widths become zero. Per-side keys override the base list.
Color parsing accepts `#RGB`, `#RRGGBB`, optional alpha hex, `rgb(......)`
hex/decimal forms, `rgba(...)`, and `0xAARRGGBB`. Role references can chain
through the flattened theme dictionary with cycle protection.

Rendering is optimized by shape:

- flat, uniform, nonzero border → native `Rectangle.border`;
- gradient or asymmetric widths → `BorderOverlay` using `QtQuick.Shapes`;
- all four enabled sides → one compound winding path with a reversed inner
  loop;
- connected subsets of sides → one closed contour per enabled run;
- no sides → no overlay;
- inner radii are reduced by side widths and normalized to fit; if they cannot
  fit, the safe fallback is the outer contour alone.

Gradient endpoints are computed from the center of the surface and the declared
angle. Ten gradient stops are declared in the renderer; extra stops repeat the
last color, missing stops use the last available color.

## Surfaces and layering

There are no drop shadows in the shared kit. Depth is conveyed by:

- a themed card fill over a themed or fixed scrim;
- thin themed borders;
- opacity changes (`0.4–0.7` is common for inactive/secondary content);
- selected/urgent color changes;
- compositor layer ordering (`Background`, `Top`, `Overlay`).

Cards reserve border insets in their content geometry. A border must never cause
neighbors to shift when a state changes; buttons reserve the maximum border
width any state can paint in their implicit size.

## Icon and logo language

Most UI icons are text glyphs from the Nerd Font/icon font, not downloaded SVGs.
Use `Text.NativeRendering` and the shared font family. `OpticalGlyph` measures
`TextMetrics.tightBoundingRect`, applies a horizontal correction to center ink
rather than the advance box, and exposes painted center/baseline diagnostics.
Keep the text line box and baseline fixed; correct horizontal optical drift only.

Source-level branding assets, retained here as exact reference facts, are:

| Asset | Exact source geometry |
|---|---|
| vector wordmark | `logo.svg`, width `1215`, height `285`, viewBox `0 0 1215 285`, black fill |
| terminal wordmark | `logo.txt`, 10 text rows |
| terminal icon | `icon.txt`, 26 rows × 54 characters of block glyphs |

The generic port should preserve those artboard dimensions and block geometry,
while replacing the names/paths with its own namespace if it is not shipping
the reference brand.

Two feature icons are deliberately drawn natively. The five-tile diamond mark
uses a `1.18 × iconSize` box; its Shape layer uses antialiasing, four samples,
and scale `0.95`. Each tile is a diamond with width `50%` of the parent and
height `37.6%`; tile centers are at x `25%`, `75%`, `25%`, `75%`, `50%` and y
`18.8%`, `18.8%`, `56.4%`, `56.4%`, `81.2%`. The network-overlay mark uses a
3×3 dot grid with `dotSize = max(2, iconSize × 0.24)`, inactive dots at opacity
`0.24`, active dots at `1.0`, and an optional warning badge at
`max(7, iconSize × 0.42)`. Its crossed state overlays a `1.22 × iconSize`
line, minimum height `2 px`, height `14%` of the icon, rotated `-45°`; the
warning badge is circular, has a 1 px popup-background border, and uses a
`0.72 × badgeHeight` exclamation glyph.

## Aurelia calendar surface

The calendar uses an Aurelia-specific minimalist language rather than the
reference calendar's oversized hero composition. Its hierarchy is:

1. one compact metadata rule with a short accent segment;
2. a single month-navigation row with fixed-width controls;
3. an unboxed six-row ledger grid with seven equal columns; and
4. one high-contrast accent state for today.

The grid is a read-only date surface, not a date picker. Every cell has the
same explicit width and height, including adjacent-month dates, so the popup
never reflows when a month starts on a different weekday or contains five
weeks. Hover is communicated with a restrained surface and border change;
today is communicated with accent text and a small underline. Popup width,
height, padding, cell size/gap, row heights, and calendar-only colors are
theme.conf tokens, so density and contrast can be customized without editing
the component.

## Motion language

Motion is short, interruptible, and tied to state changes rather than a global
animation loop:

| Motion | Default |
|---|---:|
| tooltip delay | 400 ms |
| normal card/slot opacity | 140 ms, OutCubic |
| control color | 120 ms |
| action button color | 60 ms |
| switch knob/color | 120 ms, OutCubic |
| slider track/knob | 140 ms, OutCubic; knob hover scale 110 ms |
| meter width | 160 ms, OutCubic |
| bar color/foreground theme transition | 420 ms, InOutCubic |
| indicator reveal/collapse | 120 ms |
| status phrase cycle | every 2800 ms; 180 ms fade out + 260 ms fade in |
| background image wipe | 420 ms, InOutCubic |
| video first-frame prime | 50 ms post-frame pause; 1000 ms maximum prime |
| switch/bar reflow settle | 200–300 ms |
| speed dial ignition | 550 ms to full + 650 ms to zero |

Inactive content commonly uses opacity `0.45–0.6`; critical/urgent feedback is
red-tinted and never relies on opacity alone.
