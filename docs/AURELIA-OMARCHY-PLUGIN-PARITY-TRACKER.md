# Aurelia–Omarchy Plugin Parity Tracker

Status: active execution — T00 through T17 complete; T18 onward remain.

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

Status: `[x]` complete — unified shell-state migration task.

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

CP3 post-change evidence:

- Focused state gate: test_shell_state_migration.sh — 4 assertions passed, 0
  failed.
- State coverage: version-1 legacy plugin strings and nested settings normalize
  to inline objects; idle, active bar/layout, disabled deviations, unknown
  fields, and explicit null values are preserved.
- Migration coverage: explicit migration creates one adjacent recoverable
  pre-migration backup, writes mode-600 canonical state atomically, and leaves
  a second run byte-stable without backup pollution.
- Failure coverage: malformed source state falls back to safe in-memory
  defaults without rewriting or deleting the source file.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 353 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 212 shell scripts passed.
- Diff validation: git diff --check passed.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.

- [x] Define the canonical Aurelia state shape equivalent to Omarchy's unified
  `shell.json`: version, idle/runtime state where applicable, active bar, bar
  layout, plugin instances, and disabled-plugin deviations.
- [x] Represent plugin instances as objects when settings or multiple instances
  are required; retain read support for current string IDs.
- [x] Preserve unknown user-owned state unless the contract explicitly owns it.
- [x] Normalize malformed state into safe defaults without deleting the source
  file.
- [x] Write state atomically with secure permissions and safe interruption.
- [x] Make repeated normalization byte-stable where possible.
- [x] Provide an explicit, idempotent migration from current Aurelia
  `plugins[]`, `disabledPlugins[]`, and bar entries.
- [x] Create a recoverable backup before the first migration write, without
  creating repeated backup pollution on future runs.
- [x] Keep theme, notification, keybinding, and other feature-owned state in
  their existing ownership domains unless the reference contract explicitly
  requires migration.

Exit gate: an existing Aurelia state file can be read, migrated, re-read, and
reconciled without losing user settings or changing the default visual result.

Dependencies: T01, T02, T06, T08.

### T11. Make bar-widget metadata operational

Status: `[x]` complete — operational bar-widget metadata task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/BarWidgetRegistry.qml`,
  `ShellConfig.qml`, the Aurelia bar row/center/slot boundaries,
  `shell.qml` injection wiring, and narrow host helpers needed for
  duplicate-instance addressing.
- Allowed test files: `aurelia-shell/tests/`, including isolated
  metadata/defaults/duplicate-instance fixtures, and this tracker.
- Compatibility boundary: current layout order, explicit widget settings,
  geometry, visual design, plugin IDs, and single-instance current widgets
  must remain unchanged.
- Runtime behavior impact: metadata projection and bar-entry resolution only;
  no live bar restart, persisted state migration, or installer mutation.
- Persisted user state impact: duplicate filtering must be deterministic and
  preserve explicit values; no user data may be removed outside the managed
  duplicate-instance rule.
- Rollback: revert only T11 metadata/bar/test/tracker changes if a mandatory
  gate fails; preserve completed T00–T10 history and user-owned changes.

CP3 post-change evidence:

- Focused metadata gate: test_bar_widget_metadata.sh — 3 assertions passed, 0
  failed.
- Metadata coverage: `BarWidgetRegistry` projects display name, description,
  category, default section, multiplicity, defaults, settings-form identity,
  schema, and entry-point metadata from validated manifests.
- Configuration coverage: manifest defaults are applied only through the
  registry when an entry has no explicit value; inline and legacy nested
  settings remain compatible, including unknown user-owned values.
- Duplicate coverage: `allowMultiple` is enforced while normalizing bar
  entries; explicit instance IDs are preserved and widget routing returns a
  deterministic ambiguity result instead of selecting an arbitrary duplicate.
- Visual compatibility: existing bar geometry, layout structure, widget
  loading, popup ownership, and design boundaries were not changed.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 356 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 213 shell scripts passed.
- Diff validation: git diff --check passed for the reviewed change.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.

- [x] Consume `displayName`, `description`, `category`, `defaultSection`,
  `allowMultiple`, `defaults`, `settingsForm`, and `schema` through the bar
  registry.
- [x] Build the catalog from manifest metadata rather than hardcoded widget
  lists.
- [x] Apply manifest defaults only when an instance has no user value.
- [x] Preserve explicit user values and unknown user-owned settings.
- [x] Enforce `allowMultiple` at the configuration boundary.
- [x] Define duplicate-instance addressing so IPC never selects an arbitrary
  instance.
- [x] Keep Aurelia's existing widget geometry and visual design unchanged.

Exit gate: all current Aurelia bar widgets continue to render identically, and
a new manifest-backed widget can describe itself without host source changes.

Dependencies: T05, T06, T10.

### T12. Add bar placement and settings operations

Status: `[x]` complete — bar placement and settings operations task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/ShellConfig.qml`, the
  existing shell IPC boundary in `shell.qml`, the Aurelia plugin CLI command
  boundary, and narrow bar/registry helpers required to resolve widget
  placement and instance IDs.
- Allowed test files: `aurelia-shell/tests/`, including isolated temporary
  state/CLI/QuickShell fixtures for placement, movement, settings, disable,
  and re-enable, and this tracker.
- Compatibility boundary: existing shell IPC names, current default bar
  layout/order, current widget settings, plugin IDs, visual geometry, and
  feature-owned state must remain unchanged. Existing enable/disable behavior
  must continue to work through the same canonical owner.
- Runtime behavior impact: explicit user-state operations only through the
  existing host/reconciler boundary; no automatic layout rewrite, live bar
  restart, installer mutation, or live-session change.
- Persisted user state impact: isolated fixtures only. Operations must preserve
  unknown fields/settings, use the existing atomic mode-600 state writer, and
  never interpret disable as remove or remove as purge.
- Rollback: revert only T12 placement/CLI/test/tracker changes if a mandatory
  gate fails; preserve completed T00–T11 history and user-owned changes.

- CP3 post-change evidence:

- Focused bar-operations gate: test_bar_operations.sh — 6 assertions passed, 0
  failed.
- Operation coverage: `enablePlugin`, `putBarWidget`, `moveBarWidget`, and
  `setBarWidget` are host-owned operations with one atomic state transition;
  CLI placement parsing emits the same section/index/before/after vocabulary as
  Omarchy.
- Placement coverage: manifest-provided `defaultSection`, explicit index,
  before/after targets, source section/index selectors, missing-target fallback
  for `put`, and deterministic invalid-section/index errors passed in isolated
  QuickShell and CLI fixtures.
- State safety: repeated enable/put leaves an existing position alone, move and
  set preserve unknown entry fields/settings, duplicate instances require an
  explicit address, and disable/re-enable preserves the widget's position and
  user setting without purge or source removal.
- Shell survivability: the catalog/config feedback fixture converges without a
  recursive signal loop; an isolated offscreen `shell.qml` startup reached
  configuration load without the observed stack overflow. The offscreen run
  cannot prove visual bar rendering because its `PanelWindow` backend is absent.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 362 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 216 shell scripts passed.
- Diff validation: git diff --check passed for the reviewed change.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes, CLI mocks,
  and temporary XDG/runtime directories were used. ./install.sh was not run;
  no packages, repositories, systemd/greetd state, live user configuration, or
  the VM were modified, and no reboot occurred.

- [x] Add equivalent operations for enable-and-place, put, move, and set.
- [x] Support section, index, before, and after placement.
- [x] Use `defaultSection` when no explicit placement is supplied.
- [x] Make placement idempotent.
- [x] Preserve a widget's existing position and settings when re-enabled.
- [x] Keep disabling distinct from removing and removing distinct from purging.
- [x] Provide deterministic errors for missing targets, invalid indices, and
  ambiguous duplicate instances.
- [x] Add CLI and runtime tests for all placement forms.

Exit gate: a third-party bar-widget can be installed, enabled, placed, moved,
configured, disabled, and re-enabled without manual JSON editing.

Dependencies: T10, T11.

### T13. Add generic plugin instance settings APIs

