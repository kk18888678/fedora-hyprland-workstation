#!/usr/bin/env bash

# Test Suite: Activation orchestration, failure classification, and application resilience semantics.

section "Activation orchestration"

orch_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

validate_hyprland_desktop() { return 0; }
validate_greeter_configuration() { return 0; }
enable_greetd() { :; }
configure_graphical_target() { :; }
validate_graphical_activation() { return 0; }

unexpected_podman() { return 9; }

run_classified_step workstation "podman" unexpected_podman
echo "after-unexpected-blocked=$ACTIVATION_BLOCKED"
echo "after-unexpected-exit=$(installer_exit_code)"

run_classified_step login "activate" activate_graphical_session
echo "after-podman-activation=$GRAPHICAL_ACTIVATION_STATE"
echo "after-podman-blocked=$ACTIVATION_BLOCKED"
echo "after-podman-exit=$(installer_exit_code)"
EOS
)"

if printf '%s\n' "$orch_output" | grep -q 'after-unexpected-blocked=0'; then
    pass "uncaught Podman failure does not set ACTIVATION_BLOCKED"
else
    fail "uncaught Podman blocked activation: $orch_output"
fi

if printf '%s\n' "$orch_output" | grep -q 'after-unexpected-exit=1'; then
    pass "uncaught required non-login failure produces exit code 1"
else
    fail "uncaught non-login exit code: $orch_output"
fi

if printf '%s\n' "$orch_output" | grep -q 'after-podman-activation=completed'; then
    pass "required non-login failure still permits activate_graphical_session"
else
    fail "activation skipped after Podman failure: $orch_output"
fi

greeter_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

INSTALL_GREETER=true
ENABLE_GRAPHICAL_TARGET=true

validate_hyprland_desktop() { return 0; }
validate_greeter_configuration() { return 1; }

activate_graphical_session
echo "greeter-blocked=$ACTIVATION_BLOCKED"
echo "greeter-activation=$GRAPHICAL_ACTIVATION_STATE"
echo "greeter-exit=$(installer_exit_code)"
EOS
)"

if printf '%s\n' "$greeter_output" | grep -q 'greeter-blocked=1'; then
    pass "greetd/Noctalia greeter validation failure sets ACTIVATION_BLOCKED=1"
else
    fail "greeter must block activation: $greeter_output"
fi

if printf '%s\n' "$greeter_output" | grep -q 'greeter-activation=skipped'; then
    pass "activation is skipped when ACTIVATION_BLOCKED=1"
else
    fail "activation not skipped: $greeter_output"
fi

skip_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="/tmp"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

enabled=0
enable_greetd() { enabled=1; }
configure_graphical_target() { enabled=1; }

ACTIVATION_BLOCKED=1
activate_graphical_session
echo "skip-enable=$enabled"
echo "skip-state=$GRAPHICAL_ACTIVATION_STATE"
EOS
)"

if printf '%s\n' "$skip_output" | grep -q 'skip-enable=0' &&
    printf '%s\n' "$skip_output" | grep -q 'skip-state=skipped'; then
    pass "blocked activation does not enable greetd"
else
    fail "blocked activation still enabled greetd: $skip_output"
fi

section "Resilience Semantics for Applications"

chatgpt_resilience_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

CHATGPT=true
package_installed() { return 1; }
run_with_retry() { return 1; }
install_chatgpt
echo "chatgpt-blocked=$ACTIVATION_BLOCKED"
echo "chatgpt-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$chatgpt_resilience_output" | grep -q 'chatgpt-blocked=0'; then
    pass "ChatGPT bootstrap failure does not set ACTIVATION_BLOCKED"
else
    fail "ChatGPT bootstrap failure set ACTIVATION_BLOCKED: $chatgpt_resilience_output"
fi

if printf '%s\n' "$chatgpt_resilience_output" | grep -q 'chatgpt-exit=2'; then
    pass "ChatGPT failure produces deferred exit code 2"
else
    fail "ChatGPT failure did not produce exit code 2: $chatgpt_resilience_output"
fi

media_resilience_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

MEDIA_APPLICATIONS=true
install_dnf_packages() { return 1; }
install_media_applications
echo "media-blocked=$ACTIVATION_BLOCKED"
echo "media-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$media_resilience_output" | grep -q 'media-blocked=0'; then
    pass "Media applications failure does not set ACTIVATION_BLOCKED"
else
    fail "Media applications failure set ACTIVATION_BLOCKED: $media_resilience_output"
fi

if printf '%s\n' "$media_resilience_output" | grep -q 'media-exit=2'; then
    pass "Media applications failure produces deferred exit code 2"
