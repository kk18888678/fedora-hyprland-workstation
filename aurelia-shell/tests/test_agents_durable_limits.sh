#!/usr/bin/env bash

# Durable quota-source durability tests for the four agents collectors.
#
# This suite proves the DURABILITY property, not the happy path: Cline resolves
# limits from a user-owned, non-expiring API key even when the short-lived OAuth
# token is expired, and Claude asks the pi owner to mint a fresh bearer token
# instead of reading (and inevitably outliving) a rotating stored token. Codex
# and OpenCode keep their already-durable sources. Everything runs offline with
# monkey-patched `urlopen`; a sentinel opener fails the test if any code path
# reaches the network without a credential.

set -Eeuo pipefail

section "Agents Durable Limits"

repo_root="$(cd -- "$ROOT/.." && pwd -P)"

if ! command -v python3 >/dev/null; then
    skip "[isolated] durable quota sources (python3 unavailable)"
    return 0
fi

# ---------------------------------------------------------------------------
# Static invariants: shared reader, owner mint, durable sources, no refresh.
# ---------------------------------------------------------------------------
if grep -q 'def read_ai_key' "$repo_root/bin/lib/ai_usage_common.py" &&
   grep -q 'def mint_owner_bearer_token' "$repo_root/bin/lib/ai_usage_common.py" &&
   grep -q '0o077' "$repo_root/bin/lib/ai_usage_common.py"; then
    pass "[static] shared credential reader enforces a private 0600 file and an owner-mint helper exists"
else
    fail "[static] shared AI credential reader / owner mint is missing or does not check permissions"
fi

if grep -q 'print-bearer-token' "$repo_root/bin/ai-usage-claude" &&
   grep -q 'timeout=10' "$repo_root/bin/ai-usage-claude" &&
   grep -q 'ssl.create_default_context()' "$repo_root/bin/ai-usage-claude" &&
   ! grep -q 'refreshToken\|refresh_token' "$repo_root/bin/ai-usage-claude"; then
    pass "[static] Claude collector owner-mints a bounded, TLS-verified token and has no refresh handling"
else
    fail "[static] Claude collector does not use the owner mint or still contains refresh handling"
fi

if grep -q 'cline\.api_key' "$repo_root/bin/ai-usage-cline" &&
   grep -q 'CLINE_API_KEY' "$repo_root/bin/ai-usage-cline" &&
   grep -q 'timeout=10' "$repo_root/bin/ai-usage-cline" &&
   ! grep -q 'refreshToken\|refresh_token' "$repo_root/bin/ai-usage-cline"; then
    pass "[static] Cline collector reads a durable user key with a bounded request and has no refresh handling"
else
    fail "[static] Cline collector durable key source or no-refresh contract is incomplete"
fi

if grep -q 'account/rateLimits/read' "$repo_root/bin/ai-usage-codex" &&
   ! grep -q 'refreshToken\|refresh_token' "$repo_root/bin/ai-usage-codex" &&
   grep -q 'zen/go/v1/usage' "$repo_root/bin/ai-usage-opencode" &&
   grep -q 'opencode-go' "$repo_root/bin/ai-usage-opencode" &&
   ! grep -q 'refreshToken\|refresh_token' "$repo_root/bin/ai-usage-opencode"; then
    pass "[static] Codex and OpenCode keep their durable sources and have no refresh handling"
else
    fail "[static] Codex/OpenCode durable source contract regressed"
fi

if ! grep -qE 'method="(POST|PUT|DELETE|PATCH)"' "$repo_root/bin/ai-usage-claude" "$repo_root/bin/ai-usage-cline" &&
   ! grep -q '"method": *"(POST|PUT|DELETE|PATCH)"' "$repo_root/bin/ai-usage-claude" "$repo_root/bin/ai-usage-cline" &&
   ! grep -qE "open\([^)]*, *['\"][wa]" "$repo_root/bin/ai-usage-claude" "$repo_root/bin/ai-usage-cline"; then
    pass "[static] Claude and Cline collectors are read-only (GET only, no credential writes)"
