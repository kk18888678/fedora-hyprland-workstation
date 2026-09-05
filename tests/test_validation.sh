#!/usr/bin/env bash

# Test Suite: Validation module, login stack verification, and workstation capability checks.

section "Host-Global Media Utilities"

if [[ -d "$ROOT/environments/media-tools" ]]; then
    fail "environments/media-tools should be removed"
else
    pass "environments/media-tools is removed"
fi

media_expected_tools=(ffmpeg ffprobe mediainfo mkvmerge MP4Box ccextractor mp4dump packager dovi_tool N_m3u8DL-RE)
for mtool in "${media_expected_tools[@]}"; do
    if grep -qF "$mtool" "$ROOT/modules/validation.sh"; then
        pass "validation.sh checks media tool runtime command: $mtool"
    else
        fail "validation.sh missing runtime check for $mtool"
    fi
done

section "Hyprland GUI Utilities Capability & Manifest Validation"

if grep -qxF "hyprland-guiutils" "$ROOT/packages/desktop.txt"; then
    pass "packages/desktop.txt declares hyprland-guiutils under Hyprland ownership"
else
    fail "packages/desktop.txt missing hyprland-guiutils declaration"
fi

if grep -qF "hyprland-guiutils" "$ROOT/modules/validation.sh" && grep -qF "hyprland-dialog" "$ROOT/modules/validation.sh"; then
    pass "validation.sh checks hyprland-guiutils / hyprland-dialog capability"
else
    fail "validation.sh missing check for hyprland-guiutils or hyprland-dialog"
fi