else
    fail "Media applications failure did not produce exit code 2: $media_resilience_output"
fi

media_cli_decoupling_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

CURSOR=false
KATE=false
CHATGPT=false
ANTIGRAVITY=false
MEDIA_APPLICATIONS=false

media_cli_ran=0
install_media_utilities() {
    media_cli_ran=1
}

install_applications
echo "cli-ran-when-gui-disabled=$media_cli_ran"

MEDIA_APPLICATIONS=true
install_media_applications() {
    record_deferred "applications" "media-apps" "GUI media app failure"
}
media_cli_ran_after_gui_fail=0
install_media_utilities() {
    media_cli_ran_after_gui_fail=1
}

install_applications
echo "cli-ran-after-gui-fail=$media_cli_ran_after_gui_fail"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$media_cli_decoupling_output" | grep -q 'cli-ran-when-gui-disabled=1'; then
    pass "MEDIA_APPLICATIONS=false does not suppress install_media_utilities"
else
    fail "MEDIA_APPLICATIONS=false suppressed install_media_utilities: $media_cli_decoupling_output"
fi

if printf '%s\n' "$media_cli_decoupling_output" | grep -q 'cli-ran-after-gui-fail=1'; then
    pass "GUI media app failure does not prevent install_media_utilities"
else
    fail "GUI media app failure prevented install_media_utilities: $media_cli_decoupling_output"
fi

media_cli_failure_resilience="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/applications.sh"

# Simulate media utility download failure
run_with_retry() { return 1; }
install_media_utilities
echo "cli-fail-blocked=$ACTIVATION_BLOCKED"
echo "cli-fail-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$media_cli_failure_resilience" | grep -q 'cli-fail-blocked=0'; then
    pass "Media CLI failure does not set ACTIVATION_BLOCKED"
else
    fail "Media CLI failure set ACTIVATION_BLOCKED: $media_cli_failure_resilience"
fi

if printf '%s\n' "$media_cli_failure_resilience" | grep -q 'cli-fail-exit=2'; then
    pass "Media CLI failure produces deferred exit code 2"
else
    fail "Media CLI failure did not produce exit code 2: $media_cli_failure_resilience"
fi

media_validation_decoupling="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/validation.sh"

MEDIA_APPLICATIONS=false
CURSOR=false
CHATGPT=false
KATE=false
LOCALSEND=false
ANTIGRAVITY=false

command_exists() { return 1; }
validate_application_environment
echo "validation-def-count=$(grep -c 'Media utility command is missing' <(printf '%s\n' "${INSTALL_DEFERRED[@]}") || true)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$media_validation_decoupling" | grep -qE 'validation-def-count=[1-9]'; then
    pass "Media CLI validation runs independently of MEDIA_APPLICATIONS=false"
else
    fail "Media CLI validation did not run when MEDIA_APPLICATIONS=false: $media_validation_decoupling"
fi

section "Installer Exit Semantics and SIGPIPE Resilience"

# 1. Clean successful run returns exit code 0
clean_exit_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

INTERRUPTED_SIGNAL=0
code=0
final_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" final_code
echo "clean-exit-code=$final_code"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$clean_exit_output" | grep -q 'clean-exit-code=0'; then
    pass "Clean successful run returns exit code 0"
else
    fail "Clean exit code failed: $clean_exit_output"
fi

# 2. Deferred-only completion returns exit code 2 on clean completion (code 0)
deferred_exit_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

record_deferred "applications" "N_m3u8DL-RE" "Checksum mismatch"

INTERRUPTED_SIGNAL=0
code=0
final_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" final_code
echo "deferred-exit-code=$final_code"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$deferred_exit_output" | grep -q 'deferred-exit-code=2'; then
    pass "Deferred-only completion returns exit code 2 on clean completion"
else
    fail "Deferred exit code failed: $deferred_exit_output"
fi

# 3. Classified required failure returns 1
required_exit_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

record_required "packages" "dnf" "Failed to install required package"

INTERRUPTED_SIGNAL=0
code=0
final_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" final_code
echo "required-exit-code=$final_code"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$required_exit_output" | grep -q 'required-exit-code=1'; then
    pass "Classified required failure returns exit code 1"
else
    fail "Required failure did not return 1: $required_exit_output"
fi

# 4. Explicitly trapped external signals preserve signal status (130, 143, 129, 131)
external_sig_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

# Simulate SIGINT (130)
INTERRUPTED_SIGNAL=130
code=130
sigint_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" sigint_code
echo "sigint-exit-code=$sigint_code"