else
    fail "[static] Claude or Cline collector performs a mutating operation"
fi

# ---------------------------------------------------------------------------
# Isolated durability behavior (monkey-patched urlopen, zero live network).
# ---------------------------------------------------------------------------
sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox" || true' RETURN

mkdir -p -- "$sandbox/home" "$sandbox/config" "$sandbox/pi-empty" \
    "$sandbox/claude-cred" "$sandbox/cline-oauth/data/settings" \
    "$sandbox/cline-empty" "$sandbox/keys" "$sandbox/empty" "$sandbox/empty-claude"
printf '%s' '{"claudeAiOauth":{"accessToken":"STALE-STORE-TOKEN-1234","rateLimitTier":"default_claude_max_20x"}}' \
    >"$sandbox/claude-cred/.credentials.json"
chmod 0600 "$sandbox/claude-cred/.credentials.json"
printf '%s' '{"providers":{"cline":{"settings":{"auth":{"accessToken":"EXPIRED-OAUTH-TOKEN-9999"}}}}}' \
    >"$sandbox/cline-oauth/data/settings/providers.json"
printf '%s\n' 'cline.api_key=sk_CLINE_DURABLE_KEY_ABCDEF' \
    >"$sandbox/keys/cline-api-keys.conf"
chmod 0600 "$sandbox/keys/cline-api-keys.conf"
printf '%s\n' 'cline.api_key=sk_CLINE_LOOSE_KEY_SECRET' \
    >"$sandbox/keys/loose.conf"
chmod 0644 "$sandbox/keys/loose.conf"

durable_out="$(python3 - "$repo_root" "$sandbox" <<'DURABLE_PY'
import contextlib
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import urllib.error

repo_root, sandbox = sys.argv[1], sys.argv[2]


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


claude = load("aclaude", os.path.join(repo_root, "bin", "ai-usage-claude"))
cline = load("acline", os.path.join(repo_root, "bin", "ai-usage-cline"))
common = claude.common
ORIGINAL_MINT = common.mint_owner_bearer_token

claude_cred = os.path.join(sandbox, "claude-cred")
claude_store = os.path.join(claude_cred, ".credentials.json")
cline_oauth = os.path.join(sandbox, "cline-oauth")
cline_oauth_store = os.path.join(cline_oauth, "data", "settings", "providers.json")
keys_dir = os.path.join(sandbox, "keys")
cline_key_file = os.path.join(keys_dir, "cline-api-keys.conf")
cline_loose_file = os.path.join(keys_dir, "loose.conf")
home = os.path.join(sandbox, "home")
empty = os.path.join(sandbox, "empty")
empty_claude = os.path.join(sandbox, "empty-claude")
pi_empty = os.path.join(sandbox, "pi-empty")

CLINE_KEY = "sk_CLINE_DURABLE_KEY_ABCDEF"
CLINE_LOOSE_KEY = "sk_CLINE_LOOSE_KEY_SECRET"
CLINE_OAUTH_EXPIRED = "EXPIRED-OAUTH-TOKEN-9999"
CLAUDE_STORE_TOKEN = "STALE-STORE-TOKEN-1234"
CLAUDE_FRESH = "FRESH-MINTED-TOKEN-5678"
SECRETS = [CLINE_KEY, CLINE_LOOSE_KEY, CLINE_OAUTH_EXPIRED, CLAUDE_STORE_TOKEN, CLAUDE_FRESH]

with open(os.path.join(repo_root, "aurelia-shell", "tests", "fixtures", "agents-claude", "usage.json"), encoding="utf-8") as handle:
    CLAUDE_FIXTURE = json.load(handle)
CLINE_FIXTURE = {"data": {"limits": [
    {"type": "five_hour", "percentUsed": 64, "resetsAt": "2026-09-26T17:15:41.129154652Z"},
    {"type": "weekly", "percentUsed": 63, "resetsAt": "2026-09-30T15:13:55.131223642Z"},
    {"type": "monthly", "percentUsed": 81, "resetsAt": "2026-10-16T02:55:30.133217442Z"},
]}, "success": True}

