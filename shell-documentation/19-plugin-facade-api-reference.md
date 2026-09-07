# Plugin facade API reference

This file is the exact public-object reference for the scoped QML facades added
by the full Quattro source. These objects are not general-purpose service
locators and are not operating-system sandboxes. They are parentless Qt objects
created by the shell host with callbacks closed over an owner id.

The visual entry point gets one of these objects only when the host is loading
third-party code or a replacement bar. First-party code receives the trusted
host objects. The distinction is a runtime ownership rule.

## Injection matrix

| Loaded object | shell property | registry property | bar-widget registry property | other direct injection |
|---|---|---|---|---|
| first-party panel/overlay/menu | ShellRoot | PluginRegistry | BarWidgetRegistry | matching service object only when the entry declares a service property |
| ordinary third-party panel/overlay/menu | scoped PluginShellApi | self-scoped PluginRegistryApi | self-scoped PluginBarWidgetRegistryApi | matching third-party service only when the entry declares a service property |
| first-party ordinary service | ShellRoot | PluginRegistry | BarWidgetRegistry | none unless the entry declares additional properties |
| third-party service | scoped PluginShellApi | self-scoped PluginRegistryApi | self-scoped PluginBarWidgetRegistryApi | none unless the entry declares additional properties |
| trusted authentication service | ShellRoot | PluginRegistry | BarWidgetRegistry | private AuthServiceStore; no public service-map entry or QObject parent |
| trusted built-in bar | ShellRoot-compatible trusted objects | trusted PluginRegistry | trusted BarWidgetRegistry | barConfig and manifest are injected directly |
| third-party replacement bar | scoped PluginShellApi | self-scoped PluginRegistryApi | detached widget-catalog snapshot | deep-copied barConfig and manifest are injected directly |
| widget under a replacement bar | target-scoped PluginShellApi | registry facade if declared | registry facade if declared | PluginBarApi, with a service-less entry shell facade |

The host tests property presence before assignment. An entry point is therefore
allowed to omit any injected property. A QML required property that is not
available before Loader construction is not part of the source contract.

## PluginShellApi

### Properties

| Property | Type/default | Meaning |
|---|---|---|
| pluginId | required string | owner id captured at facade creation |
| appLibrary | object/null | application-library facade only for a plugin declaring menu |
| bar | object/null | detached bar state for third-party code |
| barConfig | object, default empty | deep-copied public bar configuration |
| idleConfig | object, default empty | deep-copied idle configuration only for an idle clone |

### Methods

| Method | Arguments | Return/side effect |
|---|---|---|
| serviceFor | id | own live service object when the resolved id belongs to the caller; otherwise null |
| firstPartyServiceFor | id | own service when applicable, or one of the fixed non-authentication proxies available to a full bar; otherwise null |
| pluginShellForBarEntry | ownerId, moduleName | target-scoped shell facade only from a full replacement-bar context |
| summon | id, payload JSON string | host summon result; ordinary third-party scope permits its own resolved id, while a bar-capable plugin may address known non-auth UI-kind targets, subject to the host enabled check |
| hide | id | host hide result under the same own/bar scope |
| toggle | id, payload JSON string | host toggle result under the same own/bar scope |
| isPluginOpen | id | boolean; false when the id is outside the caller’s scope |
| updateEntryInline | id, settings object | boolean; writes only the caller’s own entry, or a configured bar entry for a full bar |
| mutateShellConfig | mutator function | boolean; only a full bar receives a callback that can mutate a cloned bar subtree |

The callback scopes are enforced in the host closure, not by trusting the
plugin-provided id argument. An ordinary third-party caller cannot widen
serviceFor or lifecycle methods by passing another id. Authentication services
are never returned by a third-party service lookup.

The full-bar lifecycle scope is narrower than unrestricted host access:

~~~text
own plugin/service target
known non-authentication bar-widget/panel/overlay/menu target
configured-in-bar-layout non-authentication target of any manifest kind
source-specific clone companion target
~~~

