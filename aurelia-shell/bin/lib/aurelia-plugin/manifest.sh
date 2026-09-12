#!/usr/bin/env bash
# Canonical, mutation-free manifest validation used by the plugin CLI and the
# runtime discovery process.

aurelia_plugin_validate_manifest() {
    local plugin_path="$1"
   local allow_first_party="${2:-0}"
   local require_directory_name="${3:-1}"
    local manifest_name="${4:-manifest.json}"
   if [[ "$plugin_path" != /* ]]; then
       plugin_path="$PWD/$plugin_path"
   fi
    if [[ "$manifest_name" != "manifest.json" && ( "$manifest_name" != *.manifest.json || "$manifest_name" == */* || "$manifest_name" == *..* || "$manifest_name" == *\\* ) ]]; then
        aurelia_plugin_fail "Manifest filename must be manifest.json or a sibling *.manifest.json: $manifest_name"
        return 1
    fi
    local manifest_path="$plugin_path/$manifest_name"

    if ! [[ "$plugin_path" == /* && "$plugin_path" != "/" && -d "$plugin_path" && ! -L "$plugin_path" ]]; then
        aurelia_plugin_fail "Plugin path must be an absolute real directory: $plugin_path"
        return 1
    fi
    if ! [[ -f "$manifest_path" && ! -L "$manifest_path" ]]; then
        aurelia_plugin_fail "Plugin manifest is missing or symlinked: $manifest_path"
        return 1
    fi
    if find -P "$plugin_path" -type l -print -quit | grep -q .; then
        aurelia_plugin_fail "Plugin tree contains a symlink: $plugin_path"
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        aurelia_plugin_fail "jq is required to validate Aurelia plugin manifests"
        return 1
    fi

    if ! jq -e '
        def nonempty_string:
            if type != "string" then false
            else length > 0 and test("[^[:space:]]")
            end;
        def safe_icon:
            if type != "string" then false
            else test("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
            end;
        def safe_path:
            if type != "string" then false
            else length > 0
                and (startswith("/") | not)
                and (contains("..") | not)
                and (contains("\\") | not)
                and (contains(":") | not)
                and (test("[\\x00-\\x1f\\x7f]") | not)
            end;
        def safe_setting_key:
            if type != "string" then false
            else test("^[A-Za-z][A-Za-z0-9_.-]*$")
            end;
        def valid_control_type:
            . as $value
            | ($value | type) == "string"
            and (["string", "integer", "number", "boolean", "enum", "path", "multiselect"]
                | index($value) != null);
        def valid_schema_option:
            if type == "string" then nonempty_string
            elif type == "object" then
                ((keys - ["value", "label", "description"]) | length == 0)
                and (.value | nonempty_string)
                and (.label | nonempty_string)
                and (if has("description") then (.description | nonempty_string) else true end)
            else false
            end;
        def valid_schema_item:
            if type != "object" then false
            else
                ((keys - ["key", "type", "label", "description", "min", "max", "step",
                    "defaultValue", "options", "noSelectionText", "placeholderText",
                    "emptyText"]) | length == 0)
                and (.key | safe_setting_key)
                and (.type | valid_control_type)
                and (.label | nonempty_string)
                and (if has("description") then (.description | nonempty_string) else true end)
                and (if has("min") then (.min | type == "number") else true end)
                and (if has("max") then (.max | type == "number") else true end)
                and (if has("step") then (.step | type == "number") else true end)
                and (if has("options") then
                    (.options | type == "array" and all(.[]; valid_schema_option))
                    else true end)
                and (if has("noSelectionText") then (.noSelectionText | nonempty_string) else true end)
                and (if has("placeholderText") then (.placeholderText | nonempty_string) else true end)
                and (if has("emptyText") then (.emptyText | nonempty_string) else true end)
            end;
        def valid_bar_widget:
            if type != "object" then false
            else
                ((keys - ["displayName", "description", "category", "aliases",
                    "allowMultiple", "defaultSection", "defaults", "settingsForm", "schema"])
                    | length == 0)
                and (.displayName | nonempty_string)
                and (.description | nonempty_string)
                and (.category | nonempty_string)
                and (.allowMultiple | type == "boolean")
                and (if has("aliases") then
                    (.aliases | type == "array" and all(.[]; nonempty_string))
                    else true end)
                and (if has("defaultSection") then
                    (.defaultSection as $section
                        | ($section | type) == "string"
                        and (["left", "center", "right"] | index($section) != null))
                    else true end)
                and (if has("defaults") then (.defaults | type == "object") else true end)
                and (if has("settingsForm") then
                    (.settingsForm | type == "string" and test("^$|^[A-Za-z][A-Za-z0-9_.-]*$"))
                    else true end)
                and (if has("schema") then
                    (.schema | type == "array" and all(.[]; valid_schema_item))
                    else true end)
            end;
        def valid_clone_paths:
            if type != "array" then false
            else
                all(.[]; type == "object"
                    and ((keys - ["source", "target"]) | length == 0)
                    and (.source | safe_path)
                    and (.target | safe_path))
                and ((map(.source + "\u0000" + .target) | unique | length) == length)
            end;
        def valid_compatibility:
            if type != "object" then false
            else
                ((keys - ["hostApi"]) | length == 0)
                and (.hostApi | nonempty_string)
            end;
        def valid_aurelia:
            if type != "object" then false
            else
                ((keys - ["icon", "clonePaths", "capabilities", "compatibility"]) | length == 0)
                and (if has("icon") then (.icon | safe_icon) else true end)
                and (if has("clonePaths") then (.clonePaths | valid_clone_paths) else true end)
                and (if has("capabilities") then
                    (.capabilities | type == "array" and all(.[]; safe_setting_key))
                    else true end)
                and (if has("compatibility") then (.compatibility | valid_compatibility) else true end)
            end;
        if type != "object" then false
        else
            .schemaVersion == 1
            and (.id | nonempty_string)
            and (.name | nonempty_string)
            and (.version | nonempty_string)
            and (.description | nonempty_string)
            and (if (.kinds | type) == "array" then (.kinds | length > 0) else false end)
            and (if (.entryPoints | type) == "object"
                then (.entryPoints | length > 0 and all(.[]; safe_path))
                else false end)
            and ((keys - ["schemaVersion", "id", "name", "version", "author",
                "license", "description", "icon", "kinds", "entryPoints", "keepLoaded",
                "activation", "barWidget", "aurelia"]) | length == 0)
            and (if has("author") then (.author | nonempty_string) else true end)
            and (if has("license") then (.license | nonempty_string) else true end)
            and (if has("icon") then (.icon | safe_icon) else true end)
            and (if has("keepLoaded") then (.keepLoaded | type == "boolean") else true end)
            and (if has("activation") then (.activation | . == "on-demand") else true end)
            and (if has("barWidget") then
                ((.kinds | index("bar-widget")) != null and (.barWidget | valid_bar_widget))
                else true end)
            and (if has("aurelia") then (.aurelia | valid_aurelia) else true end)
            and (if (.entryPoints | has("barWidget")) then has("barWidget") else true end)
            and (if has("icon") and has("aurelia")
                and (.aurelia | type == "object" and has("icon")) then false else true end)
        end
    ' "$manifest_path" >/dev/null; then
        if jq -e '
            if has("icon") then
                if (.icon | type) != "string" then true
                else ((.icon | test("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")) | not)
                end
            else false
            end
        ' "$manifest_path" >/dev/null 2>&1; then
            aurelia_plugin_fail "Manifest icon name is invalid: $manifest_path"
            return 1
        fi
        aurelia_plugin_fail "Manifest metadata is invalid: $manifest_path"
        return 1
    fi

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

    local -A seen_kinds=()
    local -A seen_entry_keys=()
    local -a kinds=()
    mapfile -t kinds < <(jq -r '.kinds[]' "$manifest_path")
    local kind entry_key entry_point
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

        if [[ "$kind" == "bar-widget" ]]; then
            if jq -e '.entryPoints | has("barWidget") and has("bar-widget")' "$manifest_path" >/dev/null; then
                aurelia_plugin_fail "Manifest cannot declare both barWidget and bar-widget entry-point keys: $id"
                return 1
            fi
            if jq -e '.entryPoints | has("barWidget")' "$manifest_path" >/dev/null; then
                entry_key="barWidget"
            else
                entry_key="bar-widget"
            fi
        else
            entry_key="$kind"
        fi

        entry_point="$(jq -r --arg key "$entry_key" '.entryPoints[$key] // empty' "$manifest_path")"
        [[ -n "$entry_point" ]] || {
            aurelia_plugin_fail "Missing entry point for '$kind' in $id"
            return 1
        }
        [[ -f "$plugin_path/$entry_point" && ! -L "$plugin_path/$entry_point" ]] || {
            aurelia_plugin_fail "Entry point does not exist for '$kind' in $id: $entry_point"
            return 1
        }
        seen_entry_keys[$entry_key]=1
    done

    local manifest_entry_key
    while IFS= read -r manifest_entry_key; do
        case "$manifest_entry_key" in
            bar-widget|barWidget|bar|panel|overlay|menu|service) ;;
            *)
                aurelia_plugin_fail "Manifest contains an unexpected entry-point key '$manifest_entry_key' in $id"
                return 1
                ;;
        esac
        [[ -n "${seen_entry_keys[$manifest_entry_key]:-}" ]] || {
            aurelia_plugin_fail "Manifest contains an unexpected entry-point key '$manifest_entry_key' in $id"
            return 1
        }
    done < <(jq -r '.entryPoints | keys[]' "$manifest_path")

    if [[ "$allow_first_party" != "1" ]] &&
        jq -e '.aurelia.capabilities? != null' "$manifest_path" >/dev/null 2>&1; then
        aurelia_plugin_fail "Third-party plugins cannot declare trusted Aurelia capabilities: $id"
        return 1
    fi

    return 0
}

aurelia_plugin_manifest_id() {
    jq -r '.id' "$1/manifest.json"
}
