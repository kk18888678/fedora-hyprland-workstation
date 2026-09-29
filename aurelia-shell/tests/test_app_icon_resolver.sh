#!/usr/bin/env bash

# T5a AppIconResolver contract. These checks are isolated: the node suite
# exercises the pure ordering/validation policy, and a disposable qs fixture
# asserts real Image.status for every form of the chain. Nothing here touches
# the live compositor, shell, notification plugin, or user configuration.

set -Eeuo pipefail

section "Aurelia App Icon Resolver"

resolver_qml="$ROOT/services/AppIconResolver.qml"
resolver_js="$ROOT/services/AppIconResolver.js"
resolver_qmldir="$ROOT/services/qmldir"
widget_file="$ROOT/plugins/aurelia.active-window/ActiveWindowBarWidget.qml"
icon_primitive="$ROOT/ui/AureliaIcon.qml"
fixture_root="$ROOT/tests/fixtures/app-icon-resolver"

if [[ -f "$resolver_qml" && -f "$resolver_js" ]] &&
   grep -Fq 'pragma Singleton' "$resolver_qml" &&
   grep -Fq 'singleton AppIconResolver 1.0 AppIconResolver.qml' "$resolver_qmldir" &&
   grep -Fq 'import "AppIconResolver.js" as Logic' "$resolver_qml"; then
    pass "[static] AppIconResolver is a registered shared service with a pure node-testable companion"
else
    fail "[static] AppIconResolver owner or qmldir registration is incomplete"
fi

if grep -Fq 'function resolve(input)' "$resolver_qml" &&
   grep -Fq 'Logic.resolve(cleanInput, metadata, resolverRoot.probe)' "$resolver_qml" &&
   grep -Fq 'function themeUsable' "$resolver_qml" &&
   grep -Fq 'Quickshell.hasThemeIcon' "$resolver_qml" &&
   grep -Fq 'Quickshell.iconPath' "$resolver_qml" &&
   grep -Fq 'function fileUsable' "$resolver_qml" &&
   grep -Fq 'blockLoading: true' "$resolver_qml"; then
    pass "[static] The QML owner delegates theme lookup to Qt and proves file usability through a blocking FileView"
else
    fail "[static] AppIconResolver host probe or Qt delegation boundary is incomplete"
fi

if grep -Fq 'function buildCandidates' "$resolver_js" &&
   grep -Fq 'function resolveCandidates' "$resolver_js" &&
   grep -Fq 'durable-rehydrated' "$resolver_js" &&
   grep -Fq 'inline-image-data' "$resolver_js" &&
   grep -Fq 'image-icon-name' "$resolver_js" &&
   grep -Fq 'desktop-entry-icon' "$resolver_js" &&
   grep -Fq 'appstream-icon' "$resolver_js" &&
   grep -Fq 'window-class' "$resolver_js" &&
   grep -Fq 'proc-exe' "$resolver_js" &&
   grep -Fq 'DEFAULT_ICON = "application-x-executable"' "$resolver_js"; then
    pass "[static] The pure companion owns the full ordered candidate chain and its provenance labels"
else
    fail "[static] AppIconResolver candidate chain, provenance labels, or honest default is incomplete"
fi

if grep -Fq 'resolverRoot.xdgDataHome + "/applications"' "$resolver_qml" &&
   grep -Fq 'dataDirs[i] + "/applications"' "$resolver_qml" &&
   grep -Fq '"/var/lib/flatpak/exports/share/applications"' "$resolver_qml" &&
   grep -Fq '"/.local/share/flatpak/exports/share/applications"' "$resolver_qml" &&
   grep -Fq 'resolverRoot.xdgDataHome + "/metainfo"' "$resolver_qml"; then
    pass "[static] The bounded metadata index searches XDG_DATA_HOME, XDG_DATA_DIRS, both Flatpak export roots, and the XDG_DATA_HOME AppStream metainfo root"
else
    fail "[static] The bounded metadata index is missing an XDG data or Flatpak export root"
fi

if grep -Fq 'SUBSTRING_MATCH_MIN_LENGTH = 5' "$resolver_js" &&
   grep -Fq 'function isValidThemeName' "$resolver_js" &&
   grep -Fq 'THEME_NAME_RE' "$resolver_js" &&
   grep -Fq 'function isSymbolicName' "$resolver_js" &&
   grep -Fq 'function localImageFile' "$resolver_js" &&
   grep -Fq 'function themeNameFromImageUrl' "$resolver_js"; then
    pass "[static] The pure companion owns theme-name validation, symbolic classification, and themed image://icon extraction (the foot fix)"
else
    fail "[static] AppIconResolver validation, symbolic rule, or themed-image extraction is incomplete"
fi

