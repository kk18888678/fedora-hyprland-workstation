#!/usr/bin/env bash

plugin_harness_run_fixture_contract() {
    local first_party user_plugin malformed duplicate_paths symlinked failing

    first_party="$(plugin_harness_write_plugin first-party fixture.first aurelia.fixture panel Panel.qml)"
    user_plugin="$(plugin_harness_write_plugin user fixture.panel fixture.panel panel Panel.qml)"
    plugin_harness_write_shell_config
    malformed="$(plugin_harness_write_malformed_manifest)"
    duplicate_paths="$(plugin_harness_write_duplicate_plugins)"
    symlinked="$(plugin_harness_write_symlinked_plugin)"
    failing="$(plugin_harness_write_failing_plugin)"

    if [[ -f "$first_party/manifest.json" && -f "$first_party/Panel.qml" &&
          -f "$user_plugin/manifest.json" && -f "$user_plugin/Panel.qml" ]]; then
        plugin_harness_pass fixture "creates separate first-party and user plugin trees"
    else
        plugin_harness_fail fixture "does not create separate first-party and user plugin trees"
    fi

    if jq -e '.version == 1 and .plugins == ["fixture.panel"] and .bar.id == "aurelia.bar"' \
        "$plugin_harness_tmp/config/aurelia/shell.json" >/dev/null; then
        plugin_harness_pass fixture "creates an isolated shell.json state fixture"
    else
        plugin_harness_fail fixture "shell.json state fixture is malformed"
    fi

    if [[ -f "$malformed/manifest.json" ]] && ! jq -e . "$malformed/manifest.json" >/dev/null 2>&1; then
        plugin_harness_pass fixture "creates malformed manifest input"
    else
        plugin_harness_fail fixture "malformed manifest fixture is not malformed"
    fi

    if [[ "$(wc -l <<<"$duplicate_paths")" -eq 2 ]] &&
       [[ "$(sed -n '1p' <<<"$duplicate_paths")" != "$(sed -n '2p' <<<"$duplicate_paths")" ]]; then
        plugin_harness_pass fixture "creates duplicate-ID plugins in distinct directories"
    else
        plugin_harness_fail fixture "duplicate-ID fixture does not contain distinct plugin directories"
    fi

    if [[ -L "$symlinked/Panel.qml" ]]; then
        plugin_harness_pass fixture "creates a symlinked plugin-tree fixture"
    else
        plugin_harness_fail fixture "symlinked plugin-tree fixture is not symlinked"
    fi

    if grep -q 'Component.onCompleted: throw' "$failing/Panel.qml"; then
        plugin_harness_pass fixture "creates a failing entry-point fixture"
    else
        plugin_harness_fail fixture "failing entry-point fixture is not failing"
    fi

    plugin_harness_pass static "result labels distinguish static and fixture evidence"
    plugin_harness_pass isolated-runtime "reserved label is available for isolated runtime checks"
    plugin_harness_skip live-session "live Wayland checks remain separate from the repository-only harness"
}
