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
import math
import os
import shutil
import subprocess
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


def empty_day(date: str) -> dict:
    """Internal per-day accumulator: total tokens plus the billable/cache split."""
    return {"date": date, "tokens": 0, "billableTokens": 0, "cacheTokens": 0}


def finalize_day(day: dict) -> dict:
    """Contract-shaped per-day entry.

    `tokens` is the cache-inclusive total that the legacy `messageCount` key
    also carried. `messageCount` is retained as a deprecated alias because the
    current AgentsPanel day chart still reads it; new consumers must read
    `tokens`/`billableTokens`/`cacheTokens`.
    """
    tokens = number(day.get("tokens"))
    billable = number(day.get("billableTokens"))
    cache = number(day.get("cacheTokens"))
    if billable == 0 and cache == 0 and tokens:
        # Legacy snapshots only recorded the cache-inclusive total.
        billable = tokens
    return {
        "date": str(day.get("date") or ""),
        "tokens": tokens,
        "billableTokens": billable,
        "cacheTokens": cache,
        "messageCount": tokens,
    }


def finalize_model_buckets(usage_by_model: dict) -> dict:
    """Add the billable/cache split to every model-usage bucket."""
    out = {}
    for model, bucket in (usage_by_model or {}).items():
        b = bucket or {}
        input_tokens = number(b.get("inputTokens"))
        output_tokens = number(b.get("outputTokens"))
        cache_read = number(b.get("cacheReadInputTokens"))
        cache_write = number(b.get("cacheCreationInputTokens"))
        billable = input_tokens + output_tokens
        cache = cache_read + cache_write
        out[model] = {
            "inputTokens": input_tokens,
            "outputTokens": output_tokens,
            "cacheReadInputTokens": cache_read,
            "cacheCreationInputTokens": cache_write,
            "billableTokens": billable,
            "cacheTokens": cache,
            "totalTokens": billable + cache,
        }
    return out


def today_model_split(usage_by_model: dict) -> dict:
    """Per-model today totals as an explicit billable/cache/total split."""
    out = {}
    for model, bucket in (usage_by_model or {}).items():
        b = bucket or {}
        billable = number(b.get("inputTokens")) + number(b.get("outputTokens"))
        cache = number(b.get("cacheReadInputTokens")) + number(b.get("cacheCreationInputTokens"))
        out[model] = {"billableTokens": billable, "cacheTokens": cache, "totalTokens": billable + cache}
    return out


def _today_split(value):
    """Accept both the new split object and the legacy bare integer total."""
    if isinstance(value, dict):
        billable = number(value.get("billableTokens"))
        cache = number(value.get("cacheTokens"))
        total = number(value.get("totalTokens"))
        if total == 0 and (billable or cache):
            total = billable + cache
        return billable, cache, total
    total = number(value)
    return total, 0, total


def normalize_resets_at(value) -> str:
    """Normalise a reset timestamp to a UTC ISO-8601 string.

    Accepts epoch seconds, epoch milliseconds and ISO-8601 text so that the UI
    can always derive a reset countdown with `Date.parse`. Unparseable input is
    returned as an empty string rather than a value `Date.parse` would turn
    into NaN.
    """
    if value is None or isinstance(value, bool):
        return ""
    numeric = None
    if isinstance(value, (int, float)):
        numeric = float(value)
    else:
        text = str(value).strip()
        if not text:
            return ""
        try:
            numeric = float(text)
        except Exception:
            numeric = None
    if numeric is not None:
        if numeric <= 0:
            return ""
        seconds = numeric / 1000.0 if numeric > 1e11 else numeric
        try:
            return dt.datetime.fromtimestamp(seconds, dt.timezone.utc).isoformat()
        except Exception:
            return ""
    text = str(value).strip()
    try:
        parsed = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except Exception:
        return ""
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc).isoformat()


RETRYABLE_ERROR_MARKERS = (
    "429",
    "too many requests",
    "rate limit",
    "ratelimit",
    "timeout",
    "timed out",
    "temporarily unavailable",
)


def retry_advised_from_error(exc) -> bool:
    """True when an upstream error warrants the single documented 30s retry."""
    text = str(exc or "").lower()
    if not text:
        return False
    return any(marker in text for marker in RETRYABLE_ERROR_MARKERS)


