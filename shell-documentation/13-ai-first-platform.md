# AI-first platform architecture

## The precise meaning of “AI-first” in the source

The reference is AI-agent-first, not an embedded large-language-model runtime.
The shell does not contain a model, prompt engine, provider router, or cloud
conversation database. Instead, it makes AI a first-class operating-system
capability through:

1. lazy command launchers for many coding-agent CLIs, plus explicit package
   adapters for agents with a different runtime owner;
2. one default-agent selection and launch path;
3. a bar/panel dashboard for local and subscription usage;
4. cross-device usage aggregation;
5. agent skills symlinked into the major harnesses;
6. crash-to-agent diagnosis;
7. optional desktop agent applications and local-LLM runtimes;
8. AI dictation as a separate voice-input integration.

That distinction is essential for a 1:1 implementation. Replacing the external
agent ecosystem with a new in-shell “AI assistant” would be a new feature, not
the reference architecture.

## AI surface map

```text
session/user setup
  ├─ lazy CLI stubs in ~/.local/bin/
  ├─ default agent file
  ├─ agent skills -> harness skill roots
  └─ optional desktop/local model installations

coding session
  ├─ default-agent launcher -> dedicated terminal or inline process
  ├─ prompt launcher -> same path with provider-specific arguments
  └─ terminal aliases and development layouts

observability
  ├─ usage collectors -> ~/.local/state/.../agents/usage/<id>.json
  ├─ shell agents widget watches records and renders the panel
  ├─ optional synced snapshots merge device-scoped stats
  └─ crash watcher -> notification -> default agent + diagnosis skill

input
  └─ Voxtype daemon -> dictation indicator and focused-input output
```

## Lazy agent launchers

The user-finalization script installs small wrappers in `~/.local/bin/` through
`omarchy-mise-install`. A wrapper has this behavior:

```text
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g --quiet <package>
exec mise x <package> -- <binary> "$@"
```

The first invocation installs/resolves the tool; later invocations execute the
same mise-managed package. The release-age override is intentional: a user
request to run the agent should not be held behind mise’s normal release
cooldown. The update command also runs `MISE_MINIMUM_RELEASE_AGE=0 mise up`.

The shipped agent command names are:

| Command | Package/owner path | Notes |
|---|---|---|
| `claude` | mise package `claude` | Claude Code |
| `codex` | mise package `codex` | OpenAI Codex CLI |
| `opencode` | mise package `opencode` | OpenCode |
| `agy` | `antigravity-cli` through mise | Antigravity CLI |
| `copilot` | mise package `copilot` | GitHub Copilot CLI |
| `crush` | mise package `crush` | Crush |
| `grok` | `npm:@xai-official/grok` | Grok CLI |
| `pi` | mise package `pi` | Pi |
| `omp` | `github:can1357/oh-my-pi` | Oh My Pi |
| `ori` | `github:OpenRouterLabs/ori-releases` | OpenRouter harness |
| `hermes` | dedicated pinned installer | Hermes Agent; not a generic mise line |
| `muse` | Meta HTTP launcher through mise | native launcher verifies/updates its binary |
| `cursor-agent` | existing Cursor install or conditional mise stub | preserve Cursor’s own installer when present |

The same setup installs non-agent developer helpers such as `gh`, Playwright,
`ghui`, `hunk`, and `hey`. They share the lazy-stub mechanism but are not
themselves AI agents.

To add another lazy command, the generic contract is:

```text
<namespace> mise-install <package> [command-name [binary-name]]
```

The command name is validated before the wrapper path is created: no slash,
leading dot, leading dash, or control character. Package and binary values are
quoted into the wrapper. The wrapper is a regular file under the user’s local
bin directory.

## Default agent lifecycle

The selected default is stored as one line in:

```text
~/.config/omarchy/defaults/agent
```

There is intentionally no default on a fresh installation. The first-run hook
shows a one-time notification that opens the default-agent menu. Selection
normalizes aliases (`claude-code` to `claude`, `open-code` to `opencode`, and
similar names), installs the selected agent if necessary, writes the canonical
name, and launches it.

The agent chooser maps the UI to these canonical ids:

```text
Pi              -> pi
Oh My Pi        -> omp
OpenCode        -> opencode
Ori             -> ori
Claude Code     -> claude
Codex           -> codex
Grok            -> grok
OpenClaw        -> openclaw
Antigravity     -> agy
Hermes          -> hermes
GitHub Copilot  -> copilot
Crush           -> crush
Cursor CLI      -> cursor-agent
Muse Code       -> muse
```

`omarchy-agent` has two launch modes:

