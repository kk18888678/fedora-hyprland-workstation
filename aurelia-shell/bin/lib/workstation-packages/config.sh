#!/usr/bin/env bash

# Safe, declarative configuration for the package manager.
#
# Configuration is deliberately parsed instead of sourced. A package-manager
# preference file must not be able to execute shell code, replace functions, or
# alter the process environment. Repository defaults are loaded first and an
# optional user override is loaded second.

# Configuration values are consumed by the other sourced package-manager
# modules; ShellCheck cannot infer that cross-file ownership boundary.
# shellcheck disable=SC2034,SC2094

wsp_config_trim() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

wsp_config_unquote() {
    local value="$1"

    if [[ "$value" == '"'*'"' && ${#value} -ge 2 ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "$value" == "'*'" && ${#value} -ge 2 ]]; then
        value="${value:1:${#value}-2}"
    fi
    printf '%s' "$value"
}

wsp_config_valid_uint() {
    local value="$1"
    local minimum="${2:-0}"
    local maximum="${3:-2147483647}"

    [[ "$value" =~ ^[0-9]+$ && "$value" -ge "$minimum" && "$value" -le "$maximum" ]]
}

wsp_config_valid_duration() {
    # Keep the accepted systemd duration vocabulary intentionally small and
    # unambiguous. Compound durations are unnecessary for these settings.
    [[ "${1:-}" =~ ^[0-9]+(s|m|min|h|d)$ ]]
}

wsp_config_valid_key() {
    # This is the fzf key grammar subset used by the package-manager UI.
    # Reject whitespace, shell metacharacters, and binding separators.
    [[ "${1:-}" =~ ^[A-Za-z0-9?+=/_.-]{1,32}$ ]]
}

wsp_config_valid_preview_window() {
    [[ "${1:-}" =~ ^[A-Za-z0-9%:+._-]{1,64}$ ]]
}

wsp_config_valid_color_spec() {
    [[ "${1:-}" =~ ^[A-Za-z0-9#+,:._-]{1,256}$ ]]
}

wsp_config_valid_display_text() {
    local value="${1:-}"

    [[ -n "$value" && ${#value} -le 64 &&
       "$value" != *$'\r'* && "$value" != *$'\n'* && "$value" != *$'\t'* ]]
}

wsp_config_defaults() {
    WSP_CFG_CATALOG_STALE_SECONDS=21600
    WSP_CFG_CATALOG_BOOT_DELAY=45s
    WSP_CFG_CATALOG_REFRESH_INTERVAL=6h
    WSP_CFG_CATALOG_REFRESH_JITTER=5m
    WSP_CFG_CATALOG_RESULT_LIMIT=250
    WSP_CFG_DNF_METADATA_TIMEOUT=240
    WSP_CFG_DNF_RESOLVE_TIMEOUT=30
    WSP_CFG_FLATPAK_METADATA_TIMEOUT=180
    WSP_CFG_TRANSACTION_TIMEOUT=1800
    WSP_CFG_LOCK_WAIT_SECONDS=15

    WSP_CFG_KEY_UP=up
    WSP_CFG_KEY_DOWN=down
    WSP_CFG_KEY_PAGE_UP=pgup
    WSP_CFG_KEY_PAGE_DOWN=pgdn
    WSP_CFG_KEY_SELECT=tab
    WSP_CFG_KEY_ACCEPT=enter
    WSP_CFG_KEY_CANCEL=esc
    WSP_CFG_KEY_REFRESH=ctrl-r
    WSP_CFG_KEY_HELP='?'
    WSP_CFG_KEY_PREVIEW_TOGGLE=alt-p
    WSP_CFG_KEY_PREVIEW_UP=alt-k
    WSP_CFG_KEY_PREVIEW_DOWN=alt-j
    WSP_CFG_KEY_SELECT_ALL=ctrl-a
    WSP_CFG_KEY_SEARCH=/
    WSP_CFG_KEY_QUEUE=a
    WSP_CFG_KEY_SOURCE=s
    WSP_CFG_KEY_INFO=i
    WSP_CFG_KEY_VERSIONS=v
    WSP_CFG_KEY_ADD_SOURCE=+
    WSP_CFG_KEY_QUIT=q
    WSP_CFG_KEY_FILTER_NEXT=right
    WSP_CFG_KEY_FILTER_PREVIOUS=left
    WSP_CFG_KEY_SORT=o
    WSP_CFG_KEY_SORT_REVERSE=O

    WSP_CFG_TUI_PREVIEW_WINDOW=down:40%:wrap
    WSP_CFG_TUI_HEIGHT=100%
    WSP_CFG_TUI_COLOR=pointer:green,marker:green,header:cyan:bold,border:blue
    WSP_CFG_TUI_BORDER=rounded
    WSP_CFG_TUI_MARGIN=1,2
    WSP_CFG_TUI_PADDING=0,1
    WSP_CFG_TUI_INFO=inline-right
    WSP_CFG_TUI_SCROLL_OFF=0
    WSP_CFG_TUI_TABSTOP=2
    WSP_CFG_TUI_TITLE='Package Manager'
    WSP_CFG_TUI_HEADER_LABEL='Catalog'
    WSP_CFG_TUI_INPUT_LABEL='Search'
    WSP_CFG_TUI_LIST_LABEL='Packages'
    WSP_CFG_TUI_PREVIEW_LABEL='Selected package · metadata'
    WSP_CFG_TUI_FOOTER_LABEL='Keys'
    WSP_CFG_TUI_PROMPT='Search > '
    WSP_CFG_TUI_POINTER='▌'
    WSP_CFG_TUI_MARKER='┃'
}

wsp_config_assign() {
    local key="$1"
    local value="$2"
    local file="$3"
    local line_number="$4"
    local variable=""

    case "$key" in
        catalog_stale_seconds)
            wsp_config_valid_uint "$value" 60 604800 || {
                wsp_error "Invalid catalog_stale_seconds in $file:$line_number"
                return 1
            }
            WSP_CFG_CATALOG_STALE_SECONDS="$value"
            ;;
        catalog_boot_delay)
            wsp_config_valid_duration "$value" || {
                wsp_error "Invalid catalog_boot_delay in $file:$line_number"
                return 1
            }
            WSP_CFG_CATALOG_BOOT_DELAY="$value"
            ;;
        catalog_refresh_interval)
            wsp_config_valid_duration "$value" || {
                wsp_error "Invalid catalog_refresh_interval in $file:$line_number"
                return 1
            }
            WSP_CFG_CATALOG_REFRESH_INTERVAL="$value"
            ;;
        catalog_refresh_jitter)
            wsp_config_valid_duration "$value" || {
                wsp_error "Invalid catalog_refresh_jitter in $file:$line_number"
                return 1
            }
            WSP_CFG_CATALOG_REFRESH_JITTER="$value"
            ;;
        catalog_result_limit)
            wsp_config_valid_uint "$value" 1 10000 || {
                wsp_error "Invalid catalog_result_limit in $file:$line_number"
                return 1
            }
            WSP_CFG_CATALOG_RESULT_LIMIT="$value"
            ;;
        dnf_metadata_timeout)
            wsp_config_valid_uint "$value" 10 1800 || {
                wsp_error "Invalid dnf_metadata_timeout in $file:$line_number"
                return 1
            }
            WSP_CFG_DNF_METADATA_TIMEOUT="$value"
            ;;
        dnf_resolve_timeout)
            wsp_config_valid_uint "$value" 5 300 || {
                wsp_error "Invalid dnf_resolve_timeout in $file:$line_number"
                return 1
            }
            WSP_CFG_DNF_RESOLVE_TIMEOUT="$value"
            ;;
        flatpak_metadata_timeout)
            wsp_config_valid_uint "$value" 10 1800 || {
                wsp_error "Invalid flatpak_metadata_timeout in $file:$line_number"
                return 1
            }
            WSP_CFG_FLATPAK_METADATA_TIMEOUT="$value"
            ;;
        transaction_timeout)
            wsp_config_valid_uint "$value" 60 7200 || {
                wsp_error "Invalid transaction_timeout in $file:$line_number"
                return 1
            }
            WSP_CFG_TRANSACTION_TIMEOUT="$value"
            ;;
        lock_wait_seconds)
            wsp_config_valid_uint "$value" 0 120 || {
                wsp_error "Invalid lock_wait_seconds in $file:$line_number"
                return 1
            }
            WSP_CFG_LOCK_WAIT_SECONDS="$value"
            ;;
        key_*)
            variable="WSP_CFG_KEY_${key#key_}"
            variable="${variable^^}"
            [[ -n "${!variable+x}" ]] || {
                wsp_error "Unknown package-manager key '$key' in $file:$line_number"
                return 1
            }
            wsp_config_valid_key "$value" || {
                wsp_error "Invalid package-manager key '$value' in $file:$line_number"
                return 1
            }
            printf -v "$variable" '%s' "$value"
            ;;
        tui_preview_window)
            wsp_config_valid_preview_window "$value" || {
                wsp_error "Invalid tui_preview_window in $file:$line_number"
                return 1
            }
            WSP_CFG_TUI_PREVIEW_WINDOW="$value"
            ;;
        tui_height)
            [[ "$value" =~ ^[0-9]+%$ ]] || {
                wsp_error "Invalid tui_height in $file:$line_number"
                return 1
            }
            WSP_CFG_TUI_HEIGHT="$value"
            ;;
        tui_color)
            wsp_config_valid_color_spec "$value" || {
                wsp_error "Invalid tui_color in $file:$line_number"
                return 1
            }
            WSP_CFG_TUI_COLOR="$value"
            ;;
        tui_border)
            [[ "$value" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || {
                wsp_error "Invalid tui_border in $file:$line_number"
                return 1
            }
            WSP_CFG_TUI_BORDER="$value"
            ;;
        tui_margin|tui_padding)
            [[ "$value" =~ ^[0-9]+(,[0-9]+){0,3}$ ]] || {
                wsp_error "Invalid $key in $file:$line_number"
                return 1
            }
            if [[ "$key" == tui_margin ]]; then
                WSP_CFG_TUI_MARGIN="$value"
            else
                WSP_CFG_TUI_PADDING="$value"
            fi
            ;;
        tui_info)
            [[ "$value" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || {
                wsp_error "Invalid tui_info in $file:$line_number"
                return 1
            }
            WSP_CFG_TUI_INFO="$value"
            ;;
        tui_scroll_off)
            wsp_config_valid_uint "$value" 0 100 || {
                wsp_error "Invalid tui_scroll_off in $file:$line_number"
                return 1
            }
            WSP_CFG_TUI_SCROLL_OFF="$value"
            ;;
        tui_tabstop)
            wsp_config_valid_uint "$value" 1 16 || {
                wsp_error "Invalid tui_tabstop in $file:$line_number"
                return 1
            }
            WSP_CFG_TUI_TABSTOP="$value"
            ;;
        tui_title|tui_header_label|tui_input_label|tui_list_label|tui_preview_label|tui_footer_label)
            wsp_config_valid_display_text "$value" || {
                wsp_error "Invalid $key in $file:$line_number"
                return 1
            }
            case "$key" in
                tui_title) WSP_CFG_TUI_TITLE="$value" ;;
                tui_header_label) WSP_CFG_TUI_HEADER_LABEL="$value" ;;
                tui_input_label) WSP_CFG_TUI_INPUT_LABEL="$value" ;;
                tui_list_label) WSP_CFG_TUI_LIST_LABEL="$value" ;;
                tui_preview_label) WSP_CFG_TUI_PREVIEW_LABEL="$value" ;;
                tui_footer_label) WSP_CFG_TUI_FOOTER_LABEL="$value" ;;
            esac
            ;;
        tui_prompt|tui_pointer|tui_marker)
            wsp_config_valid_display_text "$value" || {
                wsp_error "Invalid $key in $file:$line_number"
                return 1
            }
            case "$key" in
                tui_prompt) WSP_CFG_TUI_PROMPT="$value" ;;
                tui_pointer) WSP_CFG_TUI_POINTER="$value" ;;
                tui_marker) WSP_CFG_TUI_MARKER="$value" ;;
            esac
            ;;
        *)
            wsp_error "Unknown package-manager setting '$key' in $file:$line_number"
            return 1
            ;;
    esac
}

