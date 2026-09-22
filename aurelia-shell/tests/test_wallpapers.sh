#!/usr/bin/env bash

# Contract and isolated-state tests for the Aurelia wallpaper library and
# palette capability. These tests never open the live overlay, never touch the
# live desktop, and never reach the network: wallhaven is exercised through a
# stubbed curl and fixture responses.

set -Eeuo pipefail

wallpaper_root="$ROOT/plugins/aurelia.wallpapers"
wallpaper_bin="$ROOT/bin/aurelia-wallpaper"
wallpaper_lib="$ROOT/bin/lib/aurelia-wallpaper"

section "Aurelia Wallpaper Library and Palette Capability"

if [[ -f "$wallpaper_root/manifest.json" &&
      -f "$wallpaper_root/WallpapersPlugin.qml" &&
      -f "$wallpaper_root/ui/WallpapersPanel.qml" &&
      -f "$wallpaper_root/WallpapersModel.js" &&
      -f "$wallpaper_root/keybindings.lua" &&
      -f "$wallpaper_root/ui/qmldir" &&
      -x "$wallpaper_bin" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.wallpapers" and
       .name == "Wallpaper Library" and
       (.kinds == ["panel"]) and
       .keepLoaded == true and
       .entryPoints.panel == "WallpapersPlugin.qml"
   ' "$wallpaper_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$wallpaper_root" >/dev/null; then
    pass "wallpaper library declares a validated resident panel plugin"
else
    fail "wallpaper library manifest, entry points, or CLI is incomplete"
fi

if grep -q 'WlrLayershell.namespace: "aurelia-wallpapers"' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q 'WlrKeyboardFocus.Exclusive' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q 'Keys.onPressed' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q 'root.selectAdjacent' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q 'root.updateFilter' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q 'cache: true' "$wallpaper_root/ui/WallpapersPanel.qml"; then
    pass "wallpaper panel provides exclusive keyboard navigation, filtering, and cached previews"
else
    fail "wallpaper panel keyboard, filtering, or preview contract is incomplete"
fi

# A nested ColumnLayout otherwise stretches to the whole row in QtQuick Layouts,
# which collapses the sibling GridView and hides the thumbnail grid behind the
# preview pane. The preview column must therefore be pinned explicitly.
if grep -q 'Layout.preferredWidth: 300' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q 'Layout.fillWidth: false' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q 'Layout.maximumWidth: 300' "$wallpaper_root/ui/WallpapersPanel.qml"; then
    pass "wallpaper panel pins the preview column so the thumbnail grid stays visible"
else
    fail "wallpaper panel preview column can collapse the thumbnail grid"
fi

# The panel is a discovery surface only. It must not write theme or background
# state and must always delegate to the wallpaper command, which in turn
# delegates activation to the existing theme commands.
if grep -q '\[root.wallpaperBin, "list", "--rows"\]' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q '\[root.wallpaperBin, "wallhaven", "search"\]' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q '\[root.wallpaperBin, "wallhaven", "download", String(entry.id)\]' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q '\[root.wallpaperBin, "apply", String(entry.filePath)\]' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q '\[editor.wallpaperBin, "theme", "preview", editor.imagePath\]' "$wallpaper_root/ui/PaletteEditor.qml" &&
   grep -q '\[editor.wallpaperBin, "theme", "apply", editor.imagePath\]' "$wallpaper_root/ui/PaletteEditor.qml" &&
   ! grep -qE 'background\.path|theme\.name|aurelia-theme-bg|aurelia-theme set|curl ' \
       "$wallpaper_root/ui/WallpapersPanel.qml" "$wallpaper_root/ui/PaletteEditor.qml"; then
    pass "panel delegates every mutation to the aurelia-wallpaper command boundary"
else
    fail "panel bypasses the wallpaper command mutation boundary"
fi

# The palette editor and wallhaven key controls are separate components. The
# panel must lazy-load the editor so a headless session can still load the
# plugin without a layer-shell window backend.
if [[ -f "$wallpaper_root/ui/PaletteEditor.qml" &&
      -f "$wallpaper_root/ui/WallhavenKeyRow.qml" ]] &&
   grep -q 'source: Qt.resolvedUrl("PaletteEditor.qml")' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q 'active: root.editorOpen' "$wallpaper_root/ui/WallpapersPanel.qml" &&
   grep -q '"theme", "preview"' "$wallpaper_root/ui/PaletteEditor.qml" &&
   grep -q '"key", "--set"' "$wallpaper_root/ui/WallhavenKeyRow.qml"; then
    pass "palette editor and wallhaven key controls are separate, lazily loaded components"
else
    fail "palette editor or wallhaven key component contract is incomplete"
fi

# A live preview must never terminate the in-flight `theme preview` process:
# that SIGTERM exit raced the request-serial guard and produced a spurious
# "Color extraction failed" error. The editor defers instead, and opening it
# schedules exactly one preview through the debounce rather than an extra
# immediate `Qt.callLater` trigger.
if [[ -f "$wallpaper_root/ui/PalettePreview.js" ]] &&
   grep -q 'property bool previewPending: false' "$wallpaper_root/ui/PaletteEditor.qml" &&
   grep -q 'PalettePreview.requestAction' "$wallpaper_root/ui/PaletteEditor.qml" &&
   grep -q 'PalettePreview.shouldReplay' "$wallpaper_root/ui/PaletteEditor.qml" &&
   grep -q 'PalettePreview.previewError' "$wallpaper_root/ui/PaletteEditor.qml" &&
   ! grep -q 'previewProcess.running = false' "$wallpaper_root/ui/PaletteEditor.qml" &&
   ! grep -q 'Qt.callLater(editor.requestPreview)' "$wallpaper_root/ui/PaletteEditor.qml"; then
    pass "palette editor serializes previews instead of cancelling the in-flight process"
else
    fail "palette editor preview serialization or single-trigger contract regressed"
fi

if grep -q 'aurelia_wallpaper_activate()' "$wallpaper_lib/library.sh" &&
   grep -q '"\$AW_THEME_BG_BIN" set "\$path"' "$wallpaper_lib/library.sh" &&
   grep -q '"\$AW_THEME_BIN" set "\$slug"' "$wallpaper_lib/palette.sh" &&
   ! grep -qE 'background\.path' "$wallpaper_lib/library.sh" "$wallpaper_lib/palette.sh" &&
   ! grep -qE 'aurelia_wallpaper_atomic_text.*AW_BACKGROUND_PATH' "$wallpaper_lib/common.sh"; then
    pass "backend keeps activation ownership with aurelia-theme-bg and aurelia-theme"
else
    fail "backend writes wallpaper or theme state directly"
fi

if grep -q 'AW_HTTP_FAILURE_CLASS' "$wallpaper_lib/common.sh" &&
   grep -q -- "--proto '=https'" "$wallpaper_lib/common.sh" &&
   grep -q -- "--proto-redir '=https'" "$wallpaper_lib/common.sh" &&
   grep -q 'aurelia_wallpaper_host_allowed' "$wallpaper_lib/common.sh" &&
   grep -q 'aurelia_wallpaper_signature_matches' "$wallpaper_lib/common.sh"; then
    pass "downloads are HTTPS-only, host allowlisted, size bounded, and signature checked"
else
    fail "download safety contract is incomplete"
fi

size_failures=0
while IFS= read -r -d '' file; do
    line_count="$(wc -l < "$file")"
    if [[ "$line_count" -gt 1000 ]]; then
        printf '  FAIL file exceeds the 1000-line Aurelia guard: %s (%s lines)\n' "$file" "$line_count"
        size_failures=$((size_failures + 1))
    fi
done < <(find "$wallpaper_root" "$wallpaper_lib" -type f \
    \( -name '*.qml' -o -name '*.sh' -o -name '*.js' -o -name '*.lua' -o -name '*.awk' \) -print0)

if [[ "$size_failures" -eq 0 ]]; then
    pass "wallpaper capability sources remain below the god-file guard"
else
    fail "$size_failures wallpaper capability files exceed the god-file guard"
fi

wallpaper_keybindings="$(luajit - "$ROOT/dotfiles/hypr/keybindings_manifest.lua" <<'LUA'
local manifest = dofile(arg[1])
local found = 0
for _, item in ipairs(manifest.bindings or {}) do
    if item.id == "aurelia.wallpapers.library" then
        found = found + 1
        assert(item.key == "SUPER + SHIFT + W")
        assert(item.action_type == "plugin_ipc")
        assert(item.target == "aurelia.wallpapers")
        assert(item.method == "toggle")
        assert(item.command_argv[#item.command_argv] == "{}")
    end
end
assert(found == 1)
print("ok")
LUA
)"
if [[ "$wallpaper_keybindings" == "ok" ]]; then
    pass "wallpaper library contributes the SUPER + SHIFT + W shortcut exactly once"
else
    fail "wallpaper shortcut declaration is missing or drifted"
fi

model_output="$(node - "$wallpaper_root/WallpapersModel.js" <<'NODE'
const model = require(process.argv[2]);
const local = model.loadLocalRows(
  '/w/one.webp\t/w/one.webp\tOne\tlibrary\t0\n' +
  '/w/two.webp\t/w/two.webp\tTwo\tlibrary\t1\n'
);
const remote = model.loadWallhavenRows(
  '#meta\t2\t9\t200\n' +
  '111\t/cache/111.jpg\t1920x1080\tsfw\thttps://wallhaven.cc/w/111\n'
);
if (local.length !== 2 || model.indexForCurrent(local) !== 1) process.exit(1);
if (local[0].source !== 'library' || remote[0].kind !== 'wallhaven') process.exit(1);
if (remote.length !== 1 || remote[0].id !== '111') process.exit(1);
if (remote[0].thumb !== '/cache/111.jpg' || remote[0].purity !== 'sfw') process.exit(1);
const meta = model.parseMeta('#meta\t2\t9\t200\n111\t/x\n');
if (!meta || meta.page !== 2 || meta.lastPage !== 9 || meta.total !== 200) process.exit(1);
if (model.parseMeta('111\t/x\n') !== null) process.exit(1);
const merged = model.mergeRows([{ id: '111' }, { id: '222' }], [{ id: '222' }, { id: '333' }]);
if (merged.map((row) => row.id).join(',') !== '111,222,333') process.exit(1);
if (model.filteredRows(local, 'two').length !== 1) process.exit(1);
if (model.filteredRows(local, 'nomatch').length !== 0) process.exit(1);
if (model.loadLocalRows('only-three-fields\tx\ty\n').length !== 0) process.exit(1);
console.log('ok');
NODE
)"
if [[ "$model_output" == "ok" ]]; then
    pass "wallpaper model parses local and wallhaven rows and preserves the current selection"
else
    fail "wallpaper model behavior is incorrect: $model_output"
fi

wp_tmp="$(mktemp -d)"
cleanup_wallpaper_tmp() { rm -rf -- "$wp_tmp"; }
# The sandbox lives for the whole suite: a RETURN trap would fire on every
# pass/fail helper call and delete it mid-run.
trap cleanup_wallpaper_tmp EXIT

mkdir -p \
    "$wp_tmp/home/Pictures/Wallpapers" \
    "$wp_tmp/home/Extra" \
    "$wp_tmp/config" \
    "$wp_tmp/state" \
    "$wp_tmp/cache" \
    "$wp_tmp/bin" \
    "$wp_tmp/fixtures"

if command -v magick >/dev/null; then
    magick -size 64x64 gradient:red-blue "$wp_tmp/fixtures/wallpaper-a.jpg"
    magick -size 64x64 gradient:green-yellow "$wp_tmp/fixtures/wallpaper-b.png"
    magick -size 64x64 gradient:cyan-magenta "$wp_tmp/fixtures/wallhaven-fake.jpg"
else
    fail "ImageMagick (magick) is required to exercise the palette capability fixtures"
fi
printf 'definitely not an image\n' >"$wp_tmp/home/Extra/bogus.png"
ln -s /etc "$wp_tmp/home/Extra/escape-dir"
printf 'XDG_PICTURES_DIR="$HOME/Pictures"\n' >"$wp_tmp/config/user-dirs.dirs"

cat >"$wp_tmp/fixtures/search.json" <<'EOF'
{"data":[
 {"id":"1111111","resolution":"1920x1080","category":"general","purity":"sfw","file_size":1048576,
  "path":"https://w.wallhaven.cc/full/xx/wallhaven-1111111.jpg","url":"https://wallhaven.cc/w/1111111",
  "thumbs":{"small":"https://th.wallhaven.cc/small/xx/1111111.jpg"}},
 {"id":"2222222","resolution":"2560x1440","category":"anime","purity":"sfw","file_size":1048576,
  "path":"","url":"https://wallhaven.cc/w/2222222",
  "thumbs":{"small":"https://evil.example.com/steal.jpg"}}],
 "meta":{"current_page":1,"last_page":3,"total":60,"per_page":24}}
EOF
cat >"$wp_tmp/fixtures/detail.json" <<'EOF'
{"data":{"id":"1111111","resolution":"1920x1080","purity":"sfw","file_size":PFSIZE,
 "path":"https://w.wallhaven.cc/full/xx/wallhaven-1111111.jpg","url":"https://wallhaven.cc/w/1111111",
 "thumbs":{"small":"https://th.wallhaven.cc/small/xx/1111111.jpg"}}}
EOF
cat >"$wp_tmp/fixtures/detail-nsfw.json" <<'EOF'
{"data":{"id":"3333333","purity":"nsfw","file_size":1048576,
 "path":"https://w.wallhaven.cc/full/xx/wallhaven-3333333.jpg","url":"https://wallhaven.cc/w/3333333",
 "thumbs":{"small":"https://th.wallhaven.cc/small/xx/3333333.jpg"}}}
EOF
cat >"$wp_tmp/fixtures/catalog.js" <<'EOF'
window.WALLPAPERS_BASE_URL = "https://wallpapers.hel1.your-objectstorage.com"\;
window.WALLPAPERS = {
  "dark/blue/3840x2160_test_nebula__01-nebula.jpg": {
    "color": "blue",
    "description": "Nebula 01 Nebula. Dark blue wallpaper, omarchy theme.",
    "dimensions": "3840x2160",
    "medium_path": "cache/medium/dark/blue/3840x2160_test_nebula__01-nebula.jpg",
    "size_bytes": 12345,
    "tags": ["dark", "blue", "nebula"],
    "theme": "omarchy"
  },
  "dark/red/3840x2160_test_canyon__01-canyon.jpg": {
    "color": "red",
    "description": "Canyon 01 Canyon. Dark red wallpaper, omarchy theme.",
    "dimensions": "3840x2160",
    "medium_path": "cache/medium/dark/red/3840x2160_test_canyon__01-canyon.jpg",
    "size_bytes": 12345,
    "tags": ["dark", "red", "canyon"],
    "theme": "omarchy"
  },
  "light/green/3840x2160_test_meadow__01-meadow.jpg": {
    "color": "green",
    "description": "Meadow 01 Meadow. Light green wallpaper, omarchy theme.",
    "dimensions": "3840x2160",
    "medium_path": "https://evil.example.com/steal.jpg",
    "size_bytes": 12345,
    "tags": ["light", "green", "meadow"],
    "theme": "omarchy"
  }
};
EOF
cat >"$wp_tmp/fixtures/catalog-badhost.js" <<'EOF'
window.WALLPAPERS_BASE_URL = "https://evil.example.com/storage"\;
window.WALLPAPERS = {
  "dark/blue/x.jpg": { "description": "x", "medium_path": "m.jpg" }
};
EOF
cat >"$wp_tmp/fixtures/catalog-live.js" <<'EOF'
window.LIVE = {
  "live/1920x1080_test_retro2_live.gif": {
    "color": "live",
    "description": "Retro2. Live wallpaper.",
    "kind": "image",
    "tags": ["live", "aesthetic", "retro2"],
    "theme": "aesthetic",
    "title": "Retro2",
    "tone": "live"
  }
};
EOF
magick -size 32x32 gradient:blue-red "$wp_tmp/fixtures/catalog-live.gif"

cat >"$wp_tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Stub curl: honours --output and prints one allowlisted effective URL.
out=""
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--output" ]]; then out="$arg"; fi
    prev="$arg"
done
url="${!#}"
size="$(stat -c '%s' "$WP_FIXTURE_IMAGE")"
payload=""
case "$url" in
    *api/v1/search*) payload="$WP_FIXTURE_SEARCH" ;;
    *api/v1/w/1111111*) payload="$WP_FIXTURE_DETAIL" ;;
    *api/v1/w/3333333*) payload="$WP_FIXTURE_DETAIL_NSFW" ;;
    *wallpapers.js*) payload="$WP_FIXTURE_CATALOG_JS" ;;
    *live.js*) payload="$WP_FIXTURE_CATALOG_LIVE" ;;
    *your-objectstorage.com*.gif) payload="$WP_FIXTURE_CATALOG_GIF" ;;
    *your-objectstorage.com*) payload="$WP_FIXTURE_IMAGE" ;;
    *th.wallhaven.cc*|*w.wallhaven.cc*) payload="$WP_FIXTURE_IMAGE" ;;
    *)
        printf 'stub-curl: unexpected url %s\n' "$url" >&2
        exit 22
        ;;
