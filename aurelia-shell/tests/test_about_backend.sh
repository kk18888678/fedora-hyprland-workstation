#!/usr/bin/env bash

# Isolated tests for the Aurelia About launcher and native image boundary.

set -Eeuo pipefail

section "Aurelia About Backend"

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

cat >"$mock_bin/foot" <<'EOF_FOOT'
#!/usr/bin/env bash
exit 0
EOF_FOOT

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

chmod 0755 "$mock_bin/kitty" "$mock_bin/foot" "$mock_bin/setsid" "$mock_bin/hyprctl"

about_bin="$ROOT/bin/workstation-about"
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

if [[ -x "$about_bin" ]] &&
   grep -q -- '--logo-type "$LOGO_PROTOCOL"' "$about_bin" &&
   grep -q 'aurelia-mark.png' "$about_bin" &&
   grep -q 'kitty-direct' "$about_bin" &&
   grep -q 'sixel' "$about_bin" &&
   grep -q -- '--pipe false' "$about_bin" &&
   grep -q 'resizewindowpixel' "$about_bin" &&
   grep -q 'resizeactive' "$about_bin" &&
   grep -q 'image-v2' "$about_bin" &&
   grep -q 'initial_window_width=.*INITIAL_COLUMNS' "$about_bin" &&
   grep -q 'window-size-chars.*INITIAL_COLUMNS' "$about_bin" &&
   ! grep -q 'AURELIA_ABOUT_GRAPHICS' "$about_bin" &&
   ! grep -q -- '--logo-type file' "$about_bin" &&
   ! grep -q 'CUSTOM_FASTFETCH_CONFIG' "$about_bin" &&
   ! grep -q 'LOGO_MODE' "$about_bin"; then
    pass "About is native-image-only and cannot fall back to text or Chafa output"
else
    fail "About native image protocol or Aurelia colour boundary is incomplete"
fi

if jq -e \
    '.logo.type == "kitty-direct" and
     .logo.source == "$AURELIA_ABOUT_IMAGE" and
     .logo.width == 54 and
     .logo.height == 26 and
     .logo.preserveAspectRatio == true and
     .logo.padding.top == 2 and
     .logo.padding.left == 2 and
     .logo.padding.right == 6 and
     .display.disableLinewrap == true and
     .modules[2].format == "\u001b[38;2;224;222;244m┌──────────────────────Hardware──────────────────────┐" and
     .modules[3].keyColor == "38;2;156;207;216" and
     .modules[15].keyColor == "38;2;196;167;231" and
     .modules[25].keyColor == "38;2;246;193;119"' \
    "$ROOT/config/fastfetch/config.jsonc" >/dev/null &&
   [[ -f "$ROOT/config/branding/aurelia-mark.svg" &&
      -f "$ROOT/config/branding/aurelia-mark.png" &&
      -x "$ROOT/bin/aurelia-branding-about" ]] &&
   grep -qi '#9ccfd8' "$ROOT/config/branding/aurelia-mark.svg" &&
   grep -qi '#c4a7e7' "$ROOT/config/branding/aurelia-mark.svg" &&
   grep -qi '#f6c177' "$ROOT/config/branding/aurelia-mark.svg" &&
   grep -qi '#e0def4' "$ROOT/config/branding/aurelia-mark.svg"; then
    pass "Native image asset, Fastfetch geometry, and all SVG palette colours are present"
else
    fail "Native About asset or SVG-derived Fastfetch configuration is incomplete"
fi

if file "$ROOT/config/branding/aurelia-mark.png" | grep -q '1024 x 1024'; then
    pass "About uses a high-resolution 1024x1024 Aurelia image asset"
else
    fail "Aurelia native About image is missing or not high resolution"
fi

if grep -Fq 'class = "^org\\.aurelia\\.about$"' "$ROOT/../dotfiles/hypr/windowrules.lua" 2>/dev/null &&
   grep -A6 -Fq 'class = "^org\\.aurelia\\.about$"' "$ROOT/../dotfiles/hypr/windowrules.lua" 2>/dev/null &&
   ! sed -n '/class = "^org\\.aurelia\\.about$"/,/})/p' "$ROOT/../dotfiles/hypr/windowrules.lua" | grep -q 'size ='; then
    pass "Hyprland gives About a safe floating starting size for dynamic fitting"
