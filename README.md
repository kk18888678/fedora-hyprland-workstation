# Fedora Hyprland Workstation

Idempotent installer for a **Fedora 44** machine running **Hyprland** with the **Noctalia** desktop shell, `greetd`, and a standard workstation toolchain (Zsh, Nix/devenv, Podman, Flatpak, Chromium).

## Usage

Run as your normal user (not root):

```bash
git clone <repo>
cd fedora-hyprland-workstation
./install.sh --profile vm
```

Physical hardware:

```bash
./install.sh --profile workstation
```

Re-run the same command after a network drop, sudo timeout, or reboot. Desired state lives in Git; installer state under `/var/lib/fedora-hyprland-workstation/` is a journal, not a second configuration source.

## What it installs

- Fedora 44 + Hyprland + Noctalia + noctalia-greeter (`greetd` user, not `greeter`)
- Zsh, Oh My Zsh, Starship, fzf, zoxide
- Chromium (required when enabled). Brave Origin and Firefox are optional. **Ulaa is deferred on Fedora** (the upstream Linux installer is Debian/apt).
- Flatpak + Flathub, Fedora Nix + devenv, rootless Podman

Graphical login is enabled only after desktop and greeter validation. `greetd` is enabled for the **next boot** (`systemctl enable`, not `enable --now`) so an SSH install is not replaced by a greeter mid-run.

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
| 1 | Critical failure (graphical activation skipped when the login stack is unsafe) |

## Local tests

```bash
./tests/run.sh
```
