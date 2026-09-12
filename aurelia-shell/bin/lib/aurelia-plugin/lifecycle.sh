#!/usr/bin/env bash
# Add, update, and remove user-owned Aurelia Shell plugins.
#
# This module owns staged lifecycle mutation. It deliberately keeps network
# acquisition, validation, publication, resident discovery, and rollback
# separate so an untrusted plugin tree is never activated before it is known.

AURELIA_PLUGIN_STAGING=""
AURELIA_PLUGIN_UPDATE_ACTIVE=0
AURELIA_PLUGIN_UPDATE_PUBLISHED=0
AURELIA_PLUGIN_UPDATE_STAGE=""
AURELIA_PLUGIN_UPDATE_TARGET=""
AURELIA_PLUGIN_UPDATE_BACKUP_ROOT=""
AURELIA_PLUGIN_UPDATE_BACKUP=""

aurelia_plugin_interactive() {
    [[ -t 0 && -t 1 ]]
}

aurelia_plugin_confirm() {
    local assume_yes="$1"
    local prompt="$2"
    (( assume_yes )) && return 0
    if ! aurelia_plugin_interactive; then
        aurelia_plugin_fail "$prompt requires an interactive terminal or --yes"
        return 1
    fi
    local answer
    printf '%s [y/N] ' "$prompt" >&2
    IFS= read -r answer || return 1
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || return 2
}

aurelia_plugin_clone_remote() {
    local remote_url="$1"
    local destination="$2"
    [[ "$remote_url" =~ ^https://[^[:space:]]+$ ]] || {
        aurelia_plugin_fail "Only HTTPS git URLs are accepted"
        return 1
    }
    [[ "$remote_url" != *::* ]] || {
        aurelia_plugin_fail "Git transport-helper URLs are not accepted"
        return 1
    }
    local timeout_bin
    timeout_bin="$(aurelia_plugin_require_timeout)" || return 1
    env \
        -u GIT_CONFIG_COUNT \
        -u GIT_SSH_COMMAND \
        -u GIT_PROXY_COMMAND \
        -u GIT_ASKPASS \
        -u GIT_EXTENSIONS \
        GIT_TERMINAL_PROMPT=0 \
        GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_SYSTEM=/dev/null \
        GIT_ALLOW_PROTOCOL=https \
        "$timeout_bin" --kill-after=5s 60s git clone --depth 1 --no-tags -- \
        "$remote_url" "$destination"
}

aurelia_plugin_catalog_json() {
    local shell_cli catalog_json
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    catalog_json="$("$shell_cli" shell catalogPlugins)" || {
        aurelia_plugin_fail "Could not inspect the resident Aurelia plugin catalog"
        return 1
    }
    jq -e 'type == "object" and (.plugins | type == "array") and
        (.rejected | type == "array") and (.scan | type == "object")' \
        <<<"$catalog_json" >/dev/null || {
        aurelia_plugin_fail "Resident shell returned an invalid plugin catalog"
        return 1
    }
    printf '%s\n' "$catalog_json"
}

aurelia_plugin_git_commit() {
    local plugin_path="$1"
    local commit
    commit="$(git -C "$plugin_path" rev-parse --verify HEAD 2>/dev/null)" || {
        aurelia_plugin_fail "Could not record the selected Git commit for $plugin_path"
        return 1
    }
    [[ -n "$commit" ]] || {
        aurelia_plugin_fail "Git returned an empty selected commit for $plugin_path"
        return 1
    }
    printf '%s\n' "$commit"
}

aurelia_plugin_manifest_version() {
    jq -r '.version' "$1/manifest.json"
}

