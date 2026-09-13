# Aurelia–Omarchy Plugin Parity Tracker

Status: requested reference refresh T35, Audio foundation T36, T37 Audio
panel/default-bar work, T38 optional Microphone work, T39 Power redesign, T40
bar control-plane work, T41 persistent bar hiding, and corrective T43–T46
runtime/test-truth work are complete for repository/static/headless evidence;
T42 is next for final acceptance. T34 records the Bluetooth
discovery-retention issue and remains not started, T30 remains queued as the
separately requested plugin-local test-directory task, and live visual/
integration validation remains deferred pending explicit authorization.

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

- [x] T28 is complete.
- [x] T33 is complete.
- [ ] All gap-to-task rows are closed with evidence.
- [x] All preservation gates pass.
- [x] Runtime/visual evidence is separated from static/isolated evidence.
- [ ] The final working-tree diff is reviewed file-by-file after T33.

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

Execution status: COMPLETE

Checkpoint 2 — final audit boundary:

- Allowed scope: read-only comparison against the pinned Omarchy reference,
  repository test execution, tracker/completion evidence, and final risk
  documentation.
- Compatibility boundary: no production code, plugin source, manifest,
  configuration, installer, package, live Wayland, systemd/greetd state, or
  user data may be changed for this audit.
- Evidence boundary: distinguish static comparison, isolated runtime evidence,
  and unavailable live visual/integration evidence; do not claim 1:1 behavior
  from source resemblance alone.
- Rollback: revert the audit documentation commit; no runtime state changes.

- [x] Re-run the complete manifest and structure comparison against the pinned
  Omarchy reference.
- [x] Verify every Omarchy plugin-platform capability has an Aurelia owner or
  an explicitly documented, approved difference.
- [x] Verify every identified audit gap in the gap matrix below is closed.
- [x] Run `./tests/run.sh`.
- [x] Run `./aurelia-shell/tests/run.sh`.
- [x] Run syntax validation across every shell script in the repository,
  including the Aurelia tree.
- [x] Run ShellCheck when already installed; do not install it only for this
  gate.
- [x] Run authorized QML/runtime/visual acceptance tests separately from unit
  tests and report skipped evidence honestly.
- [x] Confirm no installer execution, package mutation, live configuration
  mutation, greetd/systemd mutation, or reboot occurred during implementation.
- [x] Record starting branch/SHA, final branch/SHA, files changed, tests,
  commits, remaining risks, and unverified integration scenarios.

Exit gate: Aurelia reaches the agreed Omarchy plugin parity target without
regressing any preserved Aurelia feature or safety invariant. PASS for the
repository-only structural parity target.

Evidence:

- Pinned reference audit: Omarchy checkout is clean at 31bd80daa461
  (29 canonical manifests plus 8 sibling manifests); Aurelia checkout has 22
  canonical first-party manifests.
- Both trees expose the same six supported kinds and canonical entry-point
  keys: bar, barWidget, menu, overlay, panel, and service.
- Read-only manifest/tree audit: Aurelia 22/22 and Omarchy 37/37 manifests
  have valid schema, safe existing entry points, and no symlinked plugin tree.
- Both architectures have zero plugin-local test directories. Aurelia's
  centralized runner now contains the generic matrix and acceptance/cutover
  gates; the reference keeps its shell test domains centralized as well.
- Every gap-to-task row below has completed closing-task evidence, and the
  final preservation gate is closed below.
- Repository suite: 228 passed, 0 failed.
- Full Aurelia suite: 527 passed, 0 failed.
- Repository-wide shell syntax: 233 scripts passed.
- Shellcheck was not installed and was skipped.
- Live Wayland/visual smoke was not authorized and was not run; the existing
  smoke gate remains explicit and skipped by default.
- No installer execution, package transaction, live user configuration,
  systemd/greetd mutation, reboot, or live shell restart occurred.
- T28 audit checkpoint: b53229f (chore(checkpoint): freeze final plugin parity audit).

Dependencies: T27 and every previous task.

### T29. Eliminate observed startup warning contracts

Execution status: COMPLETE

Checkpoint 2 — warning-cleanup boundary:

- Allowed production scope: the launcher panel property contract, display-panel
  delayed-refresh boundary, bar-widget IPC ownership guard, and Bluetooth
  object-manager probe.
- Allowed test scope: isolated warning-stream fixtures, affected feature tests,
  the Aurelia runner, and this tracker.
- Compatibility boundary: preserve launcher IPC, network/Bluetooth feature
  behavior, display refresh behavior, bar placement, and all existing design
  language; only eliminate invalid construction, stale callback, duplicate
  handler registration, and unsafe BlueZ construction.
- Safety boundary: no live shell restart, live configuration mutation,
  installer/package/systemd/greetd action, or reboot is allowed.
- Rollback: revert the T29 production/test commit; prior feature behavior and
  IPC owners remain recoverable.

- [x] Add a runtime test that loads the real Command Center plugin and catches
  missing-property construction failures.
- [x] Add a runtime test for DisplayPanel destruction during delayed refresh.
- [x] Ensure each network/Bluetooth bar widget instance has one effective IPC
  owner without duplicate-handler warnings.
- [x] Probe BlueZ's object-manager capability before constructing native
  Quickshell Bluetooth objects.
- [x] Keep benign unavailable-hardware conditions classified without hiding
  actionable QML warnings.
- [x] Run the affected and full Aurelia test suites and keep the root suite
  green.

Exit gate: the isolated warning fixture loads the affected components without
the reported construction, duplicate-handler, stale-refresh, or unsafe-BlueZ
warnings, while the existing feature and IPC contracts remain green. PASS.

Evidence:

- Added tests/fixtures/plugin-warning-smoke/shell.qml and
  tests/test_runtime_warning_contracts.sh.
- Fixed the missing CommandCenterPanel.pluginManagement property and removed
  the stale DisplayPanel delayed refresh callback.
- Network and Bluetooth compatibility IPC handlers are now instantiated only
  by the settled active bar-slot owner; NetworkPanel imports its local
  NetworkRow type.
- Bluetooth requires a successful object-manager introspection before loading
  Quickshell Bluetooth objects, preventing the reported BlueZ warning when the
  capability is unavailable.
- Warning-stream fixture: 5 passed, 0 failed. It checks the exact reported
  warning signatures and owner handoff. The offscreen runtime cannot construct
  PanelWindow-backed surfaces, so launcher/display construction remains
  statically checked there and requires separately authorized live validation.
- Affected suites: 94 passed, 0 failed.
- Full Aurelia suite: 532 passed, 0 failed.
- Repository suite: 228 passed, 0 failed.
- Repository-wide shell syntax: 234 scripts passed.
- Shellcheck was not installed and was skipped.
- No installer, package, live configuration, systemd/greetd state, or reboot
  was touched.
- Checkpoint: ee20444 (chore(checkpoint): freeze runtime warning cleanup boundary).

Dependencies: T24 through T28.

---

### T30. Add plugin-local test directories

Execution status: NOT STARTED (queued by explicit user request)

Scope note: the prior audit recorded zero plugin-local test directories in
both Omarchy and Aurelia. This task intentionally introduces a new Aurelia
test-layout requirement and therefore is not marked as Omarchy parity until
the structure and ownership decision are implemented and verified.

Checkpoint requirement: create a CP2 tracker entry before touching any plugin
directory, test file, runner, manifest, or documentation implementation.

- [ ] Define the exact local test-directory convention for every production
  Aurelia plugin, including naming, fixture placement, and runner ownership.
- [ ] Decide which existing centralized tests remain global and which focused
  contracts move beside their owning plugin.
- [ ] Add a local test directory to every production Aurelia plugin without
  changing plugin behavior, manifests, entry points, or user-visible design.
- [ ] Provide deterministic per-plugin test entry points that can be invoked
  independently and through aurelia-shell/tests/run.sh.
- [ ] Preserve the generic cross-plugin matrix, host survivability tests,
  centralized root command, and no-plugin-local-test claim only where still
  accurate.
- [ ] Add negative, lifecycle, settings, reload, and feature-preservation
  tests for each plugin where its responsibility requires them.
- [ ] Keep all local tests isolated from the live workstation, installer,
  packages, user configuration, systemd/greetd state, and reboot.
- [ ] Update the authoring guide, plugin README, tracker inventory, and test
  counts after implementation.

Exit gate: every production Aurelia plugin has the approved local test
structure, local and centralized test ownership is non-duplicative, the
one-command Aurelia test runner remains green, and no existing feature or
shell safety invariant regresses.

Dependencies: T24 through T29.

---

### T31. Preserve actionable warnings and errors (Never suppress warnings)

Execution status: COMPLETE — CP2 and CP3 passed

Scope note: this task is an observability and failure-classification audit. It
must not make the shell noisier by duplicating the same diagnostic, but it must
never hide an actionable plugin, loader, callback, IPC, or host-boundary
failure. A warning may be removed only by fixing the invalid state or by
replacing it with an explicit, test-covered, non-error classification whose
reason remains observable.

Pre-implementation finding (2026-09-13; not completion evidence): the live
Bluetooth plugin is discovered, enabled, loaded, and present in the bar, but
its public `ping` returns `false` and the catalog reports `visible:false`.
BlueZ and `hci0` are healthy, and the exact probe command exits `0`; its normal
human-readable `busctl introspect` output lists `.GetManagedObjects` and the
interface signals without repeating the full interface name. Aurelia's
`hasBluezService()` currently searches stdout for that full name, so the
successful probe is classified as unavailable, the panel loader never runs,
and the widget collapses to zero width. The corrective change must use the
probe result/capability contract (with an actionable final diagnostic), not
hide this false-negative behind the existing retry/early-return path.

Checkpoint 2 — T31 pre-change boundary:

- Allowed production scope: the Bluetooth probe/readiness boundary, host and
  bar-widget failure-reporting paths, and any production catch/redirect/filter
  that the inventory proves hides an actionable diagnostic.
- Allowed test scope: isolated warning/probe fixtures, static suppression-policy
  checks, affected plugin tests, the Aurelia runner, and this tracker.
- Compatibility boundary: preserve healthy-plugin loading, T02A quarantine,
  single-owner IPC, optional hardware classification, all Aurelia feature
  behavior, and the existing design language.
- Persisted/live-state impact: none; use only disposable XDG/runtime state and
  do not restart or mutate the live shell during implementation verification.
- Rollback: revert only T31-owned production/test/tracker changes if CP3 fails;
  preserve the prior parity commits and user-owned worktree state.

CP2 status: `[x]` contract, test boundary, impact boundary, and rollback path
recorded before implementation edits.

Checkpoint requirement: satisfied; CP2 was recorded before implementation.

- [x] Inventory every production `catch`, early-return failure gate,
  `Loader.Error` handler, stderr redirection, `|| true`, and diagnostic filter
  in the plugin/host boundary; classify each as preserve, repair, or narrowly
  suppress only with a documented reason.
- [x] Remove empty catches and silent failure returns from production plugin
  and host paths, or replace them with bounded structured diagnostics and an
  explicit result/failure state.
- [x] Ensure unavailable optional hardware/services are represented as an
  explicit non-error state with a reason and lifecycle evidence, rather than
  hiding a failed construction or probe behind a generic early return.
- [x] Ensure `Loader.Error` and plugin callback failures remain observable with
  plugin ID, kind, phase, source/entry point, and bounded detail while keeping
  T02A host survivability and quarantine behavior intact.
- [x] Prohibit log filtering, blanket stderr suppression, and warning-string
  deletion as a substitute for fixing the cause. Any intentional diagnostic
  de-duplication must have a stable correlation key and its own test.
- [x] Add isolated negative tests that prove a deliberately failing plugin,
  loader, callback, IPC method, and optional-service probe emit an actionable
  diagnostic while the host and healthy plugins remain available.
- [x] Add static policy checks for silent catches, unclassified failure gates,
  and production-wide suppression patterns; keep test-harness cleanup and
  expected negative-test command handling explicitly exempt and documented.
- [x] Verify that T29 warning cleanup fixed root causes and did not merely
  suppress their output; preserve the valid single-owner IPC and safe BlueZ
  construction contracts.
- [x] Keep all validation isolated from the live workstation, installer,
  packages, user configuration, systemd/greetd state, and reboot.

Checkpoint 3 — T31 post-change evidence:

- Tests: `test_warning_observability.sh` — 4 passed, 0 failed.
- Tests: `test_plugin_survivability.sh` — 4 passed, 0 failed, including
  explicit runtime failure diagnostics and healthy-plugin continuity.
- Tests: `test_bluetooth_plugin.sh` — all contract/model/helper assertions
  passed, including the real `busctl` member-output contract.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 544 passed, 0 failed.
- Repository suite: `./tests/run.sh` — 228 passed, 0 failed.
- Runtime evidence: the disposable offscreen shell reached configuration
  load; headless `PanelWindow` warnings were environment limitations and did
  not include source-boundary or host-load failures. Read-only live IPC after
  the development reload reported Bluetooth `state=available`,
  `serviceAvailable=true`, and `adapterAvailable=true`.
- Files changed: Bluetooth probe/readiness and status reporting, bar/host
  Loader diagnostics, survivability assertions, and warning/probe tests.
- User-visible behavior changed: the Bluetooth bar widget becomes available
  when BlueZ exposes the controller; invalid plugin failures remain visible
  and contained.
- Live system scope: no installer, package, systemd/greetd state, live user
  configuration, or reboot was touched.

Exit gate: every actionable warning/error path has either a root-cause fix or
an explicit, bounded, test-covered classification; failing plugins remain
contained, diagnostics remain visible, no duplicate-handler noise is
reintroduced, and the Aurelia shell plus healthy plugins continue to load.

Dependencies: T02A, T24, T29; T30 remains independent and may not be used as a
reason to defer this observability task.

---

### T32. Establish one canonical, relocatable plugin source boundary

Execution status: COMPLETE — CP2 and CP3 passed

Scope note: an absolute local file URL is valid as an in-memory runtime URL
when derived from the active shell root. It is not valid as a persisted,
hard-coded, checkout-specific, or inconsistently encoded source contract. This
task replaces the scattered URL construction paths with one canonical resolver
for manifest entry points and local file-backed media/asset paths. Relative
manifest entry points remain the source of truth; absolute URLs are generated
only at the final Loader/Image/Media boundary.