esac
if [[ -n "$out" ]]; then
    if [[ "$payload" == *detail.json ]]; then
        sed "s/PFSIZE/$size/" "$payload" >"$out"
    else
        cp -- "$payload" "$out"
    fi
fi
printf '%s\n' "$url"
EOF
chmod 0755 "$wp_tmp/bin/curl"

cp "$wp_tmp/fixtures/wallpaper-a.jpg" "$wp_tmp/home/Pictures/Wallpapers/sunset.jpg"
cp "$wp_tmp/fixtures/wallpaper-b.png" "$wp_tmp/home/Pictures/Wallpapers/forest.png"
cp "$wp_tmp/fixtures/wallpaper-a.jpg" "$wp_tmp/home/Extra/duplicate-content.jpg"

wp_env=(
    "PATH=$wp_tmp/bin:$PATH"
    "HOME=$wp_tmp/home"
    "XDG_CONFIG_HOME=$wp_tmp/config"
    "XDG_STATE_HOME=$wp_tmp/state"
    "XDG_CACHE_HOME=$wp_tmp/cache"
    "WORKSTATION_TEST_MODE=1"
    "AURELIA_USE_INSTALLED_SHELL=1"
    "AURELIA_WALLPAPER_MIN_DOWNLOAD_BYTES=10"
    "WP_FIXTURE_SEARCH=$wp_tmp/fixtures/search.json"
    "WP_FIXTURE_DETAIL=$wp_tmp/fixtures/detail.json"
    "WP_FIXTURE_DETAIL_NSFW=$wp_tmp/fixtures/detail-nsfw.json"
    "WP_FIXTURE_IMAGE=$wp_tmp/fixtures/wallhaven-fake.jpg"
    "WP_FIXTURE_CATALOG_JS=$wp_tmp/fixtures/catalog.js"
    "WP_FIXTURE_CATALOG_LIVE=$wp_tmp/fixtures/catalog-live.js"
    "WP_FIXTURE_CATALOG_GIF=$wp_tmp/fixtures/catalog-live.gif"
)

