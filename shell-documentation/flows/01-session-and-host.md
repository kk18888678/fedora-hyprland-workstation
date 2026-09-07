# Session, host, bar, and pointer lifecycle

This document traces the common path shared by every surface. It is the
foundation that the feature-specific flow documents must not reimplement
differently.

## Source anchor

The checked source paths are:

| Responsibility | Source |
|---|---|
| long-lived host and configuration selection | shell/shell.qml |
| plugin scan and registry state | shell/services/PluginRegistry.qml |
| per-screen bar and slot routing | shell/plugins/bar/Bar.qml |
| button target registration and dispatch | shell/Ui/WidgetButton.qml and shell/Ui/BarIconButton.qml |
| shared bar-owned panel window | shell/Ui/KeyboardPanel.qml |
| shared keyboard dispatch | shell/Ui/PanelKeyCatcher.qml |

The source commit is
e989b5b3ee1ee1babb2614655649341f80b7b323. Line numbers can be regenerated with
nl -ba against that pinned checkout; the stable source paths and the behavior
contracts below are the authority.

## Session-to-host sequence

The host is one Quickshell process for the graphical session. Startup must
follow this order:

1. Read the session-provided repository path and derive the shell directory,
   first-party plugin directory, shipped defaults path, and user configuration
   path.
2. Construct the shared PluginRegistry, BarWidgetRegistry, and AppLibrary
   objects.
3. Install the registry's shell configuration provider and mutation callback.
4. Start the plugin scan. The registry ensures the user plugin directory
   exists and watches it.
5. Read the shipped defaults and user shell state through watched FileViews.
6. Select the active bar id. An unavailable selected bar falls back to the
   built-in bar.
7. Synchronize enabled service objects.
8. Load the enabled generic panel/overlay/menu entries and enabled bar-widget
   Components.
9. Construct one bar surface per real Quickshell screen.
10. Inject the live host/facades and configuration into each loaded surface.

The configuration rule is whole-object selection, not a deep merge:

| User state | Effective state |
|---|---|
| missing, empty, invalid JSON, or not version 1 | shipped defaults, or the small built-in fallback |
| valid object with numeric version 1 | the user object as the complete shell state |

The host writes a deep-cloned version-1 object as indented JSON with a final
newline through an atomic FileView. A config change clears a previously failed
bar id, increments the registry revision, and announces the plugin change.

## Bar construction

The built-in bar is a source component. A replacement bar is an asynchronous
Loader resolved from the selected bar manifest. The host assigns the selected
bar object only after the component has loaded and injects:

| Injected property when present | Value |
|---|---|
| omarchyPath | repository root |
| shell | scoped PluginShellApi for the bar manifest |
| manifest | public manifest view |
| barWidgetRegistry | scoped or first-party bar-widget registry |
| pluginRegistry | scoped or first-party registry |
| barConfig | full first-party config, public copy for third-party bars |

If a replacement bar Loader errors, the host marks that bar id failed and
falls back to the built-in bar. The failure is observable in logs; it is not a
silent empty surface.

Every screen creates a BarPanel. The bar window is layer-shell-owned and uses
the configured position:

| Position | Bar surface geometry |
|---|---|
| top/bottom | full screen width and bar-height surface |
| left/right | bar-width and full screen height surface |

The bar may be hidden by parking its layer-shell margins just outside the
screen. Hiding does not destroy the bar scene. A remap guard prevents a
transient screen move from exposing an intermediate surface.

## Layout normalization and slot creation

The bar reads only three layout regions:

~~~text
left
center
right
~~~

Each entry is normalized to an object with an id. A registered manifest
bar-widget takes precedence over a custom QML entry, which takes precedence
over a custom command entry, which otherwise becomes an empty module. The
active item receives its inline settings exactly as the entry provides them.

The center section has anchored and unanchored arrangements. The inactive
arrangement is not loaded; this prevents two copies of every center widget,
duplicate IPC handlers, duplicate timers, and duplicate external processes.

For each live ModuleSlot:

1. Resolve the canonical id and inline settings.
2. Resolve the registered Component from BarWidgetRegistry.
3. Load the selected Component into the slot.
4. Inject bar, moduleName, and settings.
5. Register the slot with the bar.
6. Register any nested WidgetButton/BarIconButton as a click target.
7. Compute the slot's implicit width/height from the active item's visible
   state.

An item whose visible state is false contributes zero slot extent. For Weather
this means an empty data-derived label removes the clickable slot until a
label exists; it is not a blank clickable placeholder.

## Pointer dispatch contract

The host owns a slot-wide left-button MouseArea. It records the initial point,
clears drag state, and tracks the Manhattan distance:

~~~text
distance = abs(currentX - pressedX) + abs(currentY - pressedY)
drag threshold = Style.space(4)
~~~

If the threshold is reached and reordering is available, the slot enters drag
mode, captures a ghost, updates the drop target, hides the tooltip, and
suppresses the eventual click. A valid drop mutates bar configuration. A
release below the threshold continues as a click.

For a click, the bar scans registered click targets in reverse registration
order and accepts the first target that is:

~~~text
visible != false
opacity != 0
interactive != false
pressable != false
concealed != true
triggerPress is a function
~~~

The target's mapped bounds must contain the local pointer coordinate. If no
registered target contains it, the active slot item is tried with the same
contract. The bar then calls target.triggerPress(button).

WidgetButton independently exposes the reusable local route: its MouseArea
accepts left, right, and middle buttons and calls triggerPress(mouse.button)
when pressable. triggerPress first hides that widget's tooltip and emits
pressed(button). The host route and the local route therefore converge on one
signal; a port must preserve both routes.

Right and middle behavior is widget-owned. The host does not invent a generic
meaning for them. This is why the exact feature flow documents list the
button-specific branch for every widget.

## Tooltip lifecycle

On pointer enter, a WidgetButton asks the bar to show its tooltip. On exit,
invisibility, disabled interactivity, or concealment it asks the bar to hide
it. The bar delays tooltip display by 500 ms, hides it as soon as the target
is no longer hovered, and clears the target when its hide timer expires. Drag
start also hides it.

The target's tooltip text is part of the widget contract. A panel-detail
button may deliberately provide an empty tooltip; that is not a missing
framework feature.

## Shared panel handoff

Bar-owned panels use a single activePopout reference on the live bar. The
coordinator algorithm is:

~~~text
requestPopout(owner):
    if activePopout == owner: return
    if activePopout exists:
        call closeForPopoutSwitch() when available
        otherwise call close()
    activePopout = owner

releasePopout(owner):
    if activePopout == owner:
        activePopout = null
~~~

The owner is normally the slot's active bar-widget root. A nested panel must
forward its lifecycle and popout-switching state to that root if the root is
the object mounted in the slot. Otherwise the open indicator and panel
navigation compare different object identities and the handoff is incorrect.

## Panel surface lifecycle

The shared KeyboardPanel is a full-screen layer-shell PanelWindow on the
anchor item's screen. The visible card is a child inside that window. Its
logical and visual lifetimes differ:

| State | Window visibility | Keyboard focus | Dismissal input |
|---|---|---|---|
| closed and fully faded | false | None | none |
| opening/priming | true | Exclusive | controlled by panel |
| open after 75 ms | true | OnDemand | panel and bar-strip forwarding |
| logically closed, fading | true | None | disabled |

The panel's card opacity fades for 140 ms on ordinary close. The full-screen
surface remains mapped only so that fade can render; it must not retain focus
or swallow input during that interval.

The shared surface forwards bar-strip clicks to registered targets after the
focus prime. It closes on outside click, leaves clicks inside the card for the
card's own MouseArea, and creates transparent no-focus twins on other screens
so a click on another monitor can dismiss the panel.

## Reload and teardown sequence

A local plugin file change starts a 150 ms debounce. The host then:

1. marks plugin reloading;
2. unloads generic panels;
3. unloads plugin services;
4. unregisters bar widgets;
5. waits through the next event turn;
6. clears the Qt Component cache when available;
7. rescans the registry;
8. rebuilds services, panel entries, and widget registrations.

If a scan is already in progress, reload is marked pending. When that scan
finishes, the pending reload is scheduled rather than allowing two rescan/
teardown cycles to overlap.

A generic panel Loader remains active while its plugin is enabled and either
its manifest says keepLoaded or the host openPanelIds map says it is open.
Loader completion injects host facades, public manifest, matching service,
widget registry, and plugin registry before the loader is registered. A Loader
error logs the detail and asks the host to hide the plugin.

## Acceptance checks for this common layer

1. Start with valid user state and verify one host process, one active bar
   option, one bar surface per screen, and no duplicate center widget tree.
2. Start with invalid user state and verify shipped defaults are selected
   without a partial deep merge.
3. Click a widget and verify the target resolution, tooltip hide, and one
   pressed signal. Drag beyond Style.space(4) and verify no click is emitted.
4. Open two bar-owned panels and verify the first receives
   closeForPopoutSwitch and the second becomes the sole active owner.
5. Press Escape and verify logical close releases focus and activePopout
   before the 140 ms visual fade completes.
6. Change a local plugin file twice inside 150 ms and verify one serialized
   reload, no duplicate IPC handler, and no stale component registration.
7. Make a replacement bar fail to load and verify fallback to the built-in
   bar with an observable diagnostic.

