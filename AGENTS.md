# AGENTS.md

## Purpose

This repository builds and maintains a Fedora Hyprland workstation.

It is a public repository. Changes must therefore be designed under the
assumption that real users may execute the installer on machines containing
important data.

The primary engineering objective is not merely:

> Make the installer work.

It is:

> Keep the installer safe, predictable, recoverable, maintainable,
> idempotent, stable by default, and difficult to accidentally make dangerous.

A failed installation is preferable to an incorrectly successful installation
that damages, corrupts, or unpredictably modifies a user's system.

---

# 1. Engineering Principles

All changes must follow these principles:

- Safety first
- No god files
- Modularity
- Separation of concerns
- Single clear ownership
- Stability
- Reliability
- Idempotency
- Extensibility
- DRY
- YAGNI
- KISS
- Least privilege
- Fail-safe / fail-closed defaults
- Safe re-runs
- Safe interruption
- Explicit state transitions
- Validation before activation
- Bounded external operations
- Secure software supply chain
- Reproducibility where appropriate
- Observability
- Testable invariants
- Preserve user data
- Minimize mutation
- Prefer boring, understandable solutions

These principles are constraints, not excuses for over-engineering.

In particular:

- DRY must not override KISS.
- Modularity must not create unnecessary abstraction.
- Extensibility must not mean implementing hypothetical future features.
- Large files must not be split merely because of line count.
- Small files must not be created when they do not represent a coherent
  responsibility.
- Existing working behavior must not be rewritten merely for stylistic purity.

A god file is a file with too many unrelated responsibilities or reasons to
change, not simply a file above an arbitrary line count.

---

# 2. System Ownership Model

The architecture deliberately assigns responsibilities to Fedora, Nix/devenv,
Podman, and Git.

Do not blur these boundaries without a concrete technical reason.

## Fedora Host Owns

Fedora owns operating-system and workstation integration:

- kernel
- firmware
- hardware drivers
- systemd
- NetworkManager
- PipeWire
- Bluetooth
- storage integration
- Hyprland
- greetd
- Noctalia
- portals
- polkit
- fonts
- desktop utilities
- hardware utilities
- media utilities
- normal GUI applications
- Podman runtime
- Nix installation/bootstrap

Host-global utilities that are genuinely workstation capabilities may also be
owned by Fedora or explicitly provisioned as verified upstream artifacts.

## Nix + devenv Own

Development toolchains and project development environments:

- Python development environments
- Rust development environments
- Node.js development environments
- Go development environments
- JVM development environments
- compilers
- SDKs
- language package ecosystems
- project-specific CLI tooling
- reproducible development environments

Do not install these globally through DNF merely for developer convenience
unless there is a concrete Fedora OS integration requirement.

Avoid giant global Nix profiles.

Prefer project-scoped devenv environments.

## Podman Owns

- containers
- isolated services
- disposable service dependencies
- development databases
- development service infrastructure

Prefer rootless Podman.

Docker CE is not a default dependency when Podman satisfies the requirement.

## Git Repository Owns

The repository is the desired-state source of truth for:

- installer logic
- package manifests
- profiles
- managed configuration
- version metadata
- validation
- tests
- engineering documentation

---

# 3. Stable Software Policy

The workstation should be:

> Cutting edge, not bleeding edge.

Use current stable software.

The default workstation must not intentionally consume:

- alpha releases
- beta releases
- release candidates
- nightly builds
- development snapshots
- arbitrary Git HEAD builds
- Fedora Rawhide
- updates-testing merely to obtain newer software
- arbitrary third-party repositories

An exception requires an explicit technical justification documented in the
repository.

A project whose upstream labels all normal public releases with a prerelease-
looking suffix must be treated as an explicit documented exception, not silently
generalized into permission to consume prerelease software elsewhere.

### Explicit Documented Exceptions

- **Official OpenAI ChatGPT for Linux Public Preview**:
  - Reason: Official vendor desktop application distributed by OpenAI with explicit Fedora 43/44 support, required for workstation AI workflows. Currently, no separate general-availability/stable Linux channel exists.
  - Scope: Applies exclusively to the official OpenAI ChatGPT for Linux public preview; does not establish a general precedent for prerelease software elsewhere.

---

# 4. Installation vs Update Discovery

Installation and upstream update discovery are separate concerns.

## Installation

Normal installation consumes repository-reviewed known-good versions.

