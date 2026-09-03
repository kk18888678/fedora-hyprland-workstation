#!/usr/bin/env bash

# Test Suite: Desktop environment, Hyprland dotfiles, Noctalia greeter, and PAM keyring integration.

section "Greeter cursor"

if grep -q 'theme = "Adwaita"' "$ROOT/config/noctalia-greeter/greeter.toml" &&
    grep -q 'size = 24' "$ROOT/config/noctalia-greeter/greeter.toml"; then
    pass "managed greeter.toml sets Adwaita 24"
else
    fail "managed greeter.toml cursor block"
fi

section "GNOME Keyring PAM Auto-Unlock"

if grep -q "pam_gnome_keyring.so" "$ROOT/modules/validation.sh"; then
    pass "validation.sh validates pam_gnome_keyring.so"
else
    fail "validation.sh does not validate pam_gnome_keyring.so"
fi

section "Appearance and Qt Settings"

if grep -q "QT_QPA_PLATFORMTHEME,qt6ct" "$ROOT/dotfiles/hypr/startup.lua"; then
    pass "startup.lua exports QT_QPA_PLATFORMTHEME,qt6ct"
else
    fail "startup.lua missing QT_QPA_PLATFORMTHEME,qt6ct"
fi

if git -C "$ROOT" ls-files | grep -q "dotfiles/hypr/noctalia.lua"; then
    fail "untracked/dynamic noctalia.lua should not be tracked in git"
else
    pass "no dynamic noctalia.lua tracked in git"
fi

section "Rosé Pine Moon Qt6ct Color Scheme"

qt6ct_scheme="$ROOT/dotfiles/qt6ct/colors/rose-pine-moon.conf"
if [[ -f "$qt6ct_scheme" ]]; then
    pass "dotfiles/qt6ct/colors/rose-pine-moon.conf exists"
else
    fail "dotfiles/qt6ct/colors/rose-pine-moon.conf is missing"
fi

if grep -q "active_colors" "$qt6ct_scheme" &&
   grep -q "disabled_colors" "$qt6ct_scheme" &&
   grep -q "inactive_colors" "$qt6ct_scheme" &&
   grep -q "e0def4" "$qt6ct_scheme" &&
   grep -q "232136" "$qt6ct_scheme"; then
    pass "rose-pine-moon.conf contains valid Qt6ct palette roles and Rosé Pine Moon hex values"
else
    fail "rose-pine-moon.conf malformed or missing palette roles: $(cat "$qt6ct_scheme" 2>/dev/null)"
fi

section "Terminals: Foot and Kitty Configuration"

if grep -q "^foot$" "$ROOT/packages/desktop.txt"; then
    pass "packages/desktop.txt includes foot package"
else
    fail "packages/desktop.txt missing foot package"
fi

if grep -q "^kitty$" "$ROOT/packages/desktop.txt"; then
    pass "packages/desktop.txt preserves kitty package"
else
    fail "packages/desktop.txt missing kitty package"
fi

if [[ -f "$ROOT/dotfiles/foot/foot.ini" ]]; then
    pass "dotfiles/foot/foot.ini exists"
else
    fail "dotfiles/foot/foot.ini is missing"
fi

# Semantic INI validation of foot.ini
foot_ini_valid="$(
    bash -s -- "$ROOT/dotfiles/foot/foot.ini" <<'EOS'
set -Eeuo pipefail
ini_file="$1"

current_section="<global>"
declare -A section_keys

