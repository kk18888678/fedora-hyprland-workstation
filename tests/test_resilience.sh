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
configure_chatgpt_repository() { return 1; }
install_chatgpt
echo "chatgpt-blocked=$ACTIVATION_BLOCKED"
echo "chatgpt-exit=$(installer_exit_code)"
rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$chatgpt_resilience_output" | grep -q 'chatgpt-blocked=0'; then
    pass "ChatGPT repository failure does not set ACTIVATION_BLOCKED"
else
    fail "ChatGPT repository failure set ACTIVATION_BLOCKED: $chatgpt_resilience_output"
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
