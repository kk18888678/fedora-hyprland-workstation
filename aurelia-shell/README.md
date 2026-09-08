# Aurelia Shell

Aurelia Shell is a standalone Quickshell desktop-shell project. It is kept
under this repository temporarily for development, but the Fedora workstation
project does not deploy, start, or depend on it. It can be developed and tested
while Fedora continues to use Noctalia.

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

### Optional Hyprland provider integration

Aurelia plugin loading and Hyprland global shortcuts are separate boundaries.
To register the Aurelia manifest bindings, including Super+K, install the
explicit user-owned provider bridge:

~~~bash
./aurelia-shell/bin/aurelia-enable-hyprland-provider enable
hyprctl reload
~~~

The bridge loads the standalone provider only when its generated file exists;
Noctalia remains the active desktop shell and the parent configuration remains
unchanged by default. Disable it with:

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
success previews will call this service after the notification slice is
validated; that integration is deliberately not part of the initial service.
Only one session service can own `org.freedesktop.Notifications`; enable this
owner after the other notification daemon has been disabled for the session.

Its normalized layout lives under the `bar` key in
`~/.config/aurelia/shell.json`. The shipped layout places the formatted clock
and weather together in the center, with the screenshot widget on the right.
Weather follows Omarchy's automatic IP-based location flow by default. You
can pin a city or exact coordinates in the weather layout entry when needed:

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

The host intentionally uses explicit rescans instead of a long-lived recursive
filesystem watcher. This keeps the production idle path bounded and avoids
reloading plugins while a security-sensitive or session-lock surface is active.
Use `aurelia-restart-shell` for deterministic source changes; `hyprctl reload`
remains specifically for Hyprland/Lua configuration changes.

The `aurelia-plugin` command validates local plugins, lists/rescans the
resident registry, enables/disables plugins, and can add/update/remove
HTTPS-backed git checkouts. Network and destructive operations require
`--yes`; a newly added plugin remains disabled unless `--enable` is supplied.
