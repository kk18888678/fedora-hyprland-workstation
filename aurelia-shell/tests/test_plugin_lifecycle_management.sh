#!/usr/bin/env bash

# T18 staged add/update/remove lifecycle checks. The Git and shell commands
# below are local fixtures; no network or live shell state is used.

set -Eeuo pipefail

section "Aurelia Plugin Management Lifecycle"

cli_root="$ROOT/bin/lib/aurelia-plugin"
lifecycle_root="$cli_root/lifecycle.sh"
fixture_root="$ROOT/tests/fixtures/plugin-lifecycle-management"

if [[ -f "$lifecycle_root" ]] &&
   grep -q 'aurelia_plugin_catalog_json' "$lifecycle_root" &&
   grep -q 'aurelia_plugin_update_rollback' "$lifecycle_root" &&
   grep -q 'aurelia_plugin_update_show_diff' "$lifecycle_root" &&
   grep -q 'aurelia_plugin_remove_backup_target' "$lifecycle_root" &&
   grep -q 'GIT_ALLOW_PROTOCOL=https' "$lifecycle_root"; then
    pass "[static] lifecycle management has canonical preflight, staged rollback, review, provenance, and recoverable removal boundaries"
else
    fail "[static] lifecycle management boundary is incomplete"
fi

management_root="$(mktemp -d)"
trap 'rm -rf -- "$management_root" 2>/dev/null || true' RETURN

case_setup() {
    case_root="$(mktemp -d "$management_root/case.XXXXXX")"
    mkdir -p -- "$case_root/bin" "$case_root/home" "$case_root/plugins"
    cp -- "$fixture_root/git" "$case_root/bin/git"
    cp -- "$fixture_root/aurelia-shell" "$case_root/bin/aurelia-shell"
    chmod 0755 "$case_root/bin/git" "$case_root/bin/aurelia-shell"
    calls="$case_root/calls"
    git_calls="$case_root/git-calls"
    touch "$calls" "$git_calls"
    FAKE_GIT_ID=acme.lifecycle
    FAKE_GIT_VERSION=1.0.0
    FAKE_GIT_COMMIT=t18-fixture-commit
    FAKE_GIT_REMOTE=https://example.invalid/lifecycle.git
    FAKE_GIT_DIRTY=0
    FAKE_GIT_INVALID=0
    FAKE_GIT_ID_FROM_REMOTE=0
    FAKE_GIT_REMOTE_FROM_DIR=0
    FAKE_RESCAN_FAIL_ONCE=0
    FAKE_RESCAN_COUNT_FILE="$case_root/rescan-count"
    FAKE_NO_DISCOVERY=0
}

plugin_command() {
    PATH="$case_root/bin:$PATH" \
    HOME="$case_root/home" \
    AURELIA_PLUGIN_DIR="$case_root/plugins" \
    AURELIA_PLUGIN_BIN_DIR="$case_root/bin" \
    AURELIA_DEVELOPMENT_MODE=1 \
    FAKE_CALLS="$calls" \
    FAKE_GIT_CALLS="$git_calls" \
    FAKE_GIT_ID="$FAKE_GIT_ID" \
    FAKE_GIT_VERSION="$FAKE_GIT_VERSION" \
    FAKE_GIT_COMMIT="$FAKE_GIT_COMMIT" \
    FAKE_GIT_REMOTE="$FAKE_GIT_REMOTE" \
    FAKE_GIT_DIRTY="$FAKE_GIT_DIRTY" \
    FAKE_GIT_INVALID="$FAKE_GIT_INVALID" \
    FAKE_GIT_ID_FROM_REMOTE="$FAKE_GIT_ID_FROM_REMOTE" \
    FAKE_GIT_REMOTE_FROM_DIR="$FAKE_GIT_REMOTE_FROM_DIR" \
    FAKE_RESCAN_FAIL_ONCE="$FAKE_RESCAN_FAIL_ONCE" \
    FAKE_RESCAN_COUNT_FILE="$FAKE_RESCAN_COUNT_FILE" \
    FAKE_NO_DISCOVERY="$FAKE_NO_DISCOVERY" \
    bash -c '
        set -Eeuo pipefail
        module_root="$1"
        shift
        source "$module_root/common.sh"
        source "$module_root/placement.sh"
        source "$module_root/manifest.sh"
        source "$module_root/main.sh"
        source "$module_root/clone.sh"
        source "$module_root/lifecycle.sh"
        aurelia_plugin_main "$@"
    ' _ "$cli_root" "$@"
}

write_managed_plugin() {
    local plugin_id="$1"
    local version="$2"
    local target="$case_root/plugins/$plugin_id"
    mkdir -p -- "$target/.git"
    jq -n --arg id "$plugin_id" --arg version "$version" '{
        schemaVersion: 1,
        id: $id,
        name: "Managed Fixture",
        version: $version,
        description: "Managed lifecycle fixture",
        kinds: ["bar-widget"],
        entryPoints: {barWidget: "Widget.qml"},
        barWidget: {
            displayName: "Managed Fixture",
            description: "Managed lifecycle fixture",
            category: "Testing",
            allowMultiple: false,
            defaultSection: "center"
        }
    }' >"$target/manifest.json"
    printf '%s\n' 'import QtQuick' 'Item { implicitWidth: 1; implicitHeight: 1 }' >"$target/Widget.qml"
}

