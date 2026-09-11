# Aurelia Shell

Aurelia owns the desktop background when its background service is enabled.
The resident aurelia.background service renders one always-mapped wallpaper
surface per screen, supports still images and looping video, and falls back to
the active Aurelia palette instead of exposing a black desktop when no media is
selected. The resident aurelia.image-picker overlay and these commands manage
data-only themes:

    aurelia-theme list
    aurelia-theme set "Tokyo Night"
    aurelia-theme catalog --json
    aurelia-theme-preview themes
    aurelia-theme-preview backgrounds
    aurelia-theme-bg set ~/Pictures/Wallpapers/example.png
    aurelia-theme-bg next
    aurelia-theme-color --all

The Omarchy-aligned shortcuts are `Super + Ctrl + Space` for the background
carousel and `Super + Shift + Ctrl + Space` for the theme carousel. Generated
preview links and media thumbnails live under
`${XDG_CACHE_HOME:-$HOME/.cache}/aurelia/` and nearby images are activated
lazily as selection moves.

The bundled catalog contains the 22 stock themes from the inspected Omarchy
reference, with exact palettes, previews, unlock artwork, icons, backgrounds,
and inert metadata. `colors.toml` is the canonical palette format; older
`theme.conf` files remain supported for custom Aurelia themes. User bundles
live under `~/.config/aurelia/themes/<name>/`; additional per-theme backgrounds
live under `~/.config/aurelia/backgrounds/<name>/`. Aurelia does not execute
theme Lua, shell hooks, terminal launch configuration, or arbitrary application
configuration.

Aurelia Shell is a standalone Quickshell desktop-shell project. The VM profile
uses it as the post-login session shell while retaining Noctalia as the greetd
login greeter. The physical workstation profile continues to use Noctalia as
its post-login shell.

The package owns the host process, shared services, plugin registry, plugin
lifecycle, and stable shell IPC. It does not own the business logic of
individual desktop capabilities.

Run the shell-owned contract suite from the repository root with:

```bash
./aurelia-shell/tests/run.sh
```

For source-checkout development, start the resident host and its IPC console
in one reusable tmux session:

~~~bash
./aurelia-shell/bin/aurelia-dev-tmux
~~~

The first pane runs the host. The second waits for readiness, prints the
loaded plugins, and remains available for IPC commands. The workstation
installer owns tmux through packages/base.txt, so both supported profiles
include the development utility.

For a single source-checkout restart after changing Aurelia host or QML code,
run:

```bash
./aurelia-shell/bin/aurelia-restart-shell
```

The source launcher and IPC client auto-detect the checkout when invoked from
`aurelia-shell/bin/`; development environment exports are not required. The
restart command only selects and restarts Aurelia's Quickshell instance. It
does not reload Hyprland or touch Noctalia.

### Omarchy-style development reload

Development launches watch only the first-party and user plugin trees. Saving
a plugin QML, JavaScript, manifest, or related data file debounces a registry
rescan and unloads/reloads the changed plugin entry points inside the resident
host while keeping the bar host mapped. The Command Center exposes the same
boundary under **Aurelia Shell**:

```text
Hot Reload Aurelia Plugins  -> reload plugin entry points in place
Restart Aurelia Shell       -> replace the resident Quickshell host
```

Changes to `shell.qml`, `services/`, the shared theme, or the Hyprland Lua
configuration still require the restart command. If the host is not running,
the Command Center cannot exist; start it from a terminal with
`./aurelia-shell/bin/aurelia-launch-shell` and then use the Command Center for
the normal development loop.

### Optional Hyprland provider integration

Aurelia plugin loading and Hyprland global shortcuts are separate boundaries.
To register the Aurelia manifest bindings, including Super+K and SUPER+TAB,
install the explicit user-owned provider bridge:

~~~bash
./aurelia-shell/bin/aurelia-enable-hyprland-provider enable
hyprctl reload
~~~

The bridge loads the standalone provider only when its generated file exists;
the parent configuration remains unchanged by default. Disable it with:

~~~bash
./aurelia-shell/bin/aurelia-enable-hyprland-provider disable
hyprctl reload
~~~

## Plugin model

First-party plugins live in `plugins/` and use a `manifest.json` with the
Omarchy-compatible fields `schemaVersion`, `id`, `name`, `version`, `kinds`,
and `entryPoints`. User plugins live in
`~/.config/aurelia/plugins/<plugin-id>/`. The `aurelia.` id namespace is
reserved for first-party plugins.

The shell discovers manifests without executing plugin code. Invalid manifests,
unsafe entry points, symlinked plugin trees, and duplicate ids are rejected.
Third-party plugins are disabled until explicitly enabled in
`~/.config/aurelia/shell.json` and then run with the same host privileges as
the shell. Only add plugin code that you have reviewed.

The selected bar also accepts explicit user modules in its layout. QML modules
must stay under `~/.config/aurelia/bar/modules/` (or the configured XDG config
equivalent). Command modules use a structured `command` argv array; Aurelia
rejects shell strings, unsafe path components, and commands outside the normal
system or user-local binary roots, then wraps refreshes in a bounded timeout:

```json
{
  "bar": {
    "id": "aurelia.bar",
    "layout": {
      "right": [
        { "id": "date", "type": "command", "command": ["/usr/bin/date", "+%H:%M"] }
      ]
    }
  }
}
```

## IPC

The resident host exposes the `shell` target:

```text
shell ping
shell summon <plugin-id> <payload-json>
shell hide <plugin-id>
shell toggle <plugin-id> <payload-json>
shell call <plugin-id> <method> <argument>
shell rescanPlugins
shell reloadConfig
shell setPluginEnabled <plugin-id> <true|false>
shell listPlugins
```