FIXTURE_FILES = [claude_store, cline_oauth_store, cline_key_file, cline_loose_file]


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


digests_before = {path: digest(path) for path in FIXTURE_FILES}


class Response:
    def __init__(self, payload):
        self.payload = payload

    def read(self):
        return json.dumps(self.payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def base_env():
    os.environ["HOME"] = home
    os.environ["XDG_CONFIG_HOME"] = os.path.join(sandbox, "config")
    os.environ.pop("WORKSTATION_AI_KEYS_CONF", None)
    os.environ.pop("CLINE_API_KEY", None)
    os.environ["WORKSTATION_PI_BIN"] = ""


def capture_response(payload, extra_calls=None):
    calls = []

    def opener(request, *args, **kwargs):
        calls.append({
            "auth": request.get_header("Authorization") or "",
            "timeout": kwargs.get("timeout"),
            "method": request.get_method(),
        })
        if extra_calls is not None:
            extra_calls.append(1)
        return Response(payload)

    return opener, calls


def sentinel(calls):
    def opener(*args, **kwargs):
        calls.append(1)
        raise AssertionError("network call attempted without a credential")
    return opener


def http_error(status):
    def raiser(*args, **kwargs):
        raise urllib.error.HTTPError("https://example.invalid/x", status, "err", {}, None)
    return raiser


def contains_secret(text):
    return any(secret in text for secret in SECRETS)


results = {}

# --- Cline: durable config key wins even when the OAuth token is expired -----
base_env()
os.environ["WORKSTATION_AI_KEYS_CONF"] = cline_key_file
os.environ["CLINE_DIR"] = cline_oauth
opener, calls = capture_response(CLINE_FIXTURE)
cline.urllib.request.urlopen = opener
cline_result = cline.fetch_cline_limits()
record_text = ""
sys.argv = ["ai-usage-cline"]
buffer = io.StringIO()
with contextlib.redirect_stdout(buffer):
    cline.main()
record_text = buffer.getvalue()
record = json.loads(record_text)
results["clineDurable"] = {
    "limits": len(cline_result["limits"]),
    "authUsesKey": calls[0]["auth"] == "Bearer " + CLINE_KEY if calls else False,
    "authUsesExpired": any(call["auth"] == "Bearer " + CLINE_OAUTH_EXPIRED for call in calls),
    "timeout": calls[0]["timeout"] if calls else None,
    "method": calls[0]["method"] if calls else "",
    "recordLimits": len(record["limits"]),
    "recordTier": record["tierLabel"],
    "recordStatus": record["usageStatusText"],
    "recordLeaks": contains_secret(record_text),
}

# --- Cline: environment variable is accepted as a durable key ----------------
base_env()
os.environ["CLINE_API_KEY"] = "sk_CLINE_ENV_KEY"
os.environ["CLINE_DIR"] = cline_oauth
opener, calls = capture_response(CLINE_FIXTURE)
cline.urllib.request.urlopen = opener
cline.fetch_cline_limits()
results["clineEnv"] = {
    "authUsesEnv": calls[0]["auth"] == "Bearer sk_CLINE_ENV_KEY" if calls else False,
    "timeout": calls[0]["timeout"] if calls else None,
}

# --- Cline: no durable key falls back to the best-effort OAuth token ---------
base_env()
os.environ["WORKSTATION_AI_KEYS_CONF"] = os.path.join(sandbox, "does-not-exist.conf")
os.environ["CLINE_DIR"] = cline_oauth
opener, calls = capture_response(CLINE_FIXTURE)
cline.urllib.request.urlopen = opener
cline.fetch_cline_limits()
results["clineOauthFallback"] = {
    "authUsesOauth": calls[0]["auth"] == "Bearer " + CLINE_OAUTH_EXPIRED if calls else False,
}

# --- Cline: no credential means no network call and an honest status ---------
base_env()
os.environ["WORKSTATION_AI_KEYS_CONF"] = os.path.join(sandbox, "does-not-exist.conf")
os.environ["CLINE_DIR"] = os.path.join(sandbox, "cline-empty")
no_cred_calls = []
cline.urllib.request.urlopen = sentinel(no_cred_calls)
no_cred = cline.fetch_cline_limits()
results["clineNoKey"] = {
    "calls": len(no_cred_calls),
    "status": no_cred["usageStatusText"],
    "limits": len(no_cred["limits"]),
    "retry": no_cred["retryAdvised"],
}

# --- Cline: a loose-permission key file is refused, not read -----------------
base_env()
os.environ["WORKSTATION_AI_KEYS_CONF"] = cline_loose_file
os.environ["CLINE_DIR"] = os.path.join(sandbox, "cline-empty")
loose_calls = []
cline.urllib.request.urlopen = sentinel(loose_calls)
loose = cline.fetch_cline_limits()
results["clineLoosePerm"] = {
    "readEmpty": common.read_ai_key("cline.api_key") == "",
    "calls": len(loose_calls),
    "status": loose["usageStatusText"],
}

# --- Cline: a rejected key is an actionable, redacted, non-retryable error ---
base_env()
os.environ["WORKSTATION_AI_KEYS_CONF"] = cline_key_file
os.environ["CLINE_DIR"] = os.path.join(sandbox, "cline-empty")
cline.urllib.request.urlopen = http_error(401)
rejected = cline.fetch_cline_limits()
results["clineAuth"] = {
    "limits": len(rejected["limits"]),
    "status": rejected["usageStatusText"],
    "helpNonEmpty": bool(rejected["authHelpText"]),
    "retry": rejected["retryAdvised"],
    "leaks": contains_secret(json.dumps(rejected)),
}

# --- Cline: changed/malformed shapes fail closed with no fabricated 0% -------
base_env()
os.environ["WORKSTATION_AI_KEYS_CONF"] = cline_key_file
os.environ["CLINE_DIR"] = os.path.join(sandbox, "cline-empty")
shape_payloads = [
    {"success": True},
    {"data": {"limits": "nope"}},
    {"data": {"limits": [{"type": "five_hour"}]}},
    {"data": {"limits": [{"type": "five_hour", "percentUsed": "abc"}]}},
    {"data": {"limits": [42]}},
]
shape_ok = True
shape_empty = True
shape_non_retry = True
for payload in shape_payloads:
    opener, _calls = capture_response(payload)
    cline.urllib.request.urlopen = opener
    parsed = cline.fetch_cline_limits()
    shape_ok = shape_ok and parsed["usageStatusText"] == "Cline limits unavailable"
    shape_empty = shape_empty and parsed["limits"] == []
    shape_non_retry = shape_non_retry and parsed["retryAdvised"] is False
results["clineShapes"] = {
    "unavailable": shape_ok,
    "empty": shape_empty,
    "nonRetry": shape_non_retry,
}

# --- Claude: owner mint supplies a fresh token, store bytes untouched --------
base_env()
os.environ["CLAUDE_CONFIG_DIR"] = claude_cred
os.environ["PI_HOME"] = pi_empty


def mint_fresh(provider, *args, **kwargs):
    return {"token": CLAUDE_FRESH, "available": True, "error": ""}


common.mint_owner_bearer_token = mint_fresh
opener, calls = capture_response(CLAUDE_FIXTURE)
claude.urllib.request.urlopen = opener
store_before = digest(claude_store)
claude_result = claude.fetch_claude_limits()
store_after = digest(claude_store)
sys.argv = ["ai-usage-claude"]
buffer = io.StringIO()
with contextlib.redirect_stdout(buffer):
    claude.main()
claude_record_text = buffer.getvalue()
claude_record = json.loads(claude_record_text)
results["claudeMint"] = {
    "limits": len(claude_result["limits"]),
    "authUsesFresh": calls and calls[0]["auth"] == "Bearer " + CLAUDE_FRESH,
    "authUsesStale": any(call["auth"] == "Bearer " + CLAUDE_STORE_TOKEN for call in calls),
    "timeout": calls[0]["timeout"] if calls else None,
    "method": calls[0]["method"] if calls else "",
    "storeUnchanged": store_before == store_after,
    "labels": [entry["label"] for entry in claude_result["limits"]],
    "recordLimits": len(claude_record["limits"]),
    "supported": claude_record["supportedWindowMinutes"],
    "recordLeaks": contains_secret(claude_record_text),
}

# --- Claude: stored owner credential is the secondary path -------------------
base_env()
os.environ["CLAUDE_CONFIG_DIR"] = claude_cred
os.environ["PI_HOME"] = pi_empty
common.mint_owner_bearer_token = lambda *args, **kwargs: {"token": "", "available": False, "error": ""}
opener, calls = capture_response(CLAUDE_FIXTURE)
claude.urllib.request.urlopen = opener
stored_result = claude.fetch_claude_limits()
results["claudeStored"] = {
    "authUsesStored": calls and calls[0]["auth"] == "Bearer " + CLAUDE_STORE_TOKEN,
    "limits": len(stored_result["limits"]),
}

# --- Claude: no owner and no credential means no network call ----------------
base_env()
os.environ["CLAUDE_CONFIG_DIR"] = empty_claude
os.environ["PI_HOME"] = pi_empty
common.mint_owner_bearer_token = lambda *args, **kwargs: {"token": "", "available": False, "error": ""}
missing_calls = []
claude.urllib.request.urlopen = sentinel(missing_calls)
missing = claude.fetch_claude_limits()
results["claudeNoCredential"] = {
    "calls": len(missing_calls),
    "status": missing["usageStatusText"],
    "limits": len(missing["limits"]),
    "retry": missing["retryAdvised"],
}

# --- Claude: an owner that exists but fails is observable, not silent --------
base_env()
os.environ["CLAUDE_CONFIG_DIR"] = empty_claude
os.environ["PI_HOME"] = pi_empty
common.mint_owner_bearer_token = lambda *args, **kwargs: {"token": "", "available": True, "error": "boom"}
failed_calls = []
claude.urllib.request.urlopen = sentinel(failed_calls)
failed = claude.fetch_claude_limits()
results["claudeOwnerFailed"] = {
    "calls": len(failed_calls),
    "status": failed["usageStatusText"],
    "helpNonEmpty": bool(failed["authHelpText"]),
    "retry": failed["retryAdvised"],
}

# --- Claude: a 401 re-mints exactly once and retries with the fresh token -----
base_env()
os.environ["CLAUDE_CONFIG_DIR"] = empty_claude
os.environ["PI_HOME"] = pi_empty
mint_calls = []


def mint_sequence(provider, *args, **kwargs):
    mint_calls.append(1)
    token = "MINT-1" if len(mint_calls) == 1 else "MINT-2"
    return {"token": token, "available": True, "error": ""}


common.mint_owner_bearer_token = mint_sequence
net_calls = []
first = {"done": False}


def remint_opener(request, *args, **kwargs):
    net_calls.append(request.get_header("Authorization") or "")
    if not first["done"]:
        first["done"] = True
        raise urllib.error.HTTPError("https://example.invalid/x", 401, "Unauthorized", {}, None)
    return Response(CLAUDE_FIXTURE)


claude.urllib.request.urlopen = remint_opener
remint = claude.fetch_claude_limits()
results["claudeRemint"] = {
    "netCalls": len(net_calls),
    "mintCalls": len(mint_calls),
    "secondAuthFresh": len(net_calls) == 2 and net_calls[1] == "Bearer MINT-2",
    "limits": len(remint["limits"]),
}

# --- Claude: repeated 401 fails closed after the single re-mint --------------
base_env()
os.environ["CLAUDE_CONFIG_DIR"] = empty_claude
os.environ["PI_HOME"] = pi_empty
common.mint_owner_bearer_token = lambda *args, **kwargs: {"token": "MINT-X", "available": True, "error": ""}
fail_calls = []


def always_401(request, *args, **kwargs):
    fail_calls.append(1)
    raise urllib.error.HTTPError("https://example.invalid/x", 401, "Unauthorized", {}, None)


claude.urllib.request.urlopen = always_401
auth_failed = claude.fetch_claude_limits()
results["claudeRemintFail"] = {
    "calls": len(fail_calls),
    "status": auth_failed["usageStatusText"],
    "retry": auth_failed["retryAdvised"],
    "helpNonEmpty": bool(auth_failed["authHelpText"]),
}

# --- Claude: changed shapes fail closed, 429 stays retryable -----------------
base_env()
os.environ["CLAUDE_CONFIG_DIR"] = empty_claude
os.environ["PI_HOME"] = pi_empty
common.mint_owner_bearer_token = mint_fresh
claude_shapes_ok = True
for payload in ({"success": True}, {"limits": "nope"}):
    opener, _calls = capture_response(payload)
    claude.urllib.request.urlopen = opener
    parsed = claude.fetch_claude_limits()
    claude_shapes_ok = claude_shapes_ok and parsed["usageStatusText"] == "Claude limits unavailable" and parsed["limits"] == []
claude.urllib.request.urlopen = http_error(429)
rate = claude.fetch_claude_limits()
results["claudeShapes"] = {"unavailable": claude_shapes_ok}
results["claudeRate"] = {"retry": rate["retryAdvised"], "helpEmpty": rate["authHelpText"] == ""}
results["claudeWindows"] = {
    "supported": claude.SUPPORTED_WINDOW_MINUTES,
    "noMonthly": all(entry["windowMinutes"] != 43200 for entry in claude_result["limits"]),
}

common.mint_owner_bearer_token = ORIGINAL_MINT

# --- Fixture files are byte-identical after every run ------------------------
results["filesUnchanged"] = {path: digest(path) == digests_before[path] for path in FIXTURE_FILES}
results["leaksAnywhere"] = contains_secret(record_text + claude_record_text)

print(json.dumps(results, sort_keys=True))
DURABLE_PY
)"

