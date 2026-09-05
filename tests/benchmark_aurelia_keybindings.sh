#!/usr/bin/env bash

# Explicit live-session benchmark for Aurelia Keybindings.
#
# This script is intentionally not part of tests/run.sh. It exercises the
# currently running Quickshell instance and changes only the visibility of the
# Aurelia Keybindings surface. It requires an already-running, warm instance;
# it never starts Quickshell, installs anything, or changes system state.

set -Eeuo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "Error: python3 is required for the Aurelia live benchmark." >&2
    exit 1
fi

qs_bin="${QUICKSHELL_BIN:-}"
if [[ -z "$qs_bin" ]]; then
    if [[ -x /usr/bin/qs ]]; then
        qs_bin="/usr/bin/qs"
    elif [[ -x /usr/bin/quickshell ]]; then
        qs_bin="/usr/bin/quickshell"
    fi
fi
if [[ -z "$qs_bin" || ! -x "$qs_bin" ]]; then
    printf '%s\n' "Error: managed Quickshell runtime (/usr/bin/qs or /usr/bin/quickshell) was not found." >&2
    exit 1
fi

qml_root="${AURELIA_BENCHMARK_QML_ROOT:-${AURELIA_QML_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/aurelia/shell.qml}}"
if [[ ! -f "$qml_root" ]]; then
    printf 'Error: Aurelia QML root is not a file: %s\n' "$qml_root" >&2
    exit 1
fi

backend="${AURELIA_BENCHMARK_BACKEND:-}"
if [[ -z "$backend" && "${AURELIA_DEVELOPMENT_MODE:-0}" == "1" && -n "${AURELIA_SHELL_KEYBINDINGS_BIN:-}" ]]; then
    backend="$AURELIA_SHELL_KEYBINDINGS_BIN"
fi
if [[ -z "$backend" ]]; then
    backend="/usr/local/bin/aurelia-shell-keybindings"