For direct upstream artifacts prefer:

- explicit version
- authoritative upstream URL
- architecture-specific artifact
- pinned cryptographic checksum or trusted signature

A normal installer run must not silently discover and install a newer upstream
release simply because it appeared after the repository was tested.

## Update Discovery

A separate maintenance mechanism may discover newer stable releases.

Update discovery must:

- use authoritative upstream sources
- ignore drafts
- ignore prereleases unless an explicitly documented project exception applies
- identify architecture correctly
- report candidate versions
- not mutate the running workstation
- not automatically change installer pins
- not execute during normal installation

Updating a pin is a repository maintenance operation that must be reviewed,
tested, and committed.

---

# 5. Package Manager Ownership

Every installed application or tool must have one clear update owner.

Examples:

- Fedora/RPM Fusion package -> DNF
- Flatpak -> Flatpak
- development environment -> Nix/devenv
- direct upstream artifact -> repository version metadata
- container/service image -> Podman/project configuration

Avoid competing ownership where multiple package managers or self-updaters try
to manage the same installation.

Document deliberate exceptions.

---

# 6. Supply-Chain Security

Every externally downloaded artifact must be treated as untrusted until
verified.

Direct artifacts must have:

- authoritative upstream source
- HTTPS
- explicit version
- supported architecture
- cryptographic checksum or trusted signature
- bounded download timeout
- temporary staging
- verification before installation
- deterministic expected contents
- safe failure behavior

Do not use:

- random mirrors
- unofficial repacks presented as official
- unchecked binaries
- mutable `latest` URLs when versioned artifacts exist
- disabled GPG verification merely to make installation succeed
- `curl | sh` where a safer supported mechanism exists

Checksum verification authenticates bytes against repository metadata; it does
not by itself establish that the original upstream source is trustworthy.
Source provenance must also be reviewed.

---

# 7. Archive Safety

Verified archives are still untrusted structured input until safely inspected
and extracted.

Archive provisioning must be deterministic.

Do not:

- blindly extract dangerous paths
- permit archive traversal outside staging
- allow archive contents to overwrite arbitrary filesystem paths
- follow unexpected archive symlinks into external locations
- search an archive for "any executable" and install whichever file happens to
  be found first

Expected archive members must be explicit whenever practical.

If an expected binary/member is missing:

> Fail.

Do not guess.

Extraction must remain inside installer-owned temporary staging.

---

# 8. Privilege Model

Use the least privilege required for each operation.

The installer itself is expected to run as the normal target user and elevate
specific host mutations through sudo.

Root privileges are appropriate only for operations that genuinely require
them, such as narrowly scoped writes to:

- `/etc`
- `/usr/local`
- `/var/lib`
- package management
- system service configuration

User-level operations must genuinely execute as the target user.

Changing only:

- `HOME`
- `USER`

does not change process identity.

`run_as_target_user` must verify effective identity using UID-based mechanisms
and fail closed when a required user transition cannot be performed.

Environment-variable spoofing must never bypass identity checks.

Never use broad recursive ownership repair against `$TARGET_HOME`.

In particular avoid:

```text
chown -R
chmod -R
```

against a user's home directory.

---

# 9. User Data Safety

User data is more important than installer convenience.

Every configuration target should conceptually belong to one of:

* PROJECT-OWNED
* USER-OWNED
* SYSTEM-OWNED
* GENERATED

## Project-Owned

Deterministic replacement or repository-managed symlinking is acceptable when
the project explicitly owns the path.

## User-Owned

Preserve deliberate user configuration.

Do not silently destroy unknown content.

Merge only when the format and semantics make safe merging well-defined.

## System-Owned

Prefer narrowly scoped managed files or drop-ins.

Avoid replacing broad distribution-owned configuration files.

## Generated

Generated state must be reproducible or safely regenerable.

---

# 10. Filesystem Safety

Filesystem mutations are security-sensitive.

All paths must be quoted.

Before destructive or replacement operations:

* reject empty paths
* reject unexpected relative paths where absolute paths are required
* reject `/` where inappropriate
* validate expected managed namespaces
* consider symlink behavior
* ensure the target belongs to the intended owner

Never assume:

```text
rm -rf "$VARIABLE"
```

is safe merely because the variable is quoted.

The variable itself must first be proven safe.

Avoid broad destructive operations whenever a narrower operation exists.

---

# 11. Symlink Safety

