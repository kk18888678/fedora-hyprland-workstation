# Fedora Hyprland Workstation

Idempotent installer for a **Fedora 44** machine running **Hyprland** with the **Noctalia** desktop shell, `greetd`, and a standard workstation toolchain (Zsh, Nix/devenv, Podman, Flatpak, Chromium).

## Requirements & Minimal Bootstrap

The installer requires:
- **Fedora 44** (Fedora Everything, Workstation, or Netinstall).
- A standard target user account with `sudo` administrative rights.
- Working internet connectivity.

### Bootstrap Prerequisite: Git

On a fresh or minimal Fedora installation, Git may not be installed. Install Git using Fedora's official package manager before cloning:

```bash
sudo dnf install -y git
```

> [!NOTE]
> **Bootstrap vs. Installer Ownership**:
> Installing `git` (and ensuring your user has `sudo` access) is the **only** prerequisite required on the host before starting. All other dependencies, build tools, desktop packages, and system utilities (`curl`, `jq`, `tar`, `dnf-plugins-core`, etc.) are automatically verified, bootstrapped, and configured by the installer during its preflight phase.

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
   - The installer progresses through distinct stages: Preflight Validation -> Repository Trust -> Base/Desktop/Media Packages -> Display & Desktop Shell (Hyprland + Noctalia + greetd) -> System Integrations (Nix, Podman) -> Applications -> Verification -> Graphical Activation.
   - Re-running the installer after an interruption, network drop, or sudo timeout is safe and idempotent. Desired state lives in Git; installer journal files under `/var/lib/fedora-hyprland-workstation/` track progress and logs.

4. **Rebooting**:
   - Only reboot when the installer completes successfully (Exit code `0` or `2`) and outputs the summary indicating that graphical login is prepared for the next boot.
   - To preserve safe recovery, graphical activation is never forced onto an active live terminal; it activates on next reboot.


## What it installs

- Fedora 44 + Hyprland + Noctalia + noctalia-greeter (`greetd` user, not `greeter`)
- Zsh, Oh My Zsh, Starship, fzf, zoxide
- Chromium (required when enabled), Brave Origin, Firefox, and Ulaa (via Flathub Flatpak)
- Flatpak + Flathub, Fedora Nix + devenv, rootless Podman
- Host-global media utilities (`mpv`, `ffmpeg`, `mediainfo`, `mkvmerge`, `MP4Box`, `ccextractor`, `mp4dump`, `packager`, `dovi_tool`, `N_m3u8DL-RE`)

## Target Architecture

The workstation maintains a strict separation of concerns:

- **Fedora Host**: Operating system, kernel, drivers, systemd, PipeWire, desktop session (Hyprland + Noctalia + greetd), portals, fonts, system diagnostics, media codecs, normal GUI applications, Podman runtime, and base Nix installation.
- **Nix + devenv**: Reproducible development platforms, compilers, SDKs, project runtimes, language servers, and specialized CLI tooling.
- **Podman**: Isolated development services, databases, and containerized dependencies.
- **Git**: Reproducible desired state.

See detailed engineering documentation:
- [Architecture & Ownership](docs/ARCHITECTURE.md)
- [Safety & Privilege Model](docs/SAFETY.md)
- [Release & Supply-Chain Policy](docs/RELEASE-POLICY.md)

## Package Manifests

- `packages/base.txt`: Core OS utilities, shells, archive tools, networking, and audio foundations.
- `packages/desktop.txt`: Hyprland, Noctalia desktop shell, greetd, portals, terminal, file manager, and fonts.
- `packages/media.txt`: Codecs, GStreamer plugins, VA-API acceleration, MPV, FFmpeg, MediaInfo, and MKVToolNix CLI.
- `packages/diagnostics.txt`: Hardware, sensor, storage, process, and network diagnostics (`smartmontools`, `nvme-cli`, `inxi`, `htop`, `btop`, `iotop-c`, `sysstat`, `lsof`, `strace`, `duf`, `ncdu`, `btrfs-progs`).

## Workstation Applications

- **Kate**: Full-featured graphical text and code editor (Fedora official repositories).
- **Neovim**: Terminal code editor with managed configuration.
- **Cursor**: Official vendor RPM repository with Wayland Ozone flag integration.
- **ChatGPT**: Official vendor RPM repository.
- **Media Applications**: OBS Studio, MKVToolNix GUI, VLC.
- **Media CLI Utilities**: Host-global tools (`dovi_tool`, `N_m3u8DL-RE`, `packager`, `ccextractor`, `mp4dump`, `ffmpeg`, `mediainfo`, `mkvmerge`, `MP4Box`).
- **Antigravity CLI (`agy`)**: Integrated user path with non-blocking activation safety.
- **LocalSend & Ulaa**: Flathub Flatpaks.

## Profiles

| Profile | File | Notes |
| --- | --- | --- |
| `vm` | `profiles/vm.conf` | Virtio GPU, no Bluetooth |
| `workstation` | `profiles/workstation.conf` | Generic GPU, Bluetooth enabled |

Both set `DESKTOP=hyprland` and `DESKTOP_SHELL=noctalia`. Additional shells (for example an Omarchy-inspired Quickshell setup) are reserved and not implemented.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 2 | Completed with deferred optional work |
| 1 | Required component failed. Graphical activation is skipped only when the login stack is unsafe. |

## Troubleshooting

### 1. `git: command not found`
On minimal or netinst Fedora systems, Git is not included by default. Install it using DNF:
```bash
sudo dnf install -y git
```

### 2. `sudo: command not found` or User Lacks Sudo Rights
The installer is designed to run as your **normal user account** and elevate necessary system mutations (such as writing to `/etc` or installing RPMs) using `sudo`. It must **not** be invoked directly as root.
- Ensure your user account belongs to the `wheel` administrative group (`sudo usermod -aG wheel $USER`).
- If `sudo` is not installed on a minimal system, install it as root (`dnf install sudo`) and grant administrative rights to your user. Never attempt to bypass permission checks.

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
/var/lib/fedora-hyprland-workstation/logs/install-<timestamp>.log
```
You can inspect the most recent run log using:
```bash
cat /var/lib/fedora-hyprland-workstation/logs/install-*.log | less
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


