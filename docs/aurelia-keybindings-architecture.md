# Aurelia Keybindings Architecture Specification

This document specifies the architecture, lifecycle model, failure isolation boundaries, and design system contract for **Aurelia Keybindings** within the Fedora Hyprland Workstation.

---

## 1. Product Identity and Terminology

| Concept | Identifier / Label | Scope |
| :--- | :--- | :--- |
| **Internal Product Name** | `Aurelia Keybindings` | Engineering documentation, git commits, code comments |
| **User-Facing App Name** | `Keybindings` | Desktop entries (`Name=Keybindings`), window titles, UI header |
| **Generic Descriptor** | `Keyboard Shortcuts` | Desktop entry (`GenericName=Keyboard Shortcuts`) |
| **Primary Backend Binary** | `bin/workstation-keybindings` | System installation path: `/usr/local/bin/workstation-keybindings` |
| **Compatibility Wrapper** | `bin/workstation-hotkeys` | 25-line thin forwarding wrapper delegating to `workstation-keybindings` |
| **Component Registry ID** | `desktop.keybindings.aurelia` | Primary installer component (`desktop.hotkeys.aurelia` is compatibility alias) |
| **QML Component Directory** | `dotfiles/aurelia/components/keybindings/` | Source tree for `KeybindingsWindow.qml`, `KeybindingsModel.qml`, `KeybindingRow.qml` |
| **IPC Target** | `keybindings` | Quickshell IPC target (`hotkeys` preserved as forwarding alias) |

---

## 2. Failure Domains & Isolation Model

```mermaid
graph TD
    subgraph "Desktop Session Layer (Fail-Safe)"
        Greetd["greetd / noctalia-greeter"]
        Hyprland["Hyprland Wayland Compositor"]
        Activation["Graphical Session Activation"]
    end

    subgraph "Aurelia Process Boundary (Sandboxed)"
        Quickshell["Single Quickshell Process (--path dotfiles/aurelia)"]
        IPC["IPC Endpoint: keybindings"]
        Model["KeybindingsModel.qml (In-Memory State & Concurrency Guards)"]
        UI["KeybindingsWindow.qml (Layer-Shell Surface)"]
    end

    subgraph "Backend Execution Boundary (Double-Fork)"
        Backend["/usr/local/bin/workstation-keybindings"]
        LuaEngine["effective_bindings.lua / keybindings_manifest.lua"]
        Launcher["Double-Fork Grandchild (PPID=1 / init)"]
    end

    Hyprland -->|SUPER+K Dispatch| Backend
    Backend -->|IPC toggle| IPC
    IPC --> UI
    UI --> Model
    Model -->|Structured argv / run| Backend
    Backend -->|Detached Launch| Launcher
    Backend -.->|Non-blocking on failure| Hyprland

    style Activation fill:#2a273f,stroke:#9ccfd8,stroke-width:2px;
    style Quickshell fill:#232136,stroke:#f6c177,stroke-width:2px;
    style Launcher fill:#1f1d2e,stroke:#ea9a97,stroke-width:2px;
```

### 2.1 Component Level (UI & Model)
- **Safe JSON Parsing**: All backend JSON responses are parsed within `try { ... } catch (e)` blocks in `KeybindingsModel.qml`. Malformed output triggers a structured inline error state without crashing the Quickshell engine.
- **Concurrency Guards**: Dedicated boolean guards (`isReloading`, `isExecuting`, `isMutating`) prevent re-entrant dispatch. Concurrent user requests while an asynchronous operation is pending are safely dropped with warning logs.
- **Pure Native Wayland Layer-Shell**: The UI operates exclusively within the Wayland layer-shell protocol. No terminal emulators (`foot`, `kitty`, `xterm`) are ever spawned for UI presentation, key capture, or error reporting.

