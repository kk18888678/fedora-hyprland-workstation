#!/usr/bin/env bash

# Isolated tests for the Aurelia About branding controls.

set -Eeuo pipefail

section "Aurelia About Branding"

fixture="$(mktemp -d)"
mock_bin="$fixture/bin"
mock_home="$fixture/home"
mock_config="$mock_home/.config"
launch_log="$fixture/launch.log"
mkdir -p -- "$mock_bin" "$mock_config/workstation"
trap 'rm -rf -- "$fixture"' EXIT

cat >"$mock_bin/kitty" <<'EOF_KITTY'
#!/usr/bin/env bash
exit 0
EOF_KITTY

cat >"$mock_bin/setsid" <<'EOF_SETSID'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$AURELIA_ABOUT_LAUNCH_LOG"
exit 0
EOF_SETSID

cat >"$mock_bin/hyprctl" <<'EOF_HYPRCTL'
#!/usr/bin/env bash
if [[ ${1:-} == clients ]]; then
    printf '[]\n'
fi
exit 0
EOF_HYPRCTL

cat >"$mock_bin/editor" <<'EOF_EDITOR'
#!/usr/bin/env bash
printf '%s\n' '$1EDITOR$2' >"$1"
EOF_EDITOR

chmod 0755 "$mock_bin/kitty" "$mock_bin/setsid" "$mock_bin/hyprctl" "$mock_bin/editor"
printf '%s\n' 'terminal.default = kitty.desktop' >"$mock_config/workstation/desktop.conf"

test_env=(
    "PATH=$mock_bin:/usr/bin:/bin"
    "HOME=$mock_home"
    "XDG_CONFIG_HOME=$mock_config"
    "XDG_STATE_HOME=$fixture/state"
    "XDG_RUNTIME_DIR="
    "UWSM_FINALIZE_VARNAMES="
    "UWSM_WAIT_VARNAMES="
    "IN_UWSM_ENV_PRELOADER="
    "AURELIA_ABOUT_LAUNCH_LOG=$launch_log"
)

branding_bin="$ROOT/bin/aurelia-branding-about"
branding_dir="$mock_config/aurelia/branding"
branding_image="$branding_dir/about.png"

if env "${test_env[@]}" "$branding_bin" reset >/dev/null 2>&1 &&
   cmp -s "$branding_image" "$ROOT/config/branding/aurelia-mark.png" &&
   [[ -s "$launch_log" ]]; then
    pass "Restore Default publishes the high-resolution Aurelia mark and reopens About"
else
    fail "Restore Default did not publish the managed native Aurelia About image"
fi

cp -- "$ROOT/config/branding/aurelia-mark.svg" "$fixture/input.svg"
cp -- "$ROOT/config/branding/aurelia-mark.svg" "$fixture/input.txt"
: >"$launch_log"
if env "${test_env[@]}" "$branding_bin" image "$fixture/input.svg" >/dev/null 2>&1 &&
   [[ -s "$branding_image" ]] &&
   [[ -s "$launch_log" ]] &&
   file "$branding_image" | grep -q 'PNG image data' &&
   [[ $(magick identify -format '%wx%h' "$branding_image") == 1024x1024 ]] &&
   cmp -s "$branding_image" "$ROOT/config/branding/aurelia-mark.png"; then
    pass "Set From Image rasterizes the SVG sharply into the managed native PNG"
else
    fail "Set From Image did not produce a native About image"
fi

if env "${test_env[@]}" "$branding_bin" image "$fixture/input.txt" >/dev/null 2>"$fixture/invalid.err"; then
    fail "Set From Image accepted a non-PNG/SVG source"
elif grep -q 'only PNG or SVG' "$fixture/invalid.err"; then
    pass "Set From Image rejects unsupported source types before conversion"
else
    fail "Set From Image returned the wrong unsupported-source diagnostic"
fi
