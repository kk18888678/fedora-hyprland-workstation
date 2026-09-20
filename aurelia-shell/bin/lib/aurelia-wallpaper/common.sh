#!/usr/bin/env bash

# Shared helpers for the Aurelia wallpaper library backend.
#
# Ownership: this library owns wallpaper *sourcing* only - local source
# discovery, library imports, wallhaven downloads, and palette generation.
# Activation stays with the existing single mutation owners:
#
#   aurelia-theme-bg set <path>   active wallpaper
#   aurelia-theme set <slug>      active palette/theme
#
# Downloaded media is untrusted structured input: it is staged, size bounded,
# signature checked, and never executed.

aurelia_wallpaper_init_paths() {
    local shell_root="$1"
    local home_dir="${HOME:-}"
    local config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
    local state_home="${XDG_STATE_HOME:-$home_dir/.local/state}"
    local cache_home="${XDG_CACHE_HOME:-$home_dir/.cache}"

    [[ "$shell_root" == /* && "$shell_root" != "/" ]] ||
        aurelia_wallpaper_fail "Aurelia shell root must be an absolute non-root path."
    [[ "$config_home" == /* && "$config_home" != "/" ]] ||
        aurelia_wallpaper_fail "XDG_CONFIG_HOME must be an absolute non-root path."
    [[ "$state_home" == /* && "$state_home" != "/" ]] ||
        aurelia_wallpaper_fail "XDG_STATE_HOME must be an absolute non-root path."
    [[ "$cache_home" == /* && "$cache_home" != "/" ]] ||
        aurelia_wallpaper_fail "XDG_CACHE_HOME must be an absolute non-root path."
    [[ "$home_dir" == /* && "$home_dir" != "/" ]] ||
        aurelia_wallpaper_fail "HOME must be an absolute non-root path."

    AW_SHELL_ROOT="$shell_root"
    AW_BIN_ROOT="$shell_root/bin"
    AW_HOME="$home_dir"
    AW_CONFIG_HOME="$config_home"
    AW_CONFIG_ROOT="$config_home/aurelia"
    AW_CONFIG_FILE="$AW_CONFIG_ROOT/wallpapers.json"
    AW_WALLHAVEN_KEY_FILE="$AW_CONFIG_ROOT/wallhaven.json"
    AW_THEME_ROOT="$config_home/aurelia/themes"
    AW_STATE_ROOT="$state_home/aurelia/current"
    AW_BACKGROUND_PATH="$AW_STATE_ROOT/background.path"
    AW_THEME_NAME_PATH="$AW_STATE_ROOT/theme.name"
    AW_CACHE_HOME="$cache_home"
    AW_CACHE_ROOT="$cache_home/aurelia/wallpapers"
    AW_THUMB_ROOT="$AW_CACHE_ROOT/thumbs"
    AW_DOWNLOAD_ROOT="$AW_CACHE_ROOT/downloads"
    AW_DOWNLOAD_LOG="$AW_CACHE_ROOT/wallhaven-downloads.json"
    AW_THEME_BG_BIN="$shell_root/bin/aurelia-theme-bg"
    AW_THEME_BIN="$shell_root/bin/aurelia-theme"

    # Bounded external operations. Every network fetch is capped by both time
    # and transferred bytes so a hostile or broken endpoint cannot hang the
    # command or fill the disk.
    AW_CONNECT_TIMEOUT="${AURELIA_WALLPAPER_CONNECT_TIMEOUT:-15}"
    AW_SEARCH_TIMEOUT="${AURELIA_WALLPAPER_SEARCH_TIMEOUT:-25}"
    AW_THUMB_TIMEOUT="${AURELIA_WALLPAPER_THUMB_TIMEOUT:-20}"
    AW_DOWNLOAD_TIMEOUT="${AURELIA_WALLPAPER_DOWNLOAD_TIMEOUT:-180}"
    AW_MAX_DOWNLOAD_BYTES="${AURELIA_WALLPAPER_MAX_DOWNLOAD_BYTES:-67108864}"
    AW_MIN_DOWNLOAD_BYTES="${AURELIA_WALLPAPER_MIN_DOWNLOAD_BYTES:-1024}"

    # Authoritative wallhaven endpoints. Redirects are restricted to HTTPS and
    # the effective URL host is re-validated after every request.
    AW_WALLHAVEN_ALLOWED_HOSTS="wallhaven.cc api.wallhaven.cc w.wallhaven.cc th.wallhaven.cc"
    # Pinned remote catalog: the bjarneo wallpapers index and its storage host.
    # Both are declared here so neither the index nor the media it points at can
    # redirect a download to an arbitrary machine.
    AW_CATALOG_ALLOWED_HOSTS="bjarneo.github.io wallpapers.hel1.your-objectstorage.com"
    AW_CATALOG_INDEX_URL="https://bjarneo.github.io/wallpapers/wallpapers.js"
    AW_CATALOG_LIVE_URL="https://bjarneo.github.io/wallpapers/live.js"
    AW_CATALOG_DEFAULT_BASE_URL="https://wallpapers.hel1.your-objectstorage.com"
    AW_CATALOG_INDEX_ROOT="$AW_CACHE_ROOT/catalog"
    AW_CATALOG_INDEX_TIMEOUT="${AURELIA_WALLPAPER_CATALOG_TIMEOUT:-240}"
    AW_CATALOG_INDEX_MAX_BYTES="${AURELIA_WALLPAPER_CATALOG_MAX_BYTES:-134217728}"
    AW_CATALOG_INDEX_TTL="${AURELIA_WALLPAPER_CATALOG_TTL:-604800}"
    AW_BLUEPRINT_ROOT="$config_home/aurelia/blueprints"
    AW_APPS_ROOT="$config_home/aurelia/custom-apps"
    AW_ACTIVE_COLORS_PATH="$state_home/aurelia/current/colors.toml"
    AW_ACTIVE_BACKGROUND_PATH="$state_home/aurelia/current/background.path"
    AW_USER_AGENT="aurelia-wallpaper/1.0"
    AW_CURL_BIN="${AURELIA_WALLPAPER_CURL:-curl}"
    AW_SHUFFLE_BIN="${AURELIA_WALLPAPER_SHUFFLE:-shuf}"
    AW_TIMEOUT_BIN="${AURELIA_WALLPAPER_TIMEOUT:-timeout}"
    AW_WALLHAVEN_THUMB_LIMIT="${AURELIA_WALLPAPER_THUMB_LIMIT:-48}"
    AW_WALLHAVEN_LOG_LIMIT="200"
}

aurelia_wallpaper_fail() {
    printf 'Error: %s\n' "$1" >&2
    # Fail closed in every context: a safety refusal must never be followed by
    # continued execution, including inside command substitutions where `set -e`
    # is suppressed.
    exit 1
}
aurelia_wallpaper_usage() {
    cat >&2 <<'USAGE'
Usage: aurelia-wallpaper <command> [options]

Sources and library:
  sources [--json]                   List configured wallpaper sources.
  sources add <path> [--id <id>]     Add a local source directory.
  sources remove <id>                Remove a configured source.
  sources enable|disable <id>        Toggle a configured source.
  list [<source>] [--json|--rows]    List local wallpapers (default: all).
  apply <path>                       Activate a wallpaper path.
  apply --source <id> --index <n>    Activate one wallpaper from a source.
  apply --source <id> --next         Activate the next wallpaper in a source.
  random [<source>]                  Activate a random wallpaper.
  next [<source>]                    Activate the next wallpaper cyclically.
  current [--json]                   Show the active wallpaper.
  import <path> [--to <source>]      Copy an image into a library source.

Remote catalog (bjarneo wallpapers, pinned index and storage hosts):
  catalog list [--query <text>] [--live] [--refresh] [--rows|--json] [--thumbs]
  catalog download <key> [--to <source>]

Wallhaven:
  wallhaven key [--status|--set]     Report or store the optional API key.
  wallhaven search [--query <text>] [--categories <111>] [--purity <100>]
                   [--sorting <relevance|date_added|views|favorites|toplist|hot|random>]
                   [--order <desc|asc>] [--atleast <WxH>] [--page <n>]
                   [--seed <text>] [--rows] [--json]
  wallhaven download <id> [--to <source>]
                                     Download an SFW wallpaper into the library.

Palette (extract a data-only theme from a wallpaper):
  theme preview <path> [--mode <m>] [--light|--dark] [<adjustments>] --json
                                     Render the palette for the current recipe
                                     without writing any theme (UI preview).
  theme generate <path> [--name <slug>] [--mode <m>] [--light|--dark]
                                     [<adjustments>] [--json]
                                     Generate a user theme from a wallpaper.
  theme apply <path> [--name <slug>] [--mode <m>] [--light|--dark]
                                     [<adjustments>]
                                     Generate the theme and activate it.
  theme list [--json]                List generated wallpaper themes.
  theme remove <slug> --yes          Remove a generated theme.

  Extraction modes: normal, monochromatic, analogous, pastel, material,
  colorful, muted, bright.
  Adjustments: --vibrance, --saturation, --contrast, --brightness,
  --shadows, --highlights, --gamma, --black-point, --white-point,
  --hue-shift, --temperature, --tint.

Base16 schemes (tinted-theming):
  base16 import <scheme.yaml> [--name <slug>] [--light] [--apply] [--json]
  Parses plain scheme: / base00-base0F key: value lines (no YAML lib).

Blueprints (save and restore complete looks):
  blueprint save <name> [--wallpaper <path>]
  blueprint list [--json] | apply <name> | remove <name> --yes

Custom app theming (render your templates with the active palette):
  apps list [--json] | render <name> | render-all
  Variables: {background} {foreground} {accent} {red}..{magenta},
  {bright_*}, {theme_type}, {wallpaper}; modifiers .strip .rgb .rgba[:a]
  Reload hooks are intentionally not executed (safety).

Aether CLI compatibility: --generate <path>, --list-wallpapers,
--random-wallpaper, --import-base16 <file>, --list-blueprints,
--apply-blueprint <name>

Wallpapers are never installed software: downloads are user media, validated
as images, and are never executed.
USAGE
}

aurelia_wallpaper_require_tools() {
    local tool
    for tool in jq timeout flock sha256sum od mktemp; do
        command -v "$tool" >/dev/null ||
            aurelia_wallpaper_fail "Required command is unavailable: $tool"
    done
}

# Absolute, non-root, non-symlink safe directory path used as a local source.
aurelia_wallpaper_safe_dir() {
    local path="$1"
    local label="$2"

    [[ "$path" == /* && "$path" != "/" ]] ||
        aurelia_wallpaper_fail "$label must be an absolute non-root path: $path"
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]] ||
        aurelia_wallpaper_fail "$label contains control characters: $path"
    [[ ! -L "$path" ]] ||
        aurelia_wallpaper_fail "$label must not be a symlink: $path"
}

aurelia_wallpaper_mkdir() {
    local path="$1"
    local label="$2"

    aurelia_wallpaper_safe_dir "$path" "$label" || return 1
    if [[ -e "$path" && ! -d "$path" ]]; then
        aurelia_wallpaper_fail "$label exists and is not a directory: $path"
        return 1
    fi
    mkdir -p -m 0700 -- "$path" ||
        aurelia_wallpaper_fail "Could not create $label: $path"
}

aurelia_wallpaper_prepare_cache() {
    local cache_parent="${AW_CACHE_ROOT%/*}"

    [[ "$cache_parent" == /* && "$cache_parent" != "/" ]] ||
        aurelia_wallpaper_fail "Wallpaper cache parent is unsafe."
    [[ ! -L "$AW_CACHE_HOME" && ! -L "$AW_CACHE_ROOT" ]] ||
        aurelia_wallpaper_fail "Wallpaper cache path must not be a symlink."
    aurelia_wallpaper_mkdir "$AW_CACHE_ROOT" "Wallpaper cache" || return 1
    aurelia_wallpaper_mkdir "$AW_THUMB_ROOT" "Wallpaper thumbnail cache" || return 1
    aurelia_wallpaper_mkdir "$AW_DOWNLOAD_ROOT" "Wallpaper download staging" || return 1
}

aurelia_wallpaper_prepare_config() {
    [[ ! -L "$AW_CONFIG_ROOT" ]] ||
        aurelia_wallpaper_fail "Aurelia configuration root must not be a symlink: $AW_CONFIG_ROOT"
    aurelia_wallpaper_mkdir "$AW_CONFIG_ROOT" "Aurelia configuration root" || return 1
}

aurelia_wallpaper_lock() {
    local lock_path="$AW_CONFIG_ROOT/.wallpaper.lock"

    aurelia_wallpaper_prepare_config || return 1
    [[ ! -L "$lock_path" && (! -e "$lock_path" || -f "$lock_path") ]] ||
        aurelia_wallpaper_fail "Wallpaper lock path is unsafe."
    exec 8>"$lock_path" ||
        aurelia_wallpaper_fail "Could not open wallpaper lock."
    flock -x 8 ||
        aurelia_wallpaper_fail "Could not acquire wallpaper lock."
}

aurelia_wallpaper_setting_is_true() {
    [[ "${1:-0}" == "1" || "${1:-}" == "true" ]]
}
aurelia_wallpaper_atomic_text() {
    local content="$1"
    local destination="$2"
    local temporary

    [[ "$destination" == /* && "$destination" != "/" ]] ||
        aurelia_wallpaper_fail "Wallpaper state destination is unsafe: $destination"
    [[ ! -e "$destination" || ! -L "$destination" ]] ||
        aurelia_wallpaper_fail "Refusing to replace symlinked wallpaper state: $destination"

    temporary="$(mktemp "${destination}.XXXXXX")" ||
        aurelia_wallpaper_fail "Could not create wallpaper staging file."
    if ! printf '%s\n' "$content" >"$temporary"; then
        rm -f -- "$temporary"
        aurelia_wallpaper_fail "Could not stage wallpaper data."
    fi
    chmod 0600 -- "$temporary"
    mv -f -- "$temporary" "$destination"
}

aurelia_wallpaper_atomic_move() {
    local source="$1"
    local destination="$2"

    [[ -f "$source" && ! -L "$source" ]] ||
        aurelia_wallpaper_fail "Wallpaper staging source is not a regular file: $source"
    [[ "$destination" == /* && "$destination" != "/" ]] ||
        aurelia_wallpaper_fail "Wallpaper destination is unsafe: $destination"
    [[ ! -L "$destination" ]] ||
        aurelia_wallpaper_fail "Refusing to replace symlinked wallpaper file: $destination"
    mv -f -- "$source" "$destination"
}

aurelia_wallpaper_sha256() {
    local path="$1"
    local digest=""

    digest="$(sha256sum -- "$path" | cut -d ' ' -f 1)" || true
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] ||
        aurelia_wallpaper_fail "Could not hash file: $path"
    printf '%s\n' "$digest"
}

# Extension allowlist identical to the Aurelia theme/background contract.
aurelia_wallpaper_is_supported_image() {
    local path="$1"

    [[ "$path" == /* && "$path" != "/" ]] || return 1
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    [[ "$(basename -- "$path")" != .* ]] || return 1
    [[ "$path" =~ \.(jpg|jpeg|png|gif|bmp|webp|mp4|m4v|mov|webm|mkv|avi)$ ]]
}

aurelia_wallpaper_is_still_image() {
    local path="$1"

    aurelia_wallpaper_is_supported_image "$path" || return 1
    [[ ! "$path" =~ \.(mp4|m4v|mov|webm|mkv|avi)$ ]]
}

# A downloaded file must prove it is an image before it may enter the library.
# Extension checks alone are not evidence: the leading bytes are inspected so a
# renamed payload cannot be copied in as a "wallpaper".
aurelia_wallpaper_signature_matches() {
    local path="$1"
    local signature=""

    [[ -f "$path" && ! -L "$path" ]] || return 1
    signature="$(od -An -tx1 -N 12 -- "$path" | tr -d ' \n')" || return 1
    [[ -n "$signature" ]] || return 1

    case "$path" in
        *.jpg|*.jpeg) [[ "$signature" == ffd8ff* ]] ;;
        *.png) [[ "$signature" == 89504e470d0a1a0a* ]] ;;
        *.gif) [[ "$signature" == 474946* ]] ;;
        *.bmp) [[ "$signature" == 424d* ]] ;;
        *.webp) [[ "$signature" == 52494646*57454250* ]] ;;
        *.mp4|*.m4v|*.mov) [[ "$signature" == *66747970* ]] ;;
        *.webm|*.mkv) [[ "$signature" == 1a45dfa3* ]] ;;
        *.avi) [[ "$signature" == 52494646*41564920* ]] ;;
        *) return 1 ;;
    esac
}

# Normalize a wallpaper basename into a safe theme/file slug.
aurelia_wallpaper_slug() {
    local raw="$1"

    [[ -n "$raw" ]] || return 1
    LC_ALL=C printf '%s' "$raw" |
        tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9._+-]+/-/g; s/^-+//; s/-+$//' |
        cut -c 1-64 |
        sed -E 's/[-._+]+$//'
}

aurelia_wallpaper_label_for() {
    local path="$1"
    local name

    name="$(basename -- "$path")"
    name="${name%.*}"
    printf '%s\n' "$name" |
        LC_ALL=C sed -E 's/[-_]+/ /g' |
        awk '{ for (i = 1; i <= NF; i++) { $i = toupper(substr($i, 1, 1)) substr($i, 2) } } 1'
}

# Hex color helpers shared by base16 imports and app template rendering.
aurelia_wallpaper_hex_rgb() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf '%d,%d,%d' "$r" "$g" "$b"
}

aurelia_wallpaper_hex_rgba() {
    local hex="${1#\#}"
    local alpha="${2:-1}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf 'rgba(%d,%d,%d,%s)' "$r" "$g" "$b" "$alpha"
}

# Mix two hex colors; amount is the weight of the second color (0..1).
aurelia_wallpaper_mix_hex() {
    local start="${1#\#}"
    local end="${2#\#}"
    local amount="$3"
    [[ "$start" =~ ^[0-9A-Fa-f]{6}$ && "$end" =~ ^[0-9A-Fa-f]{6}$ ]] || return 1
    awk -v s="$start" -v e="$end" -v t="$amount" '
        function hv(c) { return index("0123456789abcdef", tolower(c)) - 1 }
        function pv(h, i) { return hv(substr(h, i, 1)) * 16 + hv(substr(h, i + 1, 1)) }
        BEGIN {
        r = pv(s, 1); g = pv(s, 3); b = pv(s, 5)
        r2 = pv(e, 1); g2 = pv(e, 3); b2 = pv(e, 5)
        printf "#%02x%02x%02x", int(r + (r2 - r) * t + 0.5), int(g + (g2 - g) * t + 0.5), int(b + (b2 - b) * t + 0.5)
        }'
}

aurelia_wallpaper_host_allowed() {
    local url="$1"
    local hosts="${2:-$AW_WALLHAVEN_ALLOWED_HOSTS}"
    local host=""
    local allowed=""

    [[ "$url" == https://* ]] || return 1
    host="${url#https://}"
    host="${host%%/*}"
    host="${host%%\?*}"
    host="${host##*@}"
    host="${host%%:*}"
    [[ -n "$host" ]] || return 1

    for allowed in $hosts; do
        if [[ "$host" == "$allowed" ]]; then
            return 0
        fi
    done
    return 1
}

aurelia_wallpaper_pictures_dir() {
    local user_dirs="$AW_CONFIG_HOME/user-dirs.dirs"
    local line=""
    local value=""
    local resolved=""

    AW_DEFAULT_LIBRARY="$AW_HOME/Pictures/Wallpapers"
    [[ -f "$user_dirs" && ! -L "$user_dirs" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*XDG_PICTURES_DIR[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]] ||
            continue
        value="${BASH_REMATCH[1]}"
        case "$value" in
            '$HOME'*) resolved="$AW_HOME${value#\$HOME}" ;;
            /*) resolved="$value" ;;
            *) resolved="" ;;
        esac
        [[ -n "$resolved" ]] || continue
        [[ "$resolved" == /* && "$resolved" != "/" ]] || continue
        [[ "$resolved" != *$'\n'* && "$resolved" != *$'\r'* ]] || continue
        AW_DEFAULT_LIBRARY="$resolved/Wallpapers"
        return 0
    done <"$user_dirs"
}

# A malformed or unexpected configuration file is reported, never silently
# replaced by defaults: the user's declared intent stays authoritative.
aurelia_wallpaper_config_load() {
    AW_CFG_SOURCE_IDS=()
    AW_CFG_SOURCE_PATHS=()
    AW_CFG_SOURCE_ENABLED=()
    AW_CFG_LIBRARY="$AW_DEFAULT_LIBRARY"
    AW_CFG_WALLHAVEN_CATEGORIES="111"
    AW_CFG_WALLHAVEN_PURITY="100"
    AW_CFG_WALLHAVEN_SORTING="relevance"
    AW_CFG_WALLHAVEN_ORDER="desc"
    AW_CFG_WALLHAVEN_ATLEAST=""
    AW_CFG_WALLHAVEN_PAGE_SIZE="24"

    [[ -e "$AW_CONFIG_FILE" ]] || return 0
    [[ -f "$AW_CONFIG_FILE" && ! -L "$AW_CONFIG_FILE" ]] ||
        aurelia_wallpaper_fail "Wallpaper configuration must be a regular file: $AW_CONFIG_FILE"
    jq -e 'type == "object"' "$AW_CONFIG_FILE" >/dev/null ||
        aurelia_wallpaper_fail "Wallpaper configuration is not a JSON object: $AW_CONFIG_FILE"
    [[ "$(jq -r '.version // 1' "$AW_CONFIG_FILE")" == "1" ]] ||
        aurelia_wallpaper_fail "Unsupported wallpaper configuration version (expected 1): $AW_CONFIG_FILE"

    local library=""
    library="$(jq -r '.library // empty' "$AW_CONFIG_FILE")"
    if [[ -n "$library" ]]; then
        [[ "$library" == /* ]] ||
            aurelia_wallpaper_fail "Configured library path must be absolute: $library"
        aurelia_wallpaper_safe_dir "$library" "Configured library" || return 1
        AW_CFG_LIBRARY="$library"
    fi

    local row=""
    local id=""
    local path=""
    local enabled=""
    local existing=""
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        id="$(jq -r '.id // empty' <<<"$row")"
        path="$(jq -r '.path // empty' <<<"$row")"
        enabled="$(jq -r 'if .enabled == false then "0" else "1" end' <<<"$row")"
        [[ "$id" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] ||
            aurelia_wallpaper_fail "Invalid wallpaper source id: $id"
        [[ "$path" == /* ]] ||
            aurelia_wallpaper_fail "Wallpaper source path must be absolute: $path"
        aurelia_wallpaper_safe_dir "$path" "Wallpaper source" || return 1
        for existing in ${AW_CFG_SOURCE_IDS[@]+"${AW_CFG_SOURCE_IDS[@]}"}; do
            [[ "$existing" != "$id" ]] ||
                aurelia_wallpaper_fail "Duplicate wallpaper source id: $id"
        done
        AW_CFG_SOURCE_IDS+=("$id")
        AW_CFG_SOURCE_PATHS+=("$path")
        AW_CFG_SOURCE_ENABLED+=("$enabled")
    done < <(jq -c '(.sources // [])[]' "$AW_CONFIG_FILE")
}

aurelia_wallpaper_config_load_wallhaven() {
    # The config file is optional; without it the built-in defaults apply.
    [[ -f "$AW_CONFIG_FILE" && ! -L "$AW_CONFIG_FILE" ]] || return 0

    local categories=""
    local purity=""
    local sorting=""
    local order=""
    local atleast=""
    local page_size=""

    categories="$(jq -r '.wallhaven.categories // empty' "$AW_CONFIG_FILE")"
    purity="$(jq -r '.wallhaven.purity // empty' "$AW_CONFIG_FILE")"
    sorting="$(jq -r '.wallhaven.sorting // empty' "$AW_CONFIG_FILE")"
    order="$(jq -r '.wallhaven.order // empty' "$AW_CONFIG_FILE")"
    atleast="$(jq -r '.wallhaven.atleast // empty' "$AW_CONFIG_FILE")"
    page_size="$(jq -r '.wallhaven.page_size // empty' "$AW_CONFIG_FILE")"

    if [[ -n "$categories" ]]; then
        [[ "$categories" =~ ^[01]{3}$ ]] ||
            aurelia_wallpaper_fail "wallhaven.categories must be three 0/1 digits."
        AW_CFG_WALLHAVEN_CATEGORIES="$categories"
    fi
    if [[ -n "$purity" ]]; then
        [[ "$purity" =~ ^[01]{3}$ ]] ||
            aurelia_wallpaper_fail "wallhaven.purity must be three 0/1 digits."
        AW_CFG_WALLHAVEN_PURITY="$purity"
    fi
    if [[ -n "$sorting" ]]; then
        case "$sorting" in
            relevance|date_added|views|favorites|toplist|hot|random) AW_CFG_WALLHAVEN_SORTING="$sorting" ;;
            *) aurelia_wallpaper_fail "Unsupported wallhaven.sorting value: $sorting" ;;
        esac
    fi
    if [[ -n "$order" ]]; then
        case "$order" in
            desc|asc) AW_CFG_WALLHAVEN_ORDER="$order" ;;
            *) aurelia_wallpaper_fail "Unsupported wallhaven.order value: $order" ;;
        esac
    fi
    if [[ -n "$atleast" ]]; then
        [[ "$atleast" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]] ||
            aurelia_wallpaper_fail "wallhaven.atleast must look like 1920x1080."
        AW_CFG_WALLHAVEN_ATLEAST="$atleast"
    fi
    if [[ -n "$page_size" ]]; then
        [[ "$page_size" =~ ^[0-9]+$ && "$page_size" -ge 4 && "$page_size" -le 48 ]] ||
            aurelia_wallpaper_fail "wallhaven.page_size must be between 4 and 48."
        AW_CFG_WALLHAVEN_PAGE_SIZE="$page_size"
    fi
}

aurelia_wallpaper_source_rows() {
    local exists="0"
    local index

    if [[ -d "$AW_CFG_LIBRARY" ]]; then
        exists="1"
    fi
    printf '%s\t%s\t%s\t%s\n' "library" "library" "$AW_CFG_LIBRARY" "$exists"

    for index in ${AW_CFG_SOURCE_IDS[@]+"${!AW_CFG_SOURCE_IDS[@]}"}; do
        exists="0"
        if [[ -d "${AW_CFG_SOURCE_PATHS[$index]}" ]]; then
            exists="1"
        fi
        printf '%s\t%s\t%s\t%s\n' \
            "${AW_CFG_SOURCE_IDS[$index]}" \
            "configured" \
            "${AW_CFG_SOURCE_PATHS[$index]}" \
            "$exists"
    done

    printf '%s\t%s\t%s\t%s\n' "wallhaven" "remote" "https://wallhaven.cc" "1"
    printf '%s\t%s\t%s\t%s\n' "catalog" "remote" "https://bjarneo.github.io/wallpapers" "1"
}

aurelia_wallpaper_source_record() {
    local requested="$1"
    local row=""

    while IFS= read -r row; do
        if [[ "$(cut -f1 <<<"$row")" == "$requested" ]]; then
            printf '%s\n' "$row"
            return 0
        fi
    done < <(aurelia_wallpaper_source_rows)
    return 1
}

aurelia_wallpaper_source_path_for() {
    local record=""

    record="$(aurelia_wallpaper_source_record "$1")" ||
        aurelia_wallpaper_fail "Unknown wallpaper source: $1"
    [[ "$(cut -f2 <<<"$record")" != "remote" ]] ||
        aurelia_wallpaper_fail "Wallpaper source is not a local directory: $1"
    cut -f3 <<<"$record"
}

aurelia_wallpaper_source_enabled() {
    local requested="$1"
    local index

    if [[ "$requested" == "library" || "$requested" == "wallhaven" || "$requested" == "catalog" ]]; then
        return 0
    fi
    for index in ${AW_CFG_SOURCE_IDS[@]+"${!AW_CFG_SOURCE_IDS[@]}"}; do
        if [[ "${AW_CFG_SOURCE_IDS[$index]}" == "$requested" ]]; then
            aurelia_wallpaper_setting_is_true "${AW_CFG_SOURCE_ENABLED[$index]}"
            return
        fi
    done
    return 1
}
# Append a bounded provenance record for a published remote download. The log
# lives in the regenerable cache and is capped so it can never grow unbounded.
aurelia_wallpaper_record_download() {
    local provider="$1"
    local remote_id="$2"
    local source_url="$3"
    local destination="$4"
    local digest="$5"
    local page_url="$6"
    local document="[]"

    [[ -f "$AW_DOWNLOAD_LOG" && ! -L "$AW_DOWNLOAD_LOG" ]] &&
        document="$(jq -c 'if type == "array" then . else [] end' "$AW_DOWNLOAD_LOG" || printf '[]')"

    document="$(jq -c \
        --arg provider "$provider" \
        --arg id "$remote_id" \
        --arg source "$source_url" \
        --arg destination "$destination" \
        --arg sha256 "$digest" \
        --arg page "$page_url" \
        --argjson limit "$AW_WALLHAVEN_LOG_LIMIT" \
        '. + [{provider:$provider,id:$id,source:$source,destination:$destination,sha256:$sha256,page:$page}]
         | if length > $limit then .[(length - $limit):] else . end' \
        <<<"$document" || true)"
    [[ -n "$document" ]] ||
        aurelia_wallpaper_fail "Could not record the download provenance."

    aurelia_wallpaper_atomic_text "$document" "$AW_DOWNLOAD_LOG" ||
        aurelia_wallpaper_fail "Could not write the download provenance log."
}

aurelia_wallpaper_config_write() {
    local document="$1"

    aurelia_wallpaper_prepare_config || return 1
    jq -e 'type == "object"' <<<"$document" >/dev/null ||
        aurelia_wallpaper_fail "Refusing to write a non-object wallpaper configuration."
    aurelia_wallpaper_atomic_text "$document" "$AW_CONFIG_FILE"
}

# One bounded HTTPS fetch with a single failure classification. Timeouts stay
# distinguishable from an unavailable resource, an HTTP error, and a transport
# error so callers never report a misleading cause.
aurelia_wallpaper_http_fetch() {
    local url="$1"
    local destination="$2"
    local request_timeout="$3"
    local max_bytes="$4"
    local allowed_hosts="${5:-$AW_WALLHAVEN_ALLOWED_HOSTS}"
    local error_file="${destination}.err"
    local effective=""
    local rc=0

    AW_HTTP_FAILURE_CLASS=""
    AW_HTTP_EFFECTIVE_URL=""

    [[ "$url" == https://* ]] ||
        {
            AW_HTTP_FAILURE_CLASS="insecure-url"
            aurelia_wallpaper_fail "Refusing to fetch a non-HTTPS URL: $url"
            return 1
        }

    effective="$(
        "$AW_TIMEOUT_BIN" -k 5 "$request_timeout" "$AW_CURL_BIN" \
            --silent --show-error --location --max-redirs 3 \
            --proto '=https' --proto-redir '=https' \
            --connect-timeout "$AW_CONNECT_TIMEOUT" --max-time "$request_timeout" \
            --max-filesize "$max_bytes" --user-agent "$AW_USER_AGENT" \
            --output "$destination" --write-out '%{url_effective}' \
            "$url" 2>"$error_file"
    )" || rc=$?

    if [[ "$rc" -ne 0 ]]; then
        local detail=""
        detail="$(tr -d '\r' <"$error_file" | tail -n 1)"
        rm -f -- "$error_file"
        # Classification only: the caller owns the message and the staging
        # cleanup, so a failed fetch never leaves temp files behind.
        case "$rc" in
            124|137)
                AW_HTTP_FAILURE_CLASS="timeout"
                AW_HTTP_FAILURE_MESSAGE="Request timed out after ${request_timeout}s: $url"
                ;;
            63)
                AW_HTTP_FAILURE_CLASS="too-large"
                AW_HTTP_FAILURE_MESSAGE="Response exceeds the maximum allowed size: $url"
                ;;
            22)
                AW_HTTP_FAILURE_CLASS="http-error"
                AW_HTTP_FAILURE_MESSAGE="Server rejected the request${detail:+: $detail}"
                ;;
            6)
                AW_HTTP_FAILURE_CLASS="not-resolved"
                AW_HTTP_FAILURE_MESSAGE="Host could not be resolved: $url"
                ;;
            60|77|83)
                AW_HTTP_FAILURE_CLASS="tls-error"
                AW_HTTP_FAILURE_MESSAGE="TLS verification failed for: $url"
                ;;
            *)
                AW_HTTP_FAILURE_CLASS="transport-error"
                AW_HTTP_FAILURE_MESSAGE="Request failed (curl exit $rc)${detail:+: $detail}"
                ;;
        esac
        return 1
    fi

    rm -f -- "$error_file"
    AW_HTTP_EFFECTIVE_URL="$effective"

    if ! aurelia_wallpaper_host_allowed "$effective" "$allowed_hosts"; then
        AW_HTTP_FAILURE_CLASS="unexpected-host"
        AW_HTTP_FAILURE_MESSAGE="Response came from a non-allowlisted host: $effective"
        return 1
    fi

    return 0
}

aurelia_wallpaper_url_extension() {
    local url="$1"
    local path="${url%%\?*}"
    local name="${path##*/}"
    local extension="${name##*.}"

    extension="$(LC_ALL=C printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
    case "$extension" in
        jpg|jpeg|png|gif|bmp|webp) printf '%s\n' "$extension" ;;
        *) return 1 ;;
    esac
}

