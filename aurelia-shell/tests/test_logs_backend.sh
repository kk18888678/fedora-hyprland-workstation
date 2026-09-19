#!/usr/bin/env bash

# Aurelia log diagnostics suite: the workstation-logs backend, its
# WARN/ERROR/FATAL projection over the structured and Quickshell logs, and the
# `aurelia logs` CLI wiring. Everything runs against disposable fixtures; the
# live workstation is never touched.

set -Eeuo pipefail

section "Aurelia Log Diagnostics"

repo_root="$(cd -- "$ROOT/.." && pwd -P)"
backend="$repo_root/bin/workstation-logs"

# ---------------------------------------------------------------------------
# Static invariants
# ---------------------------------------------------------------------------
if [[ -x "$backend" ]]; then
    pass "[static] workstation-logs backend is executable"
else
    fail "[static] workstation-logs backend is missing or not executable"
fi

if grep -q 'logs' "$ROOT/bin/aurelia" &&
   grep -q 'cmd_logs' "$ROOT/bin/aurelia" &&
   grep -q 'workstation-logs' "$ROOT/bin/aurelia" &&
   grep -q 'logs          Aurelia WARN/ERROR/FATAL' "$ROOT/bin/aurelia"; then
    pass "[static] aurelia CLI exposes the logs group and its description"
else
    fail "[static] aurelia logs group wiring is incomplete"
fi

if "$backend" --help >/dev/null &&
   "$backend" paths >/dev/null; then
    pass "[static] backend exposes list/count/report/paths subcommands"
else
    fail "[static] backend subcommand surface is broken"
fi

# ---------------------------------------------------------------------------
# Structured log projection (isolated)
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null; then
    skip "[unit] structured log projection (python3 unavailable)"
    return 0
fi

sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox" || true' RETURN
mkdir -p -- "$sandbox/runtime" "$sandbox/bin"

recent="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
old="$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)"
cat >"$sandbox/aurelia.log" <<EOF
${recent} [INFO] [run.launch] launched foot
${recent} [WARN] [theme.apply] fallback palette used
${recent} [ERROR] [run.dispatch] launch failed
${recent} [FATAL] [core.boot] boot aborted
${old} [ERROR] [run.dispatch] old failure
EOF

log_list() {
    AURELIA_LOG_PATH="$sandbox/aurelia.log" XDG_RUNTIME_DIR="$sandbox/runtime" \
        "$backend" "$@" --qslog "$sandbox/missing.qslog"
}

if [[ "$(log_list list | wc -l)" -eq 4 ]] &&
   log_list list | grep -q '\[WARN\] aurelia.log.theme.apply: fallback palette used' &&
   ! log_list list | grep -q '\[INFO\]'; then
    pass "[unit] list projects WARN/ERROR/FATAL and drops INFO"
else
    fail "[unit] structured list projection diverged"
fi

if log_list list --level error | grep -q 'launch failed' &&
   [[ "$(log_list list --level error | wc -l)" -eq 2 ]]; then
    pass "[unit] --level narrows the projection"
else
    fail "[unit] --level filter diverged"
fi

if log_list list --since 1h | grep -q 'launch failed' &&
   ! log_list list --since 1h | grep -q 'old failure'; then
    pass "[unit] --since bounds the projection by time"
else
    fail "[unit] --since filter diverged"
fi

if log_list count | grep -q 'WARN: 1' &&
   log_list count | grep -q 'ERROR: 2' &&
   log_list count | grep -q 'FATAL: 1'; then
    pass "[unit] count reports per-level totals"
else
    fail "[unit] level counting diverged"
fi

# ---------------------------------------------------------------------------
# Quickshell runtime log projection (mocked qs)
# ---------------------------------------------------------------------------
cat >"$sandbox/bin/qs" <<'MOCK_QS'
#!/usr/bin/env bash
# workstation-logs must read the binary log through `qs log`; this stub emits
# the same leveled text the real reader produces.
printf '\033[32m  INFO\033[97m qml\033[0m: [THEME] loaded\n'
printf '\033[33m  WARN\033[97m scene\033[0m: Unable to assign [undefined] to QColor\n'
printf '\033[31m ERROR\033[97m qml\033[0m: plugin load failed\n'
printf '\033[31m FATAL\033[97m qml\033[0m: fatal boot error\n'
MOCK_QS
chmod 0755 "$sandbox/bin/qs"
: >"$sandbox/runtime.qslog"

runtime_out="$(PATH="$sandbox/bin:$PATH" AURELIA_LOG_PATH="$sandbox/aurelia.log" XDG_RUNTIME_DIR="$sandbox/runtime" \
    "$backend" list --qslog "$sandbox/runtime.qslog" || true)"
if printf '%s\n' "$runtime_out" | grep -q '\[WARN\] quickshell.scene: Unable to assign' &&
   printf '%s\n' "$runtime_out" | grep -q '\[ERROR\] quickshell.qml: plugin load failed' &&
   printf '%s\n' "$runtime_out" | grep -q '\[FATAL\] quickshell.qml: fatal boot error' &&
   ! printf '%s\n' "$runtime_out" | grep -q '\[INFO\]'; then
    pass "[unit] Quickshell log is read through qs log and keeps its severity"
else
    fail "[unit] Quickshell runtime projection diverged: $runtime_out"
fi

# ---------------------------------------------------------------------------
# Report hands a bounded excerpt to the default agent
# ---------------------------------------------------------------------------
cat >"$sandbox/bin/mock-ai" <<'MOCK_AI'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$MOCK_AI_OUT"
MOCK_AI
chmod 0755 "$sandbox/bin/mock-ai"
MOCK_AI_OUT="$sandbox/ai.out" WORKSTATION_AI_BIN="$sandbox/bin/mock-ai" \
AURELIA_LOG_PATH="$sandbox/aurelia.log" XDG_RUNTIME_DIR="$sandbox/runtime" \
    "$backend" report --qslog "$sandbox/missing.qslog" --level error >/dev/null
if [[ -f "$sandbox/ai.out" ]] &&
   grep -q 'Diagnose these Aurelia shell log diagnostics' "$sandbox/ai.out" &&
   grep -q 'launch failed' "$sandbox/ai.out" &&
   ! grep -q 'launched foot' "$sandbox/ai.out"; then
    pass "[unit] report hands only the matching diagnostics to the default agent"
else
    fail "[unit] report excerpt diverged"
fi
