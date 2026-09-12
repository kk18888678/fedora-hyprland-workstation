# Aurelia–Omarchy Plugin Parity Tracker

Status: planning only. No implementation work is authorized by this document.

## Objective

Bring Aurelia Shell to the Omarchy plugin architecture and lifecycle as closely
as possible, with Omarchy treated as the structural reference and Aurelia's
existing capabilities, naming, design language, and safety policy preserved.

The target is not a visual rewrite of Aurelia. The target is parity of:

- plugin packaging;
- manifest semantics;
- discovery and cataloguing;
- runtime loading;
- lifecycle and reload behavior;
- bar registration and placement;
- persisted configuration;
- plugin API boundaries;
- cloning and user customization;
- CLI and management workflows;
- observability;
- tests and acceptance evidence.

No task may remove or weaken an existing Aurelia feature merely to make the
reference architecture easier to copy.

## Reference and working-state baseline

This tracker was created after a read-only comparison of:

- Aurelia initial audit HEAD: `a18bd5cb14513aaab8840ccb9037ce629bde2ac8`;
- Aurelia Git checkpoint: `9f3781d19260b12d8f55836132cc5822789d4bde`;
- Aurelia current pre-T01 baseline: branch `installer-resilience`, HEAD
  `e6a48b2a61baa1e1b381935f4208e4dbc77dc61b`;
- Omarchy reference: `/tmp/omarchy-reference`, branch `quattro`, HEAD
  `b5589faaf80c6f87c07d4560fca37c4a81722f28`.

The Aurelia working tree already contained unrelated modified and untracked
files. Those files are user-owned and must be preserved. Reconfirm the exact
inventory in T00 before implementing any task.

Observed baseline at audit time:

- Aurelia has a resident host, `PluginRegistry`, `PluginHost`, `ShellConfig`,
  manifests, user plugin discovery, plugin CLI commands, development reload,
  and centralized tests.
- Omarchy has a resident host, manifest registry, dedicated bar registry,
  scoped plugin facades, a unified shell state model, plugin catalog, clone
  workflow, plugin management commands, and broader plugin contract tests.
- Neither repository has test directories inside each plugin directory.
- Aurelia's plugin-local test-directory count is `0`; Omarchy's is also `0`.
- Aurelia's current plugin test suite and root test suite are centralized and
  must remain available through their existing entry points.

## Execution rules

All work must proceed in this order. A task is not complete because its code
exists; its completion requires the evidence listed in the task and a clean
review of the impact gates.

- [ ] Do not run `./install.sh`, reboot, restart greetd, change graphical
  activation, modify live PAM/greetd/Hyprland/Noctalia state, or install/remove
  packages as part of plugin parity work.
- [ ] Keep all new runtime behavior behind additive compatibility paths until
  the corresponding contract and migration tests pass.
- [ ] Preserve current Aurelia configuration and user data. Migrations must be
  idempotent, recoverable, and safe to interrupt.
- [ ] Keep one mutation owner per state transition. Plugin UI may change only
  in-memory state; the host/reconciler that owns the state performs persistence.
- [ ] Never treat same-process facades as a security sandbox. Third-party QML
  remains unsandboxed and must be clearly labelled as such.
- [ ] Do not copy Omarchy's arbitrary `bash -lc` custom-command execution into
  Aurelia. Aurelia's structured-argv and bounded-execution policy remains in
  force.
- [ ] Do not add a dependency resolver, marketplace, or other extension point
  unless a later task demonstrates a concrete requirement. Neither current
  implementation provides a general plugin dependency resolver.
- [ ] Do not change Aurelia colors, typography, spacing, icon treatment,
  animation policy, panel geometry, or feature behavior merely to match
  Omarchy's appearance. Use Aurelia's design tokens and UI primitives.
- [ ] Treat host survivability under plugin failure as a P0 gate. No plugin
  parity feature may proceed beyond T02A without evidence that a faulty plugin
  cannot prevent the host and healthy plugins from loading.
- [ ] Do not create duplicate compatibility implementations. Compatibility
  aliases must forward to one canonical owner.
- [ ] Do not mark a task complete based only on static inspection when runtime
  behavior is part of its acceptance criteria.

## Status and evidence convention

Use these markers in this file during implementation:

- `[ ]` not started;
- `[-]` in progress;
- `[x]` complete with evidence recorded;
- `[!]` blocked or failed; record the reason and do not silently skip it.

Every completed task must record:

```text
Evidence:
- Tests:
- Runtime/fixture evidence:
- Files changed:
- User-visible behavior changed: yes/no
- Existing Aurelia feature impact:
- Rollback/migration evidence:
- Review:
```

## Mandatory checkpoint protocol

Checkpoints are required before any source, test, manifest, configuration, or
runtime implementation file is edited. The tracker itself may be edited to
record checkpoint state; that does not count as implementation.

### CP0 — Working-tree and runtime baseline freeze

Status: `[x]` complete for the current pre-T01 baseline.

Before the first implementation edit:

- [x] Capture branch, HEAD, full `git status`, tracked diff summary, and
  untracked-file inventory.
- [x] Confirm which existing changes belong to the user and must not be
  overwritten.
- [x] Capture the current Aurelia manifest/plugin inventory and Omarchy
  reference inventory.
- [x] Run the existing repository and Aurelia test entry points in isolated
  mode and record exact pass/fail/skip results.
- [x] Run repository-wide shell syntax validation.
- [x] Record available optional verification tools without installing anything.
- [x] Record that `./install.sh`, package transactions, live configuration
  changes, greetd/systemd changes, and reboot are out of scope.

Stop condition: do not edit implementation code until CP0 is recorded in this
file and the user-visible baseline is understood.

Current CP0 capture (read-only, frozen for T01):

- Date: `2026-09-11`.
- Git checkpoint ancestor: `9f3781d19260b12d8f55836132cc5822789d4bde`.
- Current pre-T01 HEAD: `e6a48b2a61baa1e1b381935f4208e4dbc77dc61b`.
- Aurelia: `21` plugin manifests, `21` top-level plugin directories, and `0`
  plugin-local test directories.
- Omarchy reference: `37` manifest entries (`29` conventional plus `8` sibling
  manifests), and `0` plugin-local test directories.
- Current repository tests: `228` passed, `0` failed.
- Current Aurelia Shell tests: `282` passed, `0` failed.
- Repository-wide shell syntax: `199` scripts passed `bash -n`.
- ShellCheck: unavailable; no installation attempted.
- The current working tree is clean after the user-owned commits above. The
  committed snapshot includes the pre-existing Aurelia/installer changes and
  this tracker. No implementation file may be overwritten or normalized as
  part of future checkpointing.

CP0 is closed for the current baseline. If the working tree changes before a
future task's CP2, re-baseline before editing that task.

### CP1 — Contract and test readiness

Before the first behavior change:

- [ ] T00, T01, T02, and T02A are reviewed and complete.
- [ ] The exact manifest/state/API contract for the next task is written down.
- [ ] The preservation fixture for every affected Aurelia feature exists.
- [ ] The isolated test or fixture that will fail if the next change regresses
  the contract is present.
- [ ] The planned file ownership and mutation owner are identified.
- [ ] The expected user-visible and runtime impact is explicitly `none` until
  the controlled cutover task.

Stop condition: no implementation edit is allowed if the contract, test, or
rollback path is still ambiguous.

### CP2 — Per-task pre-change checkpoint

Before each individual task implementation:

- [ ] Re-run `git status --short` and confirm no unrelated user changes are
  being included.
- [ ] Re-run the smallest relevant existing tests and confirm their baseline
  result.
- [ ] Record the exact files that may change for the task.
- [ ] Record the migration/rollback strategy and whether the task changes
  runtime behavior, persisted state, or only development tooling.
- [ ] Confirm no live workstation mutation is required.

Stop condition: if the working tree changes unexpectedly or a baseline test
regresses before editing, stop and re-baseline; do not overwrite or repair the
unexpected change.