# Fetch a remote image into a validated staging path, then publish it
# atomically. The download is bounded in time and bytes, and the published file
# must pass both a size floor and an image signature check.
aurelia_wallpaper_fetch_image() {
    local url="$1"
    local destination="$2"
    local allowed_hosts="${3:-$AW_WALLHAVEN_ALLOWED_HOSTS}"
    local extension=""
    local staging=""
    local size="0"

    AW_FETCHED_SHA256=""

    aurelia_wallpaper_host_allowed "$url" "$allowed_hosts" ||
        aurelia_wallpaper_fail "Refusing to download from a non-allowlisted host: $url"
    extension="$(aurelia_wallpaper_url_extension "$url"  || true)"
    [[ -n "$extension" ]] ||
        aurelia_wallpaper_fail "Remote image URL has an unsupported extension: $url"

    aurelia_wallpaper_prepare_cache || return 1
    staging="$(mktemp "$AW_DOWNLOAD_ROOT/wallpaper-XXXXXX.$extension")" ||
        aurelia_wallpaper_fail "Could not create wallpaper download staging file."

    if ! aurelia_wallpaper_http_fetch "$url" "$staging" \
        "$AW_DOWNLOAD_TIMEOUT" "$AW_MAX_DOWNLOAD_BYTES" "$allowed_hosts"; then
        # A refused or partial download is never published.
        local failure_message="${AW_HTTP_FAILURE_MESSAGE:-Request failed: $url}"
        rm -f -- "$staging"
        aurelia_wallpaper_fail "$failure_message"
        return 1
    fi

    size="$(stat -c '%s' -- "$staging" || printf '0')"
    if [[ ! "$size" =~ ^[0-9]+$ ]] || (( size < AW_MIN_DOWNLOAD_BYTES )); then
        rm -f -- "$staging"
        aurelia_wallpaper_fail "Downloaded file is implausibly small (${size} bytes): $url"
        return 1
    fi
    if (( size > AW_MAX_DOWNLOAD_BYTES )); then
        rm -f -- "$staging"
        aurelia_wallpaper_fail "Downloaded file exceeds the size limit: $url"
        return 1
    fi
    if ! aurelia_wallpaper_signature_matches "$staging"; then
        rm -f -- "$staging"
        aurelia_wallpaper_fail "Downloaded file is not a valid image: $url"
        return 1
    fi

    AW_FETCHED_SHA256="$(aurelia_wallpaper_sha256 "$staging")" || {
        rm -f -- "$staging"
        return 1
    }
    aurelia_wallpaper_atomic_move "$staging" "$destination"
}
