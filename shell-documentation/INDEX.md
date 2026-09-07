# Long-lived Wayland shell blueprint

This folder is a generic, implementation-grade reconstruction blueprint for
the reference shell found at:

<https://github.com/omacom/omarchy/tree/quattro/shell>

The platform-level additions in this revision were cross-checked against the
full repository at the same branch:

<https://github.com/omacom/omarchy/tree/quattro>

The wording here intentionally replaces product names with roles and
placeholders. The measurements, state rules, loading rules, and interaction
contracts are retained from the audited implementation. A builder should
rename the placeholders consistently, not reinterpret the behavior.

Exact source ids, command names, and paths are retained in catalog and
cross-check sections where removing them would make a 1:1 implementation
ambiguous; the blueprint prose remains role-oriented.

## Audit snapshot

The initial shell-only pass was read from commit
`f04366de79f2b6b4372d197cd49afdcc36b06a76` on 2026-09-07. The subsequent
full-repository pass was read from commit
`e989b5b3ee1ee1babb2614655649341f80b7b323` on the same date. The full checkout
contained 1,807 tracked files, 466 shell scripts, 118 QML files, 75 Lua files,
and 91 Markdown files. The current `shell/` tree in that full snapshot contains
185 tracked files: 104 QML, 28 JavaScript, 38 JSON/JSONC, 5 Markdown, 3 shell,
and 7 other files, with 42,409 counted lines.

The earlier shell-only snapshot contained 177 files below `shell/` and 41,094
counted lines; its detailed inventory remains marked as historical in
[09-verification-and-source-map.md](09-verification-and-source-map.md). The
full-repository source maps identify the eight later files, ten modified
existing files, and the expanded lifecycle behavior.

This is documentation of source behavior, not a claim that a live workstation
was integration-tested. The verification boundary and known source quirks are
recorded in [09-verification-and-source-map.md](09-verification-and-source-map.md).

## Audit conclusion

At source level, the requested reconstruction scope is covered: the complete
shell/plugin lifecycle for shipped, cloned, hand-authored, and Git-installed
plugins; the agent-first AI ecosystem; screenshot, recording, OCR, QR, color,
and dictation flows; notification, theme, wallpaper, unlock, and image-picker
surfaces; and the package/framework/dependency ownership map. The source does
not show an embedded model runtime inside the shell, so the AI documentation
records the actual agent-centric design rather than inventing one. This is a
source-completeness claim for the declared scope, not a claim that static
reading proves pixel-perfect runtime behavior. The evidence levels, source
quirks, and non-claims are explicit in [17-claim-audit.md](17-claim-audit.md)
and [18-scope-and-nonclaims.md](18-scope-and-nonclaims.md).

## Read in this order

1. [01-runtime-architecture.md](01-runtime-architecture.md) — process,
   session, directory, dependency, and lifecycle topology.
2. [02-plugin-system.md](02-plugin-system.md) — manifest, discovery,
   validation, enablement, loading, reload, cloning, and third-party rules.
3. [03-state-and-ipc.md](03-state-and-ipc.md) — persisted JSON, configuration
   ownership, IPC targets, routing, and state transitions.
4. [04-design-language.md](04-design-language.md) — palette roles, theme
   layering, type scale, spacing, borders, surfaces, motion, iconography, and
   orientation rules.
5. [05-ui-kit-and-measurements.md](05-ui-kit-and-measurements.md) — every
   reusable UI type and its exact default dimensions/interaction contract.
6. [06-bar-engine.md](06-bar-engine.md) — multi-monitor bar layout, widgets,
   custom modules, drag placement, popout coordination, and transparency.
7. [07-feature-catalog.md](07-feature-catalog.md) — first-party feature
   families, external tools, data formats, and feature-level dimensions.
8. [08-build-and-acceptance-blueprint.md](08-build-and-acceptance-blueprint.md)
   — a generic build plan, dependency checklist, testable invariants, and
   acceptance gates.
9. [09-verification-and-source-map.md](09-verification-and-source-map.md) —
   file inventory, evidence classification, source cross-checks, and limits of
   what static reading can prove.
10. [10-external-tool-contract.md](10-external-tool-contract.md) — exact Qt,
    Quickshell, system-service, helper-command, and packaging dependencies.
11. [11-full-platform-lifecycle.md](11-full-platform-lifecycle.md) — package,
    installation, first-login, session, update, migration, refresh, and
    recovery lifecycle outside the shell host.
12. [12-full-plugin-lifecycle.md](12-full-plugin-lifecycle.md) — complete
    first-party and third-party plugin catalog, install/update/remove/clone
    lifecycle, trust boundaries, and reload states.
13. [13-ai-first-platform.md](13-ai-first-platform.md) — the agent-first
    operating model, lazy launchers, default agent, usage panel/collectors,
    skills, crash diagnosis, dictation relationship, and AI applications.
14. [14-capture-recording-and-dictation.md](14-capture-recording-and-dictation.md)
    — exact screenshot, screen-recording, webcam, OCR, QR, color, transcode,
    and Voxtype pipelines with their keybindings and dimensions.