# Simulate SIGTERM (143)
INTERRUPTED_SIGNAL=143
code=143
sigterm_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" sigterm_code
echo "sigterm-exit-code=$sigterm_code"

# Simulate SIGHUP (129)
INTERRUPTED_SIGNAL=129
code=129
sighup_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" sighup_code
echo "sighup-exit-code=$sighup_code"

# Simulate SIGQUIT (131)
INTERRUPTED_SIGNAL=131
code=131
sigquit_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" sigquit_code
echo "sigquit-exit-code=$sigquit_code"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$external_sig_output" | grep -q 'sigint-exit-code=130' &&
   printf '%s\n' "$external_sig_output" | grep -q 'sigterm-exit-code=143' &&
   printf '%s\n' "$external_sig_output" | grep -q 'sighup-exit-code=129' &&
   printf '%s\n' "$external_sig_output" | grep -q 'sigquit-exit-code=131'; then
    pass "Explicitly trapped external signals (130, 143, 129, 131) preserve signal exit codes"
else
    fail "External signals not handled correctly: $external_sig_output"
fi

# 5. Negative regression: unexpected/unclassified fatal status (141, 137, non-zero) fails closed and mutates caller shell state persistently
unexpected_status_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="tester"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"

# Case A: Unexpected 141 (SIGPIPE) with deferred work -> MUST return 1, persistently record login-critical failure, and block activation
record_deferred "applications" "N_m3u8DL-RE" "Checksum mismatch"
INTERRUPTED_SIGNAL=0
code=141
unexpected_141_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" unexpected_141_code
echo "unexpected_141_code=$unexpected_141_code"
echo "unexpected_141_failures=${#INSTALL_LOGIN_FAILURES[@]}"
echo "unexpected_141_blocked=$ACTIVATION_BLOCKED"

# Case B: Unexpected 137 (SIGKILL) with clean state -> MUST return 1 and record failure in caller
INSTALL_LOGIN_FAILURES=()
INSTALL_REQUIRED_FAILURES=()
INSTALL_DEFERRED=()
ACTIVATION_BLOCKED=0
INTERRUPTED_SIGNAL=0
code=137
unexpected_137_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" unexpected_137_code
echo "unexpected_137_code=$unexpected_137_code"
echo "unexpected_137_failures=${#INSTALL_LOGIN_FAILURES[@]}"

# Case C: Unclassified nonzero command failure (e.g. exit 1) -> MUST return 1 and record failure in caller
INSTALL_LOGIN_FAILURES=()
INSTALL_REQUIRED_FAILURES=()
INSTALL_DEFERRED=()
ACTIVATION_BLOCKED=0
INTERRUPTED_SIGNAL=0
code=1
unclassified_nonzero_code=0
resolve_installer_exit_code "$code" "$INTERRUPTED_SIGNAL" unclassified_nonzero_code
echo "unclassified_nonzero_code=$unclassified_nonzero_code"
echo "unclassified_failures=${#INSTALL_LOGIN_FAILURES[@]}"

# Case D: Regression test proving subshell $(...) command substitution loses state mutations
INSTALL_LOGIN_FAILURES=()
ACTIVATION_BLOCKED=0
# If accidentally invoked via subshell:
subshell_result="$(resolve_installer_exit_code 141 0)"
echo "subshell_returned=$subshell_result"
echo "subshell_caller_lost_failures=${#INSTALL_LOGIN_FAILURES[@]}"
echo "subshell_caller_lost_blocked=$ACTIVATION_BLOCKED"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$unexpected_status_output" | grep -q 'unexpected_141_code=1' &&
   printf '%s\n' "$unexpected_status_output" | grep -q 'unexpected_141_failures=1' &&
   printf '%s\n' "$unexpected_status_output" | grep -q 'unexpected_141_blocked=1' &&
   printf '%s\n' "$unexpected_status_output" | grep -q 'unexpected_137_code=1' &&
   printf '%s\n' "$unexpected_status_output" | grep -q 'unexpected_137_failures=1' &&
   printf '%s\n' "$unexpected_status_output" | grep -q 'unclassified_nonzero_code=1' &&
   printf '%s\n' "$unexpected_status_output" | grep -q 'unclassified_failures=1' &&
   printf '%s\n' "$unexpected_status_output" | grep -q 'subshell_caller_lost_failures=0' &&
   printf '%s\n' "$unexpected_status_output" | grep -q 'subshell_caller_lost_blocked=0'; then
    pass "Unexpected fatal status (141, 137, unclassified nonzero) fails closed with persistent caller shell mutations"
else
    fail "Unexpected status did not fail closed or persist mutations: $unexpected_status_output"
fi
