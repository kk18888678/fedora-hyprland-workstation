# Fedora Hyprland Workstation

Idempotent installer for a **Fedora 44** machine running **Hyprland**, `greetd`, the Noctalia greeter, and a selectable Noctalia or Aurelia post-login shell.

## Requirements & Minimal Bootstrap

The installer requires:
- **Fedora 44** (Fedora Everything, Workstation, or Netinstall).
- A standard target user account with `sudo` administrative rights.
- Working internet connectivity.
- A local interactive TTY for setup selection and plan review.

### Bootstrap Prerequisite: Git

On a fresh or minimal Fedora installation, Git may not be installed. Install Git using Fedora's official package manager before cloning:

```bash
sudo dnf install -y git
```

> [!NOTE]
> **Bootstrap vs. Installer Ownership**:
> Installing `git` (and ensuring your user has `sudo` access) is the prerequisite required before cloning. After the installer starts, the reviewed base package group bootstraps utilities such as `curl` and `tar`; repository tooling, desktop packages, and system integrations are then installed through the normal plan and reconciler stages.

#### What if `git: command not found`?
If you encounter `git: command not found`, run:
```bash
sudo dnf install -y git
```
*Secondary Archive Fallback*: If you cannot use Git directly, you may download and extract an official GitHub repository archive tarball/zip (`tar -xzf ...`). However, cloning via Git is strongly recommended so you can easily pull updates, manage branches, and maintain desired-state reconciliation.

---

## Installation Flow

1. **Clone the repository** as your **normal user** (not root):
   ```bash
   git clone -b installer-resilience https://github.com/kk18888678/fedora-hyprland-workstation.git
   cd fedora-hyprland-workstation
   ```

2. **Choose and execute your profile command**:

   For **physical hardware workstations** (bare metal with Bluetooth/GPU):
   ```bash
   ./install.sh --profile workstation
   ```

   For **virtual machines** (QEMU/KVM/VirtIO GPU, no Bluetooth):
   ```bash
   ./install.sh --profile vm
   ```

   *(Note: The installer provides strictly these two public profile entry points).*

3. **What to expect during installation**:
   - The installer progresses through distinct stages: Preflight Validation -> Repository Trust -> Base/Desktop/Media Packages -> Display & Desktop Shell (Hyprland + selected shell + Noctalia greeter + greetd) -> System Integrations (Nix, Podman) -> Applications -> Verification -> Graphical Activation.
   - Re-running the installer after an interruption, network drop, or sudo timeout is safe and idempotent. Desired state lives in Git; installer journal files under `/var/lib/fedora-hyprland-workstation/` track progress and logs.

4. **Rebooting**:
   - Only reboot when the installer completes successfully (Exit code `0` or `2`) and outputs the summary indicating that graphical login is prepared for the next boot.
   - To preserve safe recovery, graphical activation is never forced onto an active live terminal; it activates on next reboot.


## What it installs

- Fedora 44 + Hyprland + Noctalia Greeter (`greetd` user, not `greeter`) + profile-selected post-login shell
- Zsh, Oh My Zsh, Starship, fzf, zoxide
- Chromium (required when enabled), Brave Origin, Firefox, and Ulaa (via Flathub Flatpak)
- Flatpak + Flathub, Fedora Nix + devenv, rootless Podman
- BlueZ Bluetooth support for the physical-workstation profile
- Host-global media utilities (`mpv`, `ffmpeg`, `mediainfo`, `mkvmerge`, `MP4Box`, `ccextractor`, `mp4dump`, `packager`, `dovi_tool`, `N_m3u8DL-RE`, `magick`)

## Target Architecture

The workstation maintains a strict separation of concerns:

- **Fedora Host**: Operating system, kernel, drivers, systemd, PipeWire, desktop session (Hyprland + selected Noctalia/Aurelia shell + Noctalia greeter + greetd), portals, fonts, system diagnostics, media codecs, normal GUI applications, Podman runtime, and base Nix installation.
- **Nix + devenv**: Reproducible development platforms, compilers, SDKs, project runtimes, language servers, and specialized CLI tooling.
- **Podman**: Isolated development services, databases, and containerized dependencies.
- **Git**: Reproducible desired state.

