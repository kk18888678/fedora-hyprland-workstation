# Aurelia Wallpaper Library and Palette Capability

Status: shipped capability. The wallhaven integration, the local wallpaper
library, and the palette generator are repository-owned and data-only.

This capability is the Fedora-workstation equivalent of the sourcing half of
upstream `omacom/aether`: it applies wallpapers from `~/Pictures/Wallpapers`,
from additional user-declared sources, and from wallhaven.cc, and it can derive
a data-only color theme from any wallpaper. It is not the Aether application,
has no Wails/Go/Node dependency, and does not write Omarchy paths.

## Ownership model

- `aurelia-wallpaper` (this capability) owns wallpaper *sourcing*:
  - local source discovery over XDG Pictures/Wallpapers and configured roots,
  - library imports,
  - wallhaven search, thumbnails, and downloads,
  - the pinned bjarneo wallpaper catalog (search, thumbnails, downloads),
  - palette (`colors.toml`) generation from a wallpaper image.
- `aurelia-theme-bg set <path>` stays the only writer of the active wallpaper.
- `aurelia-theme set <slug>` stays the only writer of the active palette.
- `aurelia.wallpapers` (Quickshell panel plugin) is a discovery and selection
  surface; it never writes wallpaper or theme state itself.

## Commands

~~~bash
aurelia-wallpaper sources [--json]
aurelia-wallpaper sources add <path> [--id <id>]
aurelia-wallpaper sources remove|enable|disable <id>
aurelia-wallpaper list [<source>] [--json|--rows]
aurelia-wallpaper apply <path>
aurelia-wallpaper apply --source <id> --index <n>|--next
aurelia-wallpaper random [<source>] | next [<source>]
aurelia-wallpaper current [--json]
aurelia-wallpaper import <path> [--to <source>]
aurelia-wallpaper wallhaven key --status|--set
aurelia-wallpaper wallhaven search [--query <text>] [--rows] [--json] [--paging]
                                  [--page <n>] [--thumbs]
aurelia-wallpaper wallhaven download <id> [--to <source>]
aurelia-wallpaper catalog list [--query <text>] [--live] [--refresh] [--rows|--json] [--thumbs]
aurelia-wallpaper catalog download <key> [--to <source>]
aurelia-wallpaper theme preview <path> [--mode <m>] [--light|--dark] [<adjustments>] --json
aurelia-wallpaper theme generate <path> [--name <slug>] [--mode <m>] [--light|--dark]
                                [<adjustments>] [--json]
aurelia-wallpaper theme apply <path> [--name <slug>] [--mode <m>] [--light|--dark]
                                [<adjustments>]
aurelia-wallpaper theme list [--json]
aurelia-wallpaper theme remove <slug> --yes
~~~

Search also accepts `--categories 111`, `--purity 100`, `--sorting <s>`,
`--order <o>`, `--atleast 1920x1080`, `--page <n>`, and `--seed <text>`.
`--paging` prepends a single `#meta<TAB>page<TAB>lastPage<TAB>total` row to the
`--rows` output so a GUI can offer "load more" without a second request.

`--rows` output is the stable TSV contract consumed by the Quickshell panel:

~~~text
wallhaven meta row: #meta, page, lastPage, total
local rows:     path, thumbnail, label, source, current
wallhaven rows: id, thumbnail, resolution, purity, page URL
catalog rows:   id, thumbnail, label, resolution, purity, page URL
~~~

## Extraction modes and fine-tuning

`theme preview`, `theme generate`, and `theme apply` share one recipe:

- **Extraction modes** (`--mode`): `normal`, `monochromatic`, `analogous`,
  `pastel`, `material`, `colorful`, `muted`, `bright`. Each is a deterministic
transform of the extracted colors (hue anchoring, saturation/lightness bands,
or a Material hue mapping).
- **Light/dark** (`--light`/`--dark`, or automatic from the image mean): swaps
  the background/foreground anchors and the contrast direction.
