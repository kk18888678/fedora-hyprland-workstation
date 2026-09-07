# Full platform lifecycle and ownership

This document covers the lifecycle around the long-lived shell. The shell
itself is described in [01-runtime-architecture.md](01-runtime-architecture.md)
through [10-external-tool-contract.md](10-external-tool-contract.md); this file
describes how the rest of the distribution installs, starts, updates, repairs,
and resynchronizes it.

The reference is not just a QML desktop. It is a layered platform with a
package payload, root-side setup, user seeding, user finalization, a graphical
first-run sequence, a compositor session, and a controlled update path.

## Lifecycle graph

```text
repository source
      |
      +--> runtime package: bin/, install/, migrations/, themes/, shell/
      +--> settings package: /etc/skel, /etc drop-ins, vendor defaults, fonts
      |
      v
root target application
  config -> hardware -> login -> post-install
      |
      +--> static defaults in /etc/skel
      +--> optional deferred-provisioning marker
      |
      v
user finalization
  skills -> XDG dirs/bookmarks -> user/all.sh -> applications/defaults
      |
      v
graphical first run
  hooks -> user units -> desktop settings -> welcome/network notices
      |
      v
Hyprland session
  import environment -> launch shell -> remaining session helpers
      |
      v
steady state
  shell IPC, menu, plugins, themes, capture, agents, updates
```

The generic names above map to the reference as follows:

| Generic responsibility | Reference source | Reference installed owner |
|---|---|---|
| Runtime command and shell payload | `bin/`, `shell/`, `themes/`, `migrations/` | runtime package under `/usr/share/omarchy` and `/usr/bin` |
| Static user seed | `config/`, `default/`, `applications/` | settings package under `/etc/skel` |
| Root setup orchestration | `bin/omarchy-apply-system` | root, target/chroot |
| Root capability phases | `install/config/all.sh`, `install/hardware/all.sh`, `install/login/all.sh`, `install/post-install/all.sh` | root |
| User finalization | `bin/omarchy-provision-user`, `install/user/all.sh` | target user |
| Graphical first run | `bin/omarchy-provision-first-run`, `install/user/first-run/` | target user/systemd --user |
| Session entry | `default/hypr/autostart.lua`, `bin/omarchy-launch-shell` | Hyprland session |
| Updates and migrations | `bin/omarchy-update`, `bin/omarchy-migrate`, `migrations/` | user command with narrow root helpers |

## Package and ownership boundaries

Keep one owner for each artifact. The reference separates the package that must
exist before a user is created from the package that is installed into the
target runtime:

- The settings layer owns `/etc/skel`, `/etc` drop-ins, package-owned vendor
  defaults, systemd unit files, fonts, branding, login-manager assets, and the
  source files needed before the runtime package is present.
- The runtime layer owns the `omarchy-*` commands, shell QML, first-run/install
  scripts, migrations, themes, and runtime helpers.
- The user owns `~/.config/omarchy/` customizations: shell layout, plugins,
  themes, hooks, and template overrides.
- Generated active state belongs under
  `~/.local/state/omarchy/current/`; it is not the user’s editable theme source.

Do not make the shell install arbitrary plugin dependencies at startup. Package
or provision dependencies in the platform layer; optional UI integrations must
collapse or report unavailable capability when their external command is absent.

## Root-side application

`omarchy-apply-system` is root-only and refuses a missing or root target user
unless `--defer-provisioning` is selected. It exports the target path, install
path, install user, first-install/upgrade flags, log path, and runtime `PATH`,
then runs the phases in this exact order:

1. `install/config/all.sh` — system configuration and services.
2. `omarchy-apply-hardware` — hardware detection, packages, modules, and
   hardware-specific configuration.
3. `install/login/all.sh` — the SDDM/login surface.
4. `install/post-install/all.sh` — package, udev, and local database cleanup.

The common logging helper writes `/var/log/omarchy-install.log` unless the
caller requests stdout. Each leaf is run as `bash -eE` with a “Starting”,
“Completed”, or “Failed (exit code)” record. Debug mode changes the leaf runner
to `bash -x -eE`; it does not change ownership or lifecycle order.

The root phase does not start the graphical shell. This preserves the invariant
that root preparation and login activation are separate states.

### Deferred provisioning

When there is no target user, the root phase records group grants under
`/var/lib/omarchy/provisioning/groups` and leaves
`/var/lib/omarchy/provisioning/pending`. The first-boot owner provisioner runs
on tty1, asks for the owner, creates the account, finalizes it offline, performs
any encrypted-install key handoff, and then yields to the login manager.

