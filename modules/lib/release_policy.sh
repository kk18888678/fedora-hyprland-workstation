#!/usr/bin/env bash

# Release Policy & Declarative Prerelease Exception Library
#
# Principles:
# 1. Prerelease software is prohibited by default.
# 2. Narrowly scoped declarative exceptions may permit explicitly named
#    prerelease classes for an explicitly named application.
# 3. Exceptions affect release eligibility ONLY; they never weaken provenance,
#    checksum/signature integrity, archive safety, or validation requirements.
# 4. A policy-compliant stable release ALWAYS takes precedence over an allowed
#    prerelease release (stable > allowed prerelease).
# 5. Unknown prerelease classes and malformed policy registries fail closed.

# Supported prerelease classes recognized by the classifier and registry
SUPPORTED_PRERELEASE_CLASSES=("alpha" "beta" "rc" "preview" "pre" "nightly" "dev" "snapshot" "git")

# Supported selection policies
SUPPORTED_SELECTION_POLICIES=("stable_then_allowed_prerelease")

# Internal registry store
declare -A _PRERELEASE_APP_ENABLED=()
declare -A _PRERELEASE_APP_CLASSES=()
declare -A _PRERELEASE_APP_POLICY=()
declare -A _PRERELEASE_APP_REASON=()
_PRERELEASE_REGISTRY_LOADED=false
_PRERELEASE_REGISTRY_VALID=false
_PRERELEASE_REGISTRY_FILE=""

