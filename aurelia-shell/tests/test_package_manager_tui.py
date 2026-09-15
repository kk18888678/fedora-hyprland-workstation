#!/usr/bin/env python3
"""Unit coverage for the dedicated Package Manager TUI primitives."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
MODULE_DIR = ROOT / "aurelia-shell" / "bin" / "lib" / "workstation-packages"
sys.path.insert(0, str(MODULE_DIR))

from tui_backend import (  # noqa: E402
    PackageRow,
    infer_package_icon,
    installed_keys_from_status,
    parse_catalog_rows,
    parse_catalog_status,
    parse_info_fields,
    update_ids_from_status,
)
from tui_config import key_code, key_pressed, load_config  # noqa: E402
from tui_theme import load_theme, nearest_xterm  # noqa: E402
from tui import _selection_window, _truncate, _wrap  # noqa: E402


class PackageRowTests(unittest.TestCase):
    def test_display_row_preserves_provider_identity_and_normalizes_missing_values(self) -> None:
        rows = parse_catalog_rows(
            "dnf\tfedora\tcode\t-\t1.0\tsystem\tx86_64\t60.0 MiB\t20.0 MiB\tLATEST\t2026-09-01\tCode editor\n"
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].name, "code")
        self.assertEqual(rows[0].key, ("dnf", "fedora", "code", "system"))
        self.assertEqual(rows[0].provider_label, "DNF")

    def test_invalid_or_short_rows_are_not_install_candidates(self) -> None:
        self.assertEqual(parse_catalog_rows("\nnot-a-row\ttoo-short\n"), [])
        self.assertIsNone(PackageRow.from_fields(["dnf", "fedora", ""]))

    def test_status_parser_reads_human_summary_and_counts(self) -> None:
        status = parse_catalog_status(
            "Catalog: 9h 33m old · fresh · schema 6 · sources healthy\n"
            "Packages: 97785 total · DNF 93798 · Flatpak 3986 · Aurelia 1\n"
            "refreshed_at           2026-09-15T16:34:10+05:30\n"
        )
        self.assertEqual(status.age, "9h 33m")
        self.assertEqual(status.freshness, "fresh")
        self.assertEqual(status.schema, "6")
        self.assertEqual(status.total, "97785")
        self.assertEqual(status.dnf, "93798")
        self.assertEqual(status.flatpak, "3986")
        self.assertEqual(status.aurelia, "1")

    def test_status_parser_tolerates_unavailable_catalog(self) -> None:
        status = parse_catalog_status("Catalog unavailable\n")
        self.assertEqual(status.freshness, "loading")
        self.assertEqual(status.total, "unknown")

    def test_info_parser_keeps_colons_inside_values(self) -> None:
        fields = parse_info_fields("URL             : https://example.invalid/a:b\nSummary         : A: useful package\n")
        self.assertEqual(fields["URL"], "https://example.invalid/a:b")
        self.assertEqual(fields["Summary"], "A: useful package")

    def test_installed_and_update_sets_are_provider_aware(self) -> None:
        status = {
            "tracked": [
                {"provider": "dnf", "source": "fedora", "identifier": "code", "scope": "system", "state": "installed"},
                {"provider": "flatpak", "source": "flathub", "identifier": "org.example.App", "scope": "user", "state": "missing"},
            ],
            "unmanaged": [
                {"provider": "dnf", "source": "updates", "identifier": "v4l-utils", "scope": "system"}
            ],
        }
        self.assertEqual(
            installed_keys_from_status(status),
            {("dnf", "fedora", "code", "system"), ("dnf", "updates", "v4l-utils", "system")},
        )
        updates = {
            "providers": [
                {"id": "fedora", "items": [{"argument": "code"}]},
                {"id": "flatpak", "items": [{"argument": "org.example.App"}]},
            ]
        }
        self.assertEqual(update_ids_from_status(updates), ({"code"}, {"org.example.App"}))


class ThemeAndConfigTests(unittest.TestCase):
    def _fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path, Path]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        aurelia_root = root / "aurelia-shell"
        backend = aurelia_root / "bin" / "workstation-packages"
        backend.parent.mkdir(parents=True)
        backend.write_text("#!/bin/sh\n", encoding="utf-8")
        backend.chmod(0o755)
        (aurelia_root / "theme").mkdir()
        (aurelia_root / "theme.conf").write_text(
            "background=#101820\ntext=#e8f0f4\naccent=#45c6df\naccentAlt=#a985ff\nsuccess=#35e19d\n",
            encoding="utf-8",
        )
        (aurelia_root / "theme" / "shell.toml").write_text(
            "[launcher]\nbackground = #101820\nselected-text = #45c6df\n",
            encoding="utf-8",
        )
        return temporary, root, backend

    def test_theme_uses_active_aurelia_state_and_shell_tokens(self) -> None:
        temporary, root, backend = self._fixture()
        try:
            home = root / "home"
            active = home / ".local" / "state" / "aurelia" / "current"
            active.mkdir(parents=True)
            (active / "theme.conf").write_text("background=#202030\naccent=#7dd3fc\n", encoding="utf-8")
            (active / "shell.toml").write_text("[launcher]\nselected-text=#c4a7e7\n", encoding="utf-8")
            with mock.patch.dict(os.environ, {"HOME": str(home), "XDG_STATE_HOME": str(home / ".local" / "state")}, clear=False):
                theme = load_theme(backend)
            self.assertEqual(Path(theme.source), active / "theme.conf")
            self.assertEqual(theme.color("background"), (32, 32, 48))
            self.assertEqual(theme.color("accent"), (196, 167, 231))
        finally:
            temporary.cleanup()

    def test_theme_falls_back_to_shipped_data_when_no_user_theme_exists(self) -> None:
        temporary, root, backend = self._fixture()
        try:
            with mock.patch.dict(
                os.environ,
                {
                    "HOME": str(root / "empty-home"),
                    "XDG_CONFIG_HOME": str(root / "empty-home" / ".config"),
                    "XDG_STATE_HOME": str(root / "empty-home" / ".local" / "state"),
                },
                clear=False,
            ):
                theme = load_theme(backend)
            self.assertEqual(Path(theme.source), root / "aurelia-shell" / "theme.conf")
            self.assertEqual(theme.color("background"), (16, 24, 32))
        finally:
            temporary.cleanup()

    def test_theme_rejects_symlinked_user_theme_and_keeps_safe_fallback(self) -> None:
        temporary, root, backend = self._fixture()
        try:
            target = root / "outside.conf"
            target.write_text("background=#ffffff\n", encoding="utf-8")
            link = root / "linked.conf"
            link.symlink_to(target)
            with mock.patch.dict(os.environ, {"AURELIA_THEME_CONF": str(link), "HOME": str(root / "empty-home")}, clear=False):
                theme = load_theme(backend)
            self.assertNotEqual(theme.source, str(link))
        finally:
            temporary.cleanup()

    def test_config_reads_user_override_without_executing_content(self) -> None:
        temporary, root, backend = self._fixture()
        try:
            user_config = root / "user.conf"
            user_config.write_text("key_queue=z\ntui_title=Custom\nkey_search=/\n", encoding="utf-8")
            with mock.patch.dict(os.environ, {"HOME": str(root / "home"), "WORKSTATION_PACKAGE_USER_CONFIG": str(user_config)}, clear=False):
                config = load_config(backend)
            self.assertEqual(config.key("queue"), "z")
            self.assertEqual(config.label("title"), "Custom")
        finally:
            temporary.cleanup()

    def test_key_codes_and_text_helpers_are_deterministic(self) -> None:
        self.assertEqual(key_code("ctrl-r"), (18,))
        self.assertTrue(key_pressed(18, "ctrl-r"))
        self.assertEqual(_truncate("abcdef", 4), "abc…")
        self.assertEqual(_wrap("one two three", 7), ["one two", "three"])
        self.assertGreaterEqual(nearest_xterm((255, 0, 0)), 0)

    def test_selection_window_uses_rendered_capacity_instead_of_fixed_eight_rows(self) -> None:
        self.assertEqual(_selection_window(7, 100, 11, 0), 0)
        self.assertEqual(_selection_window(10, 100, 11, 0), 0)
        self.assertEqual(_selection_window(11, 100, 11, 0), 1)
        self.assertEqual(_selection_window(99, 100, 11, 88), 89)

    def test_package_icon_is_derived_from_metadata_and_has_provider_fallback(self) -> None:
        self.assertEqual(infer_package_icon("dnf", "example-browser", "example", "Web browser"), "◉")
        self.assertEqual(infer_package_icon("flatpak", "org.example.App", "App", "Unclassified application"), "●")


if __name__ == "__main__":
    unittest.main()
