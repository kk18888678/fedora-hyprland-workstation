#!/usr/bin/env bash

# Isolated tests for the Aurelia About ANSI sheen builder.

set -Eeuo pipefail

section "Aurelia About Animation"

fixture="$(mktemp -d)"
logo="$fixture/logo.txt"
trap 'rm -rf -- "$fixture"' EXIT

# shellcheck source=/dev/null
source "$ROOT/bin/aurelia-branding-about-animation"

SHEEN_COLOR_1=$'\e[1m\e[38;2;156;207;216m'
SHEEN_COLOR_2=$'\e[1m\e[38;2;196;167;231m'
SHEEN_COLOR_3=$'\e[1m\e[38;2;246;193;119m'
SHEEN_COLOR_4=$'\e[1m\e[38;2;224;222;244m'
SHEEN_DEFAULT_COLOR="$SHEEN_COLOR_1"

printf '%s\n' '$1████$2██' '  $3██$4  ' >"$logo"
if sheen_build "$logo" 3 3 $'\e[0m\e[1m\e[38;2;156;207;216m' 120; then
    pass "coloured Aurelia terminal art produces animation frames"
else
    fail "coloured Aurelia terminal art was rejected"
fi

if (( ${#SHEEN_FRAMES[@]} > 10 )) &&
   [[ ${SHEEN_LINES[0]} == '██████' ]] &&
   [[ ${SHEEN_LINES[1]} == '  ██  ' ]] &&
   [[ ${SHEEN_FRAMES[0]} == *$'\e[38;2;156;207;216m'* ]] &&
   [[ ${SHEEN_FRAMES[0]} == *$'\e[38;2;246;193;119m'* ]]; then
    pass "animation expands placeholders without changing terminal geometry"
else
    fail "animation placeholder expansion or frame colour state is incomplete"
fi

printf '%s\n' 'AAA中文BBB' >"$logo"
if sheen_build "$logo" 3 3 "$SHEEN_COLOR_1" 120; then
    fail "double-width logo characters were accepted for animation"
else
    pass "double-width logo characters leave the logo still"
fi

printf '%s\n' '$8AAA' >"$logo"
if sheen_build "$logo" 3 3 "$SHEEN_COLOR_1" 120; then
    fail "unconfigured colour placeholders were accepted"
else
    pass "unconfigured colour placeholders fail closed"
fi
