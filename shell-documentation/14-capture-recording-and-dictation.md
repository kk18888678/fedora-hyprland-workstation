# Capture, recording, OCR, and dictation

The reference does not implement every capture action as a QML plugin. It uses
a small command layer for capture and a few shell widgets/indicators to expose
state and launch those commands:

```text
compositor keybinding
  -> command router / capture helper
  -> Wayland/compositor capture tool
  -> file and/or clipboard
  -> notification with optional action
  -> shell indicator refresh
```

The wallpaper/image picker is a shell plugin; screenshot selection,
screen-recording, OCR, QR decoding, color picking, and dictation are external
commands integrated with the shell. A faithful replica must preserve that
ownership boundary.

## Keybindings and menu routes

| Key | Exact action |
|---|---|
| `Print` | `omarchy-capture-screenshot` |
| `Alt + Print` | stop active recorder, otherwise open the screen-record menu |
| `Super + Print` | stop an existing color picker or start `hyprpicker -a` |
| `Super + Ctrl + Print` | `omarchy-capture-text` |
| `Super + Ctrl + C` | open the capture submenu |
| `Super + Alt + [` | resize active webcam overlay smaller |
| `Super + Alt + ]` | resize active webcam overlay larger |
| `Super + Ctrl + .` | open transcode flow |
| `Super + Ctrl + S` | open LocalSend share flow |
| `Super + Ctrl + X` | toggle Voxtype recording, only when `voxtype` is present |
| `F9` press/release | start/stop Voxtype push-to-talk, only when present |

The capture menu has these source-defined routes:

```text
trigger.capture.screenshot
trigger.capture.screenrecord.stop       # visible only while recorder exists
trigger.capture.screenrecord.no-audio
trigger.capture.screenrecord.desktop-audio
trigger.capture.screenrecord.microphone
trigger.capture.screenrecord.webcam      # visible only with capture-capable webcam
trigger.capture.text
trigger.capture.qr
trigger.capture.color
```

The `Alt + Print` binding invokes stop first with `--stop-recording`; a stopped
recorder returns nonzero, so the binding falls through to the screen-record
menu. A second press while recording never opens a picker.

## Shared region picker

`omarchy-capture-region` is the single picker used by screenshots and the
default screen-record flow. It prints a geometry in the compositor’s logical
coordinate space:

```text
X,Y WxH
```

It supports these modes:

| Mode | Behavior |
|---|---|
| `region` | freeform `slurp` selection |
| `windows` | `slurp -r` over active-workspace window and monitor rectangles |
| `smart` (default) | freeform with window/monitor rectangles supplied as hints; a click under 20 square pixels snaps to the containing rectangle |
| `fullscreen` | focused monitor geometry without opening `slurp` |

Monitor geometry divides physical width/height by the monitor scale and swaps
width/height for transforms 1 and 3. Window candidates come from the focused
workspace, exclude hidden clients, and are deduplicated by geometry. If the
cursor is in a gap or on the bar, monitor geometry is the fallback.

Before an interactive picker, the helper starts `hyprpicker -r -z` and waits
`0.1 s`. This freezes the compositor view. `--keep-freeze` prints the freeze
PID as the first output line and leaves cleanup to the caller; screenshot and
recording use this so the capture includes the frozen scene.

While a selection layer with namespace `selection` exists, the Hyprland Lua
bindings install temporary keybindings:

```text
Return       --take-window
Ctrl+Return  --take-fullscreen
Tab          --select-window next
Ctrl+Tab     --select-window prev
Left/Right/Up/Down --select-window direction
```

The bindings are installed once while one or more selection layers are open and
unbound individually after the last layer closes. The temporary selection layer
has no animation and no 1 px border.

Window navigation first computes reachable window centers. It uses a 7×7 grid
of eighth-fraction probe points, closest to center first, and only warps to a
point that resolves back to the intended rectangle. Reading-order navigation
sorts top-to-bottom then left-to-right; directional navigation scores primary
distance plus twice the absolute perpendicular distance. This prevents a
covered or unreachable window from being selected by keyboard navigation.

`--match-monitor` changes an exact monitor-sized result to
`monitor:<name>`. Screen recording uses this to select the recorder’s native
monitor target instead of a scaled region.

## Screenshot pipeline

The executable is `omarchy-capture-screenshot` and its defaults are:

