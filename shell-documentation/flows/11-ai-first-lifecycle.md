# AI-first platform lifecycle

This document turns the AI architecture into end-to-end flows. The reference
does not put a language model inside the shell host. Its AI-first behavior is
the integration of external agent command lines, lazy installation, one
default-agent route, usage collectors, shared skills, optional desktop/local
model runtimes, crash diagnosis, and dictation.

The implementation must preserve that boundary. Adding an in-shell chat/model
runtime would be an architectural change, not a faithful implementation.

## Source units

~~~text
manual/17-ai.md
install/user/mise.sh
install/user/mise-work.sh
install/user/first-run/setup-agent.hook
bin/omarchy-mise-install
bin/omarchy-default-agent
bin/omarchy-agent
bin/omarchy-agent-prompt
bin/omarchy-agent-usage-update
bin/omarchy-agent-usage-*
shell/plugins/agents/Agent.qml
shell/plugins/agents/Main.qml
shell/plugins/agents/Panel.qml
install/optional/*
default/agents/skills/
default/systemd/user/omarchy-crash-watch.service
~~~

## End-to-end surface map

~~~text
fresh user finalization
    -> lazy agent wrappers and helper wrappers
    -> default-agent file is absent
    -> first-run notification opens agent chooser
    -> selected canonical id is installed and persisted
    -> omarchy-agent launches the selected provider

ongoing session
    -> usage collector commands write provider JSON atomically
    -> agents Main.qml discovers/watches records
    -> agents bar icon appears only with real provider data
    -> agents panel refreshes limits and renders normalized windows/models

agent crash
    -> coredump watcher observes new crash
    -> critical notification supplies process identity
    -> user opens diagnosis through the selected/default agent

optional voice input
    -> Voxtype daemon records/transcribes
    -> state follower drives bar indicator
    -> focused-input injection is delegated to Voxtype
~~~

## Lazy agent installation

### Wrapper creation

User finalization calls the mise installer for each selected command. The
generic wrapper contract is:

~~~text
validate command name
    -> reject slash, leading dot, leading dash, or control character
    -> create regular file under HOME/.local/bin
    -> wrapper exports MISE_MINIMUM_RELEASE_AGE=0
    -> wrapper runs mise use -g --quiet <package>
    -> wrapper execs mise x <package> -- <binary> "$@"
~~~

The first invocation may resolve/install the package; subsequent invocations
reuse the mise-managed package. The no-release-age setting is deliberate for a
user-requested execution. An update path also permits immediate mise updates.

Package and command values are quoted into the wrapper. The wrapper is not a
shell alias and is not an unchecked curl-pipe installer.

### Command-to-owner map

The shipped command routes are:

| Command | Owner/resolve route |
|---|---|
| claude | mise package claude |
| codex | mise package codex |
| opencode | mise package opencode |
| agy | antigravity-cli through mise |
| copilot | mise package copilot |
| crush | mise package crush |
| grok | npm package through mise |
| pi | mise package pi |
| omp | GitHub package through mise |
| ori | OpenRouter release package through mise |
| hermes | dedicated pinned installer |
| muse | mise-backed launcher with its own native binary path |
| cursor-agent | existing Cursor installation or conditional mise stub |

The special Hermes, Muse, Cursor, and OpenClaw ownership rules must not be
flattened into one generic package path.

## Default-agent selection

### First-run trigger

The default selection file is:

~~~text
HOME/.config/omarchy/defaults/agent
~~~

It is intentionally absent on a fresh install. The first-run hook sends a
one-time notification whose action opens the agent chooser. No provider is
silently selected because it happened to be installed.

### Selection and launch

The chooser maps display labels and aliases to canonical ids, ensures the
selected provider is installed, writes one canonical line to the selection
file, and launches the provider. The canonical set includes:

~~~text
pi, omp, opencode, ori, claude, codex, grok, openclaw, agy,
hermes, copilot, crush, cursor-agent, muse
~~~

omarchy-agent without a stored default tells the user to select one or opens
the chooser when --pick is supplied. omarchy-agent --inline replaces the
current terminal process. The normal mode starts a TUI terminal with app id
org.omarchy.agent.

When launched from exactly HOME and HOME/Work exists, the launcher changes to
HOME/Work before starting the agent. This directory rule is part of the launch
flow, not a generic current-directory convenience.

omarchy-agent-prompt joins the supplied words with spaces and sends one prompt
through the same provider route. It is a separate subcommand.

### Provider launch arguments

The launcher must preserve provider-specific argv:

| Canonical id | Launch shape |
|---|---|
| opencode | opencode --auto |
| agy | agy --dangerously-skip-permissions |
| copilot | copilot --allow-all |
| crush | crush --yolo; prompted run uses crush run prompt |
| claude | claude --permission-mode auto |
| grok | grok --permission-mode bypassPermissions |
| openclaw | platform launcher with --tui, attached to gateway |
| codex | codex --approve-for-me |
| cursor-agent | cursor-agent --yolo --trust; prompt appends agent -- prompt |
| hermes | hermes --yolo; prompt uses hermes chat --yolo --tui --query and removes HERMES_SESSION_SOURCE |
| muse | muse --approval-mode never |
| omp | omp --auto-approve |
| ori | ori code with interactive prompt flags when needed |
| pi | pi with the prompt as its next argument |

Arguments that alter approval behavior are source-defined. A shell
implementation must not replace them with a universal argument or concatenate
user prompt text into an unsafe shell command.

## Agent usage lifecycle

### Collector discovery

The update command discovers executable omarchy-agent-usage-* files under the
runtime bin directory, excluding itself. It accepts:

~~~text
no selector      -> all collectors
--force          -> force refresh
--limits-only    -> provider limits path
--except id      -> all except selected id
provider ids     -> only those collectors
~~~

Selected collectors run concurrently. An empty or invalid JSON result fails
that collector but cannot invalidate a successfully written provider record.

### Atomic record path

Each collector produces a provider record. The updater:

1. validates the output as non-empty JSON;
2. creates a unique temporary path in the usage directory;
3. writes the record;
4. renames it atomically to provider.json;
5. returns failure if a selected collector failed.

The file-backed handoff is the API between the external provider logic and the
shell UI. A new provider collector can appear without editing Panel.qml.

The common record includes schemaVersion 1, id, name, updatedAt, ready,
local/prompt flags, scope, tier, limits, prompts/sessions/tokens, recent days,
active dates, and model usage. Limits may contain label, percent, and reset
time. A prepaid provider may provide a balance record instead.

### Main.qml discovery

The agents Main component watches the usage directory and each provider file.
It normalizes provider records, drops invalid/unready records, and exposes
enabled providers to the panel. Provider-specific local scans and remote limit
requests remain outside Panel.qml.

The default refresh interval is 900 seconds and the configured interval is
clamped to at least 30 seconds. Opening the panel requests a fresh limits
refresh. Explicit refresh uses force. Concurrent update requests coalesce into
one queued run, with force taking precedence. A retry-advised provider gets one
provider-only retry after 30 seconds.

### Agents bar and panel

The bar widget is visible only when at least one enabled provider has actual
limits, balance, prompts, sessions, active days, or equivalent data. An empty
provider set renders a hidden bar item, not an empty warning icon.

Button branches:

~~~text
left click   -> Panel.toggle()
right click  -> launch omarchy-agent --pick; close panel
middle click -> select next provider; keep panel state
~~~

On panel open:

~~~text
clear cursor
refresh now timestamp
scroll to top
usage.refreshLimits()
defer focus to KeyboardPanel catcher
~~~

The panel uses fitted width Style.space(380) and fitted height capped at
Style.space(640). Its shared panel keyboard path is:

~~~text
left/right or h/l -> provider selection
up/down or j/k   -> scroll by Style.space(56)
Enter/Space      -> forced refresh
r/R              -> forced refresh
Tab              -> neighboring bar panel
Escape            -> panel close
~~~

Selection is keyed by provider id. A provider arriving or disappearing during
an open panel must not silently change the provider being read when the
selected id still exists.

## Provider-specific data boundaries

The implementation must retain these data ownership boundaries:

| Provider | Local scan | Remote/account source |
|---|---|---|
| Claude | Claude projects JSONL, stats cache/history, and supported external session sources | OAuth usage endpoint |
| Codex | CODEX_HOME sessions and archived sessions, plus supported external sessions | app-server account/rate-limits RPC |
| Fireworks | local prompt/session data where present | billing pages and balance/funding data |

Account-scoped counts are not summed across devices during aggregation; they
take the maximum to avoid double counting. Device-scoped counts sum. Active
dates are unioned. Limits and balances never merge across devices.

## Optional cross-device aggregation

When the agent entry enables sync:

~~~text
syncMode       = Off or On
syncDir        = expanded and validated directory
syncFileName   = sanitized basename, default hostname.json
syncDeviceId   = sanitized stable device id, default hostname
~~~

The local usage snapshot is atomically written, all JSON snapshots are
scanned, and device/account rules merge them. A malformed snapshot is ignored
without destroying the local provider record. Sync status stays separate from
the local provider result.

## Desktop and local-model app lifecycles

The optional application menu is presence-aware: an installed application
disables its install row, and absence enables it. The important end-to-end
ownership rules are:

### Hermes

Hermes Desktop owns a commit-matched runtime under HOME/.hermes. The terminal
CLI and default agent use that runtime when the desktop package is present.
The dedicated installer uses Python 3.13 for its mise/pipx path, writes a
marked wrapper, refuses to replace a foreign wrapper, removes a separate mise
CLI when Desktop owns Hermes, and waits up to 30 minutes for the bootstrap
marker when required.

Removal removes the app-owned runtime and wrapper but asks separately before
deleting chats, memories, skills, connections, or tokens.

### OpenClaw

OpenClaw Desktop is a local Control UI backed by a gateway:

~~~text
launch dashboard
    -> query dashboard JSON with 10 s budget
    -> if enabled/down: start gateway
    -> otherwise install gateway with 120 s budget
    -> poll readiness for up to 30 s
    -> launch loopback web app
~~~

The TUI attaches with openclaw tui. Onboarding runs through a terminal command,
watches the service's main PID/port, and stops after a 3-second settle period.
Removal is blocked while a gateway remains live against code being removed.

### Other optional apps

ChatGPT, Grok Bot, LM Studio, Ollama, Perplexity, and T3 Code retain their
source-defined package/config/data ownership. The removal flow must preserve
user chats/logins/configuration when the source says it does and remove
service/model data only when the source explicitly owns it.

## Shared agent skills

Every shipped skill directory is linked into each supported harness:

~~~text
HOME/.agents/skills/<name>
HOME/.claude/skills/<name>
HOME/.codex/skills/<name>
HOME/.pi/agent/skills/<name>
HOME/.gemini/config/skills/<name>
HOME/.hermes/skills/<name>
HOME/.hermes/profiles/*/skills/<name> for existing profiles
~~~