if printf '%s' "$durable_out" | jq -e '
        .clineDurable.limits == 3 and
        .clineDurable.authUsesKey == true and
        .clineDurable.authUsesExpired == false and
        .clineDurable.timeout == 10 and
        .clineDurable.method == "GET" and
        .clineDurable.recordLimits == 3 and
        .clineDurable.recordTier == "ClinePass" and
        .clineDurable.recordStatus == "" and
        .clineDurable.recordLeaks == false' >/dev/null; then
    pass "[isolated] Cline uses the durable config API key even when the OAuth token is expired"
else
    fail "[isolated] Cline did not prefer the durable API key over the expired OAuth token"
fi

if printf '%s' "$durable_out" | jq -e '
        .clineEnv.authUsesEnv == true and .clineEnv.timeout == 10 and
        .clineOauthFallback.authUsesOauth == true' >/dev/null; then
    pass "[isolated] Cline accepts the environment key and keeps the OAuth token as a labelled fallback"
else
    fail "[isolated] Cline environment key or OAuth fallback regressed"
fi

if printf '%s' "$durable_out" | jq -e '
        .clineNoKey.calls == 0 and .clineNoKey.limits == 0 and
        .clineNoKey.retry == false and
        (.clineNoKey.status | test("not configured"; "i"))' >/dev/null; then
    pass "[isolated] Cline with no credential makes no network call and reports a not-configured status"
