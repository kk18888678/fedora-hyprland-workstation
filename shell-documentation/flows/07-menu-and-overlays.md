# Menu, picker, and overlay flows

This document covers the generic loader surfaces that do not use the
bar-owned KeyboardPanel contract directly: the command menu, clipboard
history, emoji picker, image selector, reminder form, and developer gallery.
Their visual dimensions are specified in 07c-overlays-data-contracts-and-assets.md
and 05-ui-kit-and-measurements.md. The transitions below specify how a request
becomes a visible surface and how each close/action path repairs state.

## Generic host-loader route

For panel, overlay, and menu kinds the host uses one Loader per enabled
manifest entry:

~~~text
shell.summon(id, payload)
    -> resolve enabled id
    -> reject unknown or disabled id
    -> set openPanelIds[id] = true
    -> queue payloadJson
    -> activate asynchronous Loader
    -> inject shell, public manifest, registries, matching service
    -> register loader
    -> call plugin.open(payload) for queued payload
~~~

When the manifest is keepLoaded, the loader may already exist and receives the
payload immediately. A Loader error logs the source detail and asks the host to
hide the plugin.

Host hide calls the loaded item's close method, removes the id from
openPanelIds, and leaves the instance available for destruction according to
the loader's active/keepLoaded rule. A user action that only sets the plugin's
opened property false does not automatically remove openPanelIds unless the
plugin explicitly calls shell.hide. This distinction is source behavior and is
listed per plugin below.

## Command menu

### Entry and mode selection

The menu can be opened by the bar button, a keybinding, or host IPC. The bar
button maps:

~~~text
LeftButton  -> shell command to toggle omarchy.menu at route root
RightButton -> xdg-terminal-exec
~~~

Host open receives JSON. The menu chooses:

~~~text
mode select/input -> openDmenu(payload)
otherwise         -> openRoute(initialMenu or menu or root)
~~~

openRoute resolves aliases and links. If the resolved entry is an action with
an action command, it cancels the current menu state and runs the command
without presenting an empty action menu. A link follows its target. Otherwise
openExistingMenu selects the valid menu id or root, clears search/cursor state,
evaluates guards, sets opened true, rebuilds rows, invalidates volatile
providers, starts the provider queue, refreshes app icons, and defers focus.

openDmenu resets a request serial, stores mode/prompt/options/selection and
done files, sets opened true, rebuilds, and defers focus. It does not use menu
route aliases.

### Provider and application work

The menu reads default and user JSONC definitions through watched FileViews.
Provider processes are started in queue order. Each process collects rows;
onExited merges them only when its provider revision still matches, then starts
the next provider. Search can trigger provider loading for the narrowed query.

The application provider is backed by the host AppLibrary. App launch and
removal are host-owned actions, not arbitrary UI-local copies.

### Keyboard, pointer, and actions

The menu key catcher owns a single cursor:

~~~text
Escape                -> clear filter if non-empty; otherwise cancel
text/edit key         -> update filter
Up/Down/PageUp/PageDown -> move selection
Backspace/Left with no filter -> go back one menu
Right/Enter/Return    -> enter menu/link or activate selected action
Space                 -> activate selected row
Delete                -> request app deletion when selected row is an app
Tab                   -> menu-defined navigation where applicable
~~~

Pointer movement does not immediately steal keyboard cursor state until it
passes the PointerMoveGate. A row click sets cursor active, selects the row,
and activates it.

Selecting a menu action sets opened false, clears the filter, and runs the
detached action. In dmenu mode, selection writes the value to the supplied
selection file and truncates the supplied done file through a quoted helper
process. Cancel writes only the completion signal with no selection.

### Delete confirmation and close state

Delete confirmation is a nested ConfirmDialog. While it is open, the parent
key catcher delegates to the dialog. Confirming clears the dialog state,
cancels the menu, and asks AppLibrary to remove the selected application.
Cancel restores focus to the parent catcher.

The menu's cancel path:

~~~text
if dmenu active -> finishRequest(null)
opened = false
filterText = empty
~~~

