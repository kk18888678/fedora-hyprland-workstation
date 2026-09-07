# Theme, wallpaper, and cross-application synchronization

Themes are a state pipeline, not just a palette file:

~~~text
theme source
  -> installed/user theme resolution
  -> guarded staging directory
  -> colors.toml normalization
  -> generated application and shell configs
  -> background selection/transition
  -> atomic current-theme swap
  -> live shell theme IPC
  -> parallel application retinting
  -> user theme-set hook
  -> selector-cache warmup
~~~

The editable sources live in user configuration or the packaged theme tree. The
active generated result lives under user state and is the only path consumed by
the running desktop.

## Theme source locations

~~~text
<root>/themes/<name>/                         packaged theme
~/.config/<namespace>/themes/<name>/           user theme or Git clone
~/.local/state/<namespace>/current/theme/      generated active theme
~/.local/state/<namespace>/current/theme.name current normalized slug
~/.local/state/<namespace>/current/background  symlink to active media
~/.config/<namespace>/backgrounds/<theme>/     extra user backgrounds
~/.config/<namespace>/themed/                  user template overrides
~/.cache/<namespace>/theme-selector/           theme preview cache
~/.cache/<namespace>/image-selector/           image thumbnail cache
~~~

Theme list resolution combines user and packaged directories, sorts, removes
duplicate names, and formats slugs for display. User directories take
precedence when a packaged and user theme have the same name.

A user-authored directory and a theme cloned by the theme installer are treated
differently:

- a hand-authored user directory is not subject to the Git-installed deny
  filter and is copied as the user’s own theme; the normal `*` copy still
  excludes dotfiles;
- a Git checkout under the user theme directory is treated as untrusted
  installed theme input and is filtered before it reaches active state.

## Installing a Git theme

The installer accepts an interactive URL or an explicit argument. It first runs
the same Git URL checker used by plugins:

~~~text
allowed URL transports:
ssh, git, git+ssh, ssh+git, http, https, ftp, ftps, file
rejected:
leading dash, <helper>::<address>, unknown scheme://<address>
~~~

It derives the theme directory name from the URL by removing .git, removing a
leading omarchy-, removing a trailing -theme, and lowercasing. The name must
match:

~~~text
^[a-z0-9_][a-z0-9._+-]*$
~~~

The reference removes an existing directory of the same name, clones directly
to ~/.config/<namespace>/themes/<name>, and immediately applies the theme.
This replacement is within the user theme namespace but is not a backup
operation; a hardened implementation should preserve that exact behavior only
if the destructive replacement is an intentional compatibility decision.

## Theme application and staging

The theme setter normalizes the requested display name by removing angle-bracket
markup, lowercasing, and converting spaces to dashes. It rejects an empty,
dot-prefixed, or slash-containing name and then resolves a packaged or user
directory.

It serializes theme changes with:

~~~text
<XDG_RUNTIME_DIR or /tmp>/<namespace>-theme-set.lock
~~~

The critical section is:

1. remove the previous generated next-theme directory;
2. create a clean next-theme directory;
3. copy packaged theme files first;
4. overlay the user theme;
5. filter a Git-installed user theme;
6. generate colors and all template outputs;
7. select the next background and, when possible, snapshot the old image;
8. remove the current generated theme;
9. rename next-theme to current-theme;
10. write the normalized theme name;
11. update the background link and live shell theme;
12. release the lock before slower application retinting.

The current theme directory is therefore replaced as a unit. A partially
generated next-theme does not become current.

### Git-installed theme filter

For a user theme identified as a non-symlink directory containing .git, the
setter applies the denied-name check to each top-level entry:

~~~text
all *.lua
alacritty.toml
foot.ini
ghostty.conf
kitty.conf
vscode.json
~~~

These top-level names are intentionally denied because Lua can run at
compositor/editor startup, terminal configs choose executable shells/programs,
and vscode.json causes an editor extension installation. A top-level directory
is then copied recursively by a separate helper that skips symlinks but does
not reapply the denied-name check to nested files. Nested Lua/config files can
therefore survive; this is an implementation quirk that a claimed 1:1 port
must either preserve or label as a deliberate hardening change.

