#!/usr/bin/env python3
"""Safe configuration loading for the dedicated package-manager TUI."""

from __future__ import annotations

import curses
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, Optional, Tuple


DEFAULT_KEYS = {
    "up": "up",
    "down": "down",
    "page_up": "pgup",
    "page_down": "pgdn",
    "select": "tab",
    "accept": "enter",
    "cancel": "esc",
    "refresh": "ctrl-r",
    "help": "?",
    "preview_toggle": "alt-p",
    "preview_up": "alt-k",
    "preview_down": "alt-j",
    "select_all": "ctrl-a",
    "search": "/",
    "queue": "a",
    "source": "s",
    "info": "i",
    "quit": "q",
    "filter_next": "right",
    "filter_previous": "left",
}

DEFAULT_LABELS = {
    "title": "Package Manager",
    "header": "Catalog",
    "input": "Search",
    "list": "Packages",
    "preview": "Selected package · metadata",
    "footer": "Keys",
}


@dataclass(frozen=True)
class TuiConfig:
    keys: Dict[str, str] = field(default_factory=lambda: dict(DEFAULT_KEYS))
    labels: Dict[str, str] = field(default_factory=lambda: dict(DEFAULT_LABELS))
    prompt: str = "Search > "
    border: str = "rounded"
    margin: str = "1,2"
    padding: str = "0,1"

    def key(self, name: str) -> str:
        return self.keys.get(name, DEFAULT_KEYS.get(name, name))

    def label(self, name: str) -> str:
        return self.labels.get(name, DEFAULT_LABELS.get(name, name))


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _read_settings(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    if path.is_symlink() or not path.is_file():
        return values
    try:
        lines = path.read_text(encoding="utf-8", errors="strict").splitlines()
    except (OSError, UnicodeError):
        return values
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = _unquote(value)
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", key):
            continue
        if len(value) > 256 or any(char in value for char in "\r\n\t"):
            continue
        values[key] = value
    return values


def _valid_key(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9?+=/_.-]{1,32}", value))


def load_config(backend_path: Path) -> TuiConfig:
    settings: Dict[str, str] = {}
    try:
        repo_root = backend_path.resolve().parents[2]
    except (OSError, IndexError):
        repo_root = backend_path.parent
    config_paths = [repo_root / "config" / "package-manager.conf"]
    user_override = os.environ.get("WORKSTATION_PACKAGE_USER_CONFIG", "")
    if user_override.startswith("/"):
        config_paths.append(Path(user_override))
    else:
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
        if config_home.is_absolute() and str(config_home) != "/":
            config_paths.append(config_home / "workstation" / "package-manager.conf")
    for path in config_paths:
        settings.update(_read_settings(path))

    keys = dict(DEFAULT_KEYS)
    for name in keys:
        value = settings.get(f"key_{name}", keys[name])
        if _valid_key(value):
            keys[name] = value

    labels = dict(DEFAULT_LABELS)
    for setting_name, label_name in (
        ("tui_title", "title"),
        ("tui_header_label", "header"),
        ("tui_input_label", "input"),
        ("tui_list_label", "list"),
        ("tui_preview_label", "preview"),
        ("tui_footer_label", "footer"),
    ):
        value = settings.get(setting_name, labels[label_name])
        if value and len(value) <= 64 and not any(char in value for char in "\r\n\t"):
            labels[label_name] = value

    prompt = settings.get("tui_prompt", "Search > ")
    if not prompt or len(prompt) > 64 or any(char in prompt for char in "\r\n\t"):
        prompt = "Search > "
    border = settings.get("tui_border", "rounded")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", border):
        border = "rounded"
    margin = settings.get("tui_margin", "1,2")
    if not re.fullmatch(r"[0-9]+(,[0-9]+){0,3}", margin):
        margin = "1,2"
    padding = settings.get("tui_padding", "0,1")
    if not re.fullmatch(r"[0-9]+(,[0-9]+){0,3}", padding):
        padding = "0,1"
    return TuiConfig(keys=keys, labels=labels, prompt=prompt, border=border, margin=margin, padding=padding)


def key_code(value: str) -> Tuple[int, ...]:
    """Return the curses codes accepted for one configured key."""

    named = {
        "up": curses.KEY_UP,
        "down": curses.KEY_DOWN,
        "left": curses.KEY_LEFT,
        "right": curses.KEY_RIGHT,
        "pgup": curses.KEY_PPAGE,
        "pgdn": curses.KEY_NPAGE,
        "home": curses.KEY_HOME,
        "end": curses.KEY_END,
        "tab": 9,
        "enter": 10,
        "esc": 27,
        "space": 32,
        "backspace": curses.KEY_BACKSPACE,
        "ctrl-a": 1,
        "ctrl-b": 2,
        "ctrl-c": 3,
        "ctrl-d": 4,
        "ctrl-f": 6,
        "ctrl-r": 18,
        "ctrl-u": 21,
        "ctrl-w": 23,
    }
    if value in named:
        return (named[value],)
    if len(value) == 1:
        return (ord(value),)
    return ()


def key_pressed(ch: int, value: str) -> bool:
    if ch in key_code(value):
        return True
    # Terminal drivers encode Alt+letter as ESC followed by the letter. The
    # main loop handles the ESC prefix; this recognizes the second byte when
    # it is available as a normal character.
    if value.startswith("alt-") and len(value) == 5 and ch == ord(value[-1]):
        return True
    return False