- `--inline` replaces the current terminal process with the agent;
- the default mode launches a TUI terminal with app id
  `org.omarchy.agent`.

If it is launched from exactly `$HOME` and `$HOME/Work` exists, it changes into
`$HOME/Work` before launching. This avoids agents repeatedly refusing to trust
the home directory. `--pick` opens the chooser when no default has been set;
without it the command exits with an instruction to select one.

The provider-specific “do not stop and ask” arguments are part of the contract:

| Default id | Launch argument shape |
|---|---|
| `opencode` | `opencode --auto` |
| `agy` | `agy --dangerously-skip-permissions` |
| `copilot` | `copilot --allow-all` |
| `crush` | `crush --yolo`, or `crush run <prompt>` for a prompted run |
| `claude` | `claude --permission-mode auto` |
| `grok` | `grok --permission-mode bypassPermissions` |
| `openclaw` | platform launcher with `--tui`, attaching to its gateway |
| `codex` | `codex --approve-for-me` |
| `cursor-agent` | `cursor-agent --yolo --trust`; prompted launches append `agent -- <prompt>` |
| `hermes` | `hermes --yolo`; prompted launch uses `hermes chat --yolo --tui --query=...` with `HERMES_SESSION_SOURCE` removed |
| `muse` | `muse --approval-mode never` |
| `omp` | `omp --auto-approve` |
| `ori` | `ori code`, with interactive prompt flags when a prompt is supplied |
| `pi` | `pi`, with the prompt as its next argument |

`omarchy agent prompt <words...>` joins the words with spaces and passes one
prompt through the same launcher. It is deliberately a separate subcommand so
a bare agent prompt cannot shadow the agent group’s own commands.

## Desktop and local-model AI applications

The install menu is a catalog of optional applications; presence disables an
install row and absence enables it. The source currently offers:

| Application | Installer owner | Removal/data policy |
|---|---|---|
| ChatGPT Desktop | package `openai-codex-desktop`; opens `/usr/bin/chatgpt` | package plus `~/.config/Codex` and `~/.cache/Codex` |
| Dictation | optional `voxtype-bin` plus `wtype` | separate lifecycle; see capture document |
| Grok Bot | package `grok-bot` | package plus Grok Bot-specific config; CLI `~/.grok` survives |
| Hermes Desktop | package `hermes-desktop` | app-owned runtime is removed; chats/memories/skills/settings are kept unless explicitly confirmed |
| LM Studio | package `lmstudio-bin` | package and app/model locations are removed by its removal flow |
| Ollama | hardware-selected `ollama`, `ollama-cuda`, `ollama-rocm`, or `ollama-vulkan` | service, package, `/var/lib/ollama`, and `~/.ollama` are removed |
| OpenClaw | package `openclaw` plus local Control UI web app | gateway units/app launcher are removed; `~/.openclaw` is kept unless confirmed |
| Perplexity | package `perplexity` | runtime caches removed; logins/vault/device identity are kept unless confirmed |
| T3 Code | package `t3code-bin` | only T3-specific config/workspaces are removed |

### Hermes single-runtime rule

Hermes Desktop provisions its own commit-matched runtime under
`~/.hermes`. The terminal CLI and default agent must use that runtime whenever
the desktop package owns Hermes. The dedicated installer:

- uses Python `3.13` for the mise/pipx CLI path;
- writes a marked wrapper so it can distinguish its own install from a user’s
  foreign `hermes` command;
- refuses to replace a foreign wrapper;
- removes the separate mise CLI when Hermes Desktop is installed;
- waits up to 30 minutes for the desktop bootstrap marker when a theme or
  desktop install needs the runtime to be ready.

The desktop installer runs a user systemd job to apply the current theme after
the app’s first-run runtime becomes available. Removing the app removes its
runtime and Omarchy-owned wrapper, but asks separately before deleting the
user’s chats, memories, skills, connections, and tokens.

### OpenClaw gateway rule

OpenClaw’s desktop experience is a Control UI web app backed by a local gateway.
The launcher checks `openclaw dashboard --json` with a 10-second budget. If the
gateway is enabled but down it tries `openclaw gateway start`; otherwise it uses
`openclaw gateway install --force` with a 120-second budget, then polls for up to
30 seconds. The UI URL is loopback-only and passed to the web-app launcher.

The TUI attaches to the gateway with `openclaw tui`; it does not run the
embedded `openclaw chat` path. Onboarding runs in a terminal with
`openclaw onboard --flow quickstart --install-daemon --skip-ui`, watches for the
service’s own main PID to answer on its port, and stops the wizard after a
3-second settle period. A gateway that will not stop blocks package removal so
no live process is left running against deleted code.