def config_path() -> Path:
    override = os.environ.get("WORKSTATION_AI_CONF")
    if override:
        return Path(override)
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(os.path.expandvars(os.path.expanduser(base))) / "workstation" / "ai.conf"


# ---------------------------------------------------------------------------
# Durable credential sources (user-owned config / owner-delegated mint)
# ---------------------------------------------------------------------------
# The collectors are read-only: they never refresh a rotating token and never
# write a credential store. Instead they resolve a credential from the most
# durable source available and, when the credential has a lifecycle, ask its
# real owner to mint a fresh one at request time. These helpers are shared so
# Claude and Cline do not grow two divergent implementations.


def ai_keys_path() -> Path:
    """Path to the private, user-owned AI key file.

    Default: `~/.config/workstation/ai-keys.conf` (mode 0600). The
    `WORKSTATION_AI_KEYS_CONF` override exists for isolated tests; it is never
    used to relocate a real credential in production.
    """
    override = os.environ.get("WORKSTATION_AI_KEYS_CONF")
    if override:
        return Path(os.path.expandvars(os.path.expanduser(override)))
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(os.path.expandvars(os.path.expanduser(base))) / "workstation" / "ai-keys.conf"


def _private_config_file(path: Path) -> bool:
    """True only when `path` exists and carries no group/other permission bits."""
    try:
        mode = path.stat().st_mode & 0o777
    except OSError:
        return False
    return (mode & 0o077) == 0


def read_ai_key(field: str, env_var: str = "") -> str:
    """Return a durable user-owned API key, or "".

    Precedence is environment variable, then config file. The config file is
    read only when it is not group/world accessible, so a loose-permission file
    fails closed rather than leaking the secret. The value is never printed,
    logged or written. An absent file or field is a normal local-only state,
    not an error.
    """
    if env_var:
        value = os.environ.get(env_var)
        if value:
            text = str(value).strip()
            if text:
                return text
    path = ai_keys_path()
    if not path.is_file():
        return ""
    if not _private_config_file(path):
        return ""
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            key, _, value = stripped.partition("=")
            if key.strip() == field:
                text = value.strip()
                if text:
                    return text
    except Exception:
        return ""
    return ""


def owner_binary(binary_name: str, env_override: str = "") -> str:
    """Resolve the CLI that owns a credential's lifecycle, or "".

    The override is only consulted when set, and an explicitly empty override
    disables the owner (used by the isolated tests to keep them offline).
    """
    if env_override and env_override in os.environ:
        override = os.environ.get(env_override) or ""
        if not override:
            return ""
        path = Path(os.path.expandvars(os.path.expanduser(override)))
        return str(path) if path.is_file() else ""
    found = shutil.which(binary_name)
    return found or ""