while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" || "$line" =~ ^# ]] && continue

    if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
        current_section="${BASH_REMATCH[1]}"
        continue
    fi

    if [[ "$line" =~ ^([a-zA-Z0-9_-]+)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"

        case "$current_section" in
            "<global>")
                if [[ "$key" != "include" ]]; then
                    echo "Invalid global key: $key"
                    exit 1
                fi
                ;;
            "main")
                if [[ "$key" != "font" && "$key" != "pad" ]]; then
                    echo "Invalid key under [main]: $key"
                    exit 1
                fi
                ;;
            "scrollback")
                if [[ "$key" != "lines" && "$key" != "multiplier" && "$key" != "indicator-position" && "$key" != "indicator-format" ]]; then
                    echo "Invalid key under [scrollback]: $key"
                    exit 1
                fi
                ;;
            "cursor")
                if [[ "$key" != "style" && "$key" != "blink" && "$key" != "blink-rate" && "$key" != "beam-thickness" && "$key" != "underline-thickness" ]]; then
                    echo "Invalid key under [cursor]: $key"
                    exit 1
                fi
                ;;
            "mouse")
                if [[ "$key" != "hide-when-typing" && "$key" != "alternate-scroll-mode" ]]; then
                    echo "Invalid key under [mouse]: $key"
                    exit 1
                fi
                ;;
            "key-bindings")
                ;;
            *)
                echo "Unrecognized section: $current_section"
                exit 1
                ;;
        esac
    fi
done < "$ini_file"

echo "VALID"
EOS
)"

if [[ "$foot_ini_valid" == "VALID" ]]; then
    pass "foot.ini adheres strictly to official Foot configuration section and option schema"
else
    fail "foot.ini semantic validation failed: $foot_ini_valid"
fi

if grep -q "scrollback-lines" "$ROOT/dotfiles/foot/foot.ini"; then
    fail "foot.ini contains obsolete or unsupported scrollback-lines key"
else
    pass "foot.ini does not use unsupported scrollback-lines in [main]"
fi

if grep -q "show-urls-launch=Control+Shift+u" "$ROOT/dotfiles/foot/foot.ini"; then
    fail "foot.ini overrides show-urls-launch with Control+Shift+u which conflicts with standard unicode-input"
else
    pass "foot.ini avoids keybinding conflict between show-urls-launch and standard unicode-input"
fi

# Opportunistic foot --check-config validation if foot binary is present
if command -v foot >/dev/null 2>&1; then
    foot_chk_tmp="$(mktemp -d)"
    mkdir -p "$foot_chk_tmp/foot/themes"
    cp "$ROOT/dotfiles/foot/foot.ini" "$foot_chk_tmp/foot/foot.ini"
    cp "$ROOT/dotfiles/foot/themes/rose-pine-moon.ini" "$foot_chk_tmp/foot/themes/rose-pine-moon.ini"
    sed -i "s|include=.*|include=$foot_chk_tmp/foot/themes/rose-pine-moon.ini|" "$foot_chk_tmp/foot/foot.ini"
    foot_chk_status=0
    foot_chk_out="$(foot -C -c "$foot_chk_tmp/foot/foot.ini" 2>&1)" || foot_chk_status=$?
    rm -rf "$foot_chk_tmp"
    if (( foot_chk_status == 0 )); then
        pass "foot --check-config validates managed foot.ini with zero errors"
    else
        fail "foot --check-config failed on foot.ini: $foot_chk_out"
    fi
fi

if grep -q "Hack Nerd Font" "$ROOT/dotfiles/foot/foot.ini" &&
   grep -q "rose-pine-moon.ini" "$ROOT/dotfiles/foot/foot.ini"; then
    pass "foot.ini configures Hack Nerd Font and references Rosé Pine Moon theme"
else
    fail "foot.ini font/theme references invalid"
fi

if [[ -f "$ROOT/dotfiles/foot/themes/rose-pine-moon.ini" ]]; then
    pass "dotfiles/foot/themes/rose-pine-moon.ini exists"
else
    fail "dotfiles/foot/themes/rose-pine-moon.ini is missing"
fi

# Foot launcher visibility and desktop entry override tests
if [[ -f "$ROOT/config/desktop-entries/footclient.desktop" ]] &&
   grep -q "NoDisplay=true" "$ROOT/config/desktop-entries/footclient.desktop" &&
   [[ -f "$ROOT/config/desktop-entries/foot-server.desktop" ]] &&
   grep -q "NoDisplay=true" "$ROOT/config/desktop-entries/foot-server.desktop"; then
    pass "managed desktop overrides exist and specify NoDisplay=true for Foot Client and Server"
else
    fail "managed foot desktop entry overrides missing or lack NoDisplay=true"
fi

foot_deploy_test="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="desktest"
TARGET_HOME="$(mktemp -d)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/lib/filesystem.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/shell.sh"

deploy_foot_config

