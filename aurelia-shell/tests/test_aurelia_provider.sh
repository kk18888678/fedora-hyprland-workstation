#!/usr/bin/env bash

# Isolated Aurelia provider tests. GitHub API and artifact downloads are mocked;
# no network, package manager, sudo, or live user state is touched.

set -Eeuo pipefail

section "Aurelia verified upstream package provider"

fixture="$(mktemp -d)"
repo="$fixture/repo"
mock_bin="$fixture/bin"
home="$fixture/home"
runtime="$fixture/runtime"
cache="$fixture/cache"
mkdir -p "$repo/packages" "$mock_bin" "$home" "$runtime" "$cache"

cleanup_aurelia_fixture() {
    rm -rf -- "$fixture"
}
trap cleanup_aurelia_fixture EXIT

cat >"$repo/packages/user-managed.tsv" <<'EOF_MANIFEST'
# schema=2
# provider<TAB>source<TAB>identifier<TAB>scope<TAB>profiles
# Aurelia rows append: version<TAB>asset<TAB>checksum<TAB>target<TAB>artifact_url
EOF_MANIFEST
cat >"$repo/packages/sources.tsv" <<'EOF_SOURCES'
# schema=1
# provider<TAB>source<TAB>url<TAB>scope
EOF_SOURCES
cat >"$repo/packages/aurelia-sources.tsv" <<'EOF_AURELIA_SOURCES'
# schema=1
# source<TAB>github_url<TAB>profiles
EOF_AURELIA_SOURCES

payload='cliamp-test-binary'
payload_checksum="$(printf '%s' "$payload" | sha256sum | awk '{print $1}')"
cat >"$fixture/releases.json" <<EOF_RELEASES
[
  {
    "tag_name": "v2.1.0-beta",
    "name": "v2.1.0-beta",
    "draft": false,
    "prerelease": true,
    "published_at": "2099-02-01T00:00:00Z",
    "body": "",
    "assets": [
      {"name":"cliamp-linux-amd64","browser_download_url":"https://github.com/example/cliamp/releases/download/v2.1.0-beta/cliamp-linux-amd64","digest":"sha256:${payload_checksum}"}
    ]
  },
  {
    "tag_name": "v2.0.1",
    "name": "v2.0.1",
    "draft": false,
    "prerelease": false,
    "published_at": "2099-01-01T00:00:00Z",
    "body": "SHA256: ${payload_checksum}  cliamp-linux-amd64",
    "assets": [
      {"name":"cliamp-linux-amd64","browser_download_url":"https://github.com/example/cliamp/releases/download/v2.0.1/cliamp-linux-amd64","digest":""}
    ]
  }
]
EOF_RELEASES

cat >"$mock_bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -Eeuo pipefail
output=''
url=''
previous=''
for argument in "$@"; do
    if [[ "$previous" == -o ]]; then
        output="$argument"
    fi
    previous="$argument"
    url="$argument"
done
[[ -n "$output" && -n "$url" ]] || exit 2
case "$url" in
    https://api.github.com/repos/example/cliamp/releases?per_page=30)
        cp -- "${MOCK_RELEASES:?}" "$output"
        ;;
    https://github.com/example/cliamp/releases/download/v2.0.1/cliamp-linux-amd64)
        printf '%s' "${MOCK_PAYLOAD:?}" > "$output"
        ;;
    *)
        exit 22
        ;;
esac
EOF_CURL
chmod 0755 "$mock_bin/curl"

cat >"$mock_bin/dnf5" <<'EOF_DNF'
#!/usr/bin/env bash
exit 0
EOF_DNF
cat >"$mock_bin/flatpak" <<'EOF_FLATPAK'
#!/usr/bin/env bash
exit 0
EOF_FLATPAK
chmod 0755 "$mock_bin/dnf5" "$mock_bin/flatpak"

backend="$ROOT/bin/workstation-packages"
test_env=(
    "PATH=$mock_bin:/usr/bin:/bin"
    "HOME=$home"
    "XDG_STATE_HOME=$home/state"
    "XDG_RUNTIME_DIR=$runtime"
    "XDG_CACHE_HOME=$cache"
    "WORKSTATION_PACKAGE_REPO=$repo"
    "MOCK_RELEASES=$fixture/releases.json"
    "MOCK_PAYLOAD=$payload"
)
bad_payload_env=(
    "PATH=$mock_bin:/usr/bin:/bin"
    "HOME=$home"
    "XDG_STATE_HOME=$home/state"
    "XDG_RUNTIME_DIR=$runtime"
    "XDG_CACHE_HOME=$cache"
    "WORKSTATION_PACKAGE_REPO=$repo"
    "MOCK_RELEASES=$fixture/releases.json"
    "MOCK_PAYLOAD=tampered-payload"
)

if env "${test_env[@]}" "$backend" source add aurelia \
    https://github.com/example/cliamp --yes >/dev/null 2>&1 &&
   grep -Fxq $'github.com/example/cliamp\thttps://github.com/example/cliamp\tall' \
       "$repo/packages/aurelia-sources.tsv" &&
   ! grep -Fq $'aurelia\t' "$repo/packages/user-managed.tsv" &&
   env "${test_env[@]}" "$backend" search cliamp | grep -Fq $'aurelia\tgithub.com/example/cliamp\tcliamp'; then
    pass "Aurelia source registration discovers a stable checked GitHub release without adopting it"
else
    fail "Aurelia source registration did not validate and track the GitHub source"
fi

if ! env "${bad_payload_env[@]}" "$backend" install aurelia github.com/example/cliamp cliamp user --track --yes >/dev/null 2>&1 &&
   [[ ! -e "$home/.local/bin/cliamp" ]] &&
   ! grep -Fq $'aurelia\t' "$repo/packages/user-managed.tsv"; then
    pass "Aurelia refuses a checksum-mismatched release before changing the target or tracked state"