Non-negotiable identity and placement invariant: T32 must not rename, move, or
re-home the repository, `aurelia-shell`, any plugin directory, any manifest ID,
any manifest entry-point name, or any existing source file. Runtime resolution
must derive the active shell root and each manifest-owned plugin root from the
current execution context (`AURELIA_SHELL_ROOT`, `Qt.resolvedUrl()`, and the
validated manifest source directory as applicable), never from a developer's
checkout path or a fixed repository placement. A source-resolution failure may
quarantine only the affected plugin entry point; it must never make the
Aurelia shell, bar host, or healthy plugins unusable.

Checkpoint 2 — T32 pre-change boundary:

- Allowed production scope: a shared source/path resolver, the manifest
  registry's entry-point URL seam, existing repeated file-URL builders, and
  narrow Loader/Image/Media call sites required to consume that resolver.
- Allowed test scope: resolver unit tests, isolated QML loader fixtures,
  manifest/catalog/path safety tests, affected plugin tests, the Aurelia
  runner, and this tracker.
- Compatibility boundary: preserve every manifest ID, relative entry point,
  plugin source directory, bar/panel/overlay/menu/service lifecycle, local
  image/video behavior, icon behavior, user configuration format, and all
  Aurelia design language.
- Source safety boundary: reject empty/non-absolute roots, unsafe relative
  entry points, traversal, malformed file URLs, unsupported schemes, and paths
  escaping the declared plugin root; do not trust a source string merely
  because it begins with `file://`.
- Relocation boundary: tests must use at least two distinct temporary roots,
  including spaces and non-ASCII path segments, and prove no source or config
  contains a developer-specific `/home/user/Projects/...` path.
- Persisted/live-state impact: no production writes; tests use disposable
  temporary trees only and must not restart the live shell or alter system
  state.
- Rollback: revert only T32-owned resolver/call-site/test/tracker changes if
  CP3 fails; preserve T31's diagnostics and all prior parity work.

CP2 status: `[x]` source contract, test boundary, relocation/safety boundary,
compatibility boundary, and rollback path recorded before implementation edits.

- [x] Inventory every production source URL/path producer and classify it as
  manifest entry point, repository-relative resource, user-selected local
  file, icon URI, or external/unsupported scheme.
- [x] Add one canonical resolver with explicit path-to-file-URL and
  file-URL-to-path behavior, correct percent encoding, absolute-root checks,
  and safe descendant validation.
- [x] Route registry entry points and every repeated production file-URL
  builder through the canonical resolver; keep `Qt.resolvedUrl()` for local
  QML resources where it already provides the correct relative boundary.
- [x] Ensure manifests and persisted shell state store only relative entry
  points or approved user paths, never a developer checkout URL.
- [x] Preserve all repository/plugin names and placements exactly; prove the
  resolver works when the unchanged tree is executed from alternate temporary
  roots and when the active shell root is supplied dynamically.
- [x] Ensure third-party source paths remain detached/diagnostic-only and do
  not become an authority escalation through the resolver.
- [x] Add negative tests for traversal, root escape, malformed encoding,
  unsupported schemes, relative roots, symlinked/ambiguous source roots, and
  missing entry points.
- [x] Add relocation tests for spaces, Unicode, `#`, `?`, `%`, and repeated
  separators without changing the resolved filesystem path.
- [x] Add isolated runtime tests proving representative bar, panel, overlay,
  menu, service, image, and media loaders still resolve and healthy plugins
  remain available when one source is invalid.
- [x] Add a static check preventing hard-coded developer checkout paths and
  ad-hoc production `"file://" + path` construction outside the resolver.
- [x] Keep all validation isolated from the live workstation, installer,
  packages, user configuration, systemd/greetd state, and reboot.

Checkpoint 3 — T32 post-change evidence:

- Tests: `test_source_boundary.sh` — 7 passed, 0 failed, covering the
  descriptor, path/URL round trip, invalid authority/traversal, two relocated
  roots with spaces/Unicode, and real `PluginRegistry` descriptor output.
- Static result: repository contains `0` literal forbidden local file-URL
  prefixes and `0` hard-coded developer checkout paths in production.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 544 passed, 0 failed.
- Repository suite: `./tests/run.sh` — 228 passed, 0 failed.
- Syntax: repository-wide `bash -n` — 236 shell scripts passed.
- ShellCheck: all changed Aurelia test scripts passed; pre-existing unrelated
  findings remain outside T32 in `modules/desktop.sh`.
- Runtime evidence: the unchanged component tree loaded successfully from two
  dynamically selected temporary roots, and the real registry emitted a
  descriptor whose relative entry point and decoded source path remained
  correct.
- Files changed: host-owned `PluginSourceResolver`, source/path primitives,
  registry/host/bar descriptor consumers, local resource producers, tests,
  and source-boundary documentation.
- User-visible behavior changed: no naming, placement, manifest, design, or
  feature behavior changed; only source resolution and failure diagnostics
  were hardened.
- Live system scope: no installer, package, systemd/greetd state, live user
  configuration, or reboot was touched.

Exit gate: every production dynamic source path has one reviewed resolver or a
documented native `Qt.resolvedUrl()` boundary; source URLs are relocatable and
safe, persisted state remains path-neutral, invalid sources produce visible
diagnostics, and the shell plus healthy plugins remain usable.

Dependencies: T31, T03, T04, T06, T10, T14, T24.

---

### T33. Repair shared anchored-surface coordinate mapping (never suppress the warning)

Execution status: COMPLETE — CP2 and CP3 passed; initial directional candidate rejected and replaced

Observed failure: `AureliaToolTip.qml` reports a `TypeError` at its anchor
calculation because it calls `mapFromItem` on `anchorWindow.contentItem`.
The live receiver is a `QQuickFocusScope` supplied by the window and does not
expose that function. `AureliaPopupCard.qml` contains the same invalid mapping
direction and would fail when that shared surface is anchored.

Root-cause contract: coordinate conversion must be initiated by the actual
Quickshell's window interface owns the conversion boundary: use the
`anchorWindow.mapFromItem(sourceItem, x, y)` overload exposed by the
`PanelWindow`/`PopupWindow` interface. Do not pass the window's
`contentItem` through JavaScript into `Item.mapToItem`; the native
`QQuickFocusScope` content object is not accepted by that C++ pointer
conversion path in the live runtime. The implementation must not filter,
redirect, or hide the QML warning stream. Invalid non-`Item` inputs, if
reachable, must remain explicitly observable with a bounded diagnostic and
must not take down the shell or healthy plugins.

Validation finding after the initial candidate (2026-09-13): the user-provided
runtime trace showed `Could not convert argument 0 ... to const QQuickItem*`
at the candidate `target.mapToItem(anchorWindow.contentItem, ...)` call. The
focused fixture passed because it used a normal declarative `FocusScope`, not
the actual Quickshell window-interface content object. The candidate is not a
valid fix and has not been committed.

Additional shared call sites found before correction: `AureliaKeyboardPanel`
and `NotificationPopupSurface` also pass `anchorWindow.contentItem` into
`Item.mapToItem`. They are part of the same native argument-boundary defect
and must use the window-owned conversion as well. The unrelated
`settingsFlickable.contentItem` call in Keybindings maps to a normal QtQuick
item and remains outside this task.

Non-negotiable identity and behavior invariant: T33 must not rename, move, or
re-home the repository, `aurelia-shell`, either shared UI file, any plugin
directory, any manifest ID, any entry point, or any existing feature. It may
only correct the coordinate-conversion receiver/direction and add regression
coverage. Tooltip/pop-up delay, visibility, clamping for top/bottom/left/right
bars, popup ownership, dimensions, theme tokens, keyboard behavior, and all
existing plugin behavior must remain unchanged.

Checkpoint 2 — T33 pre-change boundary:

- Allowed production scope: `ui/AureliaToolTip.qml`,
  `ui/AureliaPopupCard.qml`, `ui/AureliaKeyboardPanel.qml`, and
  `plugins/aurelia.notifications/ui/NotificationPopupSurface.qml`, limited to
  their anchored coordinate-conversion logic and an explicit invalid-input
  diagnostic if required.
- Allowed test scope: the affected shared-surface tests, a disposable mapping
  fixture, the Aurelia runner if registration is needed, and this tracker.
- Compatibility boundary: preserve every existing source path, component
  name, plugin manifest, bar/panel/overlay/menu/service lifecycle, and Aurelia
  design-language token.
- Warning boundary: fix the invalid API receiver; do not add log filters,
  blanket catches, warning-string exclusions, or stderr suppression.
- Survivability boundary: one invalid tooltip/pop-up anchor may not prevent
  the resident host, the bar, or healthy plugins from loading.
- Persisted/live-state impact: none; use only repository files and disposable
  isolated fixtures. Do not restart the live shell or alter system state.
- Rollback: revert only T33-owned shared-surface/test/tracker changes if CP3
  fails; preserve T31/T32 commits and all unrelated user-owned work.

CP2 status: `[x]` baseline, contract, test boundary, impact boundary, and
rollback path recorded before implementation edits.

Baseline evidence:

- Starting branch/HEAD: `installer-resilience`,
  `7bb8cd75f049b70c4491a12d58cacecfc79c0994`.
- Tracker-only CP2 checkpoint: `ae150fc` (`chore(checkpoint): prepare
  anchored surface mapping fix`).
- `git status --short --branch`: clean; branch is ahead of its configured
  remote by six commits.
- Focused baseline: `bash -c 'source aurelia-shell/tests/test_helper.sh; run_suite aurelia-shell/tests/test_notification_plugins.sh; print_test_summary'` — 13 passed, 0 failed.
- Pre-change source audit: two production `mapFromItem` calls used the window
  `contentItem` as receiver; no tooltip-specific runtime regression fixture
  existed.
- Correction state: the first uncommitted candidate used
  `target.mapToItem(window.contentItem, ...)`; the user-provided runtime log
  rejected that candidate at the native argument boundary. The candidate
  remains uncommitted and is being replaced within this same T33 scope.
- Correction boundary extension: the two additional production call sites
  above were identified by read-only source inventory and are approved for
  the same window-interface correction before their files are edited.

Checkpoint requirement: satisfied; no implementation file was edited for T33
before the tracker-only CP2 commit.

- [x] Correlate the user-provided warnings to the invalid window-content
  receiver and record the root cause without suppressing its diagnostic.
- [x] Change all four shared anchored surfaces to use the Quickshell window
  interface's source-Item `mapFromItem(...)` conversion, retaining all four
  bar orientations and existing clamping.
- [x] Add negative static assertions that reject both invalid mapping forms
  across all four surfaces and a runtime fixture exercising the actual
  Quickshell window-interface mapping.
- [x] Add a focused regression assertion that the warning is not removed by a
  filter, catch, stderr redirect, or blanket diagnostic policy.
- [x] Verify invalid anchor inputs remain bounded and observable while healthy
  shell/plugin loading is unaffected.
- [x] Run the focused, affected, and full Aurelia tests plus the repository
  suite; run repository-wide shell syntax checks and ShellCheck when already
  available.
- [x] Review the final diff for name/placement changes, design drift, source
  path changes, user-state mutation, and warning suppression.
- [x] Record CP3 evidence, commit the coherent T33 change, and update the gap
  matrix only after every gate passes.

Superseded validation attempt — not completion evidence:

- The first candidate changed the initial two surfaces to source-Item
  `mapToItem` with `contentItem` as its target. The focused suite reported 4
  passed, and the broader Aurelia suite reported 548 passed, but the
  user-provided live trace demonstrated that the real Quickshell content
  object fails the C++ argument conversion. No T33 implementation commit was
  created.
- The additional `AureliaKeyboardPanel` and notification call sites were then
  found by static inventory before correction; they were not covered by the
  initial candidate's focused fixture.
- The candidate tests remain useful only as evidence that a generic
  declarative `FocusScope` is insufficient to model this runtime boundary.

CP3 status: `[ ]` superseded; a new actual-window-interface fixture and
window-owned mapping implementation are required.

Checkpoint 3 — T33 post-change evidence:

- Focused T33 suite: `test_tooltip_geometry.sh` — 4 passed, 0 failed. The
  default offscreen run explicitly classified the unavailable `PanelWindow`
  backend as skipped; it did not filter a QML warning.
- Affected notification/tooltip suite: `test_notification_plugins.sh` — 13
  passed, 0 failed.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 548 passed, 0 failed.
- Repository suite: `./tests/run.sh` — 228 passed, 0 failed.
- Syntax: repository-wide `bash -n` — 237 shell scripts passed.
- ShellCheck: all T33-owned shell scripts passed with zero findings. The
  repository-wide run retains the previously recorded unrelated findings
  outside T33; no unrelated source was changed.
- Static source audit: all four affected production surfaces now use the
  Quickshell window-owned `mapFromItem` boundary; none passes the window
  `contentItem` into `Item.mapToItem`, and no old window-content receiver
  remains.
- Isolated runtime evidence: the fixture loaded both real shared popup QML
  components and successfully mapped a source `Item` to a declarative
  `QQuickFocusScope` with finite expected coordinates. Its actual
  `PanelWindow` branch is ready for a real Wayland run but is skipped by the
  repository's offscreen environment because no PanelWindow backend is loaded.
  The optional real-Wayland smoke was not run because live visual validation
  remains separately gated.
- Survivability evidence: the full host-survivability fixture remained green;
  invalid plugin/runtime failures remain contained and healthy host/plugin
  loading remains available.
- Files changed: `ui/AureliaToolTip.qml`, `ui/AureliaPopupCard.qml`,
  `ui/AureliaKeyboardPanel.qml`,
  `plugins/aurelia.notifications/ui/NotificationPopupSurface.qml`, the T33
  geometry fixture/test, the affected notification contract assertion, the
  Aurelia test runner, and this tracker.
- User-visible behavior changed: yes; valid tooltip, popup, keyboard-panel,
  and notification-overlay anchors no longer pass the incompatible window
  content object through the JavaScript-to-C++ mapping boundary. Invalid
  window interfaces remain explicitly observable and bounded.