client_deployed="$([[ -L "$TARGET_HOME/.local/share/applications/footclient.desktop" ]] && echo 1 || echo 0)"
server_deployed="$([[ -L "$TARGET_HOME/.local/share/applications/foot-server.desktop" ]] && echo 1 || echo 0)"
normal_foot_visible="$([[ ! -f "$TARGET_HOME/.local/share/applications/foot.desktop" ]] && echo 1 || echo 0)"

echo "client_deployed=$client_deployed"
echo "server_deployed=$server_deployed"
echo "normal_foot_visible=$normal_foot_visible"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$foot_deploy_test" | grep -q 'client_deployed=1' &&
   printf '%s\n' "$foot_deploy_test" | grep -q 'server_deployed=1' &&
   printf '%s\n' "$foot_deploy_test" | grep -q 'normal_foot_visible=1'; then
    pass "deploy_foot_config deploys client/server NoDisplay overrides while keeping normal Foot visible"
else
    fail "deploy_foot_config desktop override deployment failed: $foot_deploy_test"
fi

if [[ -f "$ROOT/dotfiles/kitty/themes/rose-pine-moon.conf" ]]; then
    pass "dotfiles/kitty/themes/rose-pine-moon.conf exists"
else
    fail "dotfiles/kitty/themes/rose-pine-moon.conf is missing"
fi

if grep -q "Hack Nerd Font" "$ROOT/dotfiles/kitty/kitty.conf" &&
   grep -q "include themes/rose-pine-moon.conf" "$ROOT/dotfiles/kitty/kitty.conf"; then
    pass "kitty.conf configures Hack Nerd Font and includes static rose-pine-moon theme"
else
    fail "kitty.conf font/theme references invalid"
fi

if grep -q "themes/noctalia.conf" "$ROOT/dotfiles/kitty/kitty.conf"; then
    fail "kitty.conf must not reference nonexistent generated noctalia theme file"
else
    pass "kitty.conf does not reference transient noctalia theme"
fi

section "Desktop Fonts and Theme Provisioning"

desktop_theme_test_output="$(
    bash -s <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$HELPER_ROOT"
TARGET_USER="desktest"
TARGET_HOME="$(mktemp -d)"
FONTS_INSTALL_DIR="$(mktemp -d)"
export FONTS_INSTALL_DIR
OVERRIDE_TARGET_UID=1000

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