else
    fail "Aurelia checksum mismatch was not rejected before installation"
fi

expected_row="$(printf 'aurelia\tgithub.com/example/cliamp\tcliamp\tuser\tall\tv2.0.1\tcliamp-linux-amd64\tsha256:%s\t.local/bin/cliamp\thttps://github.com/example/cliamp/releases/download/v2.0.1/cliamp-linux-amd64' "$payload_checksum")"
if env "${test_env[@]}" "$backend" install aurelia github.com/example/cliamp cliamp user --track --yes >/dev/null 2>&1 &&
   grep -Fxq "$expected_row" "$repo/packages/user-managed.tsv" &&
   [[ -x "$home/.local/bin/cliamp" ]] &&
   [[ "$(cat -- "$home/.local/bin/cliamp")" == "$payload" ]] &&
   [[ "$(cat -- "$home/state/fedora-hyprland-workstation/package-manager/aurelia/cliamp.owner")" == *'source=github.com/example/cliamp'* ]]; then
    pass "Aurelia downloads the pinned architecture asset, verifies SHA-256, installs to ~/.local/bin, and records metadata"
else
    fail "Aurelia install-and-track did not produce the verified binary and pinned manifest row"
fi

if env "${test_env[@]}" "$backend" status --json | jq -e '
    ([.tracked[] | select(.provider == "aurelia" and .identifier == "cliamp")][0].state == "installed") and
    ([.tracked[] | select(.identifier == "cliamp")][0].origin == "github.com/example/cliamp") and
    ([.tracked[] | select(.identifier == "cliamp")][0].checksum | startswith("sha256:"))
' >/dev/null; then
    pass "Status reports Aurelia ownership, provenance, and checksum metadata"
else
    fail "Status did not report the Aurelia package provenance"
fi

aurelia_state_dir="$home/state/fedora-hyprland-workstation/package-manager/aurelia"
chmod 0500 "$aurelia_state_dir"
aurelia_marker_failure_output="$(
    env "${test_env[@]}" bash -s -- "$ROOT" "$payload_checksum" <<'EOS_MARKER_FAILURE'
set -Eeuo pipefail
ROOT="$1"
PAYLOAD_CHECKSUM="$2"
source "$ROOT/bin/lib/workstation-packages/common.sh"
source "$ROOT/bin/lib/workstation-packages/aurelia.sh"
WSP_REPO_ROOT="$ROOT"
status=0
wsp_aurelia_install_record \
    github.com/example/cliamp \
    cliamp \
    v2.0.1 \
    cliamp-linux-amd64 \
    "sha256:$PAYLOAD_CHECKSUM" \
    .local/bin/cliamp \
    https://github.com/example/cliamp/releases/download/v2.0.1/cliamp-linux-amd64 || status=$?
printf 'status=%s target=%s marker=%s\n' \
    "$status" \
    "$(cat -- "$HOME/.local/bin/cliamp")" \
    "$(grep -c '^source=github.com/example/cliamp$' "$HOME/state/fedora-hyprland-workstation/package-manager/aurelia/cliamp.owner")"
EOS_MARKER_FAILURE
)"
chmod 0700 "$aurelia_state_dir"
if grep -q 'status=[1-9].*target=cliamp-test-binary marker=1' <<< "$aurelia_marker_failure_output"; then
    pass "Aurelia marker publication failure rolls back the new binary and preserves ownership state"
else
    fail "Aurelia marker failure left an unrecoverable target state: $aurelia_marker_failure_output"
fi

if ! env "${test_env[@]}" "$backend" source remove aurelia github.com/example/cliamp --yes >/dev/null 2>&1 &&
   grep -Fq $'github.com/example/cliamp\t' "$repo/packages/aurelia-sources.tsv"; then
    pass "Aurelia source removal is blocked while a tracked package still depends on it"
else
    fail "Aurelia source removal was allowed to orphan a tracked package"
fi

rm -f -- "$home/.local/bin/cliamp" "$home/state/fedora-hyprland-workstation/package-manager/aurelia/cliamp.owner"
if env "${test_env[@]}" "$backend" restore --aurelia >/dev/null 2>&1 &&
   [[ -x "$home/.local/bin/cliamp" ]] &&
   [[ -e "$home/state/fedora-hyprland-workstation/package-manager/aurelia/cliamp.owner" ]]; then
    pass "Restore reuses the Git-pinned Aurelia release metadata on a future system"
else
    fail "Aurelia restore did not reinstall the pinned user-local binary"
fi

if env "${test_env[@]}" "$backend" remove aurelia github.com/example/cliamp cliamp user --forget --yes >/dev/null 2>&1 &&
   [[ ! -e "$home/.local/bin/cliamp" ]] &&
   [[ ! -e "$home/state/fedora-hyprland-workstation/package-manager/aurelia/cliamp.owner" ]] &&
   ! grep -Fq $'aurelia\t' "$repo/packages/user-managed.tsv" &&
   [[ "$(find "$repo" -type f -name '*.bak' -print -quit)" == "" ]]; then
    pass "Aurelia remove-and-forget removes only the owned binary and declaration without backups or purge semantics"
else
    fail "Aurelia remove-and-forget did not converge safely"
fi

if env "${test_env[@]}" "$backend" source remove aurelia github.com/example/cliamp --yes >/dev/null 2>&1 &&
   ! grep -Fq $'github.com/example/cliamp\t' "$repo/packages/aurelia-sources.tsv"; then
    pass "Aurelia source removal is allowed after its tracked package declaration is removed"
else
    fail "Aurelia source removal did not update the source registry"
fi
