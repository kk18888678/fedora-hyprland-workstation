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
import locale
import os
import queue
import shutil
import subprocess
import sys
import textwrap
import time
from concurrent.futures import Future, ThreadPoolExecutor
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


class PackageManagerTui:
    MIN_WIDTH = 72
    MIN_HEIGHT = 18
    MAX_QUEUE = 500

    def __init__(self, backend_path: Path, initial_query: str = "") -> None:
        self.backend = PackageBackend(backend_path)
        self.config: TuiConfig = load_config(self.backend.backend_path)
        self.theme: ThemePalette = load_theme(self.backend.backend_path)
        self.initial_query = initial_query

        self.events: "queue.Queue[Event]" = queue.Queue()
        self.executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="package-tui")
        self.screen: Optional[Any] = None
        self.running = True
        self.query = initial_query
        self.query_focus = False
        self.query_changed_at = time.monotonic() if initial_query else 0.0
        self.catalog_generation = 0
        self.info_generation = 0
        self.status_generation = 0
        self.catalog_status_generation = 0
        self.update_generation = 0
        self.operation_generation = 0

        self.rows: List[PackageRow] = []
        self.filtered_rows: List[PackageRow] = []
        self.selected_index = 0
        self.top_index = 0
        self.visible_list_rows = 8
        self.filters: List[str] = ["All", "Installed", "Updates"]
        self.active_filter = "All"
        self.installed_keys: Set[Tuple[str, str, str, str]] = set()
        self.update_dnf_ids: Set[str] = set()
        self.update_flatpak_ids: Set[str] = set()

        self.catalog_status = CatalogStatus()
        self.catalog_loading = True
        self.query_loading = False
        self.status_loading = False
        self.updates_loading = False
        self.info_loading = False
        self.operation_loading = False
        self.show_details = True
        self.detail_scroll = 0
        self.queue_rows: List[PackageRow] = []
        self.info_text = ""
        self.info_fields: Dict[str, str] = {}
        self.messages: List[str] = []
        self.transient_message = ""
        self.transient_until = 0.0
        self.modal: Optional[Dict[str, Any]] = None
        self.alt_prefix = False

        self._submit("bootstrap", self.backend.bootstrap, 1)

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

    def _record_error(self, error: BaseException) -> None:
        detail = str(error).strip() or error.__class__.__name__
        self.messages.append(detail)
        self.messages = self.messages[-8:]
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
        self._submit("info", lambda: self.backend.package_info(row), generation)

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
        return row.key in self.installed_keys

    def _is_update(self, row: PackageRow) -> bool:
        if row.provider == "dnf":
            return row.identifier in self.update_dnf_ids
        if row.provider == "flatpak":
            return row.identifier in self.update_flatpak_ids
        return False

    def _apply_filter(self) -> None:
        active = self.active_filter
        if active == "All":
            rows = self.rows
        elif active == "Installed":
            rows = [row for row in self.rows if self._is_installed(row)]
        elif active == "Updates":
            rows = [row for row in self.rows if self._is_update(row)]
        else:
            rows = [row for row in self.rows if row.provider_label == active]
        self.filtered_rows = rows
        self.selected_index = max(0, min(self.selected_index, max(0, len(rows) - 1)))
        self._keep_selection_visible(self.visible_list_rows)

    def _handle_event(self, event: Event) -> None:
        if event.kind == "bootstrap":
            self.catalog_loading = False
            if event.error:
                self._record_error(event.error)
            self._start_catalog_load()
            self._start_catalog_status_load()
            self._start_status_load()
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
            self.installed_keys = installed_keys_from_status(event.value or {})
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
                self._record_error(event.error)
                return
            self.info_text, self.info_fields = event.value
            return
        if event.kind == "refresh":
            self.operation_loading = False
            if event.error:
                self._record_error(event.error)
                self._start_catalog_load()
                self._start_catalog_status_load()
                self._start_status_load()
                return
            self._set_message("Catalog refreshed", 5.0)
            self._start_catalog_load()
            self._start_catalog_status_load()
            self._start_status_load()
            return
        if event.kind == "install":
            self.operation_loading = False
            if event.error:
                self._record_error(event.error)
                return
            count = len(self.install_targets)
            self.queue_rows = [row for row in self.queue_rows if row not in self.install_targets]
            self._set_message(f"Installed {count} package{'s' if count != 1 else ''}", 8.0)
            self._start_status_load()
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
        visible_rows = visible_rows or self.visible_list_rows
        self.selected_index = max(0, min(len(self.filtered_rows) - 1, self.selected_index + delta))
        self.detail_scroll = 0
        self._keep_selection_visible(visible_rows)
        self._start_info_load(self.selected_row)

    def _set_filter(self, index: int) -> None:
        if not self.filters:
            return
        self.active_filter = self.filters[index % len(self.filters)]
        self.selected_index = 0
        self.top_index = 0
        self.detail_scroll = 0
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

    def _select_all(self) -> None:
        if len(self.filtered_rows) > self.MAX_QUEUE:
            self._set_message(f"Select-all limited to {self.MAX_QUEUE} visible results", 6.0)
        self.queue_rows = list(self.filtered_rows[: self.MAX_QUEUE])
        self._set_message(f"Queued {len(self.queue_rows)} packages")

    def _show_help(self) -> None:
        self.modal = {"kind": "help", "scroll": 0}

    def _show_install(self) -> None:
        row = self.selected_row
        targets = list(self.queue_rows) if self.queue_rows else ([row] if row else [])
        if not targets:
            self._set_message("No package is selected")
            return
        self.install_targets = targets
        label = "Install and track" if len(targets) == 1 else f"Install and track {len(targets)} packages"
        label_untracked = "Install without tracking" if len(targets) == 1 else f"Install {len(targets)} packages without tracking"
        self.modal = {
            "kind": "install",
            "selected": 0,
            "options": [label, label_untracked, "Cancel"],
        }

    def _show_info(self) -> None:
        if not self.selected_row:
            return
        if self.info_loading or not self.info_text:
            self._start_info_load(self.selected_row)
        self.modal = {"kind": "info", "scroll": 0}

    def _open_source(self) -> None:
        row = self.selected_row
        if not row:
            return
        if not self.info_text:
            self._start_info_load(row)
            self._set_message("Loading source metadata…", 5.0)
            return
        url = self.backend.source_url(self.info_fields)
        if not url:
            self.modal = {"kind": "message", "title": "Source unavailable", "lines": ["This provider did not publish a browser source URL.", f"Source: {row.source}"]}
            return
        if not url.startswith("https://"):
            self._set_message("Refused a non-HTTPS source URL", 6.0)
            return
        opener = shutil.which("xdg-open")
        if not opener:
            self.modal = {"kind": "message", "title": "Source URL", "lines": [url, "xdg-open is unavailable; copy the URL manually."]}
            return
        try:
            subprocess.Popen([opener, url], stdin=subprocess.DEVNULL, stdout=None, stderr=None)
            self._set_message("Opened source URL", 4.0)
        except OSError as error:
            self._record_error(error)

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
        self.modal = None
        self.operation_generation += 1
        generation = self.operation_generation
        self.operation_loading = True
        self._set_message(f"Installing {len(targets)} package{'s' if len(targets) != 1 else ''}…", 60.0)

        def install_all() -> str:
            output: List[str] = []
            for row in targets:
                output.append(self.backend.install_catalog_row(row, track))
            return "\n".join(part for part in output if part)

        self._submit("install", install_all, generation)

    def _handle_modal_key(self, ch: int) -> bool:
        if not self.modal:
            return False
        kind = self.modal.get("kind")
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
                if selected == 0:
                    self._begin_install(True)
                elif selected == 1:
                    self._begin_install(False)
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
        if ch in (curses.KEY_BACKSPACE, 127, 8):
            self.query = self.query[:-1]
        elif 0 <= ch <= 255 and curses.ascii.isprint(ch):
            self.query += chr(ch)
        else:
            return True
        self.query_changed_at = time.monotonic()
        return True

    def _handle_key(self, ch: int) -> None:
        if self.modal and self._handle_modal_key(ch):
            return
        if self._handle_search_key(ch):
            return
        if ch == -1:
            return
        if ch == 27:
            # Decode the common ESC + key representation used for Alt-letter
            # bindings without making plain Escape ambiguous.
            self.screen.timeout(30)
            follow = self.screen.getch() if self.screen else -1
            if self.screen:
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
                        return
            self.running = False
            return
        if key_pressed(ch, self.config.key("quit")):
            self.running = False
        elif key_pressed(ch, self.config.key("search")):
            self.query_focus = True
        elif key_pressed(ch, self.config.key("up")) or ch in (ord("k"),):
            self._move_selection(-1)
        elif key_pressed(ch, self.config.key("down")) or ch in (ord("j"),):
            self._move_selection(1)
        elif key_pressed(ch, self.config.key("page_up")):
            self._move_selection(-self.visible_list_rows, self.visible_list_rows)
        elif key_pressed(ch, self.config.key("page_down")):
            self._move_selection(self.visible_list_rows, self.visible_list_rows)
        elif key_pressed(ch, self.config.key("filter_previous")):
            self._cycle_filter(-1)
        elif key_pressed(ch, self.config.key("filter_next")) or ch == 9:
            self._cycle_filter(1)
        elif key_pressed(ch, self.config.key("queue")):
            self._toggle_queue()
        elif key_pressed(ch, self.config.key("select_all")):
            self._select_all()
        elif key_pressed(ch, self.config.key("accept")):
            self._show_install()
        elif key_pressed(ch, self.config.key("refresh")) or ch == ord("r"):
            self._begin_refresh()
        elif key_pressed(ch, self.config.key("help")):
            self._show_help()
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
        create("selection", "text", "selection")
        for name in ("secondary", "muted", "accent", "accent_alt", "success", "warning", "error", "border", "border_active", "dnf", "flatpak", "aurelia"):
            create(name, name, "background")
        create("input", "text", "surface")
        create("detail", "text", "background")
        create("provider_dnf", "dnf", "surface")
        create("provider_flatpak", "flatpak", "surface")
        create("provider_aurelia", "aurelia", "surface")
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
        prompt = "▶ " + self.query
        if not self.query:
            prompt = "▶ Search package IDs, names, descriptions, commands, or capabilities"
        self._add(y + 1, 3, prompt, width - 8, self._attr(pairs, "text", bold=self.query_focus))
        if not self.query_focus:
            self._add(y + 1, max(3, width - 22), f"Press {_display_key(self.config.key('search'))} to focus", 18, self._attr(pairs, "muted", dim=True))
        return y + 4

    def _draw_filters(self, pairs: Dict[str, int], y: int, width: int) -> int:
        x = 2
        for filter_name in self.filters:
            label = f"[ {filter_name} ]" if filter_name == self.active_filter else filter_name
            attr = self._attr(pairs, "accent_alt", bold=True, reverse=filter_name == self.active_filter)
            if filter_name != self.active_filter:
                attr = self._attr(pairs, "secondary")
            if x < width - 20:
                self._add(y, x, label, min(len(label) + 1, width - x - 1), attr)
            x += len(label) + 3
        sort_text = "Sort: relevance"
        self._add(y, max(x + 1, width - len(sort_text) - 3), sort_text, len(sort_text) + 2, self._attr(pairs, "secondary"))
        return y + 2

    def _row_size(self, row: PackageRow) -> str:
        if row.installed_size != "n/a":
            return row.installed_size
        if row.download_size != "n/a":
            return "↓ " + row.download_size
        return "n/a"

    def _provider_attr(self, pairs: Dict[str, int], provider: str, bold: bool = True) -> int:
        return self._attr(pairs, f"provider_{provider}", bold=bold)

    def _draw_list(self, pairs: Dict[str, int], y: int, x: int, height: int, width: int) -> int:
        visible_rows = max(1, (height - 2) // 2)
        self.visible_list_rows = visible_rows
        self.top_index = _selection_window(self.selected_index, len(self.filtered_rows), visible_rows, self.top_index)
        end = min(len(self.filtered_rows), self.top_index + visible_rows)
        title = f"{self.config.label('list')}  {self.top_index + 1 if self.filtered_rows else 0}-{end}/{len(self.filtered_rows)}"
        self._box(y, x, height, width, pairs, title, self._attr(pairs, "accent"))
        inner_width = max(1, width - 4)
        if not self.filtered_rows:
            message = "Loading catalog…" if self.catalog_loading or self.query_loading else "No packages match this search or filter."
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
            self._fill(row_y, x + 1, 2, width - 2, row_attr)
            pointer = "▸" if selected else " "
            queued = "+" if row in self.queue_rows else " "
            installed = "✓" if self._is_installed(row) else " "
            update = "↑" if self._is_update(row) else " "
            name = f"{installed}{update} {row.name}"
            start_x = x + 2
            name_x = start_x + 8
            provider_x = name_x + name_width + 1
            version_x = provider_x + provider_width + 1
            size_x = version_x + version_width + 1
            queue_x = size_x + size_width + 1
            text_attr = self._attr(pairs, "text", bold=selected)
            self._add(row_y, start_x, pointer, 1, self._attr(pairs, "accent", bold=selected))
            self._add(row_y, start_x + 2, f"{index + 1:>3}", 3, text_attr)
            self._add(row_y, start_x + 6, row.icon, 1, self._provider_attr(pairs, row.provider, bold=False))
            self._add(row_y, name_x, name, name_width, text_attr)
            self._add(row_y, provider_x, row.provider_label, provider_width, self._provider_attr(pairs, row.provider))
            self._add(row_y, version_x, row.version, version_width, text_attr)
            self._add(row_y, size_x, self._row_size(row), size_width, text_attr)
            self._add(row_y, queue_x, queued, 1, self._attr(pairs, "success", bold=True))
            summary_attr = self._attr(pairs, "secondary" if not selected else "text")
            self._add(row_y + 1, x + 7, row.summary, inner_width - 5, summary_attr)
        return visible_rows

    def _detail_lines(self, row: PackageRow, width: int) -> List[Tuple[str, int]]:
        pairs = self._pairs
        lines: List[Tuple[str, int]] = []
        fields = [
            ("Version", self.info_fields.get("Version", row.version)),
            ("Architecture", self.info_fields.get("Architecture", row.architecture)),
            ("Installed size", self.info_fields.get("Installed size", row.installed_size)),
            ("Download size", self.info_fields.get("Download size", row.download_size)),
            ("Repository", self.info_fields.get("Source", row.source)),
            ("Release date", self.info_fields.get("Release date", row.release_date)),
        ]
        for label, value in fields:
            lines.append((f"{label:<16} : {value}", self._attr(pairs, "text")))
        lines.append(("", 0))
        description = self.info_fields.get("Description", row.summary)
        for line in _wrap(description, max(1, width - 4)):
            lines.append((line, self._attr(pairs, "secondary")))
        lines.append(("", 0))
        lines.append(("Actions", self._attr(pairs, "accent_alt", bold=True)))
        installed = self._is_installed(row)
        action_lines = [
            ("▸  Reinstall" if installed else "▸  Install", self._attr(pairs, "accent_alt", bold=True)),
            ("   Remove from queue" if row in self.queue_rows else "   Add to queue", self._attr(pairs, "secondary")),
            ("   View source", self._attr(pairs, "secondary")),
            ("   More information", self._attr(pairs, "secondary")),
        ]
        lines.extend(action_lines)
        return lines

    def _draw_detail(self, pairs: Dict[str, int], y: int, x: int, height: int, width: int) -> None:
        row = self.selected_row
        self._box(y, x, height, width, pairs, self.config.label("preview"), self._attr(pairs, "accent"))
        if not row:
            self._add(y + 2, x + 2, "Select a package to inspect metadata and actions.", width - 4, self._attr(pairs, "secondary"))
            return
        inner_width = max(1, width - 4)
        title_attr = self._attr(pairs, "accent_alt", bold=True)
        self._add(y + 1, x + 2, row.name, max(1, width - 18), title_attr)
        badge = f" {row.provider_label} "
        self._add(y + 1, x + width - len(badge) - 3, badge, len(badge) + 1, self._provider_attr(pairs, row.provider))
        detail_lines = self._detail_lines(row, inner_width)
        content_y = y + 2
        available = max(1, height - 3)
        start = min(self.detail_scroll, max(0, len(detail_lines) - available))
        for offset, (line, attr) in enumerate(detail_lines[start : start + available]):
            if content_y + offset >= y + height - 1:
                break
            if line == "":
                continue
            self._add(content_y + offset, x + 2, line, inner_width, attr)
        if self.info_loading:
            self._add(y + height - 2, x + 2, "Loading metadata…", inner_width, self._attr(pairs, "warning"))

    def _help_lines(self) -> List[str]:
        return [
            "SEARCH",
            "  Search IDs, names, summaries, descriptions, and provider capabilities.",
            "  Case, spaces, hyphens, and underscores are normalized by the backend.",
            "  The catalog is cached locally; opening search does not install anything.",
            "",
            "NAVIGATION",
            f"  {_display_key(self.config.key('up'))}/{_display_key(self.config.key('down'))} move   {_display_key(self.config.key('page_up'))}/{_display_key(self.config.key('page_down'))} page",
            f"  {_display_key(self.config.key('filter_previous'))}/{_display_key(self.config.key('filter_next'))} change provider/status filter",
            f"  {_display_key(self.config.key('search'))} focus search   Tab cycle filters   {_display_key(self.config.key('preview_toggle'))} show/hide details",
            "",
            "INSTALLATION",
            f"  {_display_key(self.config.key('accept'))} opens the install review dialog.",
            f"  {_display_key(self.config.key('queue'))} adds or removes the selected package from the queue.",
            f"  {_display_key(self.config.key('select_all'))} queues the visible results (bounded for safety).",
            "  The review dialog explicitly chooses tracking or no tracking.",
            "  All mutations are delegated to the existing package-manager backend.",
            "",
            "METADATA AND REFRESH",
            f"  {_display_key(self.config.key('refresh'))} refreshes metadata only; it never upgrades packages.",
            f"  {_display_key(self.config.key('source'))} opens an HTTPS source URL when the provider publishes one.",
            f"  {_display_key(self.config.key('info'))} opens the complete metadata view.",
            "  DNF release dates and download sizes are shown when available.",
            "  Aurelia shows the GitHub asset size and local binary size when present.",
            "",
            "DIAGNOSTICS",
            "  Backend stderr remains visible in the terminal and errors remain available here.",
            "  A failed refresh keeps the last-known-good catalog available for review.",
        ]

    def _modal_content(self, width: int, height: int) -> Tuple[str, List[str], int]:
        if not self.modal:
            return "", [], 0
        kind = self.modal.get("kind")
        if kind == "help":
            return "Package Manager Help", self._help_lines(), self.modal.get("scroll", 0)
        if kind == "info":
            lines = self.info_text.splitlines() if self.info_text else ["Loading complete package metadata…"]
            return "Complete Package Metadata", lines, self.modal.get("scroll", 0)
        if kind == "message":
            return str(self.modal.get("title", "Message")), list(self.modal.get("lines", [])), 0
        return "", [], 0

    def _draw_modal(self, pairs: Dict[str, int], height: int, width: int) -> None:
        if not self.modal:
            return
        kind = self.modal.get("kind")
        if kind == "install":
            modal_width = min(width - 4, 72)
            modal_height = min(height - 4, 10)
            x = max(1, (width - modal_width) // 2)
            y = max(1, (height - modal_height) // 2)
            self._box(y, x, modal_height, modal_width, pairs, "Review installation", self._attr(pairs, "accent_alt", bold=True))
            targets = self.install_targets
            summary = f"{len(targets)} package{'s' if len(targets) != 1 else ''} selected"
            self._add(y + 2, x + 3, summary, modal_width - 6, self._attr(pairs, "text"))
            for index, option in enumerate(self.modal["options"]):
                attr = self._attr(pairs, "selection" if index == self.modal["selected"] else "surface", bold=index == self.modal["selected"])
                self._fill(y + 4 + index, x + 2, 1, modal_width - 4, attr)
                self._add(y + 4 + index, x + 4, ("▸ " if index == self.modal["selected"] else "  ") + option, modal_width - 8, attr)
            self._add(y + modal_height - 2, x + 3, "↑/↓ choose · Enter confirm · Esc cancel", modal_width - 6, self._attr(pairs, "muted"))
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

    def _draw_footer(self, pairs: Dict[str, int], height: int, width: int) -> None:
        if time.monotonic() > self.transient_until:
            self.transient_message = ""
        if self.transient_message:
            self._add(height - 3, 2, self.transient_message, width - 4, self._attr(pairs, "error" if self.transient_message.startswith("Error") else "warning"))
        left = (
            f"{_display_key(self.config.key('up'))}{_display_key(self.config.key('down'))} move  ·  "
            f"{_display_key(self.config.key('accept'))} install  ·  {_display_key(self.config.key('search'))} search  ·  "
            f"{_display_key(self.config.key('queue'))} queue  ·  {_display_key(self.config.key('refresh'))} refresh  ·  "
            f"{_display_key(self.config.key('help'))} help"
        )
        right = f"{_display_key(self.config.key('cancel'))} Quit"
        right_x = max(2, width - len(right) - 2)
        self._add(height - 2, 2, left, max(1, right_x - 3), self._attr(pairs, "secondary"))
        self._add(height - 2, right_x, right, width - right_x - 1, self._attr(pairs, "accent_alt", bold=True))
        queue_text = f"Queue: {len(self.queue_rows)}"
        self._add(height - 1, 2, queue_text, width - 4, self._attr(pairs, "muted"))

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
        body_height = max(6, height - body_y - 4)
        if self.show_details and width >= 106 and body_height >= 12:
            left_width = max(42, int((width - 3) * 0.62))
            right_width = width - left_width - 3
            self._draw_list(pairs, body_y, 1, body_height, left_width)
            self._draw_detail(pairs, body_y, left_width + 2, body_height, right_width)
        elif self.show_details:
            list_height = max(7, int(body_height * 0.56))
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
        while self.running:
            self._drain_events()
            self._maybe_submit_query()
            self.render()
            self._handle_key(screen.getch())
        self.executor.shutdown(wait=False, cancel_futures=True)


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
    try:
        curses.wrapper(app.run)
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
