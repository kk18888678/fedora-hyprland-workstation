#!/usr/bin/env python3
"""A lightweight, responsive Package Manager terminal application.

The presentation layer is intentionally separate from the Bash package
backend. It owns navigation, filtering, rendering, and user intent only; the
backend owns catalog preparation, privilege, transactions, and manifest state.
"""

from __future__ import annotations

import argparse
import curses
import curses.ascii
from datetime import datetime
import locale
import os
import queue
import re
import shlex
import shutil
import subprocess
import sys
import threading
import textwrap
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Set, Tuple

from tui_backend import (
    BackendError,
    CatalogStatus,
    PackageBackend,
    PackageRow,
    installed_keys_from_status,
    update_ids_from_status,
)
from tui_config import TuiConfig, key_pressed, load_config
from tui_theme import ThemePalette, load_theme, nearest_xterm


@dataclass
class Event:
    kind: str
    generation: int
    value: Any = None
    error: Optional[BaseException] = None


def _truncate(value: str, width: int, marker: str = "…") -> str:
    if width <= 0:
        return ""
    value = str(value).replace("\n", " ").replace("\r", " ").replace("\t", " ")
    if len(value) <= width:
        return value
    if width == 1:
        return marker[:1]
    return value[: width - len(marker)] + marker


def _wrap(value: str, width: int) -> List[str]:
    if width <= 1:
        return [_truncate(value, max(1, width))]
    value = " ".join(str(value).split())
    return textwrap.wrap(value, width=width, break_long_words=True, break_on_hyphens=False) or [""]


def _selection_window(selected: int, total: int, visible: int, top: int = 0) -> int:
    """Return a scroll offset based on the actual rendered row capacity."""

    if total <= 0 or visible <= 0:
        return 0
    selected = max(0, min(selected, total - 1))
    top = max(0, top)
    if selected < top:
        top = selected
    elif selected >= top + visible:
        top = selected - visible + 1
    return max(0, min(top, max(0, total - visible)))


def _size_value(value: str) -> Tuple[int, int]:
    match = re.match(r"^\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?i?B)\b", value or "", re.IGNORECASE)
    if not match:
        return 0, 0
    try:
        number = float(match.group(1))
    except ValueError:
        return 0, 0
    unit = match.group(2).lower()
    multiplier = {"b": 1, "kb": 1000, "kib": 1024, "mb": 1000**2, "mib": 1024**2, "gb": 1000**3, "gib": 1024**3, "tb": 1000**4, "tib": 1024**4}.get(unit, 1)
    return 1, int(number * multiplier)


def _date_value(value: str) -> Tuple[int, str]:
    return (1, value) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value or "") else (0, "")


def _version_value(value: str) -> Tuple[Tuple[int, object], ...]:
    """Provide a deterministic natural-order fallback for version lists."""

    tokens = re.findall(r"[0-9]+|[A-Za-z]+", (value or "").lower())
    result: List[Tuple[int, object]] = []
    for token in tokens:
        if token.isdigit():
            result.append((0, int(token)))
        else:
            result.append((1, token))
    return tuple(result)


def _relative_luminance(rgb: Tuple[int, int, int]) -> float:
    channels = []
    for channel in rgb:
        value = channel / 255
        channels.append(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4)
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def _contrast_ratio(first: Tuple[int, int, int], second: Tuple[int, int, int]) -> float:
    lighter = max(_relative_luminance(first), _relative_luminance(second))
    darker = min(_relative_luminance(first), _relative_luminance(second))
    return (lighter + 0.05) / (darker + 0.05)


def _readable_color(foreground: Tuple[int, int, int], background: Tuple[int, int, int], fallback: Tuple[int, int, int]) -> Tuple[int, int, int]:
    candidates = [
        foreground,
        fallback,
        tuple(round(channel * 0.55) for channel in foreground),
        tuple(round(channel + (255 - channel) * 0.45) for channel in foreground),
    ]
    return max(candidates, key=lambda candidate: _contrast_ratio(candidate, background))


def _display_key(value: str) -> str:
    return {
        "up": "↑",
        "down": "↓",
        "left": "←",
        "right": "→",
        "pgup": "PgUp",
        "pgdn": "PgDn",
        "enter": "Enter",
        "esc": "Esc",
        "tab": "Tab",
        "ctrl-r": "Ctrl-R",
        "ctrl-a": "Ctrl-A",
        "alt-p": "Alt-P",
        "alt-k": "Alt-K",
        "alt-j": "Alt-J",
    }.get(value, value)


def _pack_footer_lines(tokens: Sequence[str], width: int) -> List[str]:
    """Pack complete shortcut tokens into as many readable footer lines as needed."""

    available = max(1, width)
    lines: List[str] = []
    current = ""
    for token in tokens:
        candidate = token if not current else f"{current}  ·  {token}"
        if current and len(candidate) > available:
            lines.append(current)
            current = token
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines or [""]


def _diagnostic_log_path() -> Optional[Path]:
    """Resolve the user-owned TUI diagnostic log without following links."""

    home = Path(os.environ.get("HOME", str(Path.home())))
    configured_state = os.environ.get("XDG_STATE_HOME", "")
    state_home = Path(configured_state) if configured_state else home / ".local" / "state"
    if not state_home.is_absolute() or str(state_home) == "/":
        return None
    return state_home / "fedora-hyprland-workstation" / "package-manager" / "tui.log"


def _redact_log_urls(value: str) -> str:
    """Remove URL credentials, queries, and fragments from persisted logs."""

    def redact(match: re.Match[str]) -> str:
        raw = match.group(0)
        try:
            from urllib.parse import urlsplit, urlunsplit

            parsed = urlsplit(raw)
            hostname = parsed.hostname or ""
            if not hostname:
                return raw
            netloc = hostname
            if parsed.port:
                netloc = f"{netloc}:{parsed.port}"
            return urlunsplit((parsed.scheme, netloc, parsed.path, "", ""))
        except (ValueError, UnicodeError):
            return "<url>"

    return re.sub(r"https?://[^\s]+", redact, value)