The menu does not call shell.hide from cancel. Consequently a source-faithful
port must either preserve the host openPanelIds behavior or intentionally
document a different host-state repair. It must not silently assume that
opened false and openPanelIds false are always the same transition.

## Clipboard history overlay

### Background capture

The clipboard plugin reads a watched history JSON file and starts a startup
cleanup process that kills old capture watchers. After that process exits it
starts text and image watchers, each using setpriv with pdeathsig TERM. A
watcher exit arms a 1000 ms restart timer. The history limit is 500 entries.

Each captured line is normalized and deduplicated by ClipboardHistory.js,
persisted as two-space JSON plus newline, and reflected in the visible display
when open. History remains available when a watcher dies; only future capture
is delayed until restart or reload.

### Open and keyboard state

open(payload) does not use the payload for selection. It:

~~~text
opened = true
filterText = empty
selectedIndex = 0
cursorActive = true
reset pointer gate
rebuild display
defer focus to key catcher
~~~

The overlay is a full-screen Exclusive layer-shell surface with a scrim and a
centered card. The card swallows internal clicks; the scrim closes the overlay.

Keyboard behavior:

~~~text
Escape with filter -> clear filter, remain open
Escape without filter -> close
text/edit          -> update filter
Up/Down/PageUp/PageDown -> select
Delete             -> remove row
Shift+Delete       -> open clear-history confirmation
Enter              -> apply selected row
Shift+Enter         -> copy selected row
Alt+Enter           -> open selected row
~~~

The exact modifier branches are source-owned by Clipboard.qml and its display
rows. Do not collapse them into a generic “select item” action.

### Selected-row terminal actions

The plugin sets opened false before dispatching:

~~~text
text apply -> omarchy-clipboard-paste-text --shift-insert --history-index <n>
text copy  -> omarchy-clipboard-paste-text --copy-only --history-index <n>
image apply -> omarchy-clipboard-paste-file <mime> <path>
image copy  -> omarchy-clipboard-paste-file --copy-only <mime> <path>
open       -> omarchy-clipboard-open --history-index <n>
~~~

History mutation writes the updated array before rebuilding. Clear-history
confirmation clears history, saves it, resets selection/cursor, and restores
focus. close cancels an active clear confirmation and sets opened false.
Clipboard close does not call a host shell.hide method because the plugin has no
shell property; this is a source-level host-map nuance.

## Emoji picker

### Open and filter

The emoji asset is loaded from the plugin's emojis.json FileView. open resets
filter, selection, cursor, rebuilds the grid, and defers focus. The centered
full-screen surface uses a scrim and card; clicking the scrim calls dismiss.

Keyboard and pointer behavior:

~~~text
Escape with filter -> clear filter and remain open
Escape without filter -> dismiss and ask shell.hide
text/edit          -> filter the emoji list
Left/Right         -> move cell
Up/Down            -> move row
PageUp/PageDown    -> move page
Enter              -> apply selected emoji
pointer row        -> select/activate row
~~~

Applying an emoji dismisses through shell.hide first and then launches
omarchy-menu-emoji-insert with the selected Unicode character. User dismissal
therefore repairs the host openPanelIds map, unlike the clipboard's local
close-only path.

The source card is capped at Style.space(400) by Style.space(500); its cell
minimum is the maximum of Style.space(44) and display-font-plus-spacing.

## Image selector

### Special IPC request

The image selector is opened through the host's special image-selector IPC
target, not by callers constructing an arbitrary plugin loader:

~~~text
image-selector.open(dirs, rowsB64, selected, selectionFile, doneFile,
                    showLabels, filterable)
    -> decode rows
    -> shell.summon(image-picker, JSON payload)
    -> host queue/loader route
    -> ImagePicker.open(payload)
~~~

The host also provides preload and cancel methods. The payload carries image
directories, optional precomputed rows, selected path, selection file, done
file, labels, and filterability.

### Scan and reveal

openSelector increments requestSerial and records the active request. It:

~~~text
rows already cached -> load/select -> opened true -> reveal after layout settles
rows supplied        -> load them on next event turn -> opened/reveal
no rows               -> opened false -> run list.sh scan
scan output           -> accept only matching serial -> load rows -> reveal
~~~

The full-screen surface stays hidden while images are not loaded. After rows
exist it shows the scrim, and after a deferred reveal callback confirms the
same serial, non-empty images, and settled layout, it shows the carousel and
focuses it.

The carousel card geometry is source-defined as:

~~~text
expandedWidth       = 768
expandedHeight      = 475
sliceWidth          = 108
sliceHeight         = 432
sliceSpacing        = -30
top margin           = Style.space(30)
card width          = min(screenWidth - 80,
                          expandedWidth + 13 * (sliceWidth + sliceSpacing) + 40)
card height         = expandedHeight + Style.space(30) + bottomChromeHeight
~~~

### Selection, apply, and cancel

The carousel uses one selectedIndex and an optional filter. Escape clears the
filter first; with no filter it calls cancel. Enter applies the selected path.
The card and carousel swallow internal clicks; scrim click calls cancel.

Apply captures the current selection/done paths, records applySerial, clears
requestActive/selectionFile/doneFile, and runs a quoted process that writes
the selected path to the selection file and truncates the done file. The panel
closes only when onExited sees the same request serial.

Cancel completes a live done file through a release queue, clears request
state, and sets opened false. closeSelector from special IPC increments the
serial, completes both the active and requested done files when needed, clears
filter and request state, and closes. A canceled scan or apply from an older
serial must not reveal or close a newer request.

## Reminder form

### Two-step state machine

open parses an optional fontFamily payload, sets opened true, resets step to
minutes, clears minutes/filter, and defers focus. The full-screen Exclusive
surface shows a centered menu-style card.

Enter/Return runs submit:

~~~text
step minutes, blank input      -> dismiss
step minutes, invalid input    -> send Invalid reminder notification; stay open
step minutes, valid input      -> store normalized minutes; step = message; clear filter
step message                  -> build omarchy-reminder args; dismiss; exec detached
~~~

Escape clears a non-empty filter first and only dismisses when the filter is
empty. Scrim click dismisses immediately through shell.hide. The two-stage
filter behavior means Escape during typed input is not equivalent to close.

## Developer gallery

The gallery is a FloatingWindow rather than a layer-shell card. open sets
window.visible true, parses an optional section payload, and defers section
selection plus focus until the content tree is mounted. A selected section
scrolls itself into view.

PanelKeyCatcher implements the same j/k/h/l/Enter/Escape semantics used by
panels. It is blocked while a demo dropdown popup or text field owns focus.
PageUp/PageDown/Home/End are handled by the surrounding FocusScope and scroll
the gallery.

The close paths are deliberately split:

~~~text
host hide -> close() -> closingFromHost true -> window.visible false
Esc/button/window close -> requestClose() -> shell.hide(plugin id)
window visibility becomes false unexpectedly -> shell.hide(plugin id)
~~~

This prevents a host-initiated hide from recursively notifying the host while
ensuring a user-initiated window close removes the host open state.

## Acceptance checks

1. Open the menu in route, select, and input modes. Test action, link, nested
   route, provider failure, search, delete confirmation, Escape-with-filter,
   Escape-without-filter, and done-file completion.
2. Kill a clipboard watcher and verify restart after 1000 ms; paste text/image,
   copy, open, delete, and clear-history paths.
3. Filter emojis, press Escape twice, and verify filter clearing before host
   dismissal; select an emoji and verify shell.hide precedes insertion.
4. Open the image selector with cached rows, supplied rows, and a scan. Cancel
   and apply during in-flight work; verify requestSerial and done-file guards.
5. Submit blank, invalid, valid-minutes, and message reminder states and verify
   the exact dismissal/notification/command result.
6. Open and close the gallery from the host, Escape, and its window close
   control while a dropdown or TextField is focused.