The Command Center also provides a Fedora/Flatpak/Aurelia **Package Manager**.
It searches configured sources, displays package provenance, and can explicitly
adopt or restore packages through the tracked `packages/user-managed.tsv`
desired state. See [the package manager documentation](docs/PACKAGE-MANAGER.md).

See detailed engineering documentation:
- [Architecture & Ownership](docs/ARCHITECTURE.md)
- [Safety & Privilege Model](docs/SAFETY.md)
- [Release & Supply-Chain Policy](docs/RELEASE-POLICY.md)

## Package Manifests

- `packages/base.txt`: Core OS utilities, shells, archive tools, networking, and audio foundations.
- `packages/desktop.txt`: Hyprland, Noctalia runtime/greeter packages, greetd, portals, terminal, file manager, and fonts.
- `packages/aurelia.txt`: Quickshell and Aurelia-only development watcher support, installed only when Aurelia is selected.
- `packages/bluetooth.txt`: BlueZ Bluetooth packages for profiles that enable physical-workstation Bluetooth.
- `packages/media.txt`: Codecs, GStreamer plugins, VA-API acceleration, MPV, FFmpeg, MediaInfo, MKVToolNix CLI, and ImageMagick (`magick`).
- `packages/diagnostics.txt`: Hardware, sensor, storage, process, and network diagnostics (`smartmontools`, `nvme-cli`, `inxi`, `htop`, `btop`, `iotop-c`, `sysstat`, `lsof`, `strace`, `duf`, `ncdu`, `btrfs-progs`).

## Workstation Applications

- **Kate**: Full-featured graphical text and code editor (Fedora official repositories).
- **Neovim**: Terminal code editor with managed configuration.
- **Cursor**: Official vendor RPM repository with Wayland Ozone flag integration.
- **ChatGPT**: Official vendor RPM repository.
- **Media Applications**: OBS Studio, MKVToolNix GUI, VLC.
- **Media CLI Utilities**: Host-global tools (`dovi_tool`, `N_m3u8DL-RE`, `packager`, `ccextractor`, `mp4dump`, `ffmpeg`, `mediainfo`, `mkvmerge`, `MP4Box`, `magick`).
- **Antigravity CLI (`agy`)**: Integrated user path with non-blocking activation safety.
- **LocalSend & Ulaa**: Flathub Flatpaks.

## Profiles

| Profile | File | Notes |
| --- | --- | --- |
| `vm` | `profiles/vm.conf` | Virtio GPU, no Bluetooth, Aurelia post-login shell by default, Noctalia greeter |
| `workstation` | `profiles/workstation.conf` | Generic GPU, Bluetooth enabled, Noctalia post-login shell by default |

Both set `DESKTOP=hyprland` and keep `INSTALL_GREETER=true` with Noctalia. The VM profile defaults to `DESKTOP_SHELL=aurelia`; the workstation profile defaults to `DESKTOP_SHELL=noctalia`. Choosing **Customize Workstation** lets you select either Noctalia or Aurelia; the choice is shown in the reviewed plan.

### Desktop shell sequence

The login and session shells are separate:

```text
Boot -> greetd -> noctalia-greeter-session -> login -> Hyprland
     -> profile-default or customization-selected session shell
```

The selected shell is recorded by the installer in the project-owned
`~/.config/fedora-hyprland-workstation/session-shell` symlink. Hyprland starts
only that shell, so the VM does not run both Noctalia and Aurelia as competing
desktop shells.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 2 | Setup cancelled with no changes, or completed with deferred optional work |
| 1 | Required component failed. Graphical activation is skipped only when the login stack is unsafe. |

## Troubleshooting

### 1. `git: command not found`
On minimal or netinst Fedora systems, Git is not included by default. Install it using DNF:
```bash
sudo dnf install -y git
```

### 2. `sudo: command not found` or User Lacks Sudo Rights
The installer is designed to run as your **normal user account** and elevate necessary system mutations (such as writing to `/etc` or installing RPMs) using `sudo`. It must **not** be invoked directly as root.
- If your user is not authorized in the `sudoers` file, an existing administrator or root user must grant your user administrative membership from an authorized root session (`su -`):
  ```bash
  usermod -aG wheel <username>
  ```
  *(Log out and back in for group membership to take effect).*
