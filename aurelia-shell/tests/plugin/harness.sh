#!/usr/bin/env bash

# Shared fixtures and result labels for Aurelia plugin-platform tests.
# These helpers create only temporary test-owned trees; they never touch the
# user's Aurelia configuration or the live shell.

plugin_harness_tmp=""

plugin_harness_pass() {
    local class="$1"
    shift
    pass "[$class] $*"
}

plugin_harness_fail() {
    local class="$1"
    shift
    fail "[$class] $*"
}

plugin_harness_skip() {
    local class="$1"
    shift
    pass "[skipped:$class] $*"
}

plugin_harness_setup() {
    plugin_harness_tmp="$(mktemp -d)" || return 1
    [[ "$plugin_harness_tmp" == /tmp/* && ! -L "$plugin_harness_tmp" ]] || return 1
    mkdir -p \
        "$plugin_harness_tmp/first-party" \
        "$plugin_harness_tmp/user/plugins" \
        "$plugin_harness_tmp/config/aurelia"
}

plugin_harness_cleanup() {
    local path="${plugin_harness_tmp:-}"
    [[ -n "$path" && "$path" == /tmp/* && -d "$path" && ! -L "$path" ]] || return 0
    rm -rf -- "$path"
    plugin_harness_tmp=""
}

plugin_harness_area_root() {
    case "$1" in
        first-party) printf '%s\n' "$plugin_harness_tmp/first-party" ;;
        user) printf '%s\n' "$plugin_harness_tmp/user/plugins" ;;
        *) return 1 ;;
    esac
}

plugin_harness_write_plugin() {
    local area="$1"
    local directory_name="$2"
    local plugin_id="$3"
    local kind="$4"
    local entry_point="$5"
    local area_root plugin_root

    [[ "$directory_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 1
    [[ "$plugin_id" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 1
    [[ "$kind" =~ ^[A-Za-z0-9-]+$ ]] || return 1
    [[ "$entry_point" != /* && "$entry_point" != *..* && "$entry_point" != *\\* && "$entry_point" != *:* ]] || return 1

    area_root="$(plugin_harness_area_root "$area")" || return 1
    plugin_root="$area_root/$directory_name"
    mkdir -p -- "$plugin_root/$(dirname -- "$entry_point")"
    jq -n \
        --arg id "$plugin_id" \
        --arg kind "$kind" \
        --arg entry "$entry_point" \
        '{schemaVersion: 1, id: $id, name: ("Fixture " + $id), version: "0.0.1", description: "Test fixture", kinds: [$kind], entryPoints: {($kind): $entry}}' \
        >"$plugin_root/manifest.json"
    printf '%s\n' 'import QtQuick' 'Item {' '    implicitWidth: 1' '    implicitHeight: 1' '}' \
        >"$plugin_root/$entry_point"
    printf '%s\n' "$plugin_root"
}

plugin_harness_write_shell_config() {
    jq -n '{
        version: 1,
        plugins: ["fixture.panel"],
        disabledPlugins: ["aurelia.clock"],
        bar: {
            id: "aurelia.bar",
            position: "top",
            transparent: false,
            centerAnchor: "aurelia.clock",
            layout: {
                left: [{id: "aurelia.workspaces"}],
                center: [{id: "aurelia.clock"}],
                right: []
            }
        }
    }' >"$plugin_harness_tmp/config/aurelia/shell.json"
}

plugin_harness_write_malformed_manifest() {
    local plugin_root="$plugin_harness_tmp/user/plugins/fixture.malformed"
    mkdir -p -- "$plugin_root"
    printf '%s\n' '{"schemaVersion":1,"id":"fixture.malformed"' >"$plugin_root/manifest.json"
    printf '%s\n' "$plugin_root"
}

plugin_harness_write_duplicate_plugins() {
    local first second
    first="$(plugin_harness_write_plugin user fixture.duplicate-a fixture.duplicate panel Panel.qml)"
    second="$(plugin_harness_write_plugin user fixture.duplicate-b fixture.duplicate panel Panel.qml)"
    printf '%s\n%s\n' "$first" "$second"
}

plugin_harness_write_symlinked_plugin() {
    local plugin_root outside
    plugin_root="$(plugin_harness_write_plugin user fixture.symlink fixture.symlink panel Panel.qml)"
    outside="$plugin_harness_tmp/outside.qml"
    printf '%s\n' 'import QtQuick' 'Item {}' >"$outside"
    rm -f -- "$plugin_root/Panel.qml"
    ln -s -- "$outside" "$plugin_root/Panel.qml"
    printf '%s\n' "$plugin_root"
}

plugin_harness_write_failing_plugin() {
    local plugin_root
    plugin_root="$(plugin_harness_write_plugin user fixture.failing fixture.failing panel Panel.qml)"
    printf '%s\n' \
        'import QtQuick' \
        'Item {' \
        '    Component.onCompleted: throw "intentional fixture failure"' \
        '}' >"$plugin_root/Panel.qml"
    printf '%s\n' "$plugin_root"
}
