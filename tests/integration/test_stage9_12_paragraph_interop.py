"""Bounded RTF/RTFD paragraph geometry and list-table interoperability tests."""

from __future__ import annotations

from contextlib import closing
import importlib.util
from pathlib import Path
import re
import sqlite3
import tempfile
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def _load(name: str):
    """Load shipping tools without running a command-line entry point."""
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rtf_export = _load("stickies_rtf")
rtf_import = _load("stickies_rtf_import")
rtfd = _load("stickies_rtfd")
exchange = _load("stickies_exchange")


class RtfParagraphCompatibilityTests(unittest.TestCase):
    """Protect import/export from losing bounded paragraph and tab information."""

    def test_indents_and_right_center_tabs_are_preserved(self) -> None:
        """Map signed RTF twips into canonical existing interval formatting."""
        source = (
            br"{\rtf1\ansi\pard\li720\ri360\fi-240\tqc\tx1440"
            br"\tqr\tx2880 First\tab Item\par\pard Second}"
        )
        text, formatting = rtf_import.RtfReader().parse(source)
        self.assertEqual(text, "First\tItem\nSecond")
        self.assertIn("0:10:para-li_720\n", formatting)
        self.assertIn("0:10:para-ri_360\n", formatting)
        self.assertIn("0:10:para-fi_-240\n", formatting)
        self.assertIn("0:10:para-tabs_1440C_2880R\n", formatting)
        self.assertNotIn("10:16:para-", formatting)

    def test_reset_does_not_leak_properties_to_following_paragraph(self) -> None:
        """RTF paragraph resets must not leave old indentation or tab stops."""
        text, formatting = rtf_import.RtfReader().parse(
            br"{\rtf1\li720\tx1440 One\par\pard Two\par\li360 Three}"
        )
        self.assertEqual(text, "One\nTwo\nThree")
        self.assertIn("0:3:para-li_720", formatting)
        self.assertIn("0:3:para-tabs_1440L", formatting)
        self.assertIn("8:13:para-li_360", formatting)
        self.assertNotIn("4:7:para-li_", formatting)

    def test_rtf_export_import_preserves_paragraph_geometry(self) -> None:
        """A supported styled body survives exporter and importer conversion."""
        original = "First\tValue\nPlain"
        styles = (
            "0:11:para-li_720\n0:11:para-ri_360\n"
            "0:11:para-fi_-240\n0:11:para-tabs_1440C_2880R\n"
        )
        exported = rtf_export.make_rtf("Heading", original, styles)
        self.assertIn(br"\li720", exported)
        self.assertIn(br"\fi-240", exported)
        self.assertIn(br"\tqc \tx1440", exported)
        self.assertIn(br"\tqr \tx2880", exported)
        decoded, formatting = rtf_import.RtfReader().parse(exported)
        start = decoded.index("First\tValue")
        for token in ("para-li_720", "para-ri_360", "para-fi_-240",
                      "para-tabs_1440C_2880R"):
            self.assertIn(f":{token}\n", formatting)
            self.assertRegex(formatting, rf"(?m)^{start}:[0-9]+:{re.escape(token)}$")

    def test_all_supported_tab_alignments(self) -> None:
        """Retain the four standard tab alignments in strictly ordered stops."""
        text, spans = rtf_import.RtfReader().parse(
            br"{\rtf1\tql\tx720\tqc\tx1440\tqr\tx2160\tqdec\tx2880 A\tab B}"
        )
        self.assertEqual(text, "A\tB")
        self.assertIn("para-tabs_720L_1440C_2160R_2880D", spans)

    def test_invalid_large_indent_is_rejected(self) -> None:
        """Reject out-of-contract indentation instead of overflowing GTK pixels."""
        with self.assertRaisesRegex(rtf_import.RtfImportError, "indentation"):
            rtf_import.RtfReader().parse(br"{\rtf1\li999999 A}")

    def test_invalid_tab_stop_list_is_rejected(self) -> None:
        """Reject duplicate, oversized, or excessively many tab stops."""
        for raw in (
            br"\tx720\tx720",
            br"\tx7201",
            b"".join(fr"\tx{index * 100} ".encode() for index in range(1, 14)),
        ):
            with self.subTest(raw=raw), self.assertRaisesRegex(
                rtf_import.RtfImportError, "tab stops"
            ):
                rtf_import.RtfReader().parse(b"{\\rtf1 " + raw + b" Text}")

    def test_invalid_export_tokens_are_rejected(self) -> None:
        """Never emit out-of-bounds or CSS-like paragraph tokens to RTF."""
        for style in ("para-li_-20", "para-fi_9999", "para-tabs_0L",
                      "para-tabs_1440X", "para-tabs_720L_480R",
                      "para-tabs_1440L;}"):
            with self.subTest(style=style), self.assertRaises(rtf_export.RtfExportError):
                rtf_export.make_rtf("T", "Text", f"0:4:{style}\n")

    def test_legacy_rtf_text_unchanged_without_paragraph_metadata(self) -> None:
        """Ordinary old RTF notes do not gain extra persistent style tokens."""
        text, formatting = rtf_import.RtfReader().parse(
            br"{\rtf1\ansi\pard\b Hello\b0\par World}"
        )
        self.assertEqual(text, "Hello\nWorld")
        self.assertIn("bold", formatting)
        self.assertNotIn("para-", formatting)

    def test_listtable_declares_bullet_kind_and_level(self) -> None:
        """Use list table declarations rather than inventing marker glyphs."""
        rtf = (
            br"{\rtf1\ansi"
            br"{\*\listtable{\list\listtemplateid1"
            br"{\listlevel\levelnfc23\leveljc0}"
            br"{\listlevel\levelnfc0\leveljc0}\listid42}}"
            br"{\*\listoverridetable{\listoverride\listid42\listoverridecount0\ls5}}"
            br"\pard\ls5\ilvl0 Bullet\par"
            br"\pard\ls5\ilvl1 Numbered\par}"
        )
        text, formatting = rtf_import.RtfReader().parse(rtf)
        self.assertEqual(text, "Bullet\nNumbered\n")
        self.assertIn("0:6:list-bullet", formatting)
        self.assertIn("0:6:list-depth-1", formatting)
        self.assertIn("7:15:list-numbered", formatting)
        self.assertIn("7:15:list-depth-2", formatting)

    def test_unknown_list_reference_does_not_invent_a_kind(self) -> None:
        """Unresolved list IDs may carry depth but not a fabricated list style."""
        text, formatting = rtf_import.RtfReader().parse(
            br"{\rtf1\pard\ls7\ilvl2 Unknown}"
        )
        self.assertEqual(text, "Unknown")
        self.assertIn("list-depth-3", formatting)
        self.assertNotIn("list-bullet", formatting)

    def test_malformed_list_metadata_stays_non_executable(self) -> None:
        """An unfamiliar list table must never become visible executable text."""
        text, formatting = rtf_import.RtfReader().parse(
            br"{\rtf1{\*\listtable{\list\listtemplateid0"
            br"{\listlevel\levelnfc255}\listid123}}"
            br"\pard\ls77 Safe}"
        )
        self.assertEqual(text, "Safe")
        self.assertNotIn("list-bullet", formatting)