```text
mode       = smart
processing = slurp
editor     = tensaku-edit
directory  = $OMARCHY_SCREENSHOT_DIR
           or $XDG_PICTURES_DIR
           or $HOME/Pictures
```

The command creates the output directory if missing and sends a 2-second
notice. If `slurp` is already running, the command kills it and exits; this is
the “press Print again to dismiss” behavior.

It reads the compositor’s current `cursor:no_hardware_cursors` value, sets
`no_hardware_cursors` to `0` for capture, starts the shared picker with
`--keep-freeze`, and restores the original setting and kills the freeze process
on every exit path.

The supported command shape is:

```text
omarchy capture screenshot [smart|region|windows|fullscreen]
                         [slurp|copy|save]
                         [--editor=<program>]
```

For `slurp` processing:

1. filename is `screenshot-YYYY-MM-DD_HH-MM-SS.png`;
2. `grim -g "$selection"` writes the PNG;
3. the path is printed;
4. the PNG is placed on the Wayland clipboard as `image/png`;
5. a notification includes the image and a click argv for the editor;
6. editor defaults to `tensaku-edit`, override with the environment variable
   or `--editor=`.

The notification is best effort after the file and clipboard succeed. `copy`
pipes `grim` directly to `wl-copy` and does not save a file. `save` writes and
prints the path without clipboard or editor notification. `fullscreen` uses
the focused monitor but otherwise follows the same processing rules.

The editor action is argv-based: the editor program and screenshot path are
separate arguments. Do not implement it by concatenating the screenshot path
into a shell command string.

## Screen-recording pipeline

The executable is `omarchy-capture-screenrecording`. It is a toggle:

```text
if a process matching ^gpu-screen-recorder exists:
    stop and finalize it
else if --stop-recording was requested:
    exit 1
else:
    start a new recording
```

The output directory is:

```text
$OMARCHY_SCREENRECORD_DIR
or $XDG_VIDEOS_DIR
or $HOME/Videos
```

Unlike screenshots, it must already exist. A missing directory produces a
critical 3-second notification and exits 1.

### Target selection

`--fullscreen` targets the focused monitor directly. Otherwise the default
picker returns either `monitor:<name>` or `region:WxH+X+Y`. Logical region
coordinates are passed unchanged to the recorder; gpu-screen-recorder performs
physical scaling itself.

`OMARCHY_SCREENRECORD_USE_PORTAL=true` opts into the recorder’s portal backend
and skips the built-in picker. The reference leaves this off by default because
the KMS path avoids known EGL DMA-BUF modifier failures; the portal path exists
for HDR, external-GPU monitors, and window capture.

If a focused monitor exceeds 3840×2160 in either dimension and no explicit
`--resolution` is supplied, the default resolution is `3840x2160`. Otherwise
the resolution argument is `0x0`, which leaves native size. A user-provided
`--resolution=<size>` is forwarded as `-s <size>`.
### Recorder arguments and audio

The recorder starts with:

~~~text
gpu-screen-recorder <target arguments>
  -k auto
  -f 60
  -fm cfr
  -fallback-cpu-encoding yes
  -o <Videos>/screenrecording-YYYY-MM-DD_HH-MM-SS.mp4
~~~

Audio flags are composed from the selected mode:

~~~text
desktop audio only       -> -a default_output -ac aac
desktop + microphone     -> -a 'default_output|default_input' -ac aac
no audio                 -> no -a/-ac flags
~~~

The process is backgrounded. The launcher waits in 200 ms intervals until the
process exits or the output file appears; only then does it store the path in
/tmp/omarchy-screenrecord-filename and refresh the bar indicators.

Stopping sends SIGINT, not SIGTERM, because the recorder needs SIGINT to close
the MP4 correctly. It waits at most 5 seconds in 100 ms intervals. If the
process remains, it sends SIGKILL and emits a critical “video may be corrupted”
notification.

Successful finalization:

1. inspect the first 0.2 seconds with ffprobe for discardable packets;
2. use video stream-copy unless discardable warmup packets require re-encode;
3. trim the first 0.1 s with -ss 0.1;
4. when audio exists, mute it until 0.4 s, fade in for 0.05 s, and run
   loudness normalization I=-14:TP=-1.5:LRA=11;
5. write <stem>-processed.mp4 and replace the original only if FFmpeg
   succeeds;
6. generate <stem>-preview.png from timestamp 0.1 s, quality 2;
7. notify for 10 seconds, with a thumbnail and click argv mpv -- <file>;
8. delete the preview after 2 seconds.

