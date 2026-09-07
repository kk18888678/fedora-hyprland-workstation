# Source-claim audit and completeness report

## Decision

This folder is source-and-flow complete for the declared reconstruction scope at
the fixed Quattro source anchor below: source units are catalogued, and
cross-component user journeys now have dedicated lifecycle traces under
flows/. It is not honest to claim that reading Markdown alone proves
pixel-identical rendering, compositor behavior, hardware behavior, package
resolution, external API behavior, or a successful real installation. Those
are separate runtime acceptance layers.

The exact claim is therefore:

~~~text
Every documented source fact in the declared scope was tied to the checked
source tree, a source test, or an explicitly recorded source quirk.

No undocumented transition is required to understand the documented shell,
plugin, AI, capture, notification, theme, wallpaper, lifecycle, dependency,
bar-widget, panel, overlay, menu, service, and modal-surface blueprint at the
source anchor. Each declared surface is now represented by an open/action/
close/cleanup trace or is explicitly identified as a no-surface service.

Runtime identity is not claimed until the blueprint is implemented and tested
against the same kind of graphical session and external dependency graph.
~~~

This wording is deliberate. A stronger unconditional guarantee would be an
assumption, not a cross-verified result.

## Fixed source anchors

~~~text
repository       https://github.com/omacom/omarchy
branch           quattro
full audit commit e989b5b3ee1ee1babb2614655649341f80b7b323
commit time      2026-09-07 03:15:39 -0400
~~~

The initial shell-only read used:

~~~text
commit f04366de79f2b6b4372d197cd49afdcc36b06a76
~~~

The branch is moving. A future implementation must either pin the full audit
commit above or repeat this audit before treating the blueprint as current.

## Inventory reconciliation

The shell-only inventory in 09-verification-and-source-map.md contains all 177
paths from the initial shell snapshot. A path comparison against the full
Quattro checkout found no removed shell path, exactly these eight additions,
and ten modified common/host files.

~~~text
shell/Ui/PluginBarApi.qml
shell/services/AuthServiceStore.js
shell/services/PluginAppLibraryApi.qml
shell/services/PluginBarStateApi.qml
shell/services/PluginBarWidgetRegistryApi.qml
shell/services/PluginFirstPartyServiceApi.qml
shell/services/PluginRegistryApi.qml
shell/services/PluginShellApi.qml
~~~

The ten existing paths modified by the full-anchor source are:

~~~text
shell/README.md
shell/Ui/qmldir
shell/plugins/bar/Bar.qml
shell/plugins/lock/manifest.json
shell/plugins/panels/clock/Panel.qml
shell/plugins/panels/weather/Panel.qml
shell/plugins/polkit/manifest.json
shell/plugins/services/idle/Service.qml
shell/services/PluginRegistry.qml
shell/shell.qml
~~~

The modifications add the scoped facade/trust architecture, mark lock and
polkit as authentication-capable first-party services, make the clock/weather
panels facade-aware, and allow the idle service to consume the scoped idle
configuration. Their behavior is covered by the host/facade sections of
12-full-plugin-lifecycle.md and the source map in 16-full-source-map-and-dependency-matrix.md.

The resulting full-snapshot counts are:

| Scope | Files | QML | JavaScript | JSON/JSONC | Markdown | shell | other assets |
|---|---:|---:|---:|---:|---:|---:|---:|
| historical shell snapshot | 177 | 97 | 27 | 38 | 5 | 3 | 7 |
| full Quattro shell snapshot | 185 | 104 | 28 | 38 | 5 | 3 | 7 |

The full repository anchor contains 1,807 tracked files, 466 shell scripts,
118 QML files, 75 Lua files, and 91 Markdown files. The 1,807-file figure is a
repository inventory, not a claim that unrelated application and hardware
internals have been behaviorally re-documented in this folder.

## Requested-area coverage

