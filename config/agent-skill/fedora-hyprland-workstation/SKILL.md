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
- `workstation-ai agents|default|set|reset|launch|skill` — AI coding agents.
- `aurelia bar|theme|...` — Aurelia shell controls (`aurelia` CLI).
- `workstation-aurelia preference get|set|unset` — shell preferences (clock
  format, calendar week start, motion, text size).

## Rules

- Never run the installer (`./install.sh`) unless the user explicitly asks for a
  full integration run.
- Prefer `set`/`reset` over editing managed files directly; backends validate
  values and fail closed.
- Run `./tests/run.sh` after repository changes; run the syntax check over every
  shell script.
- Do not disable GPG/checksum verification or add arbitrary third-party repos.
- Keep changes in the repository; the running shell reloads from it.
