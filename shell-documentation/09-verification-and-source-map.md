# Verification and source map

## Source and method

Primary source:

<https://github.com/omacom/omarchy/tree/quattro/shell>

Full repository source used for the platform expansion:

<https://github.com/omacom/omarchy/tree/quattro>

Historical shell-only audit snapshot:

```text
branch requested  quattro
commit read       f04366de79f2b6b4372d197cd49afdcc36b06a76
commit date       2026-09-07 02:02:10 -0400
source root       shell/
files             177
QML               97
JavaScript        27
JSON/JSONC        38
other             Markdown, shell, Python, SVG
source lines      41,094 counted lines
```

The branch tree was first inventoried through the public GitHub tree and its
README/plugin README pages, then fetched into a temporary read-only checkout
and read file by file. Adjacent files were inspected where the shell imports,
launches, or persists them: the default shell JSON, theme template, session
autostart, shell/plugin CLI wrappers, fontconfig defaults, package manifest,
menu JSONC, agent collectors, and logo/icon assets.

This document distinguishes static source evidence from runtime claims. The
source checkout was not launched on the workstation, and the real installer,
reboot, package transaction, lock activation, live compositor, and external
network/API behavior were not integration-tested during this documentation
task.

The later full-repository audit was anchored at commit
`e989b5b3ee1ee1babb2614655649341f80b7b323` on 2026-09-07. It contained 1,807
tracked files, 466 shell scripts, 118 QML files, 75 Lua files, and 91 Markdown
files. Its current `shell/` tree contained 185 files: 104 QML, 28 JavaScript,
38 JSON/JSONC, 5 Markdown, 3 shell, and 7 other files, with 42,409 counted
lines. The full-repository lifecycle, AI, capture, theme, and dependency audit
is split into [11-full-platform-lifecycle.md](11-full-platform-lifecycle.md),
[12-full-plugin-lifecycle.md](12-full-plugin-lifecycle.md),
[13-ai-first-platform.md](13-ai-first-platform.md),
[14-capture-recording-and-dictation.md](14-capture-recording-and-dictation.md),
[15-theme-wallpaper-and-cross-app-sync.md](15-theme-wallpaper-and-cross-app-sync.md),
and [16-full-source-map-and-dependency-matrix.md](16-full-source-map-and-dependency-matrix.md).

## Complete `shell/` inventory at the historical shell-only snapshot

The following is the complete path inventory at the audited commit. Line counts
are included for the source files with normal newlines; minified SVG/JSON assets
can report zero newline-terminated lines even though they contain data.

The list below is the complete historical shell-only inventory. The later full
repository snapshot removed no shell paths, added the following eight files,
and modified ten existing shell files. The added and modified paths are both
part of the full-anchor contract; the historical line counts below are not
current line counts for those modified files.

```text
Ui/PluginBarApi.qml
services/AuthServiceStore.js
services/PluginAppLibraryApi.qml
services/PluginBarStateApi.qml
services/PluginBarWidgetRegistryApi.qml
services/PluginFirstPartyServiceApi.qml
services/PluginRegistryApi.qml
services/PluginShellApi.qml
```

Therefore the current full-snapshot shell tree is the 177 paths listed below
plus these eight additions (185 total). The ten modified common/host paths are
listed in 17-claim-audit.md, and their exact facade/trust contracts are
documented in [12-full-plugin-lifecycle.md](12-full-plugin-lifecycle.md).

### Root, common module, and UI module

