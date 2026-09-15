#!/usr/bin/env bash

# High-value isolated coverage for the package-manager catalog and TUI. No
# real DNF, Flatpak, sudo, systemd, package installation, or repository
# mutation is allowed by this suite.

set -Eeuo pipefail

section "Advanced Package Manager Catalog, TUI, and State Contracts"

fixture="$(mktemp -d)"
repo="$fixture/repo"
mock_bin="$fixture/bin"
home="$fixture/home"
runtime="$fixture/runtime"
cache="$fixture/cache"
diagnostic_log="$fixture/diagnostics.log"
command_output="$fixture/command-output.log"
mkdir -p "$repo/packages" "$mock_bin" "$home" "$runtime" "$cache"
: >"$diagnostic_log"
: >"$command_output"

cleanup_package_manager_advanced_fixture() {
    rm -rf -- "$fixture"
}
trap cleanup_package_manager_advanced_fixture EXIT

cat >"$repo/packages/user-managed.tsv" <<'EOF_MANIFEST'
# schema=2
# provider<TAB>source<TAB>identifier<TAB>scope<TAB>profiles
EOF_MANIFEST
cat >"$repo/packages/sources.tsv" <<'EOF_SOURCES'
# schema=1
# provider<TAB>source<TAB>url<TAB>scope
flatpak	flathub	https://dl.flathub.org/repo/flathub.flatpakrepo	system
EOF_SOURCES
cat >"$repo/packages/aurelia-sources.tsv" <<'EOF_AURELIA'
# schema=1
# source<TAB>github_url<TAB>profiles
EOF_AURELIA

: >"$fixture/rpm-installed"
: >"$fixture/flatpak-installed"

cat >"$mock_bin/rpm" <<'EOF_RPM'
#!/usr/bin/env bash
if [[ "${1:-}" == -q && "${2:-}" == --qf ]]; then
    package="${@: -1}"
    if grep -Fxq -- "$package" "${MOCK_RPM_STATE:?}"; then
        printf '%s\n' 1
        exit 0
    fi
    exit 1
fi
if [[ "${1:-}" == -q ]]; then
    grep -Fxq -- "${2:-}" "${MOCK_RPM_STATE:?}"
    exit $?
fi
exit 2
EOF_RPM

cat >"$mock_bin/dnf5" <<'EOF_DNF'
#!/usr/bin/env bash

args="$*"

if [[ "${MOCK_DNF_FAILURE:-0}" == 1 ]]; then
    printf '%s\n' 'mock dnf metadata failure' >&2
    exit 42
fi

