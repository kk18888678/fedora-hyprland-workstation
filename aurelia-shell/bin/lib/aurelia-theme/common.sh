#!/usr/bin/env bash

# Shared data-only theme/background state helpers.
#
# Aurelia themes may provide palette data, media, and inert Omarchy-compatible
# metadata. They never provide executable Lua, shell hooks, or arbitrary
# application configuration to the Aurelia runtime.

aurelia_theme_init_paths() {
    local shell_root="$1"
    local home_dir="${HOME:-}"
    local config_home="${XDG_CONFIG_HOME:-$home_dir/.config}"
    local state_home="${XDG_STATE_HOME:-$home_dir/.local/state}"
    local cache_home="${XDG_CACHE_HOME:-$home_dir/.cache}"

    [[ "$shell_root" == /* && "$shell_root" != "/" ]] ||
        aurelia_theme_fail "Aurelia shell root must be an absolute non-root path."
    [[ "$config_home" == /* && "$config_home" != "/" ]] ||
        aurelia_theme_fail "XDG_CONFIG_HOME must be an absolute non-root path."
    [[ "$state_home" == /* && "$state_home" != "/" ]] ||
        aurelia_theme_fail "XDG_STATE_HOME must be an absolute non-root path."
    [[ "$cache_home" == /* && "$cache_home" != "/" ]] ||
        aurelia_theme_fail "XDG_CACHE_HOME must be an absolute non-root path."

    AURELIA_THEME_SHELL_ROOT="$shell_root"
    AURELIA_THEME_BUILTIN_ROOT="${AURELIA_THEMES_DIR:-$shell_root/themes}"
    [[ "$AURELIA_THEME_BUILTIN_ROOT" == /* && "$AURELIA_THEME_BUILTIN_ROOT" != "/" ]] ||
        aurelia_theme_fail "AURELIA_THEMES_DIR must be an absolute non-root path."
    AURELIA_THEME_USER_ROOT="$config_home/aurelia/themes"
    AURELIA_THEME_USER_BACKGROUND_ROOT="$config_home/aurelia/backgrounds"
    AURELIA_THEME_STATE_ROOT="$state_home/aurelia/current"
    AURELIA_THEME_CACHE_HOME="$cache_home"
    AURELIA_THEME_CACHE_ROOT="$cache_home/aurelia"
    AURELIA_THEME_PREVIEW_CACHE_ROOT="$cache_home/aurelia/theme-selector/previews"
    AURELIA_THEME_THUMBNAIL_CACHE_ROOT="$cache_home/aurelia/image-selector"
    AURELIA_THEME_NAME_PATH="$AURELIA_THEME_STATE_ROOT/theme.name"
    AURELIA_THEME_ACTIVE_PATH="$AURELIA_THEME_STATE_ROOT/theme.conf"
    AURELIA_THEME_ACTIVE_COLORS_PATH="$AURELIA_THEME_STATE_ROOT/colors.toml"
    AURELIA_THEME_ACTIVE_SHELL_PATH="$AURELIA_THEME_STATE_ROOT/shell.toml"
    AURELIA_THEME_BACKGROUND_PATH="$AURELIA_THEME_STATE_ROOT/background.path"
    AURELIA_THEME_LEGACY_NOCTALIA_PATH="$state_home/noctalia/settings.toml"
}

aurelia_theme_fail() {
    printf 'Error: %s\n' "$1" >&2
    return 1
}

aurelia_theme_usage() {
    cat >&2 <<'USAGE'
Usage: aurelia-theme <list|catalog|current|set> [argument]

  list                 List available data-only themes.
  catalog --json       Emit themes and metadata as JSON.
  current              Show the active theme.
  set <theme-name>     Activate a bundled or user theme.
USAGE
}

aurelia_theme_bg_usage() {
    cat >&2 <<'USAGE'
Usage: aurelia-theme-bg <set|current|next|list> [path|--json]

  set <path>           Activate an image or video background.
  current              Show the active background path.
  next                 Cycle to the next background for the active theme.
  list [--json]        List backgrounds for the active theme.
USAGE
}

aurelia_theme_normalize_name() {
    local raw="$1"
    local slug

    [[ -n "$raw" && "$raw" != *'/'* && "$raw" != *'..'* ]] ||
        return 1
    slug="$(LC_ALL=C printf '%s' "$raw" |
        tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9._+-]+/-/g; s/^-+//; s/-+$//')"
    [[ "$slug" =~ ^[a-z0-9][a-z0-9._+-]*$ && "$slug" != *'..'* ]] || return 1
    printf '%s\n' "$slug"
}

aurelia_theme_display_name() {
    printf '%s\n' "$1" | sed -E 's/(^|-)([a-z])/\1\U\2/g; s/-/ /g; s/_/ /g'
}

aurelia_theme_source_dir() {
    local slug="$1"

    if [[ "$slug" == "default" ]]; then
        printf '%s\n' "$AURELIA_THEME_SHELL_ROOT"
    elif [[ -d "$AURELIA_THEME_USER_ROOT/$slug" && ! -L "$AURELIA_THEME_USER_ROOT/$slug" ]]; then
        printf '%s\n' "$AURELIA_THEME_USER_ROOT/$slug"
    elif [[ -d "$AURELIA_THEME_BUILTIN_ROOT/$slug" && ! -L "$AURELIA_THEME_BUILTIN_ROOT/$slug" ]]; then
        printf '%s\n' "$AURELIA_THEME_BUILTIN_ROOT/$slug"
    else
        return 1
    fi
}

# Return the user and packaged roots independently. Keeping these helpers
# separate lets the catalog and background selector implement Omarchy's
# stock-then-overlay behavior without making a user directory blindly replace
# the packaged theme.
aurelia_theme_user_dir() {
    local slug="$1"

    if [[ -d "$AURELIA_THEME_USER_ROOT/$slug" && ! -L "$AURELIA_THEME_USER_ROOT/$slug" ]]; then
        printf '%s\n' "$AURELIA_THEME_USER_ROOT/$slug"
    else
        return 1
    fi
}

aurelia_theme_builtin_dir() {
    local slug="$1"

    if [[ -d "$AURELIA_THEME_BUILTIN_ROOT/$slug" && ! -L "$AURELIA_THEME_BUILTIN_ROOT/$slug" ]]; then
        printf '%s\n' "$AURELIA_THEME_BUILTIN_ROOT/$slug"
    else
        return 1
    fi
}

aurelia_theme_source_file() {
    local theme_dir="$1"
    local candidate
    local slug="${theme_dir##*/}"
    local directory
    local -a directories=()

    if [[ "$slug" == "default" ]]; then
        directories+=("$AURELIA_THEME_SHELL_ROOT")
    else
        local user_dir=""
        local builtin_dir=""
        user_dir="$(aurelia_theme_user_dir "$slug" 2>/dev/null || true)"
        builtin_dir="$(aurelia_theme_builtin_dir "$slug" 2>/dev/null || true)"
        [[ -n "$user_dir" ]] && directories+=("$user_dir")
        [[ -n "$builtin_dir" ]] && directories+=("$builtin_dir")
        [[ -n "$theme_dir" ]] && directories+=("$theme_dir")
    fi

    # colors.toml is the canonical Omarchy format. Prefer it over the older
    # Aurelia-only theme.conf when both are present, so a compatibility file
    # cannot shadow an exact stock palette.
    for directory in "${directories[@]}"; do
        for candidate in colors.toml theme.conf; do
            if [[ -f "$directory/$candidate" && ! -L "$directory/$candidate" ]]; then
                printf '%s\n' "$directory/$candidate"
                return 0
            fi
        done
    done
    return 1
}

aurelia_theme_shell_source_file() {
    local slug="$1"
    local user_dir=""
    local builtin_dir=""
    local directory

    if [[ "$slug" == "default" ]]; then
        return 1
    fi

    user_dir="$(aurelia_theme_user_dir "$slug" 2>/dev/null || true)"
    builtin_dir="$(aurelia_theme_builtin_dir "$slug" 2>/dev/null || true)"
    for directory in "$user_dir" "$builtin_dir"; do
        [[ -n "$directory" ]] || continue
        if [[ -f "$directory/shell.toml" && ! -L "$directory/shell.toml" ]]; then
            printf '%s\n' "$directory/shell.toml"
            return 0
        fi
    done
    return 1
}

aurelia_theme_shell_override_file() {
    local slug="$1"
    local section="$2"
    local user_dir=""
    local builtin_dir=""
    local directory
    local candidate

    [[ "$section" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
    user_dir="$(aurelia_theme_user_dir "$slug" 2>/dev/null || true)"
    builtin_dir="$(aurelia_theme_builtin_dir "$slug" 2>/dev/null || true)"
    for directory in "$user_dir" "$builtin_dir"; do
        [[ -n "$directory" ]] || continue
        candidate="$directory/shell.$section.toml"
        [[ -f "$candidate" && ! -L "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

aurelia_theme_asset_path() {
    local slug="$1"
    local asset="$2"
    local user_dir=""
    local builtin_dir=""
    local directory

    [[ "$asset" =~ ^[A-Za-z0-9._-]+$ ]] || return 1

    user_dir="$(aurelia_theme_user_dir "$slug" 2>/dev/null || true)"
    builtin_dir="$(aurelia_theme_builtin_dir "$slug" 2>/dev/null || true)"
    for directory in "$user_dir" "$builtin_dir"; do
        [[ -n "$directory" ]] || continue
        if [[ -f "$directory/$asset" && ! -L "$directory/$asset" ]]; then
            printf '%s\n' "$directory/$asset"
            return 0
        fi
    done

    return 1
}

aurelia_theme_preview_path() {
    local slug="$1"
    local user_dir=""
    local builtin_dir=""
    local directory
    local asset
    local -a preview_names=(
        preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp
        preview.mp4 preview.m4v preview.mov preview.webm preview.mkv preview.avi
    )

    user_dir="$(aurelia_theme_user_dir "$slug" 2>/dev/null || true)"
    builtin_dir="$(aurelia_theme_builtin_dir "$slug" 2>/dev/null || true)"
    for directory in "$user_dir" "$builtin_dir"; do
        [[ -n "$directory" ]] || continue
        for asset in "${preview_names[@]}"; do
            if [[ -f "$directory/$asset" && ! -L "$directory/$asset" ]]; then
                printf '%s\n' "$directory/$asset"
                return 0
            fi
        done
    done

    # Omarchy falls back to the first sorted background when a theme does not
    # ship a dedicated preview. Keep that useful selector behavior for custom
    # Aurelia themes and stock overlays as well.
    local theme_dir=""
    local -a backgrounds=()
    theme_dir="$(aurelia_theme_source_dir "$slug" 2>/dev/null || true)"
    if [[ -n "$theme_dir" ]]; then
        mapfile -d '' -t backgrounds < <(aurelia_theme_collect_backgrounds "$slug" "$theme_dir")
        if [[ "${#backgrounds[@]}" -gt 0 ]]; then
            printf '%s\n' "${backgrounds[0]}"
            return 0
        fi
    fi

    return 1
}

aurelia_theme_list_slugs() {
    {
        if [[ -d "$AURELIA_THEME_USER_ROOT" && ! -L "$AURELIA_THEME_USER_ROOT" ]]; then
            find -P "$AURELIA_THEME_USER_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
        fi
        if [[ -d "$AURELIA_THEME_BUILTIN_ROOT" && ! -L "$AURELIA_THEME_BUILTIN_ROOT" ]]; then
            find -P "$AURELIA_THEME_BUILTIN_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
        fi
        if [[ -f "$AURELIA_THEME_SHELL_ROOT/theme.conf" && ! -L "$AURELIA_THEME_SHELL_ROOT/theme.conf" ]]; then
            printf '%s\n' default
        fi
    } | while IFS= read -r candidate; do
        aurelia_theme_normalize_name "$candidate" || true
    done | LC_ALL=C sort -u
}

aurelia_theme_is_media_path() {
    local path="$1"
    [[ "$path" == /* && "$path" != "/" && "$path" != *$'\n'* && "$path" != *$'\r'* ]] ||
        return 1
    [[ "$path" =~ \.(jpg|jpeg|png|gif|bmp|webp|mp4|m4v|mov|webm|mkv|avi)$ ]]
}

aurelia_theme_resolve_media_path() {
    local path="$1"
    local resolved

    resolved="$(readlink -f -- "$path" 2>/dev/null || true)"
    [[ "$resolved" == /* && "$resolved" != "/" && -f "$resolved" ]] || return 1
    aurelia_theme_is_media_path "$resolved" || return 1
    printf '%s\n' "$resolved"
}

aurelia_theme_collect_backgrounds() {
    local theme_slug="$1"
    local theme_dir="$2"
    local directory
    local user_dir=""
    local builtin_dir=""

    user_dir="$(aurelia_theme_user_dir "$theme_slug" 2>/dev/null || true)"
    builtin_dir="$(aurelia_theme_builtin_dir "$theme_slug" 2>/dev/null || true)"

    # A user theme overlays the packaged theme. The extra background directory
    # is a separate user-owned source, matching Omarchy's documented layout.
    for directory in \
        "$user_dir/backgrounds" \
        "$AURELIA_THEME_USER_BACKGROUND_ROOT/$theme_slug" \
        "$builtin_dir/backgrounds" \
        "$theme_dir/backgrounds"; do
        [[ "$directory" != "/backgrounds" ]] || continue
        [[ -d "$directory" && ! -L "$directory" ]] || continue
        find -P "$directory" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
               -o -iname '*.bmp' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.m4v' \
               -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \) \
            -print0
    done | LC_ALL=C sort -z -u
}

aurelia_theme_prepare_preview_cache() {
    local cache_parent="${AURELIA_THEME_CACHE_ROOT%/*}"
    local selector_root="${AURELIA_THEME_PREVIEW_CACHE_ROOT%/*}"

    [[ "$cache_parent" == /* && "$cache_parent" != "/" ]] ||
        aurelia_theme_fail "Aurelia cache parent is unsafe."
    [[ ! -L "$AURELIA_THEME_CACHE_HOME" && ! -L "$AURELIA_THEME_CACHE_ROOT" &&
       ! -L "$selector_root" && ! -L "$AURELIA_THEME_PREVIEW_CACHE_ROOT" ]] ||
        aurelia_theme_fail "Aurelia preview cache path must not be a symlink."
    mkdir -p -m 0700 -- "$AURELIA_THEME_PREVIEW_CACHE_ROOT" ||
        aurelia_theme_fail "Could not create Aurelia preview cache."
}

aurelia_theme_prepare_thumbnail_cache() {
    [[ ! -L "$AURELIA_THEME_CACHE_HOME" && ! -L "$AURELIA_THEME_CACHE_ROOT" &&
       ! -L "${AURELIA_THEME_THUMBNAIL_CACHE_ROOT%/*}" &&
       ! -L "$AURELIA_THEME_THUMBNAIL_CACHE_ROOT" ]] ||
        aurelia_theme_fail "Aurelia thumbnail cache path must not be a symlink."
    mkdir -p -m 0700 -- "$AURELIA_THEME_THUMBNAIL_CACHE_ROOT" ||
        aurelia_theme_fail "Could not create Aurelia thumbnail cache."
}

aurelia_theme_cache_preview_link() {
    local source="$1"
    local destination="$2"
    local source_real=""
    local destination_real=""

    [[ "$destination" == "$AURELIA_THEME_PREVIEW_CACHE_ROOT/"* ]] || return 1
    [[ -f "$source" && ! -L "$source" ]] || return 1
    source_real="$(readlink -f -- "$source" 2>/dev/null || true)"
    [[ "$source_real" == /* && -f "$source_real" ]] || return 1

    if [[ -L "$destination" ]]; then
        destination_real="$(readlink -f -- "$destination" 2>/dev/null || true)"
        if [[ "$destination_real" == "$source_real" ]]; then
            return 0
        fi
        rm -f -- "$destination"
    elif [[ -e "$destination" ]]; then
        # A cache entry is generated state. Never overwrite an unexpected
        # regular file merely because its name happens to match a preview.
        return 1
    fi

    ln -s -- "$source_real" "$destination"
}

aurelia_theme_cache_key() {
    local source="$1"
    local signature

    signature="$(stat -Lc '%s:%Y' -- "$source" 2>/dev/null || true)"
    [[ -n "$signature" ]] || return 1
    printf '%s\t%s' "$source" "$signature" | sha256sum | cut -d ' ' -f 1
}

aurelia_theme_thumbnail_for() {
    local source="$1"
    local resolved=""
    local key=""
    local thumbnail=""
    local lock_path=""
    local failed_path=""
    local temporary=""
    local lock_fd
    local status=0
    local timeout_bin=""
    local generator=""

    resolved="$(aurelia_theme_resolve_media_path "$source" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || return 1
    aurelia_theme_prepare_thumbnail_cache
    key="$(aurelia_theme_cache_key "$resolved" 2>/dev/null || true)"
    [[ "$key" =~ ^[0-9a-f]{64}$ ]] || return 1

    thumbnail="$AURELIA_THEME_THUMBNAIL_CACHE_ROOT/$key.jpg"
    lock_path="$thumbnail.lock"
    failed_path="$thumbnail.failed"

    # Still images are already decoded efficiently by Qt and the QML picker
    # activates only nearby cards. Match Omarchy's lazy path: return the source
    # for stills and reserve generated cache work for video frames.
    if [[ ! "$resolved" =~ \.(mp4|m4v|mov|webm|mkv|avi)$ ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi
    generator="ffmpegthumbnailer"

    if [[ -f "$thumbnail" ]]; then
        printf '%s\n' "$thumbnail"
        return 0
    fi
    if [[ "$generator" == "ffmpegthumbnailer" && ! -x "$(command -v ffmpegthumbnailer 2>/dev/null || true)" ]]; then
        return 1
    fi
    [[ ! -L "$thumbnail" && ! -L "$lock_path" && ! -L "$failed_path" ]] || return 1
    [[ ! -f "$failed_path" ]] || return 1

    timeout_bin="$(command -v timeout 2>/dev/null || true)"
    [[ -x "$timeout_bin" ]] || return 1
    exec {lock_fd}>"$lock_path" || return 1
    flock -w 30 "$lock_fd" || return 1
    if [[ -f "$thumbnail" ]]; then
        printf '%s\n' "$thumbnail"
        return 0
    fi

    temporary="$(mktemp "$thumbnail.XXXXXX.jpg")" || return 1
    "$timeout_bin" -k 5 10 ffmpegthumbnailer -i "$resolved" -o "$temporary" -s 1536 -q 8 || status=$?
    if [[ "$status" -eq 0 && -s "$temporary" ]]; then
        mv -f -- "$temporary" "$thumbnail"
        printf '%s\n' "$thumbnail"
        return 0
    fi

    rm -f -- "$temporary"
    # A non-timeout decoder failure is stable for this source signature and
    # should not be repeated on every selector open. Timeouts remain retryable.
    if [[ "$status" -ne 124 && "$status" -ne 137 ]]; then
        : >"$failed_path"
    fi
    return 1
}

aurelia_theme_color_hex() {
    local source="$1"
    local key="$2"
    local fallback="$3"
    local color_bin="$AURELIA_THEME_SHELL_ROOT/bin/aurelia-theme-color"
    local value=""

    if [[ -x "$color_bin" ]]; then
        value="$("$color_bin" --file "$source" "$key" 2>/dev/null || true)"
    fi
    if [[ "$value" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

aurelia_theme_render_shell() {
    local slug="$1"
    local source="$2"
    local background
    local foreground
    local red
    local accent
    local override
    local line
    local key
    local value

    background="$(aurelia_theme_color_hex "$source" background '#232136')"
    foreground="$(aurelia_theme_color_hex "$source" foreground '#e0def4')"
    red="$(aurelia_theme_color_hex "$source" red '#eb6f92')"
    accent="$(aurelia_theme_color_hex "$source" accent '#9ccfd8')"

    printf '%s\n' \
        '# Generated Aurelia shell surface tokens.' \
        '# Theme and user files are data-only; no shell hooks are evaluated.' \
        '[bar]' \
        "background = \"$background\"" \
        'background-alpha = 1.0' \
        "text = \"$foreground\"" \
        "active = \"$red\"" \
        'scale-with-font = true' \
        'size-horizontal = 26' \
        'size-vertical = 28' \
        '' \
        '[controls]' \
        "normal-color = \"$foreground\"" \
        'normal-fill-alpha = 0.04' \
        "normal-border = \"$foreground\"" \
        'normal-border-width = 1' \
        'normal-border-alpha = 0.4' \
        "hover-cursor-color = \"$foreground\"" \
        'hover-cursor-fill-alpha = 0.08' \
        "hover-cursor-border = \"$foreground\"" \
        'hover-cursor-border-width = 1' \
        'hover-cursor-border-alpha = 0.25' \
        "focus-color = \"$foreground\"" \
        'focus-fill-alpha = 0.08' \
        "focus-border = \"$foreground\"" \
        'focus-border-width = 1' \
        'focus-border-alpha = 0.25' \
        "selected-color = \"$foreground\"" \
        'selected-fill-alpha = 0.18' \
        "selected-border = \"$foreground\"" \
        'selected-border-width = 0' \
        'selected-border-alpha = 1.0' \
        'pressed-fill-alpha = 0.22' \
        'selection-fill-alpha = 0.35' \
        '' \
        '[popups]' \
        "background = \"$background\"" \
        'background-alpha = 1.0' \
        "text = \"$foreground\"" \
        "border = \"$accent\"" \
        'border-alpha = 1.0' \
        '' \
        '[tooltip]' \
        "background = \"$background\"" \
        'background-alpha = 0.97' \
        "text = \"$foreground\"" \
        "border = \"$accent\"" \
        'border-alpha = 1.0' \
        '' \
        '[notifications]' \
        "background = \"$background\"" \
        'background-alpha = 1.0' \
        "text = \"$foreground\"" \
        "border = \"$accent\"" \
        'border-alpha = 1.0' \
        "countdown = \"$accent\"" \
        '' \
        '[launcher]' \
        "background = \"$background\"" \
        'background-alpha = 0.95' \
        "text = \"$foreground\"" \
        "border = \"$accent\"" \
        'border-alpha = 1.0' \
        "scrim = \"$background\"" \
        'scrim-alpha = 0.5' \
        "selected-background = \"$foreground\"" \
        'selected-background-alpha = 0.08' \
        "selected-text = \"$accent\"" \
        "selected-border = \"$accent\"" \
        'selected-border-alpha = 0.25' \
        '' \
        '[menu]' \
        "background = \"$background\"" \
        'background-alpha = 1.0' \
        "text = \"$foreground\"" \
        "border = \"$accent\"" \
        'border-alpha = 1.0' \
        "scrim = \"$background\"" \
        'scrim-alpha = 0.5' \
        "selected-background = \"$foreground\"" \
        'selected-background-alpha = 0.08' \
        "selected-text = \"$accent\"" \
        "selected-border = \"$accent\"" \
        'selected-border-alpha = 0.25' \
        '' \
        '[image-picker]' \
        "scrim = \"$background\"" \
        'scrim-alpha = 0.5' \
        "text = \"$foreground\"" \
        "selected-border = \"$accent\"" \
        'selected-border-alpha = 1.0' \
        "unselected-border = \"$foreground\"" \
        'unselected-border-alpha = 0.28'

    # Omarchy names section overrides shell.<section>.toml. Only simple
    # key/value data is accepted here; headers, commands, and substitutions
    # are ignored rather than interpreted.
    for section in lock controls popups tooltip notifications launcher menu image-picker; do
        override="$(aurelia_theme_shell_override_file "$slug" "$section" 2>/dev/null || true)"
        [[ -n "$override" ]] || continue
        printf '\n[%s]\n' "$section"
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -n "$line" && "$line" != \#* ]] || continue
            [[ "$line" =~ ^([A-Za-z0-9_-]+)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            [[ "$value" != *$'\t'* && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || continue
            [[ "$value" =~ ^[A-Za-z0-9#(),._+/%\ -]+$|^\"[A-Za-z0-9#(),._+/%\ -]+\"$ ]] || continue
            printf '%s = %s\n' "$key" "$value"
        done <"$override"
    done
}

aurelia_theme_atomic_shell() {
    local slug="$1"
    local source="$2"
    local destination="$AURELIA_THEME_ACTIVE_SHELL_PATH"
    local temporary
    local full_source=""

    [[ ! -e "$destination" || ! -L "$destination" ]] ||
        aurelia_theme_fail "Refusing to replace symlinked theme shell state: $destination"
    temporary="$(mktemp "${destination}.XXXXXX")" ||
        aurelia_theme_fail "Could not create theme shell staging file."

    full_source="$(aurelia_theme_shell_source_file "$slug" 2>/dev/null || true)"
    if [[ -n "$full_source" ]]; then
        if ! cp -- "$full_source" "$temporary"; then
            rm -f -- "$temporary"
            aurelia_theme_fail "Could not stage theme shell data."
        fi
    elif ! aurelia_theme_render_shell "$slug" "$source" >"$temporary"; then
        rm -f -- "$temporary"
        aurelia_theme_fail "Could not generate theme shell data."
    fi
    chmod 0600 -- "$temporary"
    mv -f -- "$temporary" "$destination"
}

aurelia_theme_prepare_state() {
    umask 077
    local state_parent="${AURELIA_THEME_STATE_ROOT%/*}"

    [[ "$state_parent" == /* && "$state_parent" != "/" ]] ||
        aurelia_theme_fail "Aurelia state parent is unsafe."
    [[ ! -L "$state_parent" && ! -L "$AURELIA_THEME_STATE_ROOT" ]] ||
        aurelia_theme_fail "Aurelia theme state path must not be a symlink."
    mkdir -p -m 0700 -- "$AURELIA_THEME_STATE_ROOT" ||
        aurelia_theme_fail "Could not create Aurelia theme state."
}

aurelia_theme_lock_state() {
    local lock_path="$AURELIA_THEME_STATE_ROOT/.theme.lock"

    [[ ! -L "$lock_path" && (! -e "$lock_path" || -f "$lock_path") ]] ||
        aurelia_theme_fail "Aurelia theme lock path is unsafe."
    exec 9>"$lock_path" ||
        aurelia_theme_fail "Could not open Aurelia theme lock."
    flock -x 9 ||
        aurelia_theme_fail "Could not acquire Aurelia theme lock."
}

aurelia_theme_atomic_copy() {
    local source="$1"
    local destination="$2"
    local temporary

    [[ -f "$source" && ! -L "$source" ]] ||
        aurelia_theme_fail "Theme source is not a regular file: $source"
    [[ ! -e "$destination" || ! -L "$destination" ]] ||
        aurelia_theme_fail "Refusing to replace symlinked theme state: $destination"

    temporary="$(mktemp "${destination}.XXXXXX")" ||
        aurelia_theme_fail "Could not create theme staging file."
    if ! cp -- "$source" "$temporary"; then
        rm -f -- "$temporary"
        aurelia_theme_fail "Could not stage theme data."
    fi
    chmod 0600 -- "$temporary"
    mv -f -- "$temporary" "$destination"
}

aurelia_theme_atomic_text() {
    local content="$1"
    local destination="$2"
    local temporary

    [[ ! -e "$destination" || ! -L "$destination" ]] ||
        aurelia_theme_fail "Refusing to replace symlinked theme state: $destination"
    temporary="$(mktemp "${destination}.XXXXXX")" ||
        aurelia_theme_fail "Could not create theme state staging file."
    if ! printf '%s\n' "$content" >"$temporary"; then
        rm -f -- "$temporary"
        aurelia_theme_fail "Could not stage theme state."
    fi
    chmod 0600 -- "$temporary"
    mv -f -- "$temporary" "$destination"
}

aurelia_theme_current_slug() {
    local slug=""
    if [[ -f "$AURELIA_THEME_NAME_PATH" && ! -L "$AURELIA_THEME_NAME_PATH" ]]; then
        slug="$(sed -n '1p' "$AURELIA_THEME_NAME_PATH")"
        slug="$(aurelia_theme_normalize_name "$slug" 2>/dev/null || true)"
    fi
    printf '%s\n' "${slug:-default}"
}

aurelia_theme_legacy_background() {
    local legacy_path="$AURELIA_THEME_LEGACY_NOCTALIA_PATH"
    local line
    local in_last=0

    [[ -f "$legacy_path" && ! -L "$legacy_path" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "[wallpaper.last]" ]]; then
            in_last=1
            continue
        fi
        if [[ "$in_last" -eq 1 && "$line" == \[*\] ]]; then
            break
        fi
        if [[ "$in_last" -eq 1 && "$line" =~ ^[[:space:]]*path[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            aurelia_theme_resolve_media_path "${BASH_REMATCH[1]}"
            return
        fi
    done <"$legacy_path"
    return 1
}

aurelia_theme_notify_shell() {
    AURELIA_THEME_LIVE_RELOAD_RESULT="unavailable"
    if [[ "${WORKSTATION_TEST_MODE:-0}" == "1" ]]; then
        AURELIA_THEME_LIVE_RELOAD_RESULT="test-skipped"
        return 0
    fi

    local client="$AURELIA_THEME_SHELL_ROOT/bin/aurelia-shell"
    if [[ ! -x "$client" ]]; then
        client="$(command -v aurelia-shell 2>/dev/null || true)"
    fi
    if [[ ! -x "$client" ]]; then
        printf 'Warning: Aurelia state applied, but the live shell client is unavailable.\n' >&2
        return 0
    fi

    local apply_theme_rc=0
    "$client" shell applyTheme >/dev/null 2>&1 || apply_theme_rc=$?

    if [[ "$apply_theme_rc" -eq 0 ]]; then
        AURELIA_THEME_LIVE_RELOAD_RESULT="ok"
    else
        AURELIA_THEME_LIVE_RELOAD_RESULT="failed"
        printf 'Warning: Aurelia state applied, but live reload failed (applyTheme=%s).\n' \
            "$apply_theme_rc" >&2
    fi
}