| Source area | Cross-checked source units | Documentation |
|---|---|---|
| host process and startup | shell/shell.qml, shell/README.md, default/hypr/autostart.lua, bin/omarchy-launch-shell | 01, 03, 11 |
| shared visual system | shell/Commons/, shell/Ui/, default/themed/shell.toml.tpl | 04, 05, 10, 15 |
| bar topology | shell/plugins/bar/Bar.qml, BarModel.js, bar manifest and widgets | 06, 07b, 12 |
| end-to-end interaction transitions | shell host, bar, shared UI, every user-visible plugin surface, capture/theme entrypoints | 20 and flows/01-12 |
| plugin registry | shell/services/PluginRegistry.qml, shell/shell.qml, all plugin API facades | 02, 03, 12 |
| first-party plugin catalog | every manifest under shell/plugins/ at the full anchor | 07, 07a, 07b, 07c, 12, 16 |
| third-party add/update/remove/clone | bin/omarchy-plugin-*, bin/omarchy-git-url-check, plugin tests | 02, 12 |
| persisted configuration | config/omarchy/shell.json, shell/shell.qml, PluginRegistry, bar model | 03, 06, 12 |
| session and install lifecycle | bin/omarchy-apply-system, provisioners, install phases, autostart | 11, 16 |
| updates and migrations | bin/omarchy-update, omarchy-migrate, update helpers, migrations | 11, 16 |
| AI operating model | manual/17-ai.md, agent setup, default-agent dispatch, collectors, agents panel | 13 |
| screenshot and recording | capture commands, keybindings, capture tests, screen indicator | 14 |
| OCR, QR, color, dictation | capture-text, capture-qr, menu routes, Voxtype scripts/config | 14 |
| notifications | notification service, card, sender, persistence logic, notification tests | 07a, 10 |
| themes and generated outputs | theme commands, template directory, theme manual, tests | 04, 15, 16 |
| wallpaper and image picker | background service, image-picker plugin/scripts, media components | 05, 07a, 07c, 14, 15 |
| tools/frameworks/libraries | QML imports, external process calls, package manifests | 01, 07, 10, 14, 15, 16 |
| logo and branded assets | logo/icon source files, unlock/theme assets, font/icon paths | 04, 07c, 15 |

## Exhaustive catalog checks

The full source contains 37 first-party manifest files. The catalog in
12-full-plugin-lifecycle.md contains 37 source-id rows. The IDs were compared
as sets, not sampled.

The generated default/themed directory contains 18 template files. The
template map in 15-theme-wallpaper-and-cross-app-sync.md contains all 18
outputs. The outputs were compared by source filename and destination name.

The current source manifest IDs are:

~~~text
omarchy.agents
omarchy.background
omarchy.bar
omarchy.active-window
omarchy.indicators
omarchy.keyboard-layout
omarchy.microphone
omarchy.spacer
omarchy.system-update
omarchy.tray
omarchy.workspaces
omarchy.clipboard
omarchy.dev-gallery
omarchy.emojis
omarchy.image-picker
omarchy.lock
omarchy.menu
omarchy.notifications
omarchy.osd
omarchy.audio
omarchy.bluetooth
omarchy.clock
omarchy.disk-speedtest
omarchy.dropbox
omarchy.monitor
omarchy.network
omarchy.power
omarchy.speedtest
omarchy.tailscale
omarchy.weather
omarchy.wifiqr
omarchy.polkit
omarchy.reminders
omarchy.battery
omarchy.idle
omarchy.media
omarchy.nightlight
~~~

The table in 12 also records every kind and entry-point path. The source
README under shell/plugins is not used as the completeness authority because
it is a user-facing subset rather than the manifest set.

## Verification performed

The following checks were completed during this documentation audit:

| Check | Result | Meaning |
|---|---|---|
| shell path/content comparison, historical versus full anchor | pass | no shell removal, eight additions, and ten modified common/host files recorded |
| first-party manifest count versus documentation rows | 37 versus 37 | catalog complete at the anchor |
| template count versus documentation mappings | 18 versus 18 | generated-output map complete at the anchor |
| source contract search | pass | keybindings, recorder, webcam, picker, theme, usage, Voxtype, bar, and debounce constants found in source |
| internal Markdown links | pass | every relative documentation link resolves |
| Markdown fence balance/whitespace check | pass | no malformed fenced block or trailing whitespace found |
| shell syntax scan | pass | every shell script in the shared workspace parsed with bash -n |
| repository test command | 191 passed, 1 failed | one unrelated pre-existing Kitty generated-theme reference remains |
| ShellCheck | not installed | not run; no package was installed for this task |

The repository test failure is:

~~~text
kitty.conf must not reference nonexistent generated noctalia theme file
~~~

The shared worktree already contains the user/concurrent
dotfiles/kitty/kitty.conf line that references themes/noctalia.conf; the
documentation task did not modify that file. No documentation claim depends on
that failed test.

## Source quirks intentionally preserved

These are not omissions. They are places where the source has a narrower,
broader, or surprising behavior than an idealized blueprint:

1. The QML runtime plugin validator does not require entry-point files to
   exist, does not enforce kind-to-entry-point correspondence, and does not
   recursively reject symlinks. The CLI validator does those checks.
2. First-party service objects use the hidden service host, while
   third-party and authentication service objects are created without a
   visual QObject parent. Authentication objects are kept in a private
   JavaScript store.
3. Runtime enablement, list-command enablement, bar-widget catalog presence,
   and visible bar placement are different questions.