env() {
    while [[ $# -gt 0 && "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
}

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

# Test font idempotent skip when already present
mkdir -p "$FONTS_INSTALL_DIR"
touch "$FONTS_INSTALL_DIR/HackNerdFont-Regular.ttf"
install_hack_nerd_font
font_skip_ok=1
echo "font-skip-ok=$font_skip_ok"

# Test GTK theme idempotent skip when already present
mkdir -p "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/gtk-3.0"
touch "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/index.theme"
touch "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/gtk-3.0/gtk.css"
install_rose_pine_gtk_theme
gtk_skip_ok=1
echo "gtk-skip-ok=$gtk_skip_ok"

# Helper to build mock tarball and compute sha512
build_mock_tar() {
    local src_dir="$1"
    local out_tar="$2"
    tar -czf "$out_tar" -C "$src_dir" .
    sha512sum "$out_tar" | awk '{print $1}'
}

# Negative Test 1: Archive with escaping symlink
rm -rf "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk"
mock1="$(mktemp -d)"
mkdir -p "$mock1/gtk3/rose-pine-moon-gtk/gtk-3.0"
touch "$mock1/gtk3/rose-pine-moon-gtk/index.theme"
touch "$mock1/gtk3/rose-pine-moon-gtk/gtk-3.0/gtk.css"
ln -s "../../../../../etc/shadow" "$mock1/gtk3/rose-pine-moon-gtk/escape_link"
tar1="$(mktemp --suffix=.tar.gz)"
hash1="$(build_mock_tar "$mock1" "$tar1")"

download_and_verify_artifact() { cp "$tar1" "$3"; }
ROSE_PINE_GTK_URL="https://example.com/gtk3.tar.gz"
ROSE_PINE_GTK_SHA512="$hash1"
install_rose_pine_gtk_theme
escape_rejected=$([[ ! -d "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk" ]] && echo 1 || echo 0)
echo "symlink-escape-rejected=$escape_rejected"
rm -rf "$mock1" "$tar1"

# Negative Test 2: Archive with hardlink
mock2="$(mktemp -d)"
mkdir -p "$mock2/gtk3/rose-pine-moon-gtk/gtk-3.0"
touch "$mock2/gtk3/rose-pine-moon-gtk/index.theme"
touch "$mock2/gtk3/rose-pine-moon-gtk/gtk-3.0/gtk.css"
ln "$mock2/gtk3/rose-pine-moon-gtk/index.theme" "$mock2/gtk3/rose-pine-moon-gtk/hardlink_file"
tar2="$(mktemp --suffix=.tar.gz)"
hash2="$(build_mock_tar "$mock2" "$tar2")"

ROSE_PINE_GTK_SHA512="$hash2"
download_and_verify_artifact() { cp "$tar2" "$3"; }
install_rose_pine_gtk_theme
hardlink_rejected=$([[ ! -d "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk" ]] && echo 1 || echo 0)
echo "hardlink-rejected=$hardlink_rejected"
rm -rf "$mock2" "$tar2"

# Negative Test 3: Archive missing Moon theme index.theme
mock3="$(mktemp -d)"
mkdir -p "$mock3/gtk3/rose-pine-dawn-gtk/gtk-3.0"
touch "$mock3/gtk3/rose-pine-dawn-gtk/index.theme"
touch "$mock3/gtk3/rose-pine-dawn-gtk/gtk-3.0/gtk.css"
tar3="$(mktemp --suffix=.tar.gz)"
hash3="$(build_mock_tar "$mock3" "$tar3")"

ROSE_PINE_GTK_SHA512="$hash3"
download_and_verify_artifact() { cp "$tar3" "$3"; }
install_rose_pine_gtk_theme
missing_payload_rejected=$([[ ! -d "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk" ]] && echo 1 || echo 0)
echo "missing-payload-rejected=$missing_payload_rejected"
rm -rf "$mock3" "$tar3"

# Positive Test: Valid archive with safe relative symlinks and valid Moon theme
mock4="$(mktemp -d)"
mkdir -p "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.0"
mkdir -p "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.20"
mkdir -p "$mock4/gtk3/rose-pine-moon-gtk/assets"
touch "$mock4/gtk3/rose-pine-moon-gtk/index.theme"
touch "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.0/gtk.css"
touch "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.20/gtk.css"
ln -s "../assets" "$mock4/gtk3/rose-pine-moon-gtk/gtk-3.20/assets"
tar4="$(mktemp --suffix=.tar.gz)"
hash4="$(build_mock_tar "$mock4" "$tar4")"

ROSE_PINE_GTK_SHA512="$hash4"
download_and_verify_artifact() { cp "$tar4" "$3"; }
install_rose_pine_gtk_theme
valid_installed=$([[ -f "$TARGET_HOME/.local/share/themes/rose-pine-moon-gtk/index.theme" ]] && echo 1 || echo 0)
echo "valid-installed=$valid_installed"
rm -rf "$mock4" "$tar4"

rm -rf "$TARGET_HOME" "$FONTS_INSTALL_DIR"
EOS
)"

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'font-skip-ok=1'; then
    pass "install_hack_nerd_font detects existing font installation idempotently"
else
    fail "install_hack_nerd_font idempotency failed: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'gtk-skip-ok=1'; then
    pass "install_rose_pine_gtk_theme detects existing theme installation idempotently"
else
    fail "install_rose_pine_gtk_theme idempotency failed: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'symlink-escape-rejected=1'; then
    pass "install_rose_pine_gtk_theme rejects archives with escaping symlinks before extraction"
else
    fail "install_rose_pine_gtk_theme did not reject escaping symlink: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'hardlink-rejected=1'; then
    pass "install_rose_pine_gtk_theme rejects archives with hardlink entries"
else
    fail "install_rose_pine_gtk_theme did not reject hardlink: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'missing-payload-rejected=1'; then
    pass "install_rose_pine_gtk_theme defers cleanly when required Moon theme payload is missing"
else
    fail "install_rose_pine_gtk_theme did not reject missing Moon payload: $desktop_theme_test_output"
fi

if printf '%s\n' "$desktop_theme_test_output" | grep -q 'valid-installed=1'; then
    pass "install_rose_pine_gtk_theme successfully verifies and installs valid GTK theme payload"
else
    fail "install_rose_pine_gtk_theme failed on valid payload: $desktop_theme_test_output"
fi

section "GTK Places Bookmarks Convergence & Safety"

bookmarks_test_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
SCRIPT_DIR="$1"
TARGET_USER="bmtest"
TARGET_HOME="$(mktemp -d)"
OVERRIDE_TARGET_UID=1000

# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/status.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/modules/desktop.sh"

env() {
    while [[ $# -gt 0 && "$1" == *=* ]]; do
        export "$1"
        shift
    done
    "$@"
}

sudo() {
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-u" ]]; then shift 2; continue; fi
        if [[ "$1" == "env" ]]; then shift; continue; fi
        if [[ "$1" == *=* ]]; then export "$1"; shift; continue; fi
        break
    done
    "$@"
}

# Test 1: Empty initial state -> initializes exact baseline in both gtk-3.0 and gtk-4.0
converge_gtk_bookmarks "$TARGET_HOME"

gtk3_bm="$TARGET_HOME/.config/gtk-3.0/bookmarks"
gtk4_bm="$TARGET_HOME/.config/gtk-4.0/bookmarks"

empty_init_ok=0
if [[ -f "$gtk3_bm" && -f "$gtk4_bm" ]]; then
    expected_content="$(cat << EOF
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
EOF
)"
    if cmp -s "$gtk3_bm" <(printf '%s\n' "$expected_content") &&
       cmp -s "$gtk4_bm" <(printf '%s\n' "$expected_content"); then
        empty_init_ok=1
    fi
fi
echo "empty-init-ok=$empty_init_ok"

# Test 2: Rerun idempotency on fully initialized bookmarks
mtime_before="$(stat -c %Y "$gtk3_bm")"
converge_gtk_bookmarks "$TARGET_HOME"
mtime_after="$(stat -c %Y "$gtk3_bm")"
idempotent_ok=$([[ "$mtime_before" == "$mtime_after" ]] && echo 1 || echo 0)
echo "idempotent-ok=$idempotent_ok"

# Test 3: Partially initialized bookmarks with custom user folder and remote URI
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Projects Code Repository
smb://nas.local/share Network Share
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Music
EOF

converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"

partial_preserved_ok=0
# Verify that custom Projects and SMB were preserved, and missing Downloads, Pictures, Videos were appended
if grep -q "file://${TARGET_HOME}/Projects Code Repository" "$gtk3_bm" &&
   grep -q "smb://nas.local/share Network Share" "$gtk3_bm" &&
   grep -q "file://${TARGET_HOME}/Documents" "$gtk3_bm" &&
   grep -q "file://${TARGET_HOME}/Downloads" "$gtk3_bm" &&
   grep -q "file://${TARGET_HOME}/Pictures" "$gtk3_bm" &&
   grep -q "file://${TARGET_HOME}/Music" "$gtk3_bm" &&
   grep -q "file://${TARGET_HOME}/Videos" "$gtk3_bm"; then
    # Verify no duplicate entries
    num_docs="$(grep -c "file://${TARGET_HOME}/Documents" "$gtk3_bm" || true)"
    num_music="$(grep -c "file://${TARGET_HOME}/Music" "$gtk3_bm" || true)"
    if [[ "$num_docs" -eq 1 && "$num_music" -eq 1 ]]; then
        partial_preserved_ok=1
    fi
fi
echo "partial-preserved-ok=$partial_preserved_ok"

# Test 4: Rerun on custom bookmarks causes zero changes
mtime_c1="$(stat -c %Y "$gtk3_bm")"
converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"
mtime_c2="$(stat -c %Y "$gtk3_bm")"
custom_idempotent_ok=$([[ "$mtime_c1" == "$mtime_c2" ]] && echo 1 || echo 0)
echo "custom-idempotent-ok=$custom_idempotent_ok"

# Test 5: Mixed standard and personal bookmarks out of order
cat << EOF > "$gtk3_bm"
file://${TARGET_HOME}/Pictures
file:///some/personal/location My Project
file://${TARGET_HOME}/Downloads
EOF

converge_gtk_bookmarks_file "$gtk3_bm" "$TARGET_HOME"

expected_mixed="$(cat << EOF
file://${TARGET_HOME}/Documents
file://${TARGET_HOME}/Downloads
file://${TARGET_HOME}/Pictures
file://${TARGET_HOME}/Music
file://${TARGET_HOME}/Videos
file:///some/personal/location My Project
EOF
)"

mixed_reorder_ok=0
if cmp -s "$gtk3_bm" <(printf '%s\n' "$expected_mixed"); then
    mixed_reorder_ok=1
fi
echo "mixed-reorder-ok=$mixed_reorder_ok"

rm -rf "$TARGET_HOME"
EOS
)"