run_wp() {
    env "${wp_env[@]}" "$wallpaper_bin" "$@"
}

section "Wallpaper sources and library (isolated)"

sources_json="$(run_wp sources --json)"
if jq -e '.sources[] | select(.id == "library" and .kind == "library" and .exists == true and .enabled == true)' \
    <<<"$sources_json" >/dev/null &&
   grep -q '"path": ".*Pictures/Wallpapers"' <<<"$sources_json"; then
    pass "default library source resolves the XDG Pictures/Wallpapers directory"
else
    fail "default library source is wrong: $sources_json"
fi

list_rows="$(run_wp list --rows)"
if [[ "$(grep -c . <<<"$list_rows")" == "2" ]] &&
   awk -F '\t' 'NF != 5 { exit 1 }' <<<"$list_rows" &&
   grep -q $'^/.*sunset\.jpg\t/.*sunset\.jpg\tSunset\tlibrary\t0' <<<"$list_rows" &&
   grep -q $'^/.*forest\.png\t/.*forest\.png\tForest\tlibrary\t0' <<<"$list_rows"; then
    pass "list --rows emits stable five-field rows for local sources"
else
    fail "list --rows output is not the documented row shape: $list_rows"
fi

if ! grep -q 'escape-dir' <<<"$list_rows" &&
   [[ "$(run_wp list library | grep -c .)" == "2" ]]; then
    pass "library enumeration ignores symlinks and non-image entries"
else
    fail "library enumeration followed a symlink or included non-media"
fi

if run_wp apply "$wp_tmp/home/Extra/bogus.png" >/dev/null; then
    fail "apply accepted a file whose content does not match its media type"
else
    if [[ ! -e "$wp_tmp/state/aurelia/current/background.path" ]]; then
        pass "apply rejects mis-typed content before any state mutation"
    else
        fail "rejected apply still wrote background state"
    fi
fi

if run_wp apply "$wp_tmp/home/Pictures/Wallpapers/sunset.jpg" >/dev/null &&
   [[ "$(sed -n '1p' "$wp_tmp/state/aurelia/current/background.path")" == \
      "$wp_tmp/home/Pictures/Wallpapers/sunset.jpg" ]]; then
    pass "apply activates through the existing background command"
else
    fail "apply did not activate the wallpaper"
fi

if run_wp apply "$wp_tmp/home/Extra/escape-dir/../../etc/hostname" >/dev/null; then
    fail "apply accepted a non-media file reached through a symlinked path"
else
    pass "apply rejects paths that are not media files"
fi

imported="$(run_wp import "$wp_tmp/home/Extra/duplicate-content.jpg")"
if [[ "$imported" == "$wp_tmp/home/Pictures/Wallpapers/sunset.jpg" ]] &&
   [[ "$(run_wp list library | grep -c .)" == "2" ]]; then
    pass "import is idempotent for identical content instead of duplicating files"
else
    fail "import duplicated content: $imported"
fi

if run_wp import "$wp_tmp/home/Extra/bogus.png" >/dev/null; then
    fail "import accepted a non-image file"
else
    pass "import refuses files that are not valid images"
fi

if run_wp random >/dev/null &&
   [[ -s "$wp_tmp/state/aurelia/current/background.path" ]]; then
    pass "random activates one of the enumerated wallpapers"
else
    fail "random did not activate a wallpaper"
fi

section "Wallpaper palette generation (isolated)"

theme_json="$(run_wp theme generate "$wp_tmp/home/Pictures/Wallpapers/sunset.jpg" --json)"
if jq -e '.slug == "wallpaper-sunset.jpg" and .changed == true and .background != ""' \
    <<<"$theme_json" >/dev/null; then
    pass "theme generate derives a data-only user theme from a wallpaper"
else
    fail "theme generate output is wrong: $theme_json"
fi

generated_colors="$wp_tmp/config/aurelia/themes/wallpaper-sunset.jpg/colors.toml"
color_keys_ok=1
for key in accent selection muted background foreground bright_foreground \
    red yellow green cyan blue magenta \
    bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta; do
    grep -q "^$key = \"#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]\"$" "$generated_colors" || color_keys_ok=0