### CP3 — Per-task post-change checkpoint

After each task implementation and before marking it complete:

- [ ] Run the task's focused tests.
- [ ] Run all affected feature tests.
- [ ] Run the full repository and Aurelia test entry points when the task
  changes shared host, registry, configuration, or lifecycle code.
- [ ] Run syntax checks for every changed shell script and relevant QML/JS
  runtime fixture checks.
- [ ] Review the diff for unintended changes to existing Aurelia features,
  design tokens, user data, ownership, and privilege boundaries.
- [ ] Verify no temporary files, generated state, or test artifacts remain in
  the repository.
- [ ] Record exact evidence and update the task checkbox only after all gates
  pass.

Stop condition: a failed post-change checkpoint blocks the next task. Repair
or revert only the task's owned changes; never use destructive Git commands to
erase unrelated worktree state.

### CP4 — Phase checkpoint

Before moving to the next phase:

- [ ] Every task in the completed phase has CP3 evidence.
- [ ] Shared tests are green.
- [ ] No known regression or unclassified risk is carried forward silently.
- [ ] The next phase's contract and test additions are reviewed before code
  changes begin.

### CP5 — Final parity checkpoint

Before declaring parity complete:

- [ ] T28 is complete.
- [ ] All gap-to-task rows are closed with evidence.
- [ ] All preservation gates pass.
- [ ] Runtime/visual evidence is separated from static/isolated evidence.
- [ ] The final working-tree diff is reviewed file-by-file.

No task may skip a checkpoint because it is “small,” “only a refactor,” or
“test-only.” Shared host and plugin code can change runtime behavior indirectly.

---

## Phase 0 — Freeze the baseline before changing behavior

### T00. Rebuild the inventory and acceptance matrix

Status: `[x]` complete — CP0 evidence captured against HEAD
`e6a48b2a61baa1e1b381935f4208e4dbc77dc61b`.

- [x] Recount all Aurelia plugin directories and manifests, including files
  currently untracked in the working tree.
- [x] Recount all Omarchy conventional and sibling manifests from the pinned
  reference checkout.
- [x] Record every manifest ID, kind, entry point, `keepLoaded` value, bar
  metadata field, local dependency, and plugin-specific state file.
- [x] Record all current Aurelia IPC targets and methods.
- [x] Record all current Aurelia feature plugins and custom features that must
  remain unchanged.
- [x] Record current Aurelia bar layout, theme tokens, panel geometry, keyboard
  behavior, backend commands, and failure classifications as preservation
  fixtures.
- [x] Record current test commands, pass counts, optional skips, and available
  runtime tools without changing the live workstation.
- [x] Record the starting Git status and ensure all pre-existing changes are
  distinguishable from future parity changes.
- [x] Complete CP0 and record its exact evidence before beginning T01 or any
  implementation task.

Exit gate: CP0 is complete, a complete inventory exists in this tracker/task
evidence, and every existing Aurelia feature has an explicit owner.

Dependencies: none.

### T01. Freeze the reference contract and vocabulary

Status: `[x]` complete — CP2 and CP3 passed; documentation-only task.

CP2 pre-change boundary:

- Allowed files: this tracker and
  `aurelia-shell/docs/aurelia-plugin-contract-v1.md`.
- Runtime/source behavior impact: none intended.
- Persisted user state impact: none.
- Rollback: remove only the task-owned documentation changes if verification
  fails; preserve all other worktree history.

CP3 post-change evidence:

- Tests: `./tests/run.sh` — `228` passed, `0` failed.
- Tests: `./aurelia-shell/tests/run.sh` — `282` passed, `0` failed.
- Syntax: repository-wide `bash -n` — `199` scripts passed.
- Diff validation: `git diff --check` passed.
- Runtime/fixture evidence: no runtime behavior changed; live QML smoke tests
  were not enabled for this documentation-only task.
- Files changed: this tracker and
  `aurelia-shell/docs/aurelia-plugin-contract-v1.md`.
- User-visible behavior changed: no.
- Existing Aurelia feature impact: none intended and no feature source changed.
- Rollback/migration evidence: documentation-only; no persisted state touched.
- Review: canonical manifest, state, lifecycle, failure-containment, API,
  testing, and migration rules are recorded in the contract document.

- [x] Define the exact Aurelia parity vocabulary from Omarchy: plugin, manifest,
  kind, entry point, service, panel, overlay, menu, bar-widget, bar option,
  plugin instance, enabled, active, loaded, visible, and clone.
- [x] Adopt one exact kind-to-entry-point mapping for the public contract.
- [x] Decide the compatibility treatment for Aurelia's current
  `entryPoints["bar-widget"]` spelling versus Omarchy's `entryPoints.barWidget`.
- [x] Define the reserved first-party namespace and user-plugin namespace.
- [x] Define which manifest fields are required, optional, first-party-only,
  user-visible, or host-internal.
- [x] Include the reference optional metadata surface where it has real
  behavior: `license`, `activation`, `barWidget`, `defaults`, `schema`,
  `settingsForm`, `clonePaths`, and trusted first-party capability metadata.
- [x] Define the exact semantics of `keepLoaded`, multi-kind plugins, multiple
  bar-widget instances, disabled plugins, and active replacement bars.
- [x] Define the compatibility policy: old Aurelia manifests and old
  `shell.json` state must remain readable during migration; new writes use the
  canonical parity format only after the migration gate.
- [x] Do not add a second competing manifest schema.

Exit gate: a reviewed, versioned contract exists before behavior is migrated.

Dependencies: T00.

### T02. Establish the parity test harness and golden preservation checks

Status: `[x]` complete — CP2 and CP3 passed; test-domain-only task.

CP2 pre-change boundary:

- Allowed files: `aurelia-shell/tests/`,
  `aurelia-shell/docs/` only where test documentation is required, and this
  tracker.
- Runtime/source behavior impact: none intended.
- Persisted user state impact: none.
- Rollback: remove only T02-owned test harness/fixture/tracker changes if a
  mandatory gate fails; preserve all production and user-owned files.

CP3 post-change evidence:

- Tests: `./aurelia-shell/tests/test_plugin_harness.sh` — `13` passed,
  `0` failed.
- Tests: `./aurelia-shell/tests/run.sh` — `295` passed, `0` failed.
- Tests: `./tests/run.sh` — `228` passed, `0` failed.
- Syntax: repository-wide `bash -n` — `203` scripts passed.
- Diff validation: `git diff --check` passed.
- Runtime/fixture evidence: reusable fixture creation and preservation checks
  passed; live QML tests remain separately classified and were not enabled.
- Files changed: `aurelia-shell/tests/plugin/`,
  `aurelia-shell/tests/fixtures/plugin-preservation.json`,
  `aurelia-shell/tests/test_plugin_harness.sh`,
  `aurelia-shell/tests/run.sh`, and this tracker.
- User-visible behavior changed: no.
- Existing Aurelia feature impact: no production/plugin implementation files
  changed; current manifest/layout/design/backend preservation checks passed.
- Rollback/migration evidence: test-only temporary sandboxes are cleaned by the
  harness; no live or persisted user state was touched.
- Review: T02 establishes tagged static, fixture, isolated-runtime, and
  skipped-live-session result labels for later plugin tests.

- [x] Keep `./tests/run.sh` as the repository test entry point.
- [x] Keep `./aurelia-shell/tests/run.sh` as the Aurelia Shell test entry point.
- [x] Add a coherent plugin-test domain under `aurelia-shell/tests/` rather than
  scattering contract assertions through unrelated feature tests.
- [x] Add reusable fixtures for temporary first-party and third-party plugin
  trees, temporary `shell.json`, malformed manifests, duplicate IDs, symlinked
  trees, and failing entry points.
- [x] Add golden preservation checks for current Aurelia plugin IDs, layout
  entries, theme tokens, design primitives, and backend command ownership.
- [x] Add a test result format that distinguishes static, isolated runtime,
  live-session, and skipped evidence.
- [x] Do not delete or weaken current feature tests while adding the harness.