```text
README.md (301)
shell.qml (1058)
Commons/qmldir (5)
Commons/Border.qml (242)
Commons/BorderGeometry.js (373)
Commons/Color.qml (254)
Commons/Style.qml (515)
Commons/Util.qml (159)
Ui/qmldir (36)
Ui/BackgroundMedia.qml (87)
Ui/BackgroundVideo.qml (122)
Ui/BarIconButton.qml (63)
Ui/BarIndicator.qml (51)
Ui/BarWidget.qml (45)
Ui/BorderOverlay.qml (54)
Ui/BorderSurface.qml (40)
Ui/Button.qml (209)
Ui/ButtonGroup.qml (132)
Ui/ConfirmDialog.qml (133)
Ui/CursorSurface.qml (41)
Ui/Dropdown.qml (244)
Ui/KeyboardPanel.qml (418)
Ui/MultiSelect.qml (623)
Ui/NumberField.qml (85)
Ui/OpticalGlyph.qml (56)
Ui/Panel.qml (59)
Ui/PanelActionButton.qml (100)
Ui/PanelController.qml (16)
Ui/PanelHero.qml (111)
Ui/PanelKeyCatcher.qml (85)
Ui/PanelSectionHeader.qml (30)
Ui/PanelSeparator.qml (18)
Ui/PanelSlider.qml (149)
Ui/PanelToolTip.qml (49)
Ui/PointerMoveGate.qml (54)
Ui/PopupCard.qml (176)
Ui/ScreenMoveRemap.qml (43)
Ui/SearchableDropdown.qml (353)
Ui/SpeedTestOverlay.qml (412)
Ui/TextField.qml (57)
Ui/Toggle.qml (117)
Ui/ToggleSwitch.qml (111)
Ui/WidgetButton.qml (119)
```

### Shared services

```text
services/AppLibrary.qml (268)
services/AppSearch.js (134)
services/BarWidgetRegistry.qml (49)
services/PluginRegistry.qml (716)
services/hidden-entries.sh (102)
```

### Hosted plugins and assets

