#!/usr/bin/env bash

# Test Suite: Workspaces discoverability, single-source-of-truth keybindings manifest, and zero-drift hotkeys validation.

# Isolate overrides from live workstation environment unless explicitly set
export HOTKEYS_OVERRIDES="${HOTKEYS_OVERRIDES:-/dev/null}"