case_setup
duplicate_dir="$case_root/plugins/existing.folder"
mkdir -p -- "$duplicate_dir"
jq -n '{
    schemaVersion: 1, id: "acme.lifecycle", name: "Existing", version: "1.0.0",
    description: "Existing duplicate", kinds: ["bar-widget"],
    entryPoints: {barWidget: "Widget.qml"},
    barWidget: {displayName: "Existing", description: "Existing", category: "Testing",
                 allowMultiple: false, defaultSection: "center"}
}' >"$duplicate_dir/manifest.json"
printf '%s\n' 'user-owned duplicate' >"$duplicate_dir/sentinel"
duplicate_status=0
FAKE_GIT_ID=acme.lifecycle plugin_command add https://example.invalid/incoming.git --yes >/dev/null 2>&1 || duplicate_status=$?
if [[ "$duplicate_status" -ne 0 && -f "$duplicate_dir/sentinel" &&
      ! -e "$case_root/plugins/acme.lifecycle" ]] &&
   ! find "$case_root/plugins" -mindepth 1 -maxdepth 1 -name '.add.*' -print -quit | grep -q .; then
    pass "[isolated-runtime] add performs canonical catalog duplicate preflight before publication"
else
    fail "[isolated-runtime] duplicate add preflight did not fail safely"
fi

case_setup
add_output="$(plugin_command add https://example.invalid/lifecycle.git --yes)"
add_target="$case_root/plugins/acme.lifecycle"
if [[ "$add_output" == *"disabled until explicitly enabled"* ]] &&
   jq -e '.id == "acme.lifecycle" and .version == "1.0.0"' "$add_target/manifest.json" >/dev/null &&
   jq -e '.source == "git" and .remote == "https://example.invalid/lifecycle.git" and
          .ref == "HEAD" and .commit == "t18-fixture-commit" and
          .validation == "passed" and .version == "1.0.0"' \
       "$add_target/.aurelia-provenance.json" >/dev/null &&
   [[ "$(stat -c '%a' "$add_target/.aurelia-provenance.json")" == "600" ]] &&
   ! grep -q '^enablePlugin' "$calls"; then
    pass "[isolated-runtime] add records provenance and remains disabled unless explicitly enabled"
else
    fail "[isolated-runtime] add disabled-default or provenance contract failed"
fi

case_setup
FAKE_GIT_ID=acme.enabled plugin_command add https://example.invalid/enabled.git --enable --yes >/dev/null
if grep -q 'enablePlugin acme.enabled' "$calls"; then
    pass "[isolated-runtime] add --enable is the explicit activation path"
else
    fail "[isolated-runtime] add --enable did not activate through resident IPC"
fi

case_setup
unsafe_marker="$case_root/unsafe-command-ran"
GIT_SSH_COMMAND="touch $unsafe_marker" FAKE_GIT_ID=acme.transport \
    plugin_command add https://example.invalid/transport.git --yes >/dev/null
if [[ ! -e "$unsafe_marker" ]] && grep -q 'ssh="" proxy="" askpass="" config-count=""' "$git_calls"; then
    pass "[isolated-runtime] Git transport-helper environment is neutralized before clone"
else
    fail "[isolated-runtime] Git clone received an unsafe transport environment"
fi

case_setup
noninteractive_status=0
plugin_command add https://example.invalid/noninteractive.git >/dev/null 2>&1 || noninteractive_status=$?
if [[ "$noninteractive_status" -ne 0 ]] &&
   ! find "$case_root/plugins" -mindepth 1 -maxdepth 1 -name '.add.*' -print -quit | grep -q .; then
    pass "[isolated-runtime] non-interactive add requires explicit --yes without mutating"
else
    fail "[isolated-runtime] non-interactive add confirmation boundary failed"
fi

case_setup
write_managed_plugin acme.update 1.0.0
FAKE_GIT_ID=acme.update FAKE_GIT_VERSION=2.0.0 \
    update_output="$(plugin_command update acme.update --yes)"
if [[ "$update_output" == *"Updated acme.update"* ]] &&
   jq -e '.version == "2.0.0"' "$case_root/plugins/acme.update/manifest.json" >/dev/null &&
   jq -e '.commit == "t18-fixture-commit" and .validation == "passed"' \
       "$case_root/plugins/acme.update/.aurelia-provenance.json" >/dev/null &&
   ! find "$case_root/plugins" -mindepth 1 -maxdepth 1 -name '.update-backup.*' -print -quit | grep -q .; then
    pass "[isolated-runtime] update-one stages, validates, records provenance, and publishes atomically"
else
    fail "[isolated-runtime] update-one success path failed"
fi

case_setup
write_managed_plugin acme.dirty 1.0.0
dirty_status=0
FAKE_GIT_ID=acme.dirty FAKE_GIT_DIRTY=1 plugin_command update acme.dirty --yes >/dev/null 2>&1 || dirty_status=$?
if [[ "$dirty_status" -ne 0 ]] &&
   jq -e '.version == "1.0.0"' "$case_root/plugins/acme.dirty/manifest.json" >/dev/null &&
   ! grep -q '^git-clone' "$git_calls"; then
    pass "[isolated-runtime] update refuses local modifications before staging"