if grep -Fq 'import "../../services"' "$widget_file" &&
   grep -Fq 'AppIconResolver.resolve' "$widget_file" &&
   grep -Fq 'AppIconResolver.isSymbolicName' "$widget_file" &&
   ! grep -Fq 'normalized.indexOf("chatgpt")' "$widget_file" &&
   ! grep -Fq 'Quickshell.hasThemeIcon(root.appId)' "$widget_file"; then
    pass "[static] The active-window widget delegates class-to-theme-name resolution and the symbolic rule to the shared owner"
else
    fail "[static] The active-window widget still owns ad-hoc icon resolution or has not migrated onto AppIconResolver"
fi

if grep -Fq 'AppIconResolver' "$icon_primitive" ||
   grep -Fq 'function resolve' "$icon_primitive"; then
    fail "[static] AureliaIcon grew resolution logic instead of staying a pure rendering primitive"
else
    pass "[static] AureliaIcon remains a pure rendering primitive with no resolution policy"
fi

# ---------------------------------------------------------------------------
# Pure node policy tests
# ---------------------------------------------------------------------------
if command -v node >/dev/null; then
    node_output="$(node "$ROOT/tests/app-icon-resolver.test.js" 2>&1)" && node_status=0 || node_status=$?
    if [[ "$node_status" -eq 0 ]]; then
        pass "[isolated-unit] AppIconResolver.js policy: ${node_output##*: }"
    else
        fail "[isolated-unit] AppIconResolver.js policy tests failed: $(tr '\n' ' ' <<<"$node_output")"
    fi
else
    skip "[isolated-unit] AppIconResolver.js policy tests (node unavailable)"
fi

# ---------------------------------------------------------------------------
# Isolated real-runtime fixtures
# ---------------------------------------------------------------------------
if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] AppIconResolver QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" || true' RETURN
result_file="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache" \
    "$runtime_root/home/.local/share" \
    "$runtime_root/data-home/applications" "$runtime_root/data-home/metainfo" \
    "$runtime_root/home/.local/share/flatpak/exports/share/applications" \
    "$runtime_root/data/applications" \
    "$runtime_root/data/icons/hicolor/16x16/apps"

# A real 1x1 PNG, reused as the sample image and the deterministic theme icons.
sample_png="$runtime_root/sample.png"
base64 -d >"$sample_png" <<'PNG_B64'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
PNG_B64
for icon in foot com.mitchellh.ghostty chromium-browser chatgpt utilities-terminal probefixture probefixture-symbolic; do
    cp -- "$sample_png" "$runtime_root/data/icons/hicolor/16x16/apps/$icon.png"
done

# Deterministic desktop entries. The theme icons above are what the direct
# .desktop lookup and the theme step must discover.
cat >"$runtime_root/data/applications/foot.desktop" <<'FIXTURE_FOOT'
[Desktop Entry]
Type=Application
Name=Foot
Icon=foot
Exec=foot
FIXTURE_FOOT
cat >"$runtime_root/data/applications/com.mitchellh.ghostty.desktop" <<'FIXTURE_GHOSTTY'
[Desktop Entry]
Type=Application
Name=Ghostty
Icon=com.mitchellh.ghostty
StartupWMClass=com.mitchellh.ghostty
Exec=ghostty
FIXTURE_GHOSTTY
cat >"$runtime_root/data/applications/chromium-browser.desktop" <<'FIXTURE_CHROMIUM'
[Desktop Entry]
Type=Application
Name=Chromium Web Browser
Icon=chromium-browser
StartupWMClass=Chromium-browser
Exec=chromium-browser
FIXTURE_CHROMIUM
cat >"$runtime_root/data/applications/chatgpt.desktop" <<'FIXTURE_CHATGPT'
[Desktop Entry]
Type=Application
Name=ChatGPT
Icon=chatgpt
Exec=chatgpt
FIXTURE_CHATGPT
# Root verification: entries that exist ONLY under the XDG_DATA_HOME
# applications root and ONLY under the per-user Flatpak export root must still
# be indexed, otherwise every desktop-entry-only app would silently degrade.
cat >"$runtime_root/data-home/applications/xdg-home.desktop" <<'FIXTURE_XDG_HOME'
[Desktop Entry]
Type=Application
Name=XDG Home App
Icon=foot
Exec=xdg-home
FIXTURE_XDG_HOME
cat >"$runtime_root/home/.local/share/flatpak/exports/share/applications/flatpak-user.desktop" <<'FIXTURE_FLATPAK_USER'
[Desktop Entry]
Type=Application
Name=Flatpak User App
Icon=com.mitchellh.ghostty
Exec=flatpak-user
FIXTURE_FLATPAK_USER
# AppStream-only identity living under the XDG_DATA_HOME metainfo root. The
# index must include that root or an AppStream-only icon is skipped.
cat >"$runtime_root/data-home/metainfo/appstream-only.metainfo.xml" <<'FIXTURE_APPSTREAM'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>appstream-only</id>
  <name>AppStream Only</name>
  <icon type="stock">probefixture</icon>
