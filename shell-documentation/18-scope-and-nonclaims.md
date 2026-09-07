# Scope, naming, and non-claims

## Declared reconstruction scope

The blueprint covers the long-lived graphical shell and the platform surfaces
that directly make the requested shell behavior possible:

~~~text
Quickshell host and shared QML modules
three-section multi-monitor bar
first-party manifest-backed plugins
third-party plugin add/update/remove/clone/reload paths
persisted shell state and host/plugin IPC
common controls, panel geometry, focus, cursor, and motion
background and wallpaper rendering
notifications and notification persistence
lock, polkit, battery, idle, media, audio, Bluetooth, network, power, and
  night-light service contracts used by the shell
command menu, application library, clipboard, emoji, image, QR, reminders,
  speed-test, and developer-gallery surfaces
screenshot, recording, webcam, OCR, QR, color, transcode, share, and dictation
AI-agent dispatch, usage collectors, skills, crash-to-agent, and AI app
  lifecycle relationships
theme installation, generated templates, wallpapers, image picker, unlock
  assets, and cross-application retinting
framework imports, external command contracts, package ownership, and update
  boundaries
~~~

This is the scope requested by the shell source and the follow-up request. It
is intentionally broader than the shell directory but narrower than a
behavioral re-documentation of every file in the 1,807-file repository.

## Full-repository inventory versus full-repository behavior

16-full-source-map-and-dependency-matrix.md inventories the complete repository
topology relevant to package ownership and records the exact shell tree at the
full audit anchor. 09-verification-and-source-map.md supplies the complete
historical shell path ledger plus the eight current additions.

The following repository areas are not claimed to be fully behaviorally
specified unless a requested shell surface directly depends on them:

- unrelated browser, gaming, office, editor, media, and commercial-app
  installation internals;
- hardware-specific branches that do not affect the documented shell contract;
- ISO/image-builder internals and every bootloader repair path;
- every individual migration unrelated to shell, themes, AI, capture,
  notifications, or the update boundary;
- all user manual chapters unrelated to the requested surfaces;
- every acceptance test interaction and every external provider protocol.

Those areas are not silently represented by generic prose. Where they are a
dependency, the documents name the source path and describe only the contract
the shell consumes.

## Generic naming rule

The main prose replaces product-specific names with roles and placeholders so
the document is reusable as an architecture blueprint. This does not add
capabilities:

~~~text
“bar widget” means a manifest-backed bar-widget kind
“complete bar” means the single active bar kind
“agent dashboard” means the file-backed usage panel
“cloud-sync panel” and “tunnel/VPN panel” are role labels for source features
“namespace” means the source's configuration/plugin/state namespace
~~~

The exact source IDs, file paths, command names, package names, manifest
catalog, and source anchor are retained in catalog/cross-check sections where
removing them would make a 1:1 implementation ambiguous. A builder may rename
them only as a consistent namespace substitution; it must not infer new
behavior from the generic label.

## Evidence classes

Each statement belongs to one of these classes:

| Class | Evidence | What it permits |
|---|---|---|
| source-inspected | source file, manifest, template, or manual read at the fixed commit | state the source-defined rule |
| test-inspected | test source read or source contract checked by an automated audit | state the tested invariant and its exact limits |
| isolated-tested | pure/helper or temporary-sandbox execution | state only the isolated behavior exercised |
| runtime-unverified | requires Quickshell, Hyprland, hardware, packages, DBus, network, or real user state | cannot be called proven by this folder |
| source-quirk | source behavior that differs from idealized expectations | must be preserved or consciously changed |

No isolated test was promoted to an end-to-end claim. No live installer,
package transaction, reboot, graphical activation, or live user configuration
mutation was performed for this documentation task.

## Exactness gate for an implementation

To call an implementation source-identical, all of the following are required:

1. pin the implementation to the audited source anchor or complete a new
   source-diff audit;
2. implement every source-defined path and contract in the focused documents;
3. preserve source quirks unless the result is explicitly labeled a
   deliberate compatibility change;
4. use the exact base measurements, formulas, timing, fallback, persistence,
   process, and IPC rules;
5. provide the same external dependency versions/capabilities or record the
   resulting divergence;
6. run pure and isolated tests;
7. run graphical acceptance tests for focus, layer-shell, multi-monitor,
   pointer, keyboard, image, notification, bar, and transition behavior;
8. run a scoped integration matrix for package setup, user finalization,
   systemd, DBus, PAM/polkit, PipeWire, camera/GPU, network, theme retinting,
   agent providers, and update/recovery;
9. compare screenshots and interaction traces at the same display scale,
   font configuration, compositor settings, and asset revisions;
10. report failed or untested cases separately rather than calling the whole
    system “fully verified”.

The Markdown folder is the build specification and evidence record. It is not
a substitute for these runtime gates.

## Explicit non-claims

This folder does not claim that the source:

- contains an embedded LLM or cloud AI service;
- provides an operating-system sandbox for third-party QML;
- authenticates arbitrary Git plugins or themes;
- automatically generates settings forms from manifest schema;
- enforces bar-widget allowMultiple at registry level;
- provides a dedicated screenshot, recording, or color QML plugin;
- provides a dedicated color-capture executable;
- deep-merges customized shell configuration with new defaults;
- makes kept plugin code hot-reload in place;
- makes all third-party services QObject children of the visual host;
- gives every plugin unrestricted host service access;
- makes unrelated full-repository features part of the shell contract.

These non-claims prevent the generic wording from becoming an accidental
feature list.

## Source cross-check

~~~text
17-claim-audit.md
01-runtime-architecture.md
02-plugin-system.md
03-state-and-ipc.md
04-design-language.md
05-ui-kit-and-measurements.md
06-bar-engine.md
07-feature-catalog.md
07a-system-services-and-hosted-surfaces.md
07b-bar-widgets-and-device-panels.md
07c-overlays-data-contracts-and-assets.md
08-build-and-acceptance-blueprint.md
09-verification-and-source-map.md
10-external-tool-contract.md
11-full-platform-lifecycle.md
12-full-plugin-lifecycle.md
13-ai-first-platform.md
14-capture-recording-and-dictation.md
15-theme-wallpaper-and-cross-app-sync.md
16-full-source-map-and-dependency-matrix.md
~~~
