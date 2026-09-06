#!/usr/bin/env bash

# Test Suite: Workstation Configuration Architecture (Corrective Hardening)
# Tests Component Registry, Desired State, Planner, Reconciler, Roles, Defaults,
# Lifecycle Adapters, Review, Wizard Navigation, Single Mutation Ownership, and CLI Contract.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=/dev/null
source "$ROOT/modules/common.sh"
source "$ROOT/modules/status.sh"
source "$ROOT/modules/browsers.sh"
source "$ROOT/modules/nix.sh"
source "$ROOT/modules/packages.sh"
