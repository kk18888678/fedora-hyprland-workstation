#!/usr/bin/env bash

# Isolated tests for the Fedora/Flatpak update backend. No real package manager,
# Flatpak remote, terminal, sudo, or update transaction is executed.

set -Eeuo pipefail

section "Aurelia Fedora and Flatpak Updates Backend"

fixture="$(mktemp -d)"
mock_bin="$fixture/bin"
mock_home="$fixture/home"
mock_config="$mock_home/.config"
mock_log="$fixture/update.log"
launch_log="$fixture/launch.log"
mkdir -p "$mock_bin" "$mock_config/workstation"

cleanup_updates_fixture() {
    rm -rf -- "$fixture"
}
trap cleanup_updates_fixture EXIT

cat >"$mock_bin/dnf5" <<'EOF_DNF'
#!/usr/bin/env bash
if [[ "$1" == "check-update" ]]; then
    if [[ "${MOCK_DNF_UPDATES:-1}" == "1" ]]; then
        printf '%s\n' '{"upgrades":[{"name":"kernel","arch":"x86_64","evr":"1","repository":"updates"},{"name":"kitty","arch":"x86_64","evr":"2","repository":"updates"}]}'
        exit 100
    fi
    printf '%s\n' '{"upgrades":[]}'
    exit 0
fi
if [[ "$1" == "upgrade" ]]; then
    printf 'dnf %s\n' "$*" >>"$WORKSTATION_UPDATES_TEST_LOG"
    exit 0
fi
printf 'unexpected dnf argv: %s\n' "$*" >&2
exit 2
EOF_DNF

cat >"$mock_bin/flatpak" <<'EOF_FLATPAK'
#!/usr/bin/env bash
if [[ "$1" == "remote-ls" ]]; then
    if [[ "$*" == *"--system"* && "${MOCK_FLATPAK_SYSTEM_FAIL:-0}" == "1" ]]; then
        exit 1
    fi
    if [[ "${MOCK_FLATPAK_UPDATES:-1}" == "1" ]]; then
        if [[ "$*" == *"--system"* ]]; then
            printf '%s\n' 'app/org.example.System/x86_64/stable'
        else
            printf '%s\n' 'app/org.example.User/x86_64/stable'
        fi
    fi
    exit 0
fi
if [[ "$1" == "update" ]]; then
    printf 'flatpak %s\n' "$*" >>"$WORKSTATION_UPDATES_TEST_LOG"
    exit 0
fi
printf 'unexpected flatpak argv: %s\n' "$*" >&2
exit 2
EOF_FLATPAK

cat >"$mock_bin/kitty" <<'EOF_KITTY'
#!/usr/bin/env bash
exit 0
EOF_KITTY

cat >"$mock_bin/setsid" <<'EOF_SETSID'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$WORKSTATION_UPDATES_LAUNCH_LOG"
exit 0
EOF_SETSID

chmod 0755 "$mock_bin/dnf5" "$mock_bin/flatpak" "$mock_bin/kitty" "$mock_bin/setsid"

updates_bin="$ROOT/bin/workstation-updates"
test_env=(
    "PATH=$mock_bin:/usr/bin:/bin"
    "HOME=$mock_home"
    "XDG_CONFIG_HOME=$mock_config"
    "WORKSTATION_UPDATES_TEST_LOG=$mock_log"
    "WORKSTATION_UPDATES_LAUNCH_LOG=$launch_log"
)

status_json="$(env "${test_env[@]}" "$updates_bin" status --json)"
if jq -e '
    .schema == 1 and
    .updates_available == true and
    ([.providers[] | select(.id == "fedora")][0].state == "updates") and
    ([.providers[] | select(.id == "fedora")][0].count == 2) and
    ([.providers[] | select(.id == "fedora")][0].items[0].name == "kernel") and
    ([.providers[] | select(.id == "flatpak")][0].count == 2) and
    ([.providers[] | select(.id == "flatpak")][0].items[0].argument | startswith("app/"))
' <<<"$status_json" >/dev/null; then
    pass "Status JSON reports Fedora and Flatpak update providers separately"
else
    fail "Status JSON did not report the expected Fedora and Flatpak updates: $status_json"
fi

no_update_json="$(env "${test_env[@]}" MOCK_DNF_UPDATES=0 MOCK_FLATPAK_UPDATES=0 "$updates_bin" status --json)"
if jq -e '
    .updates_available == false and
    all(.providers[]; .state == "up-to-date" and .count == 0)
' <<<"$no_update_json" >/dev/null; then
    pass "Status JSON distinguishes a fully up-to-date workstation"
else
    fail "Status JSON did not clear the update state: $no_update_json"
fi

partial_json="$(env "${test_env[@]}" MOCK_FLATPAK_SYSTEM_FAIL=1 "$updates_bin" status --json)"
if jq -e '[.providers[] | select(.id == "flatpak")][0].state == "partial"' <<<"$partial_json" >/dev/null; then
    pass "Flatpak scope failures remain visible as partial status"
else
    fail "Flatpak scope failure was incorrectly hidden: $partial_json"
fi

rm -f -- "$launch_log"
printf '%s\n' 'terminal.default = kitty.desktop' >"$mock_config/workstation/desktop.conf"
if env "${test_env[@]}" "$updates_bin" open >/dev/null 2>&1 &&
   [[ -s "$launch_log" ]] &&
   launch_args="$(tr '\0' ' ' <"$launch_log")" &&
   [[ "$launch_args" == *"kitty"* && "$launch_args" == *"menu"* && "$launch_args" == *"workstation-updates"* ]]; then
    pass "Open path launches the single interactive update menu through the configured terminal"
else
    fail "Open path did not produce the expected structured terminal launch"
fi

rm -f -- "$mock_log"
if env "${test_env[@]}" "$updates_bin" update >"$fixture/non-tty.out" 2>"$fixture/non-tty.err"; then
    fail "Update path ran without an interactive terminal"
elif grep -q 'interactive terminal' "$fixture/non-tty.err" && [[ ! -s "$mock_log" ]]; then
    pass "Update path fails closed before mutation without a TTY"
else
    fail "Non-interactive update failure did not preserve the mutation boundary"
fi

if awk '
    /interactive_update "\$\{MENU_ARGS\[@\]\}"/ { saw_transaction=1; next }
    saw_transaction && /MENU_FLOW=exit/ { found_exit_transition=1; exit }
    END { exit(found_exit_transition ? 0 : 1) }
' "$updates_bin"; then
    pass "Completed selective updates leave the terminal menu instead of reopening the picker"
else
    fail "Selective update completion does not have an explicit terminal-exit transition"
fi