- Existing Aurelia feature impact: no names, placements, manifests, entry
  points, dimensions, theme tokens, or feature behavior were changed; all
  affected and full preservation suites passed.
- Rollback/migration evidence: no persisted state or migration changed; the
  task is limited to shared coordinate boundaries and isolated tests.
- Live system scope: no installer, packages, live user configuration,
  systemd/greetd state, live shell restart, or reboot was used.

CP3 status: `[x]` completed for repository/static/isolated evidence; live
Wayland visual confirmation remains explicitly unverified and separately
authorized.

Exit gate: the exact tooltip warning is eliminated by correcting the API
receiver, the duplicate popup-card defect is corrected, no diagnostic is
suppressed, all placement behavior remains intact, and isolated tests prove
the shell plus healthy plugins remain usable when an anchor is invalid.

Dependencies: T31, T32; T30 remains independent and must not defer this fix.

---

### T34. Preserve Bluetooth scan results through discovery refreshes

Execution status: NOT STARTED — issue recorded; implementation and CP2 not started

Observed behavior: after the Bluetooth bar widget discovers a device, the
same device is not visible again in the list on a later refresh/reopen (exact
timing—while the panel remains open versus after discovery stops—still needs
to be pinned down).

Read-only audit finding: Aurelia's Bluetooth `Model.js` is functionally the
same as Omarchy's reference model. Both classify unpaired devices as
`discovered`, expose that section only while `adapter.discovering` is true,
and omit devices whose `deviceName`/`name` is empty, address-like, or UUID-like.
Aurelia's `BluetoothPanel.qml` repeats the discovery-state visibility gate in
`sectionVisible()` and `scrollRows`. BlueZ may also remove transient
discovery objects when a discovery session ends. This task must first
distinguish intentional Omarchy transient behavior from an Aurelia refresh or
identity bug before changing the model.

Parity/feature contract: retain Omarchy's connected/paired/discovered
classification and primitives-only row snapshots, while ensuring a named
device discovered during an active bar-widget session is not lost merely due
to a model refresh. Any retained row must remain address-identified,
de-duplicated when it becomes paired/connected, and must not invoke an action
against a destroyed BlueZ object. No persistent device database or BlueZ
system mutation may be introduced without a separately reviewed requirement.

Checkpoint requirement: create a CP2 tracker entry before touching
`plugins/aurelia.bluetooth/Model.js`, `BluetoothPanel.qml`,
`BluetoothBarWidget.qml`, Bluetooth tests, or related production files.

- [ ] Capture the exact disappearance sequence and determine whether the
  device is removed by BlueZ, filtered by label, hidden by discovery state, or
  lost through a non-reactive `values` binding.
- [ ] Compare the observed sequence against the pinned Omarchy reference and
  classify any intentional difference before implementation.
- [ ] Add isolated model and panel fixtures for discovery refresh, name
  arrival, address identity, paired/connected transition, removal, and
  repeated scan/reopen behavior.
- [ ] Implement the smallest host-owned/session-owned retention or refresh
  correction that preserves existing actions and no stale-object use.
- [ ] Add negative tests for duplicate rows, address-only/UUID-only labels,
  destroyed objects, and a failed discovery session; no warning suppression.
- [ ] Run Bluetooth-focused, full Aurelia, repository, syntax, and available
  ShellCheck gates before marking T34 complete.

Exit gate: the exact disappearance cause is proven, the behavior is either
aligned with Omarchy or documented as a deliberate Aurelia enhancement, named
scan results remain usable through the supported refresh boundary, and no
Bluetooth or shell failure can make the Aurelia host unusable.

Dependencies: T31, T32; T33 remains independent and must not defer this
investigation.

---

## Requested follow-up execution order

The requested Omarchy parity work is ordered below. Each task is additive or
host-owned, has mandatory tests, and must preserve the shell-survivability gate.
T34 is independent and remains tracked separately; it must not be silently
closed or used to justify changing unrelated Bluetooth behavior.

1. T35 — refresh the pinned Omarchy reference and freeze the exact requested
   Audio, Microphone, Power, bar-control, and bar-visibility contracts.
2. T36 — add the `aurelia.audio` plugin foundation and pure PipeWire/MPRIS data
   model without changing the shipped bar until the model gate passes.
3. T37 — implement the Audio panel and output bar interactions, then add Audio
   to the Aurelia default layout at the reference location.
4. T38 — add the optional Microphone bar widget with the exact mute,
   middle-button, and input-scroll semantics.
5. T39 — redesign the existing `aurelia.power` popup around the Omarchy battery,
   power-profile, and confirmation UX while preserving Aurelia's identity and
   action ownership.
6. T40 — complete the Aurelia bar configuration control plane: `use`, `reset`,
   `defaults`, `position`, `transparent`, and the already-supported placement
   and setting commands.
7. T41 — implement persistent bar hiding, `Super + Shift + Space`, and the
   Menu Bar control without killing the resident shell or its hotkeys.
8. T43 — make test outcomes truthful: count skips separately, never let a
   backend limitation mask an unrelated warning, and provide a strict no-skip
   gate.
9. T44 — correct Power panel non-visual child construction and add a real
   panel entry-point contract fixture.
10. T45 — correct the Aurelia bar hidden-state watcher for the actual
    FileView/runtime contract without suppressing diagnostics.
11. T42 — run the combined contract, failure-isolation, migration, and
    optional real-session acceptance gates; update documentation and parity
    evidence.

No task in this sequence may rename or move the repository, `aurelia-shell`, an
existing plugin, a manifest ID, an existing entry point, or a user-owned
configuration path.

---

### T35. Refresh Omarchy reference and freeze the requested capability contracts

Execution status: COMPLETE — read-only reference refresh and gap audit

Reference checkpoint:

- `/tmp/omarchy-reference` was freshly cloned from the requested upstream
  repository on `2026-09-13`.
- Reference checkout is clean on `quattro`, HEAD
  `31bd80daa4613ffdee995ac27467fce5a2990806`.
- Aurelia baseline is clean on `installer-resilience`, HEAD
  `9737256a9ab383206ddd139be19e5d5422fc3352`.

Frozen requested contracts:

- **Audio:** Omarchy ships `omarchy.audio` as a `bar-widget` with a panel
  entry point. The widget opens the Audio panel on middle-click, adjusts output
  volume on scroll, and toggles the output/input master mute on its primary
  action. The panel owns output sinks, input sources, per-application playback
  streams, default sink/source selection, output/input sliders, mute state,
  and bounded PipeWire snapshots.
- **Microphone:** Omarchy ships `omarchy.microphone` as a separate
  `bar-widget`. Primary action mutes the default source, middle-click opens
  the Audio panel, and scroll adjusts input volume. The refreshed Omarchy
  default shell layout includes Audio but does not include Microphone; Aurelia
  must preserve that default distinction unless a later explicit product
  decision changes it.
- **Power:** Omarchy's `omarchy.power` bar widget owns a battery-aware panel
  with UPower presence/state, battery progress, statistics, rotating status
  text, power-profile selection, percentage display settings, right-click
  percentage toggle, and safe confirmation for reboot/poweroff. Aurelia's
  existing `aurelia.power` ID, `PowerBarWidget.qml` entry point, action set,
  and file placement remain fixed while its popup is redesigned.
- **Bar controls:** Omarchy's bar command supports `use`, `reset`, `defaults`,
  `position top|bottom|left|right`, `transparent true|false|toggle`, and
  placement/setting operations. `defaults` restores the shipped layout;
  placement and widget settings are owned by the resident shell state rather
  than a competing direct file editor.
- **Bar hiding:** Omarchy keeps the shell alive, parks the bar off-screen,
  removes its exclusion zone, watches an XDG-state toggle, and exposes a sync
  operation for rapid flag changes. `Super + Shift + Space` toggles it, and
  the Menu Bar control provides the same operation. Panels and hotkeys remain
  usable while pixels are hidden.

Aurelia gap findings:

- No `aurelia.audio` manifest, Audio panel, output/source/stream model, or
  Audio bar widget exists. Only a Bluetooth-owned audio-output helper exists.
- No `aurelia.microphone` manifest or bar widget exists.
- `aurelia.power` currently renders only five action rows and has no UPower
  battery model, power-profile model, percentage setting, or reference panel
  information architecture.
- `aurelia-bar` currently exposes only `put`, `move`, and `set`; it lacks the
  five requested bar-level commands.
- Aurelia has an in-memory `barHidden` field and a menu item, but no persistent
  toggle state, directory watcher/sync operation, or `Super + Shift + Space`
  binding. Its current menu is a single flat Toggle Bar action rather than the
  reference Menu Bar position/transparency structure.

Evidence:

- Reference source: `shell/plugins/panels/audio/Panel.qml`,
  `shell/plugins/bar/widgets/Microphone.qml`,
  `shell/plugins/panels/power/Panel.qml`, `bin/omarchy-bar`,
  `bin/omarchy-toggle-bar`, `default/hypr/bindings/utilities.lua`, and
  `default/omarchy/omarchy-menu.jsonc`.
- Aurelia source: `plugins/aurelia.power/PowerPanel.qml`,
  `plugins/aurelia.power/PowerBarWidget.qml`, `bin/lib/aurelia-plugin/bar.sh`,
  `plugins/aurelia.menu/menu.json`, `plugins/aurelia.menu/MenuModel.qml`,
  `plugins/aurelia.bar/Bar.qml`, and
  `dotfiles/hypr/keybindings_manifest.lua`.
- No production code, live configuration, packages, services, or user data
  was changed for T35.

Dependencies: T33; T30 and T34 remain independent and must not defer this
read-only refresh.

---

### T36. Add Audio plugin foundation and safe PipeWire data model

Execution status: COMPLETE — CP2 and CP3 passed

Objective: introduce the new `aurelia.audio` `bar-widget` in the existing
Aurelia plugin architecture without enabling it in the shipped layout until
the model and host-survivability gates pass.

Checkpoint 2 — T36 pre-change boundary:

- Starting branch/HEAD: `installer-resilience`,
  `9737256a9ab383206ddd139be19e5d5422fc3352`.
- Working-tree baseline: clean after T33; no unrelated user-owned changes are
  available to stage.
- Baseline tests: `./aurelia-shell/tests/run.sh` — 548 passed, 0 failed;
  `./tests/run.sh` — 228 passed, 0 failed; repository-wide shell syntax —
  237 scripts passed; T33-owned ShellCheck checks passed.
- Allowed production scope: new `plugins/aurelia.audio/` manifest, pure
  `Model.js`, and the minimum new bar-widget/panel files required for the
  plugin contract; existing host files only where the registry contract
  requires an additive registration path.
- Allowed test scope: centralized Audio contract/model tests, disposable
  PipeWire/MPRIS fixtures, manifest matrix updates, host-survivability
  fixtures, the Aurelia runner, and this tracker. T30's plugin-local test
  directory work remains separate.
- Identity boundary: use the new Aurelia namespace IDs without renaming or
  moving any existing plugin, file, manifest, or entry point. The plugin must
  remain opt-in until T37's default-layout cutover.
- Ownership boundary: PipeWire/MPRIS own live state; the plugin owns only
  detached snapshots and UI intent. Do not add a second audio daemon, mutate
  live system services, or duplicate Bluetooth's existing audio-default
  helper ownership.
- Failure boundary: missing PipeWire/MPRIS objects, malformed node data,
  disappearing nodes, and plugin loader failures must quarantine/disable only
  the Audio surface and leave the resident host and healthy plugins available.
- Persisted/live-state impact: no production state migration or default-bar
  change in T36; tests use temporary sandboxes and mocked argv/data only.
- Rollback: remove only T36-owned new plugin/test files and additive registry
  wiring if CP3 fails; preserve existing bar, Bluetooth, power, and user state.

CP2 status: `[x]` contract, test boundary, identity/ownership boundary,
survivability boundary, baseline, and rollback path recorded before T36 code.

- [x] Add a canonical `aurelia.audio` manifest with a safe bar-widget entry
  point and reference metadata, without placing it in the shipped bar yet.
- [x] Add a pure model for PipeWire sink/source/stream classification,
  primitive snapshots, friendly labels, mute/volume bounds, and deterministic
  device/stream filtering.
- [x] Add safe live-model ownership that tracks current default sink/source,
  rejects invalid/disappearing nodes, and never feeds live QObject wrappers
  directly into incubating list delegates.
- [x] Add deterministic negative tests for missing defaults, malformed nodes,
  disappearing nodes, duplicate identities, invalid volumes, and failed
  optional MPRIS/PipeWire availability.
- [x] Add host-survivability coverage proving Audio failure cannot prevent the
  bar, resident host, Bluetooth, Power, or healthy plugins from loading.
- [x] Run focused Audio tests, full Aurelia tests, repository tests, syntax,
  and available ShellCheck before moving to T37.

Checkpoint 3 — T36 post-change evidence:

- Focused Audio foundation suite: `test_audio_plugin.sh` — 7 passed, 0
  failed, including the pure PipeWire/MPRIS model matrix and real entry-point
  fixture.
- Affected inventory suites: manifest, catalog, bar-registry, migration, and
  preservation checks passed with 23 first-party manifests and 12 bar-widget
  manifests; the shipped default bar remains unchanged and does not include
  `aurelia.audio` until T37.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 558 passed, 0 failed.
- Repository suite: `./tests/run.sh` — 228 passed, 0 failed.
- Syntax: repository-wide `bash -n` — 238 shell scripts passed.
- ShellCheck: the new T36 test and runner passed with zero findings. The
  count-only edits to existing inventory tests retain four pre-existing
  `SC2034` findings in `test_plugin_contract_matrix.sh` and
  `test_plugin_catalog.sh`; no T36-owned logic introduced a ShellCheck
  finding.
- Isolated runtime evidence: the real Audio bar entry point was exercised in
  a disposable QuickShell fixture. The offscreen environment could not load
  the nested PanelWindow backend, so that portion was explicitly classified
  as skipped; no live PipeWire mutation was attempted.
- Survivability evidence: existing host-survivability and generic manifest
  matrix tests remained green; Audio is opt-in and unavailable audio state is
  bounded to the plugin surface.