Managed symlinks must not become a path for accidental user-data destruction.

Distinguish between:

* replacing a project-owned symlink
* replacing an arbitrary existing file/directory

Existing non-managed content must follow explicit repository policy, such as:

* preserve
* back up
* refuse

Do not silently delete unknown user files.

Avoid following unexpected symlink chains during privileged writes.

---

# 12. Temporary Files

Use safe temporary locations.

Prefer `mktemp`.

Do not use predictable temporary filenames.

Only clean up paths created by the installer.

Temporary resources should be cleaned on:

* normal completion
* handled failure
* interruption

where doing so is safe.

Never make cleanup broad enough to delete unrelated data.

---

# 13. Idempotency

Installer operations must be safe to repeat.

A second successful run should converge toward the same desired state.

Repeated execution must not:

* duplicate repository entries
* duplicate configuration lines
* duplicate environment variables
* duplicate service configuration
* repeatedly create unnecessary backups
* destroy user modifications outside explicitly managed paths
* change ownership broadly
* create inconsistent partial state

Before performing mutation, prefer detecting whether desired state is already
satisfied.

---

# 14. Installer Lifecycle

The login/session architecture follows:

```text
PREPARE
   ->
VALIDATE
   ->
ACTIVATE
```

Preparation must not prematurely activate graphical login infrastructure.

Login-critical prerequisites must validate before activation.

greetd must remain next-boot activation unless repository architecture is
explicitly changed after review.

Do not casually introduce:

```text
systemctl enable --now greetd
```

during preparation.

If login validation fails, graphical activation must remain blocked.

---

# 15. Failure Classes

Preserve these conceptual classes:

## ACTIVATION-CRITICAL

Failure means graphical activation is unsafe.

These failures block activation.

## WORKSTATION-REQUIRED-BUT-NONBLOCKING

The workstation is incomplete, but graphical login itself remains safe.

These failures must be reported but must not structurally prevent safe
activation.

## OPTIONAL / DEFERRED

Failure is recorded and reported without breaking otherwise valid installation.

Do not turn optional application failures into login-critical failures.

Do not downgrade genuine login-critical failures merely to make the installer
finish successfully.

---

# 16. Exit Semantics

Preserve the established installer exit model unless explicitly redesigned:

* `0` -> successful
* `1` -> required or login-critical failure
* `2` -> optional/deferred work only

Exit code `1` alone does not necessarily mean graphical activation was blocked.

Activation state and installer completion state are related but distinct.

---

# 17. External Operation Timeouts

Network and external operations must be bounded.

This includes, where applicable:

* DNF metadata
* DNF package transactions
* repo queries
* downloads
* Git operations
* Flatpak operations
* Nix operations
* upstream release checks

Do not permit indefinite hangs.

Timeout errors must remain distinguishable from:

* package unavailable
* ordinary command failure
* successful empty result

Do not hide meaningful failures behind `|| true`.

---

# 18. Interrupt Safety

Ctrl+C and termination handling are correctness requirements.

SIGINT handling must:

* terminate active bounded child work
* avoid orphan timeout processes
* perform safe cleanup
* preserve expected exit status (`130` for SIGINT)

SIGTERM should similarly preserve appropriate termination semantics.

Signal handling must not accidentally keep the installer alive after the user
requested termination.

---

# 19. Concurrency

Concurrent installer executions are unsafe.

The installer must use a real exclusive process lock.

Concurrency protection is a safety invariant.

Therefore:

> If locking is required but a safe locking mechanism cannot be established,
> fail closed before significant mutation.

Do not merely warn and continue without locking.

Lock state must:

* not permanently block future runs after process death
* not require deleting another active process's lock
* be safe on multi-user systems
* avoid trusting arbitrary unsafe temporary locations
* be covered by tests

---

# 20. Fedora Platform Guards

Validate supported platforms before significant mutation.

At minimum verify:

* distribution
* supported Fedora release
* architecture
* required safety utilities
* required package-management primitives

Unsupported environments should fail early and clearly.

Do not partially install before discovering that the platform is unsupported.

---

# 21. Repository Configuration

Every third-party repository must have:

* concrete need
* authoritative owner
* HTTPS
* signature verification where supported
* deterministic configuration
* idempotent setup
* bounded metadata operations
* explicit failure classification

Do not disable GPG verification merely to make a repository work.

---

# 22. Package Manifests

Every host package must have a concrete workstation capability reason.