## Usage dashboard and collector contract

The AI bar widget is a display/controller, not the source of usage truth. Its
data path is:

```text
collector executable
  -> one JSON record per provider
  -> atomic rename into
     ~/.local/state/omarchy/agents/usage/<provider>.json
  -> Main.qml discovers *.json and FileView watches each record
  -> Panel.qml renders only providers with actual data
```

`omarchy-agent-usage-update` discovers every executable
`omarchy-agent-usage-*` under the runtime `bin/` directory except itself,
supports `--force`, `--limits-only`, `--except <id>`, or explicit provider ids,
runs selected collectors concurrently, rejects empty/non-JSON output, writes a
unique temporary file, and renames it into place. A failed collector makes the
overall status nonzero but does not invalidate successfully written records.

The common record shape is:

```json
{
  "schemaVersion": 1,
  "id": "provider-id",
  "name": "Provider name",
  "updatedAt": "ISO-8601 timestamp",
  "ready": true,
  "hasLocalStats": true,
  "hasPromptStats": true,
  "scope": "device",
  "tierLabel": "Plan",
  "limits": [
    { "label": "5h window", "percent": 0.25, "resetsAt": "ISO-8601" }
  ],
  "todayPrompts": 0,
  "todaySessions": 0,
  "todayTotalTokens": 0,
  "todayTokensByModel": {},
  "recentDays": [{ "date": "YYYY-MM-DD", "messageCount": 0 }],
  "totalPrompts": 0,
  "totalSessions": 0,
  "activeDays": 0,
  "activeDates": [],
  "modelUsage": {}
}
```

Token buckets contain `inputTokens`, `outputTokens`,
`cacheReadInputTokens`, and `cacheCreationInputTokens`. A prepaid provider may
instead provide `balance` with `remaining`, `funded`, `spent`, `currency`, and
`estimated`. A collector may set `usageStatusText`, `authHelpText`, or
`retryAdvised` without making the panel crash.

### Refresh and visibility

- default refresh interval: 900 seconds;
- configured interval is clamped to at least 30 seconds;
- timer starts immediately and repeats;
- opening the panel asks for a fresh limits probe while reusing local scans;
- explicit refresh uses `--force`;
- concurrent update requests collapse into one queued rerun, with `force`
  taking precedence;
- a `retryAdvised` record schedules one provider-only retry after 30 seconds;
- records are rescanned after each collector process exits;
- a provider is shown only when enabled and it has limits, balance, prompts,
  sessions, active days, or other actual usage data;
- no data means the complete bar module is invisible, not a dim empty icon;
- multiple providers add a switch row; one provider has no switch row.

The panel is a 380-unit fitted-width dashboard with a 640-unit fitted-height
cap, both passed through the shared style scale. It uses a 160 ms OutCubic
meter-width animation. Daily and model rows use a 4-unit minimum track and a
14% control-height track thickness; labels and token values reserve 52-unit
columns. These are style units, so the base style scale in
[05-ui-kit-and-measurements.md](05-ui-kit-and-measurements.md) still applies.

### Provider-specific source behavior

| Provider | Local data | Authoritative limits/balance |
|---|---|---|
| Claude | `~/.claude/projects` JSONL; fallback `stats-cache.json` and `history.jsonl`; also Pi/Oh My Pi and OpenCode Anthropic sessions | OAuth usage endpoint; `CLAUDE_CONFIG_DIR` may relocate the home |
| Codex | native `CODEX_HOME/sessions` and archived sessions; Pi/Oh My Pi/OpenCode OpenAI sessions | Codex app-server RPC: `initialize`, `account/read`, `account/rateLimits/read` |
| Fireworks | billing API grouped by day/model over the last 30 days | live balance when permitted, otherwise configured funding minus rated costs; `scope: account` |

Claude’s limits probe is cached for 15 seconds and advises a retry after
transport failure. Codex local scans use a 20-second reuse window for concurrent
deduplication and a 900-second reuse window for limits-only calls. Fireworks
uses 15-second HTTP request timeouts and follows up to 20 billing pages. These
budgets are part of the collector behavior.

Optional cross-device aggregation is configured inline on the agent widget:

```text
syncMode       Off | On
syncDir        directory, expanded from ~, $HOME/, relative-to-home
syncFileName   sanitized basename, default <device>.json, max 100 chars
syncDeviceId   sanitized id, default hostname/device, max 80 chars
```

