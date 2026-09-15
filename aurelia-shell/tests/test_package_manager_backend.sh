#!/usr/bin/env bash

# Isolated tests for the Fedora/Flatpak package manager backend. No real DNF,
# Flatpak, sudo, systemd, package installation, or repository mutation runs.

set -Eeuo pipefail

section "Aurelia Fedora and Flatpak Package Manager Backend"

fixture="$(mktemp -d)"
repo="$fixture/repo"
mock_bin="$fixture/bin"
home="$fixture/home"
runtime="$fixture/runtime"
cache="$fixture/cache"
mkdir -p "$repo/packages" "$mock_bin" "$home" "$runtime" "$cache"

cleanup_package_manager_fixture() {
    rm -rf -- "$fixture"
}
trap cleanup_package_manager_fixture EXIT

cat >"$repo/packages/user-managed.tsv" <<'EOF_MANIFEST'
# schema=1
# provider<TAB>source<TAB>identifier<TAB>scope<TAB>profiles
EOF_MANIFEST
cat >"$repo/packages/sources.tsv" <<'EOF_SOURCES'
# schema=1
# provider<TAB>source<TAB>url<TAB>scope
flatpak	flathub	https://flathub.org/repo/flathub.flatpakrepo	system
EOF_SOURCES

printf '%s\n' mock-dnf >"$fixture/rpm-installed"
printf '%s\n' org.example.App >"$fixture/flatpak-installed"

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
if [[ "$1" == "-q" ]]; then
    grep -Fxq -- "$2" "${MOCK_RPM_STATE:?}"
    exit $?
fi
if [[ "$1" == "-qa" ]]; then
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        printf 'unknown\t%s\t1\tx86_64\n' "$package"
    done <"${MOCK_RPM_STATE:?}"
    exit 0
fi
exit 2
EOF_RPM

cat >"$mock_bin/dnf5" <<'EOF_DNF'
#!/usr/bin/env bash
args="$*"
if [[ "$args" == *"makecache"* ]]; then
    exit 0