Exit gate: the harness can run without installer execution or live system
mutation, and the current Aurelia behavior has a repeatable baseline.

Dependencies: T00, T01.

### T02A. Establish the non-negotiable Aurelia host-survivability contract

Status: `[x]` complete — CP2 and CP3 passed; host failure-containment task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/PluginRegistry.qml`,
  `aurelia-shell/services/PluginHost.qml`, and the Aurelia bar widget boundary
  files required to report widget failures.
- Allowed test files: `aurelia-shell/tests/`, including isolated
  `plugin-survivability` fixtures and this tracker.
- Runtime behavior impact: intentionally additive failure containment only;
  healthy-plugin behavior and the built-in default path must remain unchanged.
- Persisted user state impact: none; failure/quarantine state is in-memory and
  must not disable or remove plugins from user configuration.
- Rollback: revert only T02A-owned production/test/tracker changes if any
  checkpoint fails; preserve the T00/T01/T02 commits and user-owned history.

CP3 post-change evidence:

- Focused runtime gate: test_plugin_survivability.sh — 4 assertions passed,
  0 failed, including a disposable offscreen QuickShell process.
- Isolated runtime coverage: malformed/syntax and missing entry points,
  host-controlled initialization, service initialization, open, close, toggle,
  and IPC callback exceptions, bar-widget construction/callback failure,
  simultaneous failures, explicit reload retry, no-retry-loop behavior, host
  ping/listPlugins responses, healthy panel/service/widget continuity, and
  replacement-bar fallback.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 299 passed, 0
  failed. The T02A isolated runtime gate ran as part of this count.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 204 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.
- Files changed for T02A: PluginRegistry.qml, PluginHost.qml,
  BarWidgetSlot.qml, aurelia-shell/tests/run.sh,
  aurelia-shell/tests/test_plugin_survivability.sh, and the isolated
  tests/fixtures/plugin-survivability/ fixtures.
- Concurrent user-owned notification edits appeared during this task and were
  intentionally kept outside the T02A commit; they were subsequently committed
  separately as 40ed5bb (feat(notifications): compact popup surfaces).
- Evidence classification: loader/callback survival and healthy-plugin
  continuity are isolated-runtime tested; manifest-discovery continuation and
  same-process limits remain code-inspected/contract-documented. QML
  Component.onCompleted exceptions are demonstrably non-fatal but are not
  exposed by Qt as Loader.Error; the opt-in aureliaInitialize hook covers the
  host-controlled initialization boundary. Deliberate Qt.quit(), native
  crashes, and engine corruption remain outside the same-process guarantee.

This is the first runtime-safety gate. The required behavior is:

```text
one faulty plugin
        -> plugin is rejected, contained, quarantined, or unloaded
        -> Aurelia host remains alive
        -> shell ping/listPlugins still respond
        -> healthy services, panels, overlays, menus, and bar widgets continue
        -> built-in bar fallback remains available
```

- [x] Define the failure classes that must be contained: malformed manifest,
  missing entry point, unsafe import/path, QML syntax/import failure,
  `Component.onCompleted` failure, plugin initialization failure, plugin
  service failure, bar-widget construction failure, and exceptions raised by
  plugin `open`, `close`, `toggle`, or IPC methods.
- [x] Keep discovery failure isolated from host startup. A single rejected
  manifest must not make the complete registry unavailable.
- [x] Keep each plugin entry point behind an independent load boundary. A
  failed panel, overlay, menu, service, widget, or replacement bar must not
  terminate or invalidate unrelated loaders.
- [x] Guard every host-to-plugin callback and bar-widget invocation at the
  boundary. A thrown plugin callback must become a recorded plugin failure,
  not an uncaught host failure.
- [x] Add per-plugin failure state with plugin ID, kind, source/entry point,
  failure phase, bounded error detail, timestamp or generation, and retry or
  quarantine state.
- [x] Prevent an immediately failing plugin from entering an uncontrolled
  reload loop. Retry only through an explicit bounded policy or after a source
  generation/configuration change.
- [x] Preserve the last known-good host and healthy plugin state when a reload
  introduces a bad plugin. A failed replacement bar must fall back to the
  built-in Aurelia bar.
- [x] Ensure failure reporting cannot mutate user configuration, remove user
  data, or disable healthy plugins as a side effect.
- [x] Add an isolated runtime fixture containing at least one deliberately
  broken plugin beside at least one healthy panel, one healthy service, one
  healthy bar widget, and the host IPC target.
- [x] Assert after the broken plugin is introduced that the host process is
  still alive, `ping` succeeds, `listPlugins` succeeds, the healthy plugin is
  loaded/usable, the bar remains available, and the bad plugin is explicitly
  reported as failed.
- [x] Repeat the fixture for syntax/import failure, initialization failure,
  service failure, bar-widget failure, callback exception, and reload-time
  failure.
- [x] Add a separate test for simultaneous failures to prove that failure
  handling is per plugin rather than a global “shell failed” state.

### Same-process boundary that must remain explicit

Omarchy and the current Aurelia design execute plugins as unsandboxed code in
the same Quickshell process. Loader and callback containment can protect the
host from ordinary malformed or failing plugin behavior, but cannot guarantee
survival if deliberately malicious code calls `Qt.quit()`, corrupts native
state, or triggers a process/engine crash. A true guarantee against that class
requires an out-of-process sandbox and would no longer be 1:1 with Omarchy.
The parity requirement for this tracker is therefore strict containment of
faulty plugin loading, initialization, callbacks, and reloads; this limitation
must not be hidden or described as a security sandbox.

Exit gate: a broken plugin is demonstrably non-fatal to the Aurelia host and
healthy plugins across all listed failure phases, with bounded diagnostics and
no uncontrolled retry loop.

Dependencies: T02.

---

## Phase 1 — Make the manifest and discovery layers structurally compatible

### T03. Implement one canonical manifest validator

Status: `[x]` complete — CP2 and CP3 passed; canonical manifest-validation task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/bin/lib/aurelia-plugin/manifest.sh`,
  `aurelia-shell/services/PluginRegistry.qml`, and the runtime scan command
  wiring in that registry.
- Allowed test files: `aurelia-shell/tests/`, including an isolated manifest
  validator fixture, and this tracker.
- Compatibility boundary: canonical `entryPoints.barWidget` is added as the
  preferred form; existing `entryPoints["bar-widget"]` manifests remain
  readable, and legacy bar-widget metadata omissions remain loadable until the
  later migration/metadata tasks.
- Runtime behavior impact: validation and rejection only; no plugin source
  execution, loader activation, persisted-state write, or live-session change.
- Persisted user state impact: none.
- Rollback: revert only T03 validator/test/tracker changes if a mandatory gate
  fails; preserve the completed T00/T01/T02/T02A history and user-owned
  changes.

CP3 post-change evidence:

- Focused validator gate: test_manifest_validator.sh — 27 assertions passed,
  0 failed.
- Matrix coverage: the CLI and real QML registry accepted/rejected the same 25
  manifest cases, including canonical and legacy bar-widget keys, metadata
  types, unsafe paths, unknown public fields, namespace capability rules,
  compatibility metadata, clone paths, and all listed negative shapes.
- Mutation proof: runtime validation left every input matrix object byte-stable.
- Discovery proof: the real runtime registry scan invoked the canonical CLI
  validator and discovered all 21 current Aurelia manifests.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 326 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 205 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Compatibility: no existing plugin manifest was rewritten; current legacy
  entryPoints["bar-widget"] forms remain accepted, while canonical
  entryPoints.barWidget forms are supported and validated strictly.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.
- Files changed for T03: manifest.sh, PluginRegistry.qml,
  test_aurelia_shell_plugins.sh, aurelia-shell/tests/run.sh,
  test_manifest_validator.sh, and the isolated manifest-validator fixture.

- [x] Make runtime and CLI validation enforce the same manifest contract.
- [x] Validate schema version, ID, name, version, description, kinds, entry
  points, safe relative paths, regular-file entry points, and symlink policy.