Status: `[x]` complete — generic plugin instance settings API task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/ShellConfig.qml`,
  `PluginRegistry.qml`, the existing `PluginHost.qml` injection/lifecycle
  seam, `shell.qml` IPC, and the narrow plugin CLI/settings helpers required
  to route instance updates through the host owner.
- Allowed test files: `aurelia-shell/tests/`, including isolated JSON/state
  fixtures for every plugin kind, bounded-value/rejection cases, reset, reload
  scope, and this tracker.
- Compatibility boundary: current plugin-owned state files, IPC identities,
  bar layout/settings, notification/theme/keybinding state, plugin loading
  behavior, and user-owned unknown fields must remain unchanged unless an
  explicit settings operation targets that instance.
- Runtime behavior impact: settings updates and reset only; no automatic
  migration, installer mutation, package/repository change, live systemd or
  greetd change, or live-session restart.
- Persisted user state impact: isolated temporary state only. Shared shell
  state writes must be atomic, mode-600, JSON-only, bounded, fail closed on
  executable/content injection, and must preserve unrelated state.
- Rollback: revert only T13 settings/API/test/tracker changes if a mandatory
  gate fails; preserve completed T00–T12 history and user-owned changes.

CP3 post-change evidence:

- Focused settings gate: test_plugin_settings.sh — 4 assertions passed, 0
  failed.
- API coverage: `ShellConfig` owns generic inline settings reads, updates, and
  reset; `PluginRegistry` and the `shell` IPC target expose the one canonical
  forwarding boundary for bar and top-level plugin entries.
- Kind coverage: configured bar-widget and panel entries are covered by
  isolated runtime fixtures; the same JSON entry path is available to
  overlay, menu, and service entries without touching their plugin-owned state
  files.
- Safety coverage: settings are bounded JSON with safe keys, finite values,
  bounded depth/nodes/arrays/strings/serialized size, and no functions or
  executable QML content; malformed selectors, ambiguous instances, and
  unchanged writes fail or converge deterministically.
- Reset coverage: reset removes only inline settings for the selected instance,
  preserves its position and explicit instance ID, is idempotent, and leaves a
  separate plugin-owned state file byte-stable.
- Live update coverage: resident plugin objects receive refreshed settings and
  an optional `aureliaSettingsChanged` hook in place; bar loaders retain all
  existing safe-configure branches and exactly one settings-change handler.
- Shell safety: the catalog/config signal-cycle regression and the duplicate
  `onSettingsChanged` regression both pass; disposable actual-shell startup
  reaches configuration load without either observed fatal signature. The
  offscreen environment cannot prove visual bar rendering because its
  `PanelWindow` backend is absent.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 366 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 217 shell scripts passed.
- Diff validation: git diff --check passed for the reviewed change.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.

- [x] Add a host-owned settings update path equivalent to `updateEntryInline`.
- [x] Support settings for panels, overlays, menus, services, and bar widgets
  where the manifest permits them.
- [x] Keep settings JSON-only, bounded, normalized, and free of executable
  content.
- [x] Separate plugin configuration from runtime state, caches, secrets, logs,
  and personal documents.
- [x] Provide safe reset-to-default behavior per plugin instance.
- [x] Make settings changes trigger only the necessary reload/update boundary.
- [x] Preserve existing Aurelia plugin-owned state files and APIs.

Exit gate: no plugin needs to parse or mutate shared `shell.json` directly.

Dependencies: T10, T11, T12.

---

## Phase 4 — Enforce the third-party API boundary

### T14. Create scoped plugin facades

Status: `[x]` complete — scoped plugin-facade boundary task.

CP2 pre-change boundary:

- Allowed production files: new facade QML types under
  `aurelia-shell/services/`, `PluginHost.qml`, `PluginRegistry.qml`,
  `BarWidgetRegistry.qml`, `shell.qml`, and narrow existing plugin injection
  adapters required to give third-party entries detached, owner-checked API
  views.
- Allowed test files: `aurelia-shell/tests/`, including isolated third-party
  facade fixtures for self/foreign lookups, lifecycle/settings ownership, bar
  state, application catalog reads, revocation, and this tracker.
- Compatibility boundary: first-party plugin behavior, current plugin IDs,
  feature-owned services, bar geometry/design, existing compatibility IPC
  aliases, and trusted built-in injection must remain unchanged. Third-party
  plugins must not receive raw host objects through newly created paths.
- Runtime behavior impact: facade construction, detached snapshots, ownership
  checks, and revocation only; no plugin source installation, automatic state
  migration, live bar restart, installer mutation, or live system changes.
- Persisted user state impact: none except isolated settings calls in fixtures;
  facade reads must not mutate shared config, and facade writes must continue
  through T13's host-owned settings boundary.
- Security boundary: facades reduce authority and enforce supported API
  ownership, but same-process QML remains unsandboxed; sensitive services must
  stay outside the third-party object graph.
- Rollback: revert only T14 facade/injection/test/tracker changes if a
  mandatory gate fails; preserve completed T00–T13 history and user-owned
  changes.

CP3 post-change evidence:

- Focused facade gate: test_plugin_facades.sh — 4 assertions passed, 0
  failed.
- Facade coverage: third-party plugins receive self-scoped registry and
  lifecycle/settings APIs, a scalar/owner-checked bar facade, a detached
  bar-widget catalog snapshot, and a read-only detached application catalog.
- Injection coverage: the real `PluginHost` and `BarWidgetSlot` fixture loads a
  third-party bar widget only after the facade host is wired; it receives no
  raw `PluginRegistry`, `ShellConfig`, `Bar`, or unrestricted shell IPC object.
- Ownership coverage: self lifecycle/settings/entry-point requests succeed;
  foreign IDs and foreign popup ownership fail deterministically. Detached
  manifest, bar-config, app-row, and widget-metadata mutations do not affect
  host-side objects.
- Revocation coverage: disable and capability-profile changes destroy cached
  registry, shell, bar, widget-catalog, and app-library facades.
- Compatibility coverage: manifests without a production trust stamp remain
  compatible with existing first-party test fixtures; production discovery
  continues to use the explicit `__isFirstParty` stamp. First-party injection
  remains on the prior trusted-object path.
- Shell safety: disposable actual-shell startup reaches configuration load
  without `Maximum call stack size exceeded`, duplicate-property assignment,
  unresolved facade-type, or configuration-load-failure signatures. The
  offscreen environment cannot prove visual bar rendering because its
  `PanelWindow` backend is absent.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 370 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 218 shell scripts passed.
- Diff validation: git diff --check passed for the reviewed change.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.

- [x] Add a self-scoped registry facade equivalent to Omarchy's
  `PluginRegistryApi`.
- [x] Add a self-scoped lifecycle/settings facade equivalent to
  `PluginShellApi`.
- [x] Add a bar facade equivalent to `PluginBarApi` with scalar state and
  owner-checked popup/click-target operations.
- [x] Add a read-only application-library facade where required.
- [x] Add a detached bar-widget registry snapshot for replacement bars.
- [x] Keep first-party plugins on trusted objects only where required by their
  existing implementation.
- [x] Give user plugins facades rather than raw `PluginRegistry`, `ShellConfig`,
  `Bar`, or unrestricted shell IPC objects.
- [x] Strip source paths, first-party markers, host capability stamps, and other
  host-internal fields from third-party manifests.
- [x] Add facade revocation when a plugin is disabled, removed, rescanned, or
  loses a capability.
- [x] Ensure facade callbacks enforce owner identity rather than trusting IDs
  supplied by plugin code.

Exit gate: a third-party fixture cannot use the public API to control an
unrelated plugin or mutate unrelated host state through the supported facade.

Dependencies: T06, T09, T13.

### T15. Add sensitive-service isolation

Status: `[x]` complete — sensitive-service isolation task.

CP2 pre-change boundary:

- Allowed production files: `aurelia-shell/services/PluginHost.qml`,
  `PluginRegistry.qml`, the narrow facade/injection files from T14, and only
  the specific sensitive-service ownership seams required to remove accidental
  third-party reachability.
- Allowed test files: `aurelia-shell/tests/`, including isolated fake-service
  fixtures for authentication/credential/secret/lock/polkit lookup,
  capability stamping, disable, rescan, and object-parent reachability, and
  this tracker.
- Compatibility boundary: current first-party notification, keyring/PAM,
  lock, polkit, screenshot, DNS, Bluetooth, and other privileged behavior must
  remain unchanged. First-party owners keep only the trusted access they
  already require.
- Runtime behavior impact: third-party service visibility and capability
  stamping only; no live authentication/PAM/polkit changes, installer or
  package mutation, systemd/greetd change, live-session restart, or secret
  migration.
- Persisted user state impact: none. Tests must use disposable services and
  temporary state; no secret, credential, lock state, notification history, or
  user file may be rewritten.
- Security boundary: same-process visual QML remains unsandboxed and must be
  documented as such; this task narrows supported API reachability and does
  not claim process isolation.
- Rollback: revert only T15 sensitive-service/injection/test/tracker changes if
  a mandatory gate fails; preserve completed T00–T14 history and user-owned
  changes.

CP3 post-change evidence:

- Focused sensitive-service gate: test_sensitive_service_boundary.sh — 4
  assertions passed, 0 failed.
- Inventory: no current resident Aurelia service manifest declares
  authentication, credentials, secrets, session-lock, or polkit ownership.
  Network and Wi-Fi QR credential strings remain transient panel-local state;
  the resident notifications service owns notification state, not
  authentication state, and is not exposed through third-party self-scoped
  lookup.
- Capability coverage: only explicitly trusted first-party manifest metadata
  can be converted into `__hostCapabilities`; user/third-party capability
  declarations are rejected and ordinary third-party manifests receive an
  empty trusted-capability stamp.
- Service boundary coverage: third-party lifecycle facades return only their
  own service object and reject foreign service IDs, while manifest copies and
  capability state remain detached across mutation and reload/disable checks.
- Object-graph limitation: visual QML executes in the same resident process and
  is not a security sandbox, matching Omarchy. The supported facade path does
  not publish sensitive services; true malicious-process isolation is outside
  1:1 in-process parity.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 374 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 219 shell scripts passed.
- Diff validation: git diff --check passed for the reviewed change.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable offscreen QuickShell processes and temporary
  XDG/runtime directories were used. ./install.sh was not run; no packages,
  repositories, systemd/greetd state, live user configuration, or the VM were
  modified, and no reboot occurred.

- [x] Identify any Aurelia service that owns authentication, credentials,
  secrets, session-lock, polkit, or equivalent sensitive state.
- [x] Keep sensitive service objects outside the public service map and ordinary
  visual QML object graph where required.
- [x] Stamp sensitive capabilities only from trusted first-party metadata.
- [x] Do not allow a user manifest to self-declare trusted authentication
  capability.
- [x] Add runtime tests for service lookup, object ownership, manifest mutation,
  disable, and reload.
- [x] Document clearly that visual QML remains unsandboxed.

Exit gate: sensitive state is not exposed by ordinary third-party facade paths,
and the limitation is covered by runtime evidence rather than comments only.

Dependencies: T14, T02.

### T16. Preserve Aurelia's command and privilege boundaries

Status: `[x]` complete — command and privilege boundary task.

CP2 pre-change boundary:

- Allowed production files: the T14 facade/injection files, plugin CLI/common
  helpers, approved Aurelia backend wrappers, and only narrow host/manifest
  validation seams needed to preserve existing ownership and timeout rules.
- Allowed test files: `aurelia-shell/tests/` and repository tests for isolated
  argv/privilege/timeout/hook-free plugin lifecycle fixtures, plus this tracker.
- Compatibility boundary: current Fedora package ownership, DNS/Bluetooth/
  network/password, screenshot, display, notification, keybinding, terminal,
  and rootless Podman actions must remain behaviorally unchanged. Existing
  user features and Aurelia design language are out of scope.
- Runtime behavior impact: validation and bounded command routing only; no
  live sudo/polkit/PAM/systemd/greetd action, package/repository mutation,
  installer run, or live-session restart.
- Persisted user state impact: none except disposable isolated fixtures; no
  credentials, tokens, package manifests, plugin source, or user configuration
  may be changed.
- Security boundary: plugin installation remains user-level and hook-free;
  third-party QML remains unsandboxed but cannot gain new privilege through
  supported facade APIs.
- Rollback: revert only T16 command/privilege/test/tracker changes if a
  mandatory gate fails; preserve completed T00–T15 history and user-owned
  changes.

CP3 post-change evidence:

- Focused command/privilege gate: test_command_privilege_boundary.sh — 3
  assertions passed, 0 failed.
- Installation coverage: a fake bounded Git clone creates a plugin containing
  an executable-looking install hook; add, manifest validation, rescan, and
  enable complete without running that hook or invoking sudo. The resident
  shell is contacted only through the expected structured IPC operations.
- Facade coverage: scoped facade files contain no sudo, pkexec, or systemd
  execution path. Existing authorization remains owned by the approved DNS,
  Bluetooth, network, screenshot, display, package, notification, and
  keybinding backends.
- Execution coverage: plugin custom argv remains validated and bounded;
  network/credential paths retain explicit timeouts and stdin-only secret
  delivery where required. Existing package ownership and privilege tests
  remain green.
- No production implementation change was necessary for T16; the audit
  confirmed T14's facade and T00–T15 command boundaries already satisfy the
  required ownership model.
- Aurelia regression suite: ./aurelia-shell/tests/run.sh — 377 passed, 0
  failed.
- Repository regression suite: ./tests/run.sh — 228 passed, 0 failed.
- Syntax: repository-wide bash -n — 220 shell scripts passed.
- Diff validation: git diff --check passed for the reviewed change.
- Shellcheck: unavailable because it is not installed; no installation was
  attempted.
- Runtime scope: only disposable CLI mocks and temporary plugin trees were
  used. ./install.sh was not run; no packages, repositories, systemd/greetd
  state, live user configuration, or the VM were modified, and no reboot
  occurred.

- [x] Keep system actions in approved Aurelia backends and structured argv.
- [x] Ensure plugin facades cannot bypass existing authorization or privilege
  boundaries.
- [x] Keep plugin installation user-level and hook-free.
- [x] Keep network operations bounded.
- [x] Add tests proving plugin discovery, validation, and enablement do not run
  plugin install code or sudo.
- [x] Preserve current notification, DNS, Bluetooth, screenshot, display,
  package, and keybinding privilege ownership.

Exit gate: parity work introduces no new privileged plugin execution path.

Dependencies: T14, T15.

---

## Phase 5 — Complete plugin customization and lifecycle tooling

### T17. Implement safe built-in plugin cloning

Status: `[x]` complete — CP2 and CP3 passed; safe built-in plugin cloning task.

CP2 pre-change boundary:

- Allowed production files: the Aurelia plugin CLI lifecycle modules,
  `PluginRegistry.qml`, `ShellConfig.qml`, narrow clone/provenance helpers, and
  only the manifest metadata needed to describe safe local clone paths.
- Narrow compatibility amendment recorded before implementation: the existing
  `PluginHost.qml` and already-scoped facade QML types may receive only the
  source-ID-to-active-clone routing needed to preserve copied plugin IPC
  identities. This does not widen third-party capabilities or change the
  existing owner checks.
- Allowed test files: `aurelia-shell/tests/`, including isolated temporary
  first-party/user plugin trees and local Git-free clone fixtures, and this
  tracker.
- Compatibility boundary: packaged first-party plugin files, current plugin
  IDs, active-bar selection, bar layout/settings, compatibility IPC aliases,
  user-owned plugin trees, and plugin-owned state files must remain unchanged
  unless an isolated clone operation explicitly targets the fixture.
- Runtime behavior impact: user-level source copy, manifest identity, and
  explicit clone provenance only; no live plugin activation, shell restart,
  installer/package/repository mutation, systemd/greetd change, or live-session
  change.
- Persisted user state impact: isolated clone/config fixtures only. Clone
  writes must validate before mutation, refuse symlink/traversal/collision
  hazards, preserve bar position/settings, and clean up recoverably on failure.
- Security boundary: cloning copies unsandboxed QML source but never executes
  plugin code or install hooks. Clone metadata cannot grant trusted
  capabilities to a user plugin.
- Contract freeze: `aurelia.clonedFrom` is syntactic provenance only; runtime
  routing may use it only when the referenced manifest is currently discovered
  as first-party. A clone receives no trusted capability stamp. A clone state
  record must retain the prior active bar, source-bar presence, source disable
  state, and clone/source IDs so disable/remove can restore the prior state.
- Rollback: revert only T17 clone/provenance/test/tracker changes if a
  mandatory gate fails; preserve completed T00–T16 history and user-owned
  changes.

- [x] Add `aurelia-plugin clone <id>` for first-party plugins.
- [x] Generate a collision-safe user-owned ID.
- [x] Copy the complete plugin directory and every declared local dependency.
- [x] Add explicit safe clone dependency metadata equivalent to Omarchy's
  `clonePaths` where a complete directory copy is insufficient.
- [x] Rewrite only identity-sensitive metadata and preserve stable source IPC
  IDs where required.
- [x] Record clone origin and source restoration intent.
- [x] Preserve bar position, instance settings, active-bar selection, and
  compatibility aliases when switching to a clone.
- [x] Restore the original implementation when an active clone is removed.
- [x] Never edit or overwrite the first-party source tree.
- [x] Add failure cleanup tests for partial clone, invalid source, collision,
  missing dependency, and discovery failure.

Evidence:
- Tests: `bash aurelia-shell/tests/test_plugin_clone.sh` — `18` passed, `0`
  failed; `bash aurelia-shell/tests/run.sh` — `395` passed, `0` failed; root
  `bash tests/run.sh` — `228` passed, `0` failed.
- Runtime/fixture evidence: inert first-party and sibling-manifest clone
  fixtures verified complete/dependency copies, identity rewriting, stable
  source IDs, collision allocation, `--edit`, invalid/symlink/missing-source
  rejection, discovery and enablement cleanup, and remove-before-delete. The
  isolated QML state fixture verified bar settings/position, active-bar
  restoration, multi-kind source disablement, and `cloneSourceRestores`; the
  facade fixture verified source-ID aliases remain owner-scoped. No live shell
  activation or restart was performed.
- Files changed: the dedicated `clone.sh`, plugin CLI wiring and removal
  boundary, canonical manifest metadata validation, `PluginCloneState.qml`,
  `PluginProvenance.qml`, `PluginRegistry.qml`, `ShellConfig.qml`,
  `PluginHost.qml`, the three scoped facade types, services `qmldir`, the
  Aurelia test runner, clone fixtures, and this tracker.
- User-visible behavior changed: yes — additive `aurelia-plugin clone
  <aurelia.plugin-id> [--edit]` workflow; existing Aurelia feature behavior and
  design language are unchanged.
- Existing Aurelia feature impact: no regressions observed; first-party source
  files, current IDs, bar defaults/settings, compatibility IPC, and plugin
  capabilities remain unchanged. Clones never inherit trusted capabilities.
- Rollback/migration evidence: all clone writes stage under the user plugin
  directory, validate before publication, reject symlinks/traversal/special
  files, clean up on discovery/enablement failure, and require disable/state
  rollback before removal. Clone state is normalized through the existing
  atomic mode-600 shell config writer. Pre-change checkpoint: `26a8d91`.
- Review: CP3 passed. Repository-wide shell syntax passed for `222` scripts;
  `git diff --check` passed; ShellCheck was unavailable and was not installed;
  no temporary repository artifacts remain.

Exit gate: a user can safely customize any eligible first-party plugin without
editing packaged Aurelia source.

Dependencies: T03, T04, T10, T12, T14.

### T18. Complete add/update/remove lifecycle

Status: `[x]` complete — CP2 and CP3 passed; staged add/update/remove lifecycle task.

CP2 pre-change boundary:

- Allowed production files: the Aurelia plugin CLI lifecycle modules, the
  existing bounded Git/placement helpers, narrow lifecycle/provenance helpers,
  and their help/dispatch wiring. No shell UI, installer, package, systemd,
  greetd, or live-session state is in scope.
- Allowed test files: `aurelia-shell/tests/`, including local Git-free command
  fixtures and temporary user-plugin trees. No network or live plugin source
  execution is allowed.
- Compatibility boundary: existing `add --enable`, `update <id> --yes`,
  `remove <id> --yes`, manifest validation, clone behavior, user settings,
  first-party trees, and current CLI output remain compatible unless the new
  lifecycle safety contract requires an explicit failure or backup message.
- Runtime behavior impact: user-owned plugin-tree mutation only; every staged
  tree must validate before publication, and every publication must remain
  recoverable until rescan/discovery succeeds.
- Persisted user state impact: no new shell-state schema is required. Removal
  must move user plugin trees to an installer-owned hidden backup rather than
  purge them; update/add provenance is a sidecar in the managed plugin tree.
- Security boundary: only HTTPS Git sources are accepted; Git transport/config
  helper environment is neutralized or rejected; no install hooks, sudo, or
  plugin code execution is introduced.
- Rollback: keep the old plugin tree until validation, publication, rescan, and
  discovery succeed. On failure restore the old tree and preserve the user
  tree; never use destructive Git reset/checkout or overwrite unrelated files.

- [x] Keep add disabled-by-default unless explicitly enabled.
- [x] Add preflight duplicate-ID detection against the canonical catalog before
  moving staged code into the user plugin tree.
- [x] Keep staged clone/update validation before activation.
- [x] Keep HTTPS and bounded Git operations, disable interactive Git prompts,
  and reject unsafe transport-helper inputs.
- [x] Add interactive review paths for human use and explicit `--yes` paths for
  automation.
- [x] Add update-one and update-all behavior.
- [x] Show a reviewable diff before an interactive update.
- [x] Refuse updates over local modifications.
- [x] Validate updated manifests before activation and roll back on validation
  or rescan failure.
- [x] Record remote URL, selected ref/commit, version, and validation result for
  provenance and diagnostics.
- [x] Make manual/non-Git plugin removal recoverable; never purge user data.
- [x] Ensure `remove` disables the plugin before removing its source.
- [x] Add local Git repository fixtures so lifecycle tests never require network.

Evidence:
- Tests: `bash aurelia-shell/tests/test_plugin_lifecycle_management.sh` — `14`
  passed, `0` failed; `bash aurelia-shell/tests/run.sh` — `409` passed, `0`
  failed; root `bash tests/run.sh` — `228` passed, `0` failed.
- Runtime/fixture evidence: local fake Git/shell fixtures verified canonical
  duplicate preflight, disabled-by-default add, explicit enablement, provenance
  sidecars with mode `600`, transport environment neutralization, non-TTY
  confirmation, update-one/update-all, dirty-tree refusal, invalid update
  rejection, rescan/discovery rollback, disable-before-remove, and recoverable
  non-Git backups. Existing clone and privilege suites remained green. No live
  network, plugin code, shell activation, or installer execution was used.
- Files changed: plugin CLI module loading/help/dispatch, the new lifecycle
  module, the T16 inert command fixtures/assertions required by the module
  split, the Aurelia test runner, lifecycle management fixtures/tests, and this
  tracker.
- User-visible behavior changed: yes — add/update/remove now require explicit
  confirmation in interactive use or `--yes` in automation, update supports
  `--all`, and removal reports a recoverable backup path. Existing explicit
  `add --enable`, `update <id> --yes`, and `remove <id> --yes` remain supported.
- Existing Aurelia feature impact: no regressions observed; plugin IDs,
  settings, bar state, clone behavior, privilege ownership, and feature UI are
  unchanged. Lifecycle changes remain user-plugin-tree scoped.
- Rollback/migration evidence: staged add/update trees are cleaned on failure;
  update retains the previous tree through validation, publication, rescan,
  and discovery and restores it on failure; remove moves source to a hidden,
  collision-safe backup; Git prompts/config/transport helpers are bounded or
  neutralized. Pre-change checkpoint: `0c269e3`.
- Review: CP3 passed. Repository-wide shell syntax passed for `224` scripts;
  `git diff --check` passed; ShellCheck was unavailable and was not installed;
  no temporary repository artifacts remain.

Exit gate: add, update, remove, clone, interruption, validation failure, and
rollback paths are deterministic and recoverable.

Dependencies: T05, T10, T17.

### T19. Add plugin management and discoverability parity

Status: `[x]` complete — CP2 and CP3 passed; plugin discoverability and management-surface task.

CP2 pre-change boundary:

- Allowed production files: the canonical plugin catalog/host projection,
  existing shell catalog IPC, and Aurelia Command Center plugin/model/module
  files plus inert metadata needed to expose a `Plugins` module. The existing
  Command Center layout, theme tokens, keyboard behavior, and provider actions
  remain unchanged.
- Allowed test files: `aurelia-shell/tests/`, including isolated catalog and
  Command Center fixtures with fake CLI/shell processes. No live plugin action,
  installer, package, systemd, greetd, or user configuration mutation is
  allowed.
- Compatibility boundary: current catalog fields, `listPlugins`/`catalogPlugins`
  IPC, existing Command Center modules and shortcuts, plugin CLI ownership,
  scoped facades, and all first-party feature behavior remain compatible.
- Runtime behavior impact: additive read-only catalog fields and an explicit
  management UI action path. UI handlers may launch only the existing
  structured plugin CLI; they do not mutate shell state directly.
- Persisted user state impact: none for catalog reads or management actions;
  any mutation remains owned by the T18 CLI lifecycle and its existing state/
  backup boundaries.
- Security boundary: management UI receives detached catalog rows and invokes
  user-level CLI argv only. It must not receive raw registry/config objects,
  run shell strings, bypass `--yes` lifecycle boundaries, or make third-party
  code loadable.
- Rollback: remove only the additive catalog fields, module rows, management
  model, and isolated fixtures if a gate fails; preserve all prior Command
  Center and plugin behavior.

- [x] Add a human-readable and JSON plugin list with source, kind, enabled,
  active, loaded, visible, in-bar, can-disable, clone origin, and error state.
- [x] Add plugin enable/disable/clone/remove/update actions to an Aurelia-owned
  management surface.
- [x] Keep management UI separate from plugin mutation internals.
- [x] Make management UI consume the canonical catalog and lifecycle APIs.
- [x] Preserve Command Center's existing modules and design language.
- [x] Add a plugin author preview/validation action without loading plugin code.

Evidence:
- Tests: `bash aurelia-shell/tests/test_plugin_management.sh` — `5` passed,
  `0` failed; affected launcher/catalog/backend/clone suites — `31` passed,
  `0` failed; `bash aurelia-shell/tests/run.sh` — `414` passed, `0` failed;
  root `bash tests/run.sh` — `228` passed, `0` failed.
- Runtime/fixture evidence: the real `PluginRegistry` catalog projection
  reported source, kind, active, enablement, in-bar, can-disable, clone
  provenance, and error state. The real Command Center
  `PluginManagementModel` generated enable/disable/clone/update/remove/
  validate rows and invoked a fake CLI with structured `remove <id> --yes`
  argv. No plugin code, live action, installer, package, or user state was
  executed.
- Files changed: `PluginCatalogProjection.qml`, host/shell catalog projection
  wiring, `PluginManagementModel.qml`, Command Center model/plugin/module
  metadata, the human/JSON plugin list CLI projection, affected preservation
  tests, management fixtures, and this tracker.
- User-visible behavior changed: yes — an additive `Plugins` Command Center
  module and complete `aurelia-plugin list` projections; existing modules,
  shortcuts, layout, theme tokens, and design language are unchanged.
- Existing Aurelia feature impact: no regressions observed. The management UI
  launches only the existing user-level lifecycle CLI; it does not mutate
  `ShellConfig`, packages, services, or system state directly.
- Rollback/migration evidence: catalog reads and rows are detached; lifecycle
  mutation remains owned by T18 CLI paths with its existing `--yes`, staging,
  backup, and rollback boundaries. Removing T19 changes removes only the
  additive catalog fields/module/model and preserves prior Command Center
  behavior. Pre-change checkpoint: `10693b2`.
- Review: CP3 passed. Repository-wide shell syntax passed for `225` scripts;
  `git diff --check` passed; ShellCheck was unavailable and was not installed;
  no temporary repository artifacts remain.

Exit gate: a user can discover and manage plugins without knowing private file
paths or editing JSON manually.

Dependencies: T05, T12, T17, T18.

### T20. Match development reload behavior safely

Status: `[x]` complete — CP2 and CP3 passed; bounded plugin watcher and targeted reload task.

CP2 pre-change boundary:

- Allowed production files: `PluginRegistry.qml`, `shell.qml`, a narrow
  watcher/path-policy helper, and existing reload timer wiring. No production
  plugin source, live configuration, installer, package, systemd, greetd, or
  reboot changes are in scope.
- Allowed test files: `aurelia-shell/tests/`, including isolated watcher-policy
  fixtures and fake event/process inputs. Tests must not start a live watcher
  against user trees or mutate the active shell.
- Compatibility boundary: current targeted reload behavior, resident bar and
  sensitive-service retention, scoped-facade revocation, plugin IPC, and the
  restart boundary for shell core/theme/Hyprland files remain unchanged.
- Runtime behavior impact: development mode only. Known plugin paths continue
  through debounced targeted reload; grouped/sibling/new/ambiguous plugin-tree
  changes use a bounded full rescan. Watcher failure becomes an explicit
  unavailable state with no uncontrolled retry loop.
- Persisted user state impact: none. Watcher events never write shell config or
  plugin-owned state.
- Security boundary: only the first-party and user plugin roots are watched;
  no broad Quickshell/core tree watch or plugin code execution is introduced.
- Rollback: revert only the watcher-policy helper, registry/shell event wiring,
  tests, and tracker if a gate fails; preserve all prior lifecycle and host
  commits.

- [x] Define the production/development watcher policy explicitly against the
  Omarchy reference.
- [x] Watch only first-party and user plugin trees; never enable broad
  Quickshell core file watching as a replacement.
- [x] Debounce atomic saves.
- [x] Support targeted plugin reload and explicit full rescan.
- [x] Keep stateful and sensitive services alive across unrelated reloads.
- [x] Revoke and recreate facades when plugin capability profiles change.
- [x] Preserve the current Aurelia restart boundary for `shell.qml`, shared
  services, theme core, and Hyprland Lua.
- [x] Add tests for changed QML, JS, JSON, Lua/config files, deletion, rename,
  invalid intermediate writes, and watcher failure.

Evidence:
- Tests: `bash aurelia-shell/tests/test_plugin_watcher.sh` — `4` passed, `0`
  failed; `bash aurelia-shell/tests/run.sh` — `418` passed, `0` failed; root
  `bash tests/run.sh` — `228` passed, `0` failed.
- Runtime/fixture evidence: the real `PluginWatcherPolicy.qml` mapped direct,
  grouped, sibling-ambiguous, user, new first-party, hidden staging, `.git`,
  and out-of-scope paths across QML/JS/JSON/Lua/conf extensions. Known paths
  target one plugin; ambiguous/new grouped paths request a full rescan. Static
  and existing reload fixtures verify the 150ms debounce, targeted Loader
  boundary, resident-service retention, facade sync/revocation, and explicit
  fail-closed watcher state. No live watcher or active session was touched.
- Files changed: `PluginWatcherPolicy.qml`, registry watcher mapping/failure
  state and signal wiring, shell full-rescan handling, services `qmldir`, the
  watcher fixture/test, the Aurelia test runner, and this tracker.
- User-visible behavior changed: no in normal operation; development-mode
  plugin changes now map grouped/sibling paths correctly and watcher failure
  reports an explicit unavailable state instead of retrying indefinitely.
- Existing Aurelia feature impact: no regressions observed; shell core restart
  boundaries, bar geometry, resident notification/service ownership, scoped
  facade behavior, and plugin IPC remain unchanged.
- Rollback/migration evidence: watcher events are read-only and do not modify
  persisted state; only exact plugin IDs are targeted, otherwise the existing
  bounded full-rescan path is used. Pre-change checkpoint: `edcfbae`.
- Review: CP3 passed. Repository-wide shell syntax passed for `226` scripts;
  `git diff --check` passed; ShellCheck was unavailable and was not installed;
  no temporary repository artifacts remain.

Exit gate: plugin source changes behave like the reference without duplicate
hosts, duplicate services, broken lock/notification owners, or broad reloads.

Dependencies: T07, T14, T15.

---

## Phase 6 — Remove static feature assumptions while preserving Aurelia behavior

### T21. Convert the Command Center provider catalog to the parity model

Status: `[x]` complete — CP2 and CP3 passed; Command Center provider catalog and menu-surface task.

CP2 pre-change boundary:

- Allowed production files: existing Aurelia Command Center module/provider
  files, new narrow provider/menu model helpers, the first-party
  `aurelia.menu` plugin and its shipped menu data, and generic host/catalog
  wiring required to discover that manifest. No existing Command Center visual
  layout, theme token, shortcut, backend ownership, or plugin feature may be
  rewritten for Omarchy appearance.
- Allowed test files: `aurelia-shell/tests/`, including isolated module,
  provider, manifest-menu, user-extension, visibility/checked-state, and
  provider-failure fixtures. No arbitrary shell command, package transaction,
  live menu action, installer, or active user-state mutation is allowed.
- Compatibility boundary: current Command Center modules/providers/actions,
  `aurelia.launcher` IPC, first-party plugin discovery, user module overrides,
  and all existing Aurelia design language remain compatible. The menu surface
  is additive and uses a separate `aurelia.menu` identity.
- Runtime behavior impact: declarative provider metadata and an on-demand
  manifest-backed menu surface. Provider actions must be allow-listed,
  structured argv or approved Aurelia APIs; unknown/invalid providers and
  actions remain inert and fail closed.
- Persisted user state impact: shipped menu data is immutable repository-owned
  input; user menu extensions are read-only input from a separate optional
  XDG file and are never merged by the shell into unrelated state.
- Security boundary: menu/provider data is validated before presentation; no
  manifest menu field may contain an executable shell string or bypass facade,
  privilege, or lifecycle boundaries. Same-process QML remains unsandboxed.
- Rollback: revert only provider metadata/model/menu files and isolated tests if
  a gate fails; preserve all completed T00–T20 commits and current features.

- [x] Keep the Command Center as an Aurelia feature with its current name,
  layout, keyboard behavior, and design language.
- [x] Separate generic module metadata from provider implementation.
- [x] Make the module registry consume declarative metadata and user overrides.
- [x] Ensure existing modules remain available with identical behavior.
- [x] Add an Aurelia-owned manifest-backed menu surface equivalent to Omarchy's
  menu plugin, including shipped menu data and user extension data, while
  preserving the existing Command Center as an Aurelia-specific feature.
- [x] Define safe menu visibility, checked-state, and action-provider contracts;
  use structured argv or explicitly approved Aurelia actions instead of copying
  arbitrary shell-string evaluation.
- [x] Define a safe provider extension point for future modules without allowing
  arbitrary shell command injection.
- [x] Keep unimplemented modules inert and fail-closed.
- [x] Add module catalog, enablement, invalid metadata, and provider failure
  tests.

Evidence:
- Tests: `bash aurelia-shell/tests/test_aurelia_menu.sh` — `4` passed, `0`
  failed; affected menu/manifest/catalog/bar/launcher suites — `52` passed,
  `0` failed; `bash aurelia-shell/tests/run.sh` — `422` passed, `0` failed;
  root `bash tests/run.sh` — `228` passed, `0` failed.
- Runtime/fixture evidence: `aurelia.menu` was validated and its real
  `MenuModel` fixture merged shipped and XDG user data, rejected arbitrary
  action strings, expanded the bounded plugin provider, evaluated checked
  state, and dispatched the approved bar action. The real registry catalog
  projection and Command Center management/provider model remained isolated;
  no live menu action, plugin code, installer, package, or active user state
  was executed.
- Files changed: the first-party `aurelia.menu` manifest/data/model/surface,
  Command Center provider metadata/dispatch, inventory/preservation fixture
  updates, menu/catalog tests and fixtures, the Aurelia test runner, and this
  tracker.
- User-visible behavior changed: yes — an additive manifest-backed Aurelia
  Menu and a provider-driven Plugins module; existing Command Center layout,
  shortcuts, design tokens, modules, and backend behavior are preserved.
- Existing Aurelia feature impact: no regressions observed. Menu data accepts
  only approved Aurelia actions/providers; invalid or unimplemented entries are
  inert and fail closed. No arbitrary shell-string execution was introduced.
- Rollback/migration evidence: shipped menu data is repository-owned and user
  extensions are read-only optional XDG input; the menu has no write path.
  Removing the task removes only the additive menu/provider files and expected
  inventory/test fixtures. Pre-change checkpoint: `e89db75`.
- Review: CP3 passed. Repository-wide shell syntax passed for `227` scripts;
  `git diff --check` passed; ShellCheck was unavailable and was not installed;
  no temporary repository artifacts remain.

Exit gate: adding a supported Command Center provider does not require editing
the host's generic navigation code.

Dependencies: T03, T13, T14.

### T22. Migrate all existing Aurelia plugins to the canonical contract

Status: `[x]` complete — CP2 and CP3 passed; existing-plugin canonical manifest migration task.

CP2 pre-change boundary:

- Allowed production files: the existing first-party plugin manifests and
  narrowly scoped generic manifest/catalog/test helpers required to consume
  canonical metadata. Plugin QML/JS/Lua/backend implementation files are
  read-only unless a focused runtime fixture proves a compatibility adapter is
  required.
- Allowed test files: `aurelia-shell/tests/`, including an all-plugin manifest
  matrix, entry-point existence checks, canonical settings injection checks,
  and the existing per-feature tests. No live plugin activation, installer,
  package, systemd, greetd, or user configuration mutation is allowed.
- Compatibility boundary: every existing plugin ID, entry-point path, bar
  position/settings, backend owner, failure class, IPC alias, theme token, and
  feature-specific behavior must remain unchanged. Legacy manifest reads stay
  available for third-party compatibility, but shipped first-party manifests
  become canonical.
- Runtime behavior impact: metadata representation only, with the same generic
  registry/host/bar loaders and the same default values made explicit in the
  manifests.
- Persisted user state impact: none. Existing state files and shell config are
  read unchanged; no migration write is introduced.
- Security boundary: canonical metadata remains validated before loading;
  first-party-only capability ownership, structured backends, and scoped
  third-party facades are unchanged.
- Rollback: revert only first-party manifest canonicalization, focused matrix
  updates, and this tracker if a preservation gate fails; preserve T00–T21.

For each plugin below:

- [x] migrate its manifest without changing its user-visible behavior;
- [x] make its entry points load through the generic registry;
- [x] make its settings use the canonical state/API boundary;
- [x] preserve its current backend ownership and failure classification;
- [x] add or update focused tests and runtime fixtures;
- [x] add a design-language review against Aurelia tokens and primitives.

Feature preservation list:

- [x] `aurelia.bar`: resident bar, exact center anchor, layout, logo, widget
  ownership, single-popout behavior, themes, and fallback.
- [x] `aurelia.background`: per-screen background service, image/video support,
  safe fallback, and state reload.
- [x] `aurelia.image-picker`: image carousel/selector behavior and theme use.
- [x] `aurelia.bluetooth`: BlueZ model, discovery ownership, power state,
  paired/discovered actions, and popup behavior.
- [x] `aurelia.calendar`: clock-owned calendar surface and geometry.
- [x] `aurelia.clock`: formatting, center placement, and calendar routing.
- [x] `aurelia.keybindings`: keyboard capture, provider integration, settings,
  compatibility targets, and structured backend execution.
- [x] `aurelia.launcher`: Command Center navigation, application search,
  calculator, file search, updates, About, and package workflows.
- [x] `aurelia.monitor`: brightness, display scale/resolution, text size, and
  multi-monitor behavior.
- [x] `aurelia.network`: NetworkManager state, DNS authorization, QR handoff,
  speed-test handoff, and credential boundaries.
- [x] `aurelia.notifications`: notification server ownership, bounded history,
  DND, popups, screenshot previews, and cross-workspace routing.
- [x] `aurelia.power`: power actions and confirmation behavior.
- [x] `aurelia.screenshot`: bar-owned capture, region selection, delay/pointer
  settings, clipboard, and notification integration.
- [x] `aurelia.speedtest`: bounded cancellable speed-test panel.
- [x] `aurelia.tasklist`: tasklist layout and window context menu.
- [x] `aurelia.theme`: data-only theme selection and background handoff.
- [x] `aurelia.tray`: system tray ownership and menu behavior.
- [x] `aurelia.weather`: automatic/pinned location, units, refresh, and popup.
- [x] `aurelia.wifiqr`: QR generation, cancellation, and network handoff.
- [x] `aurelia.workspace-switcher`: `SUPER + TAB`, workspace cards, preview
  fallback, and selection behavior.
- [x] `aurelia.workspaces`: workspace indicators and Hyprland dispatch.

Additional first-party surface covered by T21:

- [x] `aurelia.menu`: manifest-backed menu model, approved providers/actions,
  user extension boundary, and Aurelia token review.

Evidence:
- Tests: `bash aurelia-shell/tests/test_plugin_migration.sh` — `3` passed,
  `0` failed; affected first-party feature/manifest suites — `145` passed,
  `0` failed; `bash aurelia-shell/tests/run.sh` — `425` passed, `0` failed;
  root `bash tests/run.sh` — `228` passed, `0` failed.
- Runtime/fixture evidence: the all-plugin matrix validated all `22` shipped
  first-party manifests and every declared entry point; every bar widget now
  uses canonical `entryPoints.barWidget` and explicit metadata. Existing bar,
  background, picker, Bluetooth, display, network, notification, screenshot,
  Command Center/menu, and other feature fixtures remained green.
- Files changed: the `11` canonicalized bar-widget manifests, the T22
  preservation inventory and focused migration/feature test assertions, and
  this tracker. No plugin implementation, backend, state file, or visual
  token was changed.
- User-visible behavior changed: no intended behavior change; this is a
  canonical metadata representation migration with previous fallback values
  made explicit.
- Existing Aurelia feature impact: no regressions observed; IDs, entry-point
  paths, default bar layout, settings, backend ownership, IPC aliases,
  failure classes, and design language are preserved.
- Rollback/migration evidence: legacy `bar-widget` manifest reads remain
  supported for third-party compatibility; reverting the manifest/test/tracker
  changes restores the prior representation without touching user state.
  Pre-change checkpoint: `0b7f400`.
- Review: CP3 passed. Repository-wide shell syntax passed for `228` scripts;
  `git diff --check` passed; ShellCheck was unavailable and was not installed;
  no temporary repository artifacts remain.

Exit gate: all existing Aurelia features pass their preservation fixtures after
being hosted by the parity architecture.

Dependencies: T06 through T21 as applicable to each plugin.

### T23. Eliminate duplicated defaults and feature-specific host registration

Execution status: COMPLETE

Checkpoint 2 — canonical bar-default boundary:

- Allowed production scope: the repository-owned bar-default data document, its
  read-only loader/service registration, and the narrow host/bar bindings needed
  to consume that document.
- Compatibility boundary: preserve the existing default bar identity, widget
  order, widget settings, anchor, and fallback behavior; do not change plugin
  feature behavior or live workstation state.
- Verification boundary: static preservation checks and an isolated loader
  fixture must pass before this task is committed.
- Rollback: revert the task commit; the prior embedded default remains the
  recovery source.

- [x] Move the default bar layout to one canonical repository-owned data file.
- [x] Keep an embedded fallback only for safe startup recovery.
- [x] Remove duplicate default layout definitions from host and bar code.
- [x] Remove generic host registration lists that must be edited for every new
  plugin.
- [x] Preserve current defaults byte-for-byte in the preservation fixture.
- [x] Keep feature-specific registration only where the feature owns a real
  external capability or compatibility alias.

Exit gate: a new manifest-backed plugin can be discovered and managed without
editing unrelated Aurelia default lists or host registration branches. PASS.

Evidence:

- Added `aurelia-shell/config/bar-default.json` as the canonical repository
  default document and `BarDefaultConfig.qml` as its read-only, validated
  loader with an embedded recovery value.
- ShellConfig and the resident bar consume the loader; feature-specific
  compatibility seams remain untouched.
- Updated preservation and affected-plugin contracts to validate the canonical
  document rather than duplicated QML literals.
- Focused T23 and affected-plugin suites: 137 passed, 0 failed.
- Full Aurelia suite: 428 passed, 0 failed.
- Repository suite: 228 passed, 0 failed.
- Repository-wide shell syntax: 229 scripts passed.
- QuickShell fixture verified the loaded canonical identity, anchor, order, and
  widget IDs in an isolated temporary XDG environment.
- No live shell, installer, packages, systemd/greetd state, or user
  configuration was touched.
- Checkpoint: `5dc6667` (`chore(checkpoint): freeze canonical bar defaults boundary`).

Dependencies: T05, T10, T21, T22.

---

## Phase 7 — Complete verification, documentation, and cutover

### T24. Complete the generic plugin test matrix

Execution status: COMPLETE

Checkpoint 2 — generic contract-matrix boundary:

- Allowed scope: isolated Aurelia test modules, disposable plugin fixtures,
  deterministic local Git fixtures, and the test runner/tracker.
- Compatibility boundary: tests must not mutate the live workstation, launch
  the production shell, alter installed/user plugin trees, or change any
  feature implementation.
- Survivability boundary: every contained fault must be asserted against host
  liveness, healthy-plugin availability, and built-in bar fallback before a
  failure is considered contained.
- Escalation rule: if the matrix exposes a production defect, stop at the
  failing invariant and create a separate corrective checkpoint before any
  production edit.
- Rollback: revert the matrix commit; no production runtime or live state is
  changed by the task.

- [x] Add manifest enumeration tests for every Aurelia first-party manifest.
- [x] Add entry-point existence and safe-path tests for every declared kind.
- [x] Add runtime fixture loading for every supported entry-point kind.
- [x] Add broken-plugin survivability fixtures proving that syntax/import,
  initialization, service, widget, callback, and reload failures do not crash
  the host or prevent healthy plugins from loading.
- [x] Assert host ping, listPlugins, built-in bar fallback, and at least one
  healthy plugin after every contained failure.
- [x] Add first-party and third-party registry tests.
- [x] Add duplicate-ID, namespace, symlink, malformed JSON, and unsafe-path
  tests.
- [x] Add bar-widget catalog, placement, settings, multiple-instance, and
  popup-routing tests.
- [x] Add replacement-bar fallback and lifecycle tests.
- [x] Add scoped-facade and capability-revocation tests.
- [x] Add service isolation tests for every sensitive service.
- [x] Add add/update/remove/clone/rollback CLI tests using local Git fixtures.
- [x] Add development reload tests.
- [x] Add cross-plugin compatibility tests for every retained Aurelia feature.
- [x] Keep tests deterministic and isolated from the live workstation.

Exit gate: the generic plugin contract is tested independently of any one
feature plugin, and all feature-specific suites remain green. PASS.

Evidence:

- Added tests/test_plugin_contract_matrix.sh and the disposable
  tests/fixtures/plugin-contract-matrix/shell.qml.
- The matrix enumerates all 22 first-party manifests, validates each through
  the canonical CLI boundary, checks each declared kind's entry point, and
  rejects symlinked plugin trees.
- Isolated CLI fixtures reject malformed JSON, reserved namespaces, unsafe
  entry-point paths, and symlinked entry points. An isolated real registry
  fixture rejects duplicate IDs while retaining the valid generation.
- The runtime fixture loads bar, bar-widget, panel, overlay, menu, and service
  entry points through the real PluginHost; it verifies ping/list projection,
  open/close routing, callback quarantine, targeted reload recovery, healthy
  service/widget retention, replacement-bar quarantine, and built-in fallback.
- Existing generic suites are linked by the matrix coverage map for registry
  source separation, survivability, bar metadata/placement/settings,
  replacement lifecycle, facades, sensitive services, lifecycle
  add/update/remove/rollback, watcher reload, and migration preservation.
- T24 matrix: 82 passed, 0 failed.
- Full Aurelia suite: 510 passed, 0 failed.
- Repository suite: 228 passed, 0 failed.
- Repository-wide shell syntax: 230 scripts passed.
- Shellcheck was not installed and was skipped.
- No live shell, installer, packages, systemd/greetd state, or user
  configuration was touched.
- Checkpoint: c9fd0cd (chore(checkpoint): freeze generic plugin test matrix boundary).

Dependencies: T02 through T23.

### T25. Add visual and interaction parity acceptance checks

Execution status: COMPLETE

Checkpoint 2 — repository-only acceptance boundary:

- Allowed scope: deterministic static checks, isolated QuickShell fixtures,
  existing feature interaction contracts, and the test runner/tracker.
- Compatibility boundary: preserve all Aurelia feature implementations and
  design tokens; do not launch the production shell or modify live Wayland,
  Hyprland, user configuration, systemd, or greetd state.
- Live-validation boundary: actual Wayland/visual acceptance remains a
  separately authorized phase and must be recorded as deferred here.
- Rollback: revert the acceptance-test commit; no production runtime or live
  state is changed by this task.

- [x] Verify bar placement, orientation, center anchoring, and popup ownership.
- [x] Verify plugin enable/disable/clone/remove flows visually and through IPC.
- [x] Verify Command Center/plugin-management navigation using Aurelia's design
  language.
- [x] Verify loading and reload do not create duplicate windows, timers, IPC
  handlers, service owners, or notification registrations.
- [x] Verify all custom Aurelia features retain their current appearance and
  interaction behavior.
- [x] Use live QML/Wayland tests only as a separately authorized validation
  phase; do not enable them during ordinary repository-only changes.

Exit gate: static and isolated tests agree with runtime/visual evidence, and
any unavailable live evidence is explicitly recorded rather than claimed. PASS
for repository-only acceptance; live visual evidence remains deferred pending
explicit authorization.

Evidence:

- Added tests/test_plugin_acceptance.sh and registered it in the Aurelia test
  runner.
- Canonical bar geometry, orientation, center anchor, and single-popout
  ownership pass static acceptance checks.
- Lifecycle IPC ownership, enable/disable/clone/remove coverage, Command
  Center navigation/design-language coverage, resident-service and
  notification no-duplicate guards, and retained feature interaction owners
  pass.
- The live QML/Wayland smoke gate remains explicit and skipped; no production
  shell or live display session was started.
- T25 acceptance suite: 6 passed, 0 failed, including the explicit
  live-validation skip.
- Full Aurelia suite: 516 passed, 0 failed.
- Repository suite: 228 passed, 0 failed after the T25-only changes.
- Repository-wide shell syntax: 231 scripts passed.
- Shellcheck was not installed and was skipped.
- No installer, packages, systemd/greetd state, or user configuration was
  touched.
- Checkpoint: 74f67e5 (chore(checkpoint): freeze repository-only acceptance boundary).

Dependencies: T22, T24.

### T26. Publish plugin authoring and maintenance documentation

Execution status: COMPLETE

Checkpoint 2 — authoring-documentation boundary:

- Allowed scope: plugin authoring/maintenance documentation, a minimal
  disposable example plugin fixture, documentation links, documentation
  synchronization tests, and the tracker.
- Compatibility boundary: documentation and fixtures must describe existing
  behavior; they must not add a second manifest schema, production runtime
  path, installer mutation, or live configuration.
- Safety boundary: examples must validate without executing install hooks,
  requiring privileges, or touching the live plugin directory.
- Rollback: revert the documentation/example commit; no production runtime or
  live state is changed by this task.

- [x] Document the canonical manifest schema and kind-to-entry-point mapping.
- [x] Document the directory layout and source roots.
- [x] Document lifecycle, keepLoaded, multi-kind, bar, settings, and reload
  behavior.
- [x] Document the third-party facade API and scope rules.
- [x] Document no-sandbox behavior, trust requirements, no-hook policy, and
  bounded Git operations.
- [x] Add a minimal example plugin and validation instructions.
- [x] Add clone, update, remove, migration, and rollback instructions.
- [x] Document which behavior is Omarchy parity and which behavior is an
  intentionally preserved Aurelia feature.
- [x] Keep README, runtime comments, tests, and implementation synchronized.

Exit gate: a new plugin author can build, validate, install, enable, configure,
reload, test, update, clone, and remove a plugin without reading host internals.
PASS.

Evidence:

- Added docs/aurelia-plugin-authoring.md as the operational companion to the
  normative v1 contract and linked it from both Aurelia README surfaces.
- Added the isolated example plugin at
  examples/plugins/example.panel; it is outside the production plugin root,
  uses the canonical panel manifest, has safe injected-property defaults, and
  validates through the real aurelia-plugin CLI.
- The guide documents all supported kinds, canonical and legacy entry-point
  rules, source roots, lifecycle and reload behavior, bar metadata/settings,
  facades, trust/no-hook boundaries, maintenance commands, rollback, testing,
  parity language, and intentionally retained Aurelia features.
- Added test_plugin_documentation.sh to enforce documentation links, required
  topics, example safety, canonical validation, and command coverage.
- T26 documentation suite: 5 passed, 0 failed.
- Full Aurelia suite: 521 passed, 0 failed.
- Repository suite: 228 passed, 0 failed after the T26-only changes.
- Repository-wide shell syntax: 232 scripts passed.
- Shellcheck was not installed and was skipped.
- No installer, packages, systemd/greetd state, or user configuration was
  touched.
- Checkpoint: 8e418a1 (chore(checkpoint): freeze plugin authoring docs boundary).

Dependencies: T03, T05, T14, T17, T18, T24.

### T27. Perform the compatibility cutover

Execution status: COMPLETE

Checkpoint 2 — compatibility-cutover boundary:

- Allowed scope: explicit cutover/read-write invariant tests, isolated
  migration fixtures, tracker evidence, and narrowly observable documentation
  updates.
- Compatibility boundary: keep legacy manifest/state reads and compatibility
  aliases; do not remove migration code, change first-party features, or alter
  live user state.
- Activation boundary: canonical writes are verified only through isolated
  temporary state; no production installer, shell restart, package change,
  Wayland action, systemd/greetd mutation, or reboot is permitted.
- Rollback: revert the cutover-test commit; existing legacy-compatible runtime
  behavior remains unchanged.

- [x] Keep old Aurelia manifest/state reads enabled until all migration tests
  pass.
- [x] Enable canonical parity writes only after T24 and T25 pass.
- [x] Run the migration against isolated copies of representative old states.
- [x] Verify a second run produces no additional changes or backups.
- [x] Verify a failed migration leaves the original state usable.
- [x] Verify all first-party plugins start through the canonical path.
- [x] Verify third-party plugins remain disabled until explicit enablement.
- [x] Verify the built-in bar remains the safe default.
- [x] Remove compatibility code only in a separately reviewed cleanup task after
  the migration window is complete.

Exit gate: canonical parity is active, old valid state remains readable, and
the default Aurelia session is behaviorally unchanged. PASS.

Evidence:

- Added tests/test_plugin_cutover.sh and the isolated
  tests/fixtures/plugin-cutover/shell.qml probe.
- The probe verifies first-party default enablement, third-party default
  disablement, explicit third-party enablement/disablement, canonical default
  bar selection, and canonical serialization without live state.
- Representative legacy plugin strings, nested settings, and legacy bar
  entries migrate through the real ShellConfig loader into canonical inline
  state; the pre-migration file is preserved byte-for-byte as a recoverable
  backup.
- The second isolated run is byte-stable with no backup pollution. Existing
  malformed-source fixtures continue to verify original-state preservation.
- All first-party manifests remain on the canonical validated path, and
  compatibility reads/aliases remain present for the migration window.
- T27 cutover suite: 6 passed, 0 failed.
- Full Aurelia suite: 527 passed, 0 failed.
- Repository suite: 228 passed, 0 failed after the T27-only changes.
- Repository-wide shell syntax: 233 scripts passed.
- Shellcheck was not installed and was skipped.
- No installer, packages, systemd/greetd state, live user configuration, or
  reboot was touched.
- Checkpoint: 86011a9 (chore(checkpoint): freeze compatibility cutover boundary).

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