Avoid:

* duplicate packages
* obsolete package names
* unnecessary services
* accidental development toolchains
* package/application duplication across ownership systems
* architecture-specific packages without guards

"Bloat-free" means:

> No package without a justified workstation capability.

It does not mean minimizing package count at the expense of functionality.

---

# 23. Validation

Validation should verify capabilities, not blindly equate package names with
command names.

A package may provide a differently named executable.

Login-critical validation must prove the graphical-login path is usable.

Workstation validation must distinguish required and optional capability
failures without incorrectly blocking graphical activation.

---

# 24. Observability

Installer output and journal state should make it possible to determine:

* what stage ran
* what was already satisfied
* what changed
* what failed
* why it failed
* what was deferred
* what was skipped
* whether graphical activation was blocked
* whether graphical activation occurred
* final installer classification

Never write passwords, authentication tokens, or secrets to logs.

---

# 25. Shell Architecture

Bash is appropriate for:

* installer orchestration
* package operations
* Fedora integration
* service preparation
* simple configuration deployment
* bounded command execution
* validation wrappers

Bash must not gradually become a custom application framework.

If code begins requiring:

* complex structured-data transformation
* sophisticated state machines
* dependency resolution
* complex migration engines
* large custom parsers

re-evaluate whether that responsibility belongs in Bash.

Do not rewrite Bash into another language merely because another language might
look cleaner.

Require a concrete safety or complexity justification.

---

# 26. Module Architecture

`install.sh` should primarily orchestrate stages.

Business logic belongs in capability modules.

Shared libraries should contain genuinely reusable mechanisms.

Do not move unrelated functionality into `common.sh` merely to make another
file shorter.

As the project grows, prefer coherent domains such as:

```text
modules/
    ...

modules/lib/
    output.sh
    execution.sh
    filesystem.sh
    packages.sh
    artifacts.sh
```

only when actual responsibilities justify the split.

These names are architectural examples, not mandatory structure.

Avoid both extremes:

* one enormous shared helper file
* dozens of tiny one-function files

Optimize for clear ownership and few reasons to change per module.

---

# 27. Dotfile Architecture

Dotfiles must remain maintainable as features grow.

Where applications provide native include/import mechanisms, prefer composition
for genuinely independent concerns.

Examples may include:

* environment
* monitors
* input
* startup
* keybindings
* window rules
* appearance

Do not create custom loaders solely for modularity.

Do not fragment small configuration files unnecessarily.

Preserve native application semantics.

---

# 28. Test Architecture

The repository must retain one simple test command:

```bash
./tests/run.sh
```

However, the runner itself must not become an ever-growing god file.

As test domains grow, prefer:

```text
tests/
    run.sh
    ...
```

with coherent test modules underneath it.

Possible domains include:

* common primitives
* execution/privilege
* filesystem safety
* installer lifecycle
* state/concurrency
* packages
* applications
* supply chain
* XDG
* desktop/login
* validation
* resilience

These are examples, not mandatory filenames.

Tests must remain:

* deterministic
* isolated
* fast where practical
* independent of live workstation mutation

Use temporary sandboxes and mocks for mutation-heavy behavior.

Tests must include negative/failure cases for safety invariants.

---

# 29. Testing Claims

Do not claim more than tests prove.

For example:

Passing isolated idempotency tests does not prove complete end-to-end installer
idempotency unless an actual integration rerun was performed.

Likewise, source inspection does not prove runtime behavior when runtime
behavior materially matters.

Reports must distinguish:

* code-inspected property
* unit-tested property
* integration-tested property
* assumption
* remaining risk

Never describe an unexecuted integration scenario as verified.

---

# 30. Change Discipline

Before implementing a structural change, ask:

> What concrete problem does this solve?

Do not implement changes whose only justification is:

* cleaner
* more enterprise
* might be useful later
* more abstract
* theoretically reusable

Prefer the smallest change that fixes the demonstrated problem while leaving a
clear architecture for future extension.

---

# 31. Safe Development Rules for the Current Fedora VM

The current Fedora 44 VM is both the development environment and the project's
current integration-test workstation.

During ordinary implementation, audit, or refactoring tasks:

DO NOT:

* run `./install.sh`
* reboot
* power off
* restart greetd
* modify graphical activation
* change the default systemd target
* install/remove packages merely for experimentation
* modify repositories merely for experimentation
* modify live PAM configuration
* modify live greetd configuration
* modify active Hyprland/Noctalia configuration merely for testing
* modify active Nix state
* modify active Podman state
* modify storage
* install GPU drivers
* overwrite unrelated user configuration

