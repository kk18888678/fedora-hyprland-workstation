#!/usr/bin/env bash
# Manifest validation shared by the plugin CLI and repository tests.

aurelia_plugin_validate_manifest() {
    local plugin_path="$1"
    local allow_first_party="${2:-0}"
    local require_directory_name="${3:-1}"
    if [[ "$plugin_path" != /* ]]; then
        plugin_path="$PWD/$plugin_path"
    fi
    local manifest_path="$plugin_path/manifest.json"

    [[ "$plugin_path" == /* && "$plugin_path" != "/" && -d "$plugin_path" && ! -L "$plugin_path" ]] ||
        aurelia_plugin_fail "Plugin path must be an absolute real directory: $plugin_path"
    [[ -f "$manifest_path" && ! -L "$manifest_path" ]] ||
        aurelia_plugin_fail "Plugin manifest is missing or symlinked: $manifest_path"

    if find -P "$plugin_path" -type l -print -quit | grep -q .; then
        aurelia_plugin_fail "Plugin tree contains a symlink: $plugin_path"
        return 1
    fi
    command -v jq >/dev/null 2>&1 || aurelia_plugin_fail "jq is required to validate Aurelia plugin manifests"

    jq -e '
        .schemaVersion == 1 and
        (.id | type == "string") and
        (.name | type == "string" and length > 0) and
        (.version | type == "string" and length > 0) and
        (.kinds | type == "array" and length > 0) and
        (.entryPoints | type == "object")
    ' "$manifest_path" >/dev/null || {
        aurelia_plugin_fail "Manifest metadata is invalid: $manifest_path"
        return 1
    }

    local id
    id="$(jq -r '.id' "$manifest_path")"
    aurelia_plugin_valid_id "$id" || {
        aurelia_plugin_fail "Manifest id is invalid: $id"
        return 1
    }
    if [[ "$allow_first_party" != "1" && "$id" == aurelia.* ]]; then
        aurelia_plugin_fail "The aurelia. namespace is reserved for first-party plugins: $id"
        return 1
    fi
    if [[ "$allow_first_party" == "1" && "$id" != aurelia.* ]]; then
        aurelia_plugin_fail "First-party plugin ids must use the aurelia. namespace: $id"
        return 1
    fi
    if [[ "$require_directory_name" == "1" ]] && [[ "$(basename -- "$plugin_path")" != "$id" ]]; then
        aurelia_plugin_fail "Plugin directory must be named after its manifest id: $id"
        return 1
    fi

    local -a kinds=()
    mapfile -t kinds < <(jq -r '.kinds[]' "$manifest_path")
    local -A seen_kinds=()
    local kind entry_point
    for kind in "${kinds[@]}"; do
        case "$kind" in
            bar-widget|bar|panel|overlay|menu|service) ;;
            *) aurelia_plugin_fail "Unsupported plugin kind '$kind' in $id"; return 1 ;;
        esac
        [[ -z "${seen_kinds[$kind]:-}" ]] || {
            aurelia_plugin_fail "Duplicate plugin kind '$kind' in $id"
            return 1
        }
        seen_kinds[$kind]=1
        entry_point="$(jq -r --arg kind "$kind" '.entryPoints[$kind] // empty' "$manifest_path")"
        [[ -n "$entry_point" && "$entry_point" != /* && "$entry_point" != *..* && "$entry_point" != *\\* && "$entry_point" != *:* ]] || {
            aurelia_plugin_fail "Unsafe entry point for '$kind' in $id"
            return 1
        }
        [[ -f "$plugin_path/$entry_point" && ! -L "$plugin_path/$entry_point" ]] || {
            aurelia_plugin_fail "Entry point does not exist for '$kind' in $id: $entry_point"
            return 1
        }
    done

    local extra_entry
    while IFS= read -r extra_entry; do
        [[ -n "$extra_entry" && "$extra_entry" != /* && "$extra_entry" != *..* && "$extra_entry" != *\\* && "$extra_entry" != *:* ]] || {
            aurelia_plugin_fail "Unsafe entry point in $id"
            return 1
        }
    done < <(jq -r '.entryPoints[]' "$manifest_path")
}

aurelia_plugin_manifest_id() {
    jq -r '.id' "$1/manifest.json"
}
