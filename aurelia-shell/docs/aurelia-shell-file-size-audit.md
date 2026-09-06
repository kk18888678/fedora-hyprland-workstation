# Aurelia Shell and Repository File-Size Audit

This audit distinguishes a large file from a god file. Line count is a guard
against accidental growth; responsibility ownership is the architectural test.

## Aurelia Shell guard

`tests/test_aurelia_shell_plugins.sh` enforces a 1,000-line limit for the
resident host services and first-party plugin source. The current package is
below that limit. The largest private surface is the settings view; it remains
one coherent settings responsibility and is not a host/registry/installer
god file.

The Aurelia test matrices were split into domain files while retaining the
single `./tests/run.sh` entry point:

- `tests/aurelia_keybindings_sections/`
- `tests/aurelia_hotkeys_sections/`
- `tests/hotkeys_sections/`
- `tests/config_architecture_sections/`

New plugin tests belong in `tests/test_aurelia_shell_plugins.sh` or a focused
section under `tests/aurelia_shell_sections/`; do not append them to a legacy
matrix wrapper.

## Remaining repository hotspots

These are pre-existing domain cores, not new Aurelia host files:

| File | Approx. lines | Ownership | Planned boundary |
| --- | ---: | --- | --- |
| `dotfiles/hypr/effective_bindings.lua` | 2,117 | Effective binding API | policy/normalization, JSON storage, resolver, and mutation modules |
| `aurelia-shell/core/preferences.lua` | 1,033 | Aurelia preference service | schema/defaults, atomic storage, export/diagnostics |

They require behavior-preserving extraction with their existing Lua test
coverage. They are explicitly tracked as the next refactoring boundary rather
than hidden behind a new framework or duplicated implementation.

The current Aurelia package does not add a new file above the guard and does
not copy the old shell tree: the package is standalone and has no parent-repository compatibility symlink
to `aurelia-shell`.