else
    fail "[isolated] Cline no-credential behavior diverged"
fi

if printf '%s' "$durable_out" | jq -e '
        .clineLoosePerm.readEmpty == true and .clineLoosePerm.calls == 0 and
        (.clineLoosePerm.status | test("not configured"; "i"))' >/dev/null; then
    pass "[isolated] a group/world-readable Cline key file is refused rather than read"
else
    fail "[isolated] Cline loose-permission key file was not refused"
fi

if printf '%s' "$durable_out" | jq -e '
        .clineAuth.limits == 0 and .clineAuth.helpNonEmpty == true and
        .clineAuth.retry == false and .clineAuth.leaks == false and
        (.clineAuth.status | test("auth"; "i"))' >/dev/null; then
    pass "[isolated] a rejected Cline key yields a redacted actionable auth error and no retry"
else
    fail "[isolated] Cline rejected-key handling diverged"
fi

if printf '%s' "$durable_out" | jq -e '
        .clineShapes.unavailable == true and .clineShapes.empty == true and
        .clineShapes.nonRetry == true' >/dev/null; then
    pass "[isolated] every changed Cline shape fails closed as limits unavailable with no fabricated 0%"
else
    fail "[isolated] Cline shape guards regressed"
fi

if printf '%s' "$durable_out" | jq -e '
        .claudeMint.limits == 2 and .claudeMint.authUsesFresh == true and
        .claudeMint.authUsesStale == false and .claudeMint.timeout == 10 and
        .claudeMint.method == "GET" and .claudeMint.storeUnchanged == true and
        .claudeMint.labels == ["5h window","Weekly (7-day)"] and
        .claudeMint.recordLimits == 2 and .claudeMint.supported == [300,10080] and
        .claudeMint.recordLeaks == false' >/dev/null; then
    pass "[isolated] Claude owner-mints a fresh token, leaves the store untouched and classifies on kind"