done
if [[ "$color_keys_ok" == "1" ]]; then
    pass "generated colors.toml provides the complete canonical palette"
else
    fail "generated colors.toml is missing canonical keys"
fi

if [[ ! -e "$wp_tmp/config/aurelia/themes/wallpaper-sunset.jpg/shell.toml" ]] &&
   [[ -f "$wp_tmp/config/aurelia/themes/wallpaper-sunset.jpg/backgrounds/1-wallpaper.jpg" ]]; then
    pass "generated theme stays data-only and bundles its wallpaper"
else
    fail "generated theme contains unexpected or missing artifacts"
fi

theme_again="$(run_wp theme generate "$wp_tmp/home/Pictures/Wallpapers/sunset.jpg" --json)"
if jq -e '.changed == false' <<<"$theme_again" >/dev/null; then
    pass "theme generate is idempotent for the same wallpaper"
else
    fail "theme generate rewrote an unchanged theme: $theme_again"
fi

mkdir -p "$wp_tmp/config/aurelia/themes/usertheme"
printf 'mode = "dark"\n' >"$wp_tmp/config/aurelia/themes/usertheme/colors.toml"
printf 'user data\n' >"$wp_tmp/config/aurelia/themes/usertheme/extra.txt"
if run_wp theme generate "$wp_tmp/home/Pictures/Wallpapers/forest.png" --name usertheme >/dev/null; then
    fail "theme generate overwrote a user-authored theme"
else
    if [[ -f "$wp_tmp/config/aurelia/themes/usertheme/extra.txt" ]]; then
        pass "theme generate refuses to touch themes it did not generate"
    else
        fail "refused theme generation still modified the user theme"
    fi
fi

if run_wp theme apply "$wp_tmp/home/Pictures/Wallpapers/forest.png" >/dev/null &&
   [[ "$(sed -n '1p' "$wp_tmp/state/aurelia/current/theme.name")" == "wallpaper-forest.png" ]] &&
   grep -q 'themes/wallpaper-forest.png/backgrounds/' \
       "$wp_tmp/state/aurelia/current/background.path"; then
    pass "theme apply activates through the existing theme command"
else
    fail "theme apply did not activate the generated theme"
fi

theme_list_rows="$(run_wp theme list)"
if grep -E -q '^wallpaper-forest\.png +yes' <<<"$theme_list_rows"; then
    pass "theme list reports the active generated theme"
else
    fail "theme list active state is wrong"
fi

if run_wp theme remove wallpaper-forest.png >/dev/null; then
    fail "theme removal succeeded without --yes"
else
    pass "theme removal requires --yes"
fi

if run_wp theme remove wallpaper-forest.png --yes >/dev/null; then
    fail "theme removal removed the active theme"
else
    if [[ -d "$wp_tmp/config/aurelia/themes/wallpaper-forest.png" ]]; then
        pass "theme removal refuses to remove the active theme"
    else
        fail "refused theme removal still deleted the theme"
    fi
fi

if run_wp theme remove wallpaper-sunset.jpg --yes >/dev/null &&
   [[ ! -e "$wp_tmp/config/aurelia/themes/wallpaper-sunset.jpg" ]]; then
    pass "theme removal deletes only the proven generated theme"
else
    fail "theme removal did not remove the generated theme"
fi

section "Wallpaper color extraction modes and fine-tuning (isolated)"

wallpaper_image="$wp_tmp/home/Pictures/Wallpapers/sunset.jpg"

preview_json="$(run_wp theme preview "$wallpaper_image" --mode pastel --json)"
if jq -e '.recipe.mode == "pastel" and .colors.extraction_mode == "pastel" and
          (.colors.background | test("^#[0-9a-f]{6}$")) and
          (.colors.foreground | test("^#[0-9a-f]{6}$"))' <<<"$preview_json" >/dev/null &&
   [[ ! -e "$wp_tmp/config/aurelia/themes/preview" ]]; then
    pass "theme preview renders a palette without writing a theme"
else
    fail "theme preview contract is wrong: $preview_json"
fi

mode_ok=1
for extraction_mode in normal monochromatic analogous pastel material colorful muted bright; do
    rendered_mode="$(run_wp theme preview "$wallpaper_image" --mode "$extraction_mode" --json |
        jq -r '.colors.extraction_mode // empty')"
    [[ "$rendered_mode" == "$extraction_mode" ]] || mode_ok=0
done
if [[ "$mode_ok" == "1" ]]; then
    pass "all eight extraction modes render a palette"
else
    fail "an extraction mode did not render"
fi

base_colors="$(run_wp theme preview "$wallpaper_image" --mode normal --json | jq -c '.colors')"
tuned_colors="$(run_wp theme preview "$wallpaper_image" --mode normal --vibrance 40 --saturation -20 --temperature 25 --json |
    jq -c '.colors')"
if [[ "$base_colors" != "$tuned_colors" ]]; then
    pass "fine-tuning adjustments change the rendered palette"
else
    fail "fine-tuning adjustments had no effect"
fi

if run_wp theme preview "$wallpaper_image" --mode bogus >/dev/null; then
    fail "theme preview accepted an unknown extraction mode"
else
    pass "theme preview rejects an unknown extraction mode"
fi
if run_wp theme preview "$wallpaper_image" --vibrance 999 >/dev/null; then
    fail "theme preview accepted an out-of-range vibrance"
else
    pass "theme preview rejects an out-of-range adjustment"
fi
if run_wp theme preview "$wallpaper_image" --gamma 3.0 >/dev/null; then
    fail "theme preview accepted an out-of-range gamma"
else
    pass "theme preview rejects an out-of-range gamma"
fi

run_wp theme generate "$wallpaper_image" --mode material --json >/dev/null
if jq -e '.changed == false' <<<"$(run_wp theme generate "$wallpaper_image" --mode material --json)" >/dev/null &&
   jq -e '.changed == true' <<<"$(run_wp theme generate "$wallpaper_image" --mode muted --json)" >/dev/null &&
   jq -e '.recipe.mode == "muted"' "$wp_tmp/config/aurelia/themes/wallpaper-sunset.jpg/.generated.json" >/dev/null; then
    pass "theme generate treats a recipe change as a new palette"
else
    fail "theme recipe idempotency is wrong"
fi

section "Wallpaper palette regression: mean casing and alpha matte (isolated)"

# ImageMagick's `txt:` output renders hex in uppercase (for example #FFFFFF),
# while the awk mode gate matches lowercase. A dark mean must select the dark
# theme no matter which case it arrives in, even when the image also contains a
# bright candidate color that the fallback luminance heuristic would misread.
palette_awk="$wallpaper_lib/palette.awk"
upper_mode="$(printf '#101010\n#f0f0f0\n' |
    awk -v mean='#0A0B0C' -f "$palette_awk" | sed -n 's/^mode = "\(.*\)"$/\1/p')"
lower_mode="$(printf '#101010\n#f0f0f0\n' |
    awk -v mean='#0a0b0c' -f "$palette_awk" | sed -n 's/^mode = "\(.*\)"$/\1/p')"
if [[ "$upper_mode" == "dark" && "$lower_mode" == "dark" ]]; then
    pass "an uppercase ImageMagick mean selects the same dark mode as lowercase"
else
    fail "uppercase mean changed mode detection: upper=$upper_mode lower=$lower_mode"
fi

# `-background` must be set before `-alpha remove`, otherwise a transparent
# image is matted against ImageMagick's default white instead of #808080. A
# fully transparent PNG therefore must compose to exactly #808080 in both the
# computed mean and the extracted candidate colors.
# shellcheck source=/dev/null
source "$wallpaper_lib/common.sh"
# shellcheck source=/dev/null
source "$wallpaper_lib/palette.sh"
export AW_TIMEOUT_BIN="timeout"
palette_tool="$(aurelia_wallpaper_palette_tool)"
transparent_image="$wp_tmp/fixtures/transparent.png"
"$palette_tool" -size 32x32 'xc:rgba(0,0,0,0)' "PNG32:$transparent_image"
transparent_mean="$(aurelia_wallpaper_palette_mean "$transparent_image" "$palette_tool")"
transparent_colors="$(aurelia_wallpaper_palette_colors "$transparent_image" "$palette_tool" |
    tr 'A-F' 'a-f' | sort -u)"