### Webcam overlay

omarchy-capture-screenrecording-with-webcam enumerates capture-capable V4L2
devices. It filters out nodes without Video Capture, collapses each device
group to the first capture-capable node, and exits with a critical notification
if none exist. Multiple devices are selected through a menu with width 520 px
and maximum height 520 px.

It then invokes the recorder with desktop audio, microphone audio, webcam, and
the selected device. If no device was explicitly selected, the normal recorder
uses the first line from the same filtered device list.

The webcam preview is an mpv Wayland window:

~~~text
av://v4l2:<device>
profile=low-latency, untimed, no-cache
crop=ih*8/9:ih
title=WebcamOverlay
wayland-app-id=WebcamOverlay-<small|medium|large>
no border, no audio, no OSC, OSD level 0
~~~

It probes for the mapped window for up to 40 × 0.05 s = 2 s, then applies the
size and position and waits another 0.6 s before capture. The compositor
window rules pin it, remove initial focus/dim, force opacity 1 1, and place it
40 px from the bottom-right edge.

The portrait aspect is 8:9. Presets scale from the recording/monitor height:

| Preset | Width | Height | Position from right/bottom | Relative size |
|---|---:|---:|---|---|
| small | monitor_h × 4/25 | monitor_h × 9/50 | 40 px margins | 16% × 18% |
| medium | monitor_h × 2/9 | monitor_h / 4 | 40 px margins | 22.22% × 25% |
| large | monitor_h × 3/10 | monitor_h × 27/80 | 40 px margins | 30% × 33.75% |

The default is medium. When the recording is a region, the runtime file
XDG_RUNTIME_DIR/omarchy-screenrecord-region contains WxH+X+Y, and resize
anchors to that region. Otherwise it anchors to the monitor’s logical geometry.
A region too narrow for the presets caps the ladder to anchor_width - 2×40 while
preserving distinct sizes and the 8:9 ratio.

smaller and larger step through the three presets; reset means medium. Resize
does nothing when there is no window titled WebcamOverlay.

## OCR, QR, and color capture

### OCR text extraction

omarchy-capture-text repeats the freeze-plus-selection start, captures the
region to stdout, and runs:

~~~text
tesseract stdin stdout
  --oem 1
  --psm 6
  -l ${OMARCHY_OCR_LANGS:-eng}
  --dpi 300
  -c preserve_interword_spaces=1
~~~

Nonempty OCR output is copied with wl-copy and acknowledged by a low-urgency
glyph notification. Empty selection or empty OCR output is a no-op/failure and
does not write a file.

### QR-only decoding

omarchy-capture-qr uses the same freeze and picker, then runs zbarimg with all
symbologies disabled except QR code. The decoded value is copied using
wl-copy --sensitive. It is never printed, put in the notification, or left in
clipboard history. A missing result gives a critical “No QR code found” notice.

### Color picker

The menu and Super + Print use the direct command:

~~~text
pkill hyprpicker || hyprpicker -a
~~~

Thus the same key both cancels a running color picker and launches a new
eyedropper. Color output is delegated to hyprpicker’s clipboard integration.

## Transcoding and sharing

omarchy-transcode uses a menu file picker over $HOME/Pictures and
$HOME/Videos by default, or a supplied --path. The file picker uses width
800 px and maximum height 500 px.

Pictures:

| Choice | Max width expression |
|---|---:|
| high | 3160 px |
| medium | 2160 px |
| low | 1080 px |

JPEG uses ImageMagick quality 85 and -strip. PNG uses -strip, filter 5,
compression level 9, strategy 1, and excludes all PNG chunks. Video output is
named <stem>-<resolution>.<format>:

| Format | Resolution | Encoder |
|---|---|---|
| MP4 | 4k | libx265, preset slow, CRF 24, AAC 192k |
| MP4 | 1080p/720p | libx264, preset fast, CRF 23, AAC 192k |
| GIF | 4k/1080p/720p | 10 fps, Lanczos scale, palettegen/paletteuse |

All video MP4 outputs use -movflags +faststart. The result is copied to the
clipboard as a file:// URI list and acknowledged by notification.

The sharing command uses LocalSend’s headless sender in a collected user
systemd service. Clipboard sharing first writes a temporary text file and sends
that file; it intentionally leaves cleanup to system temporary-file policy so
the detached LocalSend process can read it.

## Voxtype dictation lifecycle