- **Twelve fine-tuning controls**: `--vibrance`, `--saturation`, `--contrast`,
  `--brightness`, `--shadows`, `--highlights`, `--gamma`, `--black-point`,
  `--white-point`, `--hue-shift`, `--temperature`, `--tint`. Values are
  range-checked and fail closed outside their documented bounds; the defaults
  are neutral.

The recipe is stored in the generated theme marker, and a generated theme is
only considered unchanged when both the image digest **and** the recipe match,
so changing a slider regenerates the palette. `theme preview` is mutation-free:
it renders the palette JSON for the current recipe without writing any theme,
which is what the GUI editor uses for live swatches.

## Contrast contract and surface tokens

The palette engine emits a **complete** palette, including the surface tokens
that the shell consumes. Emitting them is what keeps a light-mode generated
theme from falling back to the shipped Rosé Pine Moon `surface`/`overlay`
values (dark `#2a273f`/`#393552`), which produced dark-on-dark inputs and
cards on light wallpapers.

The WCAG contract is enforced in `palette.awk` and is fail-closed: a role can
never be emitted below its documented minimum.

| Token | Role | Minimum against `background` |
| --- | --- | --- |
| `foreground` | primary text | 4.5:1 |
| `muted` | muted text | 4.5:1 |
| `light_foreground` | secondary text | 4.5:1 |
| `dark_foreground` | subtle text | 3.0:1 |
| `accent` | text/icon accent | 3.0:1 |
| `selection` | selected-row **surface** | exempt (non-text) |
| `surface`, `surfaceElevated`, `lighter_background` | elevation **surfaces** | exempt (non-text) |

- `foreground` first runs a bounded, deterministic nudge toward the mode's
  contrast pole (white for dark, black for light). If the pair is still below
  4.5:1 after that loop, it is **escalated** to the pure pole with the highest
  possible contrast. `max(contrast_white, contrast_black)` is always at least
  ~4.58 for any background, so a sub-4.5 background/foreground pair can never
  be emitted silently.
- `muted` and `light_foreground` are mixed from the anchors and pulled toward
  the foreground until they clear 4.5:1; `dark_foreground` does the same for
  3.0:1. The requested dimness is preserved whenever it already satisfies the
  minimum.
- `accent` is the extracted highlight color, nudged and escalated toward the
  contrast pole until it clears 3.0:1.
- `selection` is a **non-text surface**: it is a background for selected rows,
  not a text color, so it is explicitly exempt from the text minimums. Text is
  still drawn on it, so the elevation is bounded to keep `foreground` at
  4.5:1 against it.
- `surface`, `surfaceElevated`, and `lighter_background` are non-text elevation
  surfaces derived from the background/foreground anchors. For dark themes the
  surface moves toward the light foreground; for light themes it moves toward
  the dark foreground, so it is always distinguishable from the background.
  Each surface uses the largest elevation that still keeps `foreground` at
  4.5:1 against it. `lighter_background` is the Omarchy-compatible alias for
  `surface` and always has the same value.

The contract is covered by a synthetic-wallpaper table in
`tests/test_wallpapers.sh` (bright, dark, busy, pastel, saturated) that asserts
every text role's ratio and key completeness in both light and dark modes.

## Files and state

~~~text
aurelia-shell/bin/aurelia-wallpaper                  CLI entry point
aurelia-shell/bin/lib/aurelia-wallpaper/*.sh         sourcing, wallhaven, palette
aurelia-shell/bin/lib/aurelia-wallpaper/palette.awk  deterministic color engine
aurelia-shell/plugins/aurelia.wallpapers/            Quickshell panel plugin
  WallpapersPlugin.qml                               resident panel entry point
  ui/WallpapersPanel.qml                             browser, paging, selection
  ui/PaletteEditor.qml                               lazily loaded palette editor
  ui/WallhavenKeyRow.qml                             API-key set/clear controls
  WallpapersModel.js                                 row parsing and paging merge

~/.config/aurelia/wallpapers.json   source configuration (version 1)
~/.config/aurelia/wallhaven.json    optional API key, 0600
~/.config/aurelia/themes/wallpaper-*/   generated user themes
~/.cache/aurelia/wallpapers/        thumbnails, download staging, provenance
~~~

