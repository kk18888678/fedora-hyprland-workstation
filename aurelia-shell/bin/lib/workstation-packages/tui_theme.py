#!/usr/bin/env python3
"""Read Aurelia's semantic theme data for the package-manager TUI.

The terminal frontend deliberately reads the same data files as Theme.qml. It
does not import QML, source shell code, or maintain a second theme registry.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Optional, Tuple

RGB = Tuple[int, int, int]

_HEX = re.compile(r"^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$")
_RGB = re.compile(r"^rgba?\(([0-9.,% ]+)\)$")


def _safe_theme_path(value: str) -> Optional[Path]:
    if not value or not value.startswith("/") or value == "/":
        return None
    path = Path(value)
    if path.is_symlink() or not path.is_file():
        return None
    return path


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _parse_data_file(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    section = ""
    try:
        lines = path.read_text(encoding="utf-8", errors="strict").splitlines()
    except (OSError, UnicodeError):
        return values
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = _unquote(value)
        if not re.fullmatch(r"[A-Za-z0-9_.-]{1,96}", key):
            continue
        if len(value) > 256 or "\t" in value or "\r" in value or "\n" in value:
            continue
        values[f"{section}.{key}" if section else key] = value
    return values


def _parse_rgb(value: str, background: RGB) -> Optional[RGB]:
    value = value.strip()
    match = _HEX.fullmatch(value)
    if match:
        raw = match.group(1)
        rgb = tuple(int(raw[index : index + 2], 16) for index in (0, 2, 4))
        alpha = int(match.group(2), 16) / 255 if match.group(2) else 1.0
        return tuple(round(rgb[index] * alpha + background[index] * (1 - alpha)) for index in range(3))  # type: ignore[return-value]
    match = _RGB.fullmatch(value)
    if match:
        parts = [part.strip() for part in match.group(1).split(",")]
        if len(parts) not in (3, 4):
            return None
        try:
            channels = []
            for part in parts[:3]:
                if part.endswith("%"):
                    channels.append(round(float(part[:-1]) * 2.55))
                else:
                    channels.append(round(float(part)))
            if len(parts) == 4:
                alpha = float(parts[3][:-1]) / 100 if parts[3].endswith("%") else float(parts[3])
            else:
                alpha = 1.0
        except ValueError:
            return None
        if any(channel < 0 or channel > 255 for channel in channels) or not 0 <= alpha <= 1:
            return None
        return tuple(round(channels[index] * alpha + background[index] * (1 - alpha)) for index in range(3))  # type: ignore[return-value]
    return None


_NEUTRAL_FALLBACK: Dict[str, RGB] = {
    "background": (12, 18, 22),
    "surface": (20, 28, 34),
    "surfaceElevated": (32, 43, 52),
    "selection": (42, 48, 74),
    "border": (111, 139, 156),
    "borderActive": (121, 194, 224),
    "text": (226, 235, 241),
    "textSecondary": (164, 190, 207),
    "textMuted": (111, 139, 156),
    "accent": (121, 194, 224),
    "accentAlt": (174, 133, 255),
    "success": (52, 226, 157),
    "warning": (246, 193, 93),
    "error": (239, 112, 143),
    "dnf": (56, 189, 248),
    "flatpak": (52, 226, 157),
    "aurelia": (174, 133, 255),
}


@dataclass(frozen=True)
class ThemePalette:
    colors: Dict[str, RGB]
    source: str

    def color(self, name: str) -> RGB:
        return self.colors.get(name, self.colors["text"])

    @property
    def theme_name(self) -> str:
        if self.source == "terminal fallback":
            return self.source
        return Path(self.source).parent.name or Path(self.source).name


def resolve_theme_paths(backend_path: Path) -> Tuple[Path, ...]:
    home = Path(os.environ.get("HOME", ""))
    candidates = []
    override = _safe_theme_path(os.environ.get("AURELIA_THEME_CONF", ""))
    if override:
        candidates.append(override)
    if home.is_absolute() and str(home) != "/":
        candidates.append(home / ".config" / "aurelia" / "theme.conf")
        state_home = Path(os.environ.get("XDG_STATE_HOME", str(home / ".local" / "state")))
        if state_home.is_absolute() and str(state_home) != "/":
            candidates.append(state_home / "aurelia" / "current" / "theme.conf")
    try:
        aurelia_root = backend_path.resolve().parents[1]
        candidates.append(aurelia_root / "theme.conf")
    except (IndexError, OSError):
        pass
    return tuple(path for path in candidates if path.is_file() and not path.is_symlink())


def load_theme(backend_path: Path) -> ThemePalette:
    paths = resolve_theme_paths(backend_path)
    chosen = paths[0] if paths else None
    raw: Dict[str, str] = {}
    shell_raw: Dict[str, str] = {}
    shipped_theme: Optional[Path] = None
    try:
        shipped_theme = backend_path.resolve().parents[1] / "theme.conf"
    except (IndexError, OSError):
        pass
    if chosen:
        raw = _parse_data_file(chosen)
        shell_candidates = [chosen.parent / "shell.toml"]
        if shipped_theme is not None and chosen == shipped_theme:
            shell_candidates.append(chosen.parent / "theme" / "shell.toml")
        for shell_path in shell_candidates:
            if shell_path.is_file() and not shell_path.is_symlink():
                shell_raw = _parse_data_file(shell_path)
                break

    colors = dict(_NEUTRAL_FALLBACK)
    background = _parse_rgb(raw.get("background", ""), colors["background"])
    if background:
        colors["background"] = background

    aliases = {
        "surface": ("surface", "lighter_background"),
        "surfaceElevated": ("surfaceElevated", "selection", "selection_active"),
        "selection": ("selection", "selection_background"),
        "border": ("border", "border_inactive", "muted", "inactive_border"),
        "borderActive": ("borderActive", "active_border_color", "accent", "active_border"),
        "text": ("text", "foreground"),
        "textSecondary": ("textSecondary", "light_foreground"),
        "textMuted": ("textMuted", "muted", "dark_foreground", "color8"),
        "accent": ("accent", "color4"),
        "accentAlt": ("accentAlt", "magenta", "purple", "color13"),
        "success": ("success", "green"),
        "warning": ("warning", "yellow"),
        "error": ("error", "red"),
    }
    for semantic, keys in aliases.items():
        for key in keys:
            parsed = _parse_rgb(raw.get(key, ""), colors["background"])
            if parsed:
                colors[semantic] = parsed
                break

    shell_aliases = {
        "surface": "launcher.background",
        "text": "launcher.text",
        "borderActive": "launcher.border",
        "selection": "launcher.selected-background",
        "accent": "launcher.selected-text",
    }
    for semantic, key in shell_aliases.items():
        parsed = _parse_rgb(shell_raw.get(key, ""), colors["background"])
        if parsed:
            colors[semantic] = parsed

    colors["dnf"] = colors.get("accent", colors["dnf"])
    colors["flatpak"] = colors.get("success", colors["flatpak"])
    colors["aurelia"] = colors.get("accentAlt", colors["aurelia"])
    return ThemePalette(colors=colors, source=str(chosen) if chosen else "terminal fallback")


def xterm_palette() -> Tuple[RGB, ...]:
    base = (
        (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
        (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
        (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
        (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
    )
    cube = (0, 95, 135, 175, 215, 255)
    colors = list(base)
    for red in cube:
        for green in cube:
            for blue in cube:
                colors.append((red, green, blue))
    colors.extend((value, value, value) for value in range(8, 239, 10))
    return tuple(colors)


def nearest_xterm(rgb: RGB, color_count: int = 256) -> int:
    palette = xterm_palette()[: max(8, min(color_count, 256))]
    return min(range(len(palette)), key=lambda index: sum((palette[index][channel] - rgb[channel]) ** 2 for channel in range(3)))
