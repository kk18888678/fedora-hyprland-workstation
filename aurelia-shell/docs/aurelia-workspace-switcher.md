# Aurelia Workspace Overview: Commit-on-Modifier-Release

This document records the mechanism behind Alt+Tab-style activation in the
`aurelia.workspace-switcher` Mission Control overlay, and why it is implemented
through the Hyprland Lua keybinding provider rather than a declarative release
bind.

## Behaviour

While the overview is open and the user cycles with `SUPER + TAB`, releasing
`SUPER` activates the currently selected workspace immediately. This matches
Alt+Tab on other systems and does not require pressing Enter.

The retained activation paths are unchanged:

- `Enter` / `Return` / `Space` activate the selected workspace.
- Clicking a workspace card activates that workspace.
- `Esc` and clicking the backdrop close without activating.
- The mouse wheel and arrow / Home / End keys navigate the selection.
- Cyclic wrap-around is preserved in both selection modes.
- Pointer hover never changes the selection; selection follows explicit input.

## Why not a declarative release bind

Hyprland's Lua bind options expose a `release` flag (`release = true`, the Lua
equivalent of the hyprlang `bindr` / `bindrt` keywords):

```lua
hl.bind(keys, dispatcher, { release = true })
```

The release flag is keyed to the bind's **own key**. For a `SUPER + TAB` bind,
the release event that matches is the release of `TAB`, not the release of
`SUPER`. On the supported Hyprland release (0.56.x) the matcher requires the
released key to equal the bind key (`Tab`), so a `SUPER + TAB` release bind
fires as soon as the user lets go of `TAB` while still holding `SUPER`. That
would commit in the middle of a multi-tab cycle and break repeated cycling:

```text
SUPER down -> TAB down -> TAB up  (release bind fires: WRONG)
                        ^ user still holding SUPER and expects to keep cycling
```

Binding the bare `SUPER` key release (`SUPER_L` / `SUPER_R`) is also not a good
fit. It is layout/keycode specific, can only be scoped by a "is the overview
open" check the compositor does not possess, and a global `SUPER` release bind
would have to run an IPC round trip for every ordinary `SUPER` shortcut.

## Chosen mechanism

The keybinding provider (`dotfiles/hypr/keybind.lua`) subscribes to the
compositor's `input.keyboard.key` Lua event:

```lua
hl.on("input.keyboard.key", function(keycode, _time, state) ... end)
```

This event reports every raw key event, including modifier release, to Lua
**before** keybind consumption and independent of which layer surface holds
keyboard focus. The provider:

1. Reads the optional declarative `release_commit` companion that the plugin
   attaches to its `SUPER + TAB` action
   (`plugins/aurelia.workspace-switcher/keybindings.lua`).
2. Arms that companion when the gated press binding fires, so ordinary `SUPER`
   shortcuts never pay an IPC cost on release.
3. On the release keycode for the declared modifier (`SUPER` -> XKB
   `SUPER_L` 133 / `SUPER_R` 134), dispatches the companion through the bounded
   Aurelia Shell IPC client and disarms.

The companion is a normal bounded plugin IPC:

```text
aurelia-shell shell call aurelia.workspace-switcher release '{}'
```

The plugin remains the single mutation owner. `WorkspaceSwitcher.release()`
delegates the decision to the pure
`WorkspaceSelection.releaseCommitWorkspace()` helper and then calls the same
`activateWorkspace()` path as `Enter`; a release while the overview is closed,
or one whose selection is stale, is ignored. Because the activation decision
and the modifier observer are separated, the release path is unit testable
without a running compositor, and the retained `Enter` path is unchanged.

## Failure isolation

- The `input.keyboard.key` subscription is installed once per Hyprland config
  load and cleared by Hyprland's own Lua event handler on reload.
- A missing or malformed `release_commit` declaration logs a bounded warning and
  falls back to the pre-existing press binding; it never registers a broken
  dispatcher.
- The release IPC is delivered with the same timeout and failure semantics as
  every other plugin IPC call in the provider.
- The release handler cannot activate anything by itself: the plugin checks
  `isOpen` and validates that the selected workspace is still navigable.