class RtfdParagraphCompatibilityTests(unittest.TestCase):
    """Preserve paragraph geometry in standard TXT.rtf and native metadata."""

    def setUp(self) -> None:
        """Create one isolated RTFD package directory per interoperability test."""
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.note_id = str(uuid.uuid4())

    def test_external_rtfd_retains_paragraph_styles(self) -> None:
        """Import external TXT.rtf with paragraph metadata, no Majoris manifest."""
        directory = self.root / "External.rtfd"
        directory.mkdir()
        (directory / "TXT.rtf").write_bytes(
            br"{\rtf1\ansi\pard\li1080\fi-360\tqr\tx2800 Term\tab Value}"
        )
        content, formatting, attachments = rtfd.inspect_package(directory)
        self.assertEqual(content, "Term\tValue")
        self.assertIn("para-li_1080", formatting)
        self.assertIn("para-fi_-360", formatting)
        self.assertIn("para-tabs_2800R", formatting)
        self.assertEqual(attachments, [])

    def test_external_inline_graphic_retains_paragraph_properties(self) -> None:
        """Apple inline graphics must not shift indents or native character offsets."""
        directory = self.root / "TextEdit-Graphic.rtfd"
        directory.mkdir()
        (directory / "Picture.png").write_bytes(
            b"\x89PNG\r\n\x1a\n" + bytes(25)
        )
        (directory / "TXT.rtf").write_bytes(
            b"{\\rtf1\\pard\\li720 Before "
            b"{{\\NeXTGraphic Picture.png \\width3600}\\'ac} after}"
        )
        _, _, assets = rtfd.inspect_package(directory)
        converted = rtfd._external_note(directory, assets)
        self.assertIsNotNone(converted)
        text, formatting, references = converted
        self.assertEqual(text, "Before \ufffc after")
        self.assertIn("0:14:para-li_720", formatting)
        self.assertIn("7:8:image_", formatting)
        self.assertIn("Picture.png", references)

    def test_native_rtfd_keeps_identical_style_intervals(self) -> None:
        """RTFD export/reimport preserves native paragraph spans and external RTF."""
        store = self.root / "data"
        (store / "attachments").mkdir(parents=True)
        formatting = (
            "0:10:para-li_720\n0:10:para-fi_-240\n"
            "0:10:para-tabs_1440C_2880R\n"
        )
        with closing(sqlite3.connect(store / "notes.db")) as db:
            db.executescript("""
                CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, content TEXT,
                    formatting TEXT, status INTEGER);
                CREATE TABLE attachments (id TEXT, note_id TEXT,
                    display_name TEXT, mime_type TEXT);
            """)
            db.execute(
                "INSERT INTO notes VALUES (?,?,?,?,0)",
                (self.note_id, "Heading", "Term\tValue", formatting),
            )
            db.commit()
        output = self.root / "Export.rtfd"
        rtfd.export_note(store, self.note_id, output)
        _, _, assets = rtfd.inspect_package(output)
        native = rtfd.read_native_note(output, assets)
        self.assertIsNotNone(native)
        self.assertEqual(native[0], "Term\tValue")
        self.assertEqual(native[1], formatting)
        exported = (output / "TXT.rtf").read_bytes()
        self.assertIn(br"\li720", exported)
        self.assertIn(br"\fi-240", exported)
        self.assertIn(br"\tqc \tx1440", exported)
        self.assertIn(br"\tqr \tx2880", exported)


