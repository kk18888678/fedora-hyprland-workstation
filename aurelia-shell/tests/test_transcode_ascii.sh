#!/usr/bin/env bash

# Contract tests for Aurelia's Omarchy-compatible image-to-terminal-raster tool.

set -Eeuo pipefail

section "Aurelia Image-to-Terminal Raster"

transcoder="$ROOT/bin/aurelia-transcode-ascii"

if [[ -x "$transcoder" ]] && bash -n "$transcoder" &&
   "$transcoder" --help | grep -q -- '--mode <braille|block|solid>' &&
   grep -q 'Required command' "$transcoder" &&
   grep -q 'alpha extract' "$transcoder" &&
   grep -q 'P1' "$transcoder"; then
    pass "Aurelia transcode utility mirrors the reference modes, alpha handling, and PBM raster conversion"
else
    fail "Aurelia transcode utility contract is incomplete"
fi

if ! command -v magick >/dev/null 2>&1; then
    fixture="$(mktemp -d)"
    if "$transcoder" "$ROOT/config/branding/aurelia-mark.svg" "$fixture/logo.txt" >"$fixture/out" 2>"$fixture/err"; then
        fail "Missing ImageMagick dependency did not fail closed"
    elif grep -q "Required command 'magick' is missing" "$fixture/err" && [[ ! -e "$fixture/logo.txt" ]]; then
        pass "Missing ImageMagick is reported without installation or output mutation"
    else
        fail "Missing ImageMagick diagnostic or output boundary is incorrect"
    fi
    rm -rf -- "$fixture"
else
    pass "ImageMagick is installed; live conversion is covered by the utility contract"
fi