15. [15-theme-wallpaper-and-cross-app-sync.md](15-theme-wallpaper-and-cross-app-sync.md)
    — theme repository rules, staging and atomic swap, wallpaper/video playback,
    image-picker contract, generated configs, and cross-application retinting.
16. [16-full-source-map-and-dependency-matrix.md](16-full-source-map-and-dependency-matrix.md)
    — full-repository source map, exact built-in manifest catalog, dependency
    ownership, and the source-versus-runtime verification boundary.
17. [17-claim-audit.md](17-claim-audit.md) — fixed source anchors, complete
    catalog checks, evidence classes, source quirks, and verification results.
18. [18-scope-and-nonclaims.md](18-scope-and-nonclaims.md) — declared scope,
    generic naming rules, implementation exactness gate, and explicit
    non-claims.
19. [19-plugin-facade-api-reference.md](19-plugin-facade-api-reference.md) —
    exact scoped facade properties, methods, ownership, and revocation.
20. [20-end-to-end-flow-coverage.md](20-end-to-end-flow-coverage.md) —
    end-to-end scenario matrix and the rule that every open, close, async, and
    handoff path must terminate with explicit cleanup.
21. [flows/01-session-and-host.md](flows/01-session-and-host.md) —
    session startup, host loading, bar construction, pointer dispatch,
    popout coordination, focus release, and reload teardown.
22. [flows/02-weather-panel.md](flows/02-weather-panel.md) —
    Weather bar click, full-screen detail card, data refresh, focus prime,
    Escape close, location-edit exception, and dismissal branches.
23. [flows/03-bar-panel-contract.md](flows/03-bar-panel-contract.md) —
    direct versus nested bar-panel ownership and the shared panel contract.
24. [flows/04-information-panels.md](flows/04-information-panels.md) —
    calendar and AI usage dashboard transitions.
25. [flows/05-device-and-connectivity-panels.md](flows/05-device-and-connectivity-panels.md) —
    audio, Bluetooth, display, power, network, credentials, QR, speed-test,
    and captive-portal transitions.
26. [flows/06-auxiliary-panels.md](flows/06-auxiliary-panels.md) —
    Dropbox, Tailscale, Internet/Disk tests, and Wi-Fi QR cancellation and
    stale-process guards.
27. [flows/07-menu-and-overlays.md](flows/07-menu-and-overlays.md) —
    menu, clipboard, emoji, image selector, reminder, and developer-gallery
    request/action/close flows.
28. [flows/08-services-and-modal-surfaces.md](flows/08-services-and-modal-surfaces.md) —
    background, notifications, OSD, lock/unlock, policy authentication, media,
    battery, idle, and night-light lifecycles.
29. [flows/09-theme-capture-and-platform.md](flows/09-theme-capture-and-platform.md) —
    theme, wallpaper, image-picker, screenshot, recording, OCR, QR, color,
    transcode, sharing, dictation, and platform lifecycle transitions.
30. [flows/10-plugin-lifecycle.md](flows/10-plugin-lifecycle.md) —
    add, validate, enable, scan, load, facade injection, clone, update,
    disable, remove, backup, and serialized reload.
31. [flows/11-ai-first-lifecycle.md](flows/11-ai-first-lifecycle.md) —
    lazy agents, default selection, launches, usage collectors, AI apps,
    skills, crash handoff, sync, and dictation boundaries.
32. [flows/12-bar-widgets-and-indicators.md](flows/12-bar-widgets-and-indicators.md) —
    simple bar widgets, indicator group, tray drawer/menus, visibility, and
    every built-in indicator action.

## Vocabulary

| Blueprint term | Meaning in an implementation |
|---|---|
| shell host | One long-running Quickshell process per graphical session |
| first-party | Code shipped in the host distribution and scanned like any other plugin |
| local plugin | User-owned plugin source under the user configuration directory |
| bar widget | A component inserted into one of three bar sections |
| panel | A floating, keyboard-focusable surface, commonly summoned from a widget |
| overlay | A full-screen modal surface, usually with its own layer-shell window |
| service | A headless singleton-like component loaded into the shell host |
| bar option | A complete bar implementation; only one is active at a time |
| inline settings | Arbitrary JSON fields placed beside an entry's `id` |
| host IPC | The stable IPC target used for plugin discovery, lifecycle, and layout |

## What “1:1” means here

A matching implementation must preserve all of the following, not only the
visual appearance:

- one host process and property-injected shared service instances;
- manifest-driven discovery for both shipped and user code;
- fail-closed relative entry-point validation and reserved namespace rules;
- separate enablement semantics for bar options, bar widgets, first-party
  infrastructure, and user plugins;
- a single authoritative user state file with no deep merge after customization;
- serialized, asynchronous loading and queued payload delivery;
- per-monitor bar instances with focused-monitor panel routing;
- one-poppable-at-a-time behavior and click-through overlay masks;
- keyboard-first panels with a single shared cursor model;
- dynamic theme values with a rem-based typography and spacing scale;
- native Hyprland/Wayland/UPower/PipeWire/notification integration where the
  reference uses it;
- the exact default constants documented in the measurement tables;
- the same fallback, timeout, debounce, persistence, and cleanup behavior.

If a new implementation changes one of these intentionally, it is a different
product architecture rather than a 1:1 reconstruction.
