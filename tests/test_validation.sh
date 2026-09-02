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

