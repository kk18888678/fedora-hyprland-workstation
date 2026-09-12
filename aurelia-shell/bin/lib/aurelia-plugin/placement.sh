#!/usr/bin/env bash
# Shared placement parsing for Aurelia plugin and bar commands.

[[ "${AURELIA_PLUGIN_PLACEMENT_LOADED:-0}" == "1" ]] && return 0
AURELIA_PLUGIN_PLACEMENT_LOADED=1

aurelia_plugin_reset_placement() {
    AURELIA_PLACEMENT_SECTION=""
    AURELIA_PLACEMENT_INDEX=""
    AURELIA_PLACEMENT_BEFORE=""
    AURELIA_PLACEMENT_AFTER=""
    AURELIA_PLACEMENT_FROM_SECTION=""
    AURELIA_PLACEMENT_FROM_INDEX=""
}

aurelia_plugin_validate_placement_section() {
    [[ "${1:-}" =~ ^(left|center|right)$ ]] ||
        aurelia_plugin_fail "section must be left, center, or right"
}

aurelia_plugin_validate_placement_index() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] ||
        aurelia_plugin_fail "index must be a non-negative integer"
}

aurelia_plugin_parse_placement() {
    local mode="$1"
    local allow_positional="${2:-1}"
    shift 2
    aurelia_plugin_reset_placement

    local positional_section=0
    if [[ "$allow_positional" == "1" ]] && (( $# > 0 )) && [[ "$1" != --* ]]; then
        AURELIA_PLACEMENT_SECTION="$1"
        positional_section=1
        aurelia_plugin_validate_placement_section "$AURELIA_PLACEMENT_SECTION" || return 1
        shift
    fi

    while (( $# > 0 )); do
        case "$1" in
            --section)
                (( $# >= 2 )) || { aurelia_plugin_fail "--section requires a section"; return 1; }
                [[ -z "$AURELIA_PLACEMENT_SECTION" ]] || {
                    aurelia_plugin_fail "specify a section positionally or with --section, not both"
                    return 1
                }
                AURELIA_PLACEMENT_SECTION="$2"
                aurelia_plugin_validate_placement_section "$AURELIA_PLACEMENT_SECTION" || return 1
                shift 2
                ;;
            --index)
                (( $# >= 2 )) || { aurelia_plugin_fail "--index requires an index"; return 1; }
                AURELIA_PLACEMENT_INDEX="$2"
                aurelia_plugin_validate_placement_index "$AURELIA_PLACEMENT_INDEX" || return 1
                shift 2
                ;;
            --before)
                (( $# >= 2 )) || { aurelia_plugin_fail "--before requires a widget id"; return 1; }
                AURELIA_PLACEMENT_BEFORE="$2"
                aurelia_plugin_valid_id "$AURELIA_PLACEMENT_BEFORE" || {
                    aurelia_plugin_fail "--before requires a valid widget id"
                    return 1
                }
                shift 2
                ;;
            --after)
                (( $# >= 2 )) || { aurelia_plugin_fail "--after requires a widget id"; return 1; }
                AURELIA_PLACEMENT_AFTER="$2"
                aurelia_plugin_valid_id "$AURELIA_PLACEMENT_AFTER" || {
                    aurelia_plugin_fail "--after requires a valid widget id"
                    return 1
                }
                shift 2
                ;;
            --from-section)
                [[ "$mode" == "move" || "$mode" == "set" ]] || {
                    aurelia_plugin_fail "$mode does not accept --from-section"
                    return 1
                }
                (( $# >= 2 )) || { aurelia_plugin_fail "--from-section requires a section"; return 1; }
                AURELIA_PLACEMENT_FROM_SECTION="$2"
                aurelia_plugin_validate_placement_section "$AURELIA_PLACEMENT_FROM_SECTION" || return 1
                shift 2
                ;;
            --from-index)
                [[ "$mode" == "move" || "$mode" == "set" ]] || {
                    aurelia_plugin_fail "$mode does not accept --from-index"
                    return 1
                }
                (( $# >= 2 )) || { aurelia_plugin_fail "--from-index requires an index"; return 1; }
                AURELIA_PLACEMENT_FROM_INDEX="$2"
                aurelia_plugin_validate_placement_index "$AURELIA_PLACEMENT_FROM_INDEX" || return 1
                shift 2
                ;;
            -h|--help)
                aurelia_plugin_fail "see command help for placement syntax"
                return 1
                ;;
            *)
                aurelia_plugin_fail "unknown placement option: $1"
                return 1
                ;;
        esac
    done

    [[ -z "$AURELIA_PLACEMENT_BEFORE" || -z "$AURELIA_PLACEMENT_AFTER" ]] || {
        aurelia_plugin_fail "use only one of --before or --after"
        return 1
    }
    if [[ "$mode" == "move" && "$positional_section" == "1" ]] &&
       [[ -n "$AURELIA_PLACEMENT_INDEX" || -n "$AURELIA_PLACEMENT_BEFORE" ||
          -n "$AURELIA_PLACEMENT_AFTER" ]]; then
        aurelia_plugin_fail "specify a section positionally or use --index, --before, or --after, not both"
        return 1
    fi
    if [[ -n "$AURELIA_PLACEMENT_FROM_INDEX" && -z "$AURELIA_PLACEMENT_FROM_SECTION" ]]; then
        aurelia_plugin_fail "--from-index requires --from-section"
        return 1
    fi
}

aurelia_plugin_placement_json() {
    command -v jq >/dev/null 2>&1 || {
        aurelia_plugin_fail "jq is required for placement operations"
        return 1
    }
    jq -cn \
        --arg section "$AURELIA_PLACEMENT_SECTION" \
        --arg index "$AURELIA_PLACEMENT_INDEX" \
        --arg before "$AURELIA_PLACEMENT_BEFORE" \
        --arg after "$AURELIA_PLACEMENT_AFTER" \
        --arg from_section "$AURELIA_PLACEMENT_FROM_SECTION" \
        --arg from_index "$AURELIA_PLACEMENT_FROM_INDEX" '
        {}
        + (if $section == "" then {} else {section: $section} end)
        + (if $index == "" then {} else {index: ($index | tonumber)} end)
        + (if $before == "" then {} else {before: $before} end)
        + (if $after == "" then {} else {after: $after} end)
        + (if $from_section == "" then {} else {fromSection: $from_section} end)
        + (if $from_index == "" then {} else {fromIndex: ($from_index | tonumber)} end)
    '
}