The full bar cannot control lock/polkit authentication targets. The host's
bar-control predicate admits a known target when its manifest declares one of
the listed UI kinds even when that target is not currently in the bar or
plugins array; the final summon path still rejects a disabled target. Its
mutateShellConfig callback receives a temporary object containing only a
deep-copied bar subtree; the host copies that subtree back after the callback.

## PluginRegistryApi

| Member | Contract |
|---|---|
| pluginId | required owner id |
| manifest | public copy of the owner manifest |
| enabled | live boolean for the owner |
| installedPlugins | map containing only the owner id and its public manifest |
| isEnabled(id) | true only when id is exactly the owner id and enabled |
| resolveEnabledId(id) | returns the owner id only for the exact owner id; otherwise empty string |
| entryPointUrl(candidate, kind) | returns a URL only when candidate.id equals the owner id; otherwise empty string |

The public manifest for third-party code does not contain the host-stamped
source directory, first-party flag, or trusted host-capability array.
First-party manifests retain those fields because first-party code receives the
trusted registry object rather than this facade.

## PluginAppLibraryApi

This facade is created for a third-party plugin whose manifest declares the
menu kind. It closes over the shared application library without exposing that
library or the ShellRoot parent.

| Member | Arguments | Contract |
|---|---|---|
| ownerPluginId | required string | owner identity |
| appsChanged signal | none | emitted when the shared application library changes |
| entryName | desktop-entry object | application display name |
| entrySubtext | desktop-entry object | generic name/comment subtext |
| sortedEntries | query string | application rows sorted and searched by the shared library |
| iconSource | icon identifier | resolved icon URL or empty string |
| refreshIcons | none | requests shared icon-index refresh |
| launch | desktop id, display name | delegates desktop launch/feedback |
| remove | desktop id, display name | delegates the existing application-removal flow |

No method adds a new menu provider, modifies the desktop-entry database, or
returns the underlying DesktopEntries object.

## PluginBarStateApi

This is a scalar snapshot/view of the active bar. It intentionally retains no
Bar QObject:

| Property | Source value |
|---|---|
| ownerPluginId | facade owner |
| barHidden | active bar barHidden, or false when no bar exists |
| barSize | active bar barSize clamped at zero, or zero when no bar exists |
| fontFamily | active bar fontFamily, or empty string |
| position | active bar position, or top |

The values are QML bindings and can change as the active bar, theme, or
visibility state changes.

## PluginBarWidgetRegistryApi

This facade is a detached catalogue view:

| Member | Contract |
|---|---|
| widgets | map of widget id to { component, metadata } snapshot |
| revision | current host widget-registry revision |
| metadataFor(id) | returns the detached metadata object or null |
| availableIds() | returns the keys in the local snapshot |
| has(id) | tests local presence |

The component reference is intentionally still usable by a replacement bar:
the facade is not a serialization boundary. No method registers, unregisters,
replaces, or mutates a host widget. The host refreshes widgets and revision
when its registry changes.

## PluginFirstPartyServiceApi

Only full replacement bars receive fixed proxies for these ids:

~~~text
omarchy.idle
omarchy.media
omarchy.nightlight
omarchy.notifications
~~~

The proxy exposes:

| Property/method | Contract |
|---|---|
| ownerPluginId | replacement-bar owner |
| serviceId | one of the four fixed ids |
| stayAwake | live idle-service state |
| enabled | live service-specific enabled state |
| doNotDisturb | live notification-service DND state |
| activePlayer | media-service active player projection |
| sourcePlayers | media-service source-player array, or empty |
| setIdleEnabled(value) | delegates only when serviceId is omarchy.idle |
| setNightlight(value) | delegates only when serviceId is omarchy.nightlight |
| setDoNotDisturb(value) | delegates only when serviceId is omarchy.notifications |
| runAction(action, showFeedback, playerId) | delegates only when serviceId is omarchy.media |
| playerKey(player) | media player-key helper, otherwise empty |
| selectPlayer(playerId) | media player selection, only for omarchy.media |

