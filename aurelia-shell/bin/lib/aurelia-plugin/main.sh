#!/usr/bin/env bash
# User-facing Aurelia Shell plugin lifecycle commands.

print_aurelia_plugin_help() {
    cat <<'USAGE'
Usage: aurelia-plugin <command> [arguments]

Commands:
  validate [--first-party] [--manifest-file <name>] <directory>
  list
  catalog [--json]
  rescan
  list [--json]
  enable <plugin-id> [placement]
  disable <plugin-id>
  clone <aurelia.plugin-id> [--edit]
  add [<https-git-url>] [--enable] [--yes]
  update [<plugin-id>|--all] [--yes]
  remove <plugin-id> [--yes]

Third-party plugins are user-owned, unsandboxed QML code. Review a plugin
before enabling it. The CLI never runs plugin install hooks.

Enable placement: --section <left|center|right>, --index <n>,
--before <plugin-id>, or --after <plugin-id>.
USAGE
}

aurelia_plugin_wait_for_scan() {
    local shell_cli="$1"
    local plugin_id="$2"
    local listing
    for _ in {1..20}; do
        listing="$("$shell_cli" shell listPlugins 2>/dev/null || true)"
        if jq -e --arg id "$plugin_id" '.[] | select(.id == $id)' <<< "$listing" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

aurelia_plugin_reload_shell() {
    local shell_cli result
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    result="$("$shell_cli" shell rescanPlugins)" || return 1
    [[ "$result" == "ok" ]] || {
        aurelia_plugin_fail "$result"
        return 1
    }
}

aurelia_plugin_set_enabled() {
    local plugin_id="$1"
    local enabled="$2"
    aurelia_plugin_require_id "$plugin_id" || return 1
    local shell_cli
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    aurelia_plugin_wait_for_scan "$shell_cli" "$plugin_id" || {
        aurelia_plugin_fail "Plugin is not present in the resident registry: $plugin_id"
        return 1
    }
    if [[ "$enabled" == "true" ]]; then
        local enable_result
        enable_result="$("$shell_cli" shell enablePlugin "$plugin_id" "{}")" || return 1
        [[ "$enable_result" == "ok" ]] || {
            aurelia_plugin_fail "$enable_result"
            return 1
        }
    else
        local disable_result
        disable_result="$("$shell_cli" shell setPluginEnabled "$plugin_id" "$enabled")" || return 1
        [[ "$disable_result" == "ok" ]] || {
            aurelia_plugin_fail "$disable_result"
            return 1
        }
    fi
}

aurelia_plugin_enable() {
    local plugin_id="$1"
    shift
    aurelia_plugin_require_id "$plugin_id" || return 1
    aurelia_plugin_parse_placement enable 1 "$@" || return 1
    local placement shell_cli result
    placement="$(aurelia_plugin_placement_json)" || return 1
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    aurelia_plugin_wait_for_scan "$shell_cli" "$plugin_id" || {
        aurelia_plugin_fail "Plugin is not present in the resident registry: $plugin_id"
        return 1
    }
    result="$("$shell_cli" shell enablePlugin "$plugin_id" "$placement")" || return 1
    [[ "$result" == "ok" ]] || {
        aurelia_plugin_fail "$result"
        return 1
    }
    if [[ "$placement" == "{}" ]]; then
        printf 'Enabled %s.\n' "$plugin_id"
    else
        printf 'Enabled and placed %s.\n' "$plugin_id"
    fi
}

aurelia_plugin_list() {
    local json=0 arg shell_cli listing
    for arg in "$@"; do
        case "$arg" in
            --json) json=1 ;;
            *) aurelia_plugin_fail "Unknown list option: $arg"; return 1 ;;
        esac
    done
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    listing="$("$shell_cli" shell listPlugins)" || return 1
    jq -e 'type == "array"' <<<"$listing" >/dev/null || {
        aurelia_plugin_fail "Resident shell returned an invalid plugin list"
        return 1
    }
    if [[ "$json" -eq 1 ]]; then
        printf '%s\n' "$listing"
        return 0
    fi
    printf 'ID\tSOURCE\tKIND\tENABLED\tACTIVE\tLOADED\tVISIBLE\tIN-BAR\tCAN-DISABLE\tCLONE-OF\tERROR\n'
    jq -r '.[] | [
        .id,
        (.source // (if .firstParty then "first-party" else "user" end)),
        (.kind // ((.kinds // []) | join(","))),
        (if .enabled then "yes" else "no" end),
        (if .active then "yes" else "no" end),
        (if .loaded then "yes" else "no" end),
        (if .visible then "yes" else "no" end),
        (if .inBar then "yes" else "no" end),
        (if .canDisable then "yes" else "no" end),
        (.clonedFrom // "-"),
        (if .errorState then (.errorState.detail // .errorState.reason // "error") else "" end)
    ] | @tsv' <<<"$listing"
}

aurelia_plugin_main() {
    local command="${1:-help}"
    shift || true
    case "$command" in
        help|-h|--help)
            print_aurelia_plugin_help
            ;;
        validate)
            local allow_first_party=0
           local manifest_name="manifest.json"
           local validate_path=""
            local manifest_file_explicit=0
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --first-party)
                        allow_first_party=1
                        shift
                        ;;
                    --manifest-file)
                        [[ $# -ge 2 ]] || {
                            aurelia_plugin_fail "Usage: aurelia-plugin validate [--first-party] [--manifest-file <name>] <directory>"
                            return 1
                       }
                       manifest_name="$2"
                        manifest_file_explicit=1
                       shift 2
                        ;;
                    --*)
                        aurelia_plugin_fail "Unknown validate option: $1"
                        return 1
                        ;;
                    *)
                        [[ -z "$validate_path" ]] || {
                            aurelia_plugin_fail "Usage: aurelia-plugin validate [--first-party] [--manifest-file <name>] <directory>"
                            return 1
                        }
                        validate_path="$1"
                        shift
                        ;;
                esac
            done
            [[ -n "$validate_path" ]] || {
                aurelia_plugin_fail "Usage: aurelia-plugin validate [--first-party] [--manifest-file <name>] <directory>"
                return 1
           }
           local require_directory_name=1
            [[ "$manifest_file_explicit" -eq 1 ]] && require_directory_name=0
           aurelia_plugin_validate_manifest "$validate_path" "$allow_first_party" "$require_directory_name" "$manifest_name" || return 1
            printf 'Valid Aurelia plugin: %s\n' "$(jq -r '.id' "$validate_path/$manifest_name")"
            ;;
        catalog)
            [[ $# -eq 0 || ( $# -eq 1 && "$1" == "--json" ) ]] || {
                aurelia_plugin_fail "Usage: aurelia-plugin catalog [--json]"
                return 1
            }
            local catalog_shell_cli catalog_json
            catalog_shell_cli="$(aurelia_plugin_shell_cli)" || return 1
            catalog_json="$("$catalog_shell_cli" shell catalogPlugins)" || return 1
            jq -e 'type == "object" and (.plugins | type == "array") and (.rejected | type == "array") and (.scan | type == "object")' \
                <<<"$catalog_json" >/dev/null || {
                aurelia_plugin_fail "Resident shell returned an invalid plugin catalog"
                return 1
            }
            if [[ "${1:-}" == "--json" ]]; then
                printf '%s\n' "$catalog_json"
            else
                printf 'Plugin catalog (%s plugins, scan=%s)\n' \
                    "$(jq -r '.plugins | length' <<<"$catalog_json")" \
                    "$(jq -r '.scan.state // "unknown"' <<<"$catalog_json")"
                printf 'ID\tVERSION\tSOURCE\tKINDS\tROOT\n'
                jq -r '.plugins[] | [.id, .version, (if .firstParty then "first-party" else "third-party" end), (.kinds | join(",")), .sourceRoot] | @tsv' \
                    <<<"$catalog_json"
                if [[ "$(jq -r '.rejected | length' <<<"$catalog_json")" -gt 0 ]]; then
                    printf '\nRejected manifests:\n'
                    jq -r '.rejected[] | [.manifestPath, .reason] | @tsv' <<<"$catalog_json"
                fi
            fi
            ;;
        list)
            aurelia_plugin_list "$@"
            ;;
        rescan)
            [[ $# -eq 0 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin rescan"; return 1; }
            aurelia_plugin_reload_shell
            ;;
        enable)
            [[ $# -ge 1 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin enable <plugin-id> [placement]"; return 1; }
            local enable_id="$1"
            shift
            aurelia_plugin_enable "$enable_id" "$@"
            ;;
        disable)
            [[ $# -eq 1 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin disable <plugin-id>"; return 1; }
            aurelia_plugin_set_enabled "$1" false
            ;;
        clone)
            [[ $# -ge 1 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin clone <aurelia.plugin-id> [--edit]"; return 1; }
            aurelia_plugin_clone "$@"
            ;;
        add)
            aurelia_plugin_add "$@"
            ;;
        update)
            aurelia_plugin_update "$@"
            ;;
        remove)
            aurelia_plugin_remove "$@"
            ;;
        *)
            aurelia_plugin_fail "Unknown command: $command"
            print_aurelia_plugin_help >&2
            return 1
            ;;
    esac
}