- If `sudo` is not installed on a minimal system, an existing administrator or root account must install and configure it:
  ```bash
  dnf install -y sudo
  usermod -aG wheel <username>
  ```
- Do not attempt privilege-bypass workarounds, and do not run the installer itself as root.

### 3. Clone or Network Failures
If `git clone` fails due to DNS issues, TLS handshakes, or GitHub reachability:
- Verify basic network access: `curl -I https://github.com`
- Check system clock/NTP synchronization (`timedatectl status`), as inaccurate system clocks cause TLS handshake failures.
- Retry the clone once network reachability is restored.
- **Never** disable Git SSL verification (`GIT_SSL_NO_VERIFY=true`) or TLS security settings.

### 4. `bash: ./install.sh: No such file or directory`
Ensure that you changed into the cloned repository directory before running the installer:
```bash
cd fedora-hyprland-workstation
```
You should see `install.sh` and the `modules/` directory when running `ls`.

### 5. `bash: ./install.sh: Permission denied`
The installer script has executable permissions by default (`-rwxr-xr-x`). If permissions were lost (for example, after extracting an archive):
- Restore execute permissions: `chmod +x install.sh`
- Or invoke it explicitly with Bash:
  ```bash
  bash ./install.sh --profile workstation
  ```
- **Never** run broad recursive permissions changes like `chmod -R 777`.

### 6. Unsupported Fedora Release or Wrong Distribution
The installer strictly targets **Fedora 44**. Platform guardrails verify the distribution ID and release version in `/etc/os-release` during preflight and fail closed if run on unsupported releases or other distributions. This prevents accidental partial mutation or system corruption.

### 7. Installer Already Running or Lock Conflict
The installer uses an exclusive process lock located at:
```text
/var/lib/fedora-hyprland-workstation/lock
```
If you receive an error that the installer is already running:
- Check if another installation process is active in another terminal (`pgrep -a -f install.sh`).
- Wait for the active run to finish.
- The process lock is automatically released upon normal completion, error, or termination. **Never** delete lock files manually while an installation may be active.

### 8. Network or Package Metadata Failure During Startup
If package downloads or DNF metadata refreshes fail:
- Check that another system update service (such as PackageKit or a background `dnf` transaction) is not holding the RPM database lock. Wait for background transactions to complete.
- Verify internet connectivity and repository accessibility.
- Re-run the installer; transactions are safe to retry and will resume from where they stopped.

### 9. Where Logs Are Stored
The installer records comprehensive step-by-step journals and error outputs. Logs for each run are saved to:
```text
/var/lib/fedora-hyprland-workstation/logs/install-<timestamp>-<unique>.log
```
You can inspect the most recent run log using:
```bash
logs=(/var/lib/fedora-hyprland-workstation/logs/install-*.log); less "${logs[-1]}"
```
Or check the last recorded status at:
```bash
cat /var/lib/fedora-hyprland-workstation/state/last-run
```

### 10. Understanding Exit Codes and Failure Classifications
At the end of an installer run, a status summary is printed:
- **`0` (Success)**: All required and optional capabilities were installed, validated, and prepared.
- **`2` (Deferred Optional Work)**: One or more optional applications (e.g. an unessential Flatpak or optional CLI tool) could not be provisioned, but all required system components, drivers, and the desktop environment are fully intact. Graphical login is safely configured.
- **`1` (Required Failure)**: A required workstation capability failed.
  > [!IMPORTANT]
  > **Exit code 1 does not necessarily mean graphical login was blocked**. The installer separates non-blocking capability failures from login-critical failures:
  > - If `ACTIVATION_BLOCKED=0`, graphical login remains safe to activate on next boot.
  > - If `ACTIVATION_BLOCKED=1`, a login-critical component (such as `greetd`, `noctalia-greeter`, or `Hyprland`) failed validation. Graphical activation is intentionally withheld to prevent locking you out of your workstation. Inspect the summary log, resolve the indicated issue, and re-run `./install.sh`.

## Local tests

```bash
./tests/run.sh
```