### 2.2 Process Level (Backend Execution)
- **Double-Fork Process Launch**: Action execution through `workstation-keybindings run <action_id>` uses a POSIX double-fork pattern:
  1. The parent orchestrator forks a launcher subshell.
  2. The launcher subshell invokes `( "$@" ) >/dev/null 2>&1 &` to spawn the target application and immediately terminates with status 0.
  3. The target application (grandchild) is instantly reparented to `systemd` / `init` (`PPID=1`).
  4. Zero intermediate wrapper shells or file descriptors are retained. No temporary files are created during execution.
- **Strict Structured `argv` Dispatch**: Commands are resolved from canonical manifests into structured argument arrays (`command_argv`). Command lines are never evaluated with `eval` or passed through arbitrary `sh -c` interpreters.

### 2.3 Desktop Session Level (Graphical Activation Invariance)
- **Non-Blocking Classification**: In accordance with `AGENTS.md` Principle 15, Keybindings failures are strictly classified as `WORKSTATION-REQUIRED-BUT-NONBLOCKING` or `OPTIONAL`.
- **Zero Impact on Display Manager**: A complete failure of Quickshell, Keybindings QML, or backend binaries records diagnostic entries but **never** sets `ACTIVATION_BLOCKED=1` or prevents `greetd` from activating graphical login.

---

## 3. Resident vs. Lazy Process Lifecycle

Aurelia Keybindings implements a hybrid **resident surface with lazy activation** model to satisfy competing requirements for responsiveness and resource conservation:

1. **Sub-100ms Warm Toggle**:
   - The Wayland layer-shell window remains resident in memory within the primary Aurelia Quickshell daemon.
   - When the user presses `Super+K`, the backend issues a non-mutating `ping` check to the Quickshell socket. Upon confirmation of socket readiness, it delivers an IPC message to target `keybindings` with argument `toggle`.
   - In production VM benchmarks, end-to-end warm opening latency averages **76.8ms** (min=67.8ms, max=82.3ms, comfortably within the <= 100ms budget). Direct `qs ipc ping` takes ~27.6ms and `qs ipc toggle` takes ~36.1ms; Lua resolution and JSON serialization require just 0.196ms.

2. **Zero Idle CPU Overhead**:
   - When the window is hidden (`visible: false`), **all timers and animations are strictly disabled**.
   - No background threads poll files or sockets.
   - In-memory search filtering executes only in response to explicit `textChanged` events from the search input.

3. **Bounded Cold Launch**:
   - If the Aurelia daemon is not currently active, the backend initiates cold launch using `quickshell --no-duplicate --daemonize --path <aurelia_dir>`.
   - Measured cold startup latency is **~171ms–177ms** (well within the <= 500ms budget).
   - The backend polls for daemon readiness using non-mutating `quickshell ipc --path <dir> target ping` probes over a bounded budget (~2000ms max, 40 iterations at 50ms intervals).
   - Once readiness is confirmed, a single `toggle` IPC command is dispatched. If the readiness budget expires, the backend fails closed with a clear diagnostic log and returns exit code 1 without spawning arbitrary fallback windows.

---

## 4. Inline Keybinding Capture State Machine & Interaction Model

Keybinding modification is handled entirely inline within the native layer-shell interface without opening external terminal windows or secondary dialogs.

```mermaid
stateDiagram-v2
    [*] --> idle

    idle --> entering_capture : 's' pressed (initiatingKey recorded)
    idle --> capture_armed : Click 'Set' / Start Capture without key
    entering_capture --> capture_armed : initiatingKey released (leak protection)
    capture_armed --> idle : Esc (Cancel Capture)
    capture_armed --> idle : Backspace / Delete (Unset Shortcut)
    capture_armed --> validating : Valid Combination Pressed
    capture_armed --> capture_armed : Standalone Modifier (Super/Ctrl/Alt/Shift)

    idle --> validating : 'u' pressed / Unset Shortcut (sets 'none')

    validating --> idle : Valid & Committed Atomically (Success feedback)
    validating --> conflict : Conflict Detected (Existing Action)
    validating --> capture_armed : Policy Rejection / Error (Armed for retry)

    conflict --> idle : Enter (Force Reassign) or Esc (Cancel)
```

