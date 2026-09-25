# Aurelia Workspace Overview: Commit-on-Modifier-Release

This document records the mechanism behind Alt+Tab-style activation in the
`aurelia.workspace-switcher` Mission Control overlay, and why it is implemented
through the Hyprland Lua keybinding provider rather than a declarative release
bind.

## Behaviour

A quick `SUPER + TAB` tap flips to the previously focused workspace without
rendering the overlay (see "Quick tap vs hold" below). Once the interaction is
held or navigated, the overview opens and the Alt+Tab-style commit applies:
releasing `SUPER` activates the currently selected workspace immediately,
without pressing Enter.

The retained activation paths are unchanged:

- `Enter` / `Return` / `Space` activate the selected workspace.
- Clicking a workspace card activates that workspace.
- `Esc` and clicking the backdrop close without activating.
- The mouse wheel and arrow / Home / End keys navigate the selection.
- Cyclic wrap-around is preserved in both selection modes.
- Pointer hover never changes the selection; selection follows explicit input.

## Quick tap vs hold

The switcher distinguishes a quick tap from a held interaction:

- **Tap** (release `SUPER` within `TAP_HOLD_THRESHOLD_MS`, 180 ms): the overlay
  never renders. The shell flips directly to the previously focused workspace,
  exactly like the fast ALT+TAB toggle on other desktops.
- **Hold** (keep `SUPER` down past the threshold) or **navigate** (press TAB
  again, use the arrow / Home / End keys, or scroll): the overlay renders and
  the historical commit-on-release behaviour applies.

The threshold is pinned once in
`plugins/aurelia.workspace-switcher/WorkspaceSelection.js` as
`TAP_HOLD_THRESHOLD_MS = 180` and mirrored by the `revealTimer` interval. The
value is deliberately small: an ordinary tap lands well under 180 ms, while a
deliberate browse sits comfortably above it. The pure-JS threshold and the QML
timer cannot drift apart because the timer binds to the exported constant, and
the static contract tests pin the value.

## Interaction state model

The switcher tracks four values:

- `activeWorkspaceId` — the workspace that currently has focus.
- `previousWorkspaceId` — the workspace focus came from.
- `interactionRevealed` — true only once the overlay is actually rendered.
- `interactionNavigated` — true once any explicit navigation has happened.

`recordFocusedWorkspace()` maintains the first pair. It is idempotent (calling
it with the same focus changes nothing), ignores out-of-range focus values, and
otherwise moves `previousWorkspaceId = activeWorkspaceId` before setting
`activeWorkspaceId` to the new focus. It runs from
`onFocusedWorkspaceChanged` and `Component.onCompleted`, so the pair is correct
even when the shell starts on an already-focused workspace.

`open()` seeds the workspace selection, sets `isOpen`, and starts
`revealTimer` — but it does **not** reveal, and it deliberately does not re-read
the focus pair (a stale focus signal would clobber the optimistic swap needed by
a rapid second tap). The timer flips `interactionRevealed` after the threshold.
A second press (`cycle`) or any navigation calls `noteInteraction()`, which sets
`interactionNavigated` and reveals immediately. `PanelWindow.visible`,
`WlrLayershell.keyboardFocus`, and the `focusSurface()` call are all gated on
`interactionRevealed`, so a tap never paints the overlay or steals keyboard
focus. `close()` stops the timer and resets both flags.

On the `SUPER` release the plugin asks the pure
`isQuickTap(isOpen, revealed, navigated)` helper. When it is true the
interaction was never seen, so the plugin stops the timer, closes, and calls
`toggleToPrevious()`. Otherwise the existing `releaseCommitWorkspace()` path is
unchanged.

`toggleToPrevious()` swaps the pair **before** calling `activateWorkspace()`
because the Hyprland focus signal arrives asynchronously; flipping first keeps a
rapid second tap aimed at the workspace that was just left.

## Why workspace-level, not window-level

The toggle is intentionally workspace-level rather than window-level. The
switcher already exposes a workspace snapshot (`Hyprland.workspaces`), not a
toplevel/window ordering, and "previous workspace" is a stable, observable
concept that survives window churn. A window-level most-recently-used list
would require the plugin to own a second ordering of toplevels, track window
lifetimes, and decide how minimized or closed windows participate — a larger,
less predictable state machine for no workstation capability gain. The design
keeps SUPER+TAB a workspace operation and leaves window management to the
compositor.

## Interaction with `only_in_use`

`knownWorkspaceIds()` deliberately returns **every real workspace object id**,
not the filtered list used for display and cycling. The
`aurelia.workspaces.only_in_use` preference continues to govern only which
workspaces the overlay shows and cycles. This matters for an
emptied-but-existing persistent workspace: it drops out of the visible list
under `only_in_use`, but it still exists as a Hyprland workspace object and must
remain a valid tap target, otherwise the toggle would silently fail for the
workspace the user just left. Using the display list here would couple a
display preference to a navigation invariant.

## Failure cases

The tap path is fail-closed and never guesses:

- **No previous workspace** (`previousWorkspaceId === 0`, as on a freshly
  started shell): `toggleTarget()` returns 0, `toggleToPrevious()` reports
  `ignored`, and nothing is activated.
- **Previous equals active**: the pair would be a no-op, so the target is 0.
- **Previous workspace no longer exists** (for example a non-persistent
  workspace destroyed after focus left it): it is absent from
  `knownWorkspaceIds()` and the target is 0.
- **Malformed ids** (NaN, null, or out of the 1..10 range): normalized to 0 and
  rejected.
- **Released after the timer fired**: `interactionRevealed` is true, so
  `isQuickTap()` is false and the normal commit path runs.
- **Released after navigating**: `interactionNavigated` is true, so the normal
  commit path runs.

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