aurelia_plugin_write_provenance() {
    local plugin_path="$1"
    local remote_url="$2"
    local selected_ref="$3"
    local commit="$4"
    local validation="$5"
    local version="$6"
    local provenance="$plugin_path/.aurelia-provenance.json"
    local temporary

    [[ -d "$plugin_path" && ! -L "$plugin_path" ]] || {
        aurelia_plugin_fail "Provenance target is not a real plugin directory: $plugin_path"
        return 1
    }
    [[ ! -L "$provenance" ]] || {
        aurelia_plugin_fail "Refusing a symlinked Aurelia provenance file: $provenance"
        return 1
    }
    temporary="$(mktemp "$plugin_path/.aurelia-provenance.XXXXXX")" || return 1
    if ! jq -n \
        --arg source "git" \
        --arg remote "$remote_url" \
        --arg selectedRef "$selected_ref" \
        --arg commit "$commit" \
        --arg validation "$validation" \
        --arg version "$version" \
        '{
            schemaVersion: 1,
            source: $source,
            remote: $remote,
            ref: $selectedRef,
            commit: $commit,
            version: $version,
            validation: $validation
        }' >"$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    chmod 600 -- "$temporary" || {
        rm -f -- "$temporary"
        return 1
    }
    mv -- "$temporary" "$provenance" || {
        rm -f -- "$temporary"
        return 1
    }
}

aurelia_plugin_review_candidate() {
    local plugin_path="$1"
    printf 'Plugin candidate: %s\n' "$(jq -r '.id + \" — \" + .name' "$plugin_path/manifest.json")" >&2
    printf 'Files to install:\n' >&2
    find -P "$plugin_path" -mindepth 1 -type f ! -name '.git*' -printf '  %P\n' |
        LC_ALL=C sort >&2
}

aurelia_plugin_lifecycle_cleanup() {
    local staging="$AURELIA_PLUGIN_STAGING"
    local plugin_prefix="$aurelia_plugin_dir/"
    if [[ -n "$staging" && "$staging" == "$plugin_prefix".add.* && -d "$staging" && ! -L "$staging" ]]; then
        rm -rf -- "$staging"
    elif [[ -n "$staging" && "$staging" == "$plugin_prefix".update.* && -d "$staging" && ! -L "$staging" ]]; then
        rm -rf -- "$staging"
    fi
    if [[ "$AURELIA_PLUGIN_UPDATE_ACTIVE" == "1" &&
          "$AURELIA_PLUGIN_UPDATE_PUBLISHED" == "1" ]]; then
        aurelia_plugin_update_rollback >/dev/null 2>&1 || true
    fi
}

aurelia_plugin_update_reset() {
    AURELIA_PLUGIN_UPDATE_ACTIVE=0
    AURELIA_PLUGIN_UPDATE_PUBLISHED=0
    AURELIA_PLUGIN_UPDATE_STAGE=""
    AURELIA_PLUGIN_UPDATE_TARGET=""
    AURELIA_PLUGIN_UPDATE_BACKUP_ROOT=""
    AURELIA_PLUGIN_UPDATE_BACKUP=""
    AURELIA_PLUGIN_STAGING=""
}

aurelia_plugin_update_stage_cleanup() {
    local staging="$AURELIA_PLUGIN_UPDATE_STAGE"
    local prefix="$aurelia_plugin_dir/"
    if [[ -n "$staging" && "$staging" == "$prefix".update.* && -d "$staging" && ! -L "$staging" ]]; then
        rm -rf -- "$staging"
    fi
    AURELIA_PLUGIN_UPDATE_STAGE=""
    AURELIA_PLUGIN_STAGING=""
}

aurelia_plugin_update_rollback() {
    [[ "$AURELIA_PLUGIN_UPDATE_PUBLISHED" == "1" ]] || return 0
    local target="$AURELIA_PLUGIN_UPDATE_TARGET"
    local backup_root="$AURELIA_PLUGIN_UPDATE_BACKUP_ROOT"
    local backup="$AURELIA_PLUGIN_UPDATE_BACKUP"
    local prefix="$aurelia_plugin_dir/"
    local rejected
    [[ "$target" == "$prefix"* && "$target" != "$prefix" ]] || return 1
    [[ "$backup_root" == "$prefix".update-backup.* && -d "$backup_root" && ! -L "$backup_root" ]] || return 1
    [[ -d "$backup" && ! -L "$backup" ]] || return 1
    rejected="$backup_root/rejected"
    if [[ -e "$target" || -L "$target" ]]; then
        [[ -d "$target" && ! -L "$target" ]] || return 1
        mv -- "$target" "$rejected" || return 1
    fi
    if ! mv -- "$backup" "$target"; then
        if [[ -d "$rejected" && ! -L "$rejected" && ! -e "$target" ]]; then
            mv -- "$rejected" "$target" || true
        fi
        return 1
    fi
    [[ ! -e "$rejected" && ! -L "$rejected" ]] || rm -rf -- "$rejected"
    rm -rf -- "$backup_root"
    AURELIA_PLUGIN_UPDATE_PUBLISHED=0
    AURELIA_PLUGIN_UPDATE_BACKUP_ROOT=""
    AURELIA_PLUGIN_UPDATE_BACKUP=""
    return 0
}