The proxy has no generic get/set/call method. Lock and polkit are deliberately
absent from the list.

## PluginBarApi

PluginBarApi is the bar facade passed to a widget rendered by a replacement
bar. The host creates one per plugin-api key and binds presentation values to
the active bar.

### Scalar and snapshot properties

| Property | Contract |
|---|---|
| pluginId | required owner/plugin API id |
| moduleName | required configured module id |
| shell | target-scoped PluginShellApi or null |
| foreground | themed ordinary foreground |
| barForeground | sampled transparent-bar foreground or themed foreground |
| background | themed bar background |
| urgent | themed active/urgent color |
| fontFamily | current bar font family |
| position | top, bottom, left, or right |
| vertical | true for left/right bar |
| barSize | current bar cross-axis size |
| transparent | current transparent mode |
| foregroundAnimationEnabled | current foreground-animation state |
| centerSectionRevealHeld | current center indicator reveal state |
| centerHoverRevealSuppressed | current suppression state |
| activePopout | owner’s live popout, foreignPopoutMarker, or null |
| clickTargets | detached list of click targets owned by this plugin |
| layoutConfig | deep-copied public layout configuration |
| foreignPopoutMarker | stable object shaped as { foreign: true } |

### Methods

| Method | Arguments | Contract |
|---|---|---|
| setCenterHoverRevealSuppressed | boolean | delegates a boolean suppression request to the bar |
| showTooltip | target, text | delegates shared tooltip ownership |
| hideTooltip | target | clears that target’s shared tooltip request |
| registerClickTarget | target | registers only when the target is not already owned by another plugin |
| unregisterClickTarget | target | unregisters only the owner’s target |
| requestPopout | owner | marks the owner and requests the bar’s one-popout transfer |
| releasePopout | owner | releases only an owner object marked for this plugin |
| switchPanelFrom | owner, direction | delegates panel switching; returns false without a host callback |
| targetBelongsToWindow | target, window | delegates per-window target membership test |
| moduleWidgets | id | returns all live instances only when id equals this facade’s moduleName; otherwise an empty array |
| run | command string | delegates fire-and-forget command execution through the bar |

### Ownership rules

The host tracks each registered click target and popout owner as
plugin-object records. A target already owned by a different plugin cannot be
claimed. Destroying a plugin releases its click targets and active popout.
activePopout is exposed as the actual object only to its owner; another plugin
sees foreignPopoutMarker while a different owner is active.

The facade forwards command strings to the bar’s detached executor. It does
not quote, validate, or sandbox a command string at this layer; the source
assumes trusted first-party use for this operation and the same-user
unsandboxed process boundary for third-party code.

## Facade cache and revocation

The host caches these objects by the following keys:

~~~text
third-party plugin id
hosted first-party id
replacement-bar owner + target entry
replacement-bar plugin API id
replacement-bar owner + first-party service id
~~~

On registry changes the host:

1. removes objects for disabled, removed, or no-longer-enabled plugins;
2. removes objects whose capability profile no longer matches the manifest;
3. refreshes public manifests, enabled values, bar configuration snapshots,
   widget snapshots, and scalar bar bindings;
4. releases registered click targets/popouts owned by revoked bar facades;
5. creates a new facade when the plugin or replacement bar is loaded again.

Application-library changes emit appsChanged on every cached app facade.
Bar-widget registry changes refresh the widget snapshot and revision. A
kept service object may survive the source rescan, but a revoked facade does
not extend that service lifetime.

## Source cross-check

~~~text
shell/shell.qml
shell/Ui/PluginBarApi.qml
shell/services/PluginShellApi.qml
shell/services/PluginRegistryApi.qml
shell/services/PluginAppLibraryApi.qml
shell/services/PluginBarStateApi.qml
shell/services/PluginBarWidgetRegistryApi.qml
shell/services/PluginFirstPartyServiceApi.qml
shell/services/AuthServiceStore.js
shell/plugins/bar/Bar.qml
shell/services/PluginRegistry.qml
~~~
