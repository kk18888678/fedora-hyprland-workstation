# Full source map and dependency matrix

## Audit anchor

The full repository checkout used for this audit was:

~~~text
repository  https://github.com/omacom/omarchy
branch      quattro
commit      e989b5b3ee1ee1babb2614655649341f80b7b323
commit time 2026-09-07 03:15:39 -0400
tracked     1,807 files
shell       185 files / 42,409 counted lines
~~~

The requested branch is moving. Treat the commit above as the exact source
anchor for the platform additions in this documentation. The earlier
shell-only files were initially read at
f04366de79f2b6b4372d197cd49afdcc36b06a76; those inventory tables are marked
historical in 09-verification-and-source-map.md. The full-anchor comparison
also found ten modified existing shell files in addition to eight new files;
17-claim-audit.md records that delta explicitly.

## Repository topology

| Tree | Responsibility | Primary consumer |
|---|---|---|
| bin/ | flat executable command surface and orchestration leaves | user shell, Hyprland, systemd, installer |
| shell/ | one Quickshell host, common UI, services, plugins, models, assets | graphical session |
| config/ | user configuration copied into home or used as resync source | user session |
| default/ | packaged defaults, templates, systemd units, Hyprland modules, fonts, login assets | settings/runtime packages |
| install/ | root-side and user-side setup phase scripts | ISO/target installation |
| migrations/ | timestamped per-user upgrade repairs | update command |
| themes/ | packaged theme source and backgrounds | theme setter |
| applications/ | packaged desktop files and app icons | application refresh/package |
| etc/ | system-owned drop-ins and package overrides | root setup/package scriptlets |
| agents/skills/ | contributor and agent-facing task instructions | development and external coding agents |
| default/agents/skills/ | shipped user skills linked into AI harnesses | user finalization |
| manual/ | user-facing feature documentation | user |
| docs/ | architecture, lifecycle, testing, and maintainer documentation | maintainer |
| test/ | CLI, shell, migration, and acceptance test suites | CI/developer |
| plans/ | design/implementation planning material | maintainers |
| themes/ and logos | visual source assets | theme/login/shell |

## Source-to-installed path map

The reference package split is part of the lifecycle:

~~~text
bin/omarchy-*                    -> /usr/bin/omarchy-*
shell/                            -> /usr/share/omarchy/shell/
themes/                           -> /usr/share/omarchy/themes/
migrations/                       -> /usr/share/omarchy/migrations/
install/                          -> /usr/share/omarchy/install/
config/                           -> /usr/share/omarchy/config/
default/                          -> /usr/share/omarchy/default/
applications/                     -> /usr/share/omarchy/applications/
logo.*, icon.*                    -> /usr/share/omarchy/ and icon locations
version                           -> /usr/share/omarchy/version
default/systemd/user/*.service    -> /usr/lib/systemd/user/
default/uwsm/env.d/*              -> /usr/share/uwsm/env.d/
default/fonts/*                   -> /usr/share/fonts/
default/sddm/*                    -> /usr/share/sddm/themes/
default/plymouth/*                -> /usr/share/plymouth/themes/
config/* and selected default/*   -> /etc/skel/.config or /etc/skel/.local
etc/*                             -> /etc or /usr/share/.../etc-overrides
~~~

The settings package must be available before user creation because it owns
the static /etc/skel seed and system defaults. The runtime package owns the
commands, shell, themes, migrations, and user setup scripts. Standalone
keyring and editor setup packages remain separate package owners.

## Shell tree at the full audit anchor

~~~text
shell/
  shell.qml
  README.md
  Commons/
    qmldir
    Border.qml
    BorderGeometry.js
    Color.qml
    Style.qml
    Util.qml
  Ui/
    qmldir
    BackgroundMedia.qml
    BackgroundVideo.qml
    BarIconButton.qml
    BarIndicator.qml
    BarWidget.qml
    BorderOverlay.qml
    BorderSurface.qml
    Button.qml
    ButtonGroup.qml
    ConfirmDialog.qml
    CursorSurface.qml
    Dropdown.qml
    KeyboardPanel.qml
    MultiSelect.qml
    NumberField.qml
    OpticalGlyph.qml
    Panel*.qml
    PanelSlider.qml
    PopupCard.qml
    SearchableDropdown.qml
    SpeedTestOverlay.qml
    TextField.qml
    Toggle*.qml
    WidgetButton.qml
  services/
    PluginRegistry.qml
    BarWidgetRegistry.qml
    AppLibrary.qml
    AppSearch.js
    hidden-entries.sh
    *Api.qml
    AuthServiceStore.js
  plugins/
    bar/
    agents/
    background/
    clipboard/
    dev-gallery/
    emojis/
    image-picker/
    lock/
    menu/
    notifications/
    osd/
    panels/
    polkit/
    reminders/
    services/
~~~

The full plugin manifest catalog is in
12-full-plugin-lifecycle.md. The dimensions and reusable controls are in
05-ui-kit-and-measurements.md.

## Framework and library matrix

| Layer | Exact source dependency | Function |
|---|---|---|
| QML engine | Qt 6 / Qt Quick | items, text, timers, loaders, models, animations |
| QML controls/layout | Qt Quick Controls, Layouts, Models | fields, popups, scroll bars, row/column/grid composition |
| QML geometry/effects | Qt Quick Shapes, Effects, Window | custom borders, skew/reveal masks, blur/masking, device-pixel data |
| QML media | Qt Multimedia with FFmpeg backend | video wallpaper, frame output, audio sink |
| shell host | Quickshell | ShellRoot, FileView, Process, IpcHandler, Variants, service bindings |
| Wayland | Quickshell Wayland / layer-shell | bar, background, popups, overlays, session lock |
| compositor | Hyprland plus hyprctl and event APIs | monitors, workspaces, toplevels, input, fullscreen, dispatch |
| audio | PipeWire/WirePlumber, Quickshell Pipewire, MPRIS/mpv-mpris | devices, volume, sources, playback, peaks |
| power | UPower and power-profiles-daemon | battery, AC state, power-saver profile |
| connectivity | BlueZ/Bluetooth and NetworkManager | paired devices, Wi-Fi scan/connectivity/DNS |
| authentication | PAM and polkit | lock password/fingerprint and privileged prompts |
| notification bus | freedesktop Notifications over DBus | notification server, history, DND, actions |
| desktop entries | XDG DesktopEntries and application database | launcher, app search, install/remove rows |
| session | systemd user manager, UWSM, DBus activation | environment import, user services, launcher context |
| shell scripting | Bash, GNU coreutils, find, awk, sed, grep, Perl | orchestration, parsing, bounded filesystem operations |
| structured data | jq and small JavaScript modules | manifest/config/provider JSON and pure model logic |
| file watching/locking | inotifywait/inotify-tools and flock | plugin reload, thumbnail/usage serialization |
| typography | fontconfig, JetBrains Mono Nerd Font, Noto families, private icon font | monospace UI, emoji/CJK, product/agent glyphs |
| capture | grim, slurp, hyprpicker, gpu-screen-recorder | screenshot, selection, freeze, recording |
| image/video processing | ImageMagick, libvips, ffmpegthumbnailer, FFmpeg | colors, thumbnails, transcoding, recording finalization |
| clipboard/input | wl-clipboard, wtype, optional Voxtype | image/text/file URI clipboard and dictation output |
| recognition | Tesseract plus language data, zbar | OCR and QR-only decoding |
| media/opening | mpv, Tensaku, Nautilus, LocalSend | recording playback, screenshot editing, file management/sharing |
| AI tools | mise, Python 3, optional uv, external agent CLIs | lazy installs, collectors, external agents |
| packaging | pacman, yay/AUR, package hooks and Snapper | package ownership, updates, rollback |
| testing | Node.js, Bash, jq, Python, optional compositor/Quickshell | pure logic, source contracts, isolated and graphical tests |

The shell imports these Quickshell modules directly:

~~~text
Quickshell
Quickshell.Io
Quickshell.Wayland
Quickshell.Hyprland
Quickshell.Bluetooth
Quickshell.Networking
Quickshell.Services.UPower
Quickshell.Services.Pam
Quickshell.Services.Polkit
Quickshell.Services.Notifications
Quickshell.Services.Mpris
Quickshell.Services.Pipewire
Quickshell.Services.SystemTray
~~~

Not every target needs every optional integration. The host must provide the
same feature contract or the corresponding component must collapse
gracefully.

## Direct package ownership matrix

The reference’s package manifests directly include the central shell/capture
packages below (split between the base and other package lists):

~~~text
quickshell
qt6-imageformats
qt6-multimedia
qt6-multimedia-ffmpeg
qt6-wayland
hyprland
hyprland-guiutils
hyprland-preview-share-picker
uwsm
sddm
pipewire / pipewire-alsa / pipewire-jack / pipewire-pulse
wireplumber
bluez / bluez-tools (profile-gated Bluetooth capability)
networkmanager
power-profiles-daemon
grim
gpu-screen-recorder
slurp
hyprpicker
ffmpegthumbnailer
libvips
imagemagick
mpv
mpv-mpris
wl-clipboard
wtype
tesseract
tesseract-data-eng
zbar
localsend
tensaku
mise-bin
jq
inotify-tools
gum
fontconfig
ttf-jetbrains-mono-nerd-basic
noto-fonts / noto-fonts-cjk / noto-fonts-emoji
~~~

voxtype-bin is not part of the base manifest; it is installed by the
optional dictation flow. V4L2 control tooling and FFmpeg may arrive through
the selected package dependency graph or a platform package, but the source
calls v4l2-ctl, ffmpeg, and ffprobe and they must be present for those paths.
The exact package names are distribution-specific outside the reference
package manager.

## Package-manager and update ownership

Each capability must have one update owner:

| Artifact | Reference owner | Generic rule |
|---|---|---|
| packaged shell/runtime | pacman package | update through the blessed system update |
| first-party shell source | runtime package | reload/restart shell after package update |
| first-party theme | runtime package | theme source is replaced by package update |
| Git third-party plugin | its checkout and plugin update command | fast-forward only, validate after merge |
| hand-authored plugin | user directory | do not overwrite/delete silently |
| Git extra theme | its checkout and theme update command | filter executable/config-bearing files before activation |
| generated active theme | theme setter | regenerate; never hand-edit as source |
| lazy agent CLI | mise global tool | update with blessed mise step |
| Hermes CLI | dedicated installer or Hermes Desktop | never maintain two ownership copies |
| OpenClaw CLI/gateway | package plus user service | package update owns binary; service lifecycle remains explicit |
| local LLM models | LM Studio/Ollama application | optional app-specific removal policy |
| usage records | collector plus user state | atomic per-provider JSON writes |
| capture outputs | user Pictures/Videos or configured directories | capture command owns names/notifications |
| user skills | symlinks to active root | dev-link changes source without copying |
| systemd user units | settings/runtime package | enable/start at first graphical run |
| user customization | user | preserve unless explicit reset |

Do not let a third-party plugin install packages, write system files, or
execute an install hook simply because it has a manifest. The reference add
command only clones, validates, and changes shell state.

## Test and verification matrix

| Area | Reference test/source | What it proves |
|---|---|---|
| CLI routing | test/cli, docs/cli-router.md | command discovery, metadata, help, aliases, collisions |
| shell unit logic | test/shell and test/shell.d/* | pure model/helper contracts and source invariants |
| plugins | plugins-test.sh, plugin add/clone/enable/validate tests | manifest scan, lifecycle, traversal/collision protections |
| plugin trust | plugin-auth-boundary-test.sh | facade wiring and authentication object isolation claims |
| screenshots | screenshot-sanity-test.sh | live shell/bar geometry and fullscreen capture sanity where environment permits |
| recording/webcam | screenrecording-test.sh | device filtering, menu dimensions, webcam math and rules |
| themes | theme staging/user/theme-install tests | source filtering, template/staging behavior, user overlay |
| wallpapers | background-test.sh, video-background-test.sh | background IPC and media/thumbnail/video transitions |
| notifications | notification send/service tests | bus sender, persistence, DND, actions, history |
| AI usage | agent-usage-* tests and agent panel source | collector contracts and usage display logic |
| first-run/update | first-run, update, migration, restart tests | marker/idempotency/order/failure behavior |
| visual acceptance | test/acceptance.d/, visual-verification skill | actual compositor screenshots and interaction |
| full integration | no source-only substitute | package versions, DBus services, hardware, API behavior, reboot/rollback |

The source repository documents ./test/all as the aggregate test entry point,
./test/cli for router/CLI tests, and ./test/shell for the shell test domain.
Graphical acceptance tests are separate and require a running
compositor/session.

## Coverage against the requested hard gate

| Requested concern | Documentation location | Status of evidence |
|---|---|---|
| complete shell lifecycle | 01, 03, 08, 11 | source-inspected; live session not launched by this task |
| first-party plugin lifecycle | 02, 07, 12 | source-inspected across registry, host, manifests, CLI, tests |
| third-party plugin add/update/remove/clone | 02, 12 | source-inspected; arbitrary code remains unsandboxed |
| AI-first essence | 07, 10, 11, 13 | source-inspected; correctly described as agent-first, not embedded model |
| screenshot/recording/OCR/QR/color | 07, 10, 14 | source-inspected, including exact helpers and keybindings |
| dictation | 07, 10, 13, 14 | source-inspected; Voxtype is optional external software |
| notifications | 07, 07a, 14 | source-inspected notification service/sender/indicator integration |
| themes and wallpapers | 04, 07c, 15 | source-inspected; image/video dimensions and transitions recorded |
| logo and icon assets | 04, 15 | source-inspected exact file dimensions and glyph source |
| design/architectural language | 04, 05, 06, 15 | source-inspected exact tokens, dimensions, motion, and ownership |
| frameworks/libraries/tools | 10, 14, 15, 16 | source-inspected import/package/call matrix |
| full repository structure | 11, 12, 13, 15, 16 | source-inspected at commit anchor |

## Remaining verification boundary

Static reading can establish source-defined constants, paths, control flow,
manifest rules, and test intent. It cannot establish:

- that a particular Quickshell/Qt release renders every pixel identically;
- that an installed GPU, monitor transform, camera, PipeWire graph, or portal
  behaves like the development machine;
- that upstream agent APIs, OAuth responses, billing APIs, or desktop app
  installers remain compatible;
- that package repositories contain the listed versions;
- that a real update snapshot can be rolled back successfully;
- that PAM, polkit, SDDM, or session lock activation is safe on a target host;
- that arbitrary third-party plugin code is trustworthy;
- that every visual interaction passes without compositor acceptance testing.

A build claiming exact reproduction must run the source-defined pure tests, shell
tests, graphical acceptance suite, and an explicitly scoped integration matrix.
Report each as source-inspected, unit-tested, integration-tested, or unverified;
never merge those evidence classes into one “fully verified” claim.

## Source cross-check

~~~text
AGENTS.md
README.md
docs/file-layout.md
docs/cli-router.md
docs/omarchy-shell.md
docs/menu.md
docs/notifications.md
docs/update-process.md
docs/testing.md
install/omarchy-base.packages
install/omarchy-other.packages
shell/
bin/
default/
config/
themes/
applications/
etc/
test/
manual/
agents/skills/
~~~

This source map is intentionally split from the feature documents so future
audits can update counts and package names without turning any one blueprint
file into a repository-sized catalog.