else
    fail "[isolated-runtime] local modification refusal failed"
fi

case_setup
write_managed_plugin acme.invalid 1.0.0
invalid_status=0
FAKE_GIT_ID=acme.invalid FAKE_GIT_INVALID=1 plugin_command update acme.invalid --yes >/dev/null 2>&1 || invalid_status=$?
if [[ "$invalid_status" -ne 0 ]] &&
   jq -e '.version == "1.0.0"' "$case_root/plugins/acme.invalid/manifest.json" >/dev/null &&
   ! find "$case_root/plugins" -mindepth 1 -maxdepth 1 -name '.update.*' -print -quit | grep -q .; then
    pass "[isolated-runtime] invalid staged update is rejected before replacing the installed tree"
else
    fail "[isolated-runtime] invalid update rollback boundary failed"
fi

case_setup
write_managed_plugin acme.rescan 1.0.0
rescan_status=0
FAKE_GIT_ID=acme.rescan FAKE_GIT_VERSION=2.0.0 FAKE_RESCAN_FAIL_ONCE=1 \
    plugin_command update acme.rescan --yes >"$case_root/rescan.out" 2>&1 || rescan_status=$?
if [[ "$rescan_status" -ne 0 ]] &&
   jq -e '.version == "1.0.0"' "$case_root/plugins/acme.rescan/manifest.json" >/dev/null &&
   grep -q 'rolled back' "$case_root/rescan.out" &&
   [[ "$(grep -c '^rescanPlugins$' "$calls")" -eq 2 ]]; then
    pass "[isolated-runtime] resident rescan failure restores the old plugin tree and retries the old generation"
else
    fail "[isolated-runtime] rescan rollback failed"
fi

case_setup
write_managed_plugin acme.discovery 1.0.0
discovery_status=0
FAKE_GIT_ID=acme.discovery FAKE_GIT_VERSION=2.0.0 FAKE_NO_DISCOVERY=1 \
    plugin_command update acme.discovery --yes >"$case_root/discovery.out" 2>&1 || discovery_status=$?
if [[ "$discovery_status" -ne 0 ]] &&
   jq -e '.version == "1.0.0"' "$case_root/plugins/acme.discovery/manifest.json" >/dev/null &&
   grep -q 'rolled back' "$case_root/discovery.out"; then
    pass "[isolated-runtime] discovery failure restores the old plugin tree"
else
    fail "[isolated-runtime] discovery rollback failed"
fi

case_setup
write_managed_plugin acme.one 1.0.0
write_managed_plugin acme.two 1.0.0
FAKE_GIT_ID_FROM_REMOTE=1 FAKE_GIT_REMOTE_FROM_DIR=1 FAKE_GIT_VERSION=3.0.0 \
    plugin_command update --all --yes >"$case_root/all.out"
if jq -e '.version == "3.0.0"' "$case_root/plugins/acme.one/manifest.json" >/dev/null &&
   jq -e '.version == "3.0.0"' "$case_root/plugins/acme.two/manifest.json" >/dev/null &&
   grep -q 'Updated acme.one' "$case_root/all.out" &&
   grep -q 'Updated acme.two' "$case_root/all.out"; then
    pass "[isolated-runtime] update --all discovers and updates every clean Git-managed plugin"
else
    fail "[isolated-runtime] update-all lifecycle failed"
fi

case_setup
write_managed_plugin acme.manual 1.0.0
rm -rf -- "$case_root/plugins/acme.manual/.git"
remove_output="$(plugin_command remove acme.manual --yes)"
backup_path="$(find "$case_root/plugins/.aurelia-backups" -mindepth 1 -maxdepth 1 -type d -name 'acme.manual.remove.*' -print -quit)"
disable_line="$(grep -n 'setPluginEnabled acme.manual false' "$calls" | cut -d: -f1)"
rescan_line="$(grep -n '^rescanPlugins$' "$calls" | tail -n 1 | cut -d: -f1)"
if [[ ! -e "$case_root/plugins/acme.manual" && -d "$backup_path" &&
      -f "$backup_path/manifest.json" && "$remove_output" == *"Backup at:"* ]] &&
   [[ "$disable_line" -lt "$rescan_line" ]]; then
    pass "[isolated-runtime] non-Git removal preserves the source in a recoverable backup after disablement"
else
    fail "[isolated-runtime] recoverable removal or disable-before-move failed"
fi

case_setup
write_managed_plugin acme.remove-confirm 1.0.0
remove_confirm_status=0
plugin_command remove acme.remove-confirm >/dev/null 2>&1 || remove_confirm_status=$?
if [[ "$remove_confirm_status" -ne 0 && -d "$case_root/plugins/acme.remove-confirm" ]]; then
    pass "[isolated-runtime] non-interactive removal requires explicit --yes without deleting user data"
else
    fail "[isolated-runtime] removal confirmation boundary failed"
fi