def mint_owner_bearer_token(provider: str, binary_name: str = "pi", env_override: str = "WORKSTATION_PI_BIN", timeout: float = 10.0) -> dict:
    """Ask a credential's owner CLI to mint a fresh bearer token.

    Returns `{"token": str, "available": bool, "error": str}`. The subprocess
    is bounded by `timeout` and killed on expiry. stdout is captured and used
    verbatim, then discarded; stderr is discarded; nothing about the token is
    ever logged or written. A missing binary is reported as `available: false`
    (a local-only state), while an execution failure is an observable error.
    """
    result = {"token": "", "available": False, "error": ""}
    binary = owner_binary(binary_name, env_override)
    if not binary:
        return result
    result["available"] = True
    try:
        completed = subprocess.run(
            [binary, "auth", "print-bearer-token", "--provider", str(provider)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            env=dict(os.environ),
            check=False,
        )
    except subprocess.TimeoutExpired:
        result["error"] = "owner token mint timed out"
        return result
    except Exception:
        result["error"] = "owner token mint failed"
        return result
    if completed.returncode != 0:
        result["error"] = "owner token mint failed"
        return result
    for line in (completed.stdout or "").splitlines():
        text = line.strip()
        if text:
            result["token"] = text
            break
    if not result["token"]:
        result["error"] = "owner token mint returned no token"
    return result


def used_fraction(percent):
    """USED percent (0..100) -> emitted USED fraction in [0,1], or None.

    The clamp is applied to the FINAL emitted fraction so a server value above
    the window cap becomes `1.0` rather than being discarded. A negative,
    non-numeric or non-finite value returns None (the caller decides whether
    that is a skipped row or a changed shape); it is never a fabricated `0%`.
    """
    if isinstance(percent, bool):
        return None
    try:
        value = float(percent)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(value) or value < 0:
        return None
    fraction = value / 100.0
    if fraction > 1.0:
        fraction = 1.0
    return fraction


def days_until(date_text: str):
    text = str(date_text or "").strip()
    if not text:
        return None
    try:
        target = dt.date.fromisoformat(text)
    except Exception:
        return None
    return (target - dt.date.today()).days


# Subscription metadata is user-owned: the vendors' local data has no billing
# date, so the user records plan / renewal / cycle in ai.conf and every
# collector merges it into its record.
def load_subscription(agent: str) -> dict:
    path = config_path()
    if not path.is_file():
        return {}
    prefix = "subscription." + str(agent) + "."
    values = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            if key.startswith(prefix):
                values[key[len(prefix):]] = value.strip()
    except Exception:
        return {}
    if not values:
        return {}
    reminder = values.get("reminder_days", "")
    result = {
        "plan": values.get("plan", ""),
        "renew": values.get("renew", ""),
        "cycle": values.get("cycle", ""),
        "cost": values.get("cost", ""),
        "currency": values.get("currency", "USD") or "USD",
        "reminderDays": int(reminder) if reminder.isdigit() else 3,
    }
    result["daysLeft"] = days_until(result["renew"])
    return result


def apply_subscription(record: dict, agent: str) -> dict:
    sub = load_subscription(agent)
    if sub:
        record["subscription"] = sub
        if not record.get("tierLabel"):
            record["tierLabel"] = sub.get("plan", "")
    return record


def account_object(source: str, **fields) -> dict:
    """Build the optional collector `account` object, or {} when nothing is known.

    Identity is private display data. This helper never emits an empty-string
    field, and returns {} when only the provenance token would be present, so a
    record only carries `account` when a real value exists. The allowed fields
    are exactly the display fields: `email`, `name`, `plan` and `billingDate`.
    The token/credential itself is never accepted here.
    """
    account = {}
    if str(source or "").strip():
        account["source"] = str(source).strip()
    for key in ("email", "name", "plan", "billingDate"):
        value = str(fields.get(key) or "").strip()
        if value:
            account[key] = value
    if "source" in account and len(account) == 1:
        return {}
    return account


def empty_stats() -> dict:
    recent = recent_date_strings()
    return {
        "todayPrompts": 0,
        "todaySessions": 0,
        "todayTotalTokens": 0,
        "todayBillableTokens": 0,
        "todayCacheTokens": 0,
        "todayTokensByModel": {},
        "recentDays": [empty_day(day) for day in recent],
        "modelUsage": {},
        "totalPrompts": 0,
        "totalSessions": 0,
        "activeDays": 0,
        "activeDates": [],
        "detected": False,
    }


def pi_agent_root() -> Path:
    base = os.environ.get("PI_HOME") or str(Path.home() / ".pi")
    return Path(os.path.expandvars(os.path.expanduser(base))) / "agent"


def pi_sessions_root() -> Path:
    return pi_agent_root() / "sessions"


def pi_provider_configured(provider: str) -> bool:
    """True when pi holds an auth or model-store entry for the provider id.

    pi keys both `agent/auth.json` (credentials) and
    `agent/models-store.json` (model catalogs) by provider id. An account
    that is configured but has not produced a turn yet has no usage to scan,
    so a collector that wants it visible before first use consults this in
    addition to its usage scans. Only key presence is inspected; credential
    material is never read or emitted.
    """
    wanted = str(provider or "")
    if not wanted:
        return False
    agent = pi_agent_root()
    for name in ("auth.json", "models-store.json"):
        path = agent / name
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if isinstance(data, dict) and bool(data.get(wanted)):
            return True
    return False


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
    today_by_model: dict[str, dict[str, int]] = {}
    usage_by_model: dict[str, dict[str, int]] = {}
    prompts = 0
    today_prompt_count = 0
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

                    billable = input_tokens + output_tokens
                    cache = cache_read + cache_write
                    if day in recent:
                        entry = recent[day]
                        entry["tokens"] += total
                        entry["billableTokens"] += billable
                        entry["cacheTokens"] += cache

                    if day == today:
                        today_prompt_count += 1
                        today_sessions.add(session_key)
                        today_bucket = today_by_model.setdefault(model, empty_bucket())
                        today_bucket["inputTokens"] += input_tokens
                        today_bucket["outputTokens"] += output_tokens
                        today_bucket["cacheReadInputTokens"] += cache_read
                        today_bucket["cacheCreationInputTokens"] += cache_write
        except Exception:
            continue

    today_split = today_model_split(today_by_model)
    stats.update({
        "todayPrompts": today_prompt_count,
        "todaySessions": len(today_sessions),
        "todayTotalTokens": sum(v["totalTokens"] for v in today_split.values()),
        "todayBillableTokens": sum(v["billableTokens"] for v in today_split.values()),
        "todayCacheTokens": sum(v["cacheTokens"] for v in today_split.values()),
        "todayTokensByModel": today_split,
        "recentDays": [finalize_day(recent[day]) for day in sorted(recent)],
        "modelUsage": finalize_model_buckets(usage_by_model),
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

    today_models: dict[str, dict[str, int]] = {}
    for source in (first.get("todayTokensByModel") or {}, second.get("todayTokensByModel") or {}):
        for model, value in source.items():
            billable, cache, total = _today_split(value)
            target = today_models.setdefault(
                model, {"billableTokens": 0, "cacheTokens": 0, "totalTokens": 0}
            )
            target["billableTokens"] += billable
            target["cacheTokens"] += cache
            target["totalTokens"] += total
    if today_models:
        out["todayTokensByModel"] = today_models
        out["todayBillableTokens"] = sum(v["billableTokens"] for v in today_models.values())
        out["todayCacheTokens"] = sum(v["cacheTokens"] for v in today_models.values())
        out["todayTotalTokens"] = out["todayBillableTokens"] + out["todayCacheTokens"]
    else:
        # No per-model detail: keep the cache-inclusive total and bill it all.
        total = number(first.get("todayTotalTokens")) + number(second.get("todayTotalTokens"))
        out["todayTokensByModel"] = {}
        out["todayBillableTokens"] = total
        out["todayCacheTokens"] = 0
        out["todayTotalTokens"] = total

    days: dict[str, dict] = {}
    for source in (first.get("recentDays") or [], second.get("recentDays") or []):
        for day in source:
            key = str(day.get("date") or "")
            tokens = number(day.get("tokens")) if "tokens" in day else number(day.get("messageCount"))
            billable = number(day.get("billableTokens"))
            cache = number(day.get("cacheTokens"))
            if billable == 0 and cache == 0 and tokens:
                billable = tokens
            entry = days.setdefault(key, empty_day(key))
            entry["tokens"] += tokens
            entry["billableTokens"] += billable
            entry["cacheTokens"] += cache
    out["recentDays"] = [finalize_day(days[day]) for day in sorted(days)]

    models: dict[str, dict[str, int]] = {}
    for source in (first.get("modelUsage") or {}, second.get("modelUsage") or {}):
        for model, bucket in source.items():
            target = models.setdefault(model, empty_bucket())
            for field in ("inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"):
                target[field] = target.get(field, 0) + number((bucket or {}).get(field))
    out["modelUsage"] = finalize_model_buckets(models)

    out["totalPrompts"] = number(first.get("totalPrompts")) + number(second.get("totalPrompts"))
    out["totalSessions"] = number(first.get("totalSessions")) + number(second.get("totalSessions"))
    dates = set(first.get("activeDates") or []) | set(second.get("activeDates") or [])
    out["activeDates"] = sorted(dates)
    out["activeDays"] = len(dates)
    out["detected"] = bool(first.get("detected")) or bool(second.get("detected"))
    return out