else
    fail "Hyprland About window rule or starting size is missing"
fi

native_output="$(timeout 10s fastfetch \
    --config "$ROOT/config/fastfetch/config.jsonc" \
    --logo-type kitty-direct \
    --logo "$ROOT/config/branding/aurelia-mark.png" \
    --logo-width 54 \
    --logo-height 26 \
    --pipe false \
    -s host 2>/dev/null)"
if [[ $native_output == *$'\e_G'* ]] && [[ $native_output == *$'\e\\'* ]]; then
    pass "Fastfetch emits a native Kitty graphics sequence for the Aurelia mark"
else
    fail "Fastfetch did not emit the expected native graphics sequence"
fi

config_output="$(AURELIA_ABOUT_IMAGE="$ROOT/config/branding/aurelia-mark.png" timeout 10s fastfetch \
    --config "$ROOT/config/fastfetch/config.jsonc" \
    --pipe false \
    -s host 2>/dev/null)"
if [[ $config_output == *$'\e_G'* ]] && [[ $config_output == *$'\e\\'* ]]; then
    pass "Fastfetch config resolves the native PNG from any working directory"
else
    fail "Fastfetch config did not resolve the absolute native PNG"
fi

printf '%s\n' 'terminal.default = kitty.desktop' >"$mock_config/workstation/desktop.conf"
if env "${test_env[@]}" "$about_bin" open >/dev/null 2>&1 &&
   [[ -s "$launch_log" ]] &&
   launch_args="$(tr '\0' ' ' <"$launch_log")" &&
   [[ "$launch_args" == *"-f env AURELIA_ABOUT_LOGO_PROTOCOL=kitty kitty"* &&
      "$launch_args" == *"--class org.aurelia.about"* &&
      "$launch_args" == *"--title Aurelia About"* &&
      "$launch_args" == *"--override initial_window_width=130c"* &&
      "$launch_args" == *"--override initial_window_height=32c"* &&
      "$launch_args" == *"workstation-about"* &&
      "$launch_args" == *"--render"* ]]; then
    pass "About opens through the configured Kitty terminal with a stable app identity"
else
    fail "About did not launch through the configured Kitty terminal"
fi

: >"$launch_log"
printf '%s\n' 'terminal.default = foot.desktop' >"$mock_config/workstation/desktop.conf"
if env "${test_env[@]}" "$about_bin" open >/dev/null 2>&1 &&
   launch_args="$(tr '\0' ' ' <"$launch_log")" &&
   [[ "$launch_args" == *"-f env AURELIA_ABOUT_LOGO_PROTOCOL=sixel foot"* &&
      "$launch_args" == *"--app-id org.aurelia.about"* ]]; then
    pass "About follows an explicitly selected Foot native-image path"
else
    fail "About ignored the explicitly selected Foot terminal"
fi

rm -f -- "$mock_config/workstation/desktop.conf" "$mock_bin/kitty"
cat >"$mock_bin/xdg-terminal-exec" <<'EOF_XDG'
#!/usr/bin/env bash
exit 0
EOF_XDG
chmod 0755 "$mock_bin/xdg-terminal-exec"
: >"$launch_log"
if env "${test_env[@]}" AURELIA_ABOUT_USE_XDG_TERMINAL=1 "$about_bin" open >/dev/null 2>&1 &&
   launch_args="$(tr '\0' ' ' <"$launch_log")" &&
   [[ "$launch_args" == *"-f xdg-terminal-exec"* &&
      "$launch_args" == *"--app-id=org.aurelia.about"* &&
      "$launch_args" == *"-e"* ]]; then
    pass "About uses xdg-terminal-exec when no Aurelia terminal preference overrides it"
else
    fail "About did not use the dynamic xdg-terminal-exec boundary"
fi

if env "${test_env[@]}" "$about_bin" about >"$fixture/non-tty.out" 2>"$fixture/non-tty.err"; then
    fail "About rendered without an interactive terminal"
elif grep -q 'interactive terminal' "$fixture/non-tty.err"; then
    pass "About fails closed before rendering without a TTY"
else
    fail "About non-interactive failure did not preserve the TTY boundary"
fi