emit_rich() {
    local field=$'\x1f'
    local record=$'\x1e'
    local index
    local -a values=("$@")

    for ((index = 0; index < ${#values[@]}; index++)); do
        (( index > 0 )) && printf '%s' "$field"
        printf '%s' "${values[$index]}"
    done
    printf '%s' "$record"
}

if [[ "$args" == *makecache* ]]; then
    exit 0
fi

if [[ "$args" == *repoquery* && "$args" == *--available* ]]; then
    if [[ "$args" == *--whatprovides* ]]; then
        emit_rich \
            v4l-utils \
            'Utilities for video4linux and DVB devices' \
            $'The v4l-utils package provides the edid-decode command.\nSecond line.' \
            1.32.0-3.fc44 fedora x86_64 1831495 653312 GPL-2.0 \
            https://example.invalid/v4l-utils \
            https://example.invalid/v4l-utils.rpm \
            v4l-utils.src.rpm Fedora Fedora \
            'edid-decode = 1.32.0-3.fc44' libc.so.6 '' '' '' '' '' '' \
            v4l-utils-1.32.0-3.fc44.x86_64 1700000000
    elif [[ "$args" == *%{summary}* ]]; then
        emit_rich \
            v4l-utils \
            'Utilities for video4linux and DVB devices' \
            $'The v4l-utils package provides the edid-decode command.\nSecond line.' \
            1.32.0-3.fc44 fedora x86_64 1831495 653312 GPL-2.0 \
            https://example.invalid/v4l-utils \
            https://example.invalid/v4l-utils.rpm \
            v4l-utils.src.rpm Fedora Fedora \
            'edid-decode = 1.32.0-3.fc44' libc.so.6 '' '' '' '' '' '' \
            v4l-utils-1.32.0-3.fc44.x86_64 1700000000
        emit_rich \
            libreoffice \
            'Free Software Productivity Suite' \
            'LibreOffice provides word processing, spreadsheets, and presentations.' \
            1:26.2.6.3-1.fc44 updates x86_64 500000000 120000000 MPL-2.0 \
            https://www.libreoffice.org \
            https://example.invalid/libreoffice.rpm \
            libreoffice.src.rpm Fedora Fedora \
            'libreoffice = 1:26.2.6.3-1.fc44' java-25-openjdk-headless '' '' '' '' '' '' \
            libreoffice-1:26.2.6.3-1.fc44.x86_64 1700000100
        emit_rich \
            libreoffice \
            'Free Software Productivity Suite' \
            'LibreOffice provides word processing, spreadsheets, and presentations.' \
            1:26.2.1.2-2.fc44 fedora x86_64 400000000 100000000 MPL-2.0 \
            https://www.libreoffice.org \
            https://example.invalid/libreoffice-base.rpm \
            libreoffice-1:26.2.1.2-2.fc44.src.rpm Fedora Fedora \
            'libreoffice = 1:26.2.1.2-2.fc44' java-25-openjdk-headless '' '' '' '' '' '' \
            libreoffice-1:26.2.1.2-2.fc44.x86_64 1699999900
        emit_rich \
            mock-dnf 'A mock DNF package' 'A package used for transaction tests.' \
            1 fedora x86_64 1024 512 MIT \
            https://example.invalid/mock-dnf \
            https://example.invalid/mock-dnf.rpm \
            mock-dnf.src.rpm Test Test \
            'mock-dnf = 1' mock-dependency '' '' '' '' '' '' \
            mock-dnf-1.x86_64 1700000200
        emit_rich \
            ignored-i686 'An i686 package' 'It must not enter an x86_64 catalog.' \
            1 fedora i686 1024 512 MIT \
            https://example.invalid/ignored-i686 \
            https://example.invalid/ignored-i686.rpm \
            ignored-i686.src.rpm Test Test \
            'ignored-i686 = 1' '' '' '' '' '' '' '' \
            ignored-i686-1.i686 1700000300
    else
        package="${@: -1}"
        package="${package%.x86_64}"
        printf '%s\t%s\n' "$package" x86_64
    fi
    exit 0
fi

if [[ "$args" == *repoquery* && "$args" == *--userinstalled* ]]; then
    printf '%s\t%s\t%s\t%s\n' fedora mock-dnf 1 x86_64
    exit 0
fi

if [[ "$args" == *repoquery* && "$args" == *--installed* ]]; then
    printf '%s\n' fedora
    exit 0
fi

if [[ "${1:-}" == install && "${2:-}" == --from-repo=* ]]; then
    package="${@: -1}"
    package="${package%.x86_64}"
    [[ "$package" == mock-dnf-1 ]] && package=mock-dnf
    printf '%s\n' "$package" >>"${MOCK_RPM_STATE:?}"
    exit 0
fi

if [[ "${1:-}" == remove ]]; then
    sed -i "/^${!#}$/d" "${MOCK_RPM_STATE:?}"
    exit 0
fi

exit 2
EOF_DNF

cat >"$mock_bin/flatpak" <<'EOF_FLATPAK'
#!/usr/bin/env bash

args="$*"

if [[ "${1:-}" == remotes ]]; then
    printf '%s\n' flathub
    exit 0
fi

if [[ "${1:-}" == remote-ls ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        org.libreoffice.LibreOffice LibreOffice \
        'The LibreOffice productivity suite' 26.8.0.3 stable x86_64 flathub \
        app/org.libreoffice.LibreOffice/x86_64/stable \
        org.freedesktop.Platform/x86_64/25.08 '650 MB' '250 MB' '' \
        abcdef123456
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        org.example.Catalog 'Catalog App' 'A catalog Flatpak' 1 stable x86_64 flathub \
        app/org.example.Catalog/x86_64/stable \
        org.gnome.Platform/x86_64/50 '100 MB' '40 MB' '' \
        fedcba654321
    exit 0
fi

if [[ "${1:-}" == list ]]; then
    if [[ "$args" == *origin,name,version,branch* ]]; then
        while IFS= read -r identifier; do
            [[ -n "$identifier" ]] || continue
            printf '%s\t%s\t%s\t%s\t%s\n' "$identifier" flathub 'Catalog App' 1 stable
        done <"${MOCK_FLATPAK_STATE:?}"
    else
        cat "${MOCK_FLATPAK_STATE:?}"
    fi
    exit 0
fi

if [[ "${1:-}" == install ]]; then
    printf '%s\n' "${@: -1}" >>"${MOCK_FLATPAK_STATE:?}"
    exit 0
fi

if [[ "${1:-}" == uninstall ]]; then
    sed -i "/^${!#}$/d" "${MOCK_FLATPAK_STATE:?}"
    exit 0
fi

exit 2
EOF_FLATPAK

cat >"$mock_bin/sudo" <<'EOF_SUDO'
#!/usr/bin/env bash
exec "$@"
EOF_SUDO

cat >"$mock_bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
exit 0
EOF_SYSTEMCTL

cat >"$mock_bin/fzf" <<'EOF_FZF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_FZF_LOG:?}"
selected=""
while IFS= read -r line; do
    [[ -n "$selected" ]] || selected="$line"
    [[ "$line" == *v4l-utils* ]] && selected="$line"
done
[[ -n "$selected" ]] && printf '%s\n' "$selected"
EOF_FZF

chmod 0755 "$mock_bin/rpm" "$mock_bin/dnf5" "$mock_bin/flatpak" \
    "$mock_bin/sudo" "$mock_bin/systemctl" "$mock_bin/fzf"

backend="$ROOT/bin/workstation-packages"
test_env=(
    "PATH=$mock_bin:/usr/bin:/bin"
    "HOME=$home"
    "XDG_CONFIG_HOME=$home/.config"
    "XDG_RUNTIME_DIR=$runtime"
    "XDG_CACHE_HOME=$cache"
    "WORKSTATION_PACKAGE_REPO=$repo"
    "MOCK_RPM_STATE=$fixture/rpm-installed"
    "MOCK_FLATPAK_STATE=$fixture/flatpak-installed"
    "MOCK_FZF_LOG=$fixture/fzf.log"
)

refresh_status=0
env "${test_env[@]}" "$backend" refresh >"$command_output" 2>>"$diagnostic_log" || refresh_status=$?
catalog_dir="$cache/fedora-hyprland-workstation/package-manager"
if [[ "$refresh_status" -eq 0 ]] &&
   grep -Fxq 'schema=6' "$catalog_dir/catalog.meta" &&
   awk -F '\t' '$1 == "dnf" && $3 == "v4l-utils" && NF == 31 && $14 == 653312 && $19 ~ /edid-decode/ && $19 !~ /[\r\n]/ && $28 !~ /[\r\n]/ && $31 == 1700000000 { found=1 } END { exit(found ? 0 : 1) }' \
       "$catalog_dir/catalog.tsv" &&
   ! grep -Fq $'ignored-i686\t' "$catalog_dir/catalog.tsv" &&
   awk -F '\t' '$1 == "flatpak" && $3 == "org.libreoffice.LibreOffice" && $12 == "x86_64" && $13 == "650 MB" { found=1 } END { exit(found ? 0 : 1) }' \
       "$catalog_dir/catalog.tsv"; then
    pass "Rich DNF/Flatpak refresh preserves capability, description, size, architecture, and record boundaries"
else
    fail "Rich catalog refresh lost metadata or accepted an incompatible architecture"
fi

failure_cache="$fixture/failure-cache"
mkdir -p "$failure_cache"
failure_status=0
failure_stderr="$fixture/refresh-failure.stderr"
if env "${test_env[@]}" WORKSTATION_PACKAGE_CACHE_DIR="$failure_cache" MOCK_DNF_FAILURE=1 \
    "$backend" refresh >"$command_output" 2>"$failure_stderr"; then
    failure_status=0
else
    failure_status=$?
fi
if [[ "$failure_status" -eq 2 ]] &&
   grep -Fq 'mock dnf metadata failure' "$failure_stderr" &&
   grep -Fq 'errors=partial' "$failure_cache/catalog.meta"; then
    pass "Refresh keeps source failures visible and publishes partial-cache status"
else
    fail "Refresh suppressed a source failure or lost partial-cache status"
fi

search_result="$(env "${test_env[@]}" "$backend" search 'Edid Decode' 2>>"$diagnostic_log" || true)"
if awk -F '\t' '
    NR == 1 && $1 == "dnf" && $3 == "v4l-utils" && $32 ~ /provided capability/ { found=1 }
    $3 != "v4l-utils" { unrelated=1 }
    END { exit(found && !unrelated ? 0 : 1) }
' <<<"$search_result"; then
    pass "Normalized DNF capability search resolves Edid Decode to v4l-utils"
else
    fail "Normalized DNF capability search did not rank v4l-utils"
fi

libre_variants=0
for query in LibreOffice libreOffice 'libre office' libre_office; do
    variant_result="$(env "${test_env[@]}" "$backend" search "$query" 2>>"$diagnostic_log" || true)"
    if grep -Fq $'dnf\tupdates\tlibreoffice' <<<"$variant_result" &&
       grep -Fq $'flatpak\tflathub\torg.libreoffice.LibreOffice' <<<"$variant_result"; then
        libre_variants=$((libre_variants + 1))
    fi
done
if [[ "$libre_variants" -eq 4 ]]; then
    pass "Case and separator variants return both DNF and Flatpak LibreOffice providers"
else
    fail "Case/separator normalization changed the provider result set"
fi

latest_result="$(env "${test_env[@]}" "$backend" latest libreoffice 2>>"$diagnostic_log" || true)"
all_versions_result="$(env "${test_env[@]}" "$backend" search --all-versions libreoffice 2>>"$diagnostic_log" || true)"
if grep -Fq $'dnf\tupdates\tlibreoffice' <<<"$latest_result" &&
   ! grep -Fq $'dnf\tfedora\tlibreoffice' <<<"$latest_result" &&
   grep -Fq $'dnf\tfedora\tlibreoffice' <<<"$all_versions_result" &&
   grep -Fq $'dnf\tupdates\tlibreoffice' <<<"$all_versions_result"; then
    pass "Latest mode selects the newest DNF build while all-version mode preserves alternatives"
else
    fail "Latest/all-version package selection did not distinguish historical builds"
fi

version_query_result="$(env "${test_env[@]}" "$backend" search 'libreoffice 26.2.6.3' 2>>"$diagnostic_log" || true)"
if grep -Fq $'dnf\tupdates\tlibreoffice' <<<"$version_query_result" &&
   ! grep -Fq $'dnf\tfedora\tlibreoffice' <<<"$version_query_result"; then
    pass "Multi-term search can target a package by its specific version"
else
    fail "Specific package-version search did not isolate the requested build"
fi

tui_result_status=0
if tui_result="$(env "${test_env[@]}" "$backend" catalog-tui-search --query edid-decode 2>>"$diagnostic_log")"; then
    :
else
    tui_result_status=$?
fi
if awk -F '\t' '
    NR == 1 && NF == 12 && $1 == "dnf" && $3 == "v4l-utils" && $10 ~ /provided capability/ && $12 ~ /video4linux/ { found=1 }
    $3 != "v4l-utils" { unrelated=1 }
    END { exit(found && !unrelated ? 0 : 1) }
' <<<"$tui_result"; then
    pass "TUI result stream contains only semantic capability matches, not arbitrary fuzzy candidates"
else
    fail "TUI result stream still exposes unrelated fuzzy candidates (status $tui_result_status)"
fi

version_history="$(env "${test_env[@]}" "$backend" catalog-tui-versions \
    --provider dnf --id libreoffice --scope system 2>>"$diagnostic_log" || true)"
if [[ "$(wc -l <<<"$version_history" | tr -d '[:space:]')" -eq 2 ]] &&
   grep -Fq $'dnf\tupdates\tlibreoffice' <<<"$version_history" &&
   grep -Fq $'dnf\tfedora\tlibreoffice' <<<"$version_history"; then
    pass "TUI version history loads every cached source/version row for selection"
else
    fail "TUI version history did not return the complete cached package history"
fi

tui_all_file="$fixture/tui-all.tsv"
tui_all_status=0
if env "${test_env[@]}" "$backend" catalog-tui-search --query '' >"$tui_all_file" 2>>"$diagnostic_log"; then
    :
else
    tui_all_status=$?
fi
tui_all_count="$(wc -l <"$tui_all_file" | tr -d '[:space:]')"
catalog_row_count="$(wc -l <"$catalog_dir/catalog.tsv" | tr -d '[:space:]')"
if [[ "$tui_all_status" -eq 0 && "$tui_all_count" -eq "$catalog_row_count" ]]; then
    pass "TUI loads the complete published catalog instead of a fixed initial slice"
else
    fail "TUI loaded $tui_all_count rows from a $catalog_row_count-row catalog"
fi

duplicate_display="$(printf '%s\n' $'aurelia\tgithub.com/example/app\tapp\tapp\t1.0\tuser\tx86_64\t-\t-\tcatalog\t-\tExample app' |
    env "${test_env[@]}" bash -c 'source "$1"; format_catalog_rows_for_fzf' _ "$backend" 2>>"$diagnostic_log")"
if awk -F '\t' 'NR == 1 && NF == 12 && $1 == "aurelia" && $3 == "app" && $4 == "-" { found=1 } END { exit(found ? 0 : 1) }' <<<"$duplicate_display"; then
    pass "Provider-neutral TUI formatting removes duplicate ID/name columns"
else
    fail "TUI formatting still duplicates an identity column for non-DNF providers"
fi

info_result="$(env "${test_env[@]}" "$backend" info --provider dnf --source fedora --id v4l-utils --scope system 2>>"$diagnostic_log" || true)"
if grep -Fq 'Capabilities    : edid-decode' <<<"$info_result" &&
   grep -Fq 'Installed size  : 1.7 MiB (1831495 bytes)' <<<"$info_result" &&
   grep -Fq 'Download size   : 638.0 KiB (653312 bytes)' <<<"$info_result" &&
   grep -Fq 'Release date    : 2023-11-15' <<<"$info_result" &&
   grep -Fq 'Description     :' <<<"$info_result"; then
    pass "Metadata preview exposes capabilities, size, and description"
else
    fail "Metadata preview omitted rich package information"
fi

cache_summary="$(env "${test_env[@]}" "$backend" catalog status 2>>"$diagnostic_log" || true)"
if grep -Fq 'schema 6' <<<"$cache_summary" &&
   grep -Fq 'Catalog:' <<<"$cache_summary" &&
   grep -Fq 'Packages:' <<<"$cache_summary" &&
   ! grep -Fq '34434s old' <<<"$cache_summary"; then
    pass "Catalog status uses human-readable age and schema/source diagnostics"
else
    fail "Catalog status remains machine-oriented or incomplete"
fi

# Opening the dedicated TUI must not turn a usable stale cache into a blocking
# network refresh. The background timer and explicit Ctrl-R own freshness.
touch -d '2 days ago' "$catalog_dir/catalog.tsv"
stale_bootstrap_status=0
stale_bootstrap_stderr="$fixture/stale-bootstrap.stderr"
env "${test_env[@]}" MOCK_DNF_FAILURE=1 "$backend" catalog-tui-bootstrap \
    >"$command_output" 2>"$stale_bootstrap_stderr" || stale_bootstrap_status=$?
if [[ "$stale_bootstrap_status" -eq 0 ]] &&
   ! grep -Fq 'Refreshing Fedora package sources' "$stale_bootstrap_stderr" &&
   ! grep -Fq 'mock dnf metadata failure' "$stale_bootstrap_stderr"; then
    pass "Dedicated TUI opens from the last-known-good stale cache without an implicit refresh"
else
    fail "Dedicated TUI still performs a blocking refresh when a usable cache is stale"
fi

user_config="$fixture/user-package-manager.conf"
cat >"$user_config" <<'EOF_USER_CONFIG'
catalog_stale_seconds=300
catalog_boot_delay=2m
catalog_refresh_interval=12h
catalog_refresh_jitter=1m
catalog_result_limit=17
lock_wait_seconds=3
key_refresh=ctrl-f
key_help=h
tui_preview_window=bottom:60%:wrap
tui_border=double
tui_margin=2,4
tui_padding=1
tui_prompt="Find > "
tui_pointer=>
tui_marker=*
tui_scroll_off=5
tui_tabstop=4
tui_color=fg:#fff,fg+:#eee,pointer:cyan
tui_title=Packages
tui_header_label=Inventory
tui_input_label=Query
tui_list_label=Results
tui_preview_label=Details
tui_footer_label=Controls
EOF_USER_CONFIG

config_output="$(env "${test_env[@]}" WORKSTATION_PACKAGE_USER_CONFIG="$user_config" \
    bash -c 'source "$1"; printf "%s\n" "$WSP_CFG_CATALOG_STALE_SECONDS|$WSP_CFG_CATALOG_BOOT_DELAY|$WSP_CFG_CATALOG_RESULT_LIMIT|$WSP_CFG_KEY_REFRESH|$WSP_CFG_KEY_HELP|$WSP_CFG_TUI_PREVIEW_WINDOW|$WSP_CFG_TUI_BORDER|$WSP_CFG_TUI_MARGIN|$WSP_CFG_TUI_PADDING|$WSP_CFG_TUI_PROMPT|$WSP_CFG_TUI_POINTER|$WSP_CFG_TUI_MARKER|$WSP_CFG_TUI_SCROLL_OFF|$WSP_CFG_TUI_TABSTOP|$WSP_CFG_TUI_COLOR|$WSP_CFG_TUI_TITLE|$WSP_CFG_TUI_HEADER_LABEL|$WSP_CFG_TUI_INPUT_LABEL|$WSP_CFG_TUI_LIST_LABEL|$WSP_CFG_TUI_PREVIEW_LABEL|$WSP_CFG_TUI_FOOTER_LABEL"' \
    _ "$backend" 2>>"$diagnostic_log")"
if [[ "$config_output" == '300|2m|17|ctrl-f|h|bottom:60%:wrap|double|2,4|1|Find > |>|*|5|4|fg:#fff,fg+:#eee,pointer:cyan|Packages|Inventory|Query|Results|Details|Controls' ]]; then
    pass "Declarative user configuration overrides refresh, limits, preview, and key commands"
else
    fail "Declarative package-manager configuration did not apply safely"
fi

bad_config="$fixture/bad-package-manager.conf"
printf '%s\n' 'catalog_refresh_jitter=not-a-duration' >"$bad_config"
bad_status=0
env "${test_env[@]}" WORKSTATION_PACKAGE_USER_CONFIG="$bad_config" \
    bash -c 'source "$1"' _ "$backend" >"$command_output" 2>>"$diagnostic_log" || bad_status=$?
if [[ "$bad_status" -ne 0 ]]; then
    pass "Malformed package-manager configuration fails closed"
else
    fail "Malformed package-manager configuration was accepted"
fi

marker="$fixture/config-executed"
unsafe_config="$fixture/unsafe-package-manager.conf"
printf 'catalog_result_limit=$(touch %s)\n' "$marker" >"$unsafe_config"
unsafe_status=0
env "${test_env[@]}" WORKSTATION_PACKAGE_USER_CONFIG="$unsafe_config" \
    bash -c 'source "$1"' _ "$backend" >"$command_output" 2>>"$diagnostic_log" || unsafe_status=$?
if [[ "$unsafe_status" -ne 0 && ! -e "$marker" ]]; then
    pass "Configuration parsing never executes shell substitutions"
else
    fail "Configuration parsing accepted or executed shell syntax"
fi

duplicate_config="$fixture/duplicate-key-package-manager.conf"
printf '%s\n' 'key_help=up' >"$duplicate_config"
duplicate_config_status=0
env "${test_env[@]}" WORKSTATION_PACKAGE_USER_CONFIG="$duplicate_config" \
    bash -c 'source "$1"' _ "$backend" >"$command_output" 2>>"$diagnostic_log" || duplicate_config_status=$?
if [[ "$duplicate_config_status" -ne 0 ]]; then
    pass "Conflicting key bindings fail closed instead of silently shadowing actions"
else
    fail "Conflicting key bindings were accepted"
fi

fallback_catalog="$fixture/fallback-catalog.tsv"
awk -F '\t' -v OFS='\t' '{ if ($3 == "v4l-utils") $19 = ""; print }' \
    "$catalog_dir/catalog.tsv" >"$fallback_catalog"
fallback_cache="$fixture/fallback-cache"
mkdir -p "$fallback_cache"
cp -- "$fallback_catalog" "$fallback_cache/catalog.tsv"
fallback_status=0
if fallback_result="$(env "${test_env[@]}" WORKSTATION_PACKAGE_CACHE_DIR="$fallback_cache" \
    "$backend" catalog-tui-search --query unindexed-tool 2>>"$diagnostic_log")"; then
    :
else
    fallback_status=$?
fi
if awk -F '\t' 'NR == 1 && $3 == "v4l-utils" && $10 ~ /provided capability/ { found=1 } END { exit(found ? 0 : 1) }' <<<"$fallback_result"; then
    pass "On-demand cached DNF whatprovides fallback resolves a capability absent from the local index"
else
    fail "DNF whatprovides fallback did not recover an unindexed capability (status $fallback_status)"
fi

tui_status=0
env "${test_env[@]}" WSP_ASSUME_YES=1 bash -c '
    source "$1"
    require_tty() { return 0; }
    tui_show_done() { :; }
    tui_search_install
' _ "$backend" >"$command_output" 2>>"$diagnostic_log" || tui_status=$?
manifest_row="$(awk -F '\t' '$1 == "dnf" && $3 == "v4l-utils" { print; exit }' "$repo/packages/user-managed.tsv")"
if [[ "$tui_status" -eq 0 ]] &&
   [[ "$manifest_row" == $'dnf\tfedora\tv4l-utils\tsystem\tall' ]] &&
   [[ "$(grep -Fxc $'dnf\tfedora\tv4l-utils\tsystem\tall' "$repo/packages/user-managed.tsv")" -eq 1 ]] &&
   grep -Fq -- '--disabled' "$fixture/fzf.log" &&
   grep -Fq -- 'change:reload' "$fixture/fzf.log" &&
   grep -Fq -- 'catalog-tui-search' "$fixture/fzf.log"; then
    pass "Interactive TUI install-and-track writes one canonical DNF manifest row and uses semantic reload"
else
    fail "Interactive TUI install-and-track did not persist the canonical manifest row"
fi

metadata_boundary_status=0
env "${test_env[@]}" bash -c '
    source "$1"
    wsp_install_and_track_row dnf fedora mock-dnf system \
        catalog-version ignored.asset sha256:ignored .local/bin/ignored https://example.invalid/ignored
' _ "$backend" >"$command_output" 2>>"$diagnostic_log" || metadata_boundary_status=$?
if [[ "$metadata_boundary_status" -eq 0 ]] &&
   grep -Fxq $'dnf\tfedora\tmock-dnf\tsystem\tall' "$repo/packages/user-managed.tsv" &&
   ! grep -Fq catalog-version "$repo/packages/user-managed.tsv"; then
    pass "Non-Aurelia catalog metadata cannot enter the tracked manifest"
else
    fail "Non-Aurelia metadata crossed the manifest ownership boundary"
fi

no_track_status=0
env "${test_env[@]}" bash -c '
    source "$1"
    tui_apply_selected_rows $'"'"'dnf\tfedora\tno-track\tno-track\t1\tsystem\tx86_64\t-\t-\tcatalog\tA test package'"'"' 0
' _ "$backend" >"$command_output" 2>>"$diagnostic_log" || no_track_status=$?
if [[ "$no_track_status" -eq 0 ]] &&
   grep -Fxq no-track "$fixture/rpm-installed" &&
   ! grep -Fq $'dnf\tfedora\tno-track' "$repo/packages/user-managed.tsv"; then
    pass "Explicit non-tracking selection installs without changing user-managed.tsv"
else
    fail "Non-tracking selection unexpectedly changed or failed the manifest path"
fi

duplicate_status=0
env "${test_env[@]}" "$backend" install dnf fedora mock-dnf system --track --yes >"$command_output" 2>>"$diagnostic_log" || duplicate_status=$?
if [[ "$duplicate_status" -eq 0 ]] &&
   grep -Fxq $'dnf\tfedora\tmock-dnf\tsystem\tall' "$repo/packages/user-managed.tsv" &&
   [[ "$(grep -Fxc $'dnf\tfedora\tmock-dnf\tsystem\tall' "$repo/packages/user-managed.tsv")" -eq 1 ]]; then
    pass "Repeated tracked installation remains idempotent"
else
    fail "Repeated tracked installation duplicated or lost the manifest identity"
fi

env "${test_env[@]}" "$backend" daily enable >"$command_output" 2>>"$diagnostic_log" || true
timer_file="$home/.config/systemd/user/workstation-packages-refresh.timer"
if grep -Fq 'OnBootSec=45s' "$timer_file" 2>>"$diagnostic_log" &&
   grep -Fq 'OnUnitActiveSec=6h' "$timer_file" 2>>"$diagnostic_log"; then
    pass "Background refresh timer is boot/interval driven and remains metadata-only"
else
    fail "Background refresh timer did not use the configured boot/interval policy"
fi

if ! grep -Fq 'start_background_catalog_refresh' "$backend" &&
   ! grep -Fq 'wsp_lock_start || return 1' <(sed -n '880,930p' "$backend"); then
    pass "Interactive search no longer starts a hidden refresh or holds the global lock while idle"
else
    fail "Interactive search still contains the hidden-refresh/long-held-lock race"
fi

age_output="$(env "${test_env[@]}" "$backend" catalog status 2>>"$diagnostic_log" || true)"
age_value="$(env "${test_env[@]}" bash -c 'source "$1"; wsp_catalog_human_age 34434' _ "$backend" 2>>"$diagnostic_log")"
if [[ "$age_value" == '9h 33m' ]] && ! grep -Fq '34434s' <<<"$age_output"; then
    pass "User-facing catalog age never regresses to raw seconds"
else
    fail "User-facing catalog age still exposes raw seconds"
fi

if grep -Fq '[[ ! -t "$tty_fd" ]]' "$backend"; then
    pass "Interactive prompts validate the opened /dev/tty descriptor"
else
    fail "Interactive prompts still validate /dev/tty as a pathname instead of a descriptor"
fi

if grep -Fq -- '--footer="$footer"' "$backend" &&
   grep -Fq -- '--no-input --no-multi --no-sort' "$backend" &&
   grep -Fq -- 'Package Manager Help' "$backend"; then
    pass "Help opens as a scrollable popup instead of consuming the search header"
else
    fail "Help is still rendered as a cramped inline message"
fi

if (( FAILS > 0 )) && [[ -s "$diagnostic_log" ]]; then
    printf '\nAdvanced package-manager diagnostics retained during failed assertions:\n' >&2
    cat -- "$diagnostic_log" >&2
fi
