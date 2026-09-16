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
aurelia-wallpaper wallhaven search [--query <text>] [--rows|--json] [--thumbs]
aurelia-wallpaper wallhaven download <id> [--to <source>]
aurelia-wallpaper theme generate <path> [--name <slug>] [--light|--dark] [--json]
aurelia-wallpaper theme apply <path> [--name <slug>] [--light|--dark]
aurelia-wallpaper theme list [--json]
aurelia-wallpaper theme remove <slug> --yes
~~~

Search also accepts `--categories 111`, `--purity 100`, `--sorting <s>`,
`--order <o>`, `--atleast 1920x1080`, `--page <n>`, and `--seed <text>`.

`--rows` output is the stable TSV contract consumed by the Quickshell panel:

~~~text
local rows:     path, thumbnail, label, source, current
wallhaven rows: id, thumbnail, resolution, purity, page URL
~~~

## Files and state

~~~text
aurelia-shell/bin/aurelia-wallpaper                  CLI entry point
aurelia-shell/bin/lib/aurelia-wallpaper/*.sh         sourcing, wallhaven, palette
aurelia-shell/bin/lib/aurelia-wallpaper/palette.awk  deterministic color engine
aurelia-shell/plugins/aurelia.wallpapers/            Quickshell panel plugin

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
  fixed hue targets for the ANSI slots, WCAG contrast enforcement for the
  foreground, and no random or time-dependent input. Decoding is bounded by
  `timeout` and requires ImageMagick (`magick` or `convert`).
- **The UI never touches the network or the state.** The panel renders cached
  thumbnails fetched by the CLI and builds argv for `aurelia-wallpaper` only.
- **Bounded operations.** Every external operation (curl, ImageMagick,
  ffmpegthumbnailer via the existing theme preview cache) runs under `timeout`
  with a kill-after, so a hostile or broken source cannot hang the session.

A failed download may leave a staging file in `~/.cache/aurelia/wallpapers/`;
that directory is regenerable cache and can be deleted safely at any time.

## Shell integration

The panel plugin is a resident `panel` kind plugin. It is summoned with
`SUPER + SHIFT + W` (declared in `plugins/aurelia.wallpapers/keybindings.lua`
and merged into the authoritative keybinding manifest) or with:

~~~bash
aurelia-shell shell toggle aurelia.wallpapers '{}'
~~~

Keyboard model: arrows move through the grid, `Tab` switches between the local
library and the wallhaven browser, typing filters (or searches, in wallhaven
mode), `Enter` applies (in wallhaven mode it downloads first, then applies),
`T` toggles "derive a theme from this wallpaper", `Esc` closes.

## Tests

`tests/test_wallpapers.sh` (run by `aurelia-shell/tests/run.sh`) covers the
manifest and delegation contract, the row model, and isolated end-to-end
behavior for sources, apply, import, palette generation, generated-theme
lifecycle, configuration failure modes, and the wallhaven integration through
a stubbed curl with fixture responses. The suite performs no network access
and never touches live desktop state.

## Provenance note

Upstream Aether is MIT-licensed. No upstream code was copied; this capability
re-implements the wallpaper sourcing and palette-extraction ideas against this
repository's existing data-only theme pipeline and safety rules.
