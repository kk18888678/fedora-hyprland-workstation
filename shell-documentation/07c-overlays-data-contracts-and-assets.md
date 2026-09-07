# Overlays, data contracts, and assets

## Clipboard history overlay

The clipboard capability is a kept overlay. It captures text and selected image
MIME types from the Wayland clipboard and stores normalized entries:

```json
{"type":"text","text":"..."}
{"type":"image","mime":"image/png","path":"/…/hash.png","capturedAt":"Monday 14:03"}
```

### State and capture

```text
STATE/clipboard-history.json
STATE/clipboard-images/<sha256>.<extension>
history retention       500 entries
display result limit    50 rows
large text scan/render   8192 characters, cut at a newline when possible
```

The watcher is started with `setpriv --pdeathsig TERM` so it dies with the
shell. A startup process kills old watchers matching this plugin's capture
script, then starts one text watcher and one PNG watcher. The capture script
skips sensitive clipboard hints, hashes image bytes with SHA-256 for de-dupe,
uses `mktemp` in the image directory, and emits one JSON line. It includes
defensive UTF-16/UTF-8 decoding for text.

Text entries containing `file://` URIs become file rows; a single image path
gets a preview, multiple paths get a count. Image/file rows use the existing
paste/open helper commands; plain text uses a history-indexed paste helper.
The full entry is preserved for paste even when display text is capped.

### Geometry and interaction

```text
card maximum width       875 px
card maximum height      600 px
content margin           18 px
header height            max(34 px, title + 2×controlPaddingY)
row height               max(50 px, body + caption + 2×rowPaddingX)
list gap                 4 px
row side inset           12 px
row top/bottom inset     8 px
preview/list split       50% / 50%
preview image/text gap   10 px
```

The overlay is a full-screen exclusive surface with menu palette/scrim. The
left list and right preview remain mounted. Keyboard behavior is filter typing,
Backspace/Ctrl-Backspace/Ctrl-U, Up/Down, PageUp/PageDown six rows, Home/End,
Enter to paste, Shift+Enter to copy, Alt+Enter to open, Delete to remove, and
Shift+Delete to open the clear-history confirmation. A confirmation uses the
shared 370 px maximum card and 88×34 px buttons.

## Emoji picker

The emoji overlay loads one JSON array from the packaged plugin directory. Each
item must provide an `e` emoji field and may provide a `k` keyword field. It
filters keyword text case-insensitively and caps display at 1000 matches.

```text
card maximum width       400 px
card maximum height      500 px
content margin           18 px
header height            max(34 px, title + 2×controlPaddingY)
cell width/height        max(44 px, display font + md spacing)
default cell              44 × 44 px
default grid columns      floor((400 - 2×18) / 44) = 8
```

It uses the menu surface palette, a full-screen exclusive overlay, and a grid
whose cells highlight the single keyboard cursor. Left/right moves one cell,
Up/Down moves one row, PageUp/PageDown move visible rows, typing filters, and
Enter inserts the selected emoji through the external insertion helper. Escape
clears the filter first, then closes. The selected cell uses the menu selected
background; empty state uses a large display mark and title font.

## Image carousel picker

The image picker is a kept overlay with both an image and video path. It can be
driven through the host's JSON summon or the stable positional IPC bridge.

### Input row format

The scanner emits one row per source:

```text
<absolute source path>\t<thumbnail path>
```

The parser rejects blank paths, de-duplicates by filename, and keeps the
original source path separate from the thumbnail path. Supported source
extensions are jpg, jpeg, png, gif, bmp, webp, mp4, m4v, mov, webm, mkv, and
avi.

The scan walks each supplied directory only one level deep, sorts NUL-safe
paths, and uses a cache under `CACHE/image-selector`. Thumbnail identity is
based on path + file size + mtime, hashed with MD5 for the cache filename.
Video thumbnails are generated with `ffmpegthumbnailer -s 1536 -q 8` under a
10 s timeout with a 5 s kill-after, protected by a per-thumbnail lock and
parallelized at approximately `nproc/4` jobs (minimum one). A failed video is
marked; a timed-out video is retried later.

### Exact geometry

```text
expanded selected slice       768 × 475 px
unselected slice              108 × 432 px
slice spacing                 -30 px
skew offset                   28 px
carousel item step            78 px
carousel top margin           30 px
card outer width              min(screen width - 80, 768 + 13×78 + 40)
carousel width                768 + 13×78 = 1782 px
card height                   475 + 30 + bottomChromeHeight
```

`bottomChromeHeight` is:

```text
labels=false, filter=false   30 px
labels=false, filter=true    60 px
labels=true,  filter=false   74 px
labels=true,  filter=true   104 px
```

The selected item is full-size at z `100`; nearby matching items within 16
filtered positions are loaded and remain texture-activated after visiting.
Selected borders are `3 px`; unselected borders are `1 px`; unselected slices
receive dim overlay alpha `0.42`. The selected image is not dimmed. The shape
mask is a parallelogram whose top/bottom edges use the 28 px skew.