Links point to the active repository path. The general workstation skill and
crash skill are instructions consumed by external agents; they are not
executed by the shell host.

## Crash-to-agent lifecycle

The user crash watcher runs after graphical-session.target and restarts after
5 seconds. When enabled it observes the systemd-coredump stream, deduplicates
by process/minute, and sends a critical notification. Clicking the notification
passes the process identity as a discrete argument to the crash command, which
loads the diagnosis skill and gathers coredump facts before proposing a fix.

Muting a program stores a narrow name/path rule and suppresses notices only. It
does not delete coredumps or stop crash collection.

## Dictation boundary

Voxtype is an optional daemon, not an agent provider and not an embedded model.
Its installation, status follower, indicator, configuration, and removal are
specified in 14-capture-recording-and-dictation.md and
flows/09-theme-capture-and-platform.md. The AI lifecycle must only consume the
reported state and invoke external Voxtype commands.

## Acceptance checks

1. Start with no default-agent file. Verify the notification/chooser path,
   canonical id write, install, and first launch.
2. Exercise inline/default/prompted launches for every provider-specific
   argument family and verify argv boundaries.
3. Add a new usage collector without editing the panel and verify discovery,
   atomic record replacement, invalid-output isolation, and retry behavior.
4. Open the agents panel with zero, one, and several providers; remove the
   selected provider during the open state and verify stable selection/fallback.
5. Test device and account aggregation with duplicate snapshots and malformed
   files.
6. Exercise Hermes ownership conflict, OpenClaw gateway-down, and removal
   while a gateway is live.
7. Trigger a crash notification, click it, and verify process identity and
   diagnosis skill handoff.
8. Install/remove dictation separately and verify the shell remains usable
   when Voxtype is absent.