class PortableParagraphExchangeTests(unittest.TestCase):
    """Preserve new RTF paragraph tokens through existing portable ZIP bundles."""

    def test_v7_bundle_retains_paragraph_styles(self) -> None:
        """Shared notes preserve paragraph tokens without database migrations."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            recipient = root / "recipient"
            for path in (source, recipient):
                path.mkdir(mode=0o700)
                with closing(sqlite3.connect(path / "notes.db")) as db:
                    db.executescript("""
                        PRAGMA user_version=7;
                        CREATE TABLE notes (
                            id TEXT PRIMARY KEY, title TEXT NOT NULL,
                            content TEXT NOT NULL, color TEXT NOT NULL,
                            created_at_us INTEGER NOT NULL,
                            updated_at_us INTEGER NOT NULL,
                            formatting TEXT NOT NULL DEFAULT '',
                            collapsed INTEGER NOT NULL DEFAULT 0,
                            floating INTEGER NOT NULL DEFAULT 0,
                            translucent INTEGER NOT NULL DEFAULT 0,
                            window_width INTEGER NOT NULL DEFAULT 370,
                            window_height INTEGER NOT NULL DEFAULT 330,
                            visible INTEGER NOT NULL DEFAULT 0,
                            source_url TEXT NOT NULL DEFAULT '',
                            remind_at_us INTEGER NOT NULL DEFAULT 0,
                            reminder_notified_at_us INTEGER NOT NULL DEFAULT 0,
                            status INTEGER NOT NULL DEFAULT 0,
                            pinned INTEGER NOT NULL DEFAULT 0,
                            auto_title INTEGER NOT NULL DEFAULT 0,
                            reminder_repeat_us INTEGER NOT NULL DEFAULT 0
                        );
                        CREATE TABLE attachments (
                            id TEXT PRIMARY KEY, note_id TEXT,
                            display_name TEXT, mime_type TEXT
                        );
                    """)
            identity = str(uuid.uuid4())
            formatting = (
                "0:10:para-li_720\n0:10:para-fi_-240\n"
                "0:10:para-tabs_1440C_2880R\n"
            )
            with closing(sqlite3.connect(source / "notes.db")) as db:
                db.execute(
                    "INSERT INTO notes (id,title,content,color,created_at_us,"
                    "updated_at_us,formatting) VALUES (?,?,?,?,?,?,?)",
                    (identity, "Title", "Term\tValue", "yellow", 10, 11, formatting),
                )
                db.commit()
            archive = root / "sample.stickies"
            with patch.object(exchange, "_application_is_running", return_value=False):
                exchange.share_note(source, identity, archive)
                self.assertEqual(
                    exchange.import_note(recipient, archive, True), "Note imported"
                )
            with closing(sqlite3.connect(recipient / "notes.db")) as db:
                self.assertEqual(db.execute(
                    "SELECT formatting FROM notes WHERE id=?", (identity,)
                ).fetchone(), (formatting,))

    def test_rtf_and_share_validators_agree_on_paragraph_tokens(self) -> None:
        """Keep the two installed workers' bounded style grammars equivalent."""
        for token in (
            "para-li_720", "para-ri_360", "para-fi_-240",
            "para-tabs_1440C_2880R", "para-li_-1", "para-fi_9999",
            "para-tabs_0L", "para-tabs_1440L_720R", "para-tabs_1440L;}",
        ):
            with self.subTest(token=token):
                self.assertEqual(
                    bool(exchange._style_supported(token)),
                    bool(rtf_export._dynamic_style(token)),
                )


if __name__ == "__main__":
    unittest.main()