The first-boot form uses the same logo, prompt palette, and validation source as
the installer form. It measures the logo at 81 columns and uses a target of
approximately 48 terminal rows when choosing a console font, while refusing a
font that would wrap the logo. Its progress bar is 34 cells wide; tips rotate
every 8 seconds. These are console-provisioning dimensions, not shell QML
dimensions.

## User seed, finalization, and first run

### Static seed

`/etc/skel` is copied by user creation. It carries static configuration and
launchers. Replaying it is not a harmless “refresh”: the explicit
`omarchy-reinstall-configs` command copies `/etc/skel/.` over the existing home
and is intentionally destructive to files it owns.

### User finalization

`omarchy-provision-user` is user-only and has the marker
`~/.local/state/omarchy/done/finalize-user`. Unless forced, a completed marker
short-circuits the sequence. It then:

- creates six skill roots and symlinks every directory under
  `<root>/default/agents/skills/` into the generic agent roots, Claude, Codex,
  Pi, Antigravity, and Hermes; existing Hermes profile roots receive the same
  links;
- creates `Downloads`, `Pictures`, `Videos`, and a GTK bookmarks file, while
  folding `Templates`, `Public`, and `Desktop` back into `$HOME`;
- sources `install/user/all.sh`, which applies the theme, Chromium, Git,
  xcompose, mise, keyring, and user hardware leaves;
- rebuilds generated application launchers and sets the browser and mailto
  defaults;
- on first install, marks the shipped migrations complete for the freshly
  created account.

The skill links are deliberately symlinks rather than copies. A development
checkout can therefore become the source of truth without rebuilding every
user’s skill tree.

### Graphical first run

`omarchy-provision-first-run` uses
`~/.local/state/omarchy/done/first-run-user`. It first attempts user
finalization, then runs each of these as an independently logged step:

- install the Voxtype, fingerprint, and default-agent post-update hooks;
- enable and start the shipped user units;
- apply GNOME theme and GTK primary-paste settings;
- apply speaker tuning;
- wait for the notification server, then show welcome and network/update
  notices.

Failures are logged but do not write the first-run marker. The sequence retries
on the next login. This is different from the one-shot leaf marker
`finalize-user`.

The user units are enabled only once a real user manager and graphical session
exist. The first-run helper runs `systemctl --user daemon-reload` followed by
`systemctl --user enable --now` for Bluetooth pairing, sleep locking, migration
notices, Fcitx, crash watching, and monitor recovery. Hardware conditions in the
unit files make inapplicable units inert.

## Session startup

On `hyprland.start`, the reference does these actions in order:

1. import the complete session environment into the user systemd manager;
2. update the DBus activation environment;
3. launch the shell supervisor;
4. start first-run provisioning;
5. initialize power profiles;
6. launch the monitor watcher;
7. launch `udiskie --automount --no-notify --no-tray`;
8. after a 2-second delay, run post-boot hooks.

The shell supervisor starts:

```text
QS_DISABLE_FILE_WATCHER=1
QS_NO_RELOAD_POPUP=1
systemd-cat -t <shell-tag> -- quickshell -n -p "$OMARCHY_PATH/shell"
```

It keeps the shell’s stderr/stdout in the journal. It treats a clean shell exit
as deliberate, retries a non-zero exit only while the compositor is alive, waits
1 second between retries, and gives up after more than 5 relaunches in a
60-second window. HUP, INT, and TERM terminate the child and stop supervision.

The restart command kills every matching shell instance with a 5-second bound,
launches the replacement through Hyprland so it inherits the canonical session
environment, waits up to 2 seconds for shell IPC readiness, and preserves a
secure session lock by re-locking it when necessary. It refuses to restart a
currently secure lock client.

## Normal update lifecycle

The blessed update command has a deliberately visible, ordered pipeline:

```text
transcript logging
  -> exclusive update lock
  -> free-space gate
  -> confirmation / unattended flag
  -> package-cache prune
  -> filesystem snapshot
  -> sleep + idle inhibition
  -> dev-checkout update
  -> keyring update
  -> system package transaction
  -> per-user migrations
  -> post-update hooks
  -> AUR packages
  -> mise tools
  -> orphan review
  -> update-log analysis
  -> shell update indicator
  -> release inhibition
  -> restart/reboot decisions
```

Exact reference details:

- The transcript is `/tmp/omarchy-update.log`, created by `script -qefc`.
- The lock is `${XDG_RUNTIME_DIR:-/tmp}/omarchy-update.lock`, held by an open
  file descriptor exported as `OMARCHY_UPDATE_LOCK_FD`. Lock ownership is
  checked by descriptor path and `flock`, not by a stale PID file.
