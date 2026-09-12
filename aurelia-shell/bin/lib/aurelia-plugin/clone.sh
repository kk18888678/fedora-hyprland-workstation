#!/usr/bin/env bash
# Built-in plugin cloning. This module copies first-party source only; it never
# evaluates plugin code or install hooks.

aurelia_plugin_clone_first_party_root() {
    local candidate="${AURELIA_FIRST_PARTY_PLUGIN_DIR:-}"
    if [[ -z "$candidate" ]]; then
        if [[ "${AURELIA_SHELL_ROOT:-}" == /* && "${AURELIA_SHELL_ROOT}" != "/" ]]; then
            candidate="${AURELIA_SHELL_ROOT%/}/plugins"
        else
            local bin_root="${AURELIA_PLUGIN_BIN_DIR:-${script_dir:-}}"
            [[ "$bin_root" == /* ]] || {
                aurelia_plugin_fail "Could not resolve the packaged Aurelia plugin tree"
                return 1
            }
            candidate="$(cd -- "$bin_root/../plugins" 2>/dev/null && pwd -P)" || {
                aurelia_plugin_fail "Could not resolve the packaged Aurelia plugin tree"
                return 1
            }
        fi
    fi
    [[ "$candidate" == /* && "$candidate" != "/" && -d "$candidate" && ! -L "$candidate" ]] || {
        aurelia_plugin_fail "First-party Aurelia plugin tree is unavailable: $candidate"
        return 1
    }

    local first_party_real user_real
    first_party_real="$(readlink -f -- "$candidate" 2>/dev/null || true)"
    user_real="$(readlink -m -- "$aurelia_plugin_dir" 2>/dev/null || true)"
    [[ -n "$first_party_real" && "$first_party_real" != "/" && -n "$user_real" ]] || {
        aurelia_plugin_fail "Could not resolve the Aurelia plugin tree safely"
        return 1
    }
    [[ "$first_party_real" != "$user_real" && "$first_party_real" != "$user_real/"* &&
        "$user_real" != "$first_party_real/"* ]] || {
        aurelia_plugin_fail "First-party and user plugin trees must be separate"
        return 1
    }
    printf '%s\n' "$first_party_real"
}

aurelia_plugin_clone_tree_safe() {
    local path="$1"
    [[ -d "$path" && ! -L "$path" ]] || {
        aurelia_plugin_fail "Clone source is not a real directory: $path"
        return 1
    }
    if find -P "$path" -mindepth 1 \( -type l -o \( ! -type f -a ! -type d \) \) -print -quit | grep -q .; then
        aurelia_plugin_fail "Clone source contains a symlink or special file: $path"
        return 1
    fi
}

aurelia_plugin_clone_path_safe() {
    local value="$1"
    if [[ -z "$value" || "$value" == /* || "$value" == *..* ||
        "$value" == *:* || "$value" == *$'\n'* || "$value" == *$'\r'* ||
        "$value" == "." || "$value" == */. || "$value" == ./* ]]; then
        aurelia_plugin_fail "Invalid clone path: $value"
        return 1
    fi
}

aurelia_plugin_clone_find_source() {
    local source_id="$1"
    local first_party_root="$2"
    local found=0 manifest_path manifest_name source_dir source_name manifest_id
    while IFS= read -r -d '' manifest_path; do
        manifest_name="${manifest_path##*/}"
        if [[ "$manifest_name" == "manifest.json" ]]; then
            source_dir="${manifest_path%/manifest.json}"
        else
            source_dir="${manifest_path%/*}"
        fi
        [[ -d "$source_dir" && ! -L "$source_dir" ]] || continue
        if ! manifest_id="$(jq -r '.id // empty' "$manifest_path" 2>/dev/null)"; then
            continue
        fi
        [[ "$manifest_id" == "$source_id" ]] || continue
        if (( found )); then
            aurelia_plugin_fail "First-party plugin id is duplicated: $source_id"
            return 1
        fi
        found=1
        AURELIA_CLONE_SOURCE_DIR="$source_dir"
        AURELIA_CLONE_SOURCE_MANIFEST="$manifest_path"
        AURELIA_CLONE_SOURCE_MANIFEST_NAME="$manifest_name"
        source_name="$(jq -r '.name // .id' "$manifest_path")"
        AURELIA_CLONE_SOURCE_NAME="$source_name"
    done < <(find -P "$first_party_root" -mindepth 2 -maxdepth 3 -type f \
        \( -name manifest.json -o -name '*.manifest.json' \) -print0 | LC_ALL=C sort -z)

    (( found )) || {
        aurelia_plugin_fail "Unknown first-party Aurelia plugin: $source_id"
        return 1
    }
}

aurelia_plugin_clone_copy_dependency() {
    local source_dir="$1"
    local stage_dir="$2"
    local source="$3"
    local target="$4"
    local source_root_real source_real source_path target_path

    aurelia_plugin_clone_path_safe "$source" || return 1
    aurelia_plugin_clone_path_safe "$target" || return 1
    [[ "$target" != "manifest.json" ]] || {
        aurelia_plugin_fail "Clone target cannot replace manifest.json"
        return 1
    }
    source_path="$source_dir/$source"
    [[ -e "$source_path" && ! -L "$source_path" ]] || {
        aurelia_plugin_fail "Declared clone dependency is missing: $source"
        return 1
    }
    source_root_real="$(readlink -f -- "$source_dir")"
    source_real="$(readlink -f -- "$source_path" 2>/dev/null || true)"
    [[ -n "$source_real" && ( "$source_real" == "$source_root_real" || "$source_real" == "$source_root_real/"* ) ]] || {
        aurelia_plugin_fail "Declared clone dependency escapes the plugin source: $source"
        return 1
    }
    target_path="$stage_dir/$target"
    if [[ -d "$source_path" ]]; then
        aurelia_plugin_clone_tree_safe "$source_path" || return 1
        mkdir -p -- "$target_path"
        cp -a -- "$source_path/." "$target_path/"
    elif [[ -f "$source_path" ]]; then
        mkdir -p -- "$(dirname -- "$target_path")"
        cp -a -- "$source_path" "$target_path"
    else
        aurelia_plugin_fail "Declared clone dependency is not a regular file or directory: $source"
        return 1
    fi
}

aurelia_plugin_clone_rewrite_references() {
    local stage_dir="$1"
    local source="$2"
    local target="$3"
    local file temporary
    [[ "$source" != "$target" ]] || return 0

    while IFS= read -r -d '' file; do
        LC_ALL=C grep -IqF -- "$source" "$file" || continue
        temporary="$(mktemp "${file}.aurelia-clone.XXXXXX")" || return 1
        if ! awk -v old="$source" -v replacement="$target" '
            {
                remaining = $0
                rendered = ""
                while ((position = index(remaining, old)) > 0) {
                    rendered = rendered substr(remaining, 1, position - 1) replacement
                    remaining = substr(remaining, position + length(old))
                }
                print rendered remaining
            }
        ' "$file" >"$temporary"; then
            rm -f -- "$temporary"
            return 1
        fi
        chmod --reference="$file" "$temporary" || {
            rm -f -- "$temporary"
            return 1
        }
        mv -- "$temporary" "$file" || {
            rm -f -- "$temporary"
            return 1
        }
    done < <(find -P "$stage_dir" -type f -print0)
}

aurelia_plugin_clone_copy_source() {
    local source_dir="$1"
    local manifest_path="$2"
    local stage_dir="$3"
    local manifest_name="${manifest_path##*/}"
    local source target

    if [[ "$manifest_name" == "manifest.json" ]]; then
        aurelia_plugin_clone_tree_safe "$source_dir" || return 1
        cp -a -- "$source_dir/." "$stage_dir/"
        return 0
    fi

    cp -- "$manifest_path" "$stage_dir/manifest.json"
    while IFS=$'\t' read -r source target; do
        [[ -n "$source" && -n "$target" ]] || continue
        aurelia_plugin_clone_copy_dependency "$source_dir" "$stage_dir" "$source" "$target" || return 1
        aurelia_plugin_clone_rewrite_references "$stage_dir" "$source" "$target" || return 1
    done < <(jq -r '
        [
          (.entryPoints | to_entries[] | {source: .value, target: .value}),
          (.aurelia.clonePaths[]? | {source: .source, target: .target})
        ] | unique_by(.target)[] | [.source, .target] | @tsv
    ' "$manifest_path")
}

aurelia_plugin_clone_update_manifest() {
    local target_dir="$1"
    local source_id="$2"
    local new_id="$3"
    local display_name="$4"
    local manifest="$target_dir/manifest.json"
    local temporary
    temporary="$(mktemp "$target_dir/.manifest.XXXXXX")" || return 1
    if ! jq --arg id "$new_id" --arg name "$display_name" --arg sourceId "$source_id" '
        .id = $id |
        .name = $name |
        if (.barWidget | type) == "object" then .barWidget.displayName = $name else . end |
        .aurelia = ((if (.aurelia | type) == "object" then .aurelia else {} end) +
            {clonedFrom: $sourceId}) |
        del(.aurelia.clonePaths, .aurelia.capabilities)
    ' "$manifest" >"$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    chmod --reference="$manifest" "$temporary" || {
        rm -f -- "$temporary"
        return 1
    }
    mv -- "$temporary" "$manifest"
}

aurelia_plugin_clone_user_prefix() {
    local raw_user="${USER:-}"
    [[ -n "$raw_user" ]] || raw_user="$(id -un 2>/dev/null || true)"
    local safe_user
    safe_user="$(printf '%s' "$raw_user" | sed 's/[^A-Za-z0-9_.-]/_/g; s/^[^A-Za-z0-9]*//')"
    while [[ "$safe_user" == *".."* ]]; do safe_user="${safe_user//../_}"; done
    aurelia_plugin_valid_id "$safe_user" || safe_user="user"
    printf '%s\n' "$safe_user"
}

aurelia_plugin_clone_choose_id() {
    local source_id="$1"
    local prefix candidate target suffix
    prefix="$(aurelia_plugin_clone_user_prefix).${source_id#aurelia.}"
    for (( suffix = 0; suffix < 1000; suffix++ )); do
        candidate="$prefix"
        (( suffix > 0 )) && candidate="$prefix.$suffix"
        aurelia_plugin_valid_id "$candidate" || continue
        target="$(aurelia_plugin_target "$candidate")" || return 1
        if [[ ! -e "$target" && ! -L "$target" ]]; then
            AURELIA_CLONE_NEW_ID="$candidate"
            AURELIA_CLONE_TARGET="$target"
            return 0
        fi
    done
    aurelia_plugin_fail "Could not allocate a collision-safe clone id for $source_id"
    return 1
}

aurelia_plugin_clone_cleanup() {
    local stage="${AURELIA_PLUGIN_CLONE_STAGE:-}"
    local target="${AURELIA_PLUGIN_CLONE_TARGET:-}"
    local plugin_prefix="${aurelia_plugin_dir%/}/"
    if [[ -n "$stage" && "$stage" == "$plugin_prefix".clone.* && -d "$stage" && ! -L "$stage" ]]; then
        rm -rf -- "$stage"
    fi
    if [[ "${AURELIA_PLUGIN_CLONE_CLEANUP_TARGET:-1}" == "1" &&
        -n "$target" && "$target" == "$plugin_prefix"* && "$target" != "$plugin_prefix" &&
        -d "$target" && ! -L "$target" ]]; then
        rm -rf -- "$target"
    fi
}

aurelia_plugin_clone_open_editor() {
    local target="$1"
    local editor_text="${EDITOR:-vi}"
    [[ "$editor_text" != *$'\n'* && "$editor_text" != *$'\r'* ]] || {
        aurelia_plugin_fail "EDITOR contains a control character"
        return 1
    }
    local -a editor_argv=()
    read -r -a editor_argv <<<"$editor_text"
    ((${#editor_argv[@]} > 0)) || {
        aurelia_plugin_fail "EDITOR is empty"
        return 1
    }
    "${editor_argv[@]}" "$target"
}

aurelia_plugin_clone() {
    local source_id="${1:-}"
    shift || true
    local edit_clone=0 arg first_party_root stage display_name

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --edit) edit_clone=1; shift ;;
            -h|--help)
                printf 'Usage: aurelia-plugin clone <aurelia.plugin-id> [--edit]\n'
                return 0
                ;;
            *)
                aurelia_plugin_fail "Unknown clone option: $1"
                return 1
                ;;
        esac
    done
    [[ -n "$source_id" ]] || {
        aurelia_plugin_fail "clone source is required"
        return 1
    }
    aurelia_plugin_valid_id "$source_id" && [[ "$source_id" == aurelia.* ]] || {
        aurelia_plugin_fail "Only first-party aurelia.* plugins can be cloned: $source_id"
        return 1
    }
    aurelia_plugin_require_root || return 1
    first_party_root="$(aurelia_plugin_clone_first_party_root)" || return 1
    aurelia_plugin_clone_find_source "$source_id" "$first_party_root" || return 1
    aurelia_plugin_validate_manifest "$AURELIA_CLONE_SOURCE_DIR" 1 0 \
        "$AURELIA_CLONE_SOURCE_MANIFEST_NAME" || return 1
    aurelia_plugin_clone_choose_id "$source_id" || return 1
    display_name="My $AURELIA_CLONE_SOURCE_NAME"
    AURELIA_PLUGIN_CLONE_TARGET="$AURELIA_CLONE_TARGET"

    stage="$(mktemp -d "$aurelia_plugin_dir/.clone.XXXXXX")" || return 1
    AURELIA_PLUGIN_CLONE_STAGE="$stage"
    AURELIA_PLUGIN_CLONE_CLEANUP_TARGET=1
    trap 'aurelia_plugin_clone_cleanup' EXIT

    if ! aurelia_plugin_clone_copy_source "$AURELIA_CLONE_SOURCE_DIR" \
        "$AURELIA_CLONE_SOURCE_MANIFEST" "$stage"; then
        aurelia_plugin_fail "Could not copy first-party plugin source: $source_id"
        return 1
    fi
    aurelia_plugin_clone_update_manifest "$stage" "$source_id" "$AURELIA_CLONE_NEW_ID" "$display_name" || {
        aurelia_plugin_fail "Could not write clone manifest: $AURELIA_CLONE_NEW_ID"
        return 1
    }
    aurelia_plugin_validate_manifest "$stage" 0 0 || return 1
    mv -- "$stage" "$AURELIA_CLONE_TARGET" || {
        aurelia_plugin_fail "Could not publish clone: $AURELIA_CLONE_TARGET"
        return 1
    }
    AURELIA_PLUGIN_CLONE_STAGE=""

    if ! aurelia_plugin_reload_shell; then
        aurelia_plugin_fail "Cloned plugin was not rescanned: $AURELIA_CLONE_NEW_ID"
        return 1
    fi
    if ! aurelia_plugin_wait_for_scan "$(aurelia_plugin_shell_cli)" "$AURELIA_CLONE_NEW_ID"; then
        aurelia_plugin_fail "Cloned plugin '$AURELIA_CLONE_NEW_ID' was not discovered"
        return 1
    fi
    if ! aurelia_plugin_enable "$AURELIA_CLONE_NEW_ID"; then
        if ! aurelia_plugin_set_enabled "$AURELIA_CLONE_NEW_ID" false >/dev/null 2>&1; then
            AURELIA_PLUGIN_CLONE_CLEANUP_TARGET=0
            aurelia_plugin_fail "Clone enablement failed and state rollback could not be confirmed; preserving $AURELIA_CLONE_TARGET"
            return 1
        fi
        aurelia_plugin_fail "Could not enable cloned plugin: $AURELIA_CLONE_NEW_ID"
        return 1
    fi

    AURELIA_PLUGIN_CLONE_CLEANUP_TARGET=0
    trap - EXIT
    printf 'Cloned %s to %s and switched to %s.\n' "$source_id" "$AURELIA_CLONE_TARGET" "$AURELIA_CLONE_NEW_ID"
    if (( edit_clone )); then
        aurelia_plugin_clone_open_editor "$AURELIA_CLONE_TARGET"
    fi
}
