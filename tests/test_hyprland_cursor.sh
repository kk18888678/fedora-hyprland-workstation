#!/usr/bin/env bash

# Test Suite: Virtio-GPU session cursor compatibility.

section "Virtio-GPU session cursor"

cursor_config="$ROOT/dotfiles/hypr/hyprland.lua"
if [[ ! -f "$cursor_config" ]]; then
    fail "Hyprland configuration is missing"
else
    cursor_block="$({
        sed -n '/local function has_virtio_gpu_device()/,/^end$/p' "$cursor_config"
        sed -n '/if has_virtio_gpu_device()/,/^end$/p' "$cursor_config"
    })"

    if grep -q '/sys/bus/virtio/drivers/virtio_gpu' <<< "$cursor_block" &&
        grep -q 'no_hardware_cursors = 1' <<< "$cursor_block" &&
        grep -q 'confirmed virtio-gpu' <<< "$cursor_block"; then
        pass "session cursor workaround is scoped to confirmed virtio-gpu detection"
    else
        fail "session cursor workaround is missing or not narrowly scoped"
    fi

    setting_count="$(grep -c 'no_hardware_cursors = 1' "$cursor_config" || true)"
    guarded_count="$(grep -A8 -B8 'no_hardware_cursors = 1' "$cursor_config" |
        grep -c 'if has_virtio_gpu_device()' || true)"
    if [[ "$setting_count" == "1" && "$guarded_count" == "1" ]]; then
        pass "hardware cursors remain enabled by default outside the virtio-gpu guard"
    else
        fail "hardware-cursor workaround is not guarded by virtio-gpu detection"
    fi
fi