if [[ "$transparent_mean" == "#808080" && "$transparent_colors" == "#808080" ]]; then
    pass "a fully transparent image is matted against #808080 before alpha removal"
else
    fail "transparent image matte is wrong: mean=$transparent_mean colors=$transparent_colors"
fi

section "Wallpaper palette WCAG contrast contract and surface tokens (isolated)"

# WCAG 2.x relative-luminance contrast helper for the synthetic-wallpaper
# table below. It mirrors the palette engine's own math so the assertions test
# the emitted contract rather than a second, divergent formula.
wcag_contrast() {
    awk -v fg="$1" -v bg="$2" '
        function hv(c) { return index("0123456789abcdef", tolower(c)) - 1 }
        function pair(h, i) { return hv(substr(h, i, 1)) * 16 + hv(substr(h, i + 1, 1)) }
        function lin(v) { v = v / 255; return (v <= 0.04045) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(h) { return 0.2126 * lin(pair(h, 2)) + 0.7152 * lin(pair(h, 4)) + 0.0722 * lin(pair(h, 6)) }
        BEGIN {
            l1 = lum(fg); l2 = lum(bg)
            if (l1 < l2) { t = l1; l1 = l2; l2 = t }
            printf "%.4f\n", (l1 + 0.05) / (l2 + 0.05)
        }'
}

ratio_at_least() {
    awk -v r="$1" -v m="$2" 'BEGIN { exit !(r + 0 >= m) }'
}

palette_value() {
    sed -n "s/^$2 = \"\(#[0-9a-f]\{6\}\)\"$/\1/p" <<<"$1"
}

# Synthetic wallpapers covering the documented extraction pressures. Each row
# is the candidate-color set the engine would receive from ImageMagick; the
# engine is then exercised in both light and dark modes.
synthetic_names=(bright dark busy pastel saturated)
synthetic_means=('#fffdf5' '#0a0a12' '#808080' '#f0ece6' '#808080')
synthetic_colors=(
    $'#fffdf5\n#f7e8c8\n#e8d5a8\n#f0e0c0\n#faebd7\n#fffaf0\n#f5deb3\n#ffe4b5'
    $'#050508\n#0a0a12\n#12121c\n#1a1a28\n#222236\n#2a2a40\n#101018\n#181824'
    $'#ff0044\n#00cc66\n#0066ff\n#ffcc00\n#aa00ff\n#00ffff\n#ff7700\n#33ff99'
    $'#f6e7f0\n#e7f0f6\n#e7f6ea\n#f6f0e7\n#efe7f6\n#f0f6e7\n#f6e7e7\n#e7e7f6'
    $'#ff0000\n#00ff00\n#0000ff\n#ffff00\n#ff00ff\n#00ffff\n#ff8000\n#8000ff'
)

assert_palette_contract() {
    local label="$1"
    local forced="$2"
    local mean="$3"
    local colors="$4"
    local doc=""
    local background foreground muted accent selection surface elevated lighter light_fg dark_fg
    local ratio=""
    local missing=""
    local problems=""
    local key=""
    local keys=(background foreground muted accent selection surface surfaceElevated \
        lighter_background light_foreground dark_foreground bright_foreground)

    doc="$(printf '%s\n' "$colors" | awk -v mean="$mean" -v forced="$forced" \
        -v name="synthetic" -v source="/synthetic" -v digest="synthetic" \
        -f "$palette_awk")"

    for key in "${keys[@]}"; do
        [[ -n "$(palette_value "$doc" "$key")" ]] || missing="$missing $key"
    done
    if [[ -n "$missing" ]]; then
        fail "$label palette is missing keys:$missing"
        return 0
    fi

    background="$(palette_value "$doc" background)"
    foreground="$(palette_value "$doc" foreground)"
    muted="$(palette_value "$doc" muted)"
    accent="$(palette_value "$doc" accent)"
    selection="$(palette_value "$doc" selection)"
    surface="$(palette_value "$doc" surface)"
    elevated="$(palette_value "$doc" surfaceElevated)"
    lighter="$(palette_value "$doc" lighter_background)"
    light_fg="$(palette_value "$doc" light_foreground)"
    dark_fg="$(palette_value "$doc" dark_foreground)"
    bright_fg="$(palette_value "$doc" bright_foreground)"

    ratio="$(wcag_contrast "$foreground" "$background")"
    ratio_at_least "$ratio" 4.5 || problems="$problems foreground/bg=$ratio"
    ratio="$(wcag_contrast "$muted" "$background")"
    ratio_at_least "$ratio" 4.5 || problems="$problems muted/bg=$ratio"
    ratio="$(wcag_contrast "$light_fg" "$background")"
    ratio_at_least "$ratio" 4.5 || problems="$problems light_foreground/bg=$ratio"
    ratio="$(wcag_contrast "$bright_fg" "$background")"
    ratio_at_least "$ratio" 4.5 || problems="$problems bright_foreground/bg=$ratio"
    ratio="$(wcag_contrast "$accent" "$background")"
    ratio_at_least "$ratio" 3.0 || problems="$problems accent/bg=$ratio"
    ratio="$(wcag_contrast "$dark_fg" "$background")"
    ratio_at_least "$ratio" 3.0 || problems="$problems dark_foreground/bg=$ratio"
    ratio="$(wcag_contrast "$foreground" "$surface")"
    ratio_at_least "$ratio" 4.5 || problems="$problems foreground/surface=$ratio"
    ratio="$(wcag_contrast "$foreground" "$elevated")"
    ratio_at_least "$ratio" 4.5 || problems="$problems foreground/surfaceElevated=$ratio"
    # selection is a non-text surface, but text is drawn on it, so the
    # foreground must stay readable against it too.
    ratio="$(wcag_contrast "$foreground" "$selection")"
    ratio_at_least "$ratio" 4.5 || problems="$problems foreground/selection=$ratio"
    [[ "$lighter" == "$surface" ]] || problems="$problems lighter_background!=$surface"
    [[ "$(sed -n 's/^mode = "\(.*\)"$/\1/p' <<<"$doc")" == "$forced" ]] ||
        problems="$problems mode!=$forced"

    if [[ -z "$problems" ]]; then
        pass "$label palette satisfies the WCAG text/surface contract"
    else
        fail "$label palette violated the WCAG contract:$problems"
    fi
}

synthetic_index=0
for synthetic_name in "${synthetic_names[@]}"; do
    for synthetic_mode in light dark; do
        assert_palette_contract "$synthetic_name/$synthetic_mode" "$synthetic_mode" \
            "${synthetic_means[$synthetic_index]}" "${synthetic_colors[$synthetic_index]}"
    done
    synthetic_index=$((synthetic_index + 1))
done

section "Wallpaper palette extraction error classification (isolated)"

# A decode failure or timeout is not the same as a successful decode that
# yielded no candidate colors. The ImageMagick stage's own exit status is the
# only signal for the former; `grep` returning 1 is the latter. These stubs
# reproduce both without depending on a particular ImageMagick build failure.
palette_stub_dir="$wp_tmp/palette-stubs"
mkdir -p "$palette_stub_dir"
cat >"$palette_stub_dir/no-candidates" <<'PALETTE_STUB'
#!/usr/bin/env bash
printf '%s\n' 'histogram: 1: (0,0,0) gray(0)'
exit 0
PALETTE_STUB
cat >"$palette_stub_dir/decode-failure" <<'PALETTE_STUB'
#!/usr/bin/env bash
printf '%s\n' 'magick: unable to read image data' >&2
exit 1
PALETTE_STUB
cat >"$palette_stub_dir/timeout" <<'PALETTE_STUB'
#!/usr/bin/env bash
exit 124
PALETTE_STUB
# A fake `magick` that identifies an image successfully but extracts no hex
# candidates, so the document path reports the distinct no-candidates error.
# Keep it in its own directory: putting the stub directory on PATH would also
# shadow the real `timeout` used to bound the extraction.
mkdir -p "$palette_stub_dir/shim"
cat >"$palette_stub_dir/shim/magick" <<'PALETTE_STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "identify" ]]; then
    exit 0
fi
printf '%s\n' 'histogram: 1: (0,0,0) gray(0)'
exit 0
PALETTE_STUB
chmod 0755 "$palette_stub_dir/no-candidates" \
    "$palette_stub_dir/decode-failure" "$palette_stub_dir/timeout" \
    "$palette_stub_dir/shim/magick"

palette_no_candidates_status=0
palette_no_candidates_out="$(aurelia_wallpaper_palette_colors "$wallpaper_image" \
    "$palette_stub_dir/no-candidates")" || palette_no_candidates_status=$?
palette_decode_status=0
palette_decode_error="$(aurelia_wallpaper_palette_colors "$wallpaper_image" \
    "$palette_stub_dir/decode-failure" 2>&1)" || palette_decode_status=$?
palette_timeout_status=0
palette_timeout_error="$(aurelia_wallpaper_palette_colors "$wallpaper_image" \
    "$palette_stub_dir/timeout" 2>&1)" || palette_timeout_status=$?

if [[ "$palette_no_candidates_status" -eq 0 && -z "$palette_no_candidates_out" ]]; then
    pass "an empty candidate set is a successful extraction, not a failure"
else
    fail "empty candidate extraction was misclassified (status=$palette_no_candidates_status out=$palette_no_candidates_out)"
fi

if [[ "$palette_decode_status" -ne 0 && "$palette_decode_error" == *"Color extraction failed"* &&
      "$palette_decode_error" != *"timed out"* ]]; then
    pass "a decode failure is reported specifically, not as missing candidate colors"
else
    fail "decode failure was misclassified: $palette_decode_error"
fi

if [[ "$palette_timeout_status" -ne 0 && "$palette_timeout_error" == *"Color extraction timed out"* ]]; then
    pass "a decode timeout is reported separately from a decode failure and from no candidates"
else
    fail "decode timeout was misclassified: $palette_timeout_error"
fi

# End-to-end document generation must surface the specific empty-candidate
# condition rather than the generic extraction failure.
palette_no_candidates_document="$(
    PATH="$palette_stub_dir/shim:$PATH"
    AW_TIMEOUT_BIN="timeout"
    aurelia_wallpaper_palette_document "$wallpaper_image" "preview" "" "" 2>&1
)" || true
if [[ "$palette_no_candidates_document" == *"No candidate colors could be extracted"* ]]; then
    pass "the palette document reports the specific no-candidate-colors condition"