else
    fail "[isolated] Claude owner-mint durability contract regressed"
fi

if printf '%s' "$durable_out" | jq -e '
        .claudeStored.authUsesStored == true and .claudeStored.limits == 2' >/dev/null; then
    pass "[isolated] Claude falls back to a stored owner credential only when the mint is unavailable"
else
    fail "[isolated] Claude stored-credential fallback regressed"
fi

if printf '%s' "$durable_out" | jq -e '
        .claudeNoCredential.calls == 0 and .claudeNoCredential.limits == 0 and
        .claudeNoCredential.retry == false and
        .claudeNoCredential.status == "Local usage only"' >/dev/null; then
    pass "[isolated] Claude with no owner and no credential makes no network call and stays local-only"
else
    fail "[isolated] Claude no-credential behavior diverged"
fi

if printf '%s' "$durable_out" | jq -e '
        .claudeOwnerFailed.calls == 0 and .claudeOwnerFailed.helpNonEmpty == true and
        .claudeOwnerFailed.retry == false and
        .claudeOwnerFailed.status == "Claude credential unavailable"' >/dev/null; then
    pass "[isolated] an unavailable Claude owner degrades to an observable, non-retryable diagnostic"
else
    fail "[isolated] Claude unavailable-owner diagnostic regressed"