Configuration example:

~~~json
{
  "version": 1,
  "library": "/home/user/Pictures/Wallpapers",
  "sources": [
    { "id": "extra", "path": "/home/user/Pictures/Backgrounds", "enabled": true }
  ],
  "wallhaven": {
    "categories": "111",
    "purity": "100",
    "sorting": "relevance",
    "order": "desc",
    "atleast": "1920x1080",
    "page_size": 24
  }
}
~~~

A malformed configuration file is reported and refuses to run; it is never
silently replaced by defaults. The optional wallhaven API key is read from
stdin (`wallhaven key --set`), never from argv, and is stored with 0600
permissions. It is never printed or logged.

## The bjarneo wallpaper catalog

`catalog` searches the pinned wallpaper catalog published at
`https://bjarneo.github.io/wallpapers/` (the same catalog used by upstream
Aether's author). The index is a static JavaScript document, fetched once into
`~/.cache/aurelia/wallpapers/catalog/` and reused for 7 days (`--refresh`
forces a re-fetch; a failed refresh keeps serving the cached copy with a
warning). Search is client-side over storage key, title, description, tags,
color, and theme, so no query ever leaves the machine.

~~~bash
aurelia-wallpaper catalog list --query aurora --rows --thumbs
aurelia-wallpaper catalog list --live --rows          # animated wallpapers
aurelia-wallpaper catalog download 'dark/blue/3840x2160_omarchy_nebula__01-nebula.jpg'
~~~

- The index host (`bjarneo.github.io`) and the storage host it declares
  (`wallpapers.hel1.your-objectstorage.com`) are pinned in the repository. An
  index that declares any other storage host fails closed, and media paths from
  the index may not carry a scheme or `..` traversal.
- Downloads land in `<source>/catalog/` with the key's separators folded
  (`dark/blue/x.jpg` becomes `dark_blue_x.jpg`), are signature-checked, and are
  skipped when the stored file already matches the size declared by the index.
- Remote previews for one page (up to 48, tunable with
  `AURELIA_WALLPAPER_THUMB_LIMIT`) are downloaded into the thumbnail cache so
  the grid never loads the network itself.
- The index is ~35 MB; it is cached, size-capped, and fetched under a
  dedicated timeout (`AURELIA_WALLPAPER_CATALOG_TIMEOUT`, default 240 s).

## Safety model

- **Activation ownership.** Applying a wallpaper or a generated theme always
  delegates to the existing `aurelia-theme-bg` / `aurelia-theme` commands. This
  capability never writes `~/.local/state/aurelia/current/` itself.
- **Downloads are user media, not software.** Every fetch is HTTPS-only with
  redirects restricted to HTTPS, bounded by connect/request timeouts and a
  maximum response size, host-allowlisted (`wallhaven.cc`, `api.wallhaven.cc`,
  `w.wallhaven.cc`, `th.wallhaven.cc`), signature-checked against the declared
  media type, and published atomically from a `mktemp` staging file. Downloaded
  files are never executed.
- **SFW by default.** Downloads refuse any result whose wallhaven purity is not
  `sfw`. The search filter defaults to purity `100`; widening it affects
  search metadata only, and downloads stay fail-closed.
- **Non-image content is rejected.** Extension checks alone are not trusted:
  `apply`, `import`, and published downloads verify the leading bytes against
  the declared media type before anything is used.
- **Generated themes are marked.** A generated theme directory contains a
  `.generated.json` marker. `theme generate` refuses to overwrite any theme it
  did not generate, and `theme remove` refuses anything without the marker or
  while the theme is active. Removal is a narrow, symlink-safe delete of the
  marked directory only.
- **Imports are idempotent.** Content is deduplicated by size and SHA-256
  inside the target source; a name collision with different content gets a
  deterministic `-<sha8>` suffix instead of overwriting user data.
- **Palette generation is deterministic.** The same image always yields the
  same `colors.toml`: a fixed 200x200 sample grid, luminance-sorted clusters,
  fixed hue targets for the ANSI slots, a fail-closed WCAG contrast contract
  for every text role, derived surface tokens, and no random or time-dependent
  input. Decoding is bounded by `timeout` and requires ImageMagick (`magick` or
  `convert`).
- **The UI never touches the network or the state.** The panel renders cached
  thumbnails fetched by the CLI and builds argv for `aurelia-wallpaper` only.
- **Bounded operations.** Every external operation (curl, ImageMagick,
  ffmpegthumbnailer via the existing theme preview cache) runs under `timeout`
  with a kill-after, so a hostile or broken source cannot hang the session.

A failed download may leave a staging file in `~/.cache/aurelia/wallpapers/`;
that directory is regenerable cache and can be deleted safely at any time.

## The GUI

The panel is a full wallpaper browser, not just a picker:

- **Source tabs** — Local, Wallhaven, and Catalog are clickable buttons at the
  top (the active one is accent-highlighted); `Tab` cycles them too.
- **Search field** — a real text field next to the tabs. Locally it filters the
  grid as you type; remotely it runs the search (debounced).
- **Thumbnail grid** — a scrolling grid of previews with labels; the active
  wallpaper carries an `ACTIVE` badge; hover and selection are accent-bordered.
- **Preview pane** — the selected wallpaper is shown large, with its name,
  source, resolution, and purity, plus the action buttons:
  - **Set wallpaper / Download & apply** — activates the selection (remote
    sources download into the library first, then apply).
  - **Extract colors…** (local source) — open the full palette editor.
  - **Random** (local source) — activate a random wallpaper.
  - **Refresh** — re-read the source.
- **Wallhaven paging** — the wallhaven tab reports the page window and total,
  and **Load more** appends the next page until the site is exhausted.
- **Wallhaven key** — the wallhaven tab shows the stored-key status and offers
  a password field plus **Save key** / **Clear key**. The key is written
  through the CLI stdin contract and never appears in argv.
- **Palette editor** (`ui/PaletteEditor.qml`, lazily loaded) — click the large
  preview or press `T` on a local wallpaper. It shows the image, live swatches
  from `theme preview`, the eight extraction modes, the light/dark choice, all
  twelve fine-tuning sliders, and **Reset** / **Set wallpaper only** /
  **Apply theme**. Every change re-renders the palette after a short debounce.
- The keyboard model still works everywhere: arrows move through the grid,
  `Enter` applies, `T` opens the editor, `Esc` closes, and typing filters while
  the grid has focus.

Every action still goes through the `aurelia-wallpaper` CLI; the GUI owns
discovery, preview, and selection only. The editor performs no network access:
its previews and swatches come from the CLI's local cache and ImageMagick
pipeline.

## Shell integration

The panel plugin is a resident `panel` kind plugin. It is summoned with
`SUPER + SHIFT + W` (declared in `plugins/aurelia.wallpapers/keybindings.lua`
and merged into the authoritative keybinding manifest) or with:

~~~bash
aurelia-shell shell toggle aurelia.wallpapers '{}'
~~~

## Tests

`tests/test_wallpapers.sh` (run by `aurelia-shell/tests/run.sh`) covers the
manifest and delegation contract, the row model and paging metadata, the eight
extraction modes and adjustment validation, the WCAG contrast contract and
surface-token completeness across the synthetic-wallpaper table, `theme
preview` being mutation-free, recipe-aware generation, and isolated end-to-end
behavior for
sources, apply, import, palette generation, generated-theme lifecycle,
configuration failure modes, and the wallhaven integration through a stubbed
curl with fixture responses. The suite performs no network access and never
touches live desktop state.

## Provenance note

Upstream Aether is MIT-licensed. No upstream code was copied; this capability
re-implements the wallpaper sourcing and palette-extraction ideas against this
repository's existing data-only theme pipeline and safety rules.