The Command Center keeps its module catalog separate from shell/plugin
enablement. Inspect or change implemented modules through its stable plugin
target; state is stored under `${XDG_CONFIG_HOME:-$HOME/.config}/aurelia/`:

```text
aurelia-shell aurelia.launcher listModules
aurelia-shell aurelia.launcher setModuleEnabled files false
```

Unimplemented modules remain disabled until their provider is added and
validated.

The built-in `Updates` module opens a dedicated terminal workflow with the
repository-owned Fastfetch About layout, Fedora/Flatpak update discovery, and
one flat list of available updates. The terminal offers `Install all` or
checked selective updates; transactions run behind a per-session lock and
bounded timeouts.

The built-in `About` module opens the Aurelia About surface through
`bin/workstation-about`. It follows the configured terminal (`kitty` is the
project default, with `foot`, `ghostty`, `alacritty`, `gnome-terminal`,
`konsole`, and `xterm` supported as fallbacks), renders the repository-owned
Fastfetch layout with native terminal graphics, and uses the four colours from
`config/branding/aurelia-mark.svg` rather than a desktop theme colour. The
default mark is rendered through the terminal's native image protocol from the
1024x1024 Aurelia PNG; imported PNG/SVG branding is rasterized at high density
and normalized to a native PNG.

The user-owned native About mark lives at
`~/.config/aurelia/branding/about.png`. About never reads the terminal-cell
logo or a user Fastfetch configuration, so its native PNG path cannot silently
fall back to ASCII/Chafa output. The matching controls are available from the
terminal:

```text
aurelia-branding-about image ~/Pictures/aurelia.png
aurelia-branding-about reset
```

About windows use the stable identity `org.aurelia.about`, are centered and
floating under Hyprland, and remember a content-sized fit under
`~/.local/state/aurelia/windows/about.fit`.

The built-in `Package Manager` module opens `workstation-packages`, the
source-aware Fedora/Flatpak/Aurelia package browser. It searches configured DNF
repositories, Flatpak remotes, and explicitly added official GitHub release
sources, shows provenance, and lets the user explicitly install, adopt, remove,
or forget packages through the tracked `packages/user-managed.tsv` desired
state. Daily catalog refresh is optional and never installs package updates.

Plugins may expose their own target. The Keybindings plugin is
`aurelia.keybindings`; the legacy `keybindings` and `hotkeys` targets remain
thin compatibility aliases.

The resident bar starts with the Aurelia Shell host. It can still be hidden,
shown, or toggled through IPC:

```text
shell summon aurelia.bar '{}'
shell hide aurelia.bar
shell toggle aurelia.bar '{}'
```

Clicking the Aurelia logo opens `aurelia.launcher`, the keyboard-first Aurelia
Command Center. The historical plugin id remains stable for existing IPC and
shortcut configuration; its hidden command service remains resident with the
panel opening only when summoned.

The notification center is exposed by `aurelia.notifications`:

```text
aurelia-shell aurelia.notifications openCenter
aurelia-shell aurelia.notifications showHistory
aurelia-shell aurelia.notifications toggleDnd
```

It is an Aurelia-owned Freedesktop notification server, not a Noctalia
notification surface. Do Not Disturb and bounded notification history are
stored under `${XDG_STATE_HOME:-$HOME/.local/state}/aurelia/`. Screenshot
success previews now call this service in-process after a successful capture.
Only one session service can own `org.freedesktop.Notifications`; enable this
owner after the other notification daemon has been disabled for the session.
When another owner is detected, Aurelia leaves the standard server unloaded
and reports the condition through its center instead of generating registration
warnings; first-party screenshot previews still use the in-process path.
The center separates Inbox from transient popup lifetime. Popup expiry never
removes an Inbox row; each Inbox card has an Archive action, and Open/Dismiss
also archive only that individual notification. ChatGPT completion notices
remain inbox-persistent while the user is away.

Its normalized layout lives under the `bar` key in
`~/.config/aurelia/shell.json`. The shipped layout places the formatted clock
and weather together in the center, with Bluetooth, display, screenshot, and
power widgets on the right. On hardware with a BlueZ adapter, the Bluetooth
widget lists paired and discovered devices and supports pair, connect,
disconnect, forget, and reboot-persistent radio power actions. Its discovery
session is stopped with bounded ownership cleanup when the popup closes.
Toggle it through `shell toggle aurelia.bluetooth '{}'` or `Super + Ctrl + B`.
Weather follows Omarchy's automatic IP-based location flow by default. You can
pin a city or exact coordinates in the weather layout entry when needed:

```json
{
  "id": "aurelia.weather",
  "location": "London",
  "units": "metric"
}
```

Additional widgets can be registered by adding a manifest entry point with
kind `bar-widget`; the bar host loads only the configured, enabled widgets.
`shell listPlugins` also returns each manifest's validated `icon` name for
launcher and plugin-management UIs.

The production launcher keeps the plugin watcher disabled. This keeps the
normal idle path bounded and avoids reloading plugins while a
security-sensitive or session-lock surface is active. The development watcher
is limited to plugin roots and is not a replacement for the explicit host
restart boundary. `hyprctl reload` remains specifically for Hyprland/Lua
configuration changes.

The workspace overview is provided by `aurelia.workspace-switcher`. Its
Mission Control-inspired overlay is opened with `SUPER + TAB`; repeated presses
cycle the selected workspace, while Enter activates it, Escape closes the
overview, and arrow keys move the selection. Window cards use Quickshell's
single-frame Hyprland toplevel capture when supported and show a safe app/title
fallback otherwise.

The `aurelia-plugin` command validates local plugins, lists/rescans the
resident registry, enables/disables plugins, and can add/update/remove
HTTPS-backed git checkouts. Network and destructive operations require
`--yes`; a newly added plugin remains disabled unless `--enable` is supplied.