- Files changed: the new `plugins/aurelia.audio/` manifest, pure model, safe
  bar/panel foundation, Audio foundation fixture/test, Aurelia runner,
  centralized inventory/count fixtures, and this tracker.
- User-visible behavior changed: no default-bar behavior changed in T36;
  Audio becomes a validated opt-in capability pending T37.
- Existing Aurelia feature impact: existing plugin IDs, entry points, default
  layout, theme, and action ownership remain unchanged.
- Rollback/migration evidence: no persisted state migration; removing only
  T36-owned new plugin/test files restores the pre-T36 inventory.
- Live system scope: no installer, packages, PipeWire state, user
  configuration, systemd/greetd state, live shell restart, or reboot was
  touched.

CP3 status: `[x]` complete; T36 is closed and T37 may begin after its own
pre-change checkpoint.

Exit gate: `aurelia.audio` is a validated, opt-in, failure-contained plugin
with a pure tested model and no live-system mutation or default-layout impact.

Dependencies: T35, T02A, T31, T32.

---

### T37. Implement Audio panel and output interaction parity

Execution status: COMPLETE — corrective CP2/CP3 passed for repository,
static, and isolated evidence; post-fix real-Wayland confirmation remains
deferred

Checkpoint 2 — T37 pre-change boundary:

- Starting branch/HEAD: `installer-resilience`, `b5d65f2` (`feat(audio): add
  safe PipeWire plugin foundation`).
- Working-tree baseline: clean after T36; no unrelated user-owned changes are
  available to stage.
- Baseline tests: `./aurelia-shell/tests/run.sh` — 558 passed, 0 failed;
  `./tests/run.sh` — 228 passed, 0 failed; repository-wide shell syntax —
  238 scripts passed; T36-owned new test and runner ShellCheck checks passed.
- Allowed production scope: the existing new
  `plugins/aurelia.audio/AudioBarWidget.qml` and `AudioPanel.qml`, its pure
  `Model.js`, the canonical `config/bar-default.json` and its preservation
  fixture, plus focused Audio tests and runner registration. No existing
  plugin identity or host architecture may change.
- Interaction boundary: implement the frozen Omarchy Audio contract with
  Aurelia primitives—output/input/stream sections, default sink/source
  selection, output/input mute, bounded sliders, middle-click panel opening,
  and output scroll volume—without shell strings, optimistic state, or direct
  config mutation from QML.
- Ownership/failure boundary: PipeWire/MPRIS own live objects; Audio owns
  detached display snapshots and UI intent. A missing/default/disappearing
  node or panel Loader failure must affect only Audio and leave the resident
  shell, bar, Bluetooth, Power, and healthy plugins usable.
- Default cutover boundary: add only `aurelia.audio` to the canonical default
  right-side layout after focused tests pass; do not add `aurelia.microphone`
  in T37 because the refreshed Omarchy default does not include it.
- Persisted/live-state impact: the default layout is a repository-owned desired
  state update; no live shell restart, PipeWire mutation, package operation,
  systemd/greetd mutation, or user-state migration is allowed during tests.
- Rollback: restore only the prior default layout and T37-owned Audio UI/test
  changes if CP3 fails; keep the validated T36 plugin opt-in foundation intact.

CP2 status: `[x]` contract, test boundary, default-cutover boundary,
ownership/survivability boundary, baseline, and rollback path recorded before
T37 code.

Scope:

- Build the panel with Omarchy's output, input, and per-application stream
  sections using Aurelia's existing `AureliaKeyboardPanel`, QtQuick Controls
  `Slider`, inline row primitives, and theme tokens. No untracked or
  nonexistent shared UI type may be introduced as a shortcut.
- Audio bar behavior must match the frozen contract: middle-click opens the
  panel, scroll changes output volume in bounded steps, and the primary mute
  action changes the intended output/input mute state without optimistic state
  lies.
- Implement default sink/source selection, output/input sliders, stream mute
  and stream volume, active-player labeling, and bounded PipeWire refreshes.
- Preserve Aurelia's structured argv and privilege ownership. Reuse the
  existing `aurelia-audio-output-set-default` ownership where applicable and
  add only narrowly justified package-owned adapters.
- Add `aurelia.audio` to the canonical Aurelia default bar in the reference
  right-side position only after T36 passes. Do not add Microphone to the
  shipped default unless explicitly approved; Omarchy's refreshed default
  does not include it.

Required tests:

- [x] Static manifest/default-layout/interaction assertions.
- [x] Pure model tests for output/input/stream classification and bounds.
- [x] Isolated QML entry-point/backend-boundary tests plus interaction contract
  assertions for middle-click, scroll, mute, slider, and selection.
- [x] Default-layout migration/idempotency and host-survivability tests.
- [x] Full Aurelia/repository suites, shell syntax, and ShellCheck.

Checkpoint 3 — T37 post-change evidence:

- Focused Audio interaction suite: `test_audio_interactions.sh` — 5 passed,
  0 failed.
- Audio foundation suite: `test_audio_plugin.sh` — 7 passed, 0 failed.
- Affected default/migration/inventory suites passed; Aurelia now has 23
  first-party manifests and 12 bar-widget manifests, with `aurelia.audio`
  placed after `aurelia.network` in the canonical right-side default layout.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 563 passed, 0 failed.
- Repository suite: `./tests/run.sh` — 228 passed, 0 failed.
- Syntax: repository-wide `bash -n` — 239 shell scripts passed.
- ShellCheck: T37-owned new/changed interaction, default-layout, acceptance,
  and runner scripts passed with zero new findings. Four pre-existing
  `SC2034` findings remain in the count-only-edited inventory tests and were
  not changed.
- Isolated runtime evidence: the real Audio bar entry point and nested panel
  source were exercised in a disposable QuickShell fixture. The offscreen
  environment cannot load the PanelWindow backend, so the nested surface was
  explicitly classified as skipped; no PipeWire or live bar mutation was
  attempted. Pure interaction and volume-bound logic passed independently.
- Failure evidence: the existing generic host-survivability and manifest
  matrix remained green, and the Audio widget remains bounded when its panel
  Loader cannot construct.
- Files changed: Audio panel/widget/model, canonical default bar and
  preservation/count fixtures, Audio interaction tests, runner registration,
  and this tracker.
- User-visible behavior changed: yes; Audio is now in the default bar, its
  primary/middle action opens the panel, right action controls mute, and wheel
  input adjusts bounded output volume. Full input/source/stream controls are
  available in the panel.
- Existing Aurelia feature impact: no existing plugin ID, entry point, theme
  token, placement identity, or non-Audio feature was renamed or moved; all
  full preservation suites passed.
- Rollback/migration evidence: T37 changes only the repository-owned default
  layout and Audio surface; restoring the prior right-side list removes Audio
  without touching user state migration.
- Live system scope: no installer, packages, PipeWire state, live user
  configuration, systemd/greetd state, live shell restart, or reboot was
  touched.

CP3 status: `[x]` original repository/static/isolated gates passed; the live
catalog, warning, and icon reports were converted into corrective checkpoints
and are covered below.

Corrective checkpoint 2 — default-bar readiness:

- Starting branch/HEAD: `installer-resilience`,
  `5958e5e1e333605e2d62be63acc6c749a677afd1` (`feat(audio): add panel
  controls and default bar widget`); working tree was clean before this
  tracker-only checkpoint.
- Read-only live catalog evidence: `aurelia.audio` was discovered and enabled
  but reported `loaded=false`, `visible=false`, and `inBar=false`; the active
  bar reported ten widget slots while the repository-owned
  `config/bar-default.json` contains Audio after Network.
- Root-cause boundary: `BarDefaultConfig.qml` still had the pre-T37 in-memory
  fallback and `ShellConfig` did not resynchronize an implicit default bar
  after the asynchronous default `FileView` completed. This affects a missing
  user `bar` document only; an explicit user-owned bar must remain untouched.
- Allowed files: `services/BarDefaultConfig.qml`, the narrowly scoped
  default-readiness connection in `services/ShellConfig.qml`, the existing
  bar-default fixture, its focused test, and this tracker. No plugin identity,
  Audio controls, user state, or host lifecycle may change.
- Required regression: exercise `ShellConfig` with a missing explicit bar,
  wait for the canonical default document to become ready, and assert the
  active in-memory right layout contains Audio; also assert an explicit
  user-owned bar is not overwritten.
- Persisted/live-state impact: no user-state write, PipeWire mutation,
  package operation, live shell restart, systemd/greetd change, or reboot is
  allowed. The fix must only repair in-memory default readiness.
- Rollback: revert only the fallback, readiness connection, fixture/test, and
  tracker changes if the regression test or full gates fail; retain T36 and
  the Audio panel implementation.

Corrective CP2 status: `[x]` baseline and exact ownership/rollback boundary
recorded before source edits.

Corrective checkpoint 2b — Audio panel transient cursor state:

- Runtime evidence: a real source-checkout restart emitted two unsuppressed
  warnings from `AudioPanel.qml:298`: `visibleSections` was transiently
  undefined while PipeWire-backed panel properties were settling, and
  `clampCursor()` dereferenced `.length` during that signal path.
- Working-tree boundary: only the T37 default-readiness correction, its
  fixtures/tests, and this tracker are currently uncommitted; no unrelated
  user change is available to stage.
- Allowed files: `plugins/aurelia.audio/AudioPanel.qml`, the existing Audio
  interaction test, and this tracker. The fix must be a bounded defensive
  handling of the transient section list, not warning suppression or a change
  to PipeWire ownership.
- Required regression: the Audio interaction contract must assert the
  cursor-clamp path handles an unavailable section list without dereferencing
  undefined state; the live warning must disappear after a controlled shell
  restart authorized by the user.
- Persisted/live-state impact: no PipeWire state, user configuration,
  package, systemd/greetd state, or reboot change is permitted. A shell
  restart is validation only and must not be performed by repository tests.
- Rollback: revert only the Audio cursor guard and its focused assertion if
  the warning contract or full gates fail; retain the default-readiness repair.

Corrective CP2b status: `[x]` warning evidence, ownership boundary, test
contract, and rollback path recorded before the Audio panel edit.

Corrective checkpoint 2b follow-up — first guard insufficient:

- Post-edit hot-reload evidence: the live shell still emitted
  `AudioPanel.qml:298: TypeError: Value is undefined and could not be
  converted to an object` after the initial `visibleSections || []` guard.
  The first guard is therefore not accepted as the final fix.
- Required correction: avoid dereferencing the reactive section property in
  the transient callback path; compute a fresh, always-array section list from
  individually validated display lists and use a bounded list-length helper
  for every cursor section decision.
- Allowed files remain `plugins/aurelia.audio/AudioPanel.qml`, the focused
  Audio interaction test, and this tracker. No warning suppression, PipeWire
  ownership change, or unrelated plugin edit is allowed.
- Required regression: static and isolated contract checks must prove the
  safe list-length/section-list boundary is present; a subsequent user
  restart/hot-reload must show no AudioPanel warning.

Corrective CP2b follow-up status: `[x]` the initial defensive patch was
rejected by live evidence; the stronger list-boundary correction passes the
focused Audio suite and full repository gates. Post-fix real-Wayland restart
remains pending.

Corrective checkpoint 2c — Audio bar icon parity:

- Runtime/user evidence: after the default-bar readiness repair, the Audio
  widget is present but its bar icon is visually wrong. Source comparison
  shows Omarchy's bar uses a volume-sensitive `outputIcon()` contract
  (mute/low/medium/high/headphones), while Aurelia currently routes the
  static device `sinkGlyph()` to the bar affordance.
- Working-tree boundary: only T37 corrective changes and this tracker are
  currently uncommitted; no unrelated user change is available to stage.
- Allowed files: the Audio pure model, Audio bar/panel consumers, the focused
  Audio interaction test, and this tracker. Existing Aurelia icon rendering,
  font/theme ownership, plugin identity, and PipeWire ownership must remain
  unchanged.
- Required regression: pure model assertions must cover every output-icon
  band and headphone/mute precedence; the bar and Audio hero must consume the
  canonical model result rather than a duplicated glyph ladder.
- Persisted/live-state impact: no PipeWire mutation, user configuration,
  package, systemd/greetd state, or reboot change is permitted. Visual
  confirmation remains a separate real-Wayland validation step.
- Rollback: revert only the canonical output-icon model/consumers and their
  focused assertions if the icon contract or full gates fail; retain the
  default-readiness and cursor-warning corrections.

Corrective CP2c status: `[x]` reference contract, exact scope, test boundary,
and rollback path recorded before icon edits.

Corrective checkpoint 3 — final T37 evidence:

- Default-readiness regression: `test_bar_default_config.sh` — 3 passed,
  0 failed. This includes the asynchronous missing-bar path that previously
  omitted Audio and the explicit user-layout preservation guard.
- Existing bar-operation regression: `test_bar_operations.sh` — 9 passed,
  0 failed; the catalog/config signal boundary remains convergent.
- Audio interaction suite: `test_audio_interactions.sh` — 7 passed, 0
  failed. It covers the transient cursor guard and the canonical low,
  medium, high, muted, missing-output, and headphone glyph results.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 565 passed, 0 failed.
- Repository functional suite: `./tests/run.sh` — 228 passed, 0 failed.
  The repository ShellCheck stage still reports pre-existing findings in
  unrelated installer/test files; the two changed shell test files pass
  ShellCheck with zero findings.
- Syntax: repository-wide `bash -n` — 239 shell scripts passed.
- Diff hygiene: `git diff --check` passed; no generated files or test
  artifacts remain in the repository.
- Default state fix: the in-memory fallback now matches the canonical JSON,
  and `ShellConfig` refreshes only default-backed state after asynchronous
  readiness; explicit user-owned bar layouts are not replaced.
- Warning fix: cursor navigation now computes an always-array
  `visibleSectionList()` through `safeListLength()` before any length/index
  operation, covering transient QML initialization state. No warning filter,
  `|| true` diagnostic suppression, or log downgrade was added.
- Icon fix: the pure model now owns the exact Omarchy volume-sensitive output
  glyph ladder; both the bar affordance and Audio hero consume it while
  device-row glyphs remain separate.
