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
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/release_policy.sh"

printf '============================================================\n'
printf 'Upstream Stable Release Audit\n'
printf '============================================================\n\n'

is_prerelease_tag() {
    local tag="$1"
    local cls
    cls="$(classify_release_tag "$tag")"
    [[ "$cls" != "stable" ]]
}

check_github_release() {
    local app_id="$1"
    local project_label="$2"
    local repo_slug="$3"
    local current_version="$4"

    printf 'Checking %s (%s)...\n' "$project_label" "$current_version"

    if ! command -v curl >/dev/null 2>&1; then
        printf '  [SKIP] curl is required for release checks.\n'
        return 0
    fi

    # Retrieve recent releases to discover both stable and allowed prereleases
    local releases_json
    releases_json="$(curl -fsSL -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo_slug}/releases?per_page=10" 2>/dev/null || true)"

    if [[ -z "$releases_json" ]]; then
        # Fallback to /releases/latest
        releases_json="$(curl -fsSL -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${repo_slug}/releases/latest" 2>/dev/null || true)"
        if [[ -n "$releases_json" ]]; then
            releases_json="[$releases_json]"
        fi
    fi

    if [[ -z "$releases_json" ]]; then
        printf '  [WARN] Could not retrieve releases from GitHub for %s.\n' "$repo_slug"
        return 0
    fi

    local candidate_tags=()
    if command -v jq >/dev/null 2>&1; then
        while IFS= read -r t; do
            [[ -n "$t" ]] && candidate_tags+=("$t")
        done < <(printf '%s' "$releases_json" | jq -r '.[].tag_name // empty' 2>/dev/null || true)
    else
        while IFS= read -r t; do
            [[ -n "$t" ]] && candidate_tags+=("$t")
        done < <(printf '%s' "$releases_json" | awk -F'"' '/"tag_name":/{print $4}' || true)
    fi

    if [[ "${#candidate_tags[@]}" -eq 0 ]]; then
        printf '  [INFO] No releases found.\n\n'
        return 0
    fi

    local selected_tag=""
    if selected_tag="$(select_eligible_release "$app_id" "${candidate_tags[@]}" 2>/dev/null)"; then
        local sel_class
        sel_class="$(classify_release_tag "$selected_tag")"
        printf '  Current pinned : %s\n' "$current_version"
        if [[ "$sel_class" == "stable" ]]; then
            printf '  Upstream latest: %s\n' "$selected_tag"
        else
            printf '  Upstream latest: %s (prerelease exception: %s)\n' "$selected_tag" "$sel_class"
        fi

        if [[ "$selected_tag" =~ $current_version ]]; then
            printf '  Status         : UP TO DATE\n\n'
        else
            printf '  Status         : UPDATE AVAILABLE (review before bumping config/versions.conf)\n\n'
        fi
    else
        local latest_raw="${candidate_tags[0]}"
        local raw_class
        raw_class="$(classify_release_tag "$latest_raw")"
        printf '  Current pinned : %s\n' "$current_version"
        printf '  Upstream latest: %s (PRERELEASE [%s] - rejected by policy)\n' "$latest_raw" "$raw_class"
        printf '  Status         : PRERELEASE IGNORED\n\n'
    fi
}

check_github_latest() {
    local project_label="$1"
    local repo_slug="$2"
    local current_version="$3"
    local app_id
    app_id="$(canonical_app_id "$project_label")"
    check_github_release "$app_id" "$project_label" "$repo_slug" "$current_version"
}

check_github_latest "CCExtractor" "CCExtractor/ccextractor" "${CCEXTRACTOR_VERSION:-unknown}"
check_github_latest "Shaka Packager" "shaka-project/shaka-packager" "${SHAKA_PACKAGER_VERSION:-unknown}"
check_github_latest "dovi_tool" "quietvoid/dovi_tool" "${DOVI_TOOL_VERSION:-unknown}"
check_github_latest "N_m3u8DL-RE" "nilaoda/N_m3u8DL-RE" "${N_M3U8DL_RE_VERSION:-unknown}"

printf 'Audit complete. Remember to verify SHA-512 checksums and test builds before committing version bumps.\n'