```text
plugins/README.md (119)

plugins/agents/Agent.qml (34)
plugins/agents/Main.qml (748)
plugins/agents/Panel.qml (942)
plugins/agents/README.md (150)
plugins/agents/assets/claude.svg
plugins/agents/assets/codex-light.svg
plugins/agents/assets/codex.svg
plugins/agents/assets/fireworks.svg (7)
plugins/agents/manifest.json (40)

plugins/background/Background.qml (364)
plugins/background/manifest.json (14)

plugins/bar/Bar.qml (1842)
plugins/bar/BarModel.js (231)
plugins/bar/README.md (180)
plugins/bar/manifest.json (14)
plugins/bar/indicators/Dictation.qml (38)
plugins/bar/indicators/Dnd.qml (22)
plugins/bar/indicators/NightLight.qml (20)
plugins/bar/indicators/Reminder.qml (59)
plugins/bar/indicators/ScreenRecording.qml (43)
plugins/bar/indicators/StayAwake.qml (20)
plugins/bar/widgets/ActiveWindow.manifest.json (21)
plugins/bar/widgets/ActiveWindow.qml (64)
plugins/bar/widgets/Indicators.manifest.json (78)
plugins/bar/widgets/Indicators.qml (471)
plugins/bar/widgets/KeyboardLayout.manifest.json (28)
plugins/bar/widgets/KeyboardLayout.qml (218)
plugins/bar/widgets/KeyboardLayoutModel.js (125)
plugins/bar/widgets/Microphone.manifest.json (20)
plugins/bar/widgets/Microphone.qml (54)
plugins/bar/widgets/Spacer.manifest.json (21)
plugins/bar/widgets/Spacer.qml (13)
plugins/bar/widgets/SystemUpdate.manifest.json (20)
plugins/bar/widgets/SystemUpdate.qml (65)
plugins/bar/widgets/Tray.manifest.json (28)
plugins/bar/widgets/Tray.qml (850)
plugins/bar/widgets/TrayModel.js (48)
plugins/bar/widgets/Workspaces.manifest.json (20)
plugins/bar/widgets/Workspaces.qml (72)

plugins/clipboard/Clipboard.qml (613)
plugins/clipboard/ClipboardHistory.js (225)
plugins/clipboard/capture.sh (106)
plugins/clipboard/manifest.json (15)

plugins/dev-gallery/GalleryPanel.qml (1854)
plugins/dev-gallery/manifest.json (14)

plugins/emojis/EmojiSearch.js (46)
plugins/emojis/Emojis.qml (345)
plugins/emojis/emojis.json
plugins/emojis/manifest.json (15)

plugins/image-picker/ImagePicker.qml (582)
plugins/image-picker/ImagePickerModel.js (97)
plugins/image-picker/list.sh (114)
plugins/image-picker/manifest.json (15)

plugins/lock/LockView.qml (221)
plugins/lock/Service.qml (621)
plugins/lock/manifest.json (15)

plugins/menu/BarWidget.qml (24)
plugins/menu/Menu.qml (1480)
plugins/menu/MenuModel.js (524)
plugins/menu/manifest.json (23)

plugins/notifications/NotificationLogic.js (479)
plugins/notifications/Service.qml (1063)
plugins/notifications/components/NotificationCard.qml (228)
plugins/notifications/manifest.json (15)

plugins/osd/Osd.qml (206)
plugins/osd/OsdModel.js (62)
plugins/osd/manifest.json (14)

plugins/panels/audio/Model.js (262)
plugins/panels/audio/Panel.qml (1248)
plugins/panels/audio/manifest.json (20)
plugins/panels/bluetooth/Model.js (177)
plugins/panels/bluetooth/Panel.qml (1045)
plugins/panels/bluetooth/manifest.json (20)
plugins/panels/clock/BarWidget.qml (185)
plugins/panels/clock/Model.js (308)
plugins/panels/clock/Panel.qml (760)
plugins/panels/clock/manifest.json (20)
plugins/panels/disk-speedtest/Panel.qml (151)
plugins/panels/disk-speedtest/manifest.json (14)
plugins/panels/dropbox/DropboxIcon.qml (45)
plugins/panels/dropbox/Model.js (137)
plugins/panels/dropbox/Panel.qml (547)
plugins/panels/dropbox/Service.qml (277)
plugins/panels/dropbox/manifest.json (36)
plugins/panels/dropbox/status.py (128)
plugins/panels/monitor/Model.js (124)
plugins/panels/monitor/Panel.qml (929)
plugins/panels/monitor/manifest.json (20)
plugins/panels/network/Model.js (398)
plugins/panels/network/Panel.qml (2087)
plugins/panels/network/manifest.json (20)
plugins/panels/power/Model.js (104)
plugins/panels/power/Panel.qml (536)
plugins/panels/power/manifest.json (20)
plugins/panels/speedtest/Panel.qml (202)
plugins/panels/speedtest/manifest.json (14)
plugins/panels/tailscale/Model.js (325)
plugins/panels/tailscale/Panel.qml (1273)
plugins/panels/tailscale/README.md (49)
plugins/panels/tailscale/Service.qml (637)
plugins/panels/tailscale/TailscaleIcon.qml (72)
plugins/panels/tailscale/manifest.json (36)
plugins/panels/weather/BarWidget.qml (83)
plugins/panels/weather/Model.js (295)
plugins/panels/weather/Panel.qml (879)
plugins/panels/weather/manifest.json (21)
plugins/panels/wifiqr/Model.js (37)
plugins/panels/wifiqr/Panel.qml (369)
plugins/panels/wifiqr/manifest.json (14)

plugins/polkit/PolkitAgent.qml (392)
plugins/polkit/PolkitModel.js (32)
plugins/polkit/manifest.json (15)

plugins/reminders/ReminderFlow.qml (173)
plugins/reminders/ReminderFlowModel.js (21)
plugins/reminders/manifest.json (15)

plugins/services/battery/BatteryModel.js (28)
plugins/services/battery/Service.qml (110)
plugins/services/battery/manifest.json (14)
plugins/services/idle/IdleModel.js (52)
plugins/services/idle/Service.qml (360)
plugins/services/idle/manifest.json (15)
plugins/services/media/BarWidget.qml (313)
plugins/services/media/MediaModel.js (142)
plugins/services/media/Service.qml (523)
plugins/services/media/manifest.json (23)
plugins/services/nightlight/NightlightModel.js (20)
plugins/services/nightlight/Service.qml (115)
plugins/services/nightlight/manifest.json (14)
```

## Adjacent source files cross-checked

These are outside `shell/` but are required to reproduce the shell's actual
runtime contract:

```text
config/omarchy/shell.json
default/themed/shell.toml.tpl
default/hypr/autostart.lua
default/fontconfig/conf.avail/50-omarchy.conf
default/omarchy/omarchy-menu.jsonc
install/omarchy-base.packages
logo.svg
logo.txt
icon.txt
bin/omarchy-launch-shell
bin/omarchy-restart-shell
bin/omarchy-shell
bin/omarchy-shell-config
bin/omarchy-plugin-add
bin/omarchy-plugin-update
bin/omarchy-plugin-remove
bin/omarchy-plugin-enable
bin/omarchy-plugin-disable
bin/omarchy-plugin-list
bin/omarchy-plugin-validate
bin/omarchy-plugin-clone
bin/omarchy-plugin-catalog
bin/omarchy-git-url-check
bin/omarchy-bar
bin/omarchy-agent-usage-update
bin/omarchy-agent-usage-claude
bin/omarchy-agent-usage-codex
bin/omarchy-agent-usage-fireworks
```

## Evidence classification

| Claim | Evidence level |
|---|---|
| one long-lived ShellRoot host | source-inspected `shell.qml`, launcher, README |
| exact manifest fields and scanner shape | source-inspected registry, validator, catalog |
| enablement/clone/restore behavior | source-inspected registry and CLI scripts |
| JSON state/no-deep-merge behavior | source-inspected host/config helpers |
| IPC names/return strings | source-inspected host and plugin handlers |
| type/spacing/color defaults | source-inspected Style/Color/theme template |
| exact UI dimensions | source-inspected QML literals/formulas |
| per-monitor routing/popout rules | source-inspected Bar/KeyboardPanel/BarModel |
| feature data parsers | source-inspected each Model.js/helper |
| visual component coverage | source-inspected developer gallery |
| runtime frame rate, visual fidelity, API response behavior | not runtime-verified |
| package availability on a target OS | not verified; package manifest only |
| security of arbitrary third-party code | not a claim; source explicitly says it is unsandboxed |

## Important source boundaries and risks

These are part of the blueprint because a “cleaner” port that erases them will
not be 1:1:

1. The runtime registry and CLI validator are not identical. The CLI checks
   entry-point existence, kind-to-entry-point correspondence, user id regex,
   reserved namespace, and symlink absence; the QML runtime validator has a
   narrower set of checks. Preserve the behavior or deliberately make both
   stricter while documenting the change.
2. The `allowMultiple` manifest field is metadata; registry code does not
   enforce it against manually duplicated layout entries.
3. First-party non-widget plugins are enabled by default and opt out through a
   disabled list. User non-widget plugins are enabled by presence in
   `plugins[]`. Treating all plugins as presence-only changes startup behavior.
4. A kept service is not hot-replaced. It survives rescans, so code changes to
   that service require a shell restart.
5. User plugin code is unsandboxed in the long-lived process. Manifest safety
   checks do not turn it into a security boundary.
6. The command menu's providers are source-defined. JSONC can select existing
   providers but cannot invent a new provider name.
7. The bar's indicators are loaded by a fixed relative QML path. They are not
   third-party manifest extension points.
8. The bar has one visual instance per monitor but a single shared state/config
   owner. Any implementation that lets each monitor write independent layout
   state will diverge from the source.
9. Real native service behavior is assumed from Quickshell/Hyprland/BlueZ/
   PipeWire/NetworkManager/UPower/PAM and the helper commands. Static reading
   proves the calls and parsing, not that every external version behaves the
   same way.

## Documentation QA performed

The generated documentation was checked against the temporary checkout for:

- all top-level directories and source-file families;
- manifest kinds and entry-point roles;
- global color, style, spacing, typography, border, and bar constants;
- host IPC names and special image-selector bridge;
- plugin install/update/remove/clone workflows;
- panel/overlay/service feature inventory;
- adjacent config, launcher, theme, font, package, collector, and branding
  dependencies.

This documentation task did not edit or commit tracked source files; it added
only the requested documentation folder. The shared workspace did advance from
the starting SHA during the audit because other work was committed concurrently;
those commits were preserved and are not part of this documentation change.
No installer run, package transaction, compositor activation, PAM/greetd
change, live user-configuration overwrite, or VM reboot was performed by this
task.