- Last live evidence: the user-provided restart before these final edits
  emitted the AudioPanel warning and showed the old icon. A post-fix
  source-checkout restart has not been performed by the agent; visual
  confirmation remains explicitly separate from these passing tests.
- Files changed: Audio model/bar/panel, default state services, focused Audio
  and bar fixtures/tests, the catalog-cycle fixture, and this tracker.
- User-visible behavior changed: yes; Audio is available through the shipped
  default bar with a dynamic reference-matched icon and the previous default
  readiness/cursor warning paths are repaired.
- Existing Aurelia feature impact: no plugin IDs, entry points, user-owned
  layout, theme ownership, or non-Audio feature was renamed, moved, or
  overwritten; full preservation gates passed.
- Rollback/migration evidence: no persisted user-state migration or PipeWire
  mutation was performed; reverting this T37 repair restores the prior
  default-readiness behavior without touching user data.

Corrective CP3 status: `[x]` repository/static/isolated acceptance complete;
real-Wayland visual confirmation remains pending and is not claimed.


Exit gate: Audio is present in the shipped Aurelia bar with Omarchy's control
semantics, no feature regression, no shell-wide failure from unavailable audio,
and mandatory isolated tests green.

Dependencies: T36, T02A, T24, T27, T31.

---

### T38. Add Microphone bar widget and input-control parity

Execution status: COMPLETE — CP2 and CP3 passed for repository, static, and
isolated evidence; live PipeWire/Wayland confirmation remains deferred

Checkpoint 2 — T38 pre-change boundary:

- Starting branch/HEAD: `installer-resilience`,
  `b27ce23d8883f915d6f9e41c4a8cc29ca66da1f9` (`fix(audio): close default
  readiness and icon warning gaps`); the working tree is clean and contains
  no unrelated user changes.
- Reference contract frozen from `/tmp/omarchy-reference`: manifest id
  `omarchy.microphone`, kind `bar-widget`, entry `Microphone.qml`, category
  `Audio`, `allowMultiple=false`, and no shipped default-bar placement.
  Aurelia will preserve its own `aurelia.microphone` identity and dynamic
  source-root resolution without adding a default placement.
- Interaction contract: read `Pipewire.defaultAudioSource`; missing source
  means hidden/zero-width and muted-by-default state; source mute is the
  primary/right action; middle-click summons `aurelia.audio` through the
  resident host API; wheel input changes source volume by bounded `0.05`
  steps; active non-sink capture streams determine `inUse` only while the
  source is not muted.
- Ownership boundary: PipeWire owns the live source/node objects; the
  Microphone widget owns only its presentation and one source retention
  boundary matching the reference. The existing Audio plugin remains the
  canonical pure-model owner for shared microphone classification helpers;
  no second audio service, competing IPC owner, backend, or shell command is
  allowed.
- Failure/survivability boundary: transiently absent or malformed source/node
  lists must produce safe empty state and affect only Microphone. A manifest,
  entry-point, PipeWire binding, tooltip, or middle-click failure must be
  quarantinable without preventing the resident bar, Audio, Bluetooth, Power,
  Command Center, or healthy plugins from loading.
- Allowed implementation scope: new
  `plugins/aurelia.microphone/manifest.json` and
  `MicrophoneBarWidget.qml`; narrowly scoped pure helper additions to
  `plugins/aurelia.audio/Model.js`; Microphone-focused tests/fixture and
  runner registration; first-party inventory/preservation/count fixtures;
  and this tracker. Do not change `config/bar-default.json`, existing plugin
  ids/entry points, or live/user configuration.
- Baseline evidence: full Aurelia suite — 565 passed, 0 failed; repository
  suite — 228 passed, 0 failed; repository-wide shell syntax — 239 scripts
  passed; changed test scripts ShellCheck-clean; T34 Bluetooth retention,
  T39 Power, T40 bar CLI, T41 bar hiding, and T42 final acceptance remain
  untouched.
- Persisted/live-state impact: Microphone remains opt-in; tests use temporary
  sandboxes and mocks only. No PipeWire mutation, shell restart, package or
  installer operation, user-state write, systemd/greetd change, or reboot is
  permitted during implementation validation.
- Rollback: remove only the new Microphone source tree, pure helper additions,
  focused tests/count fixtures, and tracker changes if CP3 fails; the default
  bar and existing Audio implementation remain intact.

CP2 status: `[x]` contract, exact scope, optional-default boundary,
survivability boundary, baseline, and rollback path recorded before source
edits.

Scope:

- Add a separate `aurelia.microphone` bar-widget manifest and unchanged,
  dynamically resolved entry-point placement under the Aurelia plugin tree.
- Read the default PipeWire source through the shared Audio contract; show
  mute/live/in-use state, mute the microphone on the primary action, open
  `aurelia.audio` on middle-click, and adjust input volume on scroll with the
  same bounded step semantics as the reference.
- Keep the widget optional in the default layout to match the refreshed
  Omarchy default while making explicit enablement/configuration reliable.
- Do not create a second competing PipeWire tracker, audio service, or IPC
  owner. A missing source must hide/degrade only this widget and never break
  the shell.

Required tests:

- [x] Manifest/catalog/default-optional and bar-widget lifecycle assertions.
- [x] Pure input mute/volume/in-use model tests, including missing-source and
  disappearing-source cases.
- [x] Isolated QML interaction tests for primary mute, middle Audio summon,
  scroll bounds, tooltip/state text, and repeated refreshes.
- [x] Host-survivability and full Aurelia/repository/syntax/ShellCheck gates.

Checkpoint 3 — T38 post-change evidence:

- Microphone-focused suite: `test_microphone_plugin.sh` — 7 passed, 0
  failed. The isolated QML fixture loaded the production widget twice, tested
  missing-source degradation, then injected notifying fake QML source/nodes
  and drove the production click/wheel handlers for mute, Audio summon,
  in-use state/text, and input bounds. The sandbox PipeWire context was
  unavailable and was explicitly classified as an environment condition; no
  live audio state was changed.
- Inventory/preservation/registry/catalog/migration/manifest affected suites:
  146 passed, 0 failed.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 575 passed, 0 failed.
- Repository functional suite: `./tests/run.sh` — 228 passed, 0 failed.
- Syntax: repository-wide `bash -n` — 240 shell scripts passed.
- ShellCheck: new/changed Microphone, runner, and inventory test scripts
  introduced no new findings. Four pre-existing `SC2034` findings remain in
  `test_plugin_contract_matrix.sh` and `test_plugin_catalog.sh`.
- Diff hygiene: `git diff --check` passed; no generated files or test
  artifacts remain in the repository.
- Optional-default evidence: `aurelia.microphone` is discoverable, enabled
  by the first-party policy, and absent from `config/bar-default.json`; the
  canonical Audio placement is unchanged.
- Failure evidence: the generic host-survivability matrix remains green; a
  missing source/list, unavailable PipeWire context, or Microphone entry-point
  failure cannot prevent the resident host or existing bar widgets from
  loading.
- Architecture evidence: the widget uses the resident host `summon` API for
  middle-click, shares pure capture helpers from Audio, retains only its live
  source boundary, and owns no shell command, backend, or second IPC target.
- Files changed: the new Microphone manifest/widget/fixture/test, shared Audio
  pure helpers, centralized inventory/count/preservation fixtures, runner
  registration, and this tracker. `config/bar-default.json` was not changed.
- User-visible behavior changed: only when explicitly enabled/configured;
  Microphone remains optional by default and follows the reference mute/live/
  in-use, Audio-summon, and input-scroll interactions.
- Existing Aurelia feature impact: no existing plugin ID, entry point, default
  placement, theme ownership, user configuration, or live state was renamed,
  moved, or overwritten; preservation gates passed.
- Rollback/migration evidence: no persisted state migration, PipeWire
  mutation, package operation, systemd/greetd change, shell restart, or reboot
  occurred; removing the new optional source tree and inventory additions
  restores the T37 behavior.

CP3 status: `[x]` repository/static/isolated acceptance complete; real
PipeWire/Wayland visual confirmation remains pending and is not claimed.

Exit gate: Microphone has the exact reference interaction contract, shares one
safe Audio state boundary, remains optional by default, and cannot make the
bar or resident host unusable.

Dependencies: T37, T02A, T31.

---

### T39. Redesign existing Power popup to Omarchy battery/profile UX

Execution status: COMPLETE — CP2 and CP3 passed for repository, static, and
isolated evidence; live UPower/Wayland confirmation remains deferred

Checkpoint 2 — T39 pre-change boundary:

- Starting branch/HEAD: `installer-resilience`,
  `dd3ec66bca9ebd912f88b1886409972f0d779acf` (`docs(tracker): record
  microphone completion`); the working tree is clean and has no unrelated
  user changes.
- Reference contract frozen from `/tmp/omarchy-reference`: retain the
  `bar-widget` role and `Power` identity, show the UPower-backed battery hero,
  percentage, progress, status/statistics, and power-profile selector, and
  keep `showPercentage` as an inline setting toggled by right-click. No
  battery must produce a safe hidden/zero-width affordance.
- Existing Aurelia invariants: preserve `aurelia.power`,
  `PowerBarWidget.qml`, `PowerPanel.qml`, manifest placement, anchored popup
  ownership, Aurelia theme/design tokens, and lock/logout/suspend/reboot/
  shutdown confirmation/actions. No action may execute during tests.
- Ownership boundary: UPower owns live battery truth; `powerprofilesctl`
  remains a user-level structured-argv profile owner; the Power panel owns
  only presentation, bounded snapshots, and action intent. System statistics
  must use bounded user-level reads. QML must not gain shell strings,
  privilege escalation, or a second power service.
- Failure/survivability boundary: missing UPower/battery, malformed or empty
  profile/stat output, a disappearing device, profile failure, or action
  failure must affect only Power and leave the resident host, bar, Audio,
  Microphone, Bluetooth, Command Center, and healthy plugins usable.
- Allowed implementation scope: `plugins/aurelia.power/PowerPanel.qml`,
  `PowerBarWidget.qml`, the new pure `Model.js`, Power-focused test/fixture
  files, runner registration, the existing Power assertions, and this
  tracker. Do not rename/move the plugin, change `config/bar-default.json`,
  alter other plugin actions, or modify live/user state.
- Baseline evidence: full Aurelia suite — 575 passed, 0 failed; repository
  suite — 228 passed, 0 failed; repository-wide shell syntax — 240 scripts
  passed; changed test scripts ShellCheck-clean; T30, T34, T40, T41, and T42
  remain untouched.
- Persisted/live-state impact: `showPercentage` may persist only through the
  existing resident `ShellConfig` owner when explicitly used by a user; tests
  must use isolated settings and action sinks. No power-profile change,
  system action, package/installer operation, shell restart, systemd/greetd
  change, or reboot is permitted during implementation validation.
- Rollback: restore the previous Power QML and remove the new model/tests if
  CP3 fails; preserve the T38 Microphone commit and all existing Power
  identity/action files.

CP2 status: `[x]` reference UX, identity/action preservation, ownership,
survivability, baseline, exact scope, and rollback path recorded before source
edits.

Non-negotiable identity invariant: retain `aurelia.power`,
`PowerBarWidget.qml`, `PowerPanel.qml`, manifest placement, existing lock,
logout, suspend, reboot, shutdown actions, and Aurelia theme/design-language
ownership. This is a controlled internal UI/data redesign, not a rename or
re-home.

Scope:

- Add a pure power model based on the refreshed Omarchy `Model.js` contract for
  battery fraction, state, charging/threshold logic, profile parsing, profile
  selection, icon selection, and bounded text labels.
- Integrate Quickshell UPower presence/state safely. No battery must produce a
  non-crashing unavailable/hidden widget; it must not prevent other bar
  widgets or the shell from loading.
- Redesign the popup around the reference information hierarchy: battery hero
  and percentage, progress bar, status/statistics, power-profile selector,
  compact rows, cursor/focus behavior, and dynamic content-fitted geometry.
- Preserve Aurelia colors, typography, spacing, icon primitive, popup ownership,
  confirmation semantics, bounded actions, and no live system mutation during
  tests.
- Add a `showPercentage` setting with safe persistence and right-click toggle
  semantics matching the reference; route settings through the existing host
  mutation owner.
- Keep power actions structured and observable. Failed profile/action commands
  must report bounded diagnostics and never crash or block the shell.

Required tests:

- [x] Pure model matrix for absent battery, charging, discharging, full,
  threshold, malformed profile output, and profile-index bounds.
- [x] Static geometry/design assertions proving the old five-row-only popup is
  gone and the required hero/progress/stats/profile owners exist.
- [x] Isolated QML fixture for popup open/close, confirmation, profile
  selection, percentage toggle, absent battery, and action-failure isolation.
- [x] Preservation tests for all existing power actions and default bar slot.
- [x] Full Aurelia/repository/syntax/ShellCheck gates; optional visual smoke
  remains separately authorized.

Checkpoint 3 — T39 post-change evidence:

- Power-focused suite: `test_power_plugin.sh` — 8 passed, 0 failed. The pure
  model covers absent, charging, discharging, fully charged, threshold/
  holding, malformed profile output, duration formatting, and profile bounds.
  The isolated fixture drives the real Power bar widget with a notifying fake
  panel for open/close, right-click percentage toggle, and no-battery hiding;
  no power command is executed.
- Existing bar-widget preservation suite: `test_bar_widgets.sh` — 37 passed,
  0 failed. It confirms `aurelia.power`, its entry point, all five action
  identities/commands, anchored popup ownership, and default placement remain
  intact while the fixed five-row-only geometry is removed.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 583 passed, 0 failed.
- Repository functional suite: `./tests/run.sh` — 228 passed, 0 failed.
- Syntax: repository-wide `bash -n` — 241 shell scripts passed.
- ShellCheck: new/changed Power and test scripts introduced no findings;
  unrelated pre-existing findings remain in the repository inventory checks
  and installer sources.
- Diff hygiene: `git diff --check` passed; no generated files or test
  artifacts remain in the repository.
- UI/data evidence: Power now renders a battery hero with percentage,
  progress, status, bounded battery statistics, profile selector, confirmation
  rows, and content-fitted Aurelia popup geometry. `showPercentage` remains an
  inline setting owned by the resident shell configuration path.