### 4.1 State Definitions & Invariants
- **`idle`**: Normal palette navigation state.
  - Arrow keys navigate rows; typing filters search; Return executes runnable applications or navigates sub-views.
  - Single-key actions in list view:
    - **`s`**: Initiate capture on the selected action (or `Alt+s`).
    - **`u`**: Unset the selected action (or `Alt+u`).
    - **`a`**: Toggle between action views and the Add Action picker (or `Alt+a`).
  - In `searchInput`, typing characters `s`, `u`, `a` types into the search query normally, while `Alt+s`, `Alt+u`, and `Alt+a` trigger actions without losing input focus.
  - All UI badges and footer hints strictly display lowercase **`s`**, **`u`**, and **`a`** (preventing user confusion with Shift-modified shortcuts).
- **`entering_capture`**: Initiating trigger key leak protection state.
  - When the user presses `s` to configure a binding, `initiatingKey` records the keycode.
  - All intermediate keypresses are swallowed until `handleRecordingKeyRelease` detects the initiating key release.
  - Prevents the initiating key from inadvertently being registered as part of the candidate combination.
- **`capture_armed`**: Live shortcut recording state.
  - `ShortcutInhibitor` is dynamically enabled, preventing Hyprland compositor global bindings from intercepting keystrokes.
  - `WlrLayershell.keyboardFocus` is dynamically elevated to `WlrKeyboardFocus.Exclusive`.
  - Standalone modifiers (Super, Ctrl, Alt, Shift) update the live display while remaining armed.
  - Standalone Backspace or Delete immediately unsets the shortcut and returns to idle.
  - `Esc` unconditionally cancels capture, returning to `idle` with zero mutation and restoring `OnDemand` focus.
- **`validating`**: Policy validation state.
  - Evaluates candidate key against centralized workstation shortcut policy (`effective_bindings.validate_shortcut_policy`).
  - Rejects naked printable keys (`s`, `a`, `1`, `space`), Shift+printable combinations, and bare Esc.
  - Reorders modifiers into canonical sorting: `SUPER + CTRL + ALT + SHIFT + KEY`.
- **`conflict`**: Conflict resolution state.
  - If candidate shortcut is already owned by another action, the conflicting action name is displayed in warning amber.
  - Pressing `Enter` confirms force reassignment (`--force`), atomically unbinding the conflicting action and binding the new action in a single transactional write.
  - Pressing `Esc` cancels the operation with zero mutation.
- **`error`**: Error feedback state.
  - Informs the user of immutable system bindings, uneditable aggregate actions, or malformed combinations.
  - Remains armed for immediate retry or cancellation with `Esc`.

### 4.2 Fullscreen Layer-Shell & Outside-Click Dismissal
- **Window Surface Geometry**: `PanelWindow` configures full-screen transparent anchoring:
  ```qml
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  ```
- **Outside-Click Dismissal (`outsideDismissArea`)**:
  - A fullscreen transparent `MouseArea` lies underneath the centered surface card.
  - Clicking outside the 800x480 command palette frame immediately closes the window (`windowRoot.visible = false`).
  - If clicked during active key recording, it safely cancels capture (`cancelCapture()`) without abruptly closing the window.
- **Centered Surface Card (`surfaceCard`)**:
  - The visual command palette is centered within the parent surface (`anchors.centerIn: parent`) with explicit design token geometry: `width: Theme.paletteWidth` (800) and `height: Theme.paletteHeight` (480).
  - An internal click-absorbing `MouseArea` covers `surfaceCard`, preventing clicks inside the palette card from bubbling through to `outsideDismissArea`.

---

## 5. Aurelia Design System Foundation & Central Configuration

Aurelia Keybindings establishes a centralized, single-source-of-truth configuration architecture. All colors, window geometry, table column dimensions, typography, spacing, and animations are defined in `dotfiles/aurelia/theme.conf` and dynamically consumed through the `dotfiles/aurelia/theme/Theme.qml` singleton.

