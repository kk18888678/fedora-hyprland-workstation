#!/usr/bin/env python3
"""Opt-in live durable-source probe for maintainers (never run by the suite).

This file is deliberately NOT named `test_*.sh`, so the strict test runner never
picks it up. It performs at most ONE bounded authenticated request per
collector and prints only HTTP-derived status and a redacted shape. It NEVER
prints, logs or writes any credential; tokens are reported only as
present/absent plus length, and the credential stores are hashed before and
after to prove the collectors did not write them.

Run it by hand when validating the durable sources:

    python3 aurelia-shell/tests/live-check-durable-limits.py
"""

from __future__ import annotations

import hashlib
import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path


def load_collector(name: str, path: Path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    if not path.is_file():
        return ""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def redact(limits) -> list:
    return [
        {
            "label": entry.get("label"),
            "percent": entry.get("percent"),
            "windowMinutes": entry.get("windowMinutes"),
            "resetsAt": entry.get("resetsAt"),
        }
        for entry in (limits or [])
    ]


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    claude = load_collector("ai_usage_claude_live", root / "bin" / "ai-usage-claude")
    cline = load_collector("ai_usage_cline_live", root / "bin" / "ai-usage-cline")

    result = {}

    # Claude: owner-delegated mint, store hash verified unchanged.
    store = Path.home() / ".claude" / ".credentials.json"
    before = sha256(store)
    token, diagnostic = claude.claude_owner_token()
    claude_result = claude.fetch_claude_limits(token) if token else {"limits": [], "usageStatusText": "no credential"}
    result["claude"] = {
        "credentialPresent": bool(token),
        "credentialLength": len(token) if token else 0,
        "diagnostic": diagnostic,
        "status": claude_result.get("usageStatusText"),
        "supportedWindowMinutes": list(claude.SUPPORTED_WINDOW_MINUTES),
        "limits": redact(claude_result.get("limits")),
        "storeUnchanged": before == sha256(store),
    }

    # Cline: durable user-owned API key.
    key = cline.cline_api_key()
    cline_result = cline.fetch_cline_limits() if key else {"limits": [], "usageStatusText": "no durable key"}
    result["cline"] = {
        "durableKeyPresent": bool(key),
        "status": cline_result.get("usageStatusText"),
        "supportedWindowMinutes": [300, 10080, 43200],
        "limits": redact(cline_result.get("limits")),
    }

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