- Failure evidence: missing UPower/battery state returns a hidden zero-width
  bar affordance; empty/malformed profiles retain the previous safe state and
  expose a bounded error; failed profile/system actions log an observable
  bounded error without escaping the Power boundary.
- Ownership evidence: UPower supplies live battery truth, `powerprofilesctl`
  and system actions use structured argv, and Power owns no privilege
  escalation, shell string, new backend, second IPC target, or direct state
  file mutation.
- Existing feature evidence: `aurelia.power`, `PowerBarWidget.qml`,
  `PowerPanel.qml`, manifest placement, lock/logout/suspend/reboot/shutdown
  behavior, default bar slot, theme ownership, and host lifecycle remain
  preserved; no `config/bar-default.json` change was made.
- User-visible behavior changed: yes; the existing Power popup now has the
  requested reference-level information hierarchy and battery-aware bar
  affordance while retaining all prior actions.
- Rollback/migration evidence: no UPower/profile/system action, persisted
  setting write, installer/package operation, systemd/greetd change, shell
  restart, or reboot occurred; reverting the Power-owned files and tests
  restores the prior popup without changing user data.
- Live status: isolated/static evidence is complete; real UPower data,
  profile availability, and Wayland visual appearance remain unrun and are
  not claimed.

CP3 status: `[x]` repository/static/isolated acceptance complete; live
UPower/Wayland visual confirmation remains pending and is not claimed.

Exit gate: the Power popup has the requested reference-level information
architecture and UX quality while every existing Aurelia power action and
shell-safety invariant remains intact.

Dependencies: T38, T02A, T24, T31, T33.

---

### T40. Complete the Aurelia bar configuration control plane

Execution status: COMPLETE — corrective CP2 and CP3 passed for repository,
static, and isolated evidence; live Wayland confirmation remains deferred

Scope:

- Extend the existing `aurelia-bar` command surface with `use`, `reset`,
  `defaults`, `position top|bottom|left|right`, and
  `transparent true|false|toggle`.
- Preserve existing `put`, `move`, and `set` behavior and support the exact
  reference examples, including moving the clock to center index zero and
  setting its format.
- Route all mutations through resident shell IPC and `ShellConfig`'s single
  mutation owner. Do not let the CLI edit `shell.json` behind the resident
  process or create a second competing config format.
- `defaults` must restore the canonical `aurelia-shell/config/bar-default.json`
  layout idempotently while preserving unrelated user-owned configuration and
  maintaining the active-bar fallback/selection contract.
- Validate all values and selectors before mutation; invalid commands must
  fail closed with no partial config changes. Existing widget IDs and settings
  remain unchanged.

Required tests:

- [x] CLI help and argument matrix for every new command and invalid value.
- [x] Isolated shell IPC/config fixture for use/reset/defaults/position/
  transparency and exact idempotent reruns.
- [x] Preservation tests for user settings, plugin instances, active bar
  fallback, and existing put/move/set operations.
- [x] No-direct-file-edit and no-duplicate-mutation checks.
- [x] Full Aurelia/repository/syntax/ShellCheck gates.

Checkpoint 3 — T40 post-change evidence:

- New bar control-plane suite: `test_bar_control_plane.sh` — 6 passed, 0
  failed. It covers `use`, `reset`, `defaults`, `position`, and
  `transparent true|false|toggle`, exact IPC routing, invalid-input rejection,
  idempotent canonical default restoration, built-in-bar re-enable, and
  preservation of unrelated plugins/user state.
- Existing placement/settings suite: `test_bar_operations.sh` — 9 passed,
  0 failed; the catalog/config signal boundary and existing `put/move/set`
  operations remain green.
- Combined focused T40 checks: 12 passed, 0 failed.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — 589 passed, 0 failed.
- Repository functional suite: `./tests/run.sh` — 228 passed, 0 failed.
- Syntax: repository-wide `bash -n` — 242 shell scripts passed.
- ShellCheck: the new/changed T40 CLI, fixture, runner, and control-plane test
  scripts introduced no findings; pre-existing findings remain only in the
  older placement-test fixture pattern and unrelated repository sources.
- File-size guard: `ShellConfig.qml` is 986 lines and `PluginRegistry.qml` is
  964 lines after responsibility extraction; the 1000-line god-file guard
  passes without suppression or threshold changes.
- Ownership evidence: the CLI is IPC-only; `BarControlRegistry` validates
  manifest bar identity and routes to ShellConfig; `BarConfigOperations` owns
  bar transitions while ShellConfig remains the sole atomic persistence owner.
- Reference examples are supported through the existing executable:
  `aurelia-bar position bottom`, `aurelia-bar transparent toggle`,
  `aurelia-bar move aurelia.clock --section center --index 0`,
  `aurelia-bar set aurelia.clock format 'HH:mm'`, and
  `aurelia-bar defaults`.
- Existing feature evidence: no plugin ID, entry point, default layout,
  widget setting, active-bar fallback, or user-owned state was renamed,
  moved, or overwritten; `config/bar-default.json` was not changed.
- Live status: no live shell restart, configuration mutation, package or
  installer operation, systemd/greetd change, or reboot occurred. Real
  Wayland IPC/visual confirmation remains unrun and is not claimed.

CP3 status: `[x]` repository/static/isolated acceptance complete; live
Wayland confirmation remains pending and is not claimed.

Corrective checkpoint 2 — T40 god-file boundary:

- Discovery: after the first T40 implementation pass, the full Aurelia suite
  reported one structural failure because `ShellConfig.qml` reached 1031 lines
  and `PluginRegistry.qml` reached 1018 lines. The 1000-line guard is a
  repository invariant and will not be weakened.
- Repair boundary: move bar-specific persistence operations into a cohesive
  `services/BarConfigOperations.qml` owned by `ShellConfig`, and move
  bar-specific registry validation/routing into a cohesive
  `services/BarControlRegistry.qml` owned by the resident shell. ShellConfig
  remains the only object that prepares/persists state; the new registry
  component remains the only IPC-facing bar-control router.
- Current working-tree boundary: only T40 CLI, shell IPC, ShellConfig,
  PluginRegistry, fixture, runner, and test changes are uncommitted; no
  unrelated user change is present. Further source edits are restricted to
  the two new services, `services/qmldir`, the narrow call-site rewiring, and
  the corresponding T40 test fixture/assertions.
- Required preservation: `use`, `reset`, `defaults`, `position`,
  `transparent`, existing `put/move/set`, exact IPC arguments, atomic writes,
  default-bar preservation, built-in-bar enablement, and invalid-input
  fail-closed behavior must remain unchanged.
- Baseline before T40 source work: `48ecb1b` was clean; Aurelia had 575
  passing tests, the repository had 228 passing tests, and 241 shell scripts
  passed `bash -n`. The first T40 pass still has 588 passing Aurelia tests,
  1 file-size failure, and 228 passing repository tests.
- No live impact: no user config, live shell, package, systemd/greetd state,
  or reboot may be touched. Rollback removes only the two services and
  rewiring while retaining the tested T40 behavior.

Corrective CP2 status: `[x]` the no-god-file repair boundary, ownership model,
preservation requirements, baseline, and rollback path are recorded before
the corrective source refactor.

Exit gate: Aurelia exposes the requested Omarchy bar command language through
its existing safe resident control plane without changing existing feature
names, user state semantics, or shell availability.

Dependencies: T39, T03, T10, T12, T18, T24, T27, T31.

---

### T41. Implement persistent bar hiding, shortcut, and Menu Bar parity

Execution status: COMPLETE — CP2 and CP3 passed for repository, static, and
isolated evidence; live Wayland confirmation remains deferred

Checkpoint 2 — T41 pre-change boundary:

- Starting branch/SHA: `installer-resilience` /
  `e07ae3d429c389e26f08bd5f9f5bf54ac76251d0`; `git status --short` is clean.
- Reference contract frozen from `/tmp/omarchy-reference` at branch `quattro`,
  SHA `31bd80daa4613ffdee995ac27467fce5a2990806`: the reference uses an
  XDG state marker, a resident bar sync IPC, a parent-directory watcher,
  mapped-but-offscreen hiding with `ExclusionMode.Ignore`, and the exact
  `Super + Shift + Space` toggle. Its menu vocabulary is `Menu Bar` with
  visible/hidden state plus position and transparency controls.
- Current Aurelia boundary: `Bar.qml` has only in-memory `barHidden` state and
  already exposes the safe off-screen/exclusion geometry; the menu currently
  has a flat `toggle-bar` action; the plugin keybinding loader merges
  plugin-owned `keybindings.lua` declarations into the authoritative manifest;
  T40's resident `ShellConfig` bar mutation API is the only configuration
  owner.
- Focused baseline: the T40 bar control-plane checks and existing placement/
  settings checks pass together — `12` passed, `0` failed. The direct test
  files require the shared runner helper and were therefore run through that
  helper, not as standalone production commands.
- Planned owned files: `plugins/aurelia.bar/Bar.qml`, the Aurelia bar state
  writer/CLI boundary and its bar module, `plugins/aurelia.bar/keybindings.lua`,
  `plugins/aurelia.menu/MenuModel.qml`, shipped menu data/UI only where needed,
  T41 fixtures/tests/runner registration, and this tracker. No Power,
  Bluetooth, installer, package, live configuration, systemd/greetd, or reboot
  work is in scope.
- State/mutation ownership: the marker is under the Aurelia XDG state
  namespace and is written atomically by one validated user-level writer;
  `Bar.qml` only reads/synchronizes it. Missing or malformed state defaults to
  visible and emits an observable diagnostic. IPC/read failures remain
  observable without making the host or healthy plugins fail to load.
- Compatibility/rollback: retain the current visible default, existing
  `aurelia.bar` IPC aliases, menu provider validation, all T40 commands, and
  all existing plugin/user state. Rollback removes only the T41 writer,
  watcher, keybinding, menu additions, fixtures, and tracker evidence.
- Live-impact decision: no live shell restart, compositor mutation, user
  configuration write, package operation, systemd/greetd change, or reboot is
  required for implementation or isolated validation.

CP2 status: `[x]` the T41 contract, baseline, file boundary, ownership,
survivability behavior, and rollback path are recorded before source/test
implementation.

Scope:

- Add an XDG-state-owned, atomic, idempotent bar-hidden toggle state with
  explicit `on|off|toggle` semantics and safe default-visible behavior.
- Keep the resident bar and shell process alive while hidden: park only the
  bar surface off-screen, remove its exclusion zone, preserve widget/plugin
  state, and keep Command Center and all hotkeys available.
- Add an explicit bar sync/read boundary so rapid state-file changes cannot
  strand the bar; watch the parent directory because a first toggle creates a
  previously absent state file.
- Add `Super + Shift + Space` to the authoritative keybinding manifest through
  an existing safe structured action path. It must toggle the Aurelia bar even
  when the bar pixels are hidden.
- Replace/extend the flat menu action with the reference Menu Bar semantics,
  including a visible/hidden checked state and safe position/transparency
  controls after T40 provides their mutation API. Preserve existing menu
  provider validation and user extensions.
- Invalid/missing toggle state, watcher failure, or bar IPC unavailability
  must remain observable and must not kill the host or suppress warnings.

Required tests:

- [x] Pure state parser and idempotent atomic-write tests for missing, valid,
  malformed, symlinked, and rapidly changed toggle state.
- [x] Isolated bar fixture proving mapped-but-offscreen hidden behavior,
  exclusion-mode transition, restore, and healthy widget/hotkey continuity.
- [x] Keybinding manifest/registration tests for exact
  `Super + Shift + Space` semantics.
- [x] Menu model/action/checked-state tests for Menu Bar controls.
- [x] Full Aurelia/repository/syntax/ShellCheck gates; no live compositor
  mutation in ordinary validation.

Checkpoint 3 — T41 post-change evidence:

- T41 focused suite: `test_bar_hiding.sh` — `16` passed, `0` failed. It
  covers the XDG marker's visible default, valid hidden state, malformed and
  symlink rejection, idempotent atomic publication, rapid transitions,
  observable resident-sync failure, exact manifest registration, Menu Bar
  provider actions/checked state, and user-menu preservation.
- The Menu Bar QuickShell model fixture passed with the safe shell facade. The
  real `PanelWindow` bar fixture was attempted but explicitly skipped because
  this offscreen environment reports `No PanelWindow backend loaded`; mapped
  surface geometry and live compositor behavior are not claimed as verified.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — `605` passed, `0`
  failed.
- Repository functional suite: `./tests/run.sh` — `228` passed, `0` failed.
- Syntax: repository-wide `bash -n` — `244` shell scripts passed.
- ShellCheck: all changed T41 shell scripts and fixtures are clean. The
  repository-wide command still reports pre-existing findings in unrelated
  installer/test sources; no warning was suppressed or deleted for T41.
- Implementation commit: `e3253b0cbe9e3b886b67d7fae4e43932023e34e6`;
  pre-change tracker checkpoint: `f0d4bf1`.
- Ownership evidence: `aurelia-bar-hidden` is the single validated state
  writer; the resident bar only reads/synchronizes the marker, queues writes
  through that writer, stays mapped, parks off-screen, and changes exclusion
  mode. The plugin-owned binding is merged by the existing authoritative
  manifest loader, and Menu Bar mutations call the existing T40 resident
  control-plane APIs.
- Preservation evidence: no plugin ID, entry point, Power/Bluetooth behavior,
  default bar layout, user-menu extension, configuration ownership, package,
  installer, systemd/greetd state, or live user state was changed.
- Live status: no shell restart, compositor mutation, package or installer
  operation, systemd/greetd change, or reboot occurred. Real Wayland visual
  acceptance remains unrun and is not claimed.

CP3 status: `[x]` repository/static/isolated acceptance complete; live
Wayland confirmation remains pending and is not claimed.

Exit gate: bar hiding matches the reference interaction without terminating
the resident shell, panels, plugins, or hotkeys, and every state transition is
tested and observable.

Dependencies: T40, T02A, T21, T23, T24, T31, T33.

---

### T43. Make test outcomes truthful and warning-complete