4. allowMultiple is manifest metadata; the registry does not reject duplicate
   layout entries.
5. keepLoaded preserves an object across a rescan; it is not code hot swap.
6. The keyboard-panel surface remains mapped for its fade. Its full-screen
   input handler forwards bar-region clicks to registered bar targets; the
   source comments use “mask” language, but the interaction is implemented by
   forwarding logic.
7. Both red and color1 assign urgent during colors.toml parsing. The last
   recognized assignment in file order wins.
8. The Voxtype sample config comments mention ydotool while the installer
   provisions wtype. The text injection is delegated to Voxtype.
9. There is no dedicated color-capture binary, screenshot QML plugin, or
   recording QML plugin. Those paths are command/keybinding integrations.
10. There is no embedded LLM runtime in the shell. The AI design is external
    agent CLI dispatch, usage collection, skills, applications, and dictation.
11. Git-installed themes are filtered differently from hand-authored user
    themes. The executable/config-denial list is part of the source contract.
12. A valid user shell.json replaces defaults as a whole; it is not deep
    merged.
13. The shell IPC enable path rejects an unknown id when enabling, but the
    underlying registry path does not require a manifest when disabling; an
    unknown disable can therefore return success after a no-op/config rewrite.
    Summon still rejects ids absent from the installed map. This is preserved
    as observed behavior, not presented as ideal command UX.
14. Git-theme denial is applied to top-level entries; nested directories are
    recursively copied without reapplying the denial list, although symlinks
    are skipped. Normal theme copying uses `*` globs and does not include
    dotfiles. This is source behavior, not the stronger security policy the
    comments suggest.
15. The dictation indicator assigns a transcribing glyph internally, but its
    active flag is true only for recording. The shared BarIndicator consequently
    renders the inactive microphone glyph while transcribing. The documentation
    records the rendered behavior rather than the apparent intent.
16. The source prose describes replacement-bar lifecycle access as configured
    UI access, but the actual bar-control predicate also admits any known
    non-authentication target whose manifest declares bar-widget, panel, overlay,
    or menu. The summon path then applies its separate enabled check.

These quirks are referenced in the feature documents at the point where they
affect implementation.

## Source fact versus blueprint instruction

The documents use two different voices:

| Wording | Interpretation |
|---|---|
| “the source does”, “the runtime checks”, “the file contains” | static source fact |
| “a faithful port must”, “preserve”, “acceptance requires” | reconstruction requirement derived from that fact |
| “hardened implementation”, “generic builder may”, “out of scope” | explicit blueprint choice or boundary, not a claim about Quattro runtime |
| “unverified”, “runtime concern”, “integration responsibility” | not established by static reading |

The build/acceptance documents do not silently turn a security hardening
recommendation into reference behavior. In particular, adding a runtime
symlink check, sandboxing third-party QML, changing package ownership, or
adding an embedded AI service would produce a safer or different system, not a
source-identical one.

## What this audit does not prove

Static source cross-checking cannot prove:

- identical Qt/Quickshell text shaping and device-pixel rounding;
- identical Hyprland layer-shell input-region behavior on another compositor;
- camera formats, GPU encoders, PipeWire nodes, fingerprint hardware, or
  monitor transforms on a target machine;
- credentials, OAuth sessions, billing APIs, weather services, Git remotes, or
  desktop applications accepting the same requests;
- package repository availability or package version resolution;
- real snapshot rollback, reboot activation, or recovery after power loss;
- correctness of arbitrary third-party code;
- complete behavior of unrelated repository subsystems outside the declared
  scope.

The flow documents add source-defined runtime acceptance checks, but those
checks have not been executed against a live Quickshell/Wayland session in this
documentation task. The remaining claims are intentionally classified in
09-verification-and-source-map.md and 16-full-source-map-and-dependency-matrix.md.

## Re-audit procedure

Before implementing from this folder after a source update:

1. record the new branch commit;
2. compare every path below shell/ with the previous anchor;
3. recount manifests, templates, QML/JavaScript API facades, and package
   manifests;
4. rerun the source-contract checks;
5. inspect changed source files and update only the affected focused document;
6. rerun Markdown QA and distinguish source-inspected from runtime-tested
   results.

Do not update the anchor silently. A changed source tree is a new audit.

## Source cross-check

~~~text
09-verification-and-source-map.md
11-full-platform-lifecycle.md
12-full-plugin-lifecycle.md
13-ai-first-platform.md
14-capture-recording-and-dictation.md
15-theme-wallpaper-and-cross-app-sync.md
16-full-source-map-and-dependency-matrix.md
19-plugin-facade-api-reference.md
temporary full source checkout at the fixed anchor above
~~~