These operations require an explicit integration-validation instruction from the
user.

Safe implementation work includes:

* repository inspection
* repository editing
* public authoritative research
* read-only host inspection
* `bash -n`
* repository tests
* isolated/mocked tests
* shellcheck when already installed
* Git commits

---

# 32. Integration Validation

A real installer execution is a distinct phase from implementation.

Do not run it merely because unit tests pass.

Before recommending a real run:

* tests must pass
* syntax checks must pass
* critical safety findings must be resolved
* direct artifact provenance must be acceptable
* login-critical architecture must remain intact

Integration results must be reported separately from unit-test results.

---

# 33. Known Separate Investigation

The Noctalia/greetd login-screen pointer initial position/orientation issue is a
separate investigation.

Do not introduce speculative pointer warps, sleeps, ydotool/wtype/xdotool
automation, or unrelated compositor hacks during general architecture work.

A change for that issue requires dedicated root-cause investigation.

---

# 34. Existing Important Invariants

Do not regress established behavior including:

* Fedora 44 workstation target
* Hyprland
* greetd
* Noctalia
* next-boot graphical activation
* activation blocking only for login-critical failures
* installer exit classification
* bounded timeout behavior
* correct SIGINT handling
* UID-based target-user execution
* fail-closed privilege switching
* XDG standard user-directory initialization
* preservation of custom XDG mappings
* deliberate English XDG baseline for fresh configuration
* Neovim managed configuration
* keyring/PAM integration
* Cursor Wayland integration
* Ulaa
* ChatGPT integration
* host-global media CLI ownership
* pinned direct media utilities
* Antigravity integration
* Flatpak
* Nix/devenv development ownership
* rootless Podman ownership
* package-provider-aware validation

---

# 35. Required Verification Before Commit

For shell changes, run the repository test suite:

```bash
./tests/run.sh
```

Run syntax validation across every shell script in the repository.

Do not assume only top-level or `modules/*.sh` files exist.

A safe pattern is:

```bash
find . -type f -name '*.sh' -print0 |
    xargs -0 -r bash -n
```

Run shellcheck when it is already installed.

Do not install shellcheck merely for verification.

Do not commit a change whose relevant tests are failing.

---

# 36. Commit Discipline

Keep commits coherent.

Prefer independently reviewable commits for independent concerns.

Do not create dozens of artificial micro-commits.

Do not combine unrelated architectural changes into one opaque commit.

Do not push unless explicitly instructed.

---

# 37. Final Reporting Requirements

After implementation work, report:

* starting branch and SHA
* findings addressed
* files changed
* architectural changes
* safety implications
* tests added/changed
* exact pass/fail count
* syntax-check result
* shellcheck result if available
* commits created with full SHAs
* final HEAD
* remaining risks
* whether `./install.sh` was run
* whether packages were modified
* whether live user configuration was modified
* whether systemd/greetd state was modified
* whether the VM was rebooted

Never claim a property is fully verified when only static inspection or isolated
tests support it.

---

# 38. Contributor Rule of Thumb

When adding a new workstation capability, determine in this order:

1. Who owns it: Fedora, Flatpak, Nix/devenv, Podman, or pinned upstream artifact?
2. Is it stable?
3. Is the source authoritative?
4. Can installation be verified?
5. Is the operation idempotent?
6. What privilege does it require?
7. What user/system data can it touch?
8. What happens if it fails halfway?
9. Is it login-critical, workstation-required, or optional?
10. How is it updated?
11. How is it validated?
12. How is it tested without damaging the live workstation?
13. Does adding it make an existing module responsible for too many unrelated things?

If these questions do not have clear answers, the capability is not ready to be
added.

---

# Final Standard

The repository should be:

> SAFE
> STABLE BY DEFAULT
> BORING TO OPERATE
> PREDICTABLE
> IDEMPOTENT
> OBSERVABLE
> MODULAR
> EASY TO UNDERSTAND
> EASY TO TEST
> EASY TO EXTEND
> HARD TO MISUSE
> HARD TO BREAK

The objective is a modern Fedora Hyprland workstation that stays current on
stable software without becoming a bleeding-edge experiment or an
unmaintainable collection of shell scripts and dotfiles.

```
