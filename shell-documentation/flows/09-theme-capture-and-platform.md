# Theme, wallpaper, capture, and platform flows

This document traces the shell-adjacent workflows that start in compositor
bindings or command scripts and end in a visible shell update, a file/clipboard
result, or a classified installation state. The exact command arguments and
dimensions are retained in 11-full-platform-lifecycle.md,
14-capture-recording-and-dictation.md, and
15-theme-wallpaper-and-cross-app-sync.md.

## Theme application flow

### Source and resolution

The theme command resolves a name from packaged or user theme directories. A
Git-installed theme is cloned into the user theme namespace and then handled
as untrusted input. A hand-authored user theme and a Git checkout are not the
same source class.

The requested name is normalized by stripping markup, lowercasing, replacing
spaces with dashes, and rejecting empty, dot-prefixed, or slash-containing
names. The theme list combines user and packaged names, de-duplicates them,
sorts them, and gives user content precedence for equal names.

### Serialize, stage, and commit

Theme application is serialized by a runtime lock. The critical sequence is:

~~~text
acquire theme-set lock
    -> remove previous generated next-theme directory
    -> create clean next-theme directory
    -> copy packaged theme
    -> overlay user theme
    -> apply Git top-level denial/recursive copy rule
    -> generate colors.toml and all template outputs
    -> select next background
    -> remove current generated theme
    -> rename next-theme to current-theme
    -> write normalized theme name
    -> update current/background symlink
    -> tell running shell to load colors and shell tokens
release lock
    -> retint slower applications and run user hook
~~~

The current directory is replaced only after generation reaches the swap step.
An incomplete next directory must not become active. A failed external
retinting step must not erase the already committed active theme.

### Git-theme input boundary

For a Git checkout, top-level Lua files, named terminal/editor configs, and
symlinks are excluded according to the source list. Top-level directories are
copied recursively by a separate helper that skips symlinks but does not
reapply the denied-name test to nested files. Ordinary star-glob copying also
excludes dotfiles. This narrow behavior is source-defined and must not be
silently replaced with a stronger recursive policy in a claimed 1:1 port.

### Color and template output

The color parser normalizes legacy ANSI and semantic names, derives missing
roles, and writes generated shell/application values. The template generator
uses user templates before packaged templates and emits each output only when
that output is not already present.

A shell.toml in the theme replaces the generated shell template. A
shell.<section>.toml file replaces one generated section. The live shell then
layers the user shell.toml over active theme values.

## Wallpaper/background flow

### Selection

Background selection combines one-level candidates from the user background
directory and generated active-theme backgrounds. Supported still/video
extensions are:

~~~text
jpg jpeg png gif bmp webp mp4 m4v mov webm mkv avi
~~~

Candidates are sorted by full path. The current filename is preserved across a
theme change when it exists in the next theme; otherwise the first sorted
candidate is chosen. Repeated selection wraps around the candidate list.

### Renderer transition

The background service reads the current background symlink and creates one
rendering surface per screen. Image-to-image changes use the source 420 ms
InOutCubic reveal. Video changes and instant requests swap immediately to avoid
decoding two full videos.

Theme color/shell payloads are held with a 300 ms fallback timer. If a reveal
exists, colors are applied at reveal start; otherwise they apply immediately.
Style refresh follows Color.loadShell so typography changes land with the
background transition.

The renderer disables video playback when the session lock or screensaver
covers the session, when a fullscreen cover applies to that output, or when
the power-saver state requires it. DPMS and screen return state must not leave a
video decoder running behind a covered surface.

### Image-picker round trip

The image picker is a separate host-loaded overlay. A caller sends an
image-selector request with directories, optional rows, selected path,
selection/done files, labels, and filterability. The host decodes the payload
and summons the picker.

~~~text
request
    -> requestSerial increments
    -> use supplied/cached rows or run list.sh
    -> accept scan only for matching serial
    -> load image rows
    -> set opened true
    -> wait for layout settled
    -> reveal carousel and focus it
~~~

Escape clears filter first and cancels only with an empty filter. Enter writes
the selected path to the selection file and truncates the done file after a
matching apply serial exits. Cancel completes the done file without a
selection, clears request state, and closes. A release queue serializes done
file cleanup. Stale scan/apply output cannot reveal or close a newer request.

## Capture menu and binding flow

The compositor binding invokes a command or menu route, not a screenshot QML
plugin:

~~~text
keybinding/menu route
    -> command router
    -> optional shared region picker/freeze
    -> capture/record/OCR/QR/color helper
    -> file and/or clipboard result
    -> notification or shell indicator update
~~~

The source bindings are:

~~~text
Print                 -> screenshot
Alt+Print             -> stop recording, or screen-record menu
Super+Print           -> stop color picker, or hyprpicker -a
Super+Ctrl+Print      -> OCR text capture
Super+Ctrl+C          -> capture menu
Super+Ctrl+.          -> transcode
Super+Ctrl+S          -> LocalSend share
Super+Ctrl+X          -> Voxtype toggle
F9 press/release      -> Voxtype push-to-talk
~~~

The Alt+Print stop-first branch is significant: stop-recording returns
nonzero when no recorder exists, and only then does the record menu open.

## Shared region-picker flow

The picker starts hyprpicker -r -z and waits 0.1 seconds so the compositor
scene is frozen before capture. With keep-freeze it prints a freeze PID for the
caller to clean up. It reports:

