#!/usr/bin/env bash

# Test Suite: rootless Podman subordinate-ID allocation safety.

section "Rootless subordinate-ID allocation"

subid_allocation_output="$(
    bash -s -- "$ROOT" <<'EOS'
set -Eeuo pipefail
ROOT="$1"
source "$ROOT/modules/common.sh"
source "$ROOT/modules/status.sh"
source "$ROOT/modules/containers.sh"

TARGET_USER=target
uid_file="$(mktemp)"
gid_file="$(mktemp)"
trap 'rm -f -- "$uid_file" "$gid_file"' EXIT
export SUBUID_FILE="$uid_file" SUBGID_FILE="$gid_file"

printf 'alice:100000:65536\n' > "$uid_file"
: > "$gid_file"
sudo_calls=0
sudo() {
    local operation="${1:-}"
    local range="${3:-}"
    local user="${4:-}"
    local start end count
    sudo_calls=$((sudo_calls + 1))
    [[ "$operation" == usermod && "$user" == "$TARGET_USER" ]] || return 1
    if [[ "$2" == --add-subuids ]]; then
        IFS=- read -r start end <<< "$range"
        count=$((end - start + 1))
        printf '%s:%s:%s\n' "$user" "$start" "$count" >> "$SUBUID_FILE"
    elif [[ "$2" == --add-subgids ]]; then
        IFS=- read -r start end <<< "$range"
        count=$((end - start + 1))
        printf '%s:%s:%s\n' "$user" "$start" "$count" >> "$SUBGID_FILE"
    else
        return 1
    fi
}

ensure_rootless_subids
allocated_uid="$(awk -F: '$1=="target"{print $2 ":" $3}' "$uid_file")"
allocated_gid="$(awk -F: '$1=="target"{print $2 ":" $3}' "$gid_file")"
overlap_with_alice=0
[[ "$allocated_uid" == 100000:* ]] && overlap_with_alice=1
printf 'collision_avoided=%s same_range=%s\n' \
    "$([[ "$overlap_with_alice" -eq 0 ]] && echo 1 || echo 0)" \
    "$([[ "$allocated_uid" == "$allocated_gid" ]] && echo 1 || echo 0)"

printf 'target:300000:65536\n' > "$uid_file"
: > "$gid_file"
sudo_calls=0
ensure_rootless_subids
reused_gid="$(awk -F: '$1=="target"{print $2 ":" $3}' "$gid_file")"
printf 'existing_range_reused=%s\n' "$([[ "$reused_gid" == 300000:65536 ]] && echo 1 || echo 0)"

printf 'malformed line\n' > "$uid_file"
: > "$gid_file"
sudo_calls=0
malformed_status=0
ensure_rootless_subids || malformed_status=$?
printf 'malformed_rejected=%s no_mutation=%s\n' \
    "$([[ "$malformed_status" -ne 0 ]] && echo 1 || echo 0)" \
    "$([[ "$sudo_calls" -eq 0 ]] && echo 1 || echo 0)"
EOS
)"

if grep -q 'collision_avoided=1 same_range=1' <<< "$subid_allocation_output" &&
   grep -q 'existing_range_reused=1' <<< "$subid_allocation_output" &&
   grep -q 'malformed_rejected=1 no_mutation=1' <<< "$subid_allocation_output"; then
    pass "rootless subuid/subgid allocation avoids overlap, reuses safe ranges, and fails closed on malformed tables"
else
    fail "rootless subordinate-ID allocation safety failed: $subid_allocation_output"
fi