class PackageManagerTui:
    MIN_WIDTH = 72
    MIN_HEIGHT = 18
    MAX_QUEUE = 500

    def __init__(self, backend_path: Path, initial_query: str = "") -> None:
        self.diagnostics: List[str] = []
        self.diagnostic_log_path = _diagnostic_log_path()
        self._diagnostic_log_lock = threading.Lock()
        self._append_diagnostic_log("INFO: Package Manager TUI session started")
        self.backend = PackageBackend(backend_path, self._record_backend_diagnostic)
        self.config: TuiConfig = load_config(self.backend.backend_path)
        self.theme: ThemePalette = load_theme(self.backend.backend_path)
        self.initial_query = initial_query

        self.events: "queue.Queue[Event]" = queue.Queue()
        self.executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="package-tui")
        self.screen: Optional[Any] = None
        self.running = True
        self.query = initial_query
        self.query_cursor = len(initial_query)
        self.query_focus = False
        self.query_changed_at = time.monotonic() if initial_query else 0.0
        self.catalog_generation = 0
        self.info_generation = 0
        self.version_generation = 0
        self.status_generation = 0
        self.installed_generation = 0
        self.catalog_status_generation = 0
        self.update_generation = 0
        self.operation_generation = 0
        self.ownership_generation = 0

        self.rows: List[PackageRow] = []
        self.filtered_rows: List[PackageRow] = []
        self.version_groups: Dict[Tuple[str, str, str], List[PackageRow]] = {}
        self.all_version_groups: Dict[Tuple[str, str, str], List[PackageRow]] = {}
        self.all_group_rows: List[PackageRow] = []
        self.grouped_row_count = -1
        self.selected_index = 0
        self.top_index = 0
        self.visible_list_rows = 0
        self.filters: List[str] = ["All", "Installed", "Updates"]
        self.active_filter = "All"
        self.sort_mode = "relevance"
        self.sort_reverse = False
        self.focus_area = "list"
        self.action_index = 0
        self.installed_keys: Set[Tuple[str, str, str, str]] = set()
        self.installed_identity_keys: Set[Tuple[str, str, str]] = set()
        self.installed_versions: Dict[Tuple[str, str, str], Set[str]] = {}
        self.status_installed_keys: Set[Tuple[str, str, str, str]] = set()
        self.discovered_installed_keys: Set[Tuple[str, str, str, str]] = set()
        self.update_dnf_ids: Set[str] = set()
        self.update_flatpak_ids: Set[str] = set()

        self.catalog_status = CatalogStatus()
        self.catalog_loading = True
        self.query_loading = False
        self.status_loading = False
        self.installed_loading = False
        self.updates_loading = False
        self.info_loading = False
        self.versions_loading = False
        self.operation_loading = False
        self.show_details = True
        self.detail_scroll = 0
        self.queue_rows: List[PackageRow] = []
        self.info_text = ""
        self.info_fields: Dict[str, str] = {}
        self.pending_source_row: Optional[PackageRow] = None
        self.project_owned_keys: Set[Tuple[str, str, str, str]] = set()
        self.ownership_checked_keys: Set[Tuple[str, str, str, str]] = set()
        self.ownership_row: Optional[PackageRow] = None
        self.ownership_loading = False
        self.ownership_error = ""
        self.install_targets: List[PackageRow] = []
        self.install_version_override: Optional[str] = None
        self.remove_target: Optional[PackageRow] = None
        self.messages: List[str] = []
        self.transient_message = ""
        self.transient_until = 0.0
        self.modal: Optional[Dict[str, Any]] = None
        self.alt_prefix = False

        self._submit("bootstrap", self.backend.bootstrap, 1)

    def _record_backend_diagnostic(self, text: str) -> None:
        for line in text.splitlines():
            if line.strip():
                self.diagnostics.append(line.strip())
                self._append_diagnostic_log(line.strip())
        if hasattr(self, "transient_until") and self.diagnostics:
            self._set_message(f"Diagnostic: {_truncate(self.diagnostics[-1], 100)}", 6.0)

    def _append_diagnostic_log(self, text: str) -> None:
        path = getattr(self, "diagnostic_log_path", None)
        lock = getattr(self, "_diagnostic_log_lock", None)
        if not isinstance(path, Path) or lock is None:
            return
        lines = [line.strip() for line in str(text).splitlines() if line.strip()]
        if not lines:
            return
        try:
            with lock:
                parent = path.parent
                current = Path(path.anchor)
                for component in parent.parts[1:]:
                    current /= component
                    if current.is_symlink():
                        return
                parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                parent_stat = parent.stat()
                if parent_stat.st_uid != os.geteuid() or parent_stat.st_mode & 0o022:
                    return
                if path.is_symlink() or (path.exists() and not path.is_file()):
                    return
                if path.exists():
                    log_stat = path.stat()
                    if log_stat.st_uid != os.geteuid() or log_stat.st_mode & 0o077:
                        return
                flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND
                flags |= getattr(os, "O_NOFOLLOW", 0)
                descriptor = os.open(path, flags, 0o600)
                with os.fdopen(descriptor, "a", encoding="utf-8") as stream:
                    timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
                    for line in lines:
                        stream.write(f"{timestamp} {_redact_log_urls(line)}\n")
        except (OSError, ValueError, UnicodeError):
            # Diagnostics must never make the package manager unusable. The
            # in-memory diagnostics and provider output remain authoritative
            # when a safe persistent state path is unavailable.
            return

    def _log_event(self, message: str) -> None:
        self._append_diagnostic_log(message)

    def _submit(self, kind: str, function: Callable[[], Any], generation: int) -> None:
        def worker() -> None:
            try:
                value = function()
                self.events.put(Event(kind, generation, value=value))
            except BaseException as error:  # surfaced in the UI and stderr
                self.events.put(Event(kind, generation, error=error))

        self.executor.submit(worker)

    def _set_message(self, message: str, seconds: float = 4.0) -> None:
        self.transient_message = message
        self.transient_until = time.monotonic() + seconds

    def _record_error(self, error: BaseException, *, show_modal: bool = False, title: str = "Package Manager error") -> None:
        detail = str(error).strip() or error.__class__.__name__
        self.diagnostics.extend(f"ERROR: {line.strip()}" for line in detail.splitlines() if line.strip())
        self._append_diagnostic_log(f"ERROR: {detail}")
        self.messages.append(detail)
        self.messages = self.messages[-8:]
        if show_modal:
            self.modal = {
                "kind": "message",
                "title": title,
                "lines": detail.splitlines() or [detail],
            }
            self._set_message("Operation failed; full diagnostics are open", 8.0)
        else:
            self._set_message(f"Error: {_truncate(detail.splitlines()[0], 100)}", 8.0)

    def _start_catalog_load(self) -> None:
        self.catalog_generation += 1
        generation = self.catalog_generation
        self.catalog_loading = True
        self.query_loading = bool(self.query)
        query = self.query
        self._submit("catalog", lambda: self.backend.catalog_rows(query), generation)

    def _start_status_load(self) -> None:
        self.status_generation += 1
        self.status_loading = True
        self._submit("status", self.backend.status_json, self.status_generation)

    def _start_installed_load(self) -> None:
        self.installed_generation += 1
        self.installed_loading = True
        self._submit("installed", self.backend.installed_snapshot, self.installed_generation)

    def _start_catalog_status_load(self) -> None:
        self.catalog_status_generation += 1
        self._submit("catalog-status", self.backend.catalog_status, self.catalog_status_generation)

    def _start_updates_load(self) -> None:
        if self.updates_loading:
            return
        self.update_generation += 1
        self.updates_loading = True
        self._submit("updates", self.backend.updates_json, self.update_generation)

    def _start_info_load(self, row: Optional[PackageRow] = None) -> None:
        row = row or self.selected_row
        if not row:
            return
        self.info_generation += 1
        generation = self.info_generation
        self.info_loading = True
        self.info_text = ""
        self.info_fields = {}
        self._submit("info", lambda: self.backend.package_info(row), generation)

    def _start_ownership_load(self, row: PackageRow) -> None:
        if row.key in self.ownership_checked_keys:
            self.ownership_row = row
            self.ownership_loading = False
            self.ownership_error = ""
            return
        self.ownership_generation += 1
        generation = self.ownership_generation
        self.ownership_row = row
        self.ownership_loading = True
        self.ownership_error = ""
        self._submit("ownership", lambda: self.backend.project_owned(row), generation)

    def _start_versions_load(self, row: PackageRow) -> None:
        self.version_generation += 1
        generation = self.version_generation
        self.versions_loading = True
        self._submit("versions", lambda: self.backend.versions_for(row), generation)

    @property
    def selected_row(self) -> Optional[PackageRow]:
        if not self.filtered_rows:
            return None
        self.selected_index = max(0, min(self.selected_index, len(self.filtered_rows) - 1))
        return self.filtered_rows[self.selected_index]

    def _provider_filters(self) -> List[str]:
        labels = {row.provider_label for row in self.rows}
        order = {"DNF": 0, "Flatpak": 1, "Aurelia": 2}
        return sorted(labels, key=lambda value: (order.get(value, 99), value.lower()))

    def _rebuild_filters(self) -> None:
        provider_filters = self._provider_filters()
        self.filters = ["All", "Installed", "Updates"] + provider_filters
        if self.active_filter not in self.filters:
            self.active_filter = "All"

    def _is_installed(self, row: PackageRow) -> bool:
        if row.key in self.installed_keys:
            return True
        if row.provider == "aurelia":
            return False
        return (row.provider, row.identifier, row.scope) in self.installed_identity_keys

    def _rebuild_installed_identity_index(self) -> None:
        self.installed_identity_keys = {(key[0], key[2], key[3]) for key in self.installed_keys}

    def _is_update(self, row: PackageRow) -> bool:
        if row.provider not in {"dnf", "flatpak"}:
            return False
        installed_versions = self.installed_versions.get(self._group_key(row), set())
        if not installed_versions:
            return False
        # Provider update status can be stale or unqualified.  The catalog
        # candidate must still be strictly newer; otherwise it can label an
        # identical installed/candidate EVR as an update.
        return any(_version_value(row.version) > _version_value(version) for version in installed_versions if version != "unknown")

    @staticmethod
    def _group_key(row: PackageRow) -> Tuple[str, str, str]:
        return row.provider, row.identifier, row.scope

    @staticmethod
    def _latest_row(rows: Sequence[PackageRow]) -> PackageRow:
        return max(rows, key=lambda row: (_date_value(row.release_date), _version_value(row.version), row.source.lower()))

    def _group_rows(self, rows: Iterable[PackageRow]) -> List[PackageRow]:
        groups: Dict[Tuple[str, str, str], List[PackageRow]] = {}
        for row in rows:
            groups.setdefault(self._group_key(row), []).append(row)
        self.version_groups = groups
        return [self._latest_row(group) for group in groups.values()]

    def _rebuild_catalog_groups(self) -> None:
        groups: Dict[Tuple[str, str, str], List[PackageRow]] = {}
        for row in self.rows:
            groups.setdefault(self._group_key(row), []).append(row)
        self.all_version_groups = groups
        self.all_group_rows = [self._latest_row(group) for group in groups.values()]
        self.grouped_row_count = len(self.rows)

    def _versions_for(self, row: PackageRow) -> List[PackageRow]:
        return list(self.version_groups.get(self._group_key(row), [row]))

    def _display_name(self, row: PackageRow) -> str:
        if self.active_filter == "Updates":
            return row.name
        count = len(self._versions_for(row))
        return f"{row.name} ({count})" if count > 1 else row.name

    def _apply_filter(self) -> None:
        if self.grouped_row_count != len(self.rows):
            self._rebuild_catalog_groups()
        active = self.active_filter
        if active == "All":
            rows = self.all_group_rows
        elif active == "Installed":
            rows = [row for row in self.all_group_rows if self._is_installed(row)]
        elif active == "Updates":
            rows = [row for row in self.all_group_rows if self._is_installed(row) and self._is_update(row)]
        else:
            rows = [row for row in self.all_group_rows if row.provider_label == active]
        self.version_groups = {
            self._group_key(row): self.all_version_groups[self._group_key(row)]
            for row in rows
            if self._group_key(row) in self.all_version_groups
        }
        self.filtered_rows = self._sort_rows(rows)
        self.selected_index = max(0, min(self.selected_index, max(0, len(self.filtered_rows) - 1)))
        self._keep_selection_visible(max(1, self.visible_list_rows))

    def _sort_rows(self, rows: Iterable[PackageRow]) -> List[PackageRow]:
        result = list(rows)
        mode = self.sort_mode
        if mode == "relevance":
            if self.sort_reverse:
                result.reverse()
            return result
        if mode == "name":
            key = lambda row: (row.name.lower(), row.provider_label.lower(), row.identifier.lower())
            default_descending = False
        elif mode == "size":
            key = lambda row: (_size_value(row.installed_size if row.installed_size != "n/a" else row.download_size), row.name.lower())
            default_descending = True
        elif mode == "date":
            key = lambda row: (_date_value(row.release_date), row.name.lower())
            default_descending = True
        else:
            key = lambda row: (row.provider_label.lower(), row.name.lower(), row.version.lower())
            default_descending = False
        return sorted(result, key=key, reverse=default_descending ^ self.sort_reverse)

    def _cycle_sort(self) -> None:
        modes = ("relevance", "name", "size", "date", "provider")
        self._set_sort_mode(modes[(modes.index(self.sort_mode) + 1) % len(modes)])

    def _set_sort_mode(self, mode: str) -> None:
        modes = ("relevance", "name", "size", "date", "provider")
        if mode not in modes:
            return
        selected_key = self._group_key(self.selected_row) if self.selected_row else None
        self.sort_mode = mode
        self._apply_filter()
        if selected_key:
            for index, row in enumerate(self.filtered_rows):
                if self._group_key(row) == selected_key:
                    self.selected_index = index
                    break
        self._keep_selection_visible(max(1, self.visible_list_rows))
        self._set_message(f"Sort: {self.sort_mode}")

    def _show_sort(self) -> None:
        modes = ("relevance", "name", "size", "date", "provider")
        self.modal = {"kind": "sort", "selected": modes.index(self.sort_mode), "options": modes}

    def _toggle_sort_direction(self) -> None:
        self.sort_reverse = not self.sort_reverse
        self._apply_filter()
        self._set_message(f"Sort direction: {'reverse' if self.sort_reverse else 'default'}")

    def _handle_event(self, event: Event) -> None:
        if event.kind == "bootstrap":
            self.catalog_loading = False
            if event.error:
                self._record_error(event.error)
            self._start_catalog_load()
            self._start_catalog_status_load()
            self._start_status_load()
            self._start_installed_load()
            return
        if event.kind == "catalog":
            if event.generation != self.catalog_generation:
                return
            self.catalog_loading = False
            self.query_loading = False
            if event.error:
                self._record_error(event.error)
                return
            self.rows = list(event.value or [])
            self._rebuild_catalog_groups()
            self._rebuild_filters()
            self._apply_filter()
            self.detail_scroll = 0
            if self.selected_row:
                self._start_info_load(self.selected_row)
            return
        if event.kind == "status":
            if event.generation != self.status_generation:
                return
            self.status_loading = False
            if event.error:
                self._record_error(event.error)
                return
            self.status_installed_keys = installed_keys_from_status(event.value or {})
            self.installed_keys = self.status_installed_keys | self.discovered_installed_keys
            self._rebuild_installed_identity_index()
            self._apply_filter()
            return
        if event.kind == "installed":
            if event.generation != self.installed_generation:
                return
            self.installed_loading = False
            if event.error:
                self._record_error(event.error)
                self._apply_filter()
                return
            if isinstance(event.value, tuple) and len(event.value) == 2:
                self.discovered_installed_keys = set(event.value[0] or set())
                self.installed_versions = dict(event.value[1] or {})
            else:
                self.discovered_installed_keys = set(event.value or set())
                self.installed_versions = {}
            self.installed_keys = self.status_installed_keys | self.discovered_installed_keys
            self._rebuild_installed_identity_index()
            self._apply_filter()
            return
        if event.kind == "catalog-status":
            if event.generation != self.catalog_status_generation:
                return
            if event.error:
                self._record_error(event.error)
                return
            self.catalog_status = event.value
            return
        if event.kind == "updates":
            if event.generation != self.update_generation:
                return
            self.updates_loading = False
            if event.error:
                self._record_error(event.error)
                self._apply_filter()
                return
            self.update_dnf_ids, self.update_flatpak_ids = update_ids_from_status(event.value or {})
            self._apply_filter()
            return
        if event.kind == "info":
            if event.generation != self.info_generation:
                return
            self.info_loading = False
            if event.error:
                self.pending_source_row = None
                self._record_error(event.error)
                return
            self.info_text, self.info_fields = event.value
            pending = self.pending_source_row
            self.pending_source_row = None
            if pending is not None and pending == self.selected_row:
                self._open_source()
            return
        if event.kind == "ownership":
            if event.generation != self.ownership_generation:
                return
            self.ownership_loading = False
            row = self.ownership_row
            if event.error:
                self.ownership_error = str(event.error)
                self._record_error(event.error)
                return
            if row is None or not isinstance(event.value, bool):
                self.ownership_error = "The backend returned an invalid package ownership state."
                self._record_error(RuntimeError(self.ownership_error))
                return
            self.ownership_checked_keys.add(row.key)
            if event.value:
                self.project_owned_keys.add(row.key)
            else:
                self.project_owned_keys.discard(row.key)
            self.ownership_error = ""
            return
        if event.kind == "versions":
            if event.generation != self.version_generation:
                return
            self.versions_loading = False
            if event.error:
                self._record_error(event.error, show_modal=True, title="Could not load package versions")
                if self.modal and self.modal.get("kind") == "versions":
                    self.modal["error"] = str(event.error)
                return
            rows = list(event.value or [])
            if self.modal and isinstance(self.modal.get("row"), PackageRow):
                row = self.modal["row"]
            elif rows:
                row = rows[0]
            else:
                row = None
            if row and rows:
                group_key = self._group_key(row)
                self.all_version_groups[group_key] = rows
                representative = self._latest_row(rows)
                self.all_group_rows = [
                    representative if self._group_key(candidate) == group_key else candidate
                    for candidate in self.all_group_rows
                ]
                if not any(self._group_key(candidate) == group_key for candidate in self.all_group_rows):
                    self.all_group_rows.append(representative)
                self.version_groups[group_key] = rows
            if self.modal and self.modal.get("kind") == "versions":
                self.modal["selected"] = 0
                self.modal["scroll"] = 0
            return
        if event.kind == "refresh":
            self.operation_loading = False
            if event.error:
                self._record_error(event.error, show_modal=True, title="Catalog refresh failed")
                self._start_catalog_load()
                self._start_catalog_status_load()
                self._start_status_load()
                self._start_installed_load()
                return
            self._set_message("Catalog refreshed", 5.0)
            self._start_catalog_load()
            self._start_catalog_status_load()
            self._start_status_load()
            self._start_installed_load()
            return
        if event.kind == "install":
            self.operation_loading = False
            if event.error:
                self._record_error(event.error, show_modal=True, title="Package operation failed")
                return
            count = len(self.install_targets)
            self.queue_rows = [row for row in self.queue_rows if row not in self.install_targets]
            self._set_message(f"Installed {count} package{'s' if count != 1 else ''}", 8.0)
            self._start_status_load()
            self._start_installed_load()
            return
        if event.kind == "source-add":
            self.operation_loading = False
            if event.error:
                self._record_error(event.error, show_modal=True, title="Could not add package source")
                return
            self._set_message("Aurelia source added; refreshing catalog…", 30.0)
            self._begin_refresh()
            return
        if event.kind == "uninstall":
            self.operation_loading = False
            if event.error:
                self.remove_target = None
                self._record_error(event.error, show_modal=True, title="Package removal failed")
                return
            row = self.remove_target
            if row:
                self.installed_keys = {
                    key
                    for key in self.installed_keys
                    if not (key[0] == row.provider and key[2] == row.identifier and key[3] == row.scope)
                }
                self.status_installed_keys = {
                    key
                    for key in self.status_installed_keys
                    if not (key[0] == row.provider and key[2] == row.identifier and key[3] == row.scope)
                }
                self.discovered_installed_keys = {
                    key
                    for key in self.discovered_installed_keys
                    if not (key[0] == row.provider and key[2] == row.identifier and key[3] == row.scope)
                }
                self.installed_versions.pop(self._group_key(row), None)
                self._rebuild_installed_identity_index()
            self.remove_target = None
            self._apply_filter()
            self._set_message("Package uninstalled; personal data was preserved", 8.0)
            self._start_status_load()
            self._start_installed_load()
            if self.selected_row:
                self._start_info_load(self.selected_row)
            return

    def _drain_events(self) -> None:
        while True:
            try:
                event = self.events.get_nowait()
            except queue.Empty:
                break
            self._handle_event(event)

    def _keep_selection_visible(self, visible_rows: int) -> None:
        if self.selected_index < self.top_index:
            self.top_index = self.selected_index
        elif self.selected_index >= self.top_index + visible_rows:
            self.top_index = self.selected_index - visible_rows + 1
        max_top = max(0, len(self.filtered_rows) - visible_rows)
        self.top_index = max(0, min(self.top_index, max_top))

    def _move_selection(self, delta: int, visible_rows: Optional[int] = None) -> None:
        if not self.filtered_rows:
            return
        visible_rows = visible_rows or max(1, self.visible_list_rows)
        self.selected_index = max(0, min(len(self.filtered_rows) - 1, self.selected_index + delta))
        self.detail_scroll = 0
        self.pending_source_row = None
        self._keep_selection_visible(visible_rows)
        self._start_info_load(self.selected_row)

    def _set_filter(self, index: int) -> None:
        if not self.filters:
            return
        self.active_filter = self.filters[index % len(self.filters)]
        self.selected_index = 0
        self.top_index = 0
        self.detail_scroll = 0
        self.pending_source_row = None
        self._apply_filter()
        if self.active_filter == "Updates":
            self._start_updates_load()
        if self.selected_row:
            self._start_info_load(self.selected_row)

    def _cycle_filter(self, delta: int) -> None:
        try:
            index = self.filters.index(self.active_filter)
        except ValueError:
            index = 0
        self._set_filter(index + delta)

    def _can_add_source(self) -> bool:
        """Return whether the global source-add action is relevant here.

        The current source-add workflow is deliberately limited to verified
        Aurelia GitHub sources.  It must not look like a generic DNF/Flatpak
        repository writer, so keep the action visible only where that intent
        is understandable.
        """

        return self.active_filter in {"All", "Aurelia"}

    def _toggle_queue(self, row: Optional[PackageRow] = None) -> None:
        row = row or self.selected_row
        if not row:
            return
        if row in self.queue_rows:
            self.queue_rows.remove(row)
            self._set_message(f"Removed {row.identifier} from queue")
            return
        if len(self.queue_rows) >= self.MAX_QUEUE:
            self._set_message(f"Queue limit is {self.MAX_QUEUE} packages", 6.0)
            return
        self.queue_rows.append(row)
        self._set_message(f"Queued {row.identifier}")

    def _action_items(self, row: Optional[PackageRow] = None) -> List[Tuple[str, str]]:
        row = row or self.selected_row
        if not row:
            return []
        if getattr(self, "installed_loading", False):
            return [("state-loading", "Checking installed state…")]
        if self.focus_area == "actions" and self.ownership_row == row:
            if self.ownership_loading:
                return [("state-loading", "Checking package ownership…")]
            if self.ownership_error:
                return [("state-error", "Ownership check failed; return and retry")]
        installed = self._is_installed(row)
        update_available = installed and self._is_update(row)
        project_owned = row.key in self.project_owned_keys
        first_action = "update" if update_available else ("reinstall" if installed else "install")
        first_label = "Update" if update_available else ("Reinstall" if installed else "Install")
        items = [(first_action, first_label)]
        if installed and not project_owned:
            items.append(("uninstall", "Uninstall"))
        if self.active_filter != "Updates":
            version_count = len(self._versions_for(row))
            items.append(("versions", f"View versions ({version_count})" if version_count > 1 else "View versions"))
        items.extend(
            [
                ("queue", "Remove from queue" if row in self.queue_rows else "Add to queue"),
                ("source", "View source"),
                ("info", "More information"),
            ]
        )
        return items

    def _run_action(self) -> None:
        actions = self._action_items()
        if not actions:
            return
        self.action_index = max(0, min(self.action_index, len(actions) - 1))
        action = actions[self.action_index][0]
        if action == "state-loading":
            self._set_message("Package state is still loading", 5.0)
        elif action == "state-error":
            self._set_message("Package ownership could not be checked; return and retry", 6.0)
        elif action in {"install", "reinstall", "update"}:
            self._show_install()
        elif action == "uninstall":
            self._show_uninstall()
        elif action == "versions":
            self._show_versions()
        elif action == "queue":
            self._toggle_queue()
        elif action == "source":
            self._open_source()
        elif action == "info":
            self._show_info()

    @staticmethod
    def _requires_privilege(rows: Sequence[PackageRow]) -> bool:
        return any(row.provider == "dnf" or row.provider == "flatpak" and row.scope == "system" for row in rows)

    def _authorize_for_mutation(self) -> bool:
        """Let sudo prompt on the real terminal without allowing curses to exit."""

        screen = getattr(self, "screen", None)
        suspended = False
        try:
            if screen is not None:
                try:
                    curses.def_prog_mode()
                    curses.endwin()
                    suspended = True
                except curses.error as error:
                    self._record_error(error)
            self.backend.authorize()
            return True
        except BackendError as error:
            self._record_error(error)
            return False
        except (OSError, ValueError, RuntimeError) as error:
            self._record_error(error)
            return False
        except Exception as error:
            self._record_error(error)
            return False
        finally:
            if screen is not None and suspended:
                try:
                    curses.reset_prog_mode()
                except curses.error as error:
                    self._record_error(error)
                for operation in (
                    lambda: screen.keypad(True),
                    lambda: screen.timeout(100),
                    lambda: screen.clear(),
                ):
                    try:
                        operation()
                    except Exception as error:
                        self._record_error(error)

    def _cycle_focus(self) -> None:
        if self.focus_area == "list":
            self.focus_area = "filters"
            self._set_message("Filter tabs focused · ←/→ change · Tab next · Enter packages")
        elif self.focus_area == "filters":
            self._cycle_filter(1)
        else:
            self.focus_area = "list"
            self._set_message("Package list focused")

    def _focus_actions(self) -> None:
        if not self.selected_row:
            self._set_message("No package is selected")
            return
        self.focus_area = "actions"
        self.action_index = 0
        self._start_ownership_load(self.selected_row)
        self._set_message("Actions focused · ↑/↓ choose · Enter run · Tab/Esc packages")

    def _select_all(self) -> None:
        if len(self.filtered_rows) > self.MAX_QUEUE:
            self._set_message(f"Select-all limited to {self.MAX_QUEUE} visible results", 6.0)
        self.queue_rows = list(self.filtered_rows[: self.MAX_QUEUE])
        self._set_message(f"Queued {len(self.queue_rows)} packages")

    def _show_help(self) -> None:
        self.modal = {"kind": "help", "scroll": 0}

    def _show_install(self, row_override: Optional[PackageRow] = None, exact_version: bool = False) -> None:
        row = row_override or self.selected_row
        targets = [row_override] if row_override else (list(self.queue_rows) if self.queue_rows else ([row] if row else []))
        if not targets:
            self._set_message("No package is selected")
            return
        self.install_targets = targets
        self.install_version_override = row_override.version if row_override and exact_version else None
        is_update = len(targets) == 1 and self._is_installed(targets[0]) and self._is_update(targets[0])
        if row_override and exact_version:
            current = self.selected_row
            verb = "Downgrade" if current and self._is_installed(current) and current.version != row_override.version else "Install selected version"
        else:
            verb = "Update" if is_update else "Install"
        project_owned = len(targets) == 1 and targets[0].key in self.project_owned_keys
        if project_owned:
            options = [f"{verb} (workstation-managed)", "Cancel"]
            track_options = [False]
            ownership_note = "This package is workstation-owned; user-managed.tsv will not be changed."
        else:
            label = f"{verb} and track" if len(targets) == 1 else f"Install and track {len(targets)} packages"
            label_untracked = f"{verb} without tracking" if len(targets) == 1 else f"Install {len(targets)} packages without tracking"
            options = [label, label_untracked, "Cancel"]
            track_options = [True, False]
            ownership_note = ""
        self.modal = {
            "kind": "install",
            "selected": 0,
            "options": options,
            "track_options": track_options,
            "ownership_note": ownership_note,
        }

    def _show_uninstall(self) -> None:
        row = self.selected_row
        if not row or not self._is_installed(row):
            self._set_message("This package is not installed")
            return
        self.remove_target = row
        self.modal = {
            "kind": "uninstall",
            "selected": 0,
            "options": ["Uninstall and keep tracking", "Uninstall and forget tracking", "Cancel"],
        }

    def _version_rows_for(self, row: PackageRow, query: str = "") -> List[PackageRow]:
        versions = sorted(
            self._versions_for(row),
            key=lambda candidate: (_date_value(candidate.release_date), _version_value(candidate.version), candidate.source.lower()),
            reverse=True,
        )
        if not query:
            return versions
        normalized = re.sub(r"[^a-z0-9]+", " ", query.lower()).split()
        return [
            candidate
            for candidate in versions
            if all(
                token in re.sub(
                    r"[^a-z0-9]+",
                    " ",
                    f"{candidate.version} {candidate.release_date} {candidate.source} {candidate.provider_label}".lower(),
                ).split()
                or token.replace(" ", "") in re.sub(r"[^a-z0-9]+", "", candidate.version.lower())
                for token in normalized
            )
        ]

    def _version_lines(self, row: PackageRow) -> List[str]:
        versions = self._version_rows_for(row)
        latest = versions[0] if versions else row
        lines = [
            f"{len(versions)} available version{'s' if len(versions) != 1 else ''} · newest first",
            "The ★ marker identifies the version selected by default for installation.",
            "",
        ]
        for candidate in versions:
            marker = "★" if (
                candidate.source == latest.source
                and candidate.identifier == latest.identifier
                and candidate.scope == latest.scope
                and candidate.version == latest.version
                and candidate.release_date == latest.release_date
            ) else " "
            release_date = candidate.release_date if candidate.release_date != "n/a" else "date not provided"
            lines.append(f"{marker} {candidate.version} · {release_date} · {candidate.provider_label} · {candidate.source}")
        return lines

    def _show_versions(self) -> None:
        row = self.selected_row
        if not row:
            return
        if self.active_filter == "Updates":
            self._set_message("Updates applies the latest installed package; use All or DNF for version history", 6.0)
            return
        available = self._versions_for(row)
        self.modal = {"kind": "versions", "row": row, "query": "", "selected": 0, "search_focus": False, "scroll": 0, "error": ""}
        if len(available) <= 1:
            self._start_versions_load(row)

    def _show_add_source(self) -> None:
        if not self._can_add_source():
            self._set_message("Aurelia source add is available from All or Aurelia", 5.0)
            return
        if self.operation_loading:
            self._set_message("An operation is already running", 5.0)
            return
        self.modal = {"kind": "source-add", "value": "", "error": ""}

    def _begin_source_add(self) -> None:
        if self.operation_loading:
            self._set_message("An operation is already running", 5.0)
            return
        url = str(self.modal.get("value", "")).strip() if self.modal else ""
        if not url:
            if self.modal:
                self.modal["error"] = "Enter an official GitHub repository URL."
            return
        if len(url) > 512 or any(char.isspace() for char in url) or not re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?", url):
            if self.modal:
                self.modal["error"] = "Use an exact HTTPS URL such as https://github.com/owner/repository."
            return
        self.modal = None
        self.operation_generation += 1
        generation = self.operation_generation
        self.operation_loading = True
        self._set_message("Adding and verifying Aurelia source…", 60.0)
        self._submit("source-add", lambda: self.backend.add_aurelia_source(url), generation)

    def _show_info(self) -> None:
        if not self.selected_row:
            return
        self.pending_source_row = None
        if self.info_loading or not self.info_text:
            self._start_info_load(self.selected_row)
        self.modal = {"kind": "info", "scroll": 0}

    def _open_source(self) -> None:
        row = self.selected_row
        if not row:
            return
        if self.info_loading:
            self.pending_source_row = row
            self._set_message("Loading source metadata…", 5.0)
            return
        if not self.info_text:
            self.pending_source_row = row
            self._start_info_load(row)
            self._set_message("Loading source metadata…", 5.0)
            return
        self.pending_source_row = None
        url = self.backend.source_url(self.info_fields)
        if not url:
            self.modal = {"kind": "message", "title": "Source unavailable", "lines": ["This provider did not publish a browser source URL.", f"Source: {row.source}"]}
            return
        if not url.startswith("https://"):
            self.modal = {"kind": "message", "title": "Source refused", "lines": ["Only HTTPS source URLs are opened.", f"Source: {url}"]}
            return

        self.modal = {"kind": "source", "url": url, "selected": 0}

    def _browser_commands(self, url: str) -> List[List[str]]:
        """Build desktop launchers in reliable order without shell parsing."""

        commands: List[List[str]] = []
        prefix = self._desktop_launch_prefix()
        gio = shutil.which("gio")
        if gio:
            commands.append(prefix + [gio, "open", url])
        xdg_open = shutil.which("xdg-open")
        if xdg_open:
            commands.append(prefix + [xdg_open, url])
        return commands

    @staticmethod
    def _desktop_launch_prefix() -> List[str]:
        """Use the active UWSM app scope when the TUI is in one."""

        if not any(
            os.environ.get(name)
            for name in ("UWSM_FINALIZE_VARNAMES", "UWSM_WAIT_VARNAMES", "IN_UWSM_ENV_PRELOADER")
        ):
            return []
        uwsm = shutil.which("uwsm-app")
        return [uwsm, "--"] if uwsm else []

    def _registered_browser_command(self, url: str, failures: List[str], remaining: float) -> Optional[List[str]]:
        """Resolve and use the desktop's registered HTTPS application."""

        gio = shutil.which("gio")
        gtk_launch = shutil.which("gtk-launch")
        xdg_mime = shutil.which("xdg-mime")
        if not (gio or gtk_launch) or not xdg_mime or remaining <= 0:
            return None
        command = [xdg_mime, "query", "default", "x-scheme-handler/https"]
        try:
            result = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=max(0.1, min(5.0, remaining)),
                check=False,
            )
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            detail = f"{' '.join(command)} failed: {error}"
            self._record_backend_diagnostic(f"ERROR: {detail}\n")
            failures.append(detail)
            return None
        if result.stderr:
            self._record_backend_diagnostic(result.stderr)
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip() or f"exit status {result.returncode}"
            failure = f"{' '.join(command)} failed: {detail}"
            self._record_backend_diagnostic(f"ERROR: {failure}\n")
            failures.append(failure)
            return None
        desktop_id = result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.desktop", desktop_id):
            detail = f"The default HTTPS desktop entry is invalid: {desktop_id or 'empty result'}"
            self._record_backend_diagnostic(f"ERROR: {detail}\n")
            failures.append(detail)
            return None
        self._log_event(f"INFO: HTTPS desktop handler selected: {desktop_id}")
        prefix = self._desktop_launch_prefix()
        if gio:
            return prefix + [gio, "launch", desktop_id, url]
        return prefix + [gtk_launch, desktop_id, url]

    def _attempt_browser_command(
        self,
        command: List[str],
        remaining: float,
        failures: List[str],
    ) -> Tuple[Optional[subprocess.CompletedProcess[str]], bool]:
        """Run one launcher; return its result and whether retrying is pointless."""

        command_text = " ".join(command)
        self._log_event(f"INFO: Browser launcher attempt: {shlex.join(command[:-1])} <url>")
        try:
            result = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=max(0.1, remaining),
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            detail = f"{command_text} timed out before opening the URL."
            if error.stderr:
                detail += f" {error.stderr.strip()}"
            self._record_backend_diagnostic(f"ERROR: {detail}\n")
            failures.append(detail)
            return None, True
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            detail = f"{command_text} failed: {error}"
            self._record_backend_diagnostic(f"ERROR: {detail}\n")
            failures.append(detail)
            return None, False

        if result.stderr:
            self._record_backend_diagnostic(result.stderr)
        if result.returncode == 0:
            self._log_event(f"INFO: Browser launcher accepted request: {shlex.join(command[:-1])} <url>")
            return result, True
        detail = result.stderr.strip() or result.stdout.strip() or "exit status " + str(result.returncode)
        failure = f"{command_text} failed: {detail}"
        self._record_backend_diagnostic(f"ERROR: {failure}\n")
        failures.append(failure)
        return None, False

    def _launch_source_url(self, url: str) -> None:
        commands = self._browser_commands(url)
        failures: List[str] = []
        deadline = time.monotonic() + 15.0
        self._log_event("INFO: Browser source launch requested")
        preferred = self._registered_browser_command(url, failures, deadline - time.monotonic())
        launch_commands = ([preferred] if preferred else []) + commands
        if not launch_commands:
            self.modal = {
                "kind": "message",
                "title": "Browser launcher unavailable",
                "lines": [url, "No HTTPS desktop handler or supported browser launcher was found. Use Copy URL and open it manually.", f"Diagnostic log: {self._display_diagnostic_log_path()}"],
            }
            self._log_event("ERROR: No HTTPS desktop handler or supported browser launcher was found")
            return
        self.modal = None
        result: Optional[subprocess.CompletedProcess[str]] = None
        suspended = False
        screen = getattr(self, "screen", None)
        try:
            if screen is not None:
                try:
                    curses.def_prog_mode()
                    curses.endwin()
                    suspended = True
                except curses.error as error:
                    # A terminal can be resized or lose its controlling
                    # session while the source dialog is active.  The browser
                    # request is still safe to attempt, but this must never
                    # escape and tear down the package manager.
                    self._record_error(error)
            for command in launch_commands:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    failures.append("Browser launcher retry window expired after 15s.")
                    break
                candidate, stop = self._attempt_browser_command(command, remaining, failures)
                if candidate is not None:
                    result = candidate
                    break
                if stop:
                    break
        finally:
            if screen is not None and suspended:
                try:
                    curses.reset_prog_mode()
                except curses.error as error:
                    self._record_error(error)
                for operation in (
                    lambda: screen.keypad(True),
                    lambda: screen.timeout(100),
                    lambda: screen.clear(),
                ):
                    try:
                        operation()
                    except curses.error as error:
                        self._record_error(error)

        if result is not None:
            self._set_message("Browser launch request accepted", 5.0)
            return
        lines = [url, "No browser launcher could open this URL."]
        lines.extend(failures or ["The available launchers returned no diagnostic."])
        lines.append(f"Diagnostic log: {self._display_diagnostic_log_path()}")
        self._log_event("ERROR: No browser launcher accepted the source URL")
        self.modal = {"kind": "message", "title": "Could not open source", "lines": lines}

    def _display_diagnostic_log_path(self) -> str:
        path = getattr(self, "diagnostic_log_path", None)
        if isinstance(path, Path):
            return str(path)
        return "persistent diagnostic log unavailable"

    def _copy_source_url(self, url: str) -> None:
        clipboard_commands = (
            ("wl-copy", ["{program}"]),
            ("xclip", ["{program}", "-selection", "clipboard"]),
            ("xsel", ["{program}", "--clipboard", "--input"]),
        )
        failures: List[str] = []
        for program_name, arguments in clipboard_commands:
            program = shutil.which(program_name)
            if not program:
                continue
            command = [program if argument == "{program}" else argument for argument in arguments]
            try:
                result = subprocess.run(
                    command,
                    input=url,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=10,
                    check=False,
                )
            except (OSError, subprocess.TimeoutExpired) as error:
                failures.append(f"{program_name}: {error}")
                continue
            if result.stderr:
                self._record_backend_diagnostic(result.stderr)
            if result.returncode == 0:
                self.modal = None
                self._set_message("Source URL copied to the clipboard", 5.0)
                return
            detail = result.stderr.strip() or result.stdout.strip() or f"exit status {result.returncode}"
            failures.append(f"{program_name}: {detail}")
        detail = failures[-1] if failures else "No supported clipboard utility was found (wl-copy, xclip, or xsel)."
        self.modal = {"kind": "message", "title": "Could not copy source URL", "lines": [url, detail]}

    def _begin_refresh(self) -> None:
        if self.operation_loading:
            self._set_message("An operation is already running", 5.0)
            return
        self.operation_generation += 1
        self.operation_loading = True
        self._set_message("Refreshing catalog metadata…", 30.0)
        self._submit("refresh", self.backend.refresh, self.operation_generation)

    def _begin_install(self, track: bool) -> None:
        if self.operation_loading:
            self._set_message("An operation is already running", 5.0)
            return
        targets = list(self.install_targets)
        if not targets:
            self.modal = None
            return
        if self._requires_privilege(targets) and not self._authorize_for_mutation():
            return
        self.modal = None
        exact_version = len(targets) == 1 and self.install_version_override == targets[0].version
        self.install_version_override = None
        self.operation_generation += 1
        generation = self.operation_generation
        self.operation_loading = True
        self._set_message(f"Installing {len(targets)} package{'s' if len(targets) != 1 else ''}…", 60.0)

        def install_all() -> str:
            output: List[str] = []
            for row in targets:
                output.append(self.backend.install_catalog_row(row, track, exact_version=exact_version))
            return "\n".join(part for part in output if part)

        self._submit("install", install_all, generation)

    def _begin_uninstall(self, forget: bool) -> None:
        if self.operation_loading:
            self._set_message("An operation is already running", 5.0)
            return
        row = self.remove_target or self.selected_row
        if not row:
            self.modal = None
            return
        if self._requires_privilege([row]) and not self._authorize_for_mutation():
            return
        self.modal = None
        self.operation_generation += 1
        generation = self.operation_generation
        self.operation_loading = True
        self._set_message(f"Uninstalling {row.identifier}…", 60.0)
        self._submit("uninstall", lambda: self.backend.remove_catalog_row(row, forget), generation)

    def _handle_modal_key(self, ch: int) -> bool:
        if not self.modal:
            return False
        kind = self.modal.get("kind")
        if kind == "source-add":
            if ch == 27:
                self.modal = None
            elif ch in (curses.KEY_BACKSPACE, 127, 8):
                self.modal["value"] = str(self.modal.get("value", ""))[:-1]
                self.modal["error"] = ""
            elif ch in (10, 13, curses.KEY_ENTER):
                self._begin_source_add()
            elif 0 <= ch <= 255 and curses.ascii.isprint(ch):
                value = str(self.modal.get("value", ""))
                if len(value) < 512:
                    self.modal["value"] = value + chr(ch)
                    self.modal["error"] = ""
            return True
        if kind == "versions":
            row = self.modal.get("row")
            if not isinstance(row, PackageRow):
                self.modal = None
                return True
            if self.versions_loading:
                if ch == ord("q"):
                    self.modal = None
                return True
            if ch == 27:
                if self.modal.get("search_focus"):
                    self.modal["search_focus"] = False
                else:
                    self.modal = None
                return True
            if self.modal.get("search_focus"):
                if ch in (10, 13, curses.KEY_ENTER):
                    self.modal["search_focus"] = False
                elif ch in (curses.KEY_BACKSPACE, 127, 8):
                    self.modal["query"] = str(self.modal.get("query", ""))[:-1]
                    self.modal["selected"] = 0
                elif 0 <= ch <= 255 and curses.ascii.isprint(ch):
                    query = str(self.modal.get("query", ""))
                    if len(query) < 128:
                        self.modal["query"] = query + chr(ch)
                        self.modal["selected"] = 0
                return True
            if ch == ord("q"):
                self.modal = None
            elif key_pressed(ch, self.config.key("search")):
                self.modal["search_focus"] = True
            else:
                versions = self._version_rows_for(row, str(self.modal.get("query", "")))
                if ch in (curses.KEY_UP, ord("k")) and versions:
                    self.modal["selected"] = max(0, self.modal.get("selected", 0) - 1)
                elif ch in (curses.KEY_DOWN, ord("j")) and versions:
                    self.modal["selected"] = min(len(versions) - 1, self.modal.get("selected", 0) + 1)
                elif ch in (10, 13, curses.KEY_ENTER):
                    if not versions:
                        self._set_message("No versions match this search")
                    else:
                        selected = max(0, min(self.modal.get("selected", 0), len(versions) - 1))
                        self.modal = None
                        self._show_install(versions[selected], exact_version=True)
            return True
        if ch in (27, ord("q")):
            self.modal = None
            return True
        if kind == "install":
            options = self.modal["options"]
            if ch in (curses.KEY_UP, ord("k")):
                self.modal["selected"] = (self.modal["selected"] - 1) % len(options)
            elif ch in (curses.KEY_DOWN, ord("j")):
                self.modal["selected"] = (self.modal["selected"] + 1) % len(options)
            elif ch in (10, 13, curses.KEY_ENTER):
                selected = self.modal["selected"]
                track_options = self.modal.get("track_options", [True, False])
                if selected < len(track_options):
                    self._begin_install(bool(track_options[selected]))
                else:
                    self.modal = None
            return True
        if kind == "sort":
            options = self.modal["options"]
            if ch in (curses.KEY_UP, ord("k")):
                self.modal["selected"] = (self.modal["selected"] - 1) % len(options)
            elif ch in (curses.KEY_DOWN, ord("j")):
                self.modal["selected"] = (self.modal["selected"] + 1) % len(options)
            elif ch in (10, 13, curses.KEY_ENTER):
                self._set_sort_mode(options[self.modal["selected"]])
                self.modal = None
            return True
        if kind == "uninstall":
            options = self.modal["options"]
            if ch in (curses.KEY_UP, ord("k")):
                self.modal["selected"] = (self.modal["selected"] - 1) % len(options)
            elif ch in (curses.KEY_DOWN, ord("j")):
                self.modal["selected"] = (self.modal["selected"] + 1) % len(options)
            elif ch in (10, 13, curses.KEY_ENTER):
                selected = self.modal["selected"]
                if selected == 0:
                    self._begin_uninstall(False)
                elif selected == 1:
                    self._begin_uninstall(True)
                else:
                    self.remove_target = None
                    self.modal = None
            return True
        if kind == "source":
            options = ("Open in browser", "Copy URL", "Close")
            if ch in (curses.KEY_UP, ord("k")):
                self.modal["selected"] = (self.modal.get("selected", 0) - 1) % len(options)
            elif ch in (curses.KEY_DOWN, ord("j")):
                self.modal["selected"] = (self.modal.get("selected", 0) + 1) % len(options)
            elif ch in (10, 13, curses.KEY_ENTER):
                selected = self.modal.get("selected", 0)
                url = str(self.modal.get("url", ""))
                if selected == 0:
                    self._launch_source_url(url)
                elif selected == 1:
                    self._copy_source_url(url)
                else:
                    self.modal = None
            return True
        if kind in {"help", "info"}:
            if ch in (10, 13, curses.KEY_ENTER):
                self.modal = None
                return True
            if ch in (curses.KEY_UP, ord("k")):
                self.modal["scroll"] = max(0, self.modal.get("scroll", 0) - 1)
            elif ch in (curses.KEY_DOWN, ord("j")):
                self.modal["scroll"] = self.modal.get("scroll", 0) + 1
            elif ch in (curses.KEY_PPAGE,):
                self.modal["scroll"] = max(0, self.modal.get("scroll", 0) - 8)
            elif ch in (curses.KEY_NPAGE,):
                self.modal["scroll"] = self.modal.get("scroll", 0) + 8
            return True
        if kind == "message" and ch in (10, 13, curses.KEY_ENTER, ord(" ")):
            self.modal = None
            return True
        return True

    def _handle_search_key(self, ch: int) -> bool:
        if not self.query_focus:
            return False
        if ch in (27, 10, 13, curses.KEY_ENTER):
            self.query_focus = False
            return True
        cursor = max(0, min(getattr(self, "query_cursor", len(self.query)), len(self.query)))
        if ch == curses.KEY_LEFT:
            self.query_cursor = max(0, cursor - 1)
            return True
        if ch == curses.KEY_RIGHT:
            self.query_cursor = min(len(self.query), cursor + 1)
            return True
        if ch == curses.KEY_HOME:
            self.query_cursor = 0
            return True
        if ch == curses.KEY_END:
            self.query_cursor = len(self.query)
            return True
        changed = False
        if ch in (curses.KEY_BACKSPACE, 127, 8):
            if cursor > 0:
                self.query = self.query[: cursor - 1] + self.query[cursor:]
                self.query_cursor = cursor - 1
                changed = True
        elif ch == curses.KEY_DC:
            if cursor < len(self.query):
                self.query = self.query[:cursor] + self.query[cursor + 1 :]
                self.query_cursor = cursor
                changed = True
        elif 0 <= ch <= 255 and curses.ascii.isprint(ch):
            self.query = self.query[:cursor] + chr(ch) + self.query[cursor:]
            self.query_cursor = cursor + 1
            changed = True
        else:
            return True
        if changed:
            self.query_changed_at = time.monotonic()
        return True

    def _handle_escape_sequence(self) -> bool:
        """Decode delayed arrow and Alt-letter sequences before plain Escape."""

        if self.screen is None:
            return False
        self.screen.timeout(30)
        follow = self.screen.getch()
        if follow == ord("["):
            sequence_end = self.screen.getch()
            arrow_keys = {
                ord("A"): curses.KEY_UP,
                ord("B"): curses.KEY_DOWN,
                ord("C"): curses.KEY_RIGHT,
                ord("D"): curses.KEY_LEFT,
            }
            self.screen.timeout(100)
            if sequence_end in arrow_keys:
                self._handle_key(arrow_keys[sequence_end])
                return True
        self.screen.timeout(100)
        if follow != -1:
            for name in ("preview_toggle", "preview_up", "preview_down"):
                if key_pressed(follow, self.config.key(name)):
                    if name == "preview_toggle":
                        self.show_details = not self.show_details
                    elif name == "preview_up":
                        self.detail_scroll = max(0, self.detail_scroll - 1)
                    else:
                        self.detail_scroll += 1
                    return True
        return False

    def _handle_key(self, ch: int) -> None:
        if self.modal and self._handle_modal_key(ch):
            return
        if self._handle_search_key(ch):
            return
        if ch == -1:
            return
        if ch == 27:
            if self._handle_escape_sequence():
                return
            if self.focus_area in {"actions", "filters"}:
                self.focus_area = "list"
                self._set_message("Package list focused")
            else:
                self.running = False
            return
        if key_pressed(ch, self.config.key("quit")):
            self.running = False
            return
        if self.focus_area == "filters":
            if key_pressed(ch, self.config.key("select")) or ch == 9:
                self._cycle_focus()
            elif key_pressed(ch, self.config.key("filter_previous")):
                self._cycle_filter(-1)
            elif key_pressed(ch, self.config.key("filter_next")):
                self._cycle_filter(1)
            elif key_pressed(ch, self.config.key("accept")):
                self.focus_area = "list"
                self._set_message("Package list focused")
            elif key_pressed(ch, self.config.key("help")):
                self._show_help()
            return
        if self.focus_area == "actions":
            if key_pressed(ch, self.config.key("select")) or ch == 9:
                self.focus_area = "list"
                self._set_message("Package list focused")
            elif key_pressed(ch, self.config.key("up")) or ch == ord("k"):
                self.action_index = (self.action_index - 1) % max(1, len(self._action_items()))
            elif key_pressed(ch, self.config.key("down")) or ch == ord("j"):
                self.action_index = (self.action_index + 1) % max(1, len(self._action_items()))
            elif key_pressed(ch, self.config.key("accept")):
                self._run_action()
            elif key_pressed(ch, self.config.key("help")):
                self._show_help()
            return
        if key_pressed(ch, self.config.key("search")):
            self.query_focus = True
        elif key_pressed(ch, self.config.key("up")) or ch in (ord("k"),):
            self._move_selection(-1)
        elif key_pressed(ch, self.config.key("down")) or ch in (ord("j"),):
            self._move_selection(1)
        elif key_pressed(ch, self.config.key("page_up")):
            self._move_selection(-self.visible_list_rows, self.visible_list_rows)
        elif key_pressed(ch, self.config.key("page_down")):
            self._move_selection(self.visible_list_rows, self.visible_list_rows)
        elif key_pressed(ch, self.config.key("select")) or ch == 9:
            self._cycle_focus()
        elif key_pressed(ch, self.config.key("filter_previous")):
            self._cycle_filter(-1)
        elif key_pressed(ch, self.config.key("filter_next")):
            self._cycle_filter(1)
        elif key_pressed(ch, self.config.key("queue")):
            self._toggle_queue()
        elif key_pressed(ch, self.config.key("select_all")):
            self._select_all()
        elif key_pressed(ch, self.config.key("accept")):
            self._focus_actions()
        elif key_pressed(ch, self.config.key("refresh")) or ch == ord("r"):
            self._begin_refresh()
        elif key_pressed(ch, self.config.key("sort")):
            self._show_sort()
        elif key_pressed(ch, self.config.key("sort_reverse")):
            self._toggle_sort_direction()
        elif key_pressed(ch, self.config.key("help")):
            self._show_help()
        elif key_pressed(ch, self.config.key("versions")):
            self._show_versions()
        elif key_pressed(ch, self.config.key("add_source")):
            self._show_add_source()
        elif key_pressed(ch, self.config.key("source")):
            self._open_source()
        elif key_pressed(ch, self.config.key("info")):
            self._show_info()

    def _maybe_submit_query(self) -> None:
        if self.query_changed_at and time.monotonic() - self.query_changed_at >= 0.16:
            self.query_changed_at = 0.0
            self._start_catalog_load()

    def _init_colors(self) -> Dict[str, int]:
        assert self.screen is not None
        screen = self.screen
        try:
            curses.start_color()
            curses.use_default_colors()
        except curses.error:
            return {"base": 0}
        color_count = max(8, min(getattr(curses, "COLORS", 8), 256))
        roles = {
            "background": self.theme.color("background"),
            "surface": self.theme.color("surface"),
            "selection": self.theme.color("selection"),
            "text": self.theme.color("text"),
            "secondary": self.theme.color("textSecondary"),
            "muted": self.theme.color("textMuted"),
            "accent": self.theme.color("accent"),
            "accent_alt": self.theme.color("accentAlt"),
            "success": self.theme.color("success"),
            "warning": self.theme.color("warning"),
            "error": self.theme.color("error"),
            "border": self.theme.color("border"),
            "border_active": self.theme.color("borderActive"),
            "dnf": self.theme.color("dnf"),
            "flatpak": self.theme.color("flatpak"),
            "aurelia": self.theme.color("aurelia"),
        }
        for provider_name in ("dnf", "flatpak", "aurelia"):
            roles[provider_name] = _readable_color(roles[provider_name], roles["surface"], roles["text"])
        selection_foreground = max(
            ("text", "accent", "accent_alt", "background"),
            key=lambda name: abs(
                sum(roles[name][channel] for channel in range(3))
                - sum(roles["selection"][channel] for channel in range(3))
            ),
        )
        roles["selection_text"] = roles[selection_foreground]
        indices = {name: nearest_xterm(rgb, color_count) for name, rgb in roles.items()}
        pairs: Dict[str, int] = {}
        pair_number = 1

        def create(name: str, foreground: str, background: str = "background") -> None:
            nonlocal pair_number
            if pair_number >= getattr(curses, "COLOR_PAIRS", 64):
                pairs[name] = pairs.get("base", 0)
                return
            try:
                curses.init_pair(pair_number, indices[foreground], indices[background])
                pairs[name] = pair_number
                pair_number += 1
            except curses.error:
                pairs[name] = pairs.get("base", 0)

        create("base", "text", "background")
        create("surface", "text", "surface")
        create("selection", "selection_text", "selection")
        create("text_selected", "selection_text", "selection")
        for name in ("secondary", "muted", "accent", "accent_alt", "success", "warning", "error", "border", "border_active", "dnf", "flatpak", "aurelia"):
            create(name, name, "background")
        create("input", "text", "surface")
        create("detail", "text", "background")
        create("provider_dnf", "dnf", "surface")
        create("provider_flatpak", "flatpak", "surface")
        create("provider_aurelia", "aurelia", "surface")
        create("provider_dnf_selected", "dnf", "selection")
        create("provider_flatpak_selected", "flatpak", "selection")
        create("provider_aurelia_selected", "aurelia", "selection")
        screen.bkgd(" ", curses.color_pair(pairs.get("base", 0)))
        return pairs

    def _attr(self, pairs: Dict[str, int], name: str, bold: bool = False, dim: bool = False, reverse: bool = False) -> int:
        value = curses.color_pair(pairs.get(name, pairs.get("base", 0)))
        if bold:
            value |= curses.A_BOLD
        if dim:
            value |= curses.A_DIM
        if reverse:
            value |= curses.A_REVERSE
        return value

    def _add(self, y: int, x: int, value: str, width: int, attr: int = 0) -> None:
        if self.screen is None or y < 0 or x < 0 or width <= 0:
            return
        try:
            self.screen.addnstr(y, x, _truncate(value, width), width, attr)
        except curses.error:
            pass

    def _fill(self, y: int, x: int, height: int, width: int, attr: int) -> None:
        if self.screen is None:
            return
        for row in range(max(0, height)):
            self._add(y + row, x, " " * max(0, width), width, attr)

    def _box(self, y: int, x: int, height: int, width: int, pairs: Dict[str, int], title: str = "", title_attr: Optional[int] = None) -> None:
        if height < 2 or width < 2:
            return
        border_attr = self._attr(pairs, "border_active")
        surface_attr = self._attr(pairs, "surface")
        self._fill(y + 1, x + 1, height - 2, width - 2, surface_attr)
        horizontal = "─" * max(0, width - 2)
        self._add(y, x, "┌" + horizontal + "┐", width, border_attr)
        for row in range(1, height - 1):
            self._add(y + row, x, "│", 1, border_attr)
            self._add(y + row, x + width - 1, "│", 1, border_attr)
        self._add(y + height - 1, x, "└" + horizontal + "┘", width, border_attr)
        if title:
            label = f" {title} "
            self._add(y, x + 2, label, max(1, width - 4), title_attr or self._attr(pairs, "accent_alt", bold=True))

    def _status_text(self) -> str:
        if self.catalog_loading:
            return "Catalog loading…"
        status = self.catalog_status
        if status.total == "unknown":
            return "Catalog status unavailable"
        state = "fresh" if status.freshness == "fresh" else status.freshness
        if self.operation_loading:
            state = "working…"
        return f"● Catalog {state}  |  {status.total} packages  |  DNF {status.dnf}  |  Flatpak {status.flatpak}  |  Aurelia {status.aurelia}"

    def _draw_header(self, pairs: Dict[str, int], width: int) -> int:
        title_attr = self._attr(pairs, "accent_alt", bold=True)
        text_attr = self._attr(pairs, "text")
        secondary_attr = self._attr(pairs, "secondary")
        success_attr = self._attr(pairs, "success", bold=True)
        title = self.config.label("title")
        brand = "Aurelia"
        self._add(0, 1, brand, max(1, width // 3), title_attr)
        separator_x = min(width - 1, 1 + len(brand) + 2)
        self._add(0, separator_x, "│", 1, self._attr(pairs, "border"))
        self._add(0, separator_x + 2, title, max(1, width - separator_x - 4), secondary_attr)
        status = self._status_text()
        status_width = min(max(20, len(status)), max(1, width - 2))
        status_x = max(separator_x + len(title) + 5, width - status_width - 1)
        if status_x > separator_x + len(title) + 4:
            self._add(0, status_x, status, width - status_x - 1, success_attr if "fresh" in status else secondary_attr)
        self._add(1, 1, "Search, install and manage software from DNF, Flatpak and Aurelia", width - 2, secondary_attr)
        return 3

    def _draw_search(self, pairs: Dict[str, int], y: int, width: int) -> int:
        self._box(y, 1, 3, width - 2, pairs, self.config.label("input"), self._attr(pairs, "accent"))
        prompt_width = max(1, width - 8)
        if not self.query and not self.query_focus:
            prompt = "▶ Search package IDs, names, descriptions, commands, or capabilities"
        elif not self.query_focus:
            prompt = "▶ " + self.query
        else:
            cursor = max(0, min(getattr(self, "query_cursor", len(self.query)), len(self.query)))
            raw = self.query[:cursor] + "▏" + self.query[cursor:]
            available = max(1, prompt_width - 2)
            if len(raw) > available:
                start = max(0, min(cursor - available // 2, len(raw) - available))
                end = start + available
                view = raw[start:end]
                if start > 0:
                    view = "…" + view[1:]
                if end < len(raw):
                    view = view[:-1] + "…"
                raw = view
            prompt = "▶ " + raw
        self._add(y + 1, 3, prompt, width - 8, self._attr(pairs, "text", bold=self.query_focus))
        if not self.query_focus:
            self._add(y + 1, max(3, width - 22), f"Press {_display_key(self.config.key('search'))} to focus", 18, self._attr(pairs, "muted", dim=True))
        return y + 4

    def _draw_filters(self, pairs: Dict[str, int], y: int, width: int) -> int:
        sort_text = f"Sort: {self.sort_mode} [{_display_key(self.config.key('sort'))}/{_display_key(self.config.key('sort_reverse'))}]"
        labels = [
            (filter_name, f"[ {filter_name} ]" if filter_name == self.active_filter else filter_name)
            for filter_name in self.filters
        ]
        tab_total = sum(len(label) + 3 for _filter_name, label in labels)
        same_line = tab_total + len(sort_text) + 4 <= width - 2
        max_tab_width = max(1, width - 4)
        tab_rows: List[List[Tuple[str, str]]] = [[]]
        row_width = 0
        for filter_name, label in labels:
            token_width = len(label) + 3
            if tab_rows[-1] and row_width + token_width > max_tab_width:
                tab_rows.append([])
                row_width = 0
            tab_rows[-1].append((filter_name, label))
            row_width += token_width

        for row_index, row in enumerate(tab_rows):
            x = 2
            for filter_name, label in row:
                if filter_name == self.active_filter:
                    attr = self._attr(pairs, "selection" if self.focus_area == "filters" else "accent_alt", bold=True)
                else:
                    attr = self._attr(pairs, "secondary")
                if x < width - 1:
                    self._add(y + row_index, x, label, min(len(label) + 1, width - x - 1), attr)
                x += len(label) + 3

        sort_y = y if same_line and len(tab_rows) == 1 else y + len(tab_rows)
        sort_x = max(2, width - len(sort_text) - 3)
        self._add(sort_y, sort_x, sort_text, len(sort_text) + 2, self._attr(pairs, "secondary"))
        return sort_y + 2

    def _row_size(self, row: PackageRow) -> str:
        if row.installed_size != "n/a":
            return row.installed_size
        if row.download_size != "n/a":
            return "↓ " + row.download_size
        return "n/a"

    def _provider_attr(self, pairs: Dict[str, int], provider: str, bold: bool = True, selected: bool = False) -> int:
        suffix = "_selected" if selected else ""
        return self._attr(pairs, f"provider_{provider}{suffix}", bold=bold)

    def _draw_list(self, pairs: Dict[str, int], y: int, x: int, height: int, width: int) -> int:
        visible_rows = max(1, (height - 2) // 2)
        self.visible_list_rows = visible_rows
        self.top_index = _selection_window(self.selected_index, len(self.filtered_rows), visible_rows, self.top_index)
        end = min(len(self.filtered_rows), self.top_index + visible_rows)
        title = f"{self.config.label('list')}  {self.top_index + 1 if self.filtered_rows else 0}-{end}/{len(self.filtered_rows)}"
        self._box(y, x, height, width, pairs, title, self._attr(pairs, "accent"))
        inner_width = max(1, width - 4)
        if not self.filtered_rows:
            if self.catalog_loading or self.query_loading:
                message = "Loading catalog…"
            elif self.active_filter == "Installed" and (self.status_loading or self.installed_loading):
                message = "Loading installed package state…"
            elif self.active_filter == "Updates" and (self.status_loading or self.installed_loading or self.updates_loading):
                message = "Loading update information…"
            else:
                message = "No packages match this search or filter."
            self._add(y + 2, x + 2, message, inner_width, self._attr(pairs, "secondary"))
            return max(1, (height - 2) // 2)
        provider_width = 8
        version_width = min(16, max(10, inner_width // 5))
        size_width = min(13, max(9, inner_width // 6))
        fixed_width = 2 + 4 + 2 + 1 + provider_width + 1 + version_width + 1 + size_width + 2
        name_width = min(26, max(12, inner_width - fixed_width))
        for offset, index in enumerate(range(self.top_index, min(end, self.top_index + visible_rows))):
            row = self.filtered_rows[index]
            row_y = y + 1 + offset * 2
            selected = index == self.selected_index
            row_attr = self._attr(pairs, "selection" if selected else "surface")
            pointer = "▸" if selected else " "
            queued = "+" if row in self.queue_rows else " "
            installed = "✓" if self._is_installed(row) else " "
            update = "↑" if self._is_update(row) else " "
            name = f"{installed}{update} {self._display_name(row)}"
            start_x = x + 2
            name_x = start_x + 8
            provider_x = name_x + name_width + 1
            version_x = provider_x + provider_width + 1
            size_x = version_x + version_width + 1
            queue_x = size_x + size_width + 1
            text_attr = self._attr(pairs, "text_selected" if selected else "text", bold=selected)
            self._fill(row_y, x + 1, 1, width - 2, row_attr)
            self._add(row_y, start_x, pointer, 1, self._attr(pairs, "accent", bold=selected))
            self._add(row_y, start_x + 2, f"{index + 1:>3}", 3, text_attr)
            self._add(row_y, start_x + 6, row.icon, 1, self._provider_attr(pairs, row.provider, bold=False, selected=selected))
            self._add(row_y, name_x, name, name_width, text_attr)
            self._add(row_y, provider_x, row.provider_label, provider_width, self._provider_attr(pairs, row.provider, selected=selected))
            self._add(row_y, version_x, row.version, version_width, text_attr)
            self._add(row_y, size_x, self._row_size(row), size_width, text_attr)
            self._add(row_y, queue_x, queued, 1, self._attr(pairs, "success" if not selected else "text_selected", bold=True))
            summary_attr = self._attr(pairs, "secondary")
            self._add(row_y + 1, x + 7, row.summary, inner_width - 5, summary_attr)
        return visible_rows

    def _detail_lines(self, row: PackageRow, width: int) -> List[Tuple[str, int]]:
        pairs = self._pairs
        lines: List[Tuple[str, int]] = []
        installed = self._is_installed(row)
        # The selected catalog row is the available candidate.  A provider
        # metadata query such as `dnf info quickshell` can report the already
        # installed EVR when it is not qualified by a version, so never let
        # that preview overwrite the candidate shown by the list.
        target_version = row.version if row.version not in {"", "n/a"} else self.info_fields.get("Version", row.version)
        installed_versions = sorted(self.installed_versions.get(self._group_key(row), set()), key=_version_value, reverse=True)
        installed_version = ", ".join(installed_versions) if installed_versions else "not available"
        install_size = self.info_fields.get("Installed size", row.installed_size) if installed else row.installed_size
        fields = [
            ("Available version" if self.active_filter == "Updates" else "Version", target_version),
            ("Status", "Update available" if self._is_update(row) else ("Installed" if self._is_installed(row) else "Available")),
            ("Architecture", self.info_fields.get("Architecture", row.architecture)),
            ("Installed size" if installed else "Install size", install_size),
            ("Download size", self.info_fields.get("Download size", row.download_size)),
            ("Repository", self.info_fields.get("Source", row.source)),
            ("Release date", self.info_fields.get("Release date", row.release_date)),
        ]
        version_count = len(self._versions_for(row))
        if version_count > 1 and self.active_filter != "Updates":
            fields.insert(2, ("Versions", f"{version_count} · press {_display_key(self.config.key('versions'))} for history"))
        if installed:
            fields.insert(1, ("Installed version", installed_version))
            if self._is_update(row):
                fields.insert(2, ("Change", f"{installed_version} → {target_version}"))
        for label, value in fields:
            prefix = f"{label:<16} : "
            value_lines = _wrap(str(value), max(1, width - len(prefix)))
            for index, value_line in enumerate(value_lines):
                lines.append(((prefix if index == 0 else " " * len(prefix)) + value_line, self._attr(pairs, "text")))
        lines.append(("", 0))
        description = self.info_fields.get("Description", row.summary)
        for line in _wrap(description, max(1, width - 4)):
            lines.append((line, self._attr(pairs, "secondary")))
        lines.append(("", 0))
        lines.append(("Actions", self._attr(pairs, "accent_alt", bold=True)))
        for index, (_action, label) in enumerate(self._action_items(row)):
            selected = self.focus_area == "actions" and index == self.action_index
            prefix = "▸  " if selected else "   "
            lines.append((prefix + label, self._attr(pairs, "selection" if selected else "secondary", bold=selected)))
        return lines

    def _draw_detail(self, pairs: Dict[str, int], y: int, x: int, height: int, width: int) -> None:
        row = self.selected_row
        self._box(y, x, height, width, pairs, self.config.label("preview"), self._attr(pairs, "accent"))
        if not row:
            self._add(y + 2, x + 2, "Select a package to inspect metadata and actions.", width - 4, self._attr(pairs, "secondary"))
            return
        inner_width = max(1, width - 4)
        title_attr = self._attr(pairs, "accent_alt", bold=True)
        self._add(y + 1, x + 2, self._display_name(row), max(1, width - 18), title_attr)
        badge = f" {row.provider_label} "
        self._add(y + 1, x + width - len(badge) - 3, badge, len(badge) + 1, self._provider_attr(pairs, row.provider))
        detail_lines = self._detail_lines(row, inner_width)
        content_y = y + 2
        # Keep the asynchronous status line separate from metadata. On a
        # short stacked layout, drawing it over the last visible field made
        # values appear truncated or concatenated while the backend loaded.
        available = max(0, height - 4) if self.info_loading else max(1, height - 3)
        if self.focus_area == "actions":
            action_start = next((index for index, (line, _attr) in enumerate(detail_lines) if line == "Actions"), len(detail_lines))
            action_line = min(len(detail_lines) - 1, action_start + 1 + min(self.action_index, max(0, len(self._action_items(row)) - 1)))
            viewport = max(1, available)
            if action_line < self.detail_scroll:
                self.detail_scroll = action_line
            elif action_line >= self.detail_scroll + viewport:
                self.detail_scroll = action_line - viewport + 1
        start = min(self.detail_scroll, max(0, len(detail_lines) - max(1, available)))
        for offset, (line, attr) in enumerate(detail_lines[start : start + available]):
            if content_y + offset >= y + height - 1:
                break
            if line == "":
                continue
            self._add(content_y + offset, x + 2, line, inner_width, attr)
        if self.info_loading:
            self._add(y + height - 2, x + 2, "Loading metadata…", inner_width, self._attr(pairs, "warning"))

    def _help_lines(self) -> List[str]:
        def key(name: str) -> str:
            return _display_key(self.config.key(name))

        def shortcut(keys: str, action: str) -> str:
            return f"  {keys:<18} {action}"

        lines = [
            "SHORTCUTS",
            shortcut(f"{key('up')}/{key('down')}", "Move"),
            shortcut(f"{key('page_up')}/{key('page_down')}", "Page"),
            shortcut(key("select"), "Tabs / packages"),
            shortcut(f"{key('filter_previous')}/{key('filter_next')}", "Change tab"),
            shortcut(key("search"), "Search package metadata"),
            shortcut(key("accept"), "Open / run Actions"),
            shortcut(key("cancel"), "Back / close"),
            shortcut(key("quit"), "Quit"),
            "",
            "PACKAGE",
            shortcut(key("queue"), "Toggle queue"),
            shortcut(key("select_all"), "Queue visible results"),
            shortcut(key("versions"), "Versions / exact downgrade (not Updates)"),
            shortcut(key("source"), "Open source URL"),
            shortcut(key("info"), "Full metadata"),
            shortcut(key("preview_toggle"), "Toggle details"),
            shortcut(f"{key('preview_up')}/{key('preview_down')}", "Scroll metadata"),
            shortcut(key("sort"), "Choose sort order"),
            shortcut(key("sort_reverse"), "Reverse sort"),
            shortcut(key("add_source"), "Add Aurelia source (All/Aurelia)"),
            "",
            "DIALOGS",
            shortcut(f"{key('up')}/{key('down')}", "Choose"),
            shortcut(key("accept"), "Confirm"),
            shortcut(key("cancel"), "Cancel"),
            "",
            "STATUS",
            shortcut(key("refresh"), "Refresh metadata only"),
            "  Errors stay visible; failed refresh keeps the last catalog.",
        ]
        if self.diagnostics:
            lines.extend(["", "RECENT DIAGNOSTICS"])
            lines.extend(f"  {line}" for line in self.diagnostics[-8:])
        return lines

    def _modal_content(self, width: int, height: int) -> Tuple[str, List[str], int]:
        if not self.modal:
            return "", [], 0
        kind = self.modal.get("kind")
        if kind == "help":
            return "Package Manager Help", self._help_lines(), self.modal.get("scroll", 0)
        if kind == "info":
            lines = self.info_text.splitlines() if self.info_text else ["Loading complete package metadata…"]
            return "Complete Package Metadata", lines, self.modal.get("scroll", 0)
        if kind == "versions":
            row = self.modal.get("row")
            if not isinstance(row, PackageRow):
                return "Package Versions", ["Version metadata is unavailable."], self.modal.get("scroll", 0)
            return f"Versions · {self._display_name(row)}", self._version_lines(row), self.modal.get("scroll", 0)
        if kind == "message":
            return str(self.modal.get("title", "Message")), list(self.modal.get("lines", [])), 0
        return "", [], 0

    def _draw_modal(self, pairs: Dict[str, int], height: int, width: int) -> None:
        if not self.modal:
            return
        kind = self.modal.get("kind")
        if kind == "versions":
            row = self.modal.get("row")
            if not isinstance(row, PackageRow):
                return
            query = str(self.modal.get("query", ""))
            versions = self._version_rows_for(row, query)
            modal_width = min(width - 4, 96)
            modal_height = min(height - 4, max(12, height - 4))
            x = max(1, (width - modal_width) // 2)
            y = max(1, (height - modal_height) // 2)
            self._box(y, x, modal_height, modal_width, pairs, f"Versions · {self._display_name(row)}", self._attr(pairs, "accent_alt", bold=True))
            self._add(y + 2, x + 3, f"{len(versions)} match{'es' if len(versions) != 1 else ''} · newest release first", modal_width - 6, self._attr(pairs, "secondary"))
            search_attr = self._attr(pairs, "input", bold=bool(self.modal.get("search_focus")))
            self._fill(y + 3, x + 2, 1, modal_width - 4, search_attr)
            self._add(y + 3, x + 4, f"/ {query}", modal_width - 8, search_attr)
            visible_rows = max(1, modal_height - 7)
            selected = max(0, min(self.modal.get("selected", 0), max(0, len(versions) - 1)))
            self.modal["selected"] = selected
            top = _selection_window(selected, len(versions), visible_rows, self.modal.get("scroll", 0))
            self.modal["scroll"] = top
            if self.versions_loading:
                self._add(y + 5, x + 3, "Loading version history…", modal_width - 6, self._attr(pairs, "warning"))
            elif self.modal.get("error"):
                self._add(y + 5, x + 3, str(self.modal["error"]), modal_width - 6, self._attr(pairs, "error"))
            elif not versions:
                self._add(y + 5, x + 3, "No versions match this search.", modal_width - 6, self._attr(pairs, "warning"))
            else:
                latest = versions[0]
                for offset, index in enumerate(range(top, min(len(versions), top + visible_rows))):
                    candidate = versions[index]
                    selected_row = index == selected
                    row_attr = self._attr(pairs, "selection" if selected_row else "surface")
                    self._fill(y + 5 + offset, x + 1, 1, modal_width - 2, row_attr)
                    marker = "★" if candidate.version == latest.version and candidate.source == latest.source and candidate.release_date == latest.release_date else " "
                    release_date = candidate.release_date if candidate.release_date != "n/a" else "date n/a"
                    line = f"{marker} {candidate.version} · {release_date} · {candidate.provider_label} · {candidate.source}"
                    self._add(y + 5 + offset, x + 3, line, modal_width - 6, self._attr(pairs, "text_selected" if selected_row else "text", bold=selected_row))
            footer = "Type version/source · Enter list · Esc back" if self.modal.get("search_focus") else "↑/↓ choose · Enter install selected · / search · Esc close"
            self._add(y + modal_height - 2, x + 3, footer, modal_width - 6, self._attr(pairs, "muted"))
            return
        if kind == "source-add":
            modal_width = min(width - 4, 84)
            modal_height = min(height - 4, 12)
            x = max(1, (width - modal_width) // 2)
            y = max(1, (height - modal_height) // 2)
            self._box(y, x, modal_height, modal_width, pairs, "Add Aurelia source", self._attr(pairs, "accent_alt", bold=True))
            self._add(y + 2, x + 3, "Official GitHub repository URL", modal_width - 6, self._attr(pairs, "text", bold=True))
            self._add(y + 3, x + 3, "https://github.com/owner/repository", modal_width - 6, self._attr(pairs, "muted"))
            self._add(y + 4, x + 3, "Verified Aurelia source only; DNF repositories stay under DNF.", modal_width - 6, self._attr(pairs, "secondary"))
            value = str(self.modal.get("value", ""))
            self._fill(y + 6, x + 2, 1, modal_width - 4, self._attr(pairs, "input"))
            self._add(y + 6, x + 4, "› " + value, modal_width - 8, self._attr(pairs, "input", bold=True))
            error = str(self.modal.get("error", ""))
            if error:
                self._add(y + 8, x + 3, error, modal_width - 6, self._attr(pairs, "error"))
            self._add(y + modal_height - 2, x + 3, "Type URL · Enter verify/add · Esc cancel", modal_width - 6, self._attr(pairs, "muted"))
            return
        if kind == "sort":
            options = self.modal["options"]
            modal_width = min(width - 4, 64)
            modal_height = min(height - 4, max(10, 7 + len(options)))
            x = max(1, (width - modal_width) // 2)
            y = max(1, (height - modal_height) // 2)
            self._box(y, x, modal_height, modal_width, pairs, "Sort packages", self._attr(pairs, "accent_alt", bold=True))
            self._add(y + 2, x + 3, "Choose the ordering for the package list.", modal_width - 6, self._attr(pairs, "secondary"))
            for index, option in enumerate(options):
                attr = self._attr(pairs, "selection" if index == self.modal["selected"] else "surface", bold=index == self.modal["selected"])
                self._fill(y + 4 + index, x + 2, 1, modal_width - 4, attr)
                self._add(y + 4 + index, x + 4, ("▸ " if index == self.modal["selected"] else "  ") + option, modal_width - 8, attr)
            self._add(y + modal_height - 2, x + 3, "↑/↓ choose · Enter apply · Esc cancel", modal_width - 6, self._attr(pairs, "muted"))
            return
        if kind == "install":
            modal_width = min(width - 4, 72)
            modal_height = min(height - 4, 10)
            x = max(1, (width - modal_width) // 2)
            y = max(1, (height - modal_height) // 2)
            self._box(y, x, modal_height, modal_width, pairs, "Review installation", self._attr(pairs, "accent_alt", bold=True))
            targets = self.install_targets
            summary = f"{len(targets)} package{'s' if len(targets) != 1 else ''} selected"
            if self.install_version_override and len(targets) == 1:
                summary += f" · version {self.install_version_override}"
            self._add(y + 2, x + 3, summary, modal_width - 6, self._attr(pairs, "text"))
            note = str(self.modal.get("ownership_note", ""))
            options_y = y + 4
            if note:
                self._add(y + 3, x + 3, note, modal_width - 6, self._attr(pairs, "warning"))
                options_y = y + 5
            for index, option in enumerate(self.modal["options"]):
                attr = self._attr(pairs, "selection" if index == self.modal["selected"] else "surface", bold=index == self.modal["selected"])
                self._fill(options_y + index, x + 2, 1, modal_width - 4, attr)
                self._add(options_y + index, x + 4, ("▸ " if index == self.modal["selected"] else "  ") + option, modal_width - 8, attr)
            self._add(y + modal_height - 2, x + 3, "↑/↓ choose · Enter confirm · Esc cancel", modal_width - 6, self._attr(pairs, "muted"))
            return
        if kind == "uninstall":
            modal_width = min(width - 4, 76)
            modal_height = min(height - 4, 12)
            x = max(1, (width - modal_width) // 2)
            y = max(1, (height - modal_height) // 2)
            self._box(y, x, modal_height, modal_width, pairs, "Review uninstall", self._attr(pairs, "accent_alt", bold=True))
            row = self.remove_target or self.selected_row
            package_name = row.identifier if row else "selected package"
            self._add(y + 2, x + 3, f"Uninstall {package_name}", modal_width - 6, self._attr(pairs, "text", bold=True))
            self._add(y + 3, x + 3, "Personal files and application data will not be purged.", modal_width - 6, self._attr(pairs, "warning"))
            for index, option in enumerate(self.modal["options"]):
                attr = self._attr(pairs, "selection" if index == self.modal["selected"] else "surface", bold=index == self.modal["selected"])
                self._fill(y + 5 + index, x + 2, 1, modal_width - 4, attr)
                self._add(y + 5 + index, x + 4, ("▸ " if index == self.modal["selected"] else "  ") + option, modal_width - 8, attr)
            self._add(y + modal_height - 2, x + 3, "↑/↓ choose · Enter confirm · Esc cancel", modal_width - 6, self._attr(pairs, "muted"))
            return
        if kind == "source":
            modal_width = min(width - 4, 76)
            url = str(self.modal.get("url", ""))
            url_lines = _wrap(url, max(1, modal_width - 8))
            modal_height = min(height - 4, max(10, 7 + len(url_lines)))
            x = max(1, (width - modal_width) // 2)
            y = max(1, (height - modal_height) // 2)
            self._box(y, x, modal_height, modal_width, pairs, "Package source", self._attr(pairs, "accent_alt", bold=True))
            self._add(y + 2, x + 3, "URL", modal_width - 6, self._attr(pairs, "accent", bold=True))
            for offset, line in enumerate(url_lines):
                self._add(y + 3 + offset, x + 3, line, modal_width - 6, self._attr(pairs, "text"))
            options_y = y + 4 + len(url_lines)
            options = ("Open in browser", "Copy URL", "Close")
            selected = self.modal.get("selected", 0)
            for index, option in enumerate(options):
                attr = self._attr(pairs, "selection" if index == selected else "surface", bold=index == selected)
                self._fill(options_y + index, x + 2, 1, modal_width - 4, attr)
                self._add(options_y + index, x + 4, ("▸ " if index == selected else "  ") + option, modal_width - 8, attr)
            self._add(y + modal_height - 2, x + 3, "↑/↓ choose · Enter confirm · Esc close", modal_width - 6, self._attr(pairs, "muted"))
            return
        title, raw_lines, scroll = self._modal_content(width, height)
        modal_width = min(width - 4, max(60, int(width * 0.84)))
        modal_height = min(height - 4, max(10, int(height * 0.80)))
        x = max(1, (width - modal_width) // 2)
        y = max(1, (height - modal_height) // 2)
        self._box(y, x, modal_height, modal_width, pairs, title, self._attr(pairs, "accent_alt", bold=True))
        inner_width = modal_width - 6
        lines: List[str] = []
        for raw in raw_lines:
            lines.extend(_wrap(raw, inner_width) if raw else [""])
        visible_height = max(1, modal_height - 4)
        scroll = min(max(0, scroll), max(0, len(lines) - visible_height))
        self.modal["scroll"] = scroll
        for offset, line in enumerate(lines[scroll : scroll + visible_height]):
            attr = self._attr(pairs, "text")
            if line.strip() in {"SEARCH", "NAVIGATION", "INSTALLATION", "METADATA AND REFRESH", "DIAGNOSTICS"}:
                attr = self._attr(pairs, "accent", bold=True)
            self._add(y + 2 + offset, x + 3, line, inner_width, attr)
        self._add(y + modal_height - 2, x + 3, "↑/↓ scroll · Enter/Esc close", inner_width, self._attr(pairs, "muted"))

    def _footer_tokens(self) -> List[str]:
        if self.focus_area == "actions":
            return [
                f"{_display_key(self.config.key('up'))}{_display_key(self.config.key('down'))} action",
                f"{_display_key(self.config.key('accept'))} choose",
                f"{_display_key(self.config.key('select'))} packages",
                f"{_display_key(self.config.key('cancel'))} back",
                f"{_display_key(self.config.key('help'))} help",
            ]
        if self.focus_area == "filters":
            return [
                f"{_display_key(self.config.key('filter_previous'))}{_display_key(self.config.key('filter_next'))} tabs",
                f"{_display_key(self.config.key('select'))} next",
                f"{_display_key(self.config.key('accept'))} packages",
                f"{_display_key(self.config.key('help'))} help",
            ]
        controls = [
            f"{_display_key(self.config.key('up'))}{_display_key(self.config.key('down'))} move",
            f"{_display_key(self.config.key('select'))} tabs",
            f"{_display_key(self.config.key('accept'))} actions",
            f"{_display_key(self.config.key('search'))} search",
            f"{_display_key(self.config.key('queue'))} queue",
            f"{_display_key(self.config.key('sort'))} sort",
        ]
        if self.active_filter != "Updates":
            controls.insert(5, f"{_display_key(self.config.key('versions'))} versions")
        if self._can_add_source():
            controls.append(f"{_display_key(self.config.key('add_source'))} Aurelia source")
        controls.extend(
            [
                f"{_display_key(self.config.key('refresh'))} refresh",
                f"{_display_key(self.config.key('help'))} help",
            ]
        )
        return controls

    def _footer_lines(self, width: int) -> List[str]:
        return _pack_footer_lines(self._footer_tokens(), max(1, width - 4))

    def _footer_height(self, width: int) -> int:
        if time.monotonic() > self.transient_until:
            self.transient_message = ""
        return len(self._footer_lines(width)) + 1 + (1 if self.transient_message else 0)

    def _draw_footer(self, pairs: Dict[str, int], height: int, width: int) -> None:
        footer_lines = self._footer_lines(width)
        transient = ""
        if time.monotonic() <= self.transient_until:
            transient = self.transient_message
        else:
            self.transient_message = ""
        footer_height = len(footer_lines) + 1 + (1 if transient else 0)
        cursor_y = height - footer_height
        if transient:
            self._add(cursor_y, 2, transient, width - 4, self._attr(pairs, "error" if transient.startswith("Error") else "warning"))
            cursor_y += 1
        for line in footer_lines:
            self._add(cursor_y, 2, line, width - 4, self._attr(pairs, "secondary"))
            cursor_y += 1
        queue_text = f"Queue: {len(self.queue_rows)}"
        if self.diagnostics:
            queue_text += f"  ·  Diagnostics: {len(self.diagnostics)} (see ?)"
        status_y = height - 1
        right = f"{_display_key(self.config.key('cancel'))} Quit"
        right_x = max(2, width - len(right) - 2)
        self._add(status_y, 2, queue_text, max(1, right_x - 3), self._attr(pairs, "muted"))
        self._add(status_y, right_x, right, width - right_x - 1, self._attr(pairs, "accent_alt", bold=True))

    def render(self) -> None:
        if self.screen is None:
            return
        screen = self.screen
        height, width = screen.getmaxyx()
        pairs = self._pairs
        self._fill(0, 0, height, width, self._attr(pairs, "base"))
        if width < self.MIN_WIDTH or height < self.MIN_HEIGHT:
            message = f"Terminal too small: need at least {self.MIN_WIDTH}×{self.MIN_HEIGHT}; current {width}×{height}."
            self._add(max(0, height // 2 - 1), 2, message, width - 4, self._attr(pairs, "warning", bold=True))
            self._add(max(0, height // 2 + 1), 2, "Resize the terminal or press Esc to quit.", width - 4, self._attr(pairs, "secondary"))
            screen.refresh()
            return
        y = self._draw_header(pairs, width)
        y = self._draw_search(pairs, y, width)
        y = self._draw_filters(pairs, y, width)
        body_y = y
        body_height = max(1, height - body_y - self._footer_height(width))
        if self.show_details and width >= 106 and body_height >= 12:
            left_width = max(42, int((width - 3) * 0.62))
            right_width = width - left_width - 3
            self._draw_list(pairs, body_y, 1, body_height, left_width)
            self._draw_detail(pairs, body_y, left_width + 2, body_height, right_width)
        elif self.show_details:
            # A stacked split needs room for two readable boxes.  At the
            # smallest supported heights, keep the list inside the body and
            # let Alt-P/details be the explicit way to trade list space for
            # metadata; never draw a fixed seven-row list into the footer.
            if body_height < 14:
                self._draw_list(pairs, body_y, 1, body_height, width - 2)
            else:
                list_height = min(max(7, int(body_height * 0.56)), body_height - 7)
                self._draw_list(pairs, body_y, 1, list_height, width - 2)
                self._draw_detail(pairs, body_y + list_height, 1, body_height - list_height, width - 2)
        else:
            self._draw_list(pairs, body_y, 1, body_height, width - 2)
        self._draw_footer(pairs, height, width)
        if self.modal:
            self._draw_modal(pairs, height, width)
        screen.refresh()

    def run(self, screen: Any) -> None:
        self.screen = screen
        locale.setlocale(locale.LC_ALL, "")
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        screen.keypad(True)
        screen.timeout(100)
        self._pairs = self._init_colors()
        try:
            while self.running:
                try:
                    self._drain_events()
                    self._maybe_submit_query()
                    self.render()
                    self._handle_key(screen.getch())
                except KeyboardInterrupt:
                    raise
                except Exception as error:
                    self._record_error(error)
                    self.modal = {
                        "kind": "message",
                        "title": "Package Manager error",
                        "lines": [str(error).strip() or error.__class__.__name__, "The TUI is still running; press Enter to continue."],
                    }
        finally:
            self.backend.cancel_active()
            self.executor.shutdown(wait=True, cancel_futures=True)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Aurelia Package Manager TUI")
    parser.add_argument("--backend", type=Path, default=None, help="Existing workstation-packages backend")
    parser.add_argument("--query", default="", help="Initial package search query")
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    script_dir = Path(__file__).resolve().parents[2]
    backend = args.backend or script_dir / "workstation-packages"
    try:
        app = PackageManagerTui(backend, args.query)
    except (BackendError, ValueError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    status = 0
    try:
        curses.wrapper(app.run)
    except KeyboardInterrupt:
        status = 130
    finally:
        if app.diagnostics:
            print("Package Manager diagnostics:", file=sys.stderr)
            for line in app.diagnostics:
                print(line, file=sys.stderr)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