wsp_config_load_file() {
    local file="$1"
    local line
    local line_number=0
    local key
    local value
    local raw_key

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        line="${line%$'\r'}"
        line="$(wsp_config_trim "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || {
            wsp_error "Malformed package-manager setting in $file:$line_number"
            return 1
        }
        raw_key="${line%%=*}"
        key="$(wsp_config_trim "$raw_key")"
        value="${line#*=}"
        value="$(wsp_config_trim "$value")"
        value="$(wsp_config_unquote "$value")"
        [[ "$key" =~ ^[a-z][a-z0-9_]*$ ]] || {
            wsp_error "Invalid package-manager setting name in $file:$line_number"
            return 1
        }
        wsp_config_assign "$key" "$value" "$file" "$line_number" || return 1
    done < "$file"
}

wsp_config_validate_keys() {
    local key_name
    local variable
    local value
    local -A seen=()

    for key_name in \
        UP DOWN PAGE_UP PAGE_DOWN SELECT ACCEPT CANCEL REFRESH HELP \
        PREVIEW_TOGGLE PREVIEW_UP PREVIEW_DOWN SELECT_ALL SEARCH QUEUE SOURCE \
        INFO VERSIONS ADD_SOURCE QUIT FILTER_NEXT FILTER_PREVIOUS SORT SORT_REVERSE; do
        variable="WSP_CFG_KEY_$key_name"
        value="${!variable}"
        if [[ -n "${seen[$value]+present}" ]]; then
            wsp_error "Package-manager key '$value' is assigned more than once."
            return 1
        fi
        seen["$value"]="$key_name"
    done
}

