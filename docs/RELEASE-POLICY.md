# Workstation Release & Supply-Chain Policy

This document defines the release standards, upstream artifact verification requirements, update discovery workflows, and extension guidelines for contributors.

---

## 1. Stable-Only Software Policy

The workstation provides a **cutting-edge, but not bleeding-edge** environment:

- **Default Profiles**: Default profiles (`workstation`, `vm`) install **only** verified stable releases.
- **Prohibited Sources**: Alpha, beta, release candidate (RC), nightly, development snapshot, and untagged git HEAD builds are prohibited from default installation paths.
- **Declarative Prerelease Exceptions**:
  - Exceptions are declared strictly in `config/prerelease_exceptions.conf` and evaluated via `modules/lib/release_policy.sh`.
  - Exceptions affect release eligibility ONLY and never weaken cryptographic checksum verification, archive safety checks, or validation.
  - Stable releases always take precedence over allowed prereleases (`stable > allowed prerelease`).
- **Explicit Documented Exceptions**:
  - **Official OpenAI ChatGPT for Linux Public Preview** (Vendor Distribution Channel Exception): Supported as official vendor desktop distribution with Fedora 43/44 support for workstation AI workflows. Future updates are managed by OpenAI's signed DNF repository.
  - **N_m3u8DL-RE** (Direct Upstream Release Class Exception: `beta`): Upstream nilaoda/N_m3u8DL-RE distributes its supported release line exclusively with the `-beta` suffix; no stable release has ever been published. Pinned SHA-512 byte verification and archive sandboxing remain strictly enforced.

---

## 2. Supply-Chain Security & Direct Upstream Artifacts

For software installed directly from upstream release assets rather than Fedora RPM repositories or Flathub:

1. **Pinned Metadata**: Every upstream artifact must have a pinned version, HTTPS download URL, and 128-character SHA-512 cryptographic checksum in `config/versions.conf`.
2. **Cryptographic Verification Before Execution**: Artifacts are downloaded to an isolated `mktemp` staging directory, verified against the pinned SHA-512 checksum, and only extracted/installed if the checksum matches.
3. **Atomic Deployment**: Binaries are installed to `/usr/local/bin` (root) or `~/.local/bin` (user) with mode `0755` using atomic staging to prevent partial state on interruption.
4. **Temporary Resource Cleanup**: Staging directories are strictly cleaned on success and on failure.

### Pinned Upstream Artifacts Table

| Tool | Version | Upstream Source | Verification |
| --- | --- | --- | --- |
| **Oh My Zsh** | Git commit `9112b53` | `github.com/ohmyzsh/ohmyzsh` | Git commit hash |
| **zsh-autosuggestions** | Git commit `85919cd` | `github.com/zsh-users/zsh-autosuggestions` | Git commit hash |
| **zsh-syntax-highlighting** | Git commit `2fc57d6` | `github.com/zsh-users/zsh-syntax-highlighting` | Git commit hash |
| **devenv** | `nixos-26.05` commit `c5c4a43` | `github.com/NixOS/nixpkgs` | Nix commit hash |
| **Antigravity CLI** | `1.1.23` | Google Cloud Storage | SHA-512 |
| **ChatGPT** | `26.831.21537-1` | `persistent.oaistatic.com` | SHA-512 (Official bootstrap RPM) |
| **CCExtractor** | `0.96.6` | `github.com/CCExtractor/ccextractor` | SHA-512 |
| **Bento4** | `1.6.0-641` | `bok.net/Bento4` | SHA-512 |
| **Shaka Packager** | `3.9.3` | `github.com/shaka-project/shaka-packager` | SHA-512 |
| **dovi_tool** | `2.3.3` | `github.com/quietvoid/dovi_tool` | SHA-512 |
| **N_m3u8DL-RE** | `0.6.0-beta` | `github.com/nilaoda/N_m3u8DL-RE` | SHA-512 (Approved declarative beta exception; verified archive) |

---


## 3. Installation vs Update Discovery

The repository strictly separates **installation** from **update discovery**:

- **Installation**: Deterministic, reproducible, consuming only known-good pinned versions from `config/versions.conf`. It never queries upstream APIs for unvalidated releases during installation.
- **Update Discovery**: Performed out-of-band by maintainers using `scripts/check-updates.sh`. Newer stable releases are tested and vetted before committing updated metadata to `config/versions.conf`.

---

## 4. Contributor Guidelines: Adding a New Capability

When contributing a new tool or application:

1. **Determine Ownership**:
   - OS utility / Desktop component / GUI app -> Fedora Host (`packages/*.txt`, `modules/applications.sh`, or `modules/flatpak.sh`).
   - Project compiler / Language toolchain -> Nix + `devenv.nix`.
   - Disposable service / Database -> Podman.
2. **Follow Packaging Precedence**:
   - Official Fedora repository (Preferred).
   - RPM Fusion Free / Nonfree.
   - Flathub Flatpak (for isolated GUI apps).
   - Official Vendor RPM repository with GPG verification (e.g. Cursor, ChatGPT).
   - Pinned upstream release binary/archive with SHA-512 verification in `config/versions.conf` and `provision_verified_*`.
3. **Classify Failures**:
   - Is it essential for graphical login? -> `record_activation_failure`.
   - Is it a required workstation CLI tool? -> `record_required`.
   - Is it an optional application? -> `record_deferred`.
4. **Add Unit & Integration Tests**:
   - Add capability checks in `modules/validation.sh`.
   - Add negative and failure-resilience tests in `tests/run.sh`.