README/license/changelog/Markdown/text files may be ignored without being
reported; other ignored top-level entries are listed on stderr. The source
uses ordinary `*` globs for these copies, so dotfiles are not copied by the
normal theme overlay or recursive helper.

Everything else is retained, including colors, backgrounds, previews,
btop.theme, chromium.theme, helix.toml, icons.theme, keyboard.rgb,
shell.toml, and other non-denied assets.

If colors.toml is absent but alacritty.toml exists, the setter derives colors
from the normal and bright Alacritty palette. All eight normal colors are
required; bright colors fall back to normal colors. Background, foreground,
selection, and accent are then written to a generated colors.toml.

## Color and template generation

The color parser accepts one-line key/value entries with safe keys and values.
It derives semantic names from legacy ANSI names and maintains both forms:

~~~text
background <-> color0
foreground <-> color7
red         <-> color1
green       <-> color2
yellow      <-> color3
blue        <-> color4
magenta     <-> color5
cyan        <-> color6
muted       <-> color8
bright_*    <-> color9..color15
~~~

It also derives light/dark mode, selection, cursor, lighter/darker backgrounds,
bright shades, orange, brown, and purple fallbacks. Color mixing accepts a
fraction or percentage and rounds each RGB channel to the nearest integer.

The template generator reads user templates first and packaged templates second.
It creates an output only when the output is not already present, so the user
template wins. Each template output drops the .tpl suffix:

~~~text
default/themed/alacritty.toml.tpl                    -> alacritty.toml
default/themed/btop.theme.tpl                       -> btop.theme
default/themed/chromium.theme.tpl                   -> chromium.theme
default/themed/claude.json.tpl                      -> claude.json
default/themed/foot.ini.tpl                         -> foot.ini
default/themed/ghostty.conf.tpl                     -> ghostty.conf
default/themed/gum_env.lua.tpl                      -> gum_env.lua
default/themed/helix.toml.tpl                        -> helix.toml
default/themed/hermes.yaml.tpl                       -> hermes.yaml
default/themed/hyprland-preview-share-picker.css.tpl -> hyprland-preview-share-picker.css
default/themed/hyprland.lua.tpl                      -> hyprland.lua
default/themed/keyboard.rgb.tpl                      -> keyboard.rgb
default/themed/kitty.conf.tpl                        -> kitty.conf
default/themed/neovim.lua.tpl                        -> neovim.lua
default/themed/obsidian.css.tpl                      -> obsidian.css
default/themed/pi.json.tpl                           -> pi.json
default/themed/shell.toml.tpl                        -> shell.toml
default/themed/vscode-theme.json.tpl                 -> vscode-theme.json
~~~

Supported placeholders include each resolved color, a no-hash form with
suffix _strip, decimal RGB with suffix _rgb, mixed colors, and three gradient
functions:

~~~text
{{ mix foreground background 34% }}
{{ mix_strip foreground background 34% }}
{{ mix_rgb foreground background 34% }}
{{ hypr_gradient hyprland_active_border accent }}
{{ gradient_start hyprland_active_border accent }}
{{ shell_gradient hyprland_active_border accent }}
~~~

A theme-provided shell.toml replaces the generated shell template. Files named
shell.<section>.toml are section overrides: they replace only that section in
the generated shell.toml. The shell runtime then merges its user-level
~/.config/<namespace>/shell.toml over the active theme shell values.

## Background selection and state

A theme’s background candidates are one directory deep and sorted as full paths.
Supported still/video extensions are:

~~~text
jpg jpeg png gif bmp webp mp4 m4v mov webm mkv avi
~~~

The candidate set combines:

~~~text
~/.config/<namespace>/backgrounds/<theme>/
~/.local/state/<namespace>/current/theme/backgrounds/
~~~

