# Fedora Package Manager

The workstation package manager is a Fedora-native package browser and
desired-state synchronizer. It uses the Omarchy reference only for the
interaction pattern: a compact keyboard-driven selector, multi-selection, and
metadata preview. The TUI reads a last-known-good local catalog and does not
make network access part of opening the selector.

## Ownership

- DNF owns Fedora/RPM packages.
- Flatpak owns sandboxed applications and their runtimes.
- Aurelia owns explicitly adopted, user-local upstream release binaries.
- The package manager backend owns only packages explicitly adopted into the
  user-managed set.
- The Command Center is a launcher only; it does not execute package-manager
  mutations inside QML.

## Tracked state

`packages/user-managed.tsv` is the single tracked desired-state file for
user-adopted packages. DNF and Flatpak rows contain:

```text
provider<TAB>source<TAB>identifier<TAB>scope<TAB>profiles
```

Examples:

```text
dnf     fedora      ripgrep                       system  all
flatpak flathub     org.localsend.localsend_app   system  all
```

Aurelia rows append pinned upstream release metadata:

```text
aurelia github.com/bjarneo/cliamp cliamp user all v2.0.1 cliamp-linux-amd64 sha256:<digest> .local/bin/cliamp https://github.com/bjarneo/cliamp/releases/download/v2.0.1/cliamp-linux-amd64
```

The exact release, asset URL, SHA-256 digest, and target path are reviewed and
stored in Git. Aurelia does not run an upstream installer script, follow a
mutable `latest` binary URL, or silently update a pinned row.

The file is updated with an atomic replacement and never receives `.bak` or
other backup copies. Duplicate provider/source/identifier/scope rows fail
closed.

`packages/sources.tsv` is the single tracked source registry for Flatpak
remotes. Enabled DNF repositories are discovered from Fedora's configured
repository set; adding a DNF repository remains a reviewed installer change.
`packages/aurelia-sources.tsv` is the tracked registry of official GitHub
repositories allowed for stable release discovery. Adding a source performs a
bounded discovery first and refuses repositories without a stable,
architecture-matching raw binary and SHA-256 checksum.

## Catalog and search

The generated catalog is stored outside Git under the user's XDG cache
directory. Catalog schema 6 includes the package identity plus provider
metadata such as description, architecture, installed/download size where the
provider exposes it, license, URL, location/ref, runtime/source RPM,
capabilities, dependency metadata, release/build time, and NEVRA/commit
information. Multiline provider data is flattened only at the TSV serialization
boundary so it cannot corrupt records. Two generated sidecars keep the rich
catalog authoritative while providing a compact complete display and a fast
normalized search index.

DNF searches use normalized, case-insensitive package metadata and also index
DNF capabilities. This means searches such as `LibreOffice`, `libreOffice`,
`libre office`, and `libre_office` reach the same package rows. A command query
such as `edid-decode` resolves to the DNF package that provides that capability
(`v4l-utils`) instead of presenting an unrelated fuzzy match. If a capability
is not in the local index, a bounded cache-only DNF `whatprovides` lookup is
used as a fallback.

Search results collapse historical builds to the newest available build for
each provider/package identity and label it `LATEST`; use
`search --all-versions <query>` when historical builds are needed. DNF release
dates come from package build metadata. Flatpak's remote listing does not
expose a release date, so the UI explicitly shows that it is unavailable.
Provider size fields are rendered as human-readable values; when a provider
truly does not publish one, the UI says `n/a` (or `not provided` in the
metadata pane) instead of using a placeholder-looking dash.
For Aurelia, the GitHub release asset size is cached as download size, and the
metadata pane refreshes the installed size from the local binary when it is
already present.

The catalog is refreshed by a user-level background timer after boot and at a
configurable interval. Refresh is metadata-only: it never installs or upgrades
packages. Opening the TUI uses a valid current cache immediately; a stale,
schema-old, or provider-incomplete cache is refreshed in the foreground with
visible progress before search opens. `Ctrl-R` (or the configured refresh key)
performs an explicit refresh.

## Package states

The backend distinguishes:

- tracked and installed;
- tracked but missing;
- tracked but installed from a different or unknown source;
- installed but unmanaged;
- project-owned baseline packages.