fi

if printf '%s' "$durable_out" | jq -e '
        .claudeRemint.netCalls == 2 and .claudeRemint.mintCalls == 2 and
        .claudeRemint.secondAuthFresh == true and .claudeRemint.limits == 2' >/dev/null; then
    pass "[isolated] a Claude 401 re-mints exactly once and retries with the fresh owner token"
else
    fail "[isolated] Claude 401 re-mint-once behavior regressed"
fi

if printf '%s' "$durable_out" | jq -e '
        .claudeRemintFail.calls == 2 and .claudeRemintFail.retry == false and
        .claudeRemintFail.helpNonEmpty == true and
        (.claudeRemintFail.status | test("auth"; "i"))' >/dev/null; then
    pass "[isolated] repeated Claude 401s fail closed after the single re-mint"
else
    fail "[isolated] Claude repeated-401 handling regressed"
fi

if printf '%s' "$durable_out" | jq -e '
        .claudeShapes.unavailable == true and .claudeRate.retry == true and
        .claudeRate.helpEmpty == true and .claudeWindows.supported == [300,10080] and
        .claudeWindows.noMonthly == true' >/dev/null; then
    pass "[isolated] Claude shape changes fail closed, 429 stays retryable and no monthly window is synthesised"
else
    fail "[isolated] Claude shape/rate/window contract regressed"
fi

if printf '%s' "$durable_out" | jq -e '
        ([.filesUnchanged[]] | all) and .leaksAnywhere == false' >/dev/null; then
    pass "[isolated] every credential fixture is byte-identical after the runs and no fixture secret is emitted"
else
    fail "[isolated] a credential fixture changed or a fixture secret leaked"
fi