# Normalize raw application identifier to a canonical internal format:
# Lowercase, trimmed, hyphens replaced with underscores.
canonical_app_id() {
    local raw="$1"
    local lower
    lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"
    lower="${lower#"${lower%%[![:space:]]*}"}"
    lower="${lower%"${lower##*[![:space:]]}"}"
    printf '%s' "$lower"
}

# Structured release candidate helpers:
# Representation: "<tag>|<is_prerelease>"
format_release_candidate() {
    local tag="$1"
    local is_prerelease="${2:-false}"
    [[ "$is_prerelease" != "true" ]] && is_prerelease="false"
    printf '%s|%s\n' "$tag" "$is_prerelease"
}

parse_release_candidate() {
    local __prc_raw="$1"
    local __prc_out_tag="$2"
    local __prc_out_meta="${3:-}"

    local __prc_tag="${__prc_raw%%|*}"
    local __prc_meta="false"
    if [[ "$__prc_raw" == *"|"* ]]; then
        __prc_meta="${__prc_raw#*|}"
    fi

    printf -v "$__prc_out_tag" '%s' "$__prc_tag"
    if [[ -n "$__prc_out_meta" ]]; then
        printf -v "$__prc_out_meta" '%s' "$__prc_meta"
    fi
}


# Boundary-aware release tag classifier.
# Returns exact class:
#   "stable"
#   "alpha" | "beta" | "rc" | "preview" | "pre" | "nightly" | "dev" | "snapshot"
#   "unknown_prerelease"
classify_release_tag() {
    local raw_tag="$1"
    local is_prerelease_meta="${2:-false}"

    local tag=""
    local parsed_meta="false"
    parse_release_candidate "$raw_tag" tag parsed_meta
    if [[ "$raw_tag" == *"|"* ]]; then
        is_prerelease_meta="$parsed_meta"
    fi

    local lower
    lower="$(printf '%s\n' "$tag" | tr '[:upper:]' '[:lower:]')"

    # Match snapshot caret (Fedora RPM snapshot packaging convention)
    if [[ "$lower" =~ \^ ]]; then
        printf 'snapshot\n'
        return 0
    fi

    # Match conventional boundary-aware prerelease tokens:
    # Delimiter or digit transition followed by keyword and delimiter, digits, or end of string.
    local token_pattern='(^|[^a-z0-9]|[0-9])(alpha|beta|rc|preview|pre|nightly|dev|snapshot|git)([0-9._+-]|$)'
    if [[ "$lower" =~ $token_pattern ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$is_prerelease_meta" == "true" ]]; then
        printf 'unknown_prerelease\n'
        return 0
    fi

    printf 'stable\n'
    return 0
}


# Validate declarative registry syntax and invariants without executing code.
validate_prerelease_exceptions_registry() {
    local file="$1"
    if [[ ! -f "$file" || ! -r "$file" ]]; then
        printf 'ERROR: Prerelease exceptions registry missing or unreadable: %s\n' "$file" >&2
        return 1
    fi

    local current_app=""
    local seen_apps=()
    local has_enabled=false
    local has_classes=false
    local has_policy=false
    local has_reason=false

    _check_section_complete() {
        if [[ -n "$current_app" ]]; then
            if ! $has_enabled || ! $has_classes || ! $has_policy || ! $has_reason; then
                printf 'ERROR: Application [%s] incomplete in registry\n' "$current_app" >&2
                return 1
            fi
        fi
        return 0
    }

    local line_no=0
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        ((line_no++)) || true
        local line="${raw_line#"${raw_line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        [[ -z "$line" || "$line" =~ ^# ]] && continue

        # Section header: [app_id]
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            _check_section_complete || return 1
            local raw_app="${BASH_REMATCH[1]}"
            local app
            app="$(canonical_app_id "$raw_app")"
            if [[ -z "$app" ]]; then
                printf 'ERROR: Line %d: Empty application ID\n' "$line_no" >&2
                return 1
            fi
            for s in "${seen_apps[@]}"; do
                if [[ "$s" == "$app" ]]; then
                    printf 'ERROR: Line %d: Duplicate application ID: %s\n' "$line_no" "$app" >&2
                    return 1
                fi
            done
            seen_apps+=("$app")
            current_app="$app"
            has_enabled=false
            has_classes=false
            has_policy=false
            has_reason=false
            continue
        fi

        # Property: key = value
        if [[ "$line" =~ ^([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            if [[ -z "$current_app" ]]; then
                printf 'ERROR: Line %d: Property outside application section: %s\n' "$line_no" "$line" >&2
                return 1
            fi
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip optional surrounding quotes
            if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\x27(.*)\x27$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi

            case "$key" in
                enabled)
                    if $has_enabled; then
                        printf 'ERROR: Line %d: Duplicate property in section [%s]: %s\n' "$line_no" "$current_app" "$key" >&2
                        return 1
                    fi
                    if [[ "$val" != "true" && "$val" != "false" ]]; then
                        printf 'ERROR: Line %d: Invalid enabled boolean: %s\n' "$line_no" "$val" >&2
                        return 1
                    fi
                    has_enabled=true
                    ;;
                allowed_classes)
                    if $has_classes; then
                        printf 'ERROR: Line %d: Duplicate property in section [%s]: %s\n' "$line_no" "$current_app" "$key" >&2
                        return 1
                    fi
                    if [[ -z "$val" ]]; then
                        printf 'ERROR: Line %d: Empty allowed_classes\n' "$line_no" >&2
                        return 1
                    fi
                    local class_list=()
                    IFS=" ," read -r -a class_list <<< "$val"
                    if [[ "${#class_list[@]}" -eq 0 ]]; then
                        printf 'ERROR: Line %d: Empty allowed_classes list\n' "$line_no" >&2
                        return 1
                    fi
                    for c in "${class_list[@]}"; do
                        [[ -z "$c" ]] && continue
                        if [[ "$c" == "*" || "$c" == "all" || "$c" == "any" ]]; then
                            printf 'ERROR: Line %d: Wildcards prohibited in allowed_classes: %s\n' "$line_no" "$c" >&2
                            return 1
                        fi
                        local matched=0
                        for sc in "${SUPPORTED_PRERELEASE_CLASSES[@]}"; do
                            if [[ "$sc" == "$c" ]]; then matched=1; break; fi
                        done
                        if [[ "$matched" -eq 0 ]]; then
                            printf 'ERROR: Line %d: Unsupported prerelease class: %s\n' "$line_no" "$c" >&2
                            return 1
                        fi
                    done
                    has_classes=true
                    ;;
                selection_policy)
                    if $has_policy; then
                        printf 'ERROR: Line %d: Duplicate property in section [%s]: %s\n' "$line_no" "$current_app" "$key" >&2
                        return 1
                    fi
                    local matched_pol=0
                    for sp in "${SUPPORTED_SELECTION_POLICIES[@]}"; do
                        if [[ "$sp" == "$val" ]]; then matched_pol=1; break; fi
                    done
                    if [[ "$matched_pol" -eq 0 ]]; then
                        printf 'ERROR: Line %d: Unsupported selection_policy: %s\n' "$line_no" "$val" >&2
                        return 1
                    fi
                    has_policy=true
                    ;;
                reason)
                    if $has_reason; then
                        printf 'ERROR: Line %d: Duplicate property in section [%s]: %s\n' "$line_no" "$current_app" "$key" >&2
                        return 1
                    fi
                    if [[ -z "$val" ]]; then
                        printf 'ERROR: Line %d: Empty reason\n' "$line_no" >&2
                        return 1
                    fi
                    has_reason=true
                    ;;
                *)
                    printf 'ERROR: Line %d: Unknown property key: %s\n' "$line_no" "$key" >&2
                    return 1
                    ;;
            esac
            continue
        fi

        printf 'ERROR: Line %d: Unrecognized registry line: %s\n' "$line_no" "$line" >&2
        return 1
    done < "$file"

    _check_section_complete || return 1
    return 0
}

# Resolve default registry file path
_default_prerelease_registry_path() {
    if [[ -n "${PRERELEASE_EXCEPTIONS_FILE:-}" ]]; then
        printf '%s\n' "$PRERELEASE_EXCEPTIONS_FILE"
        return 0
    fi
    local base_dir
    base_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
    printf '%s/config/prerelease_exceptions.conf\n' "$base_dir"
}

# Load and cache declarative prerelease exceptions
load_prerelease_exceptions_registry() {
    local file="${1:-$(_default_prerelease_registry_path)}"

    # If already loaded from same file, return cached status
    if [[ "$_PRERELEASE_REGISTRY_LOADED" == "true" && "$_PRERELEASE_REGISTRY_FILE" == "$file" ]]; then
        [[ "$_PRERELEASE_REGISTRY_VALID" == "true" ]]
        return $?
    fi

    _PRERELEASE_APP_ENABLED=()
    _PRERELEASE_APP_CLASSES=()
    _PRERELEASE_APP_POLICY=()
    _PRERELEASE_APP_REASON=()
    _PRERELEASE_REGISTRY_FILE="$file"

    if ! validate_prerelease_exceptions_registry "$file" 2>/dev/null; then
        _PRERELEASE_REGISTRY_LOADED=true
        _PRERELEASE_REGISTRY_VALID=false
        return 1
    fi

    local current_app=""
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line="${raw_line#"${raw_line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            current_app="$(canonical_app_id "${BASH_REMATCH[1]}")"
            continue
        fi

        if [[ "$line" =~ ^([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\x27(.*)\x27$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi
            case "$key" in
                enabled) _PRERELEASE_APP_ENABLED["$current_app"]="$val" ;;
                allowed_classes)
                    local clist=()
                    IFS=" ," read -r -a clist <<< "$val"
                    _PRERELEASE_APP_CLASSES["$current_app"]="${clist[*]}"
                    ;;
                selection_policy) _PRERELEASE_APP_POLICY["$current_app"]="$val" ;;
                reason) _PRERELEASE_APP_REASON["$current_app"]="$val" ;;
            esac
        fi
    done < "$file"

    _PRERELEASE_REGISTRY_LOADED=true
    _PRERELEASE_REGISTRY_VALID=true
    return 0
}

# Check if an explicit prerelease class is allowed for an application
is_prerelease_class_allowed() {
    local app_id="$1"
    local class="$2"
    local canonical
    canonical="$(canonical_app_id "$app_id")"

    load_prerelease_exceptions_registry || true
    if [[ "$_PRERELEASE_REGISTRY_VALID" != "true" ]]; then
        return 1
    fi
    if [[ "${_PRERELEASE_APP_ENABLED[$canonical]:-false}" != "true" ]]; then
        return 1
    fi

    local allowed_classes="${_PRERELEASE_APP_CLASSES[$canonical]:-}"
    for c in $allowed_classes; do
        if [[ "$c" == "$class" ]]; then
            return 0
        fi
    done
    return 1
}

# Evaluate eligibility for a single release tag/version.
# Sets out_reason_var (if passed) to a diagnostic explanation.
evaluate_release_eligibility() {
    local app_id="$1"
    local tag="$2"
    local out_var="${3:-}"
    local is_prerelease_meta="${4:-false}"

    local class
    class="$(classify_release_tag "$tag" "$is_prerelease_meta")"

    local reason=""
    local ret=0

    if [[ "$class" == "stable" ]]; then
        reason="stable release"
        ret=0
    elif [[ "$class" == "unknown_prerelease" ]]; then
        reason="unknown prerelease class"
        ret=1
    else
        load_prerelease_exceptions_registry || true
        if [[ "$_PRERELEASE_REGISTRY_VALID" != "true" ]]; then
            reason="malformed exception policy"
            ret=1
        else
            local canonical
            canonical="$(canonical_app_id "$app_id")"
            if [[ -z "${_PRERELEASE_APP_ENABLED[$canonical]:-}" ]]; then
                reason="prerelease prohibited by default"
                ret=1
            elif [[ "${_PRERELEASE_APP_ENABLED[$canonical]}" != "true" ]]; then
                reason="prerelease prohibited by default (exception disabled)"
                ret=1
            elif is_prerelease_class_allowed "$canonical" "$class"; then
                reason="policy exception permits class: $class"
                ret=0
            else
                reason="prerelease class '$class' not permitted for $app_id"
                ret=1
            fi
        fi
    fi

    if [[ -n "$out_var" ]]; then
        printf -v "$out_var" '%s' "$reason"
    fi
    return "$ret"
}

# Select the best eligible release from candidate list:
# 1. Discovery completeness MUST be established BEFORE returning any best upstream release.
#    Incomplete discovery (bound_reached, fetch_error, parse_error, parser_unavailable) fails closed.
# 2. Any policy-compliant stable release ALWAYS takes precedence over prerelease.
# 3. If no stable release exists and discovery is complete, consult exception registry.
# 4. If allowed prerelease exists, select newest allowed prerelease.
# 5. Otherwise reject with descriptive error on stderr.
select_eligible_release() {
    local discovery_status="${RELEASE_DISCOVERY_STATUS:-complete}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --discovery-status)
                discovery_status="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    local app_id="$1"
    shift
    local candidates=("$@")

    # 1. Validate discovery status: incomplete candidate universe must fail closed
    # Incomplete discovery cannot guarantee that a newer stable or release does not exist.
    if [[ "$discovery_status" != "complete" ]]; then
        printf 'ERROR: Release discovery was incomplete (%s) for %s; cannot determine best release\n' "$discovery_status" "$app_id" >&2
        return 1
    fi

    local stable_candidates=()
    local prerelease_candidates=()
    local prerelease_classes=()

    for cand in "${candidates[@]}"; do
        local tag=""
        local is_pre="false"
        parse_release_candidate "$cand" tag is_pre
        [[ -z "$tag" ]] && continue

        local cls
        cls="$(classify_release_tag "$tag" "$is_pre")"
        if [[ "$cls" == "stable" ]]; then
            stable_candidates+=("$tag")
        else
            prerelease_candidates+=("$tag")
            prerelease_classes+=("$cls")
        fi
    done

    # 2. Stable always takes precedence if any stable candidate exists
    if [[ "${#stable_candidates[@]}" -gt 0 ]]; then
        local selected
        selected="$(printf '%s\n' "${stable_candidates[@]}" | sort -V | tail -n 1)"
        printf '%s\n' "$selected"
        return 0
    fi

    if [[ "${#prerelease_candidates[@]}" -eq 0 ]]; then
        printf 'ERROR: No candidate releases provided for %s\n' "$app_id" >&2
        return 1
    fi

    # 3. Discovery was complete and zero stable candidates exist. Consult exception registry.
    load_prerelease_exceptions_registry || true
    if [[ "$_PRERELEASE_REGISTRY_VALID" != "true" ]]; then
        printf 'ERROR: Malformed exception policy\n' >&2
        return 1
    fi

    local canonical
    canonical="$(canonical_app_id "$app_id")"
    if [[ -z "${_PRERELEASE_APP_ENABLED[$canonical]:-}" ]] || [[ "${_PRERELEASE_APP_ENABLED[$canonical]}" != "true" ]]; then
        printf 'ERROR: Prerelease prohibited by default for %s\n' "$app_id" >&2
        return 1
    fi

    local allowed_candidates=()
    for i in "${!prerelease_candidates[@]}"; do
        local cand="${prerelease_candidates[$i]}"
        local cls="${prerelease_classes[$i]}"
        if is_prerelease_class_allowed "$canonical" "$cls"; then
            allowed_candidates+=("$cand")
        fi
    done

    if [[ "${#allowed_candidates[@]}" -gt 0 ]]; then
        local selected
        selected="$(printf '%s\n' "${allowed_candidates[@]}" | sort -V | tail -n 1)"
        local sel_cls
        sel_cls="$(classify_release_tag "$selected")"
        if type info >/dev/null 2>&1; then
            info "No stable release available for $app_id. Policy exception permits class: $sel_cls. Selected: $selected" >&2
        fi
        printf '%s\n' "$selected"
        return 0
    fi

    # 4. No allowed candidates
    local has_unknown=0
    for cls in "${prerelease_classes[@]}"; do
        if [[ "$cls" == "unknown_prerelease" ]]; then has_unknown=1; break; fi
    done
    if [[ "$has_unknown" -eq 1 ]]; then
        printf 'ERROR: Unknown prerelease class\n' >&2
    else
        printf 'ERROR: Prerelease class not permitted for %s\n' "$app_id" >&2
    fi
    return 1
}

# Bounded GitHub release discovery parameters
# Bounds prevent infinite pagination loops while providing full coverage for typical workstation tools.
RELEASE_DISCOVERY_MAX_PAGES="${RELEASE_DISCOVERY_MAX_PAGES:-10}"
RELEASE_DISCOVERY_PER_PAGE="${RELEASE_DISCOVERY_PER_PAGE:-30}"

_default_github_page_fetcher() {
    local repo_slug="$1"
    local page="$2"
    local per_page="$3"

    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi

    curl -fsSL --max-time 15 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo_slug}/releases?page=${page}&per_page=${per_page}" 2>/dev/null
}

# Discover release candidates from GitHub API across bounded pages.
# Preserves authoritative prerelease metadata per candidate.
discover_github_release_candidates() {
    local repo_slug="$1"
    local _out_candidates_var="$2"
    local _out_status_var="$3"
    local fetcher="${4:-_default_github_page_fetcher}"

    local max_pages="$RELEASE_DISCOVERY_MAX_PAGES"
    local per_page="$RELEASE_DISCOVERY_PER_PAGE"

    local all_candidates=()
    local discovery_status="complete"

    local jq_bin="${JQ_CMD:-jq}"
    if ! command -v "$jq_bin" >/dev/null 2>&1; then
        eval "$_out_candidates_var=()"
        printf -v "$_out_status_var" '%s' "parser_unavailable"
        return 0
    fi

    local page=1
    while [[ "$page" -le "$max_pages" ]]; do
        local page_json=""
        if ! page_json="$("$fetcher" "$repo_slug" "$page" "$per_page")"; then
            discovery_status="fetch_error"
            break
        fi

        if [[ -z "$page_json" ]]; then
            discovery_status="fetch_error"
            break
        fi

        local jq_out=""
        if ! jq_out="$(printf '%s' "$page_json" | "$jq_bin" -r '
            if type != "array" then
                error("API response is not an array")
            else
                .[] | "\(.tag_name)\t\(.prerelease)"
            end' 2>/dev/null)"; then
            discovery_status="parse_error"
            break
        fi

        local page_candidates=()
        if [[ -n "$jq_out" ]]; then
            while IFS=$'\t' read -r tag is_pre; do
                if [[ -n "$tag" && "$tag" != "null" ]]; then
                    [[ "$is_pre" != "true" ]] && is_pre="false"
                    page_candidates+=("$(format_release_candidate "$tag" "$is_pre")")
                fi
            done <<< "$jq_out"
        fi

        local count="${#page_candidates[@]}"
        if [[ "$count" -eq 0 ]]; then
            # Valid empty array [] indicates end of releases reached
            discovery_status="complete"
            break
        fi

        all_candidates+=("${page_candidates[@]}")

        if [[ "$count" -lt "$per_page" ]]; then
            # Last page has fewer than per_page items -> end of releases reached
            discovery_status="complete"
            break
        fi

        ((page++)) || true
    done

    if [[ "$page" -gt "$max_pages" && "$discovery_status" == "complete" ]]; then
        discovery_status="bound_reached"
    fi

    eval "$_out_candidates_var=(\"\${all_candidates[@]}\")"
    printf -v "$_out_status_var" '%s' "$discovery_status"
}

