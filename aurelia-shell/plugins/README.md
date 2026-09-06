# Aurelia Shell Plugins

This directory contains first-party Aurelia Shell plugins. First-party and
user plugins share the same manifest contract; only their source roots differ.

## Minimal panel plugin

```json
{
  "schemaVersion": 1,
  "id": "example.weather",
  "name": "Weather",
  "version": "1.0.0",
  "kinds": ["panel"],
  "entryPoints": { "panel": "Panel.qml" }
}
```

The entry-point file is a QML `Item`. The host injects `aureliaPath`, `shell`,
`manifest`, and `pluginRegistry` after URL loading. These properties must have
safe defaults because URL-loaded QML is constructed before `Loader.onLoaded`.
Panel, overlay, and menu entry points should implement `open(payloadJson)` and
`close()`. Use plugin-scoped IPC for direct component operations.

Plugins execute in the resident shell process and are not sandboxed. Review
third-party source before enabling it. Keep plugin code self-contained and use
the shell services/IPC boundary rather than reaching into another plugin's
internal ids.