- [x] Validate the exact kind-to-entry-point mapping.
- [x] Validate bar-widget metadata, including `displayName`, `description`,
  `category`, `allowMultiple`, `defaultSection`, `defaults`, `settingsForm`,
  and `schema` where the contract requires them.
- [x] Validate `keepLoaded` and all allowed metadata types.
- [x] Reject unknown or malformed public kinds fail-closed.
- [x] Preserve Aurelia-only metadata under an explicit Aurelia namespace rather
  than silently colliding with Omarchy fields.
- [x] Keep the validator mutation-free and ensure discovery never executes
  plugin code.
- [x] Keep any host/API compatibility metadata explicit and fail closed; do not
  use the plugin's display version as an implicit host compatibility check.
- [x] Add negative tests for every rejected shape.

Exit gate: a manifest accepted by the author-facing validator is accepted by
the runtime, and a manifest rejected by either boundary is not loadable.

Dependencies: T01, T02, T02A.

### T04. Match Omarchy's plugin tree discovery model

Status: `[x]` complete — plugin discovery parity task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/PluginRegistry.qml`,
  `aurelia-shell/bin/lib/aurelia-plugin/manifest.sh`, and the
  `aurelia-shell/bin/lib/aurelia-plugin/main.sh` validation wiring needed for
  sibling manifests.
- Allowed test files: `aurelia-shell/tests/`, including isolated
  discovery fixtures, and this tracker.
- Compatibility boundary: current one-directory Aurelia manifests and source
  checkout/installed-path resolution must continue to load unchanged; grouped
  first-party and sibling manifest support is additive.
- Runtime behavior impact: discovery/catalogue state only; no plugin source
  execution, UI activation, persisted-state write, or live-session change.
- Persisted user state impact: none.
- Rollback: revert only T04 discovery/validator/test/tracker changes if a
  mandatory gate fails; preserve completed T00–T03 history and user-owned
  changes.

CP3 post-change evidence:

- Focused discovery gate: test_plugin_discovery.sh — 6 assertions passed, 0
  failed.
- Runtime coverage: the real registry discovered grouped first-party
  directories, sibling *.manifest.json entries, top-level third-party
  plugins, deterministic duplicate handling, first-party precedence over a
  reserved-namespace shadow attempt, and rejected manifests.
- Failure-state coverage: malformed scanner output, empty valid catalogs, and
  timeout/unavailable state wiring are covered by the runtime fixture or
  explicit state assertions; prior-catalog retention remains a future
  integration extension.
- Sibling/grouped authoring path: the canonical validator accepted a sibling
  manifest and a grouped source directory whose basename differs from its ID.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 332 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 206 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Compatibility: current one-directory manifests remain unchanged and the
  source-checkout/installed-path resolver remains intact.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  discovery roots/XDG directories were used. ./install.sh was not run; no
  packages, repositories, systemd/greetd state, live user configuration, or
  the VM were modified, and no reboot occurred.
- Files changed for T04: PluginRegistry.qml, manifest.sh, main.sh,
  aurelia-shell/tests/run.sh, test_plugin_discovery.sh, and the isolated
  plugin-discovery fixture.

- [x] Support grouped first-party plugin directories at the same structural
  depth as the reference.
- [x] Support sibling `*.manifest.json` entries where a single first-party
  source directory intentionally owns multiple simple bar widgets.
- [x] Keep third-party plugins as top-level user-owned plugin directories with
  one canonical manifest per plugin.
- [x] Preserve Aurelia's safe path checks, no-symlink-tree policy, and reserved
  namespace checks.
- [x] Define deterministic ordering and duplicate-ID resolution.
- [x] Ensure first-party entries cannot be shadowed by user entries.
- [x] Preserve the current source-checkout and installed-path resolution.
- [x] Add scan failure states that retain safe previous state or fail closed;
  never report a successful partial catalog without recording the failure.
- [x] Bound the scan process and distinguish timeout, unavailable tooling,
  malformed output, and an empty valid catalog.

Exit gate: discovery structure and ordering match the reference for equivalent
trees, while current Aurelia directories continue to load unchanged.

Dependencies: T03.

### T05. Add a single source-aware plugin catalog

Status: `[x]` complete — source-aware plugin catalog task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/PluginRegistry.qml`,
  `aurelia-shell/services/PluginHost.qml`, `aurelia-shell/shell.qml`, and the
  plugin CLI files needed to expose the catalog.
- Allowed test files: `aurelia-shell/tests/`, including isolated
  catalog fixtures, and this tracker.
- Compatibility boundary: existing `listPlugins` array output and current
  plugin lifecycle commands remain readable; catalog output is additive.
- Runtime behavior impact: read-only catalog projection and diagnostics only;
  no plugin activation, source execution, or persisted-state mutation.
- Persisted user state impact: none.
- Rollback: revert only T05 catalog/CLI/test/tracker changes if a mandatory
  gate fails; preserve completed T00–T04 history and user-owned changes.

CP3 post-change evidence:

- Focused catalog gate: test_plugin_catalog.sh — 4 assertions passed, 0
  failed.
- Catalog coverage: registry projection includes ID, name, version, author,
  license, description, kinds, canonical entry points, bar metadata, source
  root, manifest path, enablement, lifecycle state, failures, scan state, and
  rejected-manifest diagnostics.
- Runtime coverage: a real offscreen registry scan produced a 21-plugin
  catalog; legacy Aurelia bar-widget keys were projected as canonical
  barWidget keys without changing the source manifests.
- CLI coverage: catalog --json and the human-readable catalog consume a
  resident shell catalog response; existing listPlugins output remains
  available.
- Read-only boundary: catalog IPC reads PluginRegistry directly and does not
  invoke plugin visibility/callback methods.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 336 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 207 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.

- [x] Add a catalog projection containing ID, name, description, kinds, source
  root, manifest path, entry points, first-party status, version, and bar
  metadata.
- [x] Make CLI commands and management UI consume the catalog instead of
  reimplementing manifest walking.
- [x] Expose machine-readable JSON and human-readable output.
- [x] Include rejected manifests and reasons in a diagnostic projection without
  making rejected code loadable.
- [x] Keep catalog generation read-only and bounded.
- [x] Add duplicate-ID and reserved-namespace catalog tests.

Exit gate: every plugin-management consumer uses the same catalog projection.

Dependencies: T04.

---

## Phase 2 — Build the Omarchy-level runtime composition boundaries

### T06. Separate registry, component catalog, services, and UI loaders

Status: `[x]` complete — runtime composition-boundary task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/BarWidgetRegistry.qml`,
  the services `qmldir`, `PluginHost.qml`, the Aurelia bar
  composition files, `shell.qml`, and the plugin contract files needed
  for structured lifecycle events.
- Allowed test files: `aurelia-shell/tests/`, including isolated
  bar-registry/runtime-composition fixtures, and this tracker.
- Compatibility boundary: current bar layout, widget IDs, service ownership,
  popup behavior, and plugin IPC identities must remain unchanged.
- Runtime behavior impact: composition ownership and event observability only;
  no persisted-state schema change, installer mutation, or live-session change.
- Persisted user state impact: none.
- Rollback: revert only T06 composition/test/tracker changes if a mandatory
  gate fails; preserve completed T00–T05 history and user-owned changes.

CP3 post-change evidence:

- Focused composition gate: test_bar_widget_registry.sh — 4 assertions passed,
  0 failed.
- Runtime coverage: the real registry scan populated a dedicated
  BarWidgetRegistry with the current bar-widget set, canonical entry-point
  projection, Bluetooth metadata, and the multi-kind notification widget.
- Ownership coverage: Bar, BarCenter, BarWidgetRow, and BarWidgetSlot receive
  the dedicated registry; the host injects it without changing existing
  widget IDs or layout data.
- Lifecycle coverage: PluginHost now emits structured loaded, load-failed,
  unloaded, and reloaded events; existing T02A survivability fixtures remain
  green.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 340 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 208 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Compatibility: current bar layout, service ownership, popup behavior, and
  plugin IPC identities were preserved; no plugin manifests or persisted state
  were changed.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.
- [x] Add the Aurelia equivalent of `BarWidgetRegistry` for component and
  metadata registration.
- [x] Keep the plugin registry responsible for discovery and identity only.
- [x] Keep the host responsible for lifecycle and loading only.
- [x] Keep services resident according to manifest semantics and ensure one
  service instance per enabled plugin ID.
- [x] Load panel, overlay, and menu entry points on demand.
- [x] Load bar-widget entry points through the bar registry and configured
  layout slots.
- [x] Preserve payload queues and deterministic delivery for summons that occur
  before asynchronous loading completes.
- [x] Emit structured load success, load failure, unload, and reload events.
- [x] Ensure a failing optional plugin cannot break the Aurelia host or login
  activation.

Exit gate: a fixture can exercise each supported kind through its intended
owner without any feature-specific host branch being required.

Dependencies: T02A, T03, T04, T05.

### T07. Implement exact `keepLoaded` and multi-kind lifecycle semantics

Status: `[x]` complete — resident and multi-kind lifecycle task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/PluginHost.qml`,
  `BarWidgetRegistry.qml`, the Aurelia bar boundary files, and the
  structured plugin lifecycle contract files needed for resident ownership.
