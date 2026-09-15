#!/usr/bin/env python3
"""Unit coverage for the dedicated Package Manager TUI primitives."""

from __future__ import annotations

import os
import curses
from dataclasses import replace
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
MODULE_DIR = ROOT / "aurelia-shell" / "bin" / "lib" / "workstation-packages"
sys.path.insert(0, str(MODULE_DIR))

from tui_backend import (  # noqa: E402
    BackendError,
    PackageBackend,
    PackageRow,
    infer_package_icon,
    installed_keys_from_rows,
    installed_versions_from_rows,
    installed_keys_from_status,
    parse_catalog_rows,
    parse_catalog_status,
    parse_info_fields,
    update_ids_from_status,
)
from tui_config import TuiConfig, key_code, key_pressed, load_config  # noqa: E402
from tui_theme import load_theme, nearest_xterm  # noqa: E402
from tui import Event, PackageManagerTui, _contrast_ratio, _pack_footer_lines, _readable_color, _selection_window, _truncate, _wrap  # noqa: E402


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

    def test_complete_installed_inventory_parser_ignores_malformed_rows(self) -> None:
        self.assertEqual(
            installed_keys_from_rows(
                "dnf\tupdates\tcode\tsystem\tcode\t1.0\n"
                "flatpak\tflathub\torg.example.App\tuser\tApp\t1\n"
                "incomplete\trow\n"
            ),
            {("dnf", "updates", "code", "system"), ("flatpak", "flathub", "org.example.App", "user")},
        )
        self.assertEqual(
            installed_versions_from_rows("dnf\tunknown\tcode\tsystem\tcode\t1.0\n"),
            {("dnf", "code", "system"): {"1.0"}},
        )


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
            self.assertEqual(config.key("versions"), "v")
            self.assertEqual(config.key("add_source"), "+")
            self.assertEqual(config.label("title"), "Custom")
        finally:
            temporary.cleanup()

    def test_key_codes_and_text_helpers_are_deterministic(self) -> None:
        self.assertEqual(key_code("ctrl-r"), (18,))
        self.assertTrue(key_pressed(18, "ctrl-r"))
        self.assertEqual(_truncate("abcdef", 4), "abc…")
        self.assertEqual(_wrap("one two three", 7), ["one two", "three"])
        self.assertGreaterEqual(nearest_xterm((255, 0, 0)), 0)

    def test_provider_color_is_adjusted_when_a_light_theme_washes_it_out(self) -> None:
        readable = _readable_color((190, 220, 240), (250, 250, 250), (33, 33, 33))
        self.assertGreaterEqual(_contrast_ratio(readable, (250, 250, 250)), 3.0)

    def test_selection_window_uses_rendered_capacity_instead_of_fixed_eight_rows(self) -> None:
        self.assertEqual(_selection_window(7, 100, 11, 0), 0)
        self.assertEqual(_selection_window(10, 100, 11, 0), 0)
        self.assertEqual(_selection_window(11, 100, 11, 0), 1)
        self.assertEqual(_selection_window(99, 100, 11, 88), 89)

    def test_footer_wraps_complete_shortcut_tokens_without_truncation(self) -> None:
        lines = _pack_footer_lines(["↑↓ move", "Tab tabs", "Enter actions", "/ search", "+ Aurelia source", "Ctrl-R refresh", "? help"], 34)
        self.assertGreater(len(lines), 1)
        self.assertTrue(all(len(line) <= 34 for line in lines))
        self.assertTrue(all("…" not in line for line in lines))
        self.assertIn("+ Aurelia source", lines)

    def test_package_icon_is_derived_from_metadata_and_has_provider_fallback(self) -> None:
        self.assertEqual(infer_package_icon("dnf", "example-browser", "example", "Web browser"), "◉")
        self.assertEqual(infer_package_icon("flatpak", "org.example.App", "App", "Unclassified application"), "●")


