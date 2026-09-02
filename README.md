# Fedora Hyprland Workstation

Idempotent installer for a **Fedora 44** machine running **Hyprland** with the **Noctalia** desktop shell, `greetd`, and a standard workstation toolchain (Zsh, Nix/devenv, Podman, Flatpak, Chromium).

## Prerequisites & Bootstrap

On a fresh or minimal Fedora installation (such as **Fedora Everything** or minimal netinst), install Git if it is not already present:

```bash
sudo dnf install -y git
```

The installer itself automatically verifies, bootstraps, and manages all subsequent required system utilities (`curl`, `jq`, `tar`, `dnf-plugins-core`, etc.) during its preflight stage.

## Usage

Clone the repository and run the installer as your **normal user** (not root):

```bash
# Clone the installer-resilience branch
git clone -b installer-resilience https://github.com/kk18888678/fedora-hyprland-workstation.git
cd fedora-hyprland-workstation

# For virtual machines (VirtIO GPU, no Bluetooth):
./install.sh --profile vm

# For physical hardware workstations:
./install.sh --profile workstation
```

Re-run the same command after a network drop, sudo timeout, or reboot. Desired state lives in Git; installer state under `/var/lib/fedora-hyprland-workstation/` is a journal, not a second configuration source.

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

## Local tests

```bash
./tests/run.sh
```