DNF search is limited to the host architecture plus `noarch`, and the selected
architecture is passed to the install transaction. DNF repository rows remain
explicit: the transaction uses DNF5's `--from-repo` behavior, so the requested
package comes from the selected row while dependencies may resolve from the
other enabled repositories. Selecting an older base-repository row can still
conflict with a newer Qt or system stack; in that case choose the newer source
row instead of allowing a downgrade.

Unmanaged packages are reported but are never silently adopted or removed.
The TUI offers explicit Adopt and Remove actions. Normal removal does not use
Flatpak `--delete-data` and does not purge personal files.

## Commands

```text
workstation-packages open
workstation-packages status
workstation-packages refresh
workstation-packages catalog status
workstation-packages latest [query]
workstation-packages search --all-versions [query]
workstation-packages source list
workstation-packages daily enable
```

The Command Center exposes the same workflow as **Package Manager**. `open`
launches the dedicated terminal TUI, which can search DNF, Flatpak, and Aurelia
sources, preview metadata, install packages, adopt existing packages, remove
packages, manage sources, and enable or disable background catalog refresh.
The main search surface uses one full-width package list with the selected
package's metadata in a lower pane; navigation and action keys are shown in a
footer rather than consuming the result header.

The dedicated frontend is `aurelia-shell/bin/workstation-packages-tui`. It is a
standard-library Python terminal application with a responsive split view on
wide terminals and a stacked view on narrow terminals. The Bash
`workstation-packages` backend remains the only owner of package transactions,
tracking, cache preparation, and diagnostics. The frontend reads Aurelia's
active semantic theme files and never copies a fixed palette.

To add an upstream GitHub source from the command line:

```text
workstation-packages source add aurelia https://github.com/OWNER/REPOSITORY
```

The package manager displays the selected stable release and checksum before
asking for confirmation. After the source is added, the repository's package
appears in search as `aurelia`, with the GitHub repository shown explicitly as
its source. Selecting it and choosing to track it installs the verified binary
to `~/.local/bin/<repository-name>` and writes the complete Aurelia row to
`packages/user-managed.tsv`.

Background refresh only updates package metadata/catalog cache. It never
installs or upgrades packages. Cache and inventory state live outside Git under
the user's XDG cache/state directories. The timer is enabled automatically by
the installer as optional user-level workstation setup; it can also be enabled
or disabled from the TUI or with `daily enable`/`daily disable`.

## Configuration and key commands

Repository defaults live in `config/package-manager.conf`. A user may override
them at `~/.config/workstation/package-manager.conf`. The file is parsed as
data rather than sourced as shell, and malformed values fail closed.

The configuration controls catalog age/refresh policy, bounded DNF/Flatpak and
transaction timeouts, result limits, preview layout, colors, visual labels, and
all TUI keys:
movement, paging, selection, acceptance, cancellation, refresh, help, preview
scrolling, preview toggle, and select-all. The default TUI exposes the active
keys in its header and help overlay.

The catalog refresh lock is acquired only for the bounded refresh or mutation
itself. The interactive selector does not hold it while idle, so an invisible
refresh cannot make an installation fail with an unexplained concurrent-task
message.

## Reinstall behavior

The installer consumes DNF rows from `user-managed.tsv` after repository setup,
Flatpak rows after the declared remotes are configured, and Aurelia rows through
the verified upstream backend. User-added packages are optional/deferred work;
they cannot block safe graphical login. Aurelia restoration uses the pinned
asset and checksum already recorded in Git; daily catalog refresh can discover
new stable candidates but never rewrites those pins.

DNF and Flatpak versions are not pinned by this file: their source IDs are
preserved so a fresh `./install.sh --profile vm` or
`./install.sh --profile workstation` can restore the same package intent while
using current stable packages from the declared source. Aurelia rows are the
exception and pin the exact upstream release asset and digest for reproducible
restoration.

Direct RPMs, archives, AppImages, and upstream binaries that do not fit the
Aurelia GitHub raw-binary contract remain outside this catalog. They require
the repository's separate verified-artifact workflow with explicit version,
provenance, architecture, and checksum/signature.

Removing an Aurelia package removes only the owned `~/.local/bin` binary and its
private ownership marker. It does not purge personal data. Removing a source
is blocked while tracked packages still depend on it. Changes to either tracked
TSV are ordinary Git changes; the installer does not auto-commit or push them.
