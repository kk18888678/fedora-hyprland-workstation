# Fedora Package Manager

The workstation package manager is a Fedora-native package browser and
desired-state synchronizer. It uses the Omarchy reference only for the
interaction pattern: an `fzf` search list, multi-selection, and metadata
preview.

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
workstation-packages source list
workstation-packages daily enable
```

The Command Center exposes the same workflow as **Package Manager**. `open`
launches the terminal-owned TUI, which can search DNF, Flatpak, and Aurelia
sources, preview metadata, install packages, adopt existing packages, remove
packages, manage sources, and enable or disable daily catalog refresh.

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

Daily refresh only updates package metadata/catalog cache. It never installs or
upgrades packages. Cache and inventory state live outside Git under the user's
XDG cache/state directories.

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