fi
if [[ "$args" == *"repoquery"* && "$args" == *"--available"* ]]; then
    if [[ "$args" == *"%{summary}"* ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' mock-dnf 'A mock DNF package' 1 fedora x86_64
        printf '%s\t%s\t%s\t%s\t%s\n' mock-dnf-i686 'An i686 package' 1 fedora i686
    elif [[ "$args" == *"%{arch}"* ]]; then
        printf '%s\t%s\n' "${@: -1}" x86_64
    else
        printf '%s\n' "${@: -1}"
    fi
    exit 0
fi
if [[ "$args" == *"repoquery"* && "$args" == *"--userinstalled"* ]]; then
    printf '%s\t%s\t%s\t%s\n' fedora mock-dnf 1 x86_64
    exit 0
fi
if [[ "$args" == *"repoquery"* && "$args" == *"--installed"* ]]; then
    printf '%s\n' fedora
    exit 0
fi
if [[ "$1" == "install" && "$2" == --from-repo=* ]]; then
    package="${@: -1}"
    package="${package%.x86_64}"
    [[ "$package" == mock-dnf-1 ]] && package=mock-dnf
    printf '%s\n' "$package" >>"${MOCK_RPM_STATE:?}"
    exit 0
fi
if [[ "$1" == "remove" ]]; then
    sed -i "/^${!#}$/d" "${MOCK_RPM_STATE:?}"
    exit 0
fi
exit 2
EOF_DNF

cat >"$mock_bin/flatpak" <<'EOF_FLATPAK'
#!/usr/bin/env bash
args="$*"
if [[ "$1" == "remotes" ]]; then
    printf '%s\n' flathub
    exit 0
fi
if [[ "$1" == "remote-ls" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\n' org.example.Catalog 'Catalog App' 'A catalog Flatpak' 1 stable
    exit 0
fi
if [[ "$1" == "list" ]]; then
    if grep -q '^org.example.App$' "${MOCK_FLATPAK_STATE:?}"; then
        if [[ "$args" == *"origin,name,version,branch"* ]]; then
            printf '%s\t%s\t%s\t%s\t%s\n' org.example.App flathub 'Example App' 1 stable
        else
            printf '%s\n' org.example.App
        fi
    fi
    exit 0
fi
if [[ "$1" == "install" ]]; then
    printf '%s\n' "${@: -1}" >>"${MOCK_FLATPAK_STATE:?}"
    exit 0
fi
if [[ "$1" == "uninstall" ]]; then
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

cat >"$mock_bin/kitty" <<'EOF_KITTY'
#!/usr/bin/env bash
exit 0
EOF_KITTY

cat >"$mock_bin/setsid" <<'EOF_SETSID'
#!/usr/bin/env bash
printf '%s\0' "$@" >"${MOCK_OPEN_LOG:?}"
exit 0
EOF_SETSID

chmod 0755 "$mock_bin/rpm" "$mock_bin/dnf5" "$mock_bin/flatpak" "$mock_bin/sudo" "$mock_bin/systemctl" "$mock_bin/kitty" "$mock_bin/setsid"

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
    "MOCK_OPEN_LOG=$fixture/open.log"
)

if env "${test_env[@]}" "$backend" adopt dnf fedora mock-dnf system --yes >/dev/null &&
   grep -Fxq $'dnf\tfedora\tmock-dnf\tsystem\tall' "$repo/packages/user-managed.tsv" &&
   [[ "$(find "$repo" -type f -name '*.bak' -print -quit)" == "" ]]; then
    pass "Adopting an installed DNF package records one canonical manifest row without backups"
else
    fail "DNF adoption did not update user-managed.tsv safely"
fi

if env "${test_env[@]}" "$backend" install dnf fedora new-dnf system --track --yes >/dev/null &&
   grep -Fxq $'dnf\tfedora\tnew-dnf\tsystem\tall' "$repo/packages/user-managed.tsv"; then
    pass "DNF install-and-track persists desired state only after the package transaction"
else
    fail "DNF install-and-track did not persist the expected row"
fi

if env "${test_env[@]}" "$backend" adopt flatpak flathub org.example.App system --yes >/dev/null &&
   grep -Fxq $'flatpak\tflathub\torg.example.App\tsystem\tall' "$repo/packages/user-managed.tsv"; then
    pass "Flatpak adoption preserves remote and installation scope"
else
    fail "Flatpak adoption did not preserve source and scope"
fi

if env "${test_env[@]}" "$backend" remove dnf fedora mock-dnf system --forget --yes >/dev/null &&
   ! grep -Fq $'dnf\tfedora\tmock-dnf\tsystem\tall' "$repo/packages/user-managed.tsv"; then
    pass "DNF remove-and-forget removes the declaration without purge semantics"
else
    fail "DNF remove-and-forget did not remove the declaration"
fi

mkdir -p "$cache/fedora-hyprland-workstation/package-manager"
printf '%s\n' $'dnf\tfedora\tmock-dnf\tmock-dnf\tA mock package\t1\tsystem' >"$cache/fedora-hyprland-workstation/package-manager/catalog.tsv"
if env "${test_env[@]}" "$backend" search mock-dnf | grep -Fq $'dnf\tfedora\tmock-dnf'; then
    pass "Search reads the normalized multi-source catalog"
else
    fail "Search did not return a catalog row with provider and source"
fi

if env "${test_env[@]}" "$backend" status --json | jq -e '
    .schema == 1 and
    ([.tracked[] | select(.identifier == "new-dnf")][0].source == "fedora") and
    ([.tracked[] | select(.identifier == "org.example.App")][0].scope == "system")
' >/dev/null; then
    pass "Status JSON reports tracked provider/source/scope state"
else
    fail "Status JSON omitted tracked package provenance"
fi

if env "${test_env[@]}" "$backend" refresh >/dev/null &&
   env "${test_env[@]}" "$backend" search mock-dnf | grep -Fq $'dnf\tfedora\tmock-dnf' &&
   ! env "${test_env[@]}" "$backend" search mock-dnf-i686 | grep -Fq $'dnf\tfedora\tmock-dnf-i686' &&
   env "${test_env[@]}" "$backend" search org.example.Catalog | grep -Fq $'flatpak\tflathub\torg.example.Catalog'; then
    pass "Refresh indexes native Fedora DNF and Flatpak rows as separate searchable providers"
else
    fail "Refresh did not make both DNF and Flatpak catalog rows searchable"
fi

if env "${test_env[@]}" "$backend" install-catalog-row \
       --provider dnf --source fedora --id mock-dnf --scope system --track --yes >/dev/null &&
   grep -Fxq $'dnf\tfedora\tmock-dnf\tsystem\tall' "$repo/packages/user-managed.tsv"; then
    pass "Dedicated TUI install boundary re-reads the selected catalog identity in the backend"
else
    fail "Dedicated catalog-row install boundary did not preserve provider-aware tracking"
fi

exact_install_output="$(env "${test_env[@]}" "$backend" install-catalog-row \
    --provider dnf --source fedora --id mock-dnf --scope system --version 1 --arch x86_64 --yes 2>&1 || true)"
if grep -Fq 'Installing DNF package mock-dnf-1 from fedora' <<<"$exact_install_output"; then
    pass "Version history installation revalidates and requests the exact DNF build"
else
    fail "Exact DNF version installation did not reach the provider-aware transaction boundary"
fi

installed_tui_output="$(env "${test_env[@]}" "$backend" catalog-tui-installed 2>&1)"
if grep -Fq $'dnf\tunknown\tmock-dnf\tsystem' <<<"$installed_tui_output" &&
   grep -Fq $'flatpak\tflathub\torg.example.App\tsystem' <<<"$installed_tui_output"; then
    pass "TUI installed-state inventory includes all local RPM and Flatpak applications"
else
    fail "TUI installed-state inventory omitted a local provider"
fi

if [[ "$(env "${test_env[@]}" "$backend" catalog-tui-ownership --provider dnf --id chatgpt)" == "project-owned" ]] &&
   [[ "$(env "${test_env[@]}" "$backend" catalog-tui-ownership --provider dnf --id mock-dnf)" == "user-trackable" ]]; then
    pass "TUI ownership discovery distinguishes workstation-owned packages from user-trackable packages"
else
    fail "TUI ownership discovery returned an incorrect tracking classification"
fi

printf '%s\n' $'dnf\tfedora\tchatgpt\tchatgpt\tChatGPT\t1\tsystem\tx86_64\t1 MiB\t1 MiB\tLATEST\t2026-09-01' \
    >>"$cache/fedora-hyprland-workstation/package-manager/catalog.tsv"
if env "${test_env[@]}" "$backend" install-catalog-row \
       --provider dnf --source fedora --id chatgpt --scope system --yes >/dev/null &&
   grep -Fxq chatgpt "$fixture/rpm-installed" &&
   ! grep -Fq $'dnf\tfedora\tchatgpt\tsystem\tall' "$repo/packages/user-managed.tsv"; then
    pass "Project-owned catalog update runs without user-managed tracking"
else
    fail "Project-owned catalog update was blocked or polluted user-managed.tsv"
fi

if env "${test_env[@]}" "$backend" remove-catalog-row \
       --provider dnf --source fedora --id mock-dnf --scope system --forget --yes >/dev/null &&
   ! grep -Fxq mock-dnf "$fixture/rpm-installed" &&
   ! grep -Fq $'dnf\tfedora\tmock-dnf\tsystem\tall' "$repo/packages/user-managed.tsv"; then
    pass "Dedicated TUI uninstall boundary removes the package and explicitly forgets tracking"
else
    fail "Dedicated catalog-row uninstall boundary did not remove the package or declaration"
fi

if env "${test_env[@]}" "$backend" open >/dev/null &&
   tr '\0' ' ' <"$fixture/open.log" | grep -Fq 'workstation-packages-tui'; then
    pass "Opening Package Manager enters the ready package search directly"
else
    fail "Opening Package Manager did not launch the direct search surface"
fi

if env "${test_env[@]}" "$backend" daily enable >/dev/null &&
   [[ -f "$home/.config/systemd/user/workstation-packages-refresh.service" ]] &&
   [[ -f "$home/.config/systemd/user/workstation-packages-refresh.timer" ]] &&
   grep -Fq 'ExecStart=' "$home/.config/systemd/user/workstation-packages-refresh.service" &&
   env "${test_env[@]}" "$backend" daily disable >/dev/null &&
   [[ ! -e "$home/.config/systemd/user/workstation-packages-refresh.service" ]] &&
   [[ ! -e "$home/.config/systemd/user/workstation-packages-refresh.timer" ]]; then
    pass "Daily refresh writes and removes one user timer without backup files"
else
    fail "Daily refresh timer lifecycle did not converge safely"
fi

if grep -q 'tui_show_done' "$backend" &&
   grep -q 'Press any key to close' "$backend" &&
   grep -q 'tui_show_done.*Package operation finished' "$backend" &&
   grep -q 'exec {tty_fd}<>"\$tty_path"' "$backend" &&
   grep -q 'return "\$search_status"' "$backend"; then
    pass "Terminal-owned package search acknowledges the result and exits after the keypress"
else
    fail "Package Manager result acknowledgement does not have a clean terminal-exit boundary"
fi

atomic_target_output="$(
    bash -s -- "$ROOT" "$fixture" <<'EOS_ATOMIC_TARGET'
set -Eeuo pipefail
ROOT="$1"
FIXTURE="$2"
source "$ROOT/bin/lib/workstation-packages/common.sh"
target="$FIXTURE/atomic-target"
source_file="$FIXTURE/atomic-source"
mkdir -p "$target"
printf 'managed-content\n' > "$source_file"
status=0
wsp_atomic_replace "$target" "$source_file" || status=$?
printf 'directory_rejected=%s staging_preserved=%s\n' \
    "$([[ $status -ne 0 ]] && echo 1 || echo 0)" \
    "$([[ -d "$target" && ! -e "$target/atomic-source" ]] && echo 1 || echo 0)"
EOS_ATOMIC_TARGET
)"

if grep -q 'directory_rejected=1 staging_preserved=1' <<< "$atomic_target_output"; then
    pass "Aurelia atomic file replacement rejects directory targets without misplacing staged files"
else
    fail "Aurelia atomic file replacement accepted a directory target: $atomic_target_output"
fi

path_guard_output="$(
    bash -s -- "$ROOT" "$fixture" <<'EOS_PATH_GUARD'
set -Eeuo pipefail
ROOT="$1"
FIXTURE="$2"
source "$ROOT/bin/lib/workstation-packages/common.sh"
source "$ROOT/bin/lib/workstation-packages/manifest.sh"
source "$ROOT/bin/lib/workstation-packages/catalog.sh"

external="$FIXTURE/external-cache"
cache_link="$FIXTURE/cache-link"
ln -s -- "$external" "$cache_link"
WSP_CACHE_DIR="$cache_link"
WSP_CATALOG_FILE="$cache_link/catalog.tsv"
WSP_CATALOG_META="$cache_link/catalog.meta"
WSP_CATALOG_ERRORS="$cache_link/catalog.errors"
cache_status=0
wsp_catalog_paths_safe || cache_status=$?

manifest_target="$FIXTURE/manifest-target"
manifest_link="$FIXTURE/manifest-link"
printf 'dnf\tfedora\tpackage\tsystem\tall\n' > "$manifest_target"
ln -s -- "$manifest_target" "$manifest_link"
WSP_MANIFEST="$manifest_link"
manifest_status=0
wsp_manifest_rows >/dev/null || manifest_status=$?

printf 'cache_symlink_rejected=%s cache_target_created=%s manifest_symlink_rejected=%s\n' \
    "$([[ $cache_status -ne 0 ]] && echo 1 || echo 0)" \
    "$([[ ! -e "$external" ]] && echo 1 || echo 0)" \
    "$([[ $manifest_status -ne 0 ]] && echo 1 || echo 0)"
EOS_PATH_GUARD
)"

if grep -q 'cache_symlink_rejected=1 cache_target_created=1 manifest_symlink_rejected=1' <<< "$path_guard_output"; then
    pass "Aurelia package-manager path guards reject symlinked caches and manifests before reading or creating targets"
else
    fail "Aurelia package-manager symlink guards are incomplete: $path_guard_output"
fi

if grep -Eq 'wsp_run_timeout .*flatpak remotes' "$ROOT/bin/lib/workstation-packages/transactions.sh"; then
    pass "Aurelia package source checks bound Flatpak remote enumeration"
else
    fail "Aurelia package source checks can run an unbounded Flatpak remote query"
fi
