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

    local candidate_list=()
    local discovery_status=""
    discover_github_release_candidates "$repo_slug" candidate_list discovery_status

    if [[ "$discovery_status" == "fetch_error" ]]; then
        printf '  [WARN] Could not retrieve releases from GitHub for %s.\n' "$repo_slug"
        return 0
    fi

    if [[ "${#candidate_list[@]}" -eq 0 ]]; then
        printf '  [INFO] No releases found.\n\n'
        return 0
    fi

    local selected_tag=""
    if selected_tag="$(select_eligible_release --discovery-status "$discovery_status" "$app_id" "${candidate_list[@]}" 2>/dev/null)"; then
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
        local latest_raw="${candidate_list[0]}"
        local raw_tag=""
        local raw_meta="false"
        parse_release_candidate "$latest_raw" raw_tag raw_meta
        local raw_class
        raw_class="$(classify_release_tag "$raw_tag" "$raw_meta")"
        printf '  Current pinned : %s\n' "$current_version"
        if [[ "$discovery_status" != "complete" ]]; then
            printf '  Upstream latest: %s (DISCOVERY INCOMPLETE [%s] - cannot verify stable precedence)\n' "$raw_tag" "$discovery_status"
            printf '  Status         : DISCOVERY INCOMPLETE\n\n'
        else
            printf '  Upstream latest: %s (PRERELEASE [%s] - rejected by policy)\n' "$raw_tag" "$raw_class"
            printf '  Status         : PRERELEASE IGNORED\n\n'
        fi
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