Execution status: COMPLETE — CP2 and CP3 passed for repository, static, and
isolated evidence; compositor-dependent coverage remains explicitly skipped

Checkpoint 2 — T43 pre-change boundary:

- Starting branch/SHA: `installer-resilience` /
  `410d644a757b64cdbcee86c49cf8a32f4974fc3c`; the working tree is clean.
- The current Aurelia runner reports `605` passed and `0` failed, but
  `test_helper.sh` increments only `PASSES`/`FAILS`; skip paths call `pass()`
  and no skip total exists. Current runtime evidence is therefore not a full
  coverage claim.
- The current runtime tests can accept a compositor/backend diagnostic by
  entering a skip branch without first asserting that the remaining log is
  free of QML warnings/errors. This allowed the Power construction warning
  and the T41 FileView warning to pass unnoticed.
- Reference contract frozen from Omarchy at `/tmp/omarchy-reference`, branch
  `quattro`, SHA `31bd80daa4613ffdee995ac27467fce5a2990806`: its shell tests
  deliberately separate pure/headless tests from compositor/VM acceptance,
  probe compositor reachability rather than trusting an environment variable,
  continue after failed test files, and document skips explicitly. Aurelia
  will retain its centralized runner but must not collapse skip into pass or
  allow a backend skip to mask an unrelated diagnostic.
- Planned owned files: Aurelia test helper/runner, existing Aurelia test skip
  branches and runtime log gates, a focused test-framework contract fixture,
  and this tracker. No production plugin, installer, package, live user
  configuration, systemd/greetd state, or reboot is in scope for T43.
- Required semantics: `skip()` increments a separate counter and is printed
  distinctly; ordinary pass counts include only executed assertions; runtime
  skip classification accepts only known environment limitations after all
  unexpected warnings/errors are rejected; a strict no-skip mode returns a
  distinct non-zero status for CI/integration gates.
- Rollback: revert only test-helper/runner/skip-gate and T43 fixture changes;
  no runtime or persisted state is changed.

CP2 status: `[x]` the T43 test contract, reference comparison, baseline
limitation, ownership boundary, strict-mode semantics, and rollback path are
recorded before test-framework edits.

Scope:

- Separate pass, skip, and failure accounting throughout the Aurelia test
  runner and migrate existing skip branches to the explicit skip primitive.
- Add a warning-complete runtime-log classifier so backend skips are accepted
  only when the log contains an approved environment limitation and no other
  warning/error/loader failure.
- Add a strict no-skip gate for final/CI acceptance without making headless
  test limitations invisible or pretending they are runtime coverage.
- Add focused tests that prove skip accounting, strict-mode exit behavior, and
  rejection of a backend diagnostic combined with an unrelated QML warning.

Required tests:

- [x] Focused test-framework accounting and strict-mode tests.
- [x] Existing runtime skip branches migrated and warning-complete.
- [x] Full Aurelia/repository/syntax/ShellCheck gates.

Checkpoint 3 — T43 post-change evidence:

- Focused framework contract: `test_test_framework.sh` — `7` assertions
  passed, `0` failed. It proves independent skip accounting, strict-mode exit
  `2`, warning-complete backend classification, child-suite isolation, and
  removal of legacy pass/printf skip paths.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — `602` passed, `9`
  skipped, `0` failed. The summary now distinguishes all three outcomes;
  skipped paths include live Wayland/QML smoke that this environment cannot
  provide.
- Strict Aurelia gate: `./aurelia-shell/tests/run.sh --strict` reports the
  same `602/9/0` result and returns `2`, so skipped runtime coverage cannot be
  mistaken for a complete acceptance run.
- Repository functional suite: `./tests/run.sh` — `228` passed, `0` failed.
- Syntax: repository-wide `bash -n` — `245` shell scripts passed.
- ShellCheck: T43-owned framework files (`test_helper.sh`, `run.sh`,
  `test_test_framework.sh`, and plugin harness) are clean. Existing unrelated
  findings remain in older test/installer sources; no warning filter was added
  to make those findings disappear.
- Implementation commit: `30f886d01eb364c4f5170bd23f35028d6432321f`;
  pre-change tracker checkpoint: `f60b0c3`.
- Architecture evidence: each suite now runs in a fresh child process and the
  parent aggregates explicit output records; runtime skip helpers reject any
  diagnostic outside the narrowly defined backend limitation and print the
  accepted environment diagnostics for visibility.
- Preservation evidence: no production plugin, installer, package, user
  configuration, systemd/greetd state, live shell, or compositor state was
  changed. T44/T45 remain the owners of the two known production warnings.

CP3 status: `[x]` test-framework truthfulness and warning-complete skip
classification are complete; the strict gate remains intentionally
inconclusive until the compositor-dependent tests can run.

Exit gate: the Aurelia test command cannot report skipped runtime coverage as
ordinary passing assertions, and no backend limitation can hide an unrelated
warning or error.

Dependencies: T02, T02A, T31, T33, T39, T41.

---

### T44. Correct Power panel construction and add real entry-point coverage

Execution status: IN PROGRESS — CP2 recorded before implementation; CP3
pending

Checkpoint 2 — T44 pre-change boundary:

- Starting branch/SHA: `installer-resilience` /
  `30f886d01eb364c4f5170bd23f35028d6432321f`; the working tree is clean.
- Confirmed production finding: `PowerPanel.qml:317` declares a non-visual
  `Process` directly beneath `AureliaKeyboardPanel`, whose default
  `contentItem` accepts only `QQuickItem` children. The live result is the
  warning “Cannot assign object of type Process to list property contentItem”
  followed by `[POWER] panel_load_failed`.
- Existing coverage boundary: `test_power_plugin.sh` statically inspects the
  panel but its runtime fixture loads `PowerBarWidget.qml` with a fake
  `panelOverride`; it does not prove real Power panel construction. The
  compositor-dependent branch is now a distinct skip and cannot mask an
  unrelated warning after T43.
- Planned owned files: `plugins/aurelia.power/PowerPanel.qml`, the Power
  runtime fixture/test and preservation assertions, plus this tracker. No
  bar hiding, Bluetooth, installer, package, live configuration, systemd,
  greetd, or reboot work is in scope.
- Required preservation: retain `aurelia.power`, its manifest and entry point,
  all five existing actions, UPower/profile ownership, popup geometry,
  settings semantics, and host failure quarantine.
- Rollback: restore only the Power construction/test changes; T43 remains
  independently reversible and the T41 bar-hiding implementation remains
  untouched.

CP2 status: `[x]` the exact construction failure, insufficient fixture
boundary, ownership, preservation requirements, and rollback path are
recorded before T44 source/test edits.

Scope:

- Move non-visual Power processes out of `AureliaKeyboardPanel`'s default
  `contentItem` list without changing the panel's identity, actions, layout,
  UPower ownership, or popup behavior.
- Add an entry-point fixture that loads the real `PowerPanel.qml` rather than
  only injecting a fake `panelOverride` into `PowerBarWidget.qml`.
- Preserve failure isolation: a Power construction failure must be reported
  and quarantined without preventing the resident shell, bar, or healthy
  plugins from loading.

Required tests:

- [x] Static ownership check rejects non-visual objects in the keyboard-panel
  content list.
- [x] Real Power panel construction/runtime fixture passes when its required
  backend is available and reports an explicit environment skip otherwise.
- [x] The skip branch rejects unrelated QML warnings through T43's log gate.
- [x] Full Aurelia/repository/syntax/ShellCheck gates.

Checkpoint 3 — T44 post-change evidence:

- Power-focused suite: `test_power_plugin.sh` — `9` executed assertions
  passed, `0` failed, and `1` explicit PowerPanel backend path was skipped.
  The real `PowerRuntime.qml` QObject constructed independently, the static
  content-list guard passed, and the real PowerPanel fixture could not create
  a PanelWindow only in this offscreen environment. Its complete diagnostics
  were printed and passed T43 classification; no `Process` contentItem warning
  remained.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — `603` passed, `10`
  skipped, `0` failed.
- Repository functional suite: `./tests/run.sh` — `228` passed, `0` failed.
- Syntax: repository-wide `bash -n` — `245` shell scripts passed.
- ShellCheck: T44 introduced no shell scripts; T43 framework files remain
  clean and existing unrelated test/installer findings remain classified.
- Implementation commit: `6c48237` (`fix(power): isolate panel runtime
  processes`); T44 checkpoint was recorded in the T43 tracker completion
  checkpoint.
- Preservation evidence: `aurelia.power`, its manifest/entry point, all
  existing actions, default placement, UPower/profile ownership, popup
  geometry, and host failure containment remain unchanged. No live power
  command, package, installer, systemd/greetd change, shell restart, or reboot
  occurred.

CP3 status: `[x]` Power construction and isolated runtime-object acceptance
are complete; live Wayland/UPower visual confirmation remains pending.

Exit gate: the live `PowerPanel.qml:317` warning and resulting panel load
failure are eliminated and covered by a real entry-point test.

Dependencies: T39, T43, T02A, T31, T33.

---

### T45. Correct the Aurelia bar hidden-state watcher contract

Execution status: COMPLETE — CP2 and CP3 passed for repository, static, and
headless runtime evidence; live Wayland confirmation remains deferred

Checkpoint 2 — T45 pre-change boundary:

- Starting branch/SHA: `installer-resilience` /
  `6c482379a4830319faf96e6df08d8c33c14aaf18`; the working tree is clean.
- Confirmed production finding: `Bar.qml:353` passes the XDG state directory
  fallback to `FileView`, and Aurelia reports “Read of .../.local/state
  failed: Not a file.” This warning is emitted because Aurelia's FileView is
  file-oriented; Omarchy's directory FileView usage cannot be copied blindly.
- Existing T41 state reader/writer, mapped/off-screen geometry, queue,
  structured `syncHidden` IPC, and XDG marker semantics are preserved. The
  correction is limited to the parent-directory event source and its fixture.
- Planned owned files: `plugins/aurelia.bar/Bar.qml`, a cohesive watcher
  component or watcher-only wiring, T41 bar-hiding tests/fixtures, and this
  tracker. No Power, Bluetooth, installer, package, live configuration,
  systemd/greetd, or reboot work is in scope.
- Host capability: `inotifywait` is already an Aurelia package/runtime
  dependency used by the plugin watcher; no package change is needed.
- Rollback: restore only the watcher source/test changes; T43 and T44 remain
  independently reversible, and no persisted user state is migrated.

CP2 status: `[x]` the exact directory/file API mismatch, reference caveat,
preservation boundary, available host capability, and rollback path are
recorded before T45 source/test edits.

Scope:

- Replace the invalid `FileView` directory fallback in the Aurelia bar with a
  watcher/read design supported by the installed QuickShell runtime.
- Continue watching the actual parent toggle directory when it exists, handle
  its initially absent state without a false “not a file” warning, and retain
  explicit sync/read behavior for rapid transitions.
- Preserve mapped-but-offscreen hiding, `ExclusionMode.Ignore`, widget state,
  shortcut continuity, XDG ownership, atomic writer behavior, and observable
  failures.

Required tests:

- [x] Static/runtime checks prove no directory is passed to a file-only reader.
- [x] Missing parent, first creation, rapid update, malformed state, and
  watcher failure cases are covered without warning suppression.
- [x] Real bar fixture passes when a PanelWindow backend is available; the
  unavailable-backend path is an explicit skip subject to T43 log validation.
- [x] Full Aurelia/repository/syntax/ShellCheck gates.

Checkpoint 3 — T45 post-change evidence:

- T45 focused bar-hiding suite: `test_bar_hiding.sh` — `17` assertions
  passed, `0` failed, and `1` explicit PanelWindow backend path was skipped.
  The real `BarHiddenWatcher` QObject observed marker creation/removal in a
  headless QuickShell fixture; the old directory `FileView` path is gone.
- The skipped real bar fixture printed only the approved IPC/PanelWindow
  environment diagnostics through T43's classifier. The live bar surface,
  exclusion transition, and compositor geometry remain separately unverified.
- Full Aurelia suite: `./aurelia-shell/tests/run.sh` — `605` passed, `10`
  skipped, `0` failed.
- Repository functional suite: `./tests/run.sh` — `228` passed, `0` failed.
- Syntax: repository-wide `bash -n` — `245` shell scripts passed.
- ShellCheck: T45-owned shell tests and the T43 framework files are clean;
  unrelated older test/installer findings remain classified.
- Implementation commit: `aa88ad41388b21a42b07c767f01a527f29d887b3`;
  pre-change tracker checkpoint: `6a4b998`.
- Preservation evidence: XDG state ownership, atomic writer behavior, exact
  shortcut, Menu Bar controls, mapped bar surface, widget routing, Power,
  Bluetooth, installer, package, systemd/greetd, user configuration, and
  reboot boundaries remain unchanged.

CP3 status: `[x]` the runtime-supported parent watcher and headless event
contract are complete; live Wayland visual confirmation remains pending.

Exit gate: the live `Bar.qml:353` watcher warning is eliminated without
silencing diagnostics, and hidden-bar state remains recoverable and resident.

Dependencies: T41, T43, T02A, T31, T33.

---

### T46. Make the test command strict and close the suite-coverage gap

Execution status: COMPLETE — strict runner, suite inventory, evidence tiers, and Power capability diagnosis implemented

Checkpoint 1 — T46 audit boundary:

- Current default `./aurelia-shell/tests/run.sh` exits `0` with `605` passed,
  `10` skipped, and `0` failed. The no-skip policy is opt-in through
  `--strict`, which permits a normal green command to omit runtime coverage.
- The current Aurelia runner registers `65` suite entry points, but five
  runnable `test_*.sh` suite files are not registered:
  `test_about_animation.sh`, `test_aurelia_hotkeys.sh`,
  `test_aurelia_keybindings.sh`, `test_hotkeys.sh`, and
  `test_quickshell_provenance.sh`. `test_helper.sh` is a helper, not a suite.
  The runner has no invariant that detects future omissions.
- Centralized root tests and static grep assertions do not constitute runtime
  coverage for every plugin entry point. T30's requested plugin-local test
  directories remain a separate structural task and must not be counted as
  complete merely because centralized tests exist.
