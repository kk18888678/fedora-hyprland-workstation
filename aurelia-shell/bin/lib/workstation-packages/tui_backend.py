#!/usr/bin/env python3
"""Structured, observable bridge from the Package Manager TUI to Bash.

The TUI never assembles package-manager shell commands. Every operation is an
argv call to the existing backend, which remains the single mutation owner.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Sequence, Set, Tuple


class BackendError(RuntimeError):
    def __init__(self, command: Sequence[str], status: int, detail: str) -> None:
        self.command = tuple(command)
        self.status = status
        self.detail = detail.strip() or "The package-manager backend returned no diagnostic."
        super().__init__(self.detail)


@dataclass(frozen=True)
class PackageRow:
    provider: str
    source: str
    identifier: str
    name: str
    version: str
    scope: str
    architecture: str
    installed_size: str
    download_size: str
    reason: str
    release_date: str
    summary: str

    @classmethod
    def from_fields(cls, fields: Sequence[str]) -> Optional["PackageRow"]:
        if len(fields) < 12 or not fields[2]:
            return None
        return cls(
            provider=fields[0],
            source=fields[1],
            identifier=fields[2],
            name=fields[3] if fields[3] != "-" else fields[2],
            version=fields[4] or "unknown",
            scope=fields[5] or "system",
            architecture=fields[6] or "unknown",
            installed_size=fields[7] or "n/a",
            download_size=fields[8] or "n/a",
            reason=fields[9] or "catalog",
            release_date=fields[10] or "n/a",
            summary=fields[11] or "(no summary)",
        )

    @property
    def key(self) -> Tuple[str, str, str, str]:
        return self.provider, self.source, self.identifier, self.scope

    @property
    def provider_label(self) -> str:
        return {"dnf": "DNF", "flatpak": "Flatpak", "aurelia": "Aurelia"}.get(self.provider, self.provider)

    @property
    def icon(self) -> str:
        return infer_package_icon(self.provider, self.identifier, self.name, self.summary)


def infer_package_icon(provider: str, identifier: str, name: str, summary: str) -> str:
    """Choose a small visual hint without requiring remote artwork.

    RPM metadata does not carry application artwork and Flatpak artwork is not
    guaranteed to be available for every remote row. These semantic glyphs are
    therefore derived from searchable metadata and remain useful offline.
    """

    text = f"{identifier} {name} {summary}".lower()
    categories = (
        (("browser", "web", "firefox", "chromium"), "◉"),
        (("terminal", "shell", "console"), "⌁"),
        (("editor", "ide", "code", "vim", "neovim"), "✎"),
        (("office", "spreadsheet", "word processor", "presentation"), "▤"),
        (("music", "audio", "sound", "player"), "♫"),
        (("video", "media", "movie", "film"), "▶"),
        (("image", "photo", "graphics", "paint"), "▧"),
        (("font", "typeface"), "A"),
        (("library", "runtime", "development", "-devel", "-libs"), "λ"),
        (("settings", "system", "utility", "tools"), "⚙"),
    )
    for tokens, glyph in categories:
        if any(token in text for token in tokens):
            return glyph
    return {"dnf": "◆", "flatpak": "●", "aurelia": "✦"}.get(provider, "•")


@dataclass
class CatalogStatus:
    age: str = "unknown"
    freshness: str = "loading"
    schema: str = "unknown"
    sources: str = "unknown"
    total: str = "unknown"
    dnf: str = "unknown"
    flatpak: str = "unknown"
    aurelia: str = "unknown"
    refreshed_at: str = "unknown"

    @property
    def summary(self) -> str:
        if self.freshness == "loading":
            return "Catalog loading…"
        return f"Catalog {self.freshness} · {self.total} packages"


def parse_catalog_rows(output: str) -> List[PackageRow]:
    rows: List[PackageRow] = []
    for line in output.splitlines():
        if not line:
            continue
        row = PackageRow.from_fields(line.split("\t"))
        if row:
            rows.append(row)
    return rows


def parse_catalog_status(output: str) -> CatalogStatus:
    status = CatalogStatus()
    for line in output.splitlines():
        if line.startswith("Catalog:"):
            text = line[len("Catalog:") :].strip()
            parts = [part.strip() for part in text.split("·")]
            if parts:
                status.age = parts[0].removesuffix(" old").strip()
            for part in parts[1:]:
                if part in {"fresh", "stale", "upgrade-needed"}:
                    status.freshness = part
                elif part.startswith("schema "):
                    status.schema = part.removeprefix("schema ")
                elif part.startswith("sources "):
                    status.sources = part.removeprefix("sources ")
        elif line.startswith("Packages:"):
            text = line[len("Packages:") :].strip()
            for part in [part.strip() for part in text.split("·")]:
                if part.endswith(" total"):
                    status.total = part.removesuffix(" total")
                elif part.startswith("DNF "):
                    status.dnf = part[4:]
                elif part.startswith("Flatpak "):
                    status.flatpak = part[8:]
                elif part.startswith("Aurelia "):
                    status.aurelia = part[8:]
        elif line.startswith("refreshed_at "):
            status.refreshed_at = line.split(None, 1)[1].strip()
    return status


def parse_info_fields(output: str) -> Dict[str, str]:
    fields: Dict[str, str] = {}
    for line in output.splitlines():
        if ":" not in line:
            continue
        label, value = line.split(":", 1)
        fields[label.strip()] = value.strip()
    return fields


def installed_keys_from_rows(output: str) -> Set[Tuple[str, str, str, str]]:
    keys: Set[Tuple[str, str, str, str]] = set()
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) < 4 or not all(fields[index] for index in range(4)):
            continue
        keys.add((fields[0], fields[1], fields[2], fields[3]))
    return keys


def installed_versions_from_rows(output: str) -> Dict[Tuple[str, str, str], Set[str]]:
    versions: Dict[Tuple[str, str, str], Set[str]] = {}
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) < 6 or not all(fields[index] for index in (0, 2, 3)):
            continue
        version = fields[5] or "unknown"
        versions.setdefault((fields[0], fields[2], fields[3]), set()).add(version)
    return versions


class PackageBackend:
    def __init__(self, backend_path: Path, diagnostic_sink: Optional[Callable[[str], None]] = None) -> None:
        self.backend_path = backend_path.resolve()
        if not self.backend_path.is_file() or not os.access(self.backend_path, os.X_OK):
            raise ValueError(f"Package-manager backend is not executable: {self.backend_path}")
        self.updates_path = self.backend_path.with_name("workstation-updates")
        self.diagnostic_sink = diagnostic_sink
        self._active_processes: Set[subprocess.Popen] = set()
        self._active_processes_lock = threading.Lock()
        self._cancel_event = threading.Event()

    def _emit_diagnostic(self, text: str) -> None:
        if not text:
            return
        if self.diagnostic_sink:
            self.diagnostic_sink(text)
        else:
            sys.stderr.write(text)
            sys.stderr.flush()

    @staticmethod
    def _terminate_process(process: subprocess.Popen) -> None:
        if process.poll() is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except (OSError, ProcessLookupError):
            try:
                process.terminate()
            except OSError:
                return
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except (OSError, ProcessLookupError):
                try:
                    process.kill()
                except OSError:
                    return
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass

    def cancel_active(self) -> None:
        self._cancel_event.set()
        with self._active_processes_lock:
            processes = list(self._active_processes)
        for process in processes:
            self._terminate_process(process)

    def _run(self, command: Sequence[str], timeout: float) -> str:
        process: Optional[subprocess.Popen] = None
        try:
            process = subprocess.Popen(
                list(command),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                start_new_session=True,
            )
        except OSError as error:
            detail = f"Could not execute package-manager command: {error}"
            self._emit_diagnostic(f"ERROR: {detail}\n")
            raise BackendError(command, 127, detail) from error

        with self._active_processes_lock:
            self._active_processes.add(process)
        stdout = ""
        stderr = ""
        try:
            deadline = time.monotonic() + timeout
            while True:
                if self._cancel_event.is_set():
                    self._terminate_process(process)
                    stdout, stderr = process.communicate()
                    detail = f"Command cancelled: {' '.join(command)}"
                    if stderr.strip():
                        detail += f"\n{stderr.strip()}"
                    self._emit_diagnostic(f"ERROR: {detail}\n")
                    raise BackendError(command, 130, detail)
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    self._terminate_process(process)
                    stdout, stderr = process.communicate()
                    detail = f"Command timed out after {timeout:.0f}s: {' '.join(command)}"
                    if stderr.strip():
                        detail += f"\n{stderr.strip()}"
                    self._emit_diagnostic(f"ERROR: {detail}\n")
                    raise BackendError(command, 124, detail)
                try:
                    stdout, stderr = process.communicate(timeout=min(0.25, remaining))
                    break
                except subprocess.TimeoutExpired:
                    continue
        finally:
            with self._active_processes_lock:
                self._active_processes.discard(process)

        if stderr:
            # Preserve every backend diagnostic through the caller-owned
            # channel. The TUI displays it without corrupting its curses
            # surface and prints it after exit; nothing is discarded.
            self._emit_diagnostic(stderr)
        if process.returncode != 0:
            detail = stderr.strip() or stdout.strip() or f"Command exited with status {process.returncode}."
            raise BackendError(command, process.returncode, detail)
        return stdout

    def bootstrap(self) -> None:
        self._run((str(self.backend_path), "catalog-tui-bootstrap"), timeout=900)

    def refresh(self) -> None:
        self._run((str(self.backend_path), "refresh"), timeout=1800)

    def catalog_status(self) -> CatalogStatus:
        return parse_catalog_status(self._run((str(self.backend_path), "catalog", "status"), timeout=30))

    def catalog_rows(self, query: str) -> List[PackageRow]:
        return parse_catalog_rows(self._run((str(self.backend_path), "catalog-tui-search", "--query", query), timeout=900))

    def package_info(self, row: PackageRow) -> Tuple[str, Dict[str, str]]:
        output = self._run(
            (
                str(self.backend_path),
                "info",
                "--provider",
                row.provider,
                "--source",
                row.source,
                "--id",
                row.identifier,
                "--scope",
                row.scope,
            ),
            timeout=60,
        )
        return output, parse_info_fields(output)

    def status_json(self) -> Dict[str, object]:
        output = self._run((str(self.backend_path), "status", "--json"), timeout=180)
        try:
            value = json.loads(output)
        except json.JSONDecodeError as error:
            raise BackendError((str(self.backend_path), "status", "--json"), 1, f"Package status returned invalid JSON: {error}") from error
        if not isinstance(value, dict):
            raise BackendError((str(self.backend_path), "status", "--json"), 1, "Package status returned a non-object JSON value.")
        return value

    def installed_keys(self) -> Set[Tuple[str, str, str, str]]:
        output = self._run((str(self.backend_path), "catalog-tui-installed"), timeout=300)
        return installed_keys_from_rows(output)

    def installed_snapshot(self) -> Tuple[Set[Tuple[str, str, str, str]], Dict[Tuple[str, str, str], Set[str]]]:
        output = self._run((str(self.backend_path), "catalog-tui-installed"), timeout=300)
        return installed_keys_from_rows(output), installed_versions_from_rows(output)

    def authorize(self, timeout: float = 60.0) -> None:
        """Validate sudo credentials through the controlling terminal only."""

        if hasattr(os, "geteuid") and os.geteuid() == 0:
            return
        command = ("sudo", "-v")
        try:
            # sudo prompts on the real terminal. Never pipe this descriptor or
            # capture its output: that could hide the prompt or expose input.
            with open("/dev/tty", "r+b", buffering=0) as terminal:
                result = subprocess.run(
                    list(command),
                    stdin=terminal,
                    stdout=terminal,
                    stderr=terminal,
                    timeout=timeout,
                    check=False,
                )
        except subprocess.TimeoutExpired as error:
            detail = f"sudo authorization timed out after {timeout:.0f}s."
            self._emit_diagnostic(f"ERROR: {detail}\n")
            raise BackendError(command, 124, detail) from error
        except OSError as error:
            detail = f"Could not authorize package operation through the terminal: {error}"
            self._emit_diagnostic(f"ERROR: {detail}\n")
            raise BackendError(command, 127, detail) from error
        if result.returncode != 0:
            detail = f"sudo authorization failed with status {result.returncode}."
            self._emit_diagnostic(f"ERROR: {detail}\n")
            raise BackendError(command, result.returncode, detail)

    def project_owned(self, row: PackageRow) -> bool:
        output = self._run(
            (
                str(self.backend_path),
                "catalog-tui-ownership",
                "--provider",
                row.provider,
                "--id",
                row.identifier,
            ),
            timeout=30,
        ).strip()
        if output == "project-owned":
            return True
        if output == "user-trackable":
            return False
        raise BackendError(
            (str(self.backend_path), "catalog-tui-ownership"),
            1,
            f"Package ownership returned an invalid state for {row.provider}/{row.identifier}: {output or 'empty result'}",
        )

    def versions_for(self, row: PackageRow) -> List[PackageRow]:
        output = self._run(
            (
                str(self.backend_path),
                "catalog-tui-versions",
                "--provider",
                row.provider,
                "--id",
                row.identifier,
                "--scope",
                row.scope,
            ),
            timeout=120,
        )
        return parse_catalog_rows(output)

    def updates_json(self) -> Dict[str, object]:
        if not self.updates_path.is_file() or not os.access(self.updates_path, os.X_OK):
            raise BackendError((str(self.updates_path), "status", "--json"), 127, "The existing Update Manager backend is unavailable.")
        output = self._run((str(self.updates_path), "status", "--json"), timeout=300)
        try:
            value = json.loads(output)
        except json.JSONDecodeError as error:
            raise BackendError((str(self.updates_path), "status", "--json"), 1, f"Update status returned invalid JSON: {error}") from error
        if not isinstance(value, dict):
            raise BackendError((str(self.updates_path), "status", "--json"), 1, "Update status returned a non-object JSON value.")
        return value

    def install_catalog_row(self, row: PackageRow, track: bool, exact_version: bool = False) -> str:
        command: List[str] = [
            str(self.backend_path),
            "install-catalog-row",
            "--provider",
            row.provider,
            "--source",
            row.source,
            "--id",
            row.identifier,
            "--scope",
            row.scope,
        ]
        if exact_version:
            command.extend(("--version", row.version, "--arch", row.architecture))
        if track:
            command.append("--track")
        command.append("--yes")
        return self._run(command, timeout=3600)

    def remove_catalog_row(self, row: PackageRow, forget: bool = False) -> str:
        command: List[str] = [
            str(self.backend_path),
            "remove-catalog-row",
            "--provider",
            row.provider,
            "--source",
            row.source,
            "--id",
            row.identifier,
            "--scope",
            row.scope,
        ]
        if forget:
            command.append("--forget")
        command.append("--yes")
        return self._run(command, timeout=3600)

    def add_aurelia_source(self, url: str) -> str:
        return self._run(
            (str(self.backend_path), "source", "add", "aurelia", url, "--yes"),
            timeout=900,
        )

    @staticmethod
    def source_url(info: Dict[str, str]) -> str:
        for key in ("URL", "Location / ref"):
            value = info.get(key, "")
            if value.startswith(("https://", "http://")):
                return value
        return ""


def installed_keys_from_status(status: Dict[str, object]) -> Set[Tuple[str, str, str, str]]:
    keys: Set[Tuple[str, str, str, str]] = set()
    for group_name in ("tracked", "unmanaged"):
        group = status.get(group_name, [])
        if not isinstance(group, list):
            continue
        for item in group:
            if not isinstance(item, dict):
                continue
            if group_name == "tracked" and item.get("state") not in {"installed", "installed-origin-unknown", "installed-source-drift"}:
                continue
            try:
                keys.add((str(item["provider"]), str(item["source"]), str(item["identifier"]), str(item["scope"])))
            except KeyError:
                continue
    return keys


def update_ids_from_status(status: Dict[str, object]) -> Tuple[Set[str], Set[str]]:
    dnf: Set[str] = set()
    flatpak: Set[str] = set()
    providers = status.get("providers", [])
    if not isinstance(providers, list):
        return dnf, flatpak
    for provider in providers:
        if not isinstance(provider, dict):
            continue
        provider_id = provider.get("id")
        items = provider.get("items", [])
        if not isinstance(items, list):
            continue
        for item in items:
            if not isinstance(item, dict):
                continue
            identifier = item.get("argument") or item.get("name") or item.get("id")
            if not identifier:
                continue
            if provider_id == "fedora":
                dnf.add(str(identifier))
            elif provider_id == "flatpak":
                flatpak.add(str(identifier))
    return dnf, flatpak