class TuiInteractionTests(unittest.TestCase):
    def _row(self) -> PackageRow:
        return PackageRow(
            provider="dnf",
            source="fedora",
            identifier="example-package",
            name="example-package",
            version="1.0-1.fc44",
            scope="system",
            architecture="x86_64",
            installed_size="10.0 MiB",
            download_size="2.0 MiB",
            reason="catalog",
            release_date="2026-09-01",
            summary="Example package",
        )

    def _app(self, installed: bool = False) -> PackageManagerTui:
        app = object.__new__(PackageManagerTui)
        row = self._row()
        app.config = TuiConfig()
        app.rows = [row]
        app.filtered_rows = [row]
        app.version_groups = {}
        app.all_version_groups = {}
        app.all_group_rows = []
        app.grouped_row_count = -1
        app.selected_index = 0
        app.top_index = 0
        app.visible_list_rows = 8
        app.detail_scroll = 0
        app.filters = ["All", "Installed", "Updates", "DNF"]
        app.active_filter = "All"
        app.sort_mode = "relevance"
        app.sort_reverse = False
        app.installed_keys = {row.key} if installed else set()
        app.installed_identity_keys = {(row.provider, row.identifier, row.scope)} if installed else set()
        app.installed_versions = {(row.provider, row.identifier, row.scope): {row.version}} if installed else {}
        app.update_dnf_ids = set()
        app.update_flatpak_ids = set()
        app.project_owned_keys = set()
        app.ownership_checked_keys = {row.key}
        app.ownership_row = None
        app.ownership_loading = False
        app.ownership_error = ""
        app.queue_rows = []
        app.info_text = ""
        app.info_fields = {}
        app.info_loading = False
        app.versions_loading = False
        app.status_installed_keys = set()
        app.discovered_installed_keys = set()
        app.installed_loading = False
        app.focus_area = "list"
        app.action_index = 0
        app.modal = None
        app.query_focus = False
        app.running = True
        app.operation_loading = False
        app.transient_message = ""
        app.transient_until = 0.0
        return app

    def test_tab_moves_to_filters_then_cycles_tabs(self) -> None:
        app = self._app()
        app._cycle_focus()
        self.assertEqual(app.focus_area, "filters")
        app._cycle_focus()
        self.assertEqual(app.active_filter, "Installed")
        self.assertEqual(app.focus_area, "filters")

    def test_search_cursor_allows_in_place_typo_correction(self) -> None:
        app = self._app()
        app.query = "libreofice"
        app.query_cursor = len(app.query)
        app.query_focus = True
        for _ in range(3):
            app._handle_search_key(curses.KEY_LEFT)
        app._handle_search_key(ord("f"))
        self.assertEqual(app.query, "libreoffice")
        app._handle_search_key(curses.KEY_HOME)
        app._handle_search_key(curses.KEY_RIGHT)
        app._handle_search_key(curses.KEY_DC)
        self.assertEqual(app.query, "lbreoffice")
        app._handle_search_key(curses.KEY_BACKSPACE)
        self.assertEqual(app.query, "breoffice")

    def test_sort_key_opens_options_and_applies_selected_order(self) -> None:
        app = self._app()
        app._handle_key(ord("o"))
        self.assertEqual(app.modal["kind"], "sort")
        app._handle_modal_key(curses.KEY_DOWN)
        app._handle_modal_key(10)
        self.assertEqual(app.sort_mode, "name")
        self.assertIsNone(app.modal)

    def test_enter_on_package_moves_to_actions_without_mutating(self) -> None:
        app = self._app()
        app._handle_key(10)
        self.assertEqual(app.focus_area, "actions")
        self.assertIsNone(app.modal)

    def test_help_is_a_compact_dynamic_shortcut_reference(self) -> None:
        app = self._app()
        app.diagnostics = []
        lines = app._help_lines()
        self.assertIn("SHORTCUTS", lines)
        self.assertIn("PACKAGE", lines)
        self.assertTrue(any("Ctrl-R" in line and "Refresh metadata" in line for line in lines))
        self.assertLessEqual(len(lines), 30)

    def test_inline_actions_navigate_to_conditional_uninstall_action(self) -> None:
        app = self._app(installed=True)
        app._handle_key(10)
        app._handle_key(curses.KEY_DOWN)
        app._handle_key(10)
        self.assertEqual(app.modal["kind"], "uninstall")

    def test_detail_pane_contains_one_inline_action_list(self) -> None:
        app = self._app(installed=True)
        app._pairs = {"base": 0, "text": 0}
        with mock.patch("tui.curses.color_pair", return_value=0):
            lines = [line for line, _attr in app._detail_lines(app.selected_row, 60)]
        self.assertEqual(lines.count("Actions"), 1)
        self.assertEqual(sum(line.strip() == "Uninstall" for line in lines), 1)

    def test_updates_view_is_current_only_and_disallows_version_downgrades(self) -> None:
        app = self._app(installed=True)
        current = app.selected_row
        older = replace(current, version="0.9-1.fc44", release_date="2025-09-01")
        app.version_groups[app._group_key(current)] = [current, older]
        app.active_filter = "Updates"
        app.update_dnf_ids = {current.identifier}
        self.assertEqual(app._display_name(current), current.name)
        self.assertNotIn("versions", [action for action, _label in app._action_items()])
        app._show_versions()
        self.assertIsNone(app.modal)
        self.assertIn("use All or DNF", app.transient_message)

    def test_updates_filter_excludes_packages_not_in_installed_inventory(self) -> None:
        app = self._app(installed=False)
        app.active_filter = "Updates"
        app.update_dnf_ids = {app.selected_row.identifier}
        app._apply_filter()
        self.assertEqual(app.filtered_rows, [])

    def test_equal_installed_and_candidate_evrs_are_not_reported_as_updates(self) -> None:
        app = self._app(installed=True)
        app.update_dnf_ids = {app.selected_row.identifier}
        self.assertFalse(app._is_update(app.selected_row))

    def test_detail_versions_wrap_without_losing_the_full_evrs_or_change(self) -> None:
        app = self._app(installed=True)
        app._pairs = {"base": 0, "text": 0}
        installed_version = "1:1.2.3-4.fc44.20260915.longbuild"
        available_version = "1:1.2.4-1.fc44.20260916.longbuild"
        row = replace(app.selected_row, version=available_version)
        app.rows = [row]
        app.filtered_rows = [row]
        app.installed_versions = {app._group_key(row): {installed_version}}
        # Unqualified provider info may expose the installed EVR; the catalog
        # row remains authoritative for the available/update EVR.
        app.info_fields = {"Version": installed_version}
        app.update_dnf_ids = {row.identifier}
        app.active_filter = "Updates"
        with mock.patch("tui.curses.color_pair", return_value=0):
            lines = [line for line, _attr in app._detail_lines(row, 36)]
        rendered = "\n".join(lines)
        compact = "".join(rendered.split())
        self.assertNotIn("…", rendered)
        self.assertIn("Available version", rendered)
        self.assertIn("Change", rendered)
        self.assertIn(installed_version.replace(" ", ""), compact)
        self.assertIn(available_version.replace(" ", ""), compact)

    def test_add_source_is_available_only_from_all_or_aurelia_contexts(self) -> None:
        app = self._app()
        app.active_filter = "DNF"
        app._handle_key(ord("+"))
        self.assertIsNone(app.modal)
        self.assertIn("All or Aurelia", app.transient_message)
        app.active_filter = "Aurelia"
        app._handle_key(ord("+"))
        self.assertEqual(app.modal["kind"], "source-add")

    def test_quit_binding_remains_available_in_each_focus_zone(self) -> None:
        for focus_area in ("list", "filters", "actions"):
            app = self._app()
            app.focus_area = focus_area
            app._handle_key(ord("q"))
            self.assertFalse(app.running, focus_area)

    def test_installed_package_actions_include_dynamic_uninstall(self) -> None:
        installed = self._app(installed=True)
        available = self._app(installed=False)
        self.assertEqual([action for action, _label in installed._action_items()], ["reinstall", "uninstall", "versions", "queue", "source", "info"])
        self.assertEqual([action for action, _label in available._action_items()], ["install", "versions", "queue", "source", "info"])
        installed.action_index = 1
        installed._run_action()
        self.assertEqual(installed.modal["kind"], "uninstall")
        self.assertIn("Uninstall and forget tracking", installed.modal["options"])

    def test_project_owned_update_review_never_offers_manifest_tracking(self) -> None:
        app = self._app(installed=True)
        row = app.selected_row
        app.project_owned_keys = {row.key}
        app.installed_versions = {app._group_key(row): {"0.9-1.fc44"}}
        app.focus_area = "actions"
        app.ownership_row = row
        app._show_install()
        self.assertEqual(app.modal["options"], ["Update (workstation-managed)", "Cancel"])
        self.assertEqual(app.modal["track_options"], [False])
        self.assertIn("user-managed.tsv will not be changed", app.modal["ownership_note"])
        self.assertNotIn("uninstall", [action for action, _label in app._action_items()])

    def test_installed_identity_is_not_lost_when_update_source_differs(self) -> None:
        app = self._app()
        row = app.selected_row
        app.installed_keys = {("dnf", "updates", row.identifier, row.scope)}
        app._rebuild_installed_identity_index()
        self.assertTrue(app._is_installed(row))
        app.update_dnf_ids = set()
        app.installed_versions = {(row.provider, row.identifier, row.scope): {"0.9-1.fc44"}}
        self.assertTrue(app._is_update(row))
        app.update_dnf_ids = {row.identifier}
        self.assertEqual(app._action_items()[0], ("update", "Update"))

    def test_same_package_versions_are_grouped_and_sorted_newest_first(self) -> None:
        app = self._app()
        current = app.selected_row
        older = replace(current, version="0.9-1.fc44", release_date="2025-09-01")
        grouped = app._group_rows([older, current])
        self.assertEqual(len(grouped), 1)
        self.assertEqual(grouped[0].version, current.version)
        self.assertEqual(app._display_name(grouped[0]), "example-package (2)")
        version_lines = app._version_lines(grouped[0])
        self.assertLess(version_lines.index(next(line for line in version_lines if current.version in line)), version_lines.index(next(line for line in version_lines if older.version in line)))
        self.assertEqual(sum(line.startswith("★") for line in version_lines), 1)

    def test_version_selection_opens_exact_install_review_for_a_downgrade(self) -> None:
        app = self._app(installed=True)
        current = app.selected_row
        older = replace(current, version="0.9-1.fc44", release_date="2025-09-01")
        app.version_groups[app._group_key(current)] = [current, older]
        app._show_versions()
        app._handle_modal_key(curses.KEY_DOWN)
        app._handle_modal_key(10)
        self.assertEqual(app.modal["kind"], "install")
        self.assertEqual(app.install_version_override, older.version)
        self.assertIn("Downgrade", app.modal["options"][0])

    def test_version_history_search_filters_before_selection(self) -> None:
        app = self._app()
        current = app.selected_row
        older = replace(current, version="0.9-1.fc44", release_date="2025-09-01")
        app.version_groups[app._group_key(current)] = [current, older]
        app._show_versions()
        app._handle_modal_key(ord("/"))
        for character in "0.9":
            app._handle_modal_key(ord(character))
        app._handle_modal_key(10)
        self.assertFalse(app.modal["search_focus"])
        app._handle_modal_key(10)
        self.assertEqual(app.install_version_override, older.version)

    def test_view_source_is_a_contained_modal_with_copy_choice(self) -> None:
        app = self._app()
        app.info_text = "URL             : https://example.invalid/source"
        app.info_fields = {"URL": "https://example.invalid/source"}
        app.backend = mock.Mock()
        app.backend.source_url.return_value = "https://example.invalid/source"
        app._open_source()
        self.assertEqual(app.modal["kind"], "source")
        with mock.patch.object(app, "_copy_source_url") as copy_url:
            app._handle_modal_key(curses.KEY_DOWN)
            app._handle_modal_key(10)
        copy_url.assert_called_once_with("https://example.invalid/source")

    def test_view_source_refuses_non_https_url_visibly(self) -> None:
        app = self._app()
        app.info_text = "URL             : http://example.invalid/source"
        app.info_fields = {"URL": "http://example.invalid/source"}
        app.backend = mock.Mock()
        app.backend.source_url.return_value = "http://example.invalid/source"
        app._open_source()
        self.assertEqual(app.modal["kind"], "message")
        self.assertIn("Only HTTPS", " ".join(app.modal["lines"]))

    def test_view_source_waits_for_metadata_then_opens_automatically(self) -> None:
        app = self._app()
        row = app.selected_row
        app.info_generation = 1
        app.info_loading = True
        app.pending_source_row = row
        app.backend = mock.Mock()
        app.backend.source_url.return_value = "https://example.invalid/source"
        app._handle_event(Event("info", 1, value=("URL: https://example.invalid/source", {"URL": "https://example.invalid/source"})))
        self.assertEqual(app.modal["kind"], "source")
        self.assertIsNone(app.pending_source_row)

    def test_add_source_modal_keeps_q_as_input_until_escape(self) -> None:
        app = self._app()
        app._show_add_source()
        app._handle_modal_key(ord("q"))
        self.assertEqual(app.modal["value"], "q")
        app._handle_modal_key(27)
        self.assertIsNone(app.modal)

    def test_remove_catalog_row_uses_identity_and_optional_forget(self) -> None:
        backend_path = ROOT / "aurelia-shell" / "bin" / "workstation-packages"
        backend = PackageBackend(backend_path)
        row = self._row()
        process = mock.Mock(returncode=0, pid=12345)
        process.communicate.return_value = ("", "")
        terminal = mock.Mock()
        with mock.patch("builtins.open", return_value=terminal), mock.patch("tui_backend.subprocess.Popen", return_value=process) as popen:
            backend.remove_catalog_row(row, forget=True)
        command = popen.call_args.args[0]
        self.assertIn("remove-catalog-row", command)
        self.assertEqual(command[-2:], ["--forget", "--yes"])

    def test_install_catalog_row_can_request_an_exact_version(self) -> None:
        backend_path = ROOT / "aurelia-shell" / "bin" / "workstation-packages"
        backend = PackageBackend(backend_path)
        row = self._row()
        process = mock.Mock(returncode=0, pid=12345)
        process.communicate.return_value = ("", "")
        terminal = mock.Mock()
        with mock.patch("builtins.open", return_value=terminal), mock.patch("tui_backend.subprocess.Popen", return_value=process) as popen:
            backend.install_catalog_row(row, track=False, exact_version=True)
        command = popen.call_args.args[0]
        self.assertIn("--version", command)
        self.assertIn(row.version, command)
        self.assertIn("--arch", command)

    def test_mutation_backend_passes_the_controlling_terminal_as_stdin(self) -> None:
        backend_path = ROOT / "aurelia-shell" / "bin" / "workstation-packages"
        backend = PackageBackend(backend_path)
        row = self._row()
        process = mock.Mock(returncode=0, pid=12345)
        process.communicate.return_value = ("", "")
        terminal = mock.Mock()
        with mock.patch("builtins.open", return_value=terminal) as open_file, mock.patch("tui_backend.subprocess.Popen", return_value=process) as popen:
            backend.install_catalog_row(row, track=False)
        open_file.assert_called_once_with("/dev/tty", "rb", buffering=0)
        self.assertIs(popen.call_args.kwargs["stdin"], terminal)
        self.assertEqual(popen.call_args.kwargs["env"]["WORKSTATION_PACKAGE_TTY_AUTHORIZED"], "yes")
        self.assertFalse(popen.call_args.kwargs["start_new_session"])
        self.assertEqual(popen.call_args.kwargs["process_group"], 0)
        terminal.close.assert_called_once()

    def test_versions_for_uses_the_dedicated_full_history_backend_command(self) -> None:
        backend_path = ROOT / "aurelia-shell" / "bin" / "workstation-packages"
        backend = PackageBackend(backend_path)
        row = self._row()
        process = mock.Mock(returncode=0, pid=12345)
        process.communicate.return_value = ("dnf\tfedora\texample-package\texample-package\t1.0\tsystem\tx86_64\t1 MiB\t1 MiB\tcatalog\t2026-09-01\tExample\n", "")
        with mock.patch("tui_backend.subprocess.Popen", return_value=process) as popen:
            versions = backend.versions_for(row)
        self.assertEqual(len(versions), 1)
        self.assertEqual(versions[0].version, "1.0")
        self.assertEqual(popen.call_args.args[0][-6:], ["--provider", "dnf", "--id", row.identifier, "--scope", "system"])

    def test_project_owned_query_uses_the_read_only_backend_boundary(self) -> None:
        backend_path = ROOT / "aurelia-shell" / "bin" / "workstation-packages"
        backend = PackageBackend(backend_path)
        row = self._row()
        process = mock.Mock(returncode=0, pid=12345)
        process.communicate.return_value = ("project-owned\n", "")
        with mock.patch("tui_backend.subprocess.Popen", return_value=process) as popen:
            self.assertTrue(backend.project_owned(row))
        self.assertEqual(
            popen.call_args.args[0][-5:],
            ["catalog-tui-ownership", "--provider", "dnf", "--id", row.identifier],
        )

    def test_sudo_authorization_uses_the_controlling_terminal_without_capture(self) -> None:
        backend_path = ROOT / "aurelia-shell" / "bin" / "workstation-packages"
        backend = PackageBackend(backend_path)
        terminal = mock.MagicMock()
        terminal.__enter__.return_value = terminal
        completed = mock.Mock(returncode=0)
        with mock.patch("tui_backend.os.geteuid", return_value=1000), mock.patch("builtins.open", return_value=terminal) as open_file, mock.patch("tui_backend.subprocess.run", return_value=completed) as run:
            backend.authorize()
        open_file.assert_called_once_with("/dev/tty", "r+b", buffering=0)
        self.assertEqual(run.call_args.args[0], ["sudo", "-v"])
        self.assertIs(run.call_args.kwargs["stdin"], terminal)
        self.assertIs(run.call_args.kwargs["stdout"], terminal)
        self.assertIs(run.call_args.kwargs["stderr"], terminal)

    def test_tui_authorization_failure_keeps_the_review_open(self) -> None:
        app = self._app(installed=True)
        app.diagnostics = []
        app.messages = []
        app.backend = mock.Mock()
        app.backend.authorize.side_effect = RuntimeError("unexpected terminal failure")
        app.modal = {"kind": "install", "options": ["Update", "Cancel"], "selected": 0}
        self.assertFalse(app._authorize_for_mutation())
        self.assertTrue(app.running)
        self.assertEqual(app.modal["kind"], "install")
        self.assertIn("unexpected terminal failure", app.transient_message)

    def test_project_owned_review_keeps_tracking_disabled(self) -> None:
        app = self._app(installed=True)
        row = app.selected_row
        app.project_owned_keys = {row.key}
        app.installed_versions = {app._group_key(row): {"0.9-1.fc44"}}
        app._show_install()
        self.assertEqual(app.modal["track_options"], [False])

    def test_source_launch_restores_the_curses_program_mode(self) -> None:
        app = self._app()
        screen = mock.Mock()
        app.screen = screen
        completed = mock.Mock(returncode=0, stdout="", stderr="")
        def which(name: str) -> str | None:
            return "/usr/bin/xdg-open" if name == "xdg-open" else None

        with mock.patch("tui.shutil.which", side_effect=which), mock.patch("tui.subprocess.run", return_value=completed) as run, mock.patch("tui.curses.def_prog_mode") as def_prog_mode, mock.patch("tui.curses.endwin") as endwin, mock.patch("tui.curses.reset_prog_mode") as reset_prog_mode:
            app._launch_source_url("https://example.invalid/source")
        run.assert_called_once()
        def_prog_mode.assert_called_once()
        endwin.assert_called_once()
        reset_prog_mode.assert_called_once()
        screen.clear.assert_called_once()
        self.assertIsNone(app.modal)

    def test_source_launch_survives_curses_suspend_failure(self) -> None:
        app = self._app()
        app.diagnostics = []
        app.messages = []
        screen = mock.Mock()
        app.screen = screen
        completed = mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch("tui.shutil.which", return_value="/usr/bin/xdg-open"), mock.patch("tui.subprocess.run", return_value=completed), mock.patch("tui.curses.def_prog_mode", side_effect=curses.error("terminal is not initialized")) as def_prog_mode, mock.patch("tui.curses.endwin") as endwin, mock.patch("tui.curses.reset_prog_mode") as reset_prog_mode:
            app._launch_source_url("https://example.invalid/source")
        self.assertTrue(app.running)
        self.assertTrue(any("terminal is not initialized" in line for line in app.diagnostics))
        def_prog_mode.assert_called_once()
        endwin.assert_not_called()
        reset_prog_mode.assert_not_called()

    def test_source_launch_survives_curses_restore_failure(self) -> None:
        app = self._app()
        app.diagnostics = []
        app.messages = []
        screen = mock.Mock()
        app.screen = screen
        completed = mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch("tui.shutil.which", return_value="/usr/bin/xdg-open"), mock.patch("tui.subprocess.run", return_value=completed), mock.patch("tui.curses.def_prog_mode"), mock.patch("tui.curses.endwin"), mock.patch("tui.curses.reset_prog_mode", side_effect=curses.error("terminal restore failed")) as reset_prog_mode:
            app._launch_source_url("https://example.invalid/source")
        self.assertTrue(app.running)
        self.assertTrue(any("terminal restore failed" in line for line in app.diagnostics))
        reset_prog_mode.assert_called_once()

    def test_source_launch_uses_gio_when_xdg_open_is_unavailable(self) -> None:
        app = self._app()
        completed = mock.Mock(returncode=0, stdout="", stderr="")

        def which(name: str) -> str | None:
            return "/usr/bin/gio" if name == "gio" else None

        with mock.patch("tui.shutil.which", side_effect=which), mock.patch("tui.subprocess.run", return_value=completed) as run:
            app._launch_source_url("https://example.invalid/source")
        self.assertEqual(run.call_args.args[0], ["/usr/bin/gio", "open", "https://example.invalid/source"])

    def test_source_launch_retries_xdg_after_gio_reports_an_error(self) -> None:
        app = self._app()
        app.diagnostics = []
        app.messages = []
        gio_failure = mock.Mock(returncode=1, stdout="", stderr="gio: no handler\n")
        xdg_success = mock.Mock(returncode=0, stdout="", stderr="")

        def which(name: str) -> str | None:
            return {"gio": "/usr/bin/gio", "xdg-open": "/usr/bin/xdg-open"}.get(name)

        with mock.patch("tui.shutil.which", side_effect=which), mock.patch("tui.subprocess.run", side_effect=[gio_failure, xdg_success]) as run:
            app._launch_source_url("https://example.invalid/source")
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[1].args[0], ["/usr/bin/xdg-open", "https://example.invalid/source"])
        self.assertIsNone(app.modal)
        self.assertTrue(any("gio: no handler" in line for line in app.diagnostics))

    def test_source_launch_keeps_both_launcher_errors_in_the_tui(self) -> None:
        app = self._app()
        app.diagnostics = []
        app.messages = []
        gio_failure = mock.Mock(returncode=1, stdout="", stderr="gio: no handler\n")
        xdg_failure = mock.Mock(returncode=3, stdout="", stderr="xdg-open: no method\n")

        def which(name: str) -> str | None:
            return {"gio": "/usr/bin/gio", "xdg-open": "/usr/bin/xdg-open"}.get(name)

        with mock.patch("tui.shutil.which", side_effect=which), mock.patch("tui.subprocess.run", side_effect=[gio_failure, xdg_failure]):
            app._launch_source_url("https://example.invalid/source")
        self.assertTrue(app.running)
        self.assertEqual(app.modal["kind"], "message")
        self.assertIn("gio: no handler", " ".join(app.modal["lines"]))
        self.assertIn("xdg-open: no method", " ".join(app.modal["lines"]))

    def test_source_launch_uses_the_registered_https_desktop_entry_as_final_fallback(self) -> None:
        app = self._app()
        app.diagnostics = []
        app.messages = []
        gio_failure = mock.Mock(returncode=1, stdout="", stderr="gio: no handler\n")
        xdg_failure = mock.Mock(returncode=3, stdout="", stderr="xdg-open: no method\n")
        mime_result = mock.Mock(returncode=0, stdout="chromium-browser.desktop\n", stderr="")
        gtk_success = mock.Mock(returncode=0, stdout="", stderr="")

        def which(name: str) -> str | None:
            return {
                "gio": "/usr/bin/gio",
                "xdg-open": "/usr/bin/xdg-open",
                "gtk-launch": "/usr/bin/gtk-launch",
                "xdg-mime": "/usr/bin/xdg-mime",
            }.get(name)

        with mock.patch("tui.shutil.which", side_effect=which), mock.patch(
            "tui.subprocess.run", side_effect=[gio_failure, xdg_failure, mime_result, gtk_success]
        ) as run:
            app._launch_source_url("https://example.invalid/source")
        self.assertEqual(run.call_count, 4)
        self.assertEqual(run.call_args_list[-1].args[0], ["/usr/bin/gtk-launch", "chromium-browser.desktop", "https://example.invalid/source"])
        self.assertIsNone(app.modal)
        self.assertTrue(any("gio: no handler" in line for line in app.diagnostics))

    def test_backend_cancellation_terminates_only_registered_children(self) -> None:
        backend = PackageBackend(ROOT / "aurelia-shell" / "bin" / "workstation-packages")
        process = mock.Mock(pid=12345)
        backend._active_processes.add(process)
        with mock.patch.object(backend, "_terminate_process") as terminate:
            backend.cancel_active()
        self.assertTrue(backend._cancel_event.is_set())
        terminate.assert_called_once_with(process)

    def test_backend_failure_preserves_stdout_and_stderr_diagnostics(self) -> None:
        backend = PackageBackend(ROOT / "aurelia-shell" / "bin" / "workstation-packages")
        process = mock.Mock(returncode=1, pid=12345)
        process.communicate.return_value = (
            "Updating and loading repositories:\n",
            "Failed to download metadata for repo 'broken': network unavailable\n",
        )
        with mock.patch("tui_backend.subprocess.Popen", return_value=process):
            with self.assertRaises(BackendError) as raised:
                backend._run(("dnf5", "upgrade"), timeout=5)
        self.assertIn("Updating and loading repositories:", raised.exception.detail)
        self.assertIn("Failed to download metadata for repo 'broken'", raised.exception.detail)

    def test_operation_failure_opens_the_complete_provider_diagnostic(self) -> None:
        app = self._app()
        app.diagnostics = []
        app.messages = []
        error = BackendError(
            ("dnf5", "upgrade", "chatgpt"),
            1,
            "Updating and loading repositories:\nFailed to download metadata for repo 'broken'.",
        )
        app._handle_event(Event("install", 1, error=error))
        self.assertEqual(app.modal["kind"], "message")
        self.assertEqual(app.modal["title"], "Package operation failed")
        self.assertIn("Failed to download metadata for repo 'broken'.", app.modal["lines"])
        self.assertIn("full diagnostics are open", app.transient_message)

    def test_add_aurelia_source_uses_structured_backend_argv(self) -> None:
        backend_path = ROOT / "aurelia-shell" / "bin" / "workstation-packages"
        backend = PackageBackend(backend_path)
        process = mock.Mock(returncode=0, pid=12345)
        process.communicate.return_value = ("", "")
        with mock.patch("tui_backend.subprocess.Popen", return_value=process) as popen:
            backend.add_aurelia_source("https://github.com/example/tool")
        self.assertEqual(
            popen.call_args.args[0][-3:],
            ["aurelia", "https://github.com/example/tool", "--yes"],
        )


if __name__ == "__main__":
    unittest.main()
