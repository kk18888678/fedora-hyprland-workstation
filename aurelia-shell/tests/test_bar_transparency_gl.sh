#!/usr/bin/env bash

# Offscreen OpenGL runtime regression for the transparent bar's legibility
# halo. The transparent bar keeps its content legible with a non-surface
# MultiEffect shadow on the content layer. A plain software offscreen backend
# silently drops shader effects, so this suite runs the fixture with
# QT_QUICK_BACKEND=opengl and proves the shadow was actually applied (shadow
# pixels exist) as well as that the layered content survived (content pixels
# exist). When the host's offscreen QPA cannot create an OpenGL context the
# suite reports an environment skip rather than passing under a software
# renderer.

set -Eeuo pipefail

section "Aurelia Transparent Bar OpenGL Halo"

panel_file="$ROOT/plugins/aurelia.bar/BarPanel.qml"
fixture="$ROOT/tests/fixtures/bar-transparency/shell.qml"

# The runtime fixture must mirror the real panel's unconditional strong halo
# parameters; otherwise it could pass while the production halo regressed.
if grep -Fq 'shadowOpacity: 0.95' "$panel_file" &&
   grep -Fq 'shadowBlur: 0.55' "$panel_file" &&
   grep -Fq 'shadowOpacity: 0.95' "$fixture" &&
   grep -Fq 'shadowBlur: 0.55' "$fixture"; then
    pass "[static] the OpenGL runtime fixture mirrors the panel's unconditionally strong halo parameters"
else
    fail "[static] the OpenGL runtime fixture or panel halo parameters are incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] transparent-bar OpenGL halo fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" || true' RETURN
runtime_result="$runtime_root/result.json"
runtime_image="$runtime_root/grab.png"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
: >"$runtime_result"

QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=opengl \
QSG_INFO=1 \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CACHE_HOME="$runtime_root/cache" \
AURELIA_BAR_TRANSPARENCY_RESULT="$runtime_result" \
AURELIA_BAR_TRANSPARENCY_IMAGE="$runtime_image" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$fixture" >"$runtime_log" 2>&1 || runtime_status=$?

# An offscreen QPA without OpenGL context support cannot exercise the shader
# effect. Never accept a software fallback as a pass: report the environment
# limitation explicitly instead.
if grep -Eq "Could not create scene graph context for backend 'opengl'|QRhiGles2: Failed to create|Failed to initialize graphics backend for OpenGL|scenegraph is not functional|Loading backend software" "$runtime_log"; then
    skip "[isolated-runtime] transparent-bar OpenGL halo fixture (offscreen QPA cannot create an OpenGL context on this host)"
    return 0
fi

if [[ ! -x /usr/bin/magick ]]; then
    skip "[isolated-runtime] transparent-bar OpenGL halo fixture (ImageMagick unavailable)"
    return 0
fi

if [[ "$runtime_status" -eq 0 && -s "$runtime_result" && -s "$runtime_image" ]] &&
   jq -e '
       .layerEnabled == true and
       .effectPresent == true and
       .effectShadowEnabled == true and
       .contentPresent == true and
       .imageSaved == true
   ' "$runtime_result" >/dev/null &&
   runtime_log_is_environment_only "$runtime_log"; then
    red_pixels="$(magick "$runtime_image" -depth 8 txt:- | grep -c '#FF0000' || true)"
    green_pixels="$(magick "$runtime_image" -depth 8 txt:- | grep -c '#00FF00' || true)"
    content_pixels=$((red_pixels + green_pixels))
    shadow_pixels="$(magick "$runtime_image" -depth 8 txt:- |
        grep -E '^[0-9]+,[0-9]+:' |
        grep -cvE '#000000|#FF0000|#00FF00' || true)"
    if (( content_pixels > 0 && shadow_pixels > 0 )); then
        pass "[isolated-runtime] offscreen OpenGL renders the layered bar content and applies the MultiEffect halo shadow (content=$content_pixels shadow=$shadow_pixels)"
    else
        fail "[isolated-runtime] offscreen OpenGL dropped layered content or the MultiEffect halo (content=$content_pixels shadow=$shadow_pixels)"
    fi
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] transparent-bar OpenGL halo fixture failed (status=$runtime_status): $details"
fi
