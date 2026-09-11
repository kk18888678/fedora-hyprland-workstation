#!/usr/bin/env bash

plugin_harness_run_preservation_contract() {
    local fixture="$ROOT/tests/fixtures/plugin-preservation.json"
    local expected actual
    local manifest
    local -a required_files=()
    local -a required_executables=()

    expected="$(jq -c '.plugins | sort_by(.id)' "$fixture")"
    actual="$({
        while IFS= read -r manifest; do
            jq -c '{id, kinds, entryPoints, keepLoaded: (.keepLoaded // false), barWidget: (.barWidget // null)}' "$manifest"
        done < <(find "$ROOT/plugins" -type f -name manifest.json -print | sort)
    } | jq -sc 'sort_by(.id)')"

    if [[ "$actual" == "$expected" ]]; then
        plugin_harness_pass preservation "current Aurelia manifest inventory matches the frozen T02 fixture"
    else
        plugin_harness_fail preservation "current Aurelia manifest inventory differs from the frozen T02 fixture"
        printf 'Expected manifest inventory:\n%s\nActual manifest inventory:\n%s\n' "$expected" "$actual" >&2
    fi

    mapfile -t required_files < <(jq -r '.requiredFiles[]' "$fixture")
    local missing_file=0
    for manifest in "${required_files[@]}"; do
        if [[ ! -f "$ROOT/$manifest" || -L "$ROOT/$manifest" ]]; then
            missing_file=1
            printf 'Missing preserved file: %s\n' "$manifest" >&2
        fi
    done
    if (( missing_file == 0 )); then
        plugin_harness_pass preservation "preserved Aurelia host, UI, plugin, and test-contract files exist"
    else
        plugin_harness_fail preservation "preserved Aurelia files are missing or symlinked"
    fi

    mapfile -t required_executables < <(jq -r '.requiredExecutables[]' "$fixture")
    local missing_executable=0
    for manifest in "${required_executables[@]}"; do
        if [[ ! -x "$ROOT/$manifest" || -L "$ROOT/$manifest" ]]; then
            missing_executable=1
            printf 'Missing preserved executable: %s\n' "$manifest" >&2
        fi
    done
    if (( missing_executable == 0 )); then
        plugin_harness_pass preservation "preserved Aurelia backend entry points remain executable"
    else
        plugin_harness_fail preservation "preserved Aurelia backend entry points are missing or unsafe"
    fi

    if ROOT="$ROOT" python3 - "$fixture" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

fixture_path = Path(sys.argv[1])
root = Path(os.environ["ROOT"])
fixture = json.loads(fixture_path.read_text())

for relative in ("services/ShellConfig.qml", "plugins/aurelia.bar/Bar.qml"):
    source = (root / relative).read_text()
    for region in ("left", "center", "right"):
        cursor = -1
        for plugin_id in fixture["defaultBar"]["layout"][region]:
            pattern = re.compile(r"\bid\s*:\s*['\"]" + re.escape(plugin_id) + r"['\"]")
            matches = [match.start() for match in pattern.finditer(source) if match.start() > cursor]
            if not matches:
                raise SystemExit(f"{relative}: {region} layout lost or reordered {plugin_id}")
            cursor = matches[0]
PY
    then
        plugin_harness_pass preservation "default Aurelia bar layout order is preserved in host and bar fallback"
    else
        plugin_harness_fail preservation "default Aurelia bar layout order changed in host or bar fallback"
    fi
}