No QML component hardcodes hex colors or layout dimensions. Editing a single variable in `theme.conf` instantly reconfigures the entire component tree.

### 5.1 Central Configuration File (`theme.conf`)
Located at `~/.config/aurelia/theme.conf` (symlinked from `dotfiles/aurelia/theme.conf`):
- **Window Geometry**: `paletteWidth` (800), `paletteHeight` (480), `searchHeight` (40), `rowHeight` (42), `footerHeight` (34).
- **Table Column Layout**: `colShortcutWidth` (350 for balanced 50/50 split, or 280 for ~40/60 split), `colSeparatorWidth` (28), `rowSpacing` (3), `scrollBarWidth` (4).
- **Corner Radii & Borders**: `radiusSm` (4), `radiusMd` (8), `radiusLg` (12), `borderWidthDefault` (1), `borderWidthFocus` (2).
- **Spacing Scale**: Modular 4px scale (`spacingXs` = 4, `spacingSm` = 8, `spacingMd` = 12, `spacingLg` = 16, `spacingXl` = 20, `spacingXxl` = 24).
- **Typography**: `fontFamily` ("JetBrainsMono Nerd Font, Hack Nerd Font, monospace"), `fontSizeXs` (10) through `fontSizeXl` (18).
- **Motion**: `durationFast` (100ms), `durationNormal` (200ms).
- **Colors**: Base surfaces (`background`, `surface`, `selection`), active and inactive borders (`border`, `borderActive`), text hierarchy (`text`, `textSecondary`, `textMuted`, `textSubtle`), and semantic accents (`accent`, `accentAlt`, `gold`, `love`, `pine`, `foam`, `rose`, `iris`, `success`, `warning`, `error`).

### 5.2 Dynamic Singleton Resolver (`Theme.qml`)
- Resolves configuration via `AURELIA_THEME_CONF` or `~/.config/aurelia/theme.conf`.
- Provides safe, typed parsing helpers: `_getInt()`, `_getString()`, and `_getColor()` with alias fallback arrays (e.g. `active_border_color`, `active_border`, `border_active`).
- Defaults securely to the canonical Rosé Pine Moon palette when no custom configuration is provided.

### 5.3 Test Suite Isolation & Zero Desktop Spam
- Automated test suites export `WORKSTATION_TEST_MODE=1`.
- `bin/workstation-keybindings` provides `notify_user()` which suppresses `notify-send` desktop popups during automated test execution.
- Test logs are isolated to `/tmp/workstation-tests-${UID}` to prevent polluting user crash logs.

---

## 6. Observability & Resource Bounds

To prevent unconstrained resource growth on production workstations:

1. **Diagnostic Log Bounding**:
   - All backend operations log to `~/.local/state/workstation-keybindings/`.
   - Every log file (`keybindings.log`, `crashes.log`, `performance.log`) is monitored by `bound_logfile()`:
   - When a log file exceeds 2000 lines, it is atomically rotated via temporary file to retain the most recent 2000 lines.
2. **Performance Telemetry (`[PERF]`)**:
   - Critical milestones (cold start readiness, warm IPC roundtrip, JSON load and parse durations) are tagged with `[PERF]` and duration timestamps.
   - Operations exceeding warning thresholds (e.g. warm toggle > 100ms) emit `[PERF-WARN]` diagnostics.
3. **Structured Crash Logging**:
   - Unhandled backend failures and timeouts append to `crashes.log` with timestamp, operation context, exit code, and captured stderr.

---

## 7. Future Seams Architecture

### 7.1 Future AI Diagnostics Seam
A future local diagnostic bundle generator can integrate cleanly at the logging and telemetry boundary:
- **Local Sanitized Bundle**: A dedicated maintenance command (`workstation-keybindings diagnose`) can package bounded logs (`crashes.log`, `performance.log`), system package EVR, and Hyprland bind state into an encrypted local archive.
- **Privacy & User Consent**: The seam enforces strict privacy invariants: zero automatic network egress, zero exfiltration of user passwords or tokens, and explicit user confirmation before generating or presenting diagnostic bundles.
- **Vendor Agnosticism**: Diagnostics generation is decoupled from specific AI vendor APIs; bundles are emitted as standard local JSON/tar.gz artifacts.