else
    fail "no-candidate-colors document misclassified: $palette_no_candidates_document"
fi

# The supersede race is encoded in the pure preview state helper: a request
# that arrives while a preview is running is deferred, not cancelled, and the
# deferred request replays when the process exits. A successful exit clears an
# earlier error, and a real failure surfaces the command's own diagnostic.
palette_preview_output="$(node - "$wallpaper_root/ui/PalettePreview.js" <<'PALETTE_PREVIEW_NODE'
const preview = require(process.argv[2]);
const assert = (condition, message) => {
    if (!condition) { console.error(message); process.exit(1); }
};
assert(preview.requestAction(false, false) === "start", "idle request must start");
assert(preview.requestAction(true, false) === "defer", "in-flight request must defer, not cancel");
assert(preview.requestAction(false, true) === "ignore", "applying must ignore previews");
assert(preview.requestAction(true, true) === "ignore", "applying must ignore in-flight previews");
assert(preview.shouldReplay(true) === true, "deferred request must replay after exit");
assert(preview.shouldReplay(false) === false, "settled run must not replay");
assert(preview.previewError(0, "stale error") === "", "success must clear the previous error");
assert(
    preview.previewError(1, "Error: Color extraction timed out: /w/x.png") ===
        "Error: Color extraction timed out: /w/x.png",
    "failure must surface the command's specific diagnostic"
);
assert(preview.previewError(1, "") === "Color extraction failed.", "empty stderr must fall back");
console.log("ok");
PALETTE_PREVIEW_NODE
)"
if [[ "$palette_preview_output" == "ok" ]]; then
    pass "preview supersede race defers in-flight work and surfaces specific errors"
else
    fail "preview supersede race regressed: $palette_preview_output"
fi

section "Wallpaper source configuration (isolated)"

if run_wp sources add "$wp_tmp/home/Extra" --id extra >/dev/null &&
   run_wp sources --json | jq -e '.sources[] | select(.id == "extra" and .enabled == true)' >/dev/null; then
    pass "sources add persists an extra local source"
else
    fail "sources add failed"
fi

if run_wp sources add "$wp_tmp/home/Pictures" --id extra >/dev/null; then
    fail "sources add accepted a duplicate id"
else
    pass "sources add rejects duplicate source ids"
fi

if run_wp sources disable extra >/dev/null &&
   run_wp sources --json | jq -e '.sources[] | select(.id == "extra" and .enabled == false)' >/dev/null &&
   [[ "$(run_wp list | grep -c .)" == "2" ]]; then
    pass "sources disable removes a source from enumeration without deleting data"
else
    fail "sources disable did not change enumeration"
fi

if run_wp sources enable extra >/dev/null &&
   run_wp sources remove extra >/dev/null &&
   ! grep -q '"extra"' "$wp_tmp/config/aurelia/wallpapers.json"; then
    pass "sources remove deletes only the configured source entry"
else
    fail "sources remove failed"
fi

if run_wp sources remove library >/dev/null; then
    fail "the built-in library source was removable"
else
    pass "built-in sources cannot be removed"
fi

printf 'not json at all\n' >"$wp_tmp/config/aurelia/wallpapers.json"
if run_wp sources >/dev/null; then
    fail "a malformed configuration was silently accepted"
else
    pass "malformed wallpaper configuration fails closed"
fi
rm -f -- "$wp_tmp/config/aurelia/wallpapers.json"

# The wallhaven.* block in wallpapers.json must actually be applied. Loading the
# configuration is fail-closed: an explicit but unsupported value is a
# configuration error, while a valid block is accepted.
printf '{"version":1,"wallhaven":{"sorting":"bogus"}}\n' \
    >"$wp_tmp/config/aurelia/wallpapers.json"
if run_wp sources >/dev/null; then
    fail "an unsupported wallhaven.sorting value was silently accepted"
else
    pass "wallhaven configuration is validated at load time"
fi
printf '{"version":1,"wallhaven":{"sorting":"toplist","atleast":"2560x1440","purity":"100"}}\n' \
    >"$wp_tmp/config/aurelia/wallpapers.json"
if run_wp sources >/dev/null; then
    pass "a valid wallhaven configuration block is accepted"
else
    fail "a valid wallhaven configuration block was rejected"
fi
rm -f -- "$wp_tmp/config/aurelia/wallpapers.json"

section "Wallhaven integration (isolated, stubbed network)"

search_json="$(run_wp wallhaven search --query mountains --json)"
if jq -e '.results | length == 1' <<<"$search_json" >/dev/null &&
   jq -e '.results[0].id == "1111111"' <<<"$search_json" >/dev/null &&
   ! grep -q 'evil.example.com' <<<"$search_json"; then
    pass "wallhaven search drops results from non-allowlisted hosts"
else
    fail "wallhaven search filtering failed: $search_json"
fi