Dictation is optional AI-assisted voice input, not a shell plugin and not a
coding-agent provider. The install flow is:

~~~text
confirm roughly 150 MB download
  -> install wtype and voxtype-bin
  -> copy default/voxtype/config.toml to ~/.config/voxtype/
  -> voxtype setup --download --no-post-install
  -> if Vulkan hardware: voxtype setup gpu --enable (best effort)
  -> voxtype setup systemd
  -> hyprctl reload
  -> restart shell
  -> ready notification
~~~

The shipped configuration is:

~~~toml
state_file = "auto"
[hotkey]
enabled = false
[audio]
device = "default"
sample_rate = 16000
max_duration_secs = 60
pause_media = true
[whisper]
model = "base.en"
language = "en"
translate = false
[output]
mode = "type"
fallback_to_clipboard = true
type_delay_ms = 1
~~~

The shipped sample configuration comments describe `ydotool` as the typing
provider, while the installer explicitly provisions `wtype`; the actual text
injection choice is delegated to the installed Voxtype runtime. This is a
source-level mismatch and is recorded intentionally, not silently corrected
in a claimed 1:1 port.

Voxtype’s automatic state file is under XDG_RUNTIME_DIR/voxtype/state and
reports idle, recording, or transcribing. The bar indicator follows
omarchy-voxtype-status, which execs:

~~~text
setpriv --pdeathsig TERM voxtype status --follow --extended --format json
~~~

This keeps the follower as a direct child and guarantees it dies with the shell.
The indicator is active only for `recording` and opens the Voxtype
configuration on click. The source also assigns a transcribing glyph when the
state is `transcribing`, but `BarIndicator` selects `activeText` only when
`active` is true; therefore the rendered transcribing state currently falls
back to the inactive microphone glyph. Its status process is started only when
the command exists, so a fresh installation has no dictation binding or active
indicator.

The configuration and model commands open voxtype configure and
voxtype setup model in a presented terminal, then restart the shell. Removal
disables/stops voxtype.service, reloads the user manager, removes voxtype-bin,
~/.config/voxtype, and ~/.local/share/voxtype, and reloads Hyprland. The
reference does not preserve those Voxtype directories during removal.

## Required dependencies

The exact base package manifest names these capture dependencies:

~~~text
grim
gpu-screen-recorder
hyprpicker
slurp
tesseract
tesseract-data-eng
ffmpegthumbnailer
libvips
imagemagick
wl-clipboard
wtype
zbar
qt6-multimedia
qt6-multimedia-ffmpeg
mpv
mpv-mpris
localsend
tensaku
~~~

voxtype-bin is optional and installed by the dictation flow. The scripts also
invoke ffmpeg, ffprobe, and v4l2-ctl; their providers are not direct lines in
the base manifest shown above and must be supplied by the platform dependency
graph. The compositor must expose Hyprland JSON for monitors, clients, cursor
position, devices, layer events, and dispatch; the picker and webcam logic
cannot be reproduced from generic Wayland alone.

## Source cross-check

~~~text
manual/11-text-extraction-dictation.md
manual/12-screenshots-recording.md
default/hypr/bindings/utilities.lua
default/hypr/bindings/voxtype.lua
default/hypr/apps/screenshot-selection.lua
default/hypr/apps/webcam-overlay.lua
default/voxtype/config.toml
default/omarchy/omarchy-menu.jsonc
bin/omarchy-capture-region
bin/omarchy-capture-screenshot
bin/omarchy-capture-screenrecording
bin/omarchy-capture-screenrecording-with-webcam
bin/omarchy-capture-text
bin/omarchy-capture-qr
bin/omarchy-capture-webcam-list
bin/omarchy-capture-webcam-resize
bin/omarchy-menu-images
bin/omarchy-transcode
bin/omarchy-menu-share
bin/omarchy-voxtype-install
bin/omarchy-voxtype-remove
bin/omarchy-voxtype-status
shell/plugins/bar/indicators/ScreenRecording.qml
shell/plugins/bar/indicators/Dictation.qml
shell/plugins/image-picker/
test/shell.d/screenshot-sanity-test.sh
test/shell.d/screenrecording-test.sh
test/shell.d/voxtype-invitation-test.sh
~~~

The exact source has no dedicated omarchy-capture-color binary; color capture
is the direct hyprpicker menu action. It also has no screenshot or recording
QML plugin; the shell indicator and notification integrations are the shell
side of those command pipelines.