- The refreshed Omarchy reference also separates shell tests from authorized
  acceptance tests, but its compositor guard reports unavailable hardware as
  `ok`/skip. Aurelia's user requirement is stricter: a skipped assertion must
  be visible and must fail the strict command rather than inflate a pass count.
- The current VM has no `/sys/class/power_supply` battery and UPower cannot be
  contacted from the test sandbox. Omarchy explicitly hides the Power bar on
  desktops/VMs without a battery. Aurelia's `aurelia.power` default layout
  entry remains present and its widget is intentionally zero-width/hidden when
  `batteryPresent` is false; the former `PowerPanel.qml` construction warning
  is absent from the latest restart log. This is a capability condition, not
  evidence that the widget failed to load.

Scope and preservation boundary:

- Make the public Aurelia test command fail closed on skipped assertions by
  default; provide an explicit, clearly named diagnostic mode only when a
  developer intentionally wants to inspect headless skips.
- Make suite discovery/registration fail closed so no runnable suite can be
  silently omitted. Repair only test-entry ownership/path issues needed to
  execute existing suites; do not rename or relocate product files.
- Add real coverage accounting (suite count, assertion count, pass/skip/fail
  count, and omitted-suite detection) and a Power capability test that proves
  both default placement and the reference no-battery visibility contract.
- Do not fake battery hardware, force the Power widget visible on a desktop,
  suppress QML warnings, weaken runtime diagnostic classification, or alter
  UPower/systemd/package/live-shell state.
- T30 plugin-local test directories, T34 Bluetooth retention, and T42 final
  acceptance remain separate tasks. Existing Aurelia feature behavior, plugin
  IDs, bar layout, user state, shortcuts, and live configuration are outside
  this correction.

Required tests:

- [x] Default Aurelia test invocation rejects any skip with a distinct
  non-zero result; explicit diagnostic mode remains honest and visibly reports
  skips.
- [x] Every runnable Aurelia suite entry point is executed exactly once or is
  explicitly classified with a checked-in reason; an unregistered suite fails
  the test framework contract.
- [x] Summary reports suite and assertion coverage separately; a suite that
  exits without an assertion is not silently accepted.
- [x] Power tests prove default placement, real bar entry loading, safe
  no-battery hiding, and diagnostic capability evidence without fake live
  hardware.
- [x] The full diagnostic Aurelia/repository/syntax/ShellCheck gates pass with
  no suppressed warnings. The strict Aurelia command intentionally returns 2
  for the ten unavailable-backend paths; live Wayland/UPower visual evidence
  remains separately labeled.

Checkpoint 2 status: `[x]` tracker-only pre-change checkpoint committed as `bfd7dda`.

Checkpoint 3 — T46 post-change evidence:

- The ordinary `./aurelia-shell/tests/run.sh` command is strict by default. It
  returned exit `2` with `623` assertions: `613` passed, `10` skipped, and
  `0` failed. The non-zero result is intentional: strict mode refuses to call
  an environment-gated assertion a successful test while the required backend
  is absent.
- The explicit `./aurelia-shell/tests/run.sh --allow-skips` diagnostic command
  returned exit `0` with the same `623` assertion accounting and visibly
  reported all `10` skips. It never converted a skip into a pass.
- `66` owned suite entry points executed. The runner now discovers top-level
  suites dynamically, verifies the executed count, and reports four explicit
  legacy repository matrices excluded from Aurelia Shell coverage:
  `test_aurelia_hotkeys.sh`, `test_aurelia_keybindings.sh`, `test_hotkeys.sh`,
  and `test_quickshell_provenance.sh`. These files remain at their original
  paths and are not represented as passing Aurelia tests.
- Evidence tiers are reported separately: `static=213`, `isolated=107`,
  `live=2`, and `unlabelled=301`. This is an evidence inventory, not a claim
  of source line/branch coverage; the remaining unlabelled legacy assertions
  are visible follow-up work rather than hidden coverage.
- Framework-focused checks: `9` passed, `0` failed. Power-focused checks:
  `9` passed, `1` explicit PanelWindow-backend skip, `0` failed. The Power
  fixture proves the real bar widget's battery lifecycle and emits the
  observable `availabilityReason=no_battery` contract.
- Repository suite: `./tests/run.sh` — `228` passed, `0` failed. Repository-
  wide shell syntax: `245` scripts passed `bash -n`. ShellCheck on all T46-
  changed shell files: clean. `git diff --check`: passed.
- Reference confirmation: Omarchy's acceptance test intentionally hides its
  Power panel when `upower -e` exposes no battery. This VM has an empty
  `/sys/class/power_supply` battery inventory and the sandbox cannot connect
  to UPower, so no Power pixels are expected here. Aurelia retains the
  `aurelia.power` default entry, makes it zero-width when no battery is
  present, and now logs `[POWER] bar_hidden reason=no_battery`; it does not
  fake hardware or diverge from the reference to make the icon appear.
- Implementation commit: `890ca7c` (`test(aurelia): enforce strict suite
  coverage`); tracker checkpoint: `bfd7dda`.
- No plugin source other than the Power availability diagnostic changed. No
  Power action, UPower state, bar layout, user state, package, systemd/
  greetd state, live configuration, or reboot was touched.

CP3 status: `[x]` strictness and coverage accounting are complete. The strict
command is correctly blocked by the ten backend-gated paths; live Wayland,
UPower, and visual acceptance remain unrun and must not be claimed as green.

Exit gate: the ordinary test command cannot report a green result while
coverage is skipped or a suite is omitted, and Power's no-battery behavior is
proven as the same intentional contract used by Omarchy.

Dependencies: T30, T39, T43, T44, T45, T02A, T31, T32, T33.

---

### T42. Requested capability integration and final acceptance gate

Execution status: NOT STARTED — queued behind completed corrective T43 through T45

Scope:

- Re-run the complete Aurelia manifest/catalog/default-layout inventory and
  compare Audio, Microphone, Power, bar commands, hiding, menu, and shortcut
  contracts against the refreshed Omarchy checkout.
- Add end-to-end isolated lifecycle coverage for default startup, plugin
  failure/quarantine, Audio/Microphone/Power open-close, bar mutations,
  defaults restoration, hidden-bar restoration, reload, and repeated execution.
- Add/update authoring and user documentation for new plugin IDs, controls,
  exact command language, shortcut, Menu Bar path, optional Microphone
  enablement, and failure behavior.
- Run optional real-Wayland visual/session acceptance only after explicit
  authorization; separate those results from isolated tests and do not claim
  visual parity from static checks.
- Record exact test/syntax/ShellCheck counts, unchanged feature inventory,
  rollback evidence, final commits, and all remaining intentional Omarchy
  differences.

Required tests:

- [ ] Full Aurelia suite and repository suite are green.
- [ ] All affected failure-isolation and preservation fixtures are green.
- [ ] Repository-wide shell syntax passes; available ShellCheck findings are
  classified without suppressing or deleting warnings.
- [ ] Optional real-session evidence is either authorized and recorded or
  explicitly marked unrun.

Exit gate: the requested capability set is structurally and behaviorally at
Omarchy parity as far as Aurelia's preserved features and safety boundaries
allow, every task has CP3 evidence, and no task leaves the shell unusable.

Dependencies: T36, T37, T38, T39, T40, T41, T43, T44, T45, T02A, T31, T32, T33.

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
| Observed startup warning-producing component graph lacked regression coverage | T29 |
| No plugin-local test directory structure (new requested requirement) | T30 |
| Actionable plugin/host warnings or errors may be hidden by silent catches or failure gates | T31 |
| Dynamic plugin/resource sources are built by scattered ad-hoc file-URL paths and are not relocation-tested | T32 |
| Shared anchored surfaces call coordinate mapping on a window content receiver that lacks the API | T33 |
| Bluetooth scan results disappear across discovery refresh/reopen despite device identity | T34 |
| No Audio bar-widget plugin or Audio panel with output/input/stream controls | T36, T37 |
| No separate Microphone bar widget with mute, Audio summon, and input-scroll controls | T38 |
| Existing Power popup lacks Omarchy battery, statistics, profile, and percentage UX | T39 |
| Aurelia bar CLI lacks use/reset/defaults/position/transparent controls | T40 |
| Bar hiding lacks persistent state, exact shortcut, and full Menu Bar semantics | T41 |
| Test summary collapses skipped runtime coverage into passed assertions | T43 |
| Power panel places non-visual processes in the keyboard panel content list | T44 |
| Bar hidden-state watcher passes a directory to Aurelia's file reader | T45 |
| Default test command permits skipped coverage and omits runnable suite files | T46 |
| Power no-battery capability is not clearly distinguished from widget failure | T46, T39, T44 |
| Requested Audio/Microphone/Power/bar/hiding capabilities lack a combined acceptance gate | T42 |

## Final preservation gate

Before declaring parity complete:

- [x] Existing Aurelia plugin IDs remain valid or have an explicit migration.
- [x] Existing Aurelia IPC aliases still forward correctly.
- [x] Existing Aurelia bar defaults, theme tokens, panel geometry, keyboard
  behavior, and popup ownership remain unchanged.
- [x] Existing notification, screenshot, network, Bluetooth, display, theme,
  image-picker, workspace, launcher, keybinding, tray, tasklist, power,
  calendar, and weather features remain available.
- [x] A deliberately faulty plugin cannot prevent Aurelia host readiness or
  healthy-plugin availability in isolated runtime tests.
- [x] Existing backend and privilege ownership remains unchanged.
- [x] Existing user configuration is preserved and migration is idempotent.
- [x] Existing login-critical architecture is untouched.
- [x] No test claims runtime parity without runtime evidence.
- [x] Any intentional difference from Omarchy is written here, reviewed, and
  approved before release.

## Reference feature inventory differences

The structural parity work is tracked task-by-task above. Omarchy currently
ships 37 plugin manifest entries while Aurelia ships 24 first-party feature
plugins. The following differences are explicit product-scope decisions, not
missing manifest, registry, lifecycle, API-boundary, safety, or test
architecture.

| Reference capability | Aurelia owner or approved difference |
|---|---|
| bar, background, image-picker, menu, notifications | Aurelia bar, background, image-picker, menu, and notifications plugins. |
| clock, calendar, weather, network, monitor, power | Aurelia clock/calendar, weather, network, monitor, and power plugins. |
| bluetooth, wifiqr, speedtest, tray, workspaces | Aurelia Bluetooth, Wi-Fi QR, speed-test, tray, and workspace plugins. |
| system-update | Aurelia launcher Updates provider and package/update backends. |
| active-window, indicators, keyboard-layout, spacer | No standalone Aurelia equivalents; the current bar composition intentionally omits these reference-only widgets. |
| microphone | Aurelia provides optional `aurelia.microphone`; it remains absent from the shipped default bar like the reference. |
| audio, media | Aurelia provides `aurelia.audio` and optional `aurelia.microphone`; host-global media tooling remains under its established ownership. |
| clipboard, emojis, reminders, dev-gallery, agents | No current Aurelia feature owner; intentionally outside the preserved Aurelia feature inventory. |
| lock, polkit, battery, idle, nightlight | No current Aurelia plugin owner; login, authentication, power, and desktop ownership remain with the existing Fedora/Hyprland/session architecture. |
| osd, disk-speedtest, dropbox, tailscale | No current Aurelia feature owner; intentionally not added as speculative parity work. |

Omarchy's platform-level contract for all rows above is still represented by
Aurelia's shared manifest validator, source-aware registry, resident host,
bar registry, shell state, scoped facades, failure containment, lifecycle CLI,
reload policy, centralized tests, and authoring documentation. This table
prevents the feature-count difference from being mistaken for an untracked
architecture gap.

## Completion record

```text
Parity status:
Repository-only plugin parity work is complete through T46; live
visual/integration validation is deferred pending explicit authorization.
Starting T38 branch/SHA: installer-resilience /
b27ce23d8883f915d6f9e41c4a8cc29ca66da1f9
T38 implementation branch/SHA: installer-resilience /
638e9d459eeaac3de10b08caaee6c0c506cef423
T39 implementation branch/SHA: installer-resilience /
105f95a0cca2b5a1aedbc75a04b2b7cc5e8efb05
T40 implementation branch/SHA: installer-resilience /
7bf8e959410d0435eeb83e05803512910b53485e
T41 implementation branch/SHA: installer-resilience /
e3253b0cbe9e3b886b67d7fae4e43932023e34e6
Reference Omarchy branch/SHA: quattro / 31bd80daa4613ffdee995ac27467fce5a2990806
Tasks completed: all tasks marked `[x]` through T46; T30 plugin-local test
directories, T34 Bluetooth retention, T42 final acceptance, and authorized
live Wayland/visual acceptance remain.
Tests: ./tests/run.sh 228 passed, 0 failed; ./aurelia-shell/tests/run.sh
--allow-skips 613 passed, 10 skipped, 0 failed across 66 suites; the default
strict command returned 2 for the 10 skips
Syntax checks: 245 shell scripts passed bash -n
ShellCheck: all T46-changed shell files are clean; pre-existing findings remain
in older migrated test sources, the repository inventory checks, and installer
sources.
Runtime/visual acceptance: isolated QuickShell/CLI fixtures passed; live
Wayland/visual smoke was not authorized and was skipped
Files changed: T46 strict runner, suite inventory, evidence accounting, Power
availability diagnostic, focused fixture/assertions, README, and tracker;
T43–T45 changes remain in Git history
Recent implementation commits: T38 `638e9d4`, T39 `105f95a`, T40 `7bf8e95`,
T41 `e3253b0`, T43 `30f886d`, T44 `6c48237`, T45 `aa88ad4`, T46 `890ca7c`
Remaining risks: same-process unsandboxed QML cannot survive deliberate
Qt.quit/native crash/engine corruption; 301 existing unlabelled assertions and
four excluded legacy repository matrices remain outside the strict Aurelia
coverage inventory; live visual/UPower behavior remains unverified; T30/T34/
T42 remain open and reference feature omissions remain the explicit
product-scope differences documented above
./install.sh run: no
Packages modified: no
Live user configuration modified: no
systemd/greetd state modified: no
VM rebooted: no
```