aurelia_plugin_update_failure() {
    local message="$1"
    if ! aurelia_plugin_update_rollback; then
        aurelia_plugin_fail "$message; rollback failed, preserving the staged recovery tree"
        return 1
    fi
    aurelia_plugin_update_stage_cleanup
    local rescan_status=0
    aurelia_plugin_reload_shell || rescan_status=$?
    aurelia_plugin_update_reset
    if [[ "$rescan_status" -ne 0 ]]; then
        aurelia_plugin_fail "$message; old plugin tree restored but resident rescan failed"
        return 1
    fi
    aurelia_plugin_fail "$message; update rolled back"
    return 1
}

aurelia_plugin_add() {
    local remote_url=""
    if [[ "$#" -gt 0 && "$1" != --* ]]; then
        remote_url="$1"
        shift
    fi
    local enable=0 assume_yes=0 arg
    for arg in "$@"; do
        case "$arg" in
            --enable) enable=1 ;;
            --yes|-y) assume_yes=1 ;;
            *) aurelia_plugin_fail "Unknown add option: $arg"; return 1 ;;
        esac
    done
    if (( ! assume_yes )) && ! aurelia_plugin_interactive; then
        aurelia_plugin_fail "add requires --yes when no interactive terminal is available"
        return 1
    fi
    if [[ -z "$remote_url" ]]; then
        printf 'Git URL: ' >&2
        IFS= read -r remote_url || return 1
        [[ -n "$remote_url" ]] || {
            aurelia_plugin_fail "a git URL is required"
            return 1
        }
    fi
    local confirm_status=0
    aurelia_plugin_confirm "$assume_yes" "Clone and add $remote_url?" || confirm_status=$?
    if [[ "$confirm_status" -ne 0 ]]; then
        aurelia_plugin_fail "add aborted"
        return 1
    fi
    aurelia_plugin_require_root || return 1

    local staging plugin_path plugin_id target shell_cli commit version catalog_json
    staging="$(mktemp -d "$aurelia_plugin_dir/.add.XXXXXX")" || return 1
    AURELIA_PLUGIN_STAGING="$staging"
    trap 'aurelia_plugin_lifecycle_cleanup' EXIT
    plugin_path="$staging/source"
    aurelia_plugin_clone_remote "$remote_url" "$plugin_path" || return 1
    aurelia_plugin_validate_manifest "$plugin_path" 0 0 || return 1
    plugin_id="$(aurelia_plugin_manifest_id "$plugin_path")"
    catalog_json="$(aurelia_plugin_catalog_json)" || return 1
    if jq -e --arg id "$plugin_id" 'any(.plugins[]; .id == $id)' <<<"$catalog_json" >/dev/null; then
        aurelia_plugin_fail "Plugin id is already present in the resident catalog: $plugin_id"
        return 1
    fi
    target="$(aurelia_plugin_target "$plugin_id")" || return 1
    [[ ! -e "$target" && ! -L "$target" ]] || {
        aurelia_plugin_fail "Plugin target already exists: $target"
        return 1
    }
    if (( ! assume_yes )); then
        aurelia_plugin_review_candidate "$plugin_path"
        confirm_status=0
        aurelia_plugin_confirm 0 "Install the validated plugin $plugin_id?" || confirm_status=$?
        if [[ "$confirm_status" -ne 0 ]]; then
            aurelia_plugin_fail "add aborted"
            return 1
        fi
    fi
    commit="$(aurelia_plugin_git_commit "$plugin_path")" || return 1
    version="$(aurelia_plugin_manifest_version "$plugin_path")"
    aurelia_plugin_write_provenance "$plugin_path" "$remote_url" "HEAD" "$commit" "passed" "$version" || return 1
    mv -- "$plugin_path" "$target" || return 1
    AURELIA_PLUGIN_STAGING=""
    rm -rf -- "$staging"
    trap - EXIT

    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    if ! aurelia_plugin_reload_shell; then
        aurelia_plugin_fail "Plugin installed but the resident shell could not rescan it"
        return 1
    fi
    if ! aurelia_plugin_wait_for_scan "$shell_cli" "$plugin_id"; then
        aurelia_plugin_fail "Plugin installed but was not discovered by the resident shell: $plugin_id"
        return 1
    fi
    if [[ "$enable" -eq 1 ]]; then
        aurelia_plugin_enable "$plugin_id" || return 1
        printf 'Installed %s and explicitly enabled it.\n' "$plugin_id"
    else
        printf 'Installed %s (disabled until explicitly enabled).\n' "$plugin_id"
    fi
}