- The free-space gate is 10 GiB on `/`; it is bypassed only by the explicit
  `OMARCHY_UPDATE_FORCE=1` override. An indeterminate free-space query skips
  the gate rather than claiming a measurement.
- Cache pruning keeps two package versions before the snapshot.
- Snapper absence returns the sentinel status 127 and allows the update to
  continue without a snapshot; a configured Snapper failure is reported and
  also does not masquerade as a successful snapshot.
- `-y` exports `OMARCHY_UPDATE_UNATTENDED=1`; any later step that needs a human
  skips or reports instead of hanging for input.
- The stay-awake helper uses both a systemd inhibitor and the shell’s idle
  state. It records process start time so cleanup cannot kill a recycled PID,
  and it restores only the idle state it changed.
- The system package step uses `OMARCHY_UPDATE_PACMAN=1` and package-owned
  overwrite rules. A failed transaction enters the separate conflict handler;
  it does not silently continue as if the package state were current.
- Migrations run after the package transaction and record one marker per
  migration under `~/.local/state/omarchy/migrations/`.
- The shell is restarted at the end so a package update cannot leave old QML
  code lazily loading a new file tree.

The update command has an ERR message and an EXIT cleanup for the inhibitor.
It explicitly stops and removes the EXIT trap before a confirmed reboot so a
reboot cannot interrupt cleanup halfway through.

## Migrations and direct package updates

`omarchy-migrate --pending` prints missing migration filenames and exits 0 when
any exist; it prints nothing and exits 1 when none exist. Normal execution waits
up to 900 seconds for `/var/lib/pacman/db.lck` to disappear, runs each missing
migration with `bash -euo pipefail`, then touches its per-user marker.

An ALPM pre-transaction hook detects direct system upgrades. It allows the
blessed environment marker, aborts ordinary direct upgrade attempts before
package mutation, and tells the user to use the full update command. An explicit
`OMARCHY_ALLOW_DIRECT_PACMAN=1` escape exists for experienced operators. A
login-time migration notifier is the fallback for a user who bypassed the
blessed flow; it prompts but never runs migrations in the background.

## Theme, plugin, and shell state during updates

The update pipeline does not deep-merge new shell defaults into a customized
`shell.json`. A user’s layout remains authoritative until the user explicitly
runs the shell refresh command. Package updates replace first-party source and
then restart the shell; user plugins remain in the user plugin directory and
are rescanned by the new host.

Theme selection and plugin updates are separate user operations. Theme sources,
generated active theme files, and plugin checkouts each have distinct owners;
see [12-full-plugin-lifecycle.md](12-full-plugin-lifecycle.md) and
[15-theme-wallpaper-and-cross-app-sync.md](15-theme-wallpaper-and-cross-app-sync.md).

## Refresh, recovery, and reset semantics

The narrow shell refresh does three things:

1. copy the shipped `omarchy/shell.json` into the user config through the
   generic config refresher;
2. reset the bar layout to defaults;
3. restart the shell.

The generic config refresher makes a timestamped `.bak.<epoch>` only when a
user file exists, removes the backup when the bytes are identical, and prints a
diff when they differ. Full config reinstall is broader and destructive because
it replays `/etc/skel`.

The recovery model is therefore:

```text
bad user shell state       -> refresh shell (targeted backup)
bad packaged config        -> package/snapshot rollback or reinstall configs
bad migration               -> repair and rerun pending migration
bad plugin update           -> plugin fast-forward validation rollback
shell process failure       -> supervisor retry / explicit shell restart
secure lock in progress     -> refuse unsafe restart
```

Never make an optional application failure block graphical activation. Keep the
reference distinction between “login cannot safely proceed”, “workstation is
incomplete”, and “optional/deferred”.

## Source cross-check

The lifecycle above was read from:

```text
bin/omarchy-apply-system
bin/omarchy-apply-hardware
bin/omarchy-provision-user
bin/omarchy-provision-owner
bin/omarchy-provision-first-run
bin/omarchy-launch-shell
bin/omarchy-restart-shell
bin/omarchy-update
bin/omarchy-update-lock
bin/omarchy-update-stay-awake
bin/omarchy-migrate
bin/omarchy-migrate-notify
bin/omarchy-reinstall-configs
bin/omarchy-refresh-config
default/hypr/autostart.lua
install/config/all.sh
install/hardware/all.sh
install/login/all.sh
install/post-install/all.sh
install/user/all.sh
install/user/first-run/enable-user-units.sh
docs/file-layout.md
docs/update-process.md
```

These are source-inspected contracts. A live login, package transaction,
snapshot rollback, reboot, or hardware branch still requires integration
testing on the target platform.