### 7.2 Future Actual vs. Desired vs. Drift Seam
The keybinding system is architected to support bidirectional drift detection between declarative desired state and live compositor bindings:
- **Desired State**: Defined declaratively by `dotfiles/hypr/keybindings_manifest.lua` merged with user overrides `~/.config/hypr/keybindings_overrides.json`.
- **Actual State**: Queryable at runtime via `hyprctl binds -j`.
- **Reconciliation Engine**: The installer reconciler can detect discrepancies between declared binds and compositor state, providing non-destructive auditing and automated resynchronization on user command.

---

---

## 8. Universal Aurelia Component Contract

Aurelia Keybindings serves as the reference implementation for the **Universal Aurelia Component Contract** defined in [`docs/aurelia-shell-architecture.md`](file:///home/user/Projects/fedora-hyprland-workstation/docs/aurelia-shell-architecture.md).

Future components (e.g. Launcher, Status Bar, Notification Center) are **not** constrained to specific UI structures like `Window`/`Model`/`Row`, but must fulfill universal contract invariants:
1. **Conditional Activation**: Single-process ShellRoot hosting with independent conditional `Loader` controls. Disabled components consume 0 MB RAM and 0% CPU.
2. **Readiness Protocol**: Explicit IPC target exposing a non-mutating `ping(): bool` method. Probing before mutation; process existence is not readiness.
3. **Structured Execution & Process Detachment**: POSIX double-fork detachment reparenting to `init` (`PPID=1`); strict structured `argv` arrays with zero `eval` or shell interpretation.
4. **Design System Tokens**: Visual elements consume tokens exclusively from `Theme.qml` and `theme.conf`.
5. **Failure Isolation**: Component failures are non-blocking and decoupled from display manager activation (`greetd`).

---

## 9. Role-Based Action Resolution & Dynamic Application Intent

Workstation keybindings bind generic user intents to application roles rather than hardcoded commands:
- **Files Default (`file_manager`)**: `Super+E` dynamically launches the active default file manager (`nautilus` by default, or `thunar` if selected in `desktop.conf` or MIME defaults).
- **Terminal Default (`terminal`)**: `Super+Return` dynamically launches the active default terminal (`kitty` by default, or `foot` if selected).
- **Browser Default (`browser`)**: `Super+B` dynamically launches the active default browser (`chromium-browser` by default, or `firefox` if selected).
- **Direct Application Actions**: Concrete applications (`files.nautilus`, `files.thunar`, `terminal.kitty`, `terminal.foot`, `browser.chromium`, `browser.firefox`) exist as unbound actions in the manifest. Users can bind explicit shortcuts to specific applications without mutating or breaking role actions.
- **Zero Shortcut Mutation**: Switching application defaults updates the executed command dynamically at runtime without modifying keybinding declarations or user override files.

---

## 10. Application Registry, Action Registry & View Architecture

Aurelia Keybindings implements a clean three-tier separation of concerns across application discovery, action declaration, and shortcut configuration:

```mermaid
graph TD
    subgraph "Application Registry (Discovery)"
        XDG["XDG Data Dirs (~/.local/share, /usr/share)"]
        Parser["application_registry.lua (Safe Desktop Parser)"]
        AppsCLI["workstation-keybindings apps"]
        XDG --> Parser --> AppsCLI
    end

    subgraph "Action Registry (Identities & Metadata)"
        Manifest["keybindings_manifest.lua (Static System Actions)"]
        UserActions["~/.config/hypr/user_actions.json (User App Actions)"]
        ActionReg["Action Registry (app:<desktop_id>)"]
        Manifest --> ActionReg
        UserActions --> ActionReg
    end

    subgraph "Effective Bindings & Aurelia Shell UI"
        Overrides["~/.config/hypr/keybindings_overrides.json"]
        EffectiveEngine["effective_bindings.lua"]
        JSON["workstation-keybindings json"]
        UI["Aurelia Keybindings (Bound / Unbound / Add App)"]

        ActionReg --> EffectiveEngine
        Overrides --> EffectiveEngine
        EffectiveEngine --> JSON --> UI
    end
```

### 10.1 Application Registry (`dotfiles/hypr/application_registry.lua`)
- **Standards-Compliant Desktop Parsing**: Recursively scans standard XDG directories (`$XDG_DATA_HOME/applications`, `$XDG_DATA_DIRS/applications`) respecting user shadowing and `Hidden=true` masking.
- **Trusted Launcher Platform Delegation**: Delegates execution directly to trusted platform launcher (`gtk-launch`) with structured arguments, eliminating custom Exec tokenizers and shell interpolation.
- **In-Memory Cache**: Lazy process-lifetime cache with explicit invalidation/refresh prevents redundant filesystem operations while ensuring responsive CLI output (< 20ms).
- **Installed Applications Discovery**: Emitted via `workstation-keybindings apps` as structured JSON consumed on-demand by the UI.

### 10.2 Action Registry vs. Application Registry vs. Effective Bindings
- **Application Registry (`application_registry.lua`)**: Dynamically discovers launchable graphical desktop applications from standard XDG data directories. **Crucial Invariant**: Discovered applications do NOT automatically populate the Action Registry or Unbound actions. Discovery is strictly lazy and on-demand.
- **Action Registry**: Defines the universe of actions eligible for shortcut assignment. Composed strictly of:
  1. Curated core system actions (`keybindings_manifest.lua`).
  2. 20 expanded discrete workspace actions (`workspace_1`..`workspace_10` and `move_workspace_1`..`move_workspace_10`), generated ahead of effective binding resolution.
  3. Explicitly added user application actions (`type: "application"` in `user_actions.json`).
  4. Explicitly added user custom executable/script actions (`type: "executable"` in `user_actions.json`).
- **Effective Bindings (`effective_bindings.lua`)**: The single source of truth for runtime keyboard shortcuts:
  - **Bound ∩ Unbound = ∅**: Every action in the Action Registry belongs to exactly one of `Bound` (assigned exactly 1 shortcut) or `Unbound` (assigned no shortcut).
  - **Bound ∪ Unbound = Action Registry**: The exact union of Bound and Unbound equals the complete Action Registry with zero unclassified or orphaned actions.
  - If bound, the shortcut is registered with Hyprland (`hl.bind`). If unbound, Hyprland registers nothing.

### 10.3 Bound and Unbound View Architecture
`KeybindingsWindow.qml` and `KeybindingsModel.qml` partition the effective bindings into distinct operational views:
- **Bound View (Default)**:
  - Displays all active keyboard shortcuts (`unbound: false`).
  - Fast warm opening (< 100ms) with zero application enumeration overhead.
  - Pressing `u` unsets a shortcut, atomically moving it to the Unbound view and unregistering it from Hyprland.
  - Pressing `s` initiates inline shortcut capture.
  - Return runs runnable actions directly.
- **Unbound View**:
  - Displays actions without assigned shortcuts (`unbound: true`).
  - Displays `—` in the shortcut column.
  - Pressing `s` captures and assigns a new shortcut, moving the item to the Bound view and registering it with Hyprland.
  - Pressing `a` opens the Add Action type selector.
- **View Navigation**:
  - Minimal command-palette tab bar: `[ Bound (N) ]`, `[ Unbound (M) ]`, and `[ + Add Action (a) ]`.
  - `Tab` key toggles between Bound and Unbound views instantly.
  - Pressing `a` toggles into the Add Action flow or returns back to shortcuts.
  - Footer hints clearly show lowercase `s`, `u`, `a`, `Tab`, and `Esc`.

### 10.4 Add Action Lifecycle: Applications & Custom Executables
The Add Action workflow provides two distinct mechanisms for extending workstation actions:

1. **Installed Desktop Applications (`add_app`)**:
   - Discovers installed `.desktop` files via `application_registry.list_applications()`.
   - Adding an application validates the desktop ID syntax (rejecting path traversal and leading dashes), writes atomically to `user_actions.json` with 0600 permissions, and emits an observability log.
   - Newly added applications begin in the Unbound state (`app:<desktop_id>`) and can immediately receive a key combination via `s`.
   - `workstation-keybindings remove-app <desktop_id>` cleans up both the user action registration and any associated shortcut overrides atomically.

2. **Custom Executables and Scripts (`add_exec`)**:
   - Persisted using Schema v2 in `user_actions.json`:
     ```json
     {
       "version": 2,
       "actions": [
         {
           "type": "executable",
           "id": "exec:my_script",
           "name": "My Custom Script",
           "path": "/usr/local/bin/my-script",
           "argv": ["/usr/local/bin/my-script", "--profile", "work"]
         }
       ]
     }
     ```
   - **Path & Execution Security**:
     - Requires absolute paths without path traversal (`..`).
     - Rejects non-existent paths, directories, and non-executable files.
     - Strictly rejects shell injection characters (`;&|`$><"'\`).
     - Arguments are stored as structured `argv` arrays with zero shell interpolation.
    - **Graceful Degradation**:
      - If a configured executable file is deleted or unmounted later, the action is safely marked `runnable = false` with friendly "(executable not found)" status without corrupting the Action Registry or breaking other shortcuts.

### 10.5 Add Action Navigation Correctness & `activateSelected()` Invariants
Prior implementations contained duplicate `Keys.onPressed` handlers across `searchInput` and `listView` that could allow navigation Enter keypresses to fall through to `runSelected()`, erroneously closing the command palette window (`windowRoot.visible = false`).

To guarantee navigation correctness and semantic parity:
1. **Centralized Authoritative Operation (`activateSelected(): bool`)**:
   - Implemented as a single, authoritative method on `KeybindingsWindow.qml`.
   - Explicitly evaluates active view states:
     - `add_action_type`: When `item.action_type_kind === "application"`, transitions to `add_app`. When `"executable"`, transitions to `add_exec`. The palette window remains open (`visible` is never set to false).
     - `add_app`: Adds the application to `user_actions.json` via `keybindingsModel.addApplication()` and schedules focus restoration.
     - `bound` / `unbound`: Runs the selected runnable item via `keybindingsModel.runSelected()`, closing the palette only upon confirmed execution launch.
2. **Re-entrancy Deduplication**:
   - A 200ms debounce threshold (`now - lastActivationTime < 200`) guards against double-activation from simultaneous key press/release or rapid repeat events.
3. **Mouse & Keyboard Semantic Parity**:
   - `KeybindingRow.qml` double-click delegates directly to `windowRoot.activateSelected()`, ensuring 100% behavioral parity between mouse and keyboard interaction paths.

---

## 11. Aurelia Shell Core Integration: Preferences, Motion & Diagnostics

Aurelia Keybindings consumes and integrates with the centralized Shell Core foundation services:
- **User Preferences**: Default view (`components.keybindings.default_view = "bound"`), component-level reset (`workstation-aurelia preference reset --component=keybindings`), and atomic overrides.
- **Motion Scaling**: Border animations, row selection transitions, and view switches consume `Theme.effectiveDurationFast` and `Theme.effectiveDurationNormal`. When motion is disabled, all durations collapse to 0ms (instantaneous transitions).
- **Structured CLI Diagnostics**: Accessible via `workstation-keybindings diagnostics [--json]` or `workstation-aurelia diagnostics [--json]`, reporting version, schema, preference health, motion status, and privacy boundaries.
- **Privacy Boundary**: Search queries are strictly protected; filter timing logs record query length rather than raw query strings. Raw tokens, credentials, and passwords are redacted before log emission.