When enabled, the shell atomically writes this device’s snapshot, scans every
JSON snapshot in the directory, and merges them. Device-scoped counts sum;
account-scoped counts take the maximum to avoid double counting the same API
truth. Active dates are unioned. Rate limits and balances never merge across
devices. A bad snapshot is ignored and the status is kept separate from the
local provider record.

## Agent skills and system tailoring

Every directory under `<root>/default/agents/skills/` is linked into:

```text
~/.agents/skills/<name>
~/.claude/skills/<name>
~/.codex/skills/<name>
~/.pi/agent/skills/<name>
~/.gemini/config/skills/<name>
~/.hermes/skills/<name>
~/.hermes/profiles/*/skills/<name>   # existing profiles only
```

The links point to the active `OMARCHY_PATH`, so a development checkout can
replace the packaged source. The shipped general skill teaches agents how to
tailor the compositor, shell, bar, themes, and workstation; the crash skill
teaches fact-first crash diagnosis. The skills are instructions for external
agents, not code executed by the shell host.

## Crash-to-agent workflow

The user crash watcher follows the systemd-coredump stream. When enabled and a
new process crash is detected, it sends a critical notification whose click
target runs the crash command with the process identity as a discrete argument.
The default agent receives the diagnosis skill and gathers coredump facts before
suggesting a fix or report. Notifications are deduplicated per process/minute.

The watcher is enabled as a user service after `graphical-session.target`,
restarts after 5 seconds, and is disabled persistently by a state toggle rather
than by deleting the unit. Per-program muting stores a narrow name/path rule;
muting hides notices, not crashes or coredumps.

## Theme relationship

Theme changes retint the AI surfaces that have an explicit integration:

- Claude receives generated `claude.json` as `~/.claude/themes/omarchy.json`
  and may be activated with `custom:omarchy`;
- Pi receives generated `pi.json` as `omarchy-system`;
- Hermes receives generated `hermes.yaml` as the `omarchy` skin in its home and
  existing profiles, unless the user chose another skin;
- OpenCode is restarted with `SIGUSR2` so its system theme/config reloads;
- the agents panel itself follows shell colors and uses optional provider SVG
  marks, including `-light.svg` variants.

There is no Codex-specific generated color-theme file in the audited source.
Do not invent one when reproducing the reference.

## AI acceptance checklist

A replica has captured the AI-first essence only when:

1. no default agent is silently selected on first boot;
2. all shipped agent names resolve through one default-agent dispatch, with mise
   lazy stubs where applicable and special ownership for Hermes/OpenClaw;
3. special runtime ownership for Hermes and OpenClaw is preserved;
4. default-agent prompts use provider-specific launch flags and safe argv;
5. usage is a file-backed collector contract, not provider logic in QML;
6. new collectors appear without editing the agents panel;
7. local stats, remote limits, account scope, and device scope remain separate;
8. the bar icon hides until a provider has real data;
9. skills are linked into each supported harness root;
10. crash notifications can hand evidence to the default agent;
11. dictation remains an optional external daemon integration;
12. credential/data removal is explicit and preserves user data by default;
13. failures and network/API timeouts leave the dashboard usable;
14. the host never claims that same-user agent processes are sandboxed.

## Source cross-check

```text
manual/17-ai.md
install/user/mise.sh
install/user/mise-work.sh
install/user/first-run/setup-agent.hook
bin/omarchy-mise-install
bin/omarchy-default-agent
bin/omarchy-agent
bin/omarchy-agent-prompt
bin/omarchy-agent-usage-update
bin/omarchy-agent-usage-claude
bin/omarchy-agent-usage-codex
bin/omarchy-agent-usage-fireworks
shell/plugins/agents/manifest.json
shell/plugins/agents/Agent.qml
shell/plugins/agents/Main.qml
shell/plugins/agents/Panel.qml
shell/plugins/agents/README.md
bin/omarchy-install-ai-chatgpt
bin/omarchy-install-ai-hermes
bin/omarchy-install-ai-openclaw
bin/omarchy-launch-openclaw
bin/omarchy-openclaw-onboard
bin/omarchy-install-hermes-cli
bin/omarchy-install-openclaw-cli
bin/omarchy-remove-ai-*
default/agents/skills/
default/omarchy/omarchy-menu.jsonc
default/hypr/bindings/applications.lua
default/hypr/bindings/utilities.lua
default/hypr/bindings/voxtype.lua
default/systemd/user/omarchy-crash-watch.service
```

The source demonstrates an integrated AI operating model, but not a built-in
model or provider service. External agent authentication, cloud responses,
desktop-app bootstrap, and API availability remain runtime concerns.