- Allowed test files: `aurelia-shell/tests/`, including isolated
  multi-kind, resident-reload, pending-open, and unload fixtures, and this
  tracker.
- Compatibility boundary: notification service ownership, bar-widget behavior,
  current keepLoaded values, payload delivery, and plugin IPC identities must
  remain unchanged for healthy plugins.
- Runtime behavior impact: reload retention and lifecycle observability only;
  no persisted-state schema or live-session mutation.
- Persisted user state impact: none.
- Rollback: revert only T07 lifecycle/test/tracker changes if a mandatory gate
  fails; preserve completed T00–T06 history and user-owned changes.

CP3 post-change evidence:

- Focused lifecycle gate: test_plugin_lifecycle.sh — 3 assertions passed, 0
  failed.
- Runtime coverage: one resident service instance and one kept panel retained
  object identity across a full reload; a service+bar-widget and
  menu+bar-widget plugin used separate owners; two pending summons delivered
  in order; toggle/close worked; and a non-kept panel unloaded after close.
- Host behavior: reload now preserves resident/keepLoaded instances, pending
  opens use ordered queues, and reload/unload lifecycle events are emitted.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 343 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 209 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Compatibility: current notification service residency, bar-widget behavior,
  payload contract, and IPC identities were preserved; no persisted state or
  plugin manifests were changed.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.

- [x] Define one canonical primary service owner for a multi-kind plugin.
- [x] Load every declared functional kind through its own entry point when the
  kind requires an independent surface.
- [x] Keep services and explicitly kept UI surfaces alive across a plugin
  rescan according to the manifest.
- [x] Do not destroy session-lock, notification-bus, or other sensitive/stateful
  owners during an unrelated plugin reload.
- [x] Preserve current Aurelia notification service plus bar-widget behavior.
- [x] Add runtime tests for service-plus-widget and menu-plus-widget fixtures.
- [x] Add tests for pending opens, repeated summons, close, toggle, and unload.

Exit gate: reload behavior is deterministic and no duplicate service, IPC, timer,
or notification owner is created.

Dependencies: T06.

### T08. Implement active replacement-bar parity

Status: `[x]` complete — active replacement-bar task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/PluginHost.qml`, the
  active Aurelia bar boundary files, and `shell.qml` only where the active-bar
  seam requires it.
- Allowed test files: `aurelia-shell/tests/`, including isolated
  replacement-bar fixtures, and this tracker.
- Compatibility boundary: built-in Aurelia bar selection, layout order, logo,
  widgets, popup ownership, theme behavior, and existing IPC identities must
  remain unchanged.
- Runtime behavior impact: active-bar selection/fallback only; no persisted
  state, installer, package, systemd, or live-session mutation.
- Persisted user state impact: none.
- Rollback: revert only T08 active-bar/test/tracker changes if a mandatory
  gate fails; preserve completed T00–T07 history and user-owned changes.

CP3 post-change evidence:

- Focused active-bar gate: test_active_bar.sh — 3 assertions passed, 0 failed.
- Runtime coverage: built-in selection, healthy replacement activation,
  broken replacement failure fallback, disabled replacement fallback,
  successful rescan, host ping continuity, and exactly one active full-bar
  instance all passed in a disposable offscreen QuickShell process.
- Ownership coverage: full-bar selection remains separate from the dedicated
  bar-widget registry and current Aurelia bar layout/design boundaries.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 346 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 210 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Compatibility: the built-in Aurelia bar remains the fallback and no default
  layout, theme, popup, widget, or IPC identity was changed.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.
- [x] Add a canonical active bar selector equivalent to Omarchy's `bar.id`.
- [x] Keep exactly one full bar active at a time.
- [x] Preserve the built-in Aurelia bar as the safe fallback.
- [x] Load replacement bars asynchronously and fall back when unavailable or
  when loading fails.
- [x] Keep bar-widget registration and lifecycle independent from the active
  full-bar implementation.
- [x] Preserve current Aurelia bar layout, logo, widgets, popup ownership, and
  theme behavior when the built-in bar remains selected.
- [x] Add replacement-bar fixtures for success, failure, disable, rescan, and
  fallback paths.
- [x] Do not leave the public `bar` kind half-implemented.

Exit gate: the active bar path matches Omarchy structurally and the default
Aurelia bar is byte/behavior compatible with its preservation fixture.

Dependencies: T06, T07.

### T09. Remove hardcoded host assumptions from generic lifecycle routing

Status: `[x]` complete — generic lifecycle-routing task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/PluginHost.qml`,
  `aurelia-shell/shell.qml`, and narrow registry/compatibility adapter
  files required to centralize active-bar ownership.
- Allowed test files: `aurelia-shell/tests/`, including generic
  routing fixtures and this tracker.
- Compatibility boundary: existing compatibility IPC targets, feature-owned
  backend commands, plugin IDs, and active-bar fallback behavior must remain
  unchanged.
- Runtime behavior impact: generic routing/refactoring only; no persisted
  state, installer, package, systemd, or live-session mutation.
- Persisted user state impact: none.
- Rollback: revert only T09 routing/test/tracker changes if a mandatory gate
  fails; preserve completed T00–T08 history and user-owned changes.

CP3 post-change evidence:

- Focused generic-routing gate: test_generic_routing.sh — 3 assertions
  passed, 0 failed.
- Generic routing now resolves the default bar through one host seam, uses
  active-bar resolution for status, and derives resident reload behavior from
  keepLoaded semantics rather than naming the notification service.
- Compatibility IPC aliases remain explicit forwarding adapters; feature-owned
  backend commands and plugin IDs were not changed.
- Existing generic lifecycle fixture covers new panel/service/menu/widget kinds
  without adding an ID-specific host branch.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 349 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 211 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.
- [x] Replace generic routing that is hardcoded to `aurelia.bar` with registry
  ownership and active-bar resolution.
- [x] Keep compatibility IPC targets as thin forwarding aliases.
- [x] Move plugin-specific auxiliary relationships into manifest metadata or
  explicit, narrow compatibility adapters.
- [x] Ensure adding a new panel, service, menu, overlay, bar-widget, or bar
  option does not require editing unrelated host branches.
- [x] Preserve Aurelia's feature-specific backend ownership and existing IPC
  IDs.

Exit gate: a new fixture plugin can exercise its kind without adding a new
`if pluginId == ...` branch to the generic host.

Dependencies: T06, T07, T08.

---

## Phase 3 — Bring configuration and bar customization to parity

### T10. Introduce canonical unified shell state with migration