When applying a theme, the setter maps the selected path in next-theme back to
the durable current-theme path before the swap. If the current symlink points
to a background with the same filename in the old theme, the corresponding
filename in the next theme is selected; otherwise the first sorted candidate is
selected. If a current candidate is found, the next candidate wraps around.

The active path is persisted only as a symlink:

~~~text
~/.local/state/<namespace>/current/background -> <absolute-media-path>
~~~

Direct background selection resolves the input to an absolute path, replaces
the symlink, and immediately sends a background IPC set request. Background
cycling enumerates the same two directories, finds the symlink target, advances
with wraparound, and uses the same setter.

The background install menu creates the user extra-background directory and
opens it in the file manager. A user can therefore add media without modifying
the packaged theme.

## Wallpaper renderer

The first-party background service creates one full-screen background
PanelWindow per Quickshell screen:

~~~text
namespace       omarchy-background
layer           background
keyboard focus  none
exclusion       ignore
color           transparent
updatesEnabled  true
~~~

The renderer uses PreserveAspectCrop, asynchronous image loading, smooth/mipmap
image sampling, and never parks a still layer with updates disabled.

Images and videos have separate loader paths. Videos use a bare Qt Multimedia
MediaPlayer and VideoOutput; the convenience Video type is not used because it
would create an audio client even for muted output. Video playback loops
forever, with audio enabled only on the first screen.

Playback is enabled only when all of these are true:

~~~text
no session lock
no screensaver window
not on battery with active power-saver profile
no fullscreen window on that monitor
~~~

This is per-monitor for fullscreen windows and global for lock/screensaver.
Every monitor has its own decoder, but only the first screen produces wallpaper
audio.

A new video is switched instantly without the image reveal stack. A new image
uses a 420 ms InOutCubic reveal. The reveal mask is a four-sided slanted
polygon with:

~~~text
slant = -0.18
reach = width/2 + abs(slant)*height/2 + 4
spread = reach * revealProgress
~~~

The background service keeps pending theme colors/shell values for 300 ms. It
applies them when the image reveal starts, or after the 300 ms fallback if a
decoder stalls. A theme switch on an unchanged file path increments a reload
counter so the image cache is invalidated.

### Image-to-image transition snapshots

For a still-to-still transition, the setter snapshots the old and next image
into:

~~~text
~/.cache/<namespace>/background-transitions/
~~~

It creates a hard link where possible and falls back to a copy. Video files are
never snapshotted. If either side is a video, the transition snapshot path is
disabled and the QML renderer switches directly.

Old/next snapshots are deleted asynchronously after 3 seconds. This avoids
leaving the old generated theme path as a dependency after the current swap.

## Shared image picker

The kept image-picker overlay is used by the theme switcher, background
switcher, unlock selector, and any other caller that supplies image rows.

The shell IPC bridge accepts a base64-encoded row payload because paths can carry
tabs/newlines through a positional shell argument. The row round trip is:

~~~text
caller creates selection_file and done_file with mktemp
caller sends rows + selected path + both files
image-picker writes selected path, then touches done_file
caller polls done_file
cancel clears selection and completes done_file
~~~

The direct image selector target uses:

~~~text
open(imageDirs, imageRowsB64, selectedImage, selectionFile, doneFile,
     showLabels, filterable)
preload(imageRowsB64, selectedImage, showLabels, filterable)
cancel(doneFile)
ping()
~~~

The picker’s exact base geometry is:

~~~text
expandedWidth       = 768 px
expandedHeight      = 475 px
sliceWidth          = 108 px
sliceHeight         = 432 px
sliceSpacing        = -30 px
skewOffset          = 28 px
~~~

Bottom chrome is:

~~~text
showLabels=false, filterable=false -> 30 px
showLabels=false, filterable=true  -> 60 px
showLabels=true,  filterable=false -> 74 px
showLabels=true,  filterable=true  -> 104 px
~~~

The centered card uses:

~~~text
width  = min(parent.width - 80,
             expandedWidth + 13 * (sliceWidth + sliceSpacing) + 40)