The scrim uses the image-picker role. Labels use display font and outline
style with background alpha `0.7`; the filter line uses title font and outline.
The picker waits for layout settlement before granting exclusive keyboard focus.
Left/right/Tab cycles matching images; filterable instances accept text edits;
Enter writes the selected path; Escape clears the filter then cancels.

### File-based selection round trip

For callers that need a result:

```text
caller creates selection_file and done_file with mktemp
caller summons picker with both paths
picker writes selected path + newline to selection_file
picker touches done_file
cancel touches/clears done_file without selection
```

Done-file operations are queued and serialized. Closing clears passwords,
selection paths, rows, and generation flags; in-flight canceled results are
discarded with `expectedStop`/request serial guards.

## Wi-Fi QR overlay

The QR panel is a standalone panel plugin so it can be replaced independently.
It runs a network helper that emits:

```text
meta<TAB>interface<TAB>security<TAB>ssid
<square matrix of 0/1 characters>
```

The parser requires a square matrix and rejects any non-binary/mismatched row.
The card is a centered, no-card overlay over a fixed near-black scrim
`#000000` at alpha `0.78`.

```text
content column spacing     16 px
title/error max width      320 px
QR logical maximum         240 px
module size                max(4 px, floor(240 / matrix size))
```

The QR canvas is white with the shared corner radius; dark modules are native
integer-sized rectangles in `#111111`, preserving a crisp quiet zone. The
password is fetched only after an explicit “show password” click, is held only
while the overlay is open, and is cleared on close. A canceled QR generation
cannot repopulate a closed overlay or overwrite a later request.

## Speed-test overlays

Network and disk tests are separate panel plugins over the common
`SpeedTestOverlay` gauge cluster.

### Internet test

Opening starts a download phase, then an upload phase. Each phase runs at most
`5000 ms`; streaming numeric output updates the corresponding dial. Closing
sets an expected-stop flag, clears the phase before terminating the child, and
prevents a buffered line/exit from being treated as a failure. A run requested
while a stop is still landing is queued and starts after exit.

The connection title comes from an optional JSON payload or a one-shot
`omarchy-network-status` probe. The source does not put a timeout around that
particular QML `Process`; the display unit is Mbps and scale stops are
`100, 250, 500, 1000, 2500, 5000, 10000`.

### Disk test

One process streams lines in this form:

```text
disk <model>
read <MB/s>
write <MB/s>
```

The same close/queued-rerun/error handling applies. Dials are READ and WRITE,
unit MB/s, with scale stops `500, 1000, 2500, 5000, 10000, 15000`.

Both overlays use the exact common dial geometry in
[05-ui-kit-and-measurements.md](05-ui-kit-and-measurements.md), keyboard
exclusive focus, Escape/scrim dismissal, and a Run Again button that is hidden
while a test is active.

## Reminder flow

The reminder capability is a two-step kept overlay. It intentionally reuses
the menu's text-filter state rather than embedding a separate text control:

```text
step 1: positive decimal minutes only
step 2: optional free-form message
```

```text
card maximum width        300 px
content margin            18 px
header height             max(34 px, title + 2×controlPaddingY)
card height               min(content margin×2 + header height,
                              panel height - 2×gapsOut)
```

Blank minutes cancel. Invalid minutes emit an error notification. A valid
message invokes the reminder helper via an argv vector and then closes.

## Developer component gallery

The developer gallery is a real `panel` plugin and renders the actual `qs.Ui`
types, not copies. It is therefore both documentation and a smoke test for the
component library. Its fake bar provides:

```text
font family = monospace
position    = top
vertical    = false
bar size    = 26 px
```

The gallery's outer implicit surface is `720 × 760 px`, with an internal
18 px content margin and 22 px section spacing. It demonstrates typography,
section headers, separators, cursor rows, Button, ButtonGroup,
PanelActionButton, tooltip, slider, TextField, NumberField, Toggle,
ToggleSwitch, Dropdown, SearchableDropdown, and a composed Wi-Fi-style row.
The gallery uses the same semantic keyboard recipe as production panels: one
cursor state, j/k across sections, h/l within horizontal choices or sliders,
Enter/Space activation, and Escape close.

## Agent marks and vector assets

The agent dashboard looks for convention-based files:

```text
assets/<provider>.svg
assets/<provider>-light.svg   # optional light-surface twin
```

It tries the light twin first when the surface luminance is at least `0.5`, then
the normal mark, then the bar glyph. This lets a new data provider appear by
shipping one collector record and an optional asset; the panel source is not
changed.

The cloud-sync and tunnel widgets demonstrate the opposite choice: small marks
are drawn in QML to avoid tiny-SVG rendering quirks. These assets must remain
vector/native rather than rasterizing a new icon at arbitrary sizes.
