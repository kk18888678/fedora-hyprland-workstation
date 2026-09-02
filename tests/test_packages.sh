#!/usr/bin/env bash

# Test Suite: Package manifests and profile validation.

section "Package manifests"

assert_not_in_manifest() {
    local name="$1"

    if grep -h -vE '^\s*#' "$ROOT"/packages/*.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qx "$name"; then
        fail "forbidden package present: $name"
    else
        pass "forbidden package absent: $name"
    fi
}

assert_in_manifest() {
    local file="$1"
    local name="$2"

    if grep -h -vE '^\s*#' "$ROOT/$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qx "$name"; then
        pass "$name in $file"
    else
        fail "$name missing from $file"
    fi
}

# Legacy/incompatible Fedora packages
assert_not_in_manifest mesa-vdpau-drivers
assert_not_in_manifest p7zip
assert_not_in_manifest p7zip-plugins
assert_not_in_manifest wget

# Project development toolchains forbidden from Fedora host manifests
assert_not_in_manifest pyenv
assert_not_in_manifest nvm
assert_not_in_manifest rustup
assert_not_in_manifest docker-ce
assert_not_in_manifest docker
assert_not_in_manifest nodejs
assert_not_in_manifest npm
assert_not_in_manifest rustc
assert_not_in_manifest cargo
assert_not_in_manifest golang
assert_not_in_manifest gradle
assert_not_in_manifest maven
assert_not_in_manifest dotnet-sdk
assert_not_in_manifest clang
assert_not_in_manifest cmake
assert_not_in_manifest meson
assert_not_in_manifest ninja-build
assert_not_in_manifest pkgconf
assert_not_in_manifest rocm-opencl
assert_not_in_manifest rocm-hip
assert_not_in_manifest steam
assert_not_in_manifest mangohud
assert_not_in_manifest wine
assert_not_in_manifest winetricks
assert_not_in_manifest os-prober
assert_not_in_manifest gnome-software

assert_in_manifest packages/base.txt wget2-wget
assert_in_manifest packages/base.txt 7zip
assert_in_manifest packages/base.txt 7zip-standalone
assert_in_manifest packages/desktop.txt hyprland
assert_in_manifest packages/desktop.txt noctalia
assert_in_manifest packages/desktop.txt greetd
assert_in_manifest packages/desktop.txt hyprpolkitagent
assert_in_manifest packages/desktop.txt gnome-keyring
assert_in_manifest packages/desktop.txt gnome-keyring-pam
assert_in_manifest packages/desktop.txt xdg-desktop-portal-hyprland
assert_in_manifest packages/desktop.txt adwaita-cursor-theme
assert_in_manifest packages/desktop.txt adw-gtk3-theme
assert_in_manifest packages/desktop.txt yaru-icon-theme
assert_in_manifest packages/desktop.txt qt6-qtbase
assert_in_manifest packages/desktop.txt qt6-qtwayland
assert_in_manifest packages/desktop.txt qt6ct
assert_in_manifest packages/desktop.txt nwg-look
assert_in_manifest packages/desktop.txt thunar
assert_in_manifest packages/desktop.txt thunar-archive-plugin
assert_in_manifest packages/desktop.txt thunar-volman
assert_in_manifest packages/desktop.txt thunar-media-tags-plugin
assert_in_manifest packages/desktop.txt file-roller
assert_in_manifest packages/desktop.txt gvfs
assert_in_manifest packages/desktop.txt gvfs-mtp
assert_in_manifest packages/desktop.txt gvfs-smb
assert_in_manifest packages/desktop.txt gvfs-afc
assert_in_manifest packages/desktop.txt xdg-user-dirs
assert_in_manifest packages/desktop.txt tumbler
assert_in_manifest packages/desktop.txt ffmpegthumbnailer
assert_in_manifest packages/desktop.txt poppler-glib
assert_in_manifest packages/desktop.txt libgsf
assert_in_manifest packages/desktop.txt libopenraw
assert_in_manifest packages/desktop.txt gnome-disk-utility
assert_in_manifest packages/desktop.txt gnome-calculator
assert_in_manifest packages/desktop.txt loupe
assert_in_manifest packages/desktop.txt dejavu-sans-fonts
assert_in_manifest packages/base.txt zsh
assert_in_manifest packages/base.txt starship
assert_in_manifest packages/media.txt ffmpeg
assert_in_manifest packages/media.txt mediainfo
assert_in_manifest packages/media.txt mkvtoolnix
assert_in_manifest packages/media.txt gpac
assert_in_manifest packages/diagnostics.txt smartmontools
assert_in_manifest packages/diagnostics.txt nvme-cli
assert_in_manifest packages/diagnostics.txt inxi
assert_in_manifest packages/diagnostics.txt lm_sensors
assert_in_manifest packages/diagnostics.txt htop
assert_in_manifest packages/diagnostics.txt btop
assert_in_manifest packages/diagnostics.txt iotop-c
assert_in_manifest packages/diagnostics.txt sysstat
assert_in_manifest packages/diagnostics.txt lsof
assert_in_manifest packages/diagnostics.txt strace
assert_in_manifest packages/diagnostics.txt nethogs
assert_in_manifest packages/diagnostics.txt duf
assert_in_manifest packages/diagnostics.txt ncdu
assert_in_manifest packages/diagnostics.txt btrfs-progs

if grep -h -vE '^\s*#' "$ROOT/packages/base.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qx "xdg-user-dirs"; then
    fail "xdg-user-dirs should not be duplicated in packages/base.txt"
else
    pass "xdg-user-dirs not duplicated in packages/base.txt"
fi

if grep -vE '^\s*#' "$ROOT"/packages/base.txt | grep -qw chromium; then
    fail "chromium belongs in the browser module, not base.txt"
else
    pass "chromium is not in base.txt"
fi

section "Profiles"

check_profile() {
    local file="$1"

    # shellcheck source=/dev/null
    source "$file"

    local required=(
        PROFILE_NAME GPU DESKTOP DESKTOP_SHELL SHELL PROMPT
        OH_MY_ZSH BROWSER_CHROMIUM BROWSER_ULAA BROWSER_BRAVE_ORIGIN
        BROWSER_FIREFOX CURSOR KATE CHATGPT MEDIA_APPLICATIONS ANTIGRAVITY LOCALSEND
        BLUETOOTH GAMING FLATPAK NIX PODMAN
        NVIDIA ROCM ENABLE_GRAPHICAL_TARGET INSTALL_GREETER INSTALL_NOCTALIA
    )

    local var
    for var in "${required[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            fail "$file missing $var"
        else
            pass "$file has $var"
        fi
    done

    if [[ "$DESKTOP" != "hyprland" ]]; then
        fail "$file DESKTOP is not hyprland"
    else
        pass "$file DESKTOP=hyprland"
    fi

    if [[ "$DESKTOP_SHELL" != "noctalia" ]]; then
        fail "$file DESKTOP_SHELL is not noctalia"
    else
        pass "$file DESKTOP_SHELL=noctalia"
    fi

    if [[ "$BROWSER_ULAA" != "true" ]]; then
        fail "$file BROWSER_ULAA is not true"
    else
        pass "$file BROWSER_ULAA=true"
    fi

    if [[ "$CHATGPT" != "true" ]]; then
        fail "$file CHATGPT is not true"
    else
        pass "$file CHATGPT=true"
    fi
}

check_profile "$ROOT/profiles/vm.conf"
check_profile "$ROOT/profiles/workstation.conf"