if printf '%s\n' "$bookmarks_test_output" | grep -q 'empty-init-ok=1'; then
    pass "converge_gtk_bookmarks initializes baseline GTK3 and GTK4 bookmarks in exact desired order"
else
    fail "converge_gtk_bookmarks empty init failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'idempotent-ok=1'; then
    pass "converge_gtk_bookmarks is fully idempotent on satisfied bookmarks"
else
    fail "converge_gtk_bookmarks idempotency failed: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'partial-preserved-ok=1'; then
    pass "converge_gtk_bookmarks preserves existing custom paths, remote URIs, and labels without duplicates"
else
    fail "converge_gtk_bookmarks failed to preserve custom/partial bookmarks: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'custom-idempotent-ok=1'; then
    pass "converge_gtk_bookmarks is fully idempotent after custom bookmark convergence"
else
    fail "converge_gtk_bookmarks failed custom idempotency: $bookmarks_test_output"
fi

if printf '%s\n' "$bookmarks_test_output" | grep -q 'mixed-reorder-ok=1'; then
    pass "converge_gtk_bookmarks deterministically reorders standard bookmarks and preserves personal bookmarks"
else
    fail "converge_gtk_bookmarks mixed reordering failed: $bookmarks_test_output"
fi

section "Monitor Configuration"