height = expandedHeight + Style.space(30) + bottomChromeHeight
top margin in card     = Style.space(30)   # 30 px at base scale
selected label margin  = Style.space(16)   # 16 px at base scale
filter text margin     = Style.space(8)    # 8 px at base scale
selected border        = 3 px
unselected border      = 1 px
unselected dim overlay = 0.42 alpha
~~~

The active slice is expanded to 768×475 content geometry; nearby slices use
108×432 and a -30 px overlap spacing. Up to 16 neighboring slices on either
side are activated. Images use PreserveAspectCrop, cache true, and synchronous
loading once activated to avoid carousel flicker.

Rows are parsed as:

~~~text
<absolute-source-path>\t<thumbnail-path>
~~~

Blank paths are rejected, and duplicate filenames are removed. Filters are
case-insensitive against the filename stem and a title-cased label. Selected
images default to the first row when no match exists. Escape clears the filter
first and cancels second; Enter applies; left/right/tab moves the selection.

## Thumbnail generation and cache rules

The menu image generator and direct picker share a cache under
~/.cache/<namespace>/image-selector. A cache key is the MD5 of the joined image
directories. File identity is path plus size plus mtime, mapped to a cache
filename using MD5.

Still thumbnails use:

~~~text
env VIPS_CONCURRENCY=1 vipsthumbnail
  --size 1536x864
  --smartcrop=centre
  --path <cache>.jpg[Q=82,strip]
~~~

Video thumbnails use:

~~~text
timeout -k 5 10 ffmpegthumbnailer
  -i <video>
  -o <cache>.jpg
  -s 1536
  -q 8
~~~

Still thumbnail jobs fan out to nproc workers, video jobs to max(1,nproc/4)
workers. Each output is protected by a flock with a 30-second wait. A failed
video is remembered with a .failed marker; a timeout is retried next time. Rows,
full signatures, and fast signatures are published using temporary files and
renames.

The theme switcher caches theme previews. It first looks for a named
preview.png/jpg/jpeg/webp/gif/bmp/mp4/m4v/mov/webm/mkv/avi, otherwise uses the
first supported background. Its fast signature is versioned and includes theme
directory mtimes; a full signature includes preview file size and mtime. A
changed fast signature rebuilds the preview symlink directory.

The background switcher invokes the image menu with:

~~~text
--print-name --show-labels --filterable --lazy-thumbnails
~~~

Theme selection invokes the same image menu over the preview cache with labels,
filtering, lazy thumbnails, and the current preview selected.

## Live theme propagation

After the current theme swap, live mode sends base64-encoded colors.toml and
shell.toml to the background service’s theme-transition method. The service
updates its Color/Style singletons and starts the transition. If the background
service is not available, the setter falls back to the shell applyTheme IPC.

The shell receives:

~~~text
applyTheme(colorsBase64, shellBase64)
  -> decode both values
  -> Color.loadColors
  -> Color.loadShell
  -> Style.scheduleRefresh
~~~

The shell re-polls Hyprland rounding/gaps after 200 ms. The user shell override
remains layered above the theme shell values.

Headless/offline theme application does not use shell IPC. It still swaps
generated current state and creates the background symlink unless background
selection was explicitly skipped. This is used during chroot/first-install
stages.

## Cross-application retinting

Live theme application launches these commands in parallel after releasing the
theme lock:

~~~text
omarchy-restart-terminal
omarchy-restart-hyprctl
omarchy-restart-btop
omarchy-restart-opencode
omarchy-restart-helix
omarchy-theme-set-foot
omarchy-theme-set-tmux
omarchy-theme-set-gnome
omarchy-theme-set-pi
omarchy-theme-set-claude
omarchy-theme-set-hermes
omarchy-theme-set-browser
omarchy-theme-set-vscode
omarchy-theme-set-obsidian
omarchy-theme-set-keyboard
~~~

Then it runs the user theme-set hook with the normalized slug, preloads the theme
selector, and warms the background selector cache asynchronously.

The cross-application ownership rules are:

| Consumer | Active generated input | Application action |
|---|---|---|
| shell | colors.toml + shell.toml | live IPC and 200 ms geometry refresh |
| terminal families | alacritty/foot/ghostty/kitty outputs | restart or OSC retint depending on terminal |
| Hyprland | hyprland.lua and gum environment | restart/reload helper |
| btop | btop.theme symlinked as current.theme | restart helper |
| Claude | claude.json | atomic custom theme file; optional settings activation |
| Hermes | hermes.yaml | atomic skin in home and existing profiles |
| Pi | pi.json | atomic theme and settings activation |
| OpenCode | system config | SIGUSR2 reload |
| browser family | chromium.theme | browser policy refresh and running-browser refresh |
| VS Code/Codium/Cursor | vscode descriptor or generated local extension | install descriptor extension when valid, update colorTheme |
| Obsidian | obsidian.css | copy into each configured vault theme |
| supported keyboards | keyboard.rgb | hardware-specific keyboard setter |
| tmux | gum_env.lua/colors.toml | global/session environment, styles, OSC, pane refresh |
| GNOME/GTK | colors.toml/icons.theme | gsettings color/icon mode |
| boot unlock screen | colors.toml + unlock.png | Plymouth setter, separate from live shell |

A generated application file remains active even when the corresponding
application is not installed; the command exits early when its consumer is
absent. Third-party theme Lua/terminal/VS Code code is not allowed to cross the
filter into these outputs.

## Unlock and logo assets

A theme may include unlock.png and preview-unlock.png. The unlock selector
creates a preview directory with the packaged default preview plus links to each
theme’s preview-unlock.png, then uses the same image picker.

Applying an unlock theme passes its colors.toml background/foreground and
unlock.png to the boot-screen setter. A generated 1920×1080 preview composes:

~~~text
centered logo
entry image 40 px below logo
lock icon to the left, 15 px gap
four 7×7 bullets, 12 px pitch, starting 20 px into entry
lock height = floor(entry_height × 0.8)
lock width  = floor(84 × lock_height / 96)
~~~

The source branding assets are separate from theme images:

~~~text
logo.txt  -> 81 columns wide, 10 rows
icon.txt  -> 54 columns wide, 26 rows
logo.svg  -> viewBox 1215×285
icon.png  -> 300×300
~~~

The shell uses the vector/private icon font for product and agent glyphs; see
13-ai-first-platform.md and 04-design-language.md for the interaction and type
contracts.

## Source cross-check

~~~text
manual/06-themes.md
manual/39-backgrounds.md
manual/43-making-your-own-theme.md
default/themed/
themes/
bin/omarchy-theme-install
bin/omarchy-theme-set
bin/omarchy-theme-set-templates
bin/omarchy-theme-color
bin/omarchy-theme-colors-from-alacritty
bin/omarchy-theme-bg-install
bin/omarchy-theme-bg-set
bin/omarchy-theme-bg-next
bin/omarchy-theme-bg-switcher
bin/omarchy-theme-bg-cache
bin/omarchy-theme-switcher
bin/omarchy-theme-set-browser
bin/omarchy-theme-set-claude
bin/omarchy-theme-set-hermes
bin/omarchy-theme-set-pi
bin/omarchy-theme-set-vscode
shell/plugins/background/
shell/plugins/image-picker/
shell/Ui/BackgroundMedia.qml
shell/Ui/BackgroundVideo.qml
default/hypr/apps/webcam-overlay.lua
default/omarchy/omarchy-menu.jsonc
test/shell.d/theme-install-guards-test.sh
test/shell.d/theme-staging-test.sh
test/shell.d/user-theme-test.sh
test/shell.d/video-background-test.sh
~~~

The implementation should not infer more than this source says. For example,
the active theme is not a live directory overlay, video wallpapers do not use
the image reveal snapshots, and top-level denied Git-theme files do not enter
the generated current theme. The source’s nested-directory copier currently
allows non-symlink nested Lua/config files through, as documented above.