search_rows="$(run_wp wallhaven search --query mountains --rows --thumbs)"
if grep -q $'^1111111\t/.*/thumbs/1111111\.jpg\t1920x1080\tsfw\thttps://wallhaven\.cc/w/1111111$' \
    <<<"$search_rows"; then
    pass "wallhaven search serves cached local previews to the UI"
else
    fail "wallhaven search rows did not use cached thumbnails: $search_rows"
fi

paging_rows="$(run_wp wallhaven search --query mountains --rows --paging)"
if [[ "$(sed -n '1p' <<<"$paging_rows")" == $'#meta\t1\t3\t60' ]] &&
   grep -q $'^1111111\t' <<<"$paging_rows"; then
    pass "wallhaven --paging emits page metadata for load-more"
else
    fail "wallhaven --paging metadata is missing: $paging_rows"
fi

if [[ ! -f "$wp_tmp/config/aurelia/wallhaven.json" ]] &&
   [[ "$(run_wp wallhaven key --status)" == "not-configured" ]]; then
    pass "wallhaven reports an unset API key without exposing anything"
else
    fail "wallhaven key status is wrong"
fi

if printf 'abcd1234abcd1234abcd1234abcd1234\n' | run_wp wallhaven key --set >/dev/null &&
   [[ "$(run_wp wallhaven key --status)" == "configured" ]] &&
   [[ "$(stat -c '%a' "$wp_tmp/config/aurelia/wallhaven.json")" == "600" ]]; then
    pass "wallhaven API key is stored from stdin with 0600 permissions"
else
    fail "wallhaven API key storage failed"
fi

downloaded="$(run_wp wallhaven download 1111111)"
if [[ "$downloaded" == "$wp_tmp/home/Pictures/Wallpapers/wallhaven/wallhaven-1111111.jpg" ]] &&
   [[ -f "$downloaded" ]]; then
    pass "wallhaven download publishes a validated image into the library"
else
    fail "wallhaven download failed: $downloaded"
fi

if [[ "$(run_wp wallhaven download 1111111)" == "$downloaded" ]] &&
   [[ "$(stat -c '%Y' "$downloaded")" == "$(stat -c '%Y' "$downloaded")" ]]; then
    pass "wallhaven download is idempotent for an already stored wallpaper"
else
    fail "wallhaven download re-downloaded or moved the file"
fi

if run_wp wallhaven download 3333333 >/dev/null; then
    fail "wallhaven downloaded a non-SFW wallpaper"
else
    pass "wallhaven download refuses non-SFW results"
fi

if run_wp wallhaven download '../etc/passwd' >/dev/null; then
    fail "wallhaven accepted an invalid wallpaper id"
else
    pass "wallhaven rejects malformed wallpaper ids"
fi

section "Remote wallpaper catalog (isolated, stubbed network)"

catalog_json="$(run_wp catalog list --json)"
if jq -e '.provider == "bjarneo-catalog" and (.results | length == 2)' \
    <<<"$catalog_json" >/dev/null &&
   ! grep -q 'evil.example.com' <<<"$catalog_json"; then
    pass "catalog list drops entries whose media path is not allowlisted"
else
    fail "catalog list filtering failed: $catalog_json"
fi

catalog_rows="$(run_wp catalog list --rows --thumbs)"
if [[ "$(grep -c . <<<"$catalog_rows")" == "2" ]] &&
   grep -q $'^dark/blue/3840x2160_test_nebula__01-nebula\.jpg\t/.*/thumbs/catalog-dark_blue_3840x2160_test_nebula__01-nebula\.jpg\.jpg\tNebula 01 Nebula\. Dark blue wallpaper, omarchy theme\.\t3840x2160\tsfw\thttps://wallpapers\.hel1\.your-objectstorage\.com/dark/blue/' \
       <<<"$catalog_rows"; then
    pass "catalog list emits six-field rows with cached local previews"
else
    fail "catalog rows did not use the documented shape or cached thumbnails: $catalog_rows"
fi

catalog_query="$(run_wp catalog list --query canyon --rows)"
if [[ "$(grep -c . <<<"$catalog_query")" == "1" ]] &&
   grep -q 'canyon' <<<"$catalog_query"; then
    pass "catalog search filters client-side by key, description, and tags"
else
    fail "catalog search filtering failed: $catalog_query"
fi

catalog_downloaded="$(run_wp catalog download 'dark/blue/3840x2160_test_nebula__01-nebula.jpg')"
if [[ "$catalog_downloaded" == "$wp_tmp/home/Pictures/Wallpapers/catalog/dark_blue_3840x2160_test_nebula__01-nebula.jpg" ]] &&
   [[ -f "$catalog_downloaded" ]]; then
    pass "catalog download publishes a validated image into the library"
else
    fail "catalog download failed: $catalog_downloaded"
fi

if [[ "$(run_wp catalog download 'dark/blue/3840x2160_test_nebula__01-nebula.jpg')" == "$catalog_downloaded" ]]; then
    pass "catalog download is idempotent when the stored size matches the index"
else
    fail "catalog download re-downloaded an unchanged wallpaper"
fi

if run_wp catalog download '../../etc/passwd' >/dev/null; then
    fail "catalog accepted an unsafe storage key"
else
    pass "catalog rejects storage keys with traversal"
fi

if run_wp catalog download 'dark/blue/missing.jpg' >/dev/null; then
    fail "catalog downloaded a key that is not in the index"
else
    pass "catalog refuses keys that are not in the index"
fi

live_rows="$(run_wp catalog list --live --rows)"
if grep -q $'^live/1920x1080_test_retro2_live\.gif\t' <<<"$live_rows"; then
    pass "catalog exposes the live wallpaper index"
else
    fail "live wallpaper rows are missing: $live_rows"
fi

live_downloaded="$(run_wp catalog download 'live/1920x1080_test_retro2_live.gif')"
if [[ "$live_downloaded" == "$wp_tmp/home/Pictures/Wallpapers/catalog/live_1920x1080_test_retro2_live.gif" ]] &&
   [[ -f "$live_downloaded" ]]; then
    pass "catalog downloads animated wallpapers through the same bounded pipeline"
else
    fail "live wallpaper download failed: $live_downloaded"
fi

# A refresh that returns a foreign-host index must fail closed: the rejected
# index never enters the cache and the session keeps serving the cached copy.
env "${wp_env[@]}" WP_FIXTURE_CATALOG_JS="$wp_tmp/fixtures/catalog-badhost.js" \
    "$wallpaper_bin" catalog list --refresh --rows >/dev/null || true
catalog_cache="$wp_tmp/cache/aurelia/wallpapers/catalog/wallpapers.js"
if [[ -s "$catalog_cache" ]] &&
   grep -Fq 'window.WALLPAPERS_BASE_URL = "https://wallpapers.hel1.your-objectstorage.com"' \
       "$catalog_cache"; then
    pass "an index declaring a foreign storage host fails closed and keeps the cached catalog"
else
    fail "a foreign-host catalog index was accepted or cached"
fi

section "Wallpaper plugin import and runtime load integrity"

# Every relative import in the plugin tree must resolve on disk. A wrong
# import depth quarantines the plugin at shell load time and is invisible to
# static grep contracts.
import_failures=0
while IFS= read -r -d '' qml_file; do
    qml_dir="$(dirname -- "$qml_file")"
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        if [[ ! -e "$qml_dir/$rel" ]]; then
            printf '  FAIL unresolved import "%s" in %s\n' "$rel" "${qml_file#$ROOT/}"
            import_failures=$((import_failures + 1))
        fi
    done < <(grep -oE 'import +"[.][^"]*"' "$qml_file" | \
        sed -E 's/^import +"//; s/"$//')
done < <(find "$wallpaper_root" -type f \
    \( -name '*.qml' -o -name '*.js' \) -print0 | LC_ALL=C sort -z)

if [[ "$import_failures" -eq 0 ]]; then
    pass "every relative import in the wallpaper plugin resolves on disk"
