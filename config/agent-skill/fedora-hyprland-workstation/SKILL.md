---
name: fedora-hyprland-workstation
description: Operate and customize this Fedora Hyprland workstation — Hyprland settings, the Aurelia shell, app defaults, and the bounded backend commands.
---

# Fedora Hyprland Workstation

This machine is provisioned by the `fedora-hyprland-workstation` repository. Prefer
the bounded, reviewed backends over editing files by hand.

## Safe commands

- `workstation-hypr-settings schema|status|get|set|reset|clear` — Hyprland options.
  Writes a managed overlay (`~/.config/fedora-hyprland-workstation/hypr-settings.lua`)
  and applies live with `hyprctl`.
- `workstation-system-settings schema|status|get|set|check` — power profile,
  brightness, audio, Bluetooth, Wi-Fi, appearance (gsettings), time zone.
- `workstation-app-defaults status|choices|current|set|reset <role> [app]` —
  default terminal, file manager, browser, editor, email client.
- `workstation-ai agents|default|set|reset|launch|prompt|crash|skill` — AI coding
  agents (detect, choose a default, launch, diagnose a crash, install the
  workstation skills). This backend never installs agents.
- `aurelia crash diagnose|watch|mute|list|capture` — crash diagnosis and
  notification control. The coredump watcher offers a click-to-diagnose
  notification; `aurelia crash mute <program>` silences one program and
  `aurelia crash capture off` is the global switch.
- `aurelia bar|theme|...` — Aurelia shell controls (`aurelia` CLI).
- `workstation-aurelia preference get|set|unset` — shell preferences (clock
  format, calendar week start, motion, text size).

## Diagnosing a crash

1. `coredumpctl list` to find the PID (the watcher notification also carries it).
2. `aurelia crash diagnose <pid>` (or `workstation-ai crash <pid>`) hands the
   crash facts to the default agent with the evidence-first diagnosis task.
3. Follow the `diagnose-crash` skill: establish the facts from the dump before
   proposing a fix; only recommend an upstream report when the cause is in the
   program, not the local setup.
4. Offer to mute the program with `aurelia crash mute '<program>'`, and say how
   to undo it with `off`.

## Rules

- Never run the installer (`./install.sh`) unless the user explicitly asks for a
  full integration run.
- Prefer `set`/`reset` over editing managed files directly; backends validate
  values and fail closed.
- Run `./tests/run.sh` after repository changes; run the syntax check over every
  shell script.
- Do not disable GPG/checksum verification or add arbitrary third-party repos.
- Keep changes in the repository; the running shell reloads from it.