fi
if [[ "$backend" != /* || ! -x "$backend" ]]; then
    printf 'Error: canonical Aurelia backend is not executable: %s\n' "$backend" >&2
    printf '%s\n' "Set AURELIA_BENCHMARK_BACKEND explicitly for a controlled development checkout." >&2
    exit 1
fi

exec python3 - "$qs_bin" "$qml_root" "$backend" <<'PY_BENCHMARK'
import math
import statistics
import subprocess
import sys
import time


QS_BIN, QML_ROOT, BACKEND = sys.argv[1:4]
TARGET = "keybindings"
COMMAND_TIMEOUT = 3.0
STATE_TIMEOUT = 2.0
SAMPLES = 20


class BenchmarkError(RuntimeError):
    pass


def run_command(argv, timeout=COMMAND_TIMEOUT):
    try:
        return subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise BenchmarkError(
            "timed out after %.1fs: %s" % (timeout, " ".join(argv[:5]))
        ) from exc


def ipc_call(method):
    result = run_command(
        [QS_BIN, "ipc", "--path", QML_ROOT, "call", TARGET, method]
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip().replace("\n", " ")
        if len(detail) > 240:
            detail = detail[:240] + "…"
        raise BenchmarkError(
            "IPC %s failed with exit %d%s"
            % (method, result.returncode, ": " + detail if detail else "")
        )
    return (result.stdout or "").strip()


def parse_bool(value, label):
    normalized = value.strip().lower().splitlines()[-1] if value.strip() else ""
    if normalized in {"true", "1"}:
        return True
    if normalized in {"false", "0"}:
        return False
    raise BenchmarkError("unexpected %s response: %s" % (label, value[:160]))


def visible():
    return parse_bool(ipc_call("isVisible"), "isVisible")


def wait_for_state(expected):
    deadline = time.monotonic() + STATE_TIMEOUT
    while time.monotonic() < deadline:
        if visible() is expected:
            return time.monotonic_ns()
        time.sleep(0.01)
    raise BenchmarkError(
        "visibility did not become %s within %.1fs" % (expected, STATE_TIMEOUT)
    )


def direct_request(method, expected):
    started = time.monotonic_ns()
    ipc_call(method)
    request_done = time.monotonic_ns()
    state_done = wait_for_state(expected)
    return request_done - started, state_done - request_done


def cli_toggle(expected):
    started = time.monotonic_ns()
    result = run_command([BACKEND, "toggle"])
    request_done = time.monotonic_ns()
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip().replace("\n", " ")
        if len(detail) > 240:
            detail = detail[:240] + "…"
        raise BenchmarkError(
            "CLI toggle failed with exit %d%s"
            % (result.returncode, ": " + detail if detail else "")
        )
    state_done = wait_for_state(expected)
    return request_done - started, state_done - request_done


def ensure_closed():
    if visible():
        direct_request("close", False)


def format_ms(nanoseconds):
    # Keep high-resolution values visible; never turn an unobservable/small
    # measurement into a misleading literal "0 ms".
    if nanoseconds < 1_000:
        return "<0.001 ms (%d ns)" % nanoseconds
    return "%.3f ms" % (nanoseconds / 1_000_000.0)


def percentile_95(values):
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    # Inclusive interpolation is deterministic for the fixed 20-sample run.
    position = (len(ordered) - 1) * 0.95
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def print_stats(label, values):
    print(label)
    print("  samples: %d" % len(values))
    print("  min:    %s" % format_ms(min(values)))
    print("  max:    %s" % format_ms(max(values)))
    print("  mean:   %s" % format_ms(statistics.mean(values)))
    print("  median: %s" % format_ms(statistics.median(values)))
    print("  p95:    %s" % format_ms(percentile_95(values)))


def collect_cli():
    request_open = []
    state_open = []
    request_close = []
    state_close = []
    for _ in range(SAMPLES):
        ensure_closed()
        request, state = cli_toggle(True)
        request_open.append(request)
        state_open.append(state)
        request, state = cli_toggle(False)
        request_close.append(request)
        state_close.append(state)
    return request_open, state_open, request_close, state_close


def collect_direct():
    request_open = []
    state_open = []
    request_close = []
    state_close = []
    for _ in range(SAMPLES):
        ensure_closed()
        request, state = direct_request("open", True)
        request_open.append(request)
        state_open.append(state)
        request, state = direct_request("close", False)
        request_close.append(request)
        state_close.append(state)
    return request_open, state_open, request_close, state_close


def main():
    try:
        if not parse_bool(ipc_call("ping"), "ping"):
            raise BenchmarkError("Aurelia Keybindings IPC endpoint is not ready")
        ensure_closed()

        # Discard exactly one warm-up cycle before collecting the fixed sample
        # sets. The close restores the starting state for the real run.
        cli_toggle(True)
        cli_toggle(False)

        cli = collect_cli()
        direct = collect_direct()
        ensure_closed()
    except BenchmarkError as exc:
        try:
            ipc_call("close")
        except BenchmarkError:
            pass
        print("Error: %s" % exc, file=sys.stderr)
        return 1

    print("Aurelia Keybindings live benchmark")
    print("  qml_root: %s" % QML_ROOT)
    print("  backend:  %s" % BACKEND)
    print("  warm-up:  1 discarded open/close cycle")
    print("  samples:  %d warm opens + %d warm closes per path" % (SAMPLES, SAMPLES))
    print()
    print("Observable timing boundaries (all measured with monotonic_ns):")
    print("  CLI request: process startup + argument parsing + warm-path readiness/IPC request")
    print("  Direct IPC request: qs IPC client startup + IPC request")
    print("  QML state confirmation: bounded isVisible polling after request completion")
    print("  Provenance hashing: not performed on the warm toggle path")
    print("  QML receipt/compositor mapping/focus completion: not externally observable")
    print()

    labels = (
        "CLI open request",
        "CLI open -> visible state",
        "CLI close request",
        "CLI close -> hidden state",
    )
    for label, values in zip(labels, cli):
        print_stats(label, values)
    print()
    labels = (
        "Direct IPC open request",
        "Direct IPC open -> visible state",
        "Direct IPC close request",
        "Direct IPC close -> hidden state",
    )
    for label, values in zip(labels, direct):
        print_stats(label, values)

    cli_visible = [request + state for request, state in zip(cli[0], cli[1])]
    cli_hidden = [request + state for request, state in zip(cli[2], cli[3])]
    direct_visible = [request + state for request, state in zip(direct[0], direct[1])]
    direct_hidden = [request + state for request, state in zip(direct[2], direct[3])]
    print()
    print("End-to-end observable boundaries")
    print_stats("CLI open request -> visible", cli_visible)
    print_stats("CLI close request -> hidden", cli_hidden)
    print_stats("Direct IPC open request -> visible", direct_visible)
    print_stats("Direct IPC close request -> hidden", direct_hidden)
    return 0


raise SystemExit(main())
PY_BENCHMARK
