# Settings Hub — Hyprland + Aurelia Shell Settings

One screen to tweak the workstation:

- **Hyprland settings always available** (gaps, borders, rounding, layout,
  opacity, shadows, blur, input, animations, workspace pinning), with
  live preview through bounded `hyprctl` calls.
- **Aurelia Shell settings when the resident shell is Aurelia** (theme,
  background, motion, display text size, bar visibility, keybindings),
  through the existing bounded `aurelia-*` helpers.

The repository baseline under `dotfiles/hypr/` stays the reviewed desired
state. User tweaks are stored in a separate **user-owned overlay**:

```
$XDG_CONFIG_HOME/fedora-hyprland-workstation/hypr-settings.lua
(~/.config/fedora-hyprland-workstation/hypr-settings.lua)
```

`dotfiles/hypr/hyprland.lua` loads the overlay at the end of the config
(fail closed, like the Aurelia provider bridge), so `hyprctl reload` and the
next session restore the user's settings.

## Components

| Component | Role |
| --- | --- |
| `bin/workstation-hypr-settings` | Shell-agnostic backend: strict option schema, atomic/idempotent overlay writes, bounded live apply |
| `dotfiles/hypr/hyprland.lua` | Optional overlay loader (config merge, animation blocks, workspace pins) |
| `aurelia-shell/plugins/aurelia.settings/` | Aurelia Settings hub panel (IPC `aurelia.settings`, `Super + T`) |
| `aurelia-shell/dotfiles/hypr/keybindings_manifest.lua` | `desktop_settings` binding opens the hub in the Aurelia session |

## The overlay

```lua
-- WORKSTATION_HYPR_SETTINGS_MANAGED_V1
return {
    schema_version = 1,
    config = {
        general = { gaps_in = 4, layout = "master",
                    col = { active_border = "#9ccfd8" } },
        decoration = { rounding = 10 },
        input = { repeat_rate = 40 },
        animations = { enabled = true },
    },
    animation_preset = "snappy",
    animations = { { leaf = "windows", enabled = true, speed = 9,
                     bezier = "workstation", style = "slide" }, ... },
    persistent_workspaces = { 1, 2, 3, 4 },
}
```

The overlay is **data only**. The backend emits it deterministically; the
loader re-applies it through the normal Hyprland Lua API. Recovery is
`workstation-hypr-settings clear` (or deleting the file).

## Backend usage (works in any session)

```bash
workstation-hypr-settings schema          # option registry (JSON)
workstation-hypr-settings status          # per-option override/live/effective (JSON)
workstation-hypr-settings get <id>        # effective value
workstation-hypr-settings set <id> <val>  # validate, persist, live-apply
workstation-hypr-settings reset <id>      # drop one override
workstation-hypr-settings clear           # drop all overrides
workstation-hypr-settings dump | path     # inspect the overlay
workstation-hypr-settings check           # backend + Hyprland diagnostics
```

Examples:

```bash
workstation-hypr-settings set general.gaps_in 6
workstation-hypr-settings set decoration.blur.enabled true
workstation-hypr-settings set animations.preset snappy
workstation-hypr-settings set workspaces.persistent 4
```

## Safety model

- **Schema-enforced**: unknown ids, out-of-range values, bad enums/colors/
  booleans fail closed with no overlay mutation.
- **Atomic + idempotent**: writes use `mktemp` + rename, `0600`; a repeated
  identical `set` is a write no-op.
- **Bounded**: every `hyprctl` call runs through `timeout`.
- **Path safety**: absolute non-root config home, no symlink parents, no
  `/etc /usr /var` destinations, no traversal.
- **Managed-file guard**: an unmanaged file at the overlay path is refused.
- **Live apply, observable failures**: leaf options go through
  `hyprctl keyword`; structural options (animation presets, workspace pins)
  go through `hyprctl reload`. When Hyprland is unreachable, settings still
  persist and apply on the next reload/session — with an explicit warning.
- **Aurelia helpers are never replaced**: theme/motion/display/bar changes
  reuse the existing `aurelia-theme`, `workstation-aurelia`,
  `aurelia-display-text-size`, and `aurelia-bar-hidden` commands.

## Opening the hub

- **Super + T** (`desktop_settings`) toggles the hub in the Aurelia session.
  The binding resolves the Aurelia Shell IPC client to an absolute path
  (checkout or installed), so it works even when `aurelia` is not on the
  keybind environment PATH.
- From a terminal: `aurelia settings toggle` (or legacy
  `aurelia-shell shell toggle aurelia.settings`).
- The hub appears in the Aurelia plugin registry as **Settings**.

## The unified `aurelia` CLI

`aurelia` is the omarchy-style command center for the workstation shell. It
re-executes the existing bounded backends — it adds zero duplicate capability
logic:

```bash
aurelia bar transparent toggle                 # -> aurelia-bar transparent toggle
aurelia bar position bottom                    # -> aurelia-bar position bottom
aurelia bar move aurelia.clock --section center --index 0
aurelia bar set aurelia.clock format "HH:mm"
aurelia bar defaults                           # back to the shipped layout
aurelia plugin disable aurelia.weather
aurelia plugin enable example.plugin --section center

aurelia settings toggle                        # open/toggle the Settings hub
aurelia settings hypr set general.gaps_in 6    # forward to the hypr backend
aurelia settings status
aurelia theme list | set <name> | bg next
aurelia shell ping | restart | toggle <plugin>
aurelia capture screenshot [full|region] [options]
aurelia display text-size [9..20|reset]
aurelia keybindings

aurelia commands [--all] [--json] [--check]    # command reference
```

Backend resolution is deterministic (never PATH-first):
`$AURELIA_SHELL_ROOT/bin`, the dispatcher's own directory (checkout
`bin/`), `/usr/local/share/aurelia-shell/bin`, then PATH. The installer
places the self-contained `aurelia` dispatcher and the `aurelia-shell` IPC
client in `/usr/local/bin`.

> `aurelia` is the canonical user CLI. `aurelia-shell` remains the internal
> IPC client name used across the resident shell platform; the dispatcher
> forwards to it transparently, so you interact with `aurelia` only.

## Layout

- **General & Appearance** — gaps, border size, corner rounding, layout,
  snap, border colors, opacities, shadow, blur, VRR.
- **Animations** — master switch and curated presets (baseline / snappy /
  relaxed / off). Presets change per-leaf animation speed over the baseline
  named bezier curves; the baseline file is never rewritten.
- **Input** — keyboard layout, numlock, repeat delay/rate, pointer
  acceleration, follow-mouse, touchpad behavior.
- **Workspaces** — number of pinned default workspaces (1..10).
- **Aurelia Shell** — theme picker, Theme/Wallpaper panel, keybindings
  editor, motion switch + scale, display text size, bar visibility. Shown
  only when the Aurelia shell is the live session.
- **About & Reset** — overlay path, Hyprland reachability, clear-all
  (two-click confirm; never touches personal files or Aurelia preferences).

## Extension

Add an option by extending the schema table in
`bin/workstation-hypr-settings` (id | hypr leaf | type | min | max | enum |
category | default | label | description). The backend, overlay format, and
hyprland.lua loader are generic; the Settings hub renders any schema entry
automatically. Run `./aurelia-shell/tests/run.sh` to exercise the contract.

## What it does not do

- It does not rewrite `dotfiles/hypr/*.lua`; the repository baseline is
  read-only from the hub's perspective.
- It does not remove or purge anything; `clear` only restarts the baseline.
- It does not evaluate theme Lua/shell hooks or execute arbitrary config.
- It never replaces a package manager's ownership of installed software.