aurelia_plugin_update_show_diff() {
    local old_path="$1"
    local new_path="$2"
    local diff_status=0
    diff -ruN --exclude=.git -- "$old_path" "$new_path" || diff_status=$?
    [[ "$diff_status" -eq 0 || "$diff_status" -eq 1 ]] || {
        aurelia_plugin_fail "Could not produce a reviewable update diff"
        return 1
    }
}

aurelia_plugin_update_one() {
    local plugin_id="$1"
    local assume_yes="$2"
    local target remote staging new_plugin shell_cli commit version
    target="$(aurelia_plugin_target "$plugin_id")" || return 1
    [[ -d "$target" && ! -L "$target" && -d "$target/.git" && ! -L "$target/.git" ]] || {
        aurelia_plugin_fail "Plugin is not a git-managed checkout: $plugin_id"
        return 1
    }
    aurelia_plugin_validate_manifest "$target" 0 1 || return 1
    [[ -z "$(git -C "$target" status --porcelain 2>/dev/null)" ]] || {
        aurelia_plugin_fail "Plugin has local changes; refusing an in-place update: $plugin_id"
        return 1
    }
    remote="$(git -C "$target" config --get remote.origin.url 2>/dev/null || true)"
    [[ "$remote" =~ ^https://[^[:space:]]+$ ]] || {
        aurelia_plugin_fail "Plugin remote is not an HTTPS URL: $plugin_id"
        return 1
    }
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    staging="$(mktemp -d "$aurelia_plugin_dir/.update.XXXXXX")" || return 1
    new_plugin="$staging/source"
    AURELIA_PLUGIN_STAGING="$staging"
    AURELIA_PLUGIN_UPDATE_ACTIVE=1
    AURELIA_PLUGIN_UPDATE_STAGE="$staging"
    AURELIA_PLUGIN_UPDATE_TARGET="$target"
    aurelia_plugin_clone_remote "$remote" "$new_plugin" || {
        aurelia_plugin_update_stage_cleanup
        aurelia_plugin_update_reset
        return 1
    }
    aurelia_plugin_validate_manifest "$new_plugin" 0 0 || {
        aurelia_plugin_update_stage_cleanup
        aurelia_plugin_update_reset
        return 1
    }
    [[ "$(aurelia_plugin_manifest_id "$new_plugin")" == "$plugin_id" ]] || {
        aurelia_plugin_fail "Updated repository changed its plugin id: $plugin_id"
        aurelia_plugin_update_stage_cleanup
        aurelia_plugin_update_reset
        return 1
    }
    commit="$(aurelia_plugin_git_commit "$new_plugin")" || {
        aurelia_plugin_update_stage_cleanup
        aurelia_plugin_update_reset
        return 1
    }
    version="$(aurelia_plugin_manifest_version "$new_plugin")"
    aurelia_plugin_write_provenance "$new_plugin" "$remote" "HEAD" "$commit" "passed" "$version" || {
        aurelia_plugin_update_stage_cleanup
        aurelia_plugin_update_reset
        return 1
    }
    if (( ! assume_yes )); then
        printf 'Changes for %s:\n' "$plugin_id" >&2
        aurelia_plugin_update_show_diff "$target" "$new_plugin" || {
            aurelia_plugin_update_stage_cleanup
            aurelia_plugin_update_reset
            return 1
        }
        local confirm_status=0
        aurelia_plugin_confirm 0 "Update $plugin_id?" || confirm_status=$?
        if [[ "$confirm_status" -eq 2 ]]; then
            printf 'Skipped %s.\n' "$plugin_id"
            aurelia_plugin_update_stage_cleanup
            aurelia_plugin_update_reset
            return 0
        elif [[ "$confirm_status" -ne 0 ]]; then
            aurelia_plugin_update_stage_cleanup
            aurelia_plugin_update_reset
            return 1
        fi
    fi

    local backup_root backup
    backup_root="$(mktemp -d "$aurelia_plugin_dir/.update-backup.XXXXXX")" || {
        aurelia_plugin_update_stage_cleanup
        aurelia_plugin_update_reset
        return 1
    }
    backup="$backup_root/old"
    AURELIA_PLUGIN_UPDATE_BACKUP_ROOT="$backup_root"
    AURELIA_PLUGIN_UPDATE_BACKUP="$backup"
    AURELIA_PLUGIN_UPDATE_PUBLISHED=1
    mv -- "$target" "$backup" || {
        rm -rf -- "$backup_root"
        aurelia_plugin_update_stage_cleanup
        aurelia_plugin_update_reset
        return 1
    }
    if ! mv -- "$new_plugin" "$target"; then
        aurelia_plugin_update_failure "Could not publish updated plugin $plugin_id"
        return 1
    fi
    AURELIA_PLUGIN_UPDATE_STAGE=""
    AURELIA_PLUGIN_STAGING=""
    if ! aurelia_plugin_reload_shell || ! aurelia_plugin_wait_for_scan "$shell_cli" "$plugin_id"; then
        aurelia_plugin_update_failure "Updated plugin $plugin_id was not accepted by resident rescan/discovery"
        return 1
    fi
    rm -rf -- "$backup_root"
    aurelia_plugin_update_reset
    printf 'Updated %s (commit %s).\n' "$plugin_id" "$commit"
}

aurelia_plugin_update() {
    local requested_id="" assume_yes=0 explicit_all=0 target_count=0 target_list="" arg
    for arg in "$@"; do
        case "$arg" in
            --yes|-y) assume_yes=1 ;;
            --all)
                [[ -z "$requested_id" ]] || { aurelia_plugin_fail "update accepts either a plugin id or --all"; return 1; }
                explicit_all=1
                ;;
            --*) aurelia_plugin_fail "Unknown update option: $arg"; return 1 ;;
            *)
                [[ -z "$requested_id" && "$explicit_all" -eq 0 ]] || {
                    aurelia_plugin_fail "update accepts one plugin id"
                    return 1
                }
                requested_id="$arg"
                ;;
        esac
    done
    if (( ! assume_yes )) && ! aurelia_plugin_interactive; then
        aurelia_plugin_fail "update requires --yes when no interactive terminal is available"
        return 1
    fi
    aurelia_plugin_require_root || return 1

    local entry plugin_id target
    if [[ -n "$requested_id" ]]; then
        aurelia_plugin_require_id "$requested_id" || return 1
        target_list="$requested_id"
        target_count=1
    else
        while IFS= read -r -d '' entry; do
            plugin_id="$(basename -- "$entry")"
            [[ "$plugin_id" != .* && -d "$entry/.git" && ! -L "$entry/.git" ]] || continue
            aurelia_plugin_valid_id "$plugin_id" || continue
            target_list+="$plugin_id"$'\n'
            target_count=$((target_count + 1))
        done < <(find -P "$aurelia_plugin_dir" -mindepth 1 -maxdepth 1 -type d -print0 | LC_ALL=C sort -z)
        if (( target_count == 0 )); then
            printf 'No git-managed plugins installed.\n'
            return 0
        fi
    fi

    trap 'aurelia_plugin_lifecycle_cleanup' EXIT
    local rc=0
    while IFS= read -r plugin_id; do
        [[ -n "$plugin_id" ]] || continue
        target="$(aurelia_plugin_target "$plugin_id")" || { rc=1; continue; }
        if [[ ! -d "$target/.git" || -L "$target/.git" ]]; then
            aurelia_plugin_fail "Plugin is not a git-managed checkout: $plugin_id"
            rc=1
            continue
        fi
        aurelia_plugin_update_one "$plugin_id" "$assume_yes" || rc=1
    done <<<"$target_list"
    aurelia_plugin_update_reset
    trap - EXIT
    return "$rc"
}