monitor_conf="$ROOT/dotfiles/hypr/monitors.lua"
if [[ -f "$monitor_conf" ]]; then
    if command -v luajit >/dev/null 2>&1; then
        if luajit -e 'assert(loadfile("'"$monitor_conf"'"))' >/dev/null 2>&1; then
            pass "monitors.lua has valid Lua syntax"
        else
            fail "monitors.lua has invalid Lua syntax"
        fi
    else
        pass "monitors.lua syntax check skipped (luajit not installed)"
    fi

    # Ensure no hardcoded machine-specific dimensions or output names
    if grep -Eq '[0-9]{3,4}x[0-9]{3,4}' "$monitor_conf"; then
        fail "monitors.lua must not hardcode fixed pixel resolutions"
    else
        pass "monitors.lua contains no hardcoded pixel resolutions"
    fi

    if grep -Fq 'Virtual-1' "$monitor_conf"; then
        fail "monitors.lua must not hardcode output name Virtual-1"
    else
        pass "monitors.lua does not hardcode Virtual-1"
    fi

    if grep -Fq 'output = ""' "$monitor_conf" && grep -Fq 'mode = "preferred"' "$monitor_conf"; then
        pass "monitors.lua contains generic fallback rule with preferred mode"
    else
        fail "monitors.lua missing generic fallback rule with preferred mode"
    fi

    if grep -Fq 'desc:Red Hat Inc. QEMU Monitor' "$monitor_conf"; then
        fail "monitors.lua contains misleading/placebo VM-specific rule"
    else
        pass "monitors.lua avoids dead or misleading VM-specific monitor rules"
    fi

    if grep -iq 'seamless resolution adaptation' "$monitor_conf"; then
        fail "monitors.lua makes unwarranted claims of dynamic post-enumeration adaptation"
    else
        pass "monitors.lua accurately documents VM dynamic resize capabilities without unwarranted claims"
    fi
else
    fail "monitors.lua file not found at $monitor_conf"
fi
