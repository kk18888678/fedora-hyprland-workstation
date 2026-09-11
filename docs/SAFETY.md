# Workstation Safety & Security Engineering

This document specifies the safety invariants, privilege policies, data protection rules, and failure classification model enforced by the Fedora Hyprland Workstation installer.

---

## 1. Privilege Boundaries & Least Privilege

The installer adheres strictly to the principle of least privilege:

- **Non-Root Execution**: `install.sh` must be executed as the normal workstation user (`$TARGET_USER`), never directly as `root`. Running as root risks deploying user configurations and dotfiles with root ownership.
- **Sudo Scoping**: `sudo` is used only for specific host-level operations (e.g. writing `/etc/greetd/config.toml`, installing RPMs via `dnf`, enabling systemd system units, managing `/var/lib/noctalia-greeter`).
- **Target User Transitions (`run_as_target_user`)**:
  - Production privilege transitions use genuine UID matching or `sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" USER="$TARGET_USER" "$@"`.
  - `OVERRIDE_EUID` and `OVERRIDE_TARGET_UID` are test-fixture controls only; the production entry point ignores them.
  - Repository-path, parser, and reconciler mock overrides are likewise restricted to `WORKSTATION_TEST_MODE=1`; production runs use fixed repository paths, the system `jq`, and registered lifecycle callbacks.
  - The production entry point derives and validates `USER`/`HOME` from the real UID and passwd database rather than trusting their environment values.
  - If a required user transition cannot be performed safely, the installer **fails closed**.
  - Generic target-user commands inherit the caller's active locale without global `LC_ALL` pollution.

---

## 2. User Data & Configuration Safety

Configuration targets are strictly categorized:

| Category | Policy |
| --- | --- |
| **Project-Owned** | Managed symlinks (e.g. `~/.config/hypr` -> `dotfiles/hypr`, `~/.zshrc`). If a non-symlink file or directory pre-exists, it is moved to a timestamped `.bak` backup before symlinking. |
| **User-Owned** | User directories and files (e.g. `~/.config/user-dirs.dirs`, `~/.config/nix/nix.conf`, documents in `~/Documents`). Existing custom entries are parsed safely and preserved; settings are merged without wiping custom configurations. |
| **System-Owned** | Distro system configuration files. Replaced or created only with minimal drop-ins (e.g. `/etc/greetd/config.toml`). |
| **Generated** | Logs and journals in `/var/lib/fedora-hyprland-workstation/`. |

### Prohibited Operations
- **No recursive home chowning**: `chown -R` against `$TARGET_HOME` is prohibited.
- **No blind deletions**: `rm -rf` against unvalidated or user-controlled paths is prohibited.
- **Rootless container isolation**: subordinate UID/GID files are parsed and
  allocated ranges are checked for overlap before Podman setup; malformed
  tables fail closed instead of using a fixed shared range.
- **Path guards**: `ensure_directory` and `ensure_symlink` require absolute, validated paths, reject `.` / `..` and symlinked parent components, and preserve an existing file, directory, or unknown symlink as a timestamped backup before replacement.
- **XDG configuration path**: A custom `XDG_CONFIG_HOME` is honored for the session-shell selector only after absolute-path, ownership, and symlink-component checks; unsafe overrides fail closed.
- **Deterministic archive extraction**: Upstream archives must have explicitly declared binary members. Pre-extraction structural checks reject path traversal (`../`) and absolute paths (`/`). Post-extraction checks verify symlinks do not escape the staging sandbox. Verified members are published through unique sibling staging with rollback for multi-binary sets; unverified executable guessing or fallback is prohibited.
- **Pinned artifact reruns**: Directly installed binaries are checked against root-owned provenance manifests containing the pinned source checksum and installed file digests. Missing or mismatched provenance causes re-verification rather than accepting an executable merely because it exists.

---

## 3. Failure Classification

Failures are recorded into three distinct severity classes:

```mermaid
graph TD
    F[Installer Operation Failure]
    F -->|Critical for graphical login| LC[LOGIN-CRITICAL]
    F -->|Required workstation feature| RQ[WORKSTATION-REQUIRED]
    F -->|Optional application/tool| DF[DEFERRED / OPTIONAL]

    LC -->|Sets ACTIVATION_BLOCKED=1| NB[Blocks greetd Activation<br/>Final Exit Code 1]
    RQ -->|Activation still eligible| AB[Permits greetd Activation<br/>Final Exit Code 1]
    DF -->|Non-blocking| OK[Permits greetd Activation<br/>Final Exit Code 2]
```

1. **LOGIN-CRITICAL (`record_activation_failure`)**:
   - Hyprland compositor, greetd, noctalia-greeter, polkit agent, desktop portals, PAM keyring module.
   - Blocks graphical login activation (`ACTIVATION_BLOCKED=1`).
   - Prevents an unbootable graphical state.
2. **WORKSTATION-REQUIRED (`record_required`)**:
   - Base CLI utilities, Chromium, Zsh/Starship, Nix daemon, rootless Podman.
   - Does not block graphical login if the login stack itself is intact.
   - Yields exit code 1 to alert human maintainers/CI.
3. **DEFERRED / OPTIONAL (`record_deferred`)**:
   - Optional workstation applications (Cursor, ChatGPT, Kate, GUI media apps, media CLI tools, Antigravity CLI, Ulaa Flatpak, and user-adopted Aurelia binaries).
   - Safe to rerun; yields exit code 2.

---

## 4. Signal Handling, Timeouts & Concurrency

- **Bounded Execution**: Every network, package manager, and external download command is bounded via `run_with_timeout` with GNU `timeout --kill-after=10s`.
- **Signal Trapping**: `SIGINT` (130) and `SIGTERM` (143) are captured via traps, terminating all tracked child processes, preserving the installer lock through cleanup/final state handling, and terminating cleanly.
- **Concurrency Locking**: `install.sh` acquires an exclusive non-blocking `flock` on a private dynamic file descriptor using `/run/user/$EUID/fedora-hyprland-workstation.lock` (or fallback private `0700` directory `/tmp/.fhw-lock-$EUID/installer.lock` with foreign ownership and symlink rejection). If another installer process is active or `flock` is unavailable, it fails closed immediately with a clear error message. The lock is kernel-backed and automatically released if the process terminates or crashes.
- **Activation rollback**: Before enabling `greetd` or changing the default system target, the installer snapshots both states. If a later activation step fails, it restores the previous service-enable state and default target before reporting activation blocked.