aurelia_plugin_remove_backup_target() {
    local plugin_id="$1"
    local backup_root="$aurelia_plugin_dir/.aurelia-backups"
    local timestamp base backup suffix
    if [[ -L "$backup_root" || ( -e "$backup_root" && ! -d "$backup_root" ) ]]; then
        aurelia_plugin_fail "Refusing unsafe Aurelia plugin backup directory: $backup_root"
        return 1
    fi
    mkdir -p -- "$backup_root" || return 1
    timestamp="$(date -u +%Y%m%d%H%M%S)" || return 1
    base="$backup_root/$plugin_id.remove.$timestamp"
    backup="$base"
    suffix=1
    while [[ -e "$backup" || -L "$backup" ]] && (( suffix < 1000 )); do
        backup="$base.$suffix"
        suffix=$((suffix + 1))
    done
    [[ ! -e "$backup" && ! -L "$backup" ]] || {
        aurelia_plugin_fail "Could not allocate a recoverable removal backup for $plugin_id"
        return 1
    }
    printf '%s\n' "$backup"
}

aurelia_plugin_remove() {
    local plugin_id="" assume_yes=0 arg
    for arg in "$@"; do
        case "$arg" in
            --yes|-y) assume_yes=1 ;;
            --*) aurelia_plugin_fail "Unknown remove option: $arg"; return 1 ;;
            *)
                [[ -z "$plugin_id" ]] || { aurelia_plugin_fail "remove accepts one plugin id"; return 1; }
                plugin_id="$arg"
                ;;
        esac
    done
    aurelia_plugin_require_root || return 1
    [[ -n "$plugin_id" ]] || {
        aurelia_plugin_fail "remove requires a plugin id"
        return 1
    }
    aurelia_plugin_require_id "$plugin_id" || return 1
    local target manifest_id cloned_from backup
    target="$(aurelia_plugin_target "$plugin_id")" || return 1
    [[ -d "$target" && ! -L "$target" ]] || {
        aurelia_plugin_fail "Plugin directory does not exist: $plugin_id"
        return 1
    }
    if [[ -e "$target/manifest.json" || -L "$target/manifest.json" ]]; then
        [[ -f "$target/manifest.json" && ! -L "$target/manifest.json" ]] || {
            aurelia_plugin_fail "Plugin manifest is not a regular file: $plugin_id"
            return 1
        }
        aurelia_plugin_validate_manifest "$target" 0 || return 1
        manifest_id="$(aurelia_plugin_manifest_id "$target")"
        [[ "$manifest_id" == "$plugin_id" ]] || {
            aurelia_plugin_fail "Plugin manifest id does not match its directory: $plugin_id"
            return 1
        }
        cloned_from="$(jq -r '.aurelia.clonedFrom // empty' "$target/manifest.json")"
    else
        cloned_from=""
    fi
    if (( ! assume_yes )) && ! aurelia_plugin_interactive; then
        aurelia_plugin_fail "remove requires --yes when no interactive terminal is available"
        return 1
    fi
    local confirm_status=0
    aurelia_plugin_confirm "$assume_yes" "Remove $plugin_id? It will be moved to a recoverable backup." || confirm_status=$?
    if [[ "$confirm_status" -ne 0 ]]; then
        aurelia_plugin_fail "remove aborted"
        return 1
    fi
    aurelia_plugin_set_enabled "$plugin_id" false || {
        aurelia_plugin_fail "Could not disable plugin before removal: $plugin_id"
        return 1
    }
    backup="$(aurelia_plugin_remove_backup_target "$plugin_id")" || return 1
    mv -- "$target" "$backup" || return 1
    if ! aurelia_plugin_reload_shell; then
        aurelia_plugin_fail "Plugin removed to $backup but the resident shell could not rescan it"
        return 1
    fi
    if [[ -n "$cloned_from" ]]; then
        printf 'Removed %s. Backup at: %s. Source restoration requested for %s.\n' \
            "$plugin_id" "$backup" "$cloned_from"
    else
        printf 'Removed %s. Backup at: %s.\n' "$plugin_id" "$backup"
    fi
}