else
    fail "$import_failures wallpaper plugin imports do not resolve"
fi

# Load the real resident shell offscreen: the plugin must produce no
# file-specific error, and any failure must be the same window-backend
# limitation shared by every known-good window plugin in this environment.
if [[ -x /usr/bin/qs ]]; then
    runtime_root="$(mktemp -d)"
    mkdir -p "$runtime_root/config" "$runtime_root/state" \
        "$runtime_root/cache" "$runtime_root/runtime"
    QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$runtime_root/runtime" XDG_STATE_HOME="$runtime_root/state" \
    XDG_CONFIG_HOME="$runtime_root/config" XDG_CACHE_HOME="$runtime_root/cache" \
    timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
        --path "$ROOT/shell.qml" >"$runtime_root/qs.log" 2>&1 || true

    # The complete runtime log is classified; the plugin passes only when it
    # contributes no unexpected diagnostic of its own. Pre-existing diagnostics
    # from unrelated plugins are reported by the classifier and asserted to be
    # unrelated below.
    # Offscreen has no layer shell, so window plugins quarantine by design; the
    # extra patterns allow exactly this plugin's two environmental lines and
    # nothing else.
    classification="$(runtime_log_is_environment_only \
        "$runtime_root/qs.log" \
        'plugin[.]failure id=aurelia[.]wallpapers|Type WallpapersPanel unavailable' \
    2>&1)" || true

    if grep 'Unexpected diagnostic:' <<<"$classification" | \
        grep -q 'aurelia.wallpapers'; then
        printf '%s\n' "$classification" >&2
        fail "wallpaper plugin load produced unexpected runtime diagnostics"
    else
        pass "wallpaper plugin load contributes no unexpected runtime diagnostics"
    fi

    # Offscreen has no layer shell, so the panel quarantines exactly like the
    # known-good calendar panel; a real session loads it instead.
    if grep -q 'plugin.failure id=aurelia.wallpapers kind=panel phase=load state=quarantined detail=Loader.Error' \
        "$runtime_root/qs.log"; then
        if grep -q 'plugin.failure id=aurelia.calendar kind=panel phase=load state=quarantined detail=Loader.Error' \
            "$runtime_root/qs.log"; then
            pass "wallpaper panel failure signature matches the known-good panel under the same environment"
        else
            fail "wallpaper panel failed where the calendar panel loaded"
        fi
    else
        pass "wallpaper panel loaded in the resident shell"
    fi

    if grep -q 'plugins/aurelia.wallpapers' "$runtime_root/qs.log" &&
       grep 'plugins/aurelia.wallpapers' "$runtime_root/qs.log" | \
       grep -qE 'no such directory|is not installed|Syntax error|Unexpected token'; then
        fail "wallpaper plugin sources produced file-specific load errors"
    else
        pass "wallpaper plugin sources produce no import or syntax errors at load time"
    fi

    rm -rf -- "$runtime_root"
else
    fail "/usr/bin/qs is required to verify the wallpaper plugin loads in the resident shell"
fi

section "Base16 import (isolated)"

cat >"$wp_tmp/fixtures/scheme.yaml" <<'EOF'
scheme: "Test Nord Base16"
author: "test"
base00: "2E3440"
base01: "3B4252"
base02: "434C5E"
base03: "4C566A"
base04: "D8DEE9"
base05: "E5E9F0"
base06: "ECEFF4"
base07: "8FBCBB"
base08: "BF616A"
base09: "D08770"
base0A: "EBCB8B"
base0B: "A3BE8C"
base0C: "88C0D0"
base0D: "81A1C1"
base0E: "B48EAD"
base0F: "BF616A"
EOF

base16_out="$(run_wp base16 import "$wp_tmp/fixtures/scheme.yaml" --json)"
if jq -e '.slug == "base16-test-nord-base16" and .applied == false' <<<"$base16_out" >/dev/null; then
    pass "base16 import derives its slug from the scheme name"
else
    fail "base16 import output is wrong: $base16_out"
fi

imported_colors="$wp_tmp/config/aurelia/themes/base16-test-nord-base16/colors.toml"
base16_keys_ok=1
for pair in 'mode = "dark"' 'background = "#2e3440"' 'foreground = "#e5e9f0"' \
    'accent = "#81a1c1"' 'red = "#bf616a"' 'brown = "#bf616a"'; do
    grep -Fq "$pair" "$imported_colors" || base16_keys_ok=0
done
if [[ "$base16_keys_ok" == "1" ]]; then
    pass "base16 import maps the sixteen bases to the canonical palette"
else
    fail "base16 import produced an incomplete palette"
fi

if run_wp theme apply "$wp_tmp/home/Pictures/Wallpapers/forest.png" >/dev/null &&
   run_wp blueprint save forest-look >/dev/null &&
   [[ -f "$wp_tmp/config/aurelia/blueprints/forest-look.json" ]]; then
    pass "blueprint save captures the active palette and wallpaper"
else
    fail "blueprint save failed"
fi

if run_wp blueprint list | grep -q '^forest-look' &&
   run_wp blueprint list --json | jq -e '.blueprints[] | select(.slug == "forest-look")' >/dev/null; then
    pass "blueprint list exposes saved blueprints in text and JSON"
else
    fail "blueprint list failed"
fi

if run_wp blueprint apply forest-look >/dev/null &&
   [[ "$(sed -n 1p "$wp_tmp/state/aurelia/current/theme.name")" == "blueprint-forest-look" ]]; then
    pass "blueprint apply restores the saved look through the theme command"
else
    fail "blueprint apply did not activate"
fi

if run_wp blueprint remove forest-look >/dev/null; then
    fail "blueprint removal succeeded without --yes"
else
    pass "blueprint removal requires --yes"
fi

if run_wp blueprint remove forest-look --yes >/dev/null &&
   [[ ! -f "$wp_tmp/config/aurelia/blueprints/forest-look.json" ]]; then
    pass "blueprint removal deletes the saved blueprint"
else
    fail "blueprint removal failed"
fi

section "Custom app theming (isolated)"

mkdir -p "$wp_tmp/config/aurelia/custom-apps/testapp"
printf '{"template":"theme.ini","destination":"~/.config/testapp-theme.ini"}' \
    >"$wp_tmp/config/aurelia/custom-apps/testapp/config.json"
printf 'background = {background}\nstripped = {background.strip}\nrgb = {red.rgb}\nalpha = {accent.rgba:0.5}\nmode = {theme_type}\n' \
    >"$wp_tmp/config/aurelia/custom-apps/testapp/theme.ini"

if run_wp apps list --json | jq -se 'map(select(.name == "testapp")) | length == 1' >/dev/null; then
    pass "apps list discovers declared custom apps"
else
    fail "apps list failed"
fi

if run_wp apps render testapp >/dev/null &&
   grep -Fq 'background = #' "$wp_tmp/home/.config/testapp-theme.ini" ||
   grep -Fq 'background = "' "$wp_tmp/home/.config/testapp-theme.ini"; then
    pass "apps render substitutes palette variables into the destination"
else
    fail "apps render failed"
fi

printf 'bad = {not_a_variable}\n' >"$wp_tmp/config/aurelia/custom-apps/testapp/theme.ini"
if run_wp apps render testapp >/dev/null; then
    fail "apps render accepted an unknown template variable"
else
    pass "apps render rejects unknown template variables"
fi

if run_wp apps render-all >/dev/null; then
    fail "apps render-all succeeded with an unknown variable in the template"
else
    pass "apps render-all reports template failures"
fi

printf 'background = {background}\n' >"$wp_tmp/config/aurelia/custom-apps/testapp/theme.ini"
if run_wp apps render-all >/dev/null &&
   grep -Fq 'background = "' "$wp_tmp/home/.config/testapp-theme.ini"; then
    pass "apps render-all renders every declared app"
else
    fail "apps render-all failed"
fi
