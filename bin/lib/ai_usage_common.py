"""Shared helpers for the Aurelia ai-usage-* collectors.

The pi coding agent drives several AI subscriptions (opencode-go, clinepass,
openai-codex, ...) directly through its own API clients, so their usage never
lands in the underlying CLIs' native session stores. pi does record every
assistant turn, with per-provider token usage, in
`$PI_HOME/agent/sessions/**/*.jsonl`; these helpers let each provider
collector merge that usage into its record.
"""

from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path


def number(value) -> int:
    try:
        n = float(value or 0)
        return round(n) if n == n else 0
    except Exception:
        return 0


def local_date_string() -> str:
    return dt.datetime.now().strftime("%Y-%m-%d")


def recent_date_strings() -> list[str]:
    today = dt.datetime.now().date()
    return [(today - dt.timedelta(days=offset)).strftime("%Y-%m-%d") for offset in range(6, -1, -1)]


def local_date_from_millis(value) -> str:
    try:
        millis = float(value)
        if millis <= 0:
            return local_date_string()
        return dt.datetime.fromtimestamp(millis / 1000.0).strftime("%Y-%m-%d")
    except Exception:
        return local_date_string()


def empty_bucket() -> dict[str, int]:
    return {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 0,
        "cacheCreationInputTokens": 0,
    }


def empty_stats() -> dict:
    recent = recent_date_strings()
    return {
        "todayPrompts": 0,
        "todaySessions": 0,
        "todayTotalTokens": 0,
        "todayTokensByModel": {},
        "recentDays": [{"date": day, "messageCount": 0} for day in recent],
        "modelUsage": {},
        "totalPrompts": 0,
        "totalSessions": 0,
        "activeDays": 0,
        "activeDates": [],
        "detected": False,
    }


def pi_sessions_root() -> Path:
    base = os.environ.get("PI_HOME") or str(Path.home() / ".pi")
    return Path(os.path.expandvars(os.path.expanduser(base))) / "agent" / "sessions"


def provider_matches(provider: str, substrings: list[str]) -> bool:
    text = str(provider or "").lower()
    return any(substring in text for substring in substrings)


def scan_pi_sessions(match_substrings: list[str]) -> dict:
    """Aggregate pi's per-provider usage for the given provider substrings."""
    stats = empty_stats()
    root = pi_sessions_root()
    if not root.is_dir():
        return stats

    today = local_date_string()
    recent = {day["date"]: day for day in stats["recentDays"]}
    seen: set[str] = set()
    sessions: set[str] = set()
    active_days: set[str] = set()
    today_sessions: set[str] = set()
    today_tokens: dict[str, int] = {}
    usage_by_model: dict[str, dict[str, int]] = {}
    prompts = 0
    today_prompt_count = 0
    today_token_total = 0
    found = False

    for path in sorted(root.rglob("*.jsonl")):
        session_key = str(path)
        provider = ""
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                for line_number, line in enumerate(handle, 1):
                    if '"usage"' not in line and '"provider"' not in line:
                        continue
                    try:
                        entry = json.loads(line)
                    except Exception:
                        continue
                    if entry.get("type") == "model_change":
                        provider = str(entry.get("provider") or provider)
                        continue
                    message = entry.get("message") if isinstance(entry.get("message"), dict) else None
                    if not message or message.get("role") != "assistant":
                        continue
                    usage = message.get("usage")
                    if not isinstance(usage, dict):
                        continue
                    turn_provider = str(message.get("provider") or provider)
                    if not provider_matches(turn_provider, match_substrings):
                        continue
                    found = True

                    unique_key = f"{path}:{message.get('id') or entry.get('id') or line_number}"
                    if unique_key in seen:
                        continue
                    seen.add(unique_key)

                    input_tokens = number(usage.get("input"))
                    output_tokens = number(usage.get("output")) + number(usage.get("reasoning"))
                    cache_read = number(usage.get("cacheRead"))
                    cache_write = number(usage.get("cacheWrite"))
                    total = input_tokens + output_tokens + cache_read + cache_write
                    if total <= 0:
                        continue

                    model = str(message.get("model") or turn_provider or "pi")
                    day = local_date_from_millis(message.get("timestamp") or entry.get("timestamp"))
                    sessions.add(session_key)
                    active_days.add(day)
                    prompts += 1

                    bucket = usage_by_model.setdefault(model, empty_bucket())
                    bucket["inputTokens"] += input_tokens
                    bucket["outputTokens"] += output_tokens
                    bucket["cacheReadInputTokens"] += cache_read
                    bucket["cacheCreationInputTokens"] += cache_write

                    if day in recent:
                        recent[day]["messageCount"] += total

                    if day == today:
                        today_prompt_count += 1
                        today_sessions.add(session_key)
                        today_token_total += total
                        today_tokens[model] = today_tokens.get(model, 0) + total
        except Exception:
            continue

    stats.update({
        "todayPrompts": today_prompt_count,
        "todaySessions": len(today_sessions),
        "todayTotalTokens": today_token_total,
        "todayTokensByModel": today_tokens,
        "recentDays": [recent[day] for day in sorted(recent)],
        "modelUsage": usage_by_model,
        "totalPrompts": prompts,
        "totalSessions": len(sessions),
        "activeDays": len(active_days),
        "activeDates": sorted(active_days),
        "detected": found,
    })
    return stats


def merge_stats(first: dict, second: dict) -> dict:
    out = dict(first)
    out["todayPrompts"] = number(first.get("todayPrompts")) + number(second.get("todayPrompts"))
    out["todaySessions"] = number(first.get("todaySessions")) + number(second.get("todaySessions"))
    out["todayTotalTokens"] = number(first.get("todayTotalTokens")) + number(second.get("todayTotalTokens"))

    today_tokens = dict(first.get("todayTokensByModel") or {})
    for model, value in (second.get("todayTokensByModel") or {}).items():
        today_tokens[model] = today_tokens.get(model, 0) + number(value)
    out["todayTokensByModel"] = today_tokens

    days: dict[str, int] = {}
    for source in (first.get("recentDays") or [], second.get("recentDays") or []):
        for day in source:
            key = str(day.get("date") or "")
            days[key] = days.get(key, 0) + number(day.get("messageCount"))
    out["recentDays"] = [{"date": day, "messageCount": days[day]} for day in sorted(days)]

    models: dict[str, dict[str, int]] = {}
    for source in (first.get("modelUsage") or {}, second.get("modelUsage") or {}):
        for model, bucket in source.items():
            target = models.setdefault(model, empty_bucket())
            for field in ("inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"):
                target[field] = target.get(field, 0) + number((bucket or {}).get(field))
    out["modelUsage"] = models

    out["totalPrompts"] = number(first.get("totalPrompts")) + number(second.get("totalPrompts"))
    out["totalSessions"] = number(first.get("totalSessions")) + number(second.get("totalSessions"))
    dates = set(first.get("activeDates") or []) | set(second.get("activeDates") or [])
    out["activeDates"] = sorted(dates)
    out["activeDays"] = len(dates)
    out["detected"] = bool(first.get("detected")) or bool(second.get("detected"))
    return out
