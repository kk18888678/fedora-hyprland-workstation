# Aurelia Shell

Aurelia Shell is the resident Quickshell desktop host for the Fedora Hyprland
Workstation. The package owns the host process, shared services, plugin
registry, plugin lifecycle, and stable shell IPC. It does not own the business
logic of individual desktop capabilities.

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

Plugins may expose their own target. The Keybindings plugin is
`aurelia.keybindings`; the legacy `keybindings` and `hotkeys` targets remain
thin compatibility aliases.

The host intentionally uses explicit rescans instead of a long-lived recursive
filesystem watcher. This keeps idle resource use bounded and avoids reloading
plugins while a security-sensitive or session-lock surface is active.

The `aurelia-plugin` command validates local plugins, lists/rescans the
resident registry, enables/disables plugins, and can add/update/remove
HTTPS-backed git checkouts. Network and destructive operations require
`--yes`; a newly added plugin remains disabled unless `--enable` is supplied.
