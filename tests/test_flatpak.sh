#!/usr/bin/env bash

# Test Suite: Flatpak source identity and signature-verification settings.

section "Flatpak Source Trust"

if grep -qF 'https://dl.flathub.org/repo/flathub.flatpakrepo' "$ROOT/packages/sources.tsv"; then
    pass "Flathub source manifest uses the authoritative descriptor URL"
else
    fail "Flathub source manifest uses an unexpected URL"
fi

flatpak_source_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
trap 'rm -rf -- "$TARGET_HOME"' EXIT

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/flatpak.sh"

run_with_timeout() {
    shift 2
    "$@"
}

flatpak() {
    [[ "${1:-}" == remotes ]] || return 1
    case "${FLATPAK_FIXTURE:-valid}" in
        valid)
            printf '%s\t%s\t%s\n' \
                flathub \
                https://dl.flathub.org/repo/ \
                ''
            ;;
        wrong-url)
            printf '%s\t%s\t%s\n' \
                flathub \
                https://evil.example/repo/ \
                ''
            ;;
        no-gpg)
            printf '%s\t%s\t%s\n' \
                flathub \
                https://dl.flathub.org/repo/ \
                no-gpg-verify
            ;;
    esac
}

source_url="$(flatpak_source_url_for flathub system)"
valid_status=0
flatpak_source_configured flathub system "$source_url" || valid_status=$?

FLATPAK_FIXTURE=wrong-url wrong_status=0
FLATPAK_FIXTURE=wrong-url flatpak_source_configured flathub system "$source_url" || wrong_status=$?

FLATPAK_FIXTURE=no-gpg no_gpg_status=0
FLATPAK_FIXTURE=no-gpg flatpak_source_configured flathub system "$source_url" || no_gpg_status=$?

printf 'source_url=%s valid=%s wrong_url_rejected=%s no_gpg_rejected=%s\n' \
    "$source_url" "$valid_status" \
    "$([[ $wrong_status -ne 0 ]] && echo 1 || echo 0)" \
    "$([[ $no_gpg_status -ne 0 ]] && echo 1 || echo 0)"
EOS
)"

if grep -q 'source_url=https://dl.flathub.org/repo/flathub.flatpakrepo' <<< "$flatpak_source_test_output" &&
   grep -q 'valid=0' <<< "$flatpak_source_test_output" &&
   grep -q 'wrong_url_rejected=1' <<< "$flatpak_source_test_output" &&
   grep -q 'no_gpg_rejected=1' <<< "$flatpak_source_test_output"; then
    pass "Flatpak source validation requires the declared URL and GPG verification"
else
    fail "Flatpak source trust validation failed: $flatpak_source_test_output"
fi

if grep -q 'flatpak list (LocalSend validation)' "$ROOT/modules/flatpak.sh" &&
   grep -q 'org.localsend.localsend_app' "$ROOT/modules/flatpak.sh"; then
    pass "LocalSend installation validates bounded post-install presence"
else
    fail "LocalSend installation can report success without post-install validation"
fi