Status: `[-]` in progress — unified shell-state migration task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/ShellConfig.qml`,
  the shell state IPC seam, and narrowly scoped state-migration helpers.
- Allowed test files: `aurelia-shell/tests/`, including isolated
  temporary-home/state fixtures, and this tracker.
- Compatibility boundary: current version-1 Aurelia `plugins[]`,
  `disabledPlugins[]`, string bar entries, nested settings, default layout,
  notification/theme/keybinding state ownership, and atomic writes must remain
  readable and behavior-compatible.
- Runtime behavior impact: normalize/migrate only in test-owned state paths;
  no live user-state write or installer execution.
- Persisted user state impact: isolated fixtures only; migration writes must
  be explicit, recoverable, idempotent, and preserve unknown fields.
- Rollback: revert only T10 state/test/tracker changes if a mandatory gate
  fails; preserve completed T00–T09 history and user-owned changes.

- [ ] Define the canonical Aurelia state shape equivalent to Omarchy's unified
  `shell.json`: version, idle/runtime state where applicable, active bar, bar
  layout, plugin instances, and disabled-plugin deviations.
- [ ] Represent plugin instances as objects when settings or multiple instances
  are required; retain read support for current string IDs.
- [ ] Preserve unknown user-owned state unless the contract explicitly owns it.
- [ ] Normalize malformed state into safe defaults without deleting the source
  file.
- [ ] Write state atomically with secure permissions and safe interruption.
- [ ] Make repeated normalization byte-stable where possible.
- [ ] Provide an explicit, idempotent migration from current Aurelia
  `plugins[]`, `disabledPlugins[]`, and bar entries.
- [ ] Create a recoverable backup before the first migration write, without
  creating repeated backup pollution on future runs.
- [ ] Keep theme, notification, keybinding, and other feature-owned state in
  their existing ownership domains unless the reference contract explicitly
  requires migration.

Exit gate: an existing Aurelia state file can be read, migrated, re-read, and
reconciled without losing user settings or changing the default visual result.

Dependencies: T01, T02, T06, T08.

### T11. Make bar-widget metadata operational

- [ ] Consume `displayName`, `description`, `category`, `defaultSection`,
  `allowMultiple`, `defaults`, `settingsForm`, and `schema` through the bar
  registry.
- [ ] Build the catalog from manifest metadata rather than hardcoded widget
  lists.
- [ ] Apply manifest defaults only when an instance has no user value.
- [ ] Preserve explicit user values and unknown user-owned settings.
- [ ] Enforce `allowMultiple` at the configuration boundary.
- [ ] Define duplicate-instance addressing so IPC never selects an arbitrary
  instance.
- [ ] Keep Aurelia's existing widget geometry and visual design unchanged.

Exit gate: all current Aurelia bar widgets continue to render identically, and
a new manifest-backed widget can describe itself without host source changes.

Dependencies: T05, T06, T10.

### T12. Add bar placement and settings operations

- [ ] Add equivalent operations for enable-and-place, put, move, and set.
- [ ] Support section, index, before, and after placement.
- [ ] Use `defaultSection` when no explicit placement is supplied.
- [ ] Make placement idempotent.
- [ ] Preserve a widget's existing position and settings when re-enabled.
- [ ] Keep disabling distinct from removing and removing distinct from purging.
- [ ] Provide deterministic errors for missing targets, invalid indices, and
  ambiguous duplicate instances.
- [ ] Add CLI and runtime tests for all placement forms.

Exit gate: a third-party bar-widget can be installed, enabled, placed, moved,
configured, disabled, and re-enabled without manual JSON editing.

Dependencies: T10, T11.

### T13. Add generic plugin instance settings APIs

- [ ] Add a host-owned settings update path equivalent to `updateEntryInline`.
- [ ] Support settings for panels, overlays, menus, services, and bar widgets
  where the manifest permits them.
- [ ] Keep settings JSON-only, bounded, normalized, and free of executable
  content.
- [ ] Separate plugin configuration from runtime state, caches, secrets, logs,
  and personal documents.
- [ ] Provide safe reset-to-default behavior per plugin instance.
- [ ] Make settings changes trigger only the necessary reload/update boundary.
- [ ] Preserve existing Aurelia plugin-owned state files and APIs.

Exit gate: no plugin needs to parse or mutate shared `shell.json` directly.

Dependencies: T10, T11, T12.

---

## Phase 4 — Enforce the third-party API boundary

### T14. Create scoped plugin facades

- [ ] Add a self-scoped registry facade equivalent to Omarchy's
  `PluginRegistryApi`.
- [ ] Add a self-scoped lifecycle/settings facade equivalent to
  `PluginShellApi`.
- [ ] Add a bar facade equivalent to `PluginBarApi` with scalar state and
  owner-checked popup/click-target operations.
- [ ] Add a read-only application-library facade where required.
- [ ] Add a detached bar-widget registry snapshot for replacement bars.
- [ ] Keep first-party plugins on trusted objects only where required by their
  existing implementation.
- [ ] Give user plugins facades rather than raw `PluginRegistry`, `ShellConfig`,
  `Bar`, or unrestricted shell IPC objects.
- [ ] Strip source paths, first-party markers, host capability stamps, and other
  host-internal fields from third-party manifests.
- [ ] Add facade revocation when a plugin is disabled, removed, rescanned, or
  loses a capability.
- [ ] Ensure facade callbacks enforce owner identity rather than trusting IDs
  supplied by plugin code.

Exit gate: a third-party fixture cannot use the public API to control an
unrelated plugin or mutate unrelated host state through the supported facade.

Dependencies: T06, T09, T13.

### T15. Add sensitive-service isolation

- [ ] Identify any Aurelia service that owns authentication, credentials,
  secrets, session-lock, polkit, or equivalent sensitive state.
- [ ] Keep sensitive service objects outside the public service map and ordinary
  visual QML object graph where required.
- [ ] Stamp sensitive capabilities only from trusted first-party metadata.
- [ ] Do not allow a user manifest to self-declare trusted authentication
  capability.
- [ ] Add runtime tests for service lookup, object ownership, manifest mutation,
  disable, and reload.
- [ ] Document clearly that visual QML remains unsandboxed.

Exit gate: sensitive state is not exposed by ordinary third-party facade paths,
and the limitation is covered by runtime evidence rather than comments only.

Dependencies: T14, T02.

### T16. Preserve Aurelia's command and privilege boundaries

- [ ] Keep system actions in approved Aurelia backends and structured argv.
- [ ] Ensure plugin facades cannot bypass existing authorization or privilege
  boundaries.
- [ ] Keep plugin installation user-level and hook-free.
- [ ] Keep network operations bounded.
- [ ] Add tests proving plugin discovery, validation, and enablement do not run
  plugin install code or sudo.
- [ ] Preserve current notification, DNS, Bluetooth, screenshot, display,
  package, and keybinding privilege ownership.

Exit gate: parity work introduces no new privileged plugin execution path.

Dependencies: T14, T15.

---

## Phase 5 — Complete plugin customization and lifecycle tooling

### T17. Implement safe built-in plugin cloning

- [ ] Add `aurelia-plugin clone <id>` for first-party plugins.
- [ ] Generate a collision-safe user-owned ID.
- [ ] Copy the complete plugin directory and every declared local dependency.
- [ ] Add explicit safe clone dependency metadata equivalent to Omarchy's
  `clonePaths` where a complete directory copy is insufficient.
- [ ] Rewrite only identity-sensitive metadata and preserve stable source IPC
  IDs where required.
- [ ] Record clone origin and source restoration intent.
- [ ] Preserve bar position, instance settings, active-bar selection, and
  compatibility aliases when switching to a clone.
- [ ] Restore the original implementation when an active clone is removed.
- [ ] Never edit or overwrite the first-party source tree.
- [ ] Add failure cleanup tests for partial clone, invalid source, collision,
  missing dependency, and discovery failure.

Exit gate: a user can safely customize any eligible first-party plugin without
editing packaged Aurelia source.

Dependencies: T03, T04, T10, T12, T14.

### T18. Complete add/update/remove lifecycle

- [ ] Keep add disabled-by-default unless explicitly enabled.
- [ ] Add preflight duplicate-ID detection against the canonical catalog before
  moving staged code into the user plugin tree.
- [ ] Keep staged clone/update validation before activation.
- [ ] Keep HTTPS and bounded Git operations, disable interactive Git prompts,
  and reject unsafe transport-helper inputs.
- [ ] Add interactive review paths for human use and explicit `--yes` paths for
  automation.
- [ ] Add update-one and update-all behavior.
- [ ] Show a reviewable diff before an interactive update.
- [ ] Refuse updates over local modifications.
- [ ] Validate updated manifests before activation and roll back on validation
  or rescan failure.
- [ ] Record remote URL, selected ref/commit, version, and validation result for
  provenance and diagnostics.
- [ ] Make manual/non-Git plugin removal recoverable; never purge user data.
- [ ] Ensure `remove` disables the plugin before removing its source.
- [ ] Add local Git repository fixtures so lifecycle tests never require network.

Exit gate: add, update, remove, clone, interruption, validation failure, and
rollback paths are deterministic and recoverable.

Dependencies: T05, T10, T17.

### T19. Add plugin management and discoverability parity

- [ ] Add a human-readable and JSON plugin list with source, kind, enabled,
  active, loaded, visible, in-bar, can-disable, clone origin, and error state.
- [ ] Add plugin enable/disable/clone/remove/update actions to an Aurelia-owned
  management surface.
- [ ] Keep management UI separate from plugin mutation internals.
- [ ] Make management UI consume the canonical catalog and lifecycle APIs.
- [ ] Preserve Command Center's existing modules and design language.
- [ ] Add a plugin author preview/validation action without loading plugin code.

Exit gate: a user can discover and manage plugins without knowing private file
paths or editing JSON manually.

Dependencies: T05, T12, T17, T18.

### T20. Match development reload behavior safely

- [ ] Define the production/development watcher policy explicitly against the
  Omarchy reference.
- [ ] Watch only first-party and user plugin trees; never enable broad
  Quickshell core file watching as a replacement.
- [ ] Debounce atomic saves.
- [ ] Support targeted plugin reload and explicit full rescan.
- [ ] Keep stateful and sensitive services alive across unrelated reloads.
- [ ] Revoke and recreate facades when plugin capability profiles change.
- [ ] Preserve the current Aurelia restart boundary for `shell.qml`, shared
  services, theme core, and Hyprland Lua.
- [ ] Add tests for changed QML, JS, JSON, Lua/config files, deletion, rename,
  invalid intermediate writes, and watcher failure.

Exit gate: plugin source changes behave like the reference without duplicate
hosts, duplicate services, broken lock/notification owners, or broad reloads.

Dependencies: T07, T14, T15.

---

## Phase 6 — Remove static feature assumptions while preserving Aurelia behavior

### T21. Convert the Command Center provider catalog to the parity model

- [ ] Keep the Command Center as an Aurelia feature with its current name,
  layout, keyboard behavior, and design language.
- [ ] Separate generic module metadata from provider implementation.
- [ ] Make the module registry consume declarative metadata and user overrides.
- [ ] Ensure existing modules remain available with identical behavior.
- [ ] Add an Aurelia-owned manifest-backed menu surface equivalent to Omarchy's
  menu plugin, including shipped menu data and user extension data, while
  preserving the existing Command Center as an Aurelia-specific feature.
- [ ] Define safe menu visibility, checked-state, and action-provider contracts;
  use structured argv or explicitly approved Aurelia actions instead of copying
  arbitrary shell-string evaluation.
- [ ] Define a safe provider extension point for future modules without allowing
  arbitrary shell command injection.
- [ ] Keep unimplemented modules inert and fail-closed.
- [ ] Add module catalog, enablement, invalid metadata, and provider failure
  tests.

Exit gate: adding a supported Command Center provider does not require editing
the host's generic navigation code.

Dependencies: T03, T13, T14.

### T22. Migrate all existing Aurelia plugins to the canonical contract

For each plugin below:

- [ ] migrate its manifest without changing its user-visible behavior;
- [ ] make its entry points load through the generic registry;
- [ ] make its settings use the canonical state/API boundary;
- [ ] preserve its current backend ownership and failure classification;
- [ ] add or update focused tests and runtime fixtures;
- [ ] add a design-language review against Aurelia tokens and primitives.

Feature preservation list:

- [ ] `aurelia.bar`: resident bar, exact center anchor, layout, logo, widget
  ownership, single-popout behavior, themes, and fallback.
- [ ] `aurelia.background`: per-screen background service, image/video support,
  safe fallback, and state reload.
- [ ] `aurelia.image-picker`: image carousel/selector behavior and theme use.
- [ ] `aurelia.bluetooth`: BlueZ model, discovery ownership, power state,
  paired/discovered actions, and popup behavior.
- [ ] `aurelia.calendar`: clock-owned calendar surface and geometry.
- [ ] `aurelia.clock`: formatting, center placement, and calendar routing.
- [ ] `aurelia.keybindings`: keyboard capture, provider integration, settings,
  compatibility targets, and structured backend execution.
- [ ] `aurelia.launcher`: Command Center navigation, application search,
  calculator, file search, updates, About, and package workflows.
- [ ] `aurelia.monitor`: brightness, display scale/resolution, text size, and
  multi-monitor behavior.
- [ ] `aurelia.network`: NetworkManager state, DNS authorization, QR handoff,
  speed-test handoff, and credential boundaries.
- [ ] `aurelia.notifications`: notification server ownership, bounded history,
  DND, popups, screenshot previews, and cross-workspace routing.
- [ ] `aurelia.power`: power actions and confirmation behavior.
- [ ] `aurelia.screenshot`: bar-owned capture, region selection, delay/pointer
  settings, clipboard, and notification integration.
- [ ] `aurelia.speedtest`: bounded cancellable speed-test panel.
- [ ] `aurelia.tasklist`: tasklist layout and window context menu.
- [ ] `aurelia.theme`: data-only theme selection and background handoff.
- [ ] `aurelia.tray`: system tray ownership and menu behavior.
- [ ] `aurelia.weather`: automatic/pinned location, units, refresh, and popup.
- [ ] `aurelia.wifiqr`: QR generation, cancellation, and network handoff.
- [ ] `aurelia.workspace-switcher`: `SUPER + TAB`, workspace cards, preview
  fallback, and selection behavior.
- [ ] `aurelia.workspaces`: workspace indicators and Hyprland dispatch.

Exit gate: all existing Aurelia features pass their preservation fixtures after
being hosted by the parity architecture.

Dependencies: T06 through T21 as applicable to each plugin.

### T23. Eliminate duplicated defaults and feature-specific host registration

- [ ] Move the default bar layout to one canonical repository-owned data file.
- [ ] Keep an embedded fallback only for safe startup recovery.
- [ ] Remove duplicate default layout definitions from host and bar code.
- [ ] Remove generic host registration lists that must be edited for every new
  plugin.
- [ ] Preserve current defaults byte-for-byte in the preservation fixture.
- [ ] Keep feature-specific registration only where the feature owns a real
  external capability or compatibility alias.

Exit gate: a new manifest-backed plugin can be discovered and managed without
editing unrelated Aurelia default lists or host registration branches.

Dependencies: T05, T10, T21, T22.

---

## Phase 7 — Complete verification, documentation, and cutover

### T24. Complete the generic plugin test matrix

- [ ] Add manifest enumeration tests for every Aurelia first-party manifest.
- [ ] Add entry-point existence and safe-path tests for every declared kind.
- [ ] Add runtime fixture loading for every supported entry-point kind.
- [ ] Add broken-plugin survivability fixtures proving that syntax/import,
  initialization, service, widget, callback, and reload failures do not crash
  the host or prevent healthy plugins from loading.
- [ ] Assert host `ping`, `listPlugins`, built-in bar fallback, and at least one
  healthy plugin after every contained failure.
- [ ] Add first-party and third-party registry tests.
- [ ] Add duplicate-ID, namespace, symlink, malformed JSON, and unsafe-path
  tests.
- [ ] Add bar-widget catalog, placement, settings, multiple-instance, and
  popup-routing tests.
- [ ] Add replacement-bar fallback and lifecycle tests.
- [ ] Add scoped-facade and capability-revocation tests.
- [ ] Add service isolation tests for every sensitive service.
- [ ] Add add/update/remove/clone/rollback CLI tests using local Git fixtures.
- [ ] Add development reload tests.
- [ ] Add cross-plugin compatibility tests for every retained Aurelia feature.
- [ ] Keep tests deterministic and isolated from the live workstation.

Exit gate: the generic plugin contract is tested independently of any one
feature plugin, and all feature-specific suites remain green.

Dependencies: T02 through T23.

### T25. Add visual and interaction parity acceptance checks

- [ ] Verify bar placement, orientation, center anchoring, and popup ownership.
- [ ] Verify plugin enable/disable/clone/remove flows visually and through IPC.
- [ ] Verify Command Center/plugin-management navigation using Aurelia's design
  language.
- [ ] Verify loading and reload do not create duplicate windows, timers, IPC
  handlers, service owners, or notification registrations.
- [ ] Verify all custom Aurelia features retain their current appearance and
  interaction behavior.
- [ ] Use live QML/Wayland tests only as a separately authorized validation
  phase; do not enable them during ordinary repository-only changes.

Exit gate: static and isolated tests agree with runtime/visual evidence, and
any unavailable live evidence is explicitly recorded rather than claimed.

Dependencies: T22, T24.

### T26. Publish plugin authoring and maintenance documentation

- [ ] Document the canonical manifest schema and kind-to-entry-point mapping.
- [ ] Document the directory layout and source roots.
- [ ] Document lifecycle, `keepLoaded`, multi-kind, bar, settings, and reload
  behavior.
- [ ] Document the third-party facade API and scope rules.
- [ ] Document no-sandbox behavior, trust requirements, no-hook policy, and
  bounded Git operations.
- [ ] Add a minimal example plugin and validation instructions.
- [ ] Add clone, update, remove, migration, and rollback instructions.
- [ ] Document which behavior is Omarchy parity and which behavior is an
  intentionally preserved Aurelia feature.
- [ ] Keep README, runtime comments, tests, and implementation synchronized.

Exit gate: a new plugin author can build, validate, install, enable, configure,
reload, test, update, clone, and remove a plugin without reading host internals.

Dependencies: T03, T05, T14, T17, T18, T24.

### T27. Perform the compatibility cutover

- [ ] Keep old Aurelia manifest/state reads enabled until all migration tests
  pass.
- [ ] Enable canonical parity writes only after T24 and T25 pass.
- [ ] Run the migration against isolated copies of representative old states.
- [ ] Verify a second run produces no additional changes or backups.
- [ ] Verify a failed migration leaves the original state usable.
- [ ] Verify all first-party plugins start through the canonical path.
- [ ] Verify third-party plugins remain disabled until explicit enablement.
- [ ] Verify the built-in bar remains the safe default.
- [ ] Remove compatibility code only in a separately reviewed cleanup task after
  the migration window is complete.

Exit gate: canonical parity is active, old valid state remains readable, and
the default Aurelia session is behaviorally unchanged.

Dependencies: T24, T25, T26.

### T28. Final 1:1 parity audit and release gate

- [ ] Re-run the complete manifest and structure comparison against the pinned
  Omarchy reference.
- [ ] Verify every Omarchy plugin-platform capability has an Aurelia owner or
  an explicitly documented, approved difference.
- [ ] Verify every identified audit gap in the gap matrix below is closed.
- [ ] Run `./tests/run.sh`.
- [ ] Run `./aurelia-shell/tests/run.sh`.
- [ ] Run syntax validation across every shell script in the repository,
  including the Aurelia tree.
- [ ] Run ShellCheck when already installed; do not install it only for this
  gate.
- [ ] Run authorized QML/runtime/visual acceptance tests separately from unit
  tests and report skipped evidence honestly.
- [ ] Confirm no installer execution, package mutation, live configuration
  mutation, greetd/systemd mutation, or reboot occurred during implementation.
- [ ] Record starting branch/SHA, final branch/SHA, files changed, tests,
  commits, remaining risks, and unverified integration scenarios.

Exit gate: Aurelia reaches the agreed Omarchy plugin parity target without
regressing any preserved Aurelia feature or safety invariant.

Dependencies: T27 and every previous task.

---

## Gap-to-task closure matrix

| Audit gap | Closing task(s) |
|---|---|
| `barWidget` metadata accepted but not operational | T03, T05, T11, T24 |
| Enabling a bar widget does not place it in the bar | T10, T12, T24 |
| No dedicated Aurelia bar-widget registry | T06, T11 |
| Declared `bar` kind lacks active replacement-bar semantics | T08, T24, T25 |
| `plugins[]` stores IDs rather than plugin instances/settings | T10, T13, T27 |
| No generic multiple-instance enforcement | T11, T12, T24 |
| Raw third-party host objects are injected | T14, T15, T16, T24 |
| No sensitive-service isolation pattern | T15, T24 |
| No built-in clone/customization workflow | T17, T24, T26 |
| Incomplete add/update/remove CLI lifecycle | T18, T19, T24 |
| No duplicate-ID preflight before plugin installation | T05, T18, T24 |
| Manual plugin removal is not recoverable | T18, T24 |
| No update-all or diff review | T18, T24 |
| No canonical plugin catalog | T05, T19 |
| No plugin-management UI | T19, T21, T25 |
| Limited plugin error/status observability | T05, T06, T19, T24 |
| A faulty plugin can threaten host startup/runtime survivability | T02A, T06, T07, T20, T24, T25 |
| No generic all-manifest contract test | T02, T24 |
| No generic runtime entry-point loading test | T02, T06, T24 |
| No third-party lifecycle fixtures | T02, T18, T24 |
| No facade/isolation runtime tests | T02, T14, T15, T24 |
| Command Center provider catalog remains static | T21, T23, T24 |
| Default bar layout duplicated in multiple files | T10, T23 |
| Aurelia/Omarchy manifest key mismatch | T01, T03, T04, T27 |
| Reference optional manifest metadata is missing or inert | T01, T03, T05, T11, T17 |
| Plugin development reload is less complete | T07, T20, T24 |
| No manifest-backed Omarchy-style menu/data-extension surface | T21, T24, T25 |
| No plugin authoring documentation/template | T26 |

## Final preservation gate

Before declaring parity complete:

- [ ] Existing Aurelia plugin IDs remain valid or have an explicit migration.
- [ ] Existing Aurelia IPC aliases still forward correctly.
- [ ] Existing Aurelia bar defaults, theme tokens, panel geometry, keyboard
  behavior, and popup ownership remain unchanged.
- [ ] Existing notification, screenshot, network, Bluetooth, display, theme,
  image-picker, workspace, launcher, keybinding, tray, tasklist, power,
  calendar, and weather features remain available.
- [ ] A deliberately faulty plugin cannot prevent Aurelia host readiness or
  healthy-plugin availability in isolated runtime tests.
- [ ] Existing backend and privilege ownership remains unchanged.
- [ ] Existing user configuration is preserved and migration is idempotent.
- [ ] Existing login-critical architecture is untouched.
- [ ] No test claims runtime parity without runtime evidence.
- [ ] Any intentional difference from Omarchy is written here, reviewed, and
  approved before release.

## Completion record

```text
Parity status:
Final Aurelia branch/SHA:
Reference Omarchy branch/SHA:
Tasks completed:
Tasks outstanding:
Tests:
Syntax checks:
ShellCheck:
Runtime/visual acceptance:
Files changed:
Commits:
Remaining risks:
./install.sh run: no
Packages modified: no
Live user configuration modified: no
systemd/greetd state modified: no
VM rebooted: no
```
