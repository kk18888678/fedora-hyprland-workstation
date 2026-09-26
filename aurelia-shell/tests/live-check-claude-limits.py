#!/usr/bin/env python3
"""Opt-in live Claude limits probe for maintainers (never run by the suite).

Makes ONE bounded authenticated GET to Anthropic's OAuth usage endpoint via
the collector's own `fetch_claude_limits`, then prints only the HTTP-derived
status and a redacted shape. It NEVER prints, logs or writes the access token;
the credential is reported only as present/absent plus its length.

This file is deliberately NOT named `test_*.sh`, so the strict test runner
never picks it up. Run it by hand when validating the endpoint:

    python3 aurelia-shell/tests/live-check-claude-limits.py
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path


def load_collector(path: Path):
    loader = importlib.machinery.SourceFileLoader("ai_usage_claude_live", str(path))
    spec = importlib.util.spec_from_loader("ai_usage_claude_live", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def main() -> int:
    collector = Path(__file__).resolve().parents[1] / "bin" / "ai-usage-claude"
    if len(sys.argv) > 1:
        collector = Path(sys.argv[1])
    module = load_collector(collector)
    token = module.claude_access_token()
    # The token is never emitted; only presence and length are safe to report.
    result = {
        "credentialPresent": bool(token),
        "credentialLength": len(token) if token else 0,
    }
    limits = module.fetch_claude_limits(token).get("limits") if token else []
    if not token:
        result["status"] = "no credential (no network call)"
        result["supportedWindowMinutes"] = list(module.SUPPORTED_WINDOW_MINUTES)
        result["limits"] = []
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    # Exactly one authenticated call was made by fetch_claude_limits above.
    result["status"] = "ok" if limits else "no windows reported"
    result["supportedWindowMinutes"] = list(module.SUPPORTED_WINDOW_MINUTES)
    result["limits"] = [
        {
            "label": entry.get("label"),
            "percent": entry.get("percent"),
            "windowMinutes": entry.get("windowMinutes"),
            "resetsAt": entry.get("resetsAt"),
        }
        for entry in limits
    ]
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