~~~text
X,Y WxH
~~~

Modes:

~~~text
region     -> freeform slurp
windows    -> slurp -r over focused-workspace/monitor rectangles
smart      -> freeform plus snap-to-rectangle for a click under 20 px²
fullscreen -> focused-monitor geometry without slurp
~~~

Monitor geometry is converted from physical to logical coordinates by scale and
transform. Window candidates exclude hidden clients and deduplicate geometry.
Gap/bar clicks fall back to monitor geometry.

While a selection layer exists, temporary compositor bindings provide
Return, Ctrl+Return, Tab/Ctrl+Tab, and directional selection. They are installed
once for all open selection layers and removed after the last closes.

## Screenshot flow

The screenshot command defaults to smart mode, slurp processing, the configured
editor, and the Pictures directory fallback. It:

~~~text
stop a prior slurp if already running
    -> notify selection starting
    -> preserve cursor:no_hardware_cursors
    -> disable hardware cursor for capture
    -> freeze scene
    -> obtain region/monitor geometry
    -> grim capture
    -> restore cursor setting and freeze process on every exit path
    -> process result
~~~

Save mode writes screenshot-YYYY-MM-DD_HH-MM-SS.png. Slurp mode also puts the
PNG on the Wayland clipboard and sends a notification with an argv editor
action. Copy mode pipes directly to wl-copy without saving; save mode prints
the file and does not notify/editor-launch. An editor receives the program and
file path as separate argv entries.

## Screen-recording flow

The recorder command is a toggle:

~~~text
matching gpu-screen-recorder exists -> SIGINT stop/finalize
--stop-recording with no process   -> exit 1
otherwise                          -> select target and start
~~~

Selection uses fullscreen monitor geometry or the shared region picker. Portal
mode is opt-in. The default recorder uses 60 fps CFR, automatic codec,
fallback CPU encoding, and a timestamped MP4 path. Desktop/microphone/no-audio
choices determine the exact audio argv.

Stop waits up to 5 seconds in 100 ms intervals, then SIGKILLs a recorder that
will not exit and sends a corruption warning. Normal finalization optionally
trims the first 0.1 seconds, normalizes audio, creates a preview, sends an
action notification with an mpv argv, and deletes the preview after 2 seconds.
The original is replaced only after processed output succeeds.

The webcam wrapper filters capture-capable V4L2 devices, selects one, starts
the WebcamOverlay mpv window, waits up to 2 seconds for it, resizes/positions
it, waits 0.6 seconds, then starts recording. Resize commands use the three
source presets and do nothing if the titled window is absent.

## OCR, QR, color, transcode, and sharing

~~~text
OCR -> freeze/select -> tesseract stdin/stdout -> copy non-empty text
QR  -> freeze/select -> zbarimg QR-only -> wl-copy --sensitive; never notify value
color -> pkill hyprpicker, or hyprpicker -a
transcode -> image picker -> exact image/video encoder -> file clipboard + notice
share -> LocalSend headless sender; clipboard share stages a temporary file
~~~

OCR uses OEM 1, PSM 6, configured language, 300 DPI, and preserved word
spaces. QR data is not printed or put into notification/history. Transcode
keeps the source resolution/format matrix and only reports success after output
exists.

## Dictation flow

Dictation is optional external daemon integration:

~~~text
install request
    -> install wtype and voxtype-bin
    -> copy/configure Voxtype
    -> setup/download model
    -> optional Vulkan setup
    -> user systemd service setup
    -> Hyprland reload and shell restart
    -> status follower and indicator
~~~

The indicator starts only when voxtype exists. Its follower is a pdeathsig
child, so it dies with the shell. The status flow is idle/recording/
transcribing, but the reference rendered transcribing glyph falls through to
the inactive microphone glyph because active is true only for recording.

Toggle/configure/model actions are command-driven. Removal stops/disables the
user service, removes the provisioned package and source-defined Voxtype
directories, reloads Hyprland, and does not turn absence into a shell error.

## Platform install/update flow

The platform lifecycle is:

~~~text
prepare
    -> validate platform, dependencies, provenance, and state
    -> stage packages/configuration/artifacts
validate
    -> prove login-critical prerequisites and desired state
activate
    -> apply next-boot graphical session state
    -> first login/session autostart
~~~

Package ownership, direct artifact verification, failure classes, exit codes,
lock/interruption handling, migration, update, and recovery are fully specified
in 11-full-platform-lifecycle.md. The shell flow must not turn optional
capture/theme/AI failures into a login-critical activation failure.

## Acceptance checks

1. Apply a packaged, hand-authored, and Git theme. Verify name normalization,
   staging/swap, top-level filter, nested-directory quirk, generated templates,
   live shell retint, and application retint.
2. Switch still and video backgrounds and test image reveal, instant swap,
   lock/screensaver cover, DPMS, and screen return.
3. Run screenshot in every mode, cancel the picker, fail grim, and verify
   cursor/freeze restoration and notification boundaries.
4. Start/stop screen recording with every audio/webcam/portal branch, including
   forced stop and finalization timeout.
5. Run OCR, QR, color, transcode, and sharing flows with empty/failing output.
6. Install, toggle, configure, and remove dictation; verify shell behavior with
   and without the optional daemon.
7. Execute platform prepare, validation failure, optional failure, interruption,
   rerun, update, migration, and next-boot activation scenarios.