</component>
FIXTURE_APPSTREAM

# Pretend the result file already exists (empty) so the blocking FileView does
# not emit an avoidable "File does not exist" scene warning.
: >"$result_file"

AURELIA_APP_ICON_SOURCE="file://$fixture_root/resolver.qml" \
AURELIA_APP_ICON_RESULT="$result_file" \
AURELIA_APP_ICON_PNG="$sample_png" \
AURELIA_APP_ICON_MISSING="$runtime_root/does-not-exist.png" \
HOME="$runtime_root/home" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
XDG_DATA_HOME="$runtime_root/data-home" \
XDG_DATA_DIRS="$runtime_root/data:/usr/share" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$result_file" ]] &&
   runtime_log_is_environment_only "$runtime_log" 'hyprland|Hyprland|FileView.*failed' &&
   jq -e '
        .readyStatus == 1 and
        .errorStatus == 3 and
        ([.cases[] | select(.status != 1)] | length == 0) and
        .cases.absolute.kind == "file" and
        .cases.absolute.status == 1 and
        .cases.fileUrl.kind == "file" and
        .cases.fileUrl.status == 1 and
        .cases.appIconName.kind == "theme" and
        .cases.appIconName.name == "foot" and
        .cases.appIconName.status == 1 and
        .cases.themedImage.kind == "theme" and
        .cases.themedImage.name == "foot" and
        .cases.themedImage.origin == "image-icon-name" and
        .cases.themedImage.status == 1 and
        .cases.desktopFoot.kind == "desktop" and
        .cases.desktopFoot.name == "foot" and
        .cases.desktopFoot.status == 1 and
        .cases.desktopGhostty.kind == "desktop" and
        .cases.desktopGhostty.name == "com.mitchellh.ghostty" and
        .cases.desktopGhostty.status == 1 and
        .cases.desktopChromium.kind == "desktop" and
        .cases.desktopChromium.name == "chromium-browser" and
        .cases.desktopChromium.status == 1 and
        .cases.desktopChatgpt.kind == "desktop" and
        .cases.desktopChatgpt.name == "chatgpt" and
        .cases.desktopChatgpt.status == 1 and
        .cases.desktopXdgDataHome.kind == "desktop" and
        .cases.desktopXdgDataHome.name == "foot" and
        .cases.desktopXdgDataHome.origin == "desktop-entry-icon" and
        .cases.desktopXdgDataHome.status == 1 and
        .cases.desktopFlatpakUser.kind == "desktop" and
        .cases.desktopFlatpakUser.name == "com.mitchellh.ghostty" and
        .cases.desktopFlatpakUser.status == 1 and
        .cases.appstreamXdgDataHome.kind == "appstream" and
        .cases.appstreamXdgDataHome.name == "probefixture" and
        .cases.appstreamXdgDataHome.status == 1 and
        .cases.windowFoot.kind == "window" and
        .cases.windowFoot.name == "foot" and
        .cases.windowFoot.status == 1 and
        .cases.windowGhostty.kind == "window" and
        .cases.windowGhostty.name == "com.mitchellh.ghostty" and
        .cases.windowGhostty.status == 1 and
        .cases.inline.kind == "inline" and
        .cases.inline.status == 1 and
        .cases.unresolvable.kind == "default" and
        .cases.unresolvable.name == "application-x-executable" and
        .cases.unresolvable.status == 1 and
        (.cases.unresolvable.source | contains("application-x-executable")) and
        .cases.durable.kind == "durable" and
        .cases.durable.status == 1 and
        .cases.dangling.kind == "default" and
        .cases.dangling.name == "application-x-executable" and
        (.cases.dangling.source | contains("dangling-icon") | not) and
        .cases.symbolic.kind == "theme" and
        .cases.symbolic.name == "probefixture-symbolic" and
        .cases.symbolic.symbolic == true and
        .cases.symbolic.status == 1
   ' "$result_file" >/dev/null; then
    pass "[isolated-runtime] AppIconResolver renders an absolute path, a file:// URI, a bare theme name, the themed image://icon/foot value (Image.Ready), desktop-entry-only foot/ghostty/chromium/chatgpt, XDG_DATA_HOME, per-user Flatpak export, and XDG_DATA_HOME AppStream metadata, the foot/ghostty window-class fallback, an inline image-data value, an honest application-x-executable default, a durable value used as-is, and a dangling durable value rejected to the default"
elif runtime_log_has_environment_diagnostic "$runtime_log" &&
     runtime_skip_if_environment_only "$runtime_log" "[isolated-runtime] AppIconResolver fixture cannot create a disposable runtime backend"; then
    :
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_file" ]]; then details="$details result=$(tr '\n' ' ' <"$result_file")"; fi
    fail "[isolated-runtime] AppIconResolver fixture failed (status=$runtime_status): $details"
fi