wsp_config_file_safe() {
    local file="$1"

    [[ "$file" == /* && "$file" != / ]] || return 1
    [[ ! -L "$file" ]] || return 1
    wsp_path_components_safe "$(dirname -- "$file")" || return 1
    [[ ! -e "$file" || -f "$file" ]]
}

wsp_config_load() {
    local config_file="${WSP_CONFIG_FILE:-}"
    local user_config="${WSP_USER_CONFIG_FILE:-}"
    local config_home

    wsp_config_defaults

    [[ -n "$config_file" ]] || {
        wsp_error 'Package-manager repository configuration path is empty.'
        return 1
    }
    wsp_config_file_safe "$config_file" || {
        wsp_error "Unsafe package-manager configuration path: $config_file"
        return 1
    }
    if [[ -e "$config_file" ]]; then
        wsp_config_load_file "$config_file" || return 1
    fi

    if [[ -z "$user_config" ]]; then
        config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
        [[ "$config_home" == /* && "$config_home" != / ]] || {
            wsp_error 'XDG_CONFIG_HOME must be an absolute non-root path for package-manager configuration.'
            return 1
        }
        user_config="$config_home/workstation/package-manager.conf"
    fi
    wsp_config_file_safe "$user_config" || {
        wsp_error "Unsafe user package-manager configuration path: $user_config"
        return 1
    }
    if [[ -e "$user_config" ]]; then
        wsp_config_load_file "$user_config" || return 1
    fi

    wsp_config_validate_keys
}
