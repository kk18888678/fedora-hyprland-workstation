#!/usr/bin/env bash

# Upstream Stable Release Checker
#
# This maintenance tool inspects authoritative upstream repositories for newer
# stable releases of pinned workstation artifacts.
#
# Policy:
#   - Read-only queries only.
#   - NEVER runs during normal installation.
#   - NEVER silently mutates config/versions.conf.
#   - Ignores prereleases, drafts, alphas, and betas.
#   - Human maintainers review and update pinned versions intentionally.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSIONS_FILE="$SCRIPT_DIR/config/versions.conf"

[[ -f "$VERSIONS_FILE" ]] || {
    printf 'ERROR: Pinned versions file missing at %s\n' "$VERSIONS_FILE" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$VERSIONS_FILE"

printf '============================================================\n'
printf 'Upstream Stable Release Audit\n'
printf '============================================================\n\n'

is_prerelease_tag() {
    local tag="$1"
    local lower
    lower="$(printf '%s\n' "$tag" | tr '[:upper:]' '[:lower:]')"

    # Match conventional boundary-aware prerelease tokens:
    # Delimiter or digit transition followed by keyword and delimiter, digits, or end of string.
    local token_pattern='(^|[^a-z0-9]|[0-9])(alpha|beta|rc|preview|pre|nightly|dev|snapshot)([0-9._+-]|$)'
    if [[ "$lower" =~ $token_pattern ]]; then
        return 0
    fi
    return 1
}

check_github_latest() {
    local project_label="$1"
    local repo_slug="$2"
    local current_version="$3"

    printf 'Checking %s (%s)...\n' "$project_label" "$current_version"

    if ! command -v curl >/dev/null 2>&1; then
        printf '  [SKIP] curl is required for release checks.\n'
        return 0
    fi

    local release_json
    release_json="$(curl -fsSL -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo_slug}/releases/latest" 2>/dev/null || true)"

    if [[ -z "$release_json" ]]; then
        printf '  [WARN] Could not retrieve latest stable release from GitHub for %s.\n' "$repo_slug"
        return 0
    fi

    local latest_tag
    latest_tag="$(printf '%s\n' "$release_json" | grep -m1 '"tag_name":' | cut -d'"' -f4 || true)"

    if [[ -n "$latest_tag" ]]; then
        if is_prerelease_tag "$latest_tag"; then
            printf '  Current pinned : %s\n' "$current_version"
            printf '  Upstream latest: %s (PRERELEASE - rejected by stable policy)\n' "$latest_tag"
            printf '  Status         : PRERELEASE IGNORED\n\n'
            return 0
        fi

        printf '  Current pinned : %s\n' "$current_version"
        printf '  Upstream latest: %s\n' "$latest_tag"
        if [[ "$latest_tag" =~ $current_version ]]; then
            printf '  Status         : UP TO DATE\n\n'
        else
            printf '  Status         : UPDATE AVAILABLE (review before bumping config/versions.conf)\n\n'
        fi
    else
        printf '  [INFO] No standard latest release found.\n\n'
    fi
}

check_github_latest "CCExtractor" "CCExtractor/ccextractor" "${CCEXTRACTOR_VERSION:-unknown}"
check_github_latest "Shaka Packager" "shaka-project/shaka-packager" "${SHAKA_PACKAGER_VERSION:-unknown}"
check_github_latest "dovi_tool" "quietvoid/dovi_tool" "${DOVI_TOOL_VERSION:-unknown}"
check_github_latest "N_m3u8DL-RE" "nilaoda/N_m3u8DL-RE" "${N_M3U8DL_RE_VERSION:-unknown}"

printf 'Audit complete. Remember to verify SHA-512 checksums and test builds before committing version bumps.\n'
