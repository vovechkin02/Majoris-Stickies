"""Qualify richer RTF paragraph styling and bounded Apple RTFD package support."""

from __future__ import annotations

from pathlib import Path
import importlib.util
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load_tool(name: str):
    """Load the shipping helper, not a similarly named system module."""
    source = ROOT / "tools" / (name + ".py")
    spec = importlib.util.spec_from_file_location(name, source)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rtf_import = load_tool("stickies_rtf_import")
rtf_export = load_tool("stickies_rtf")
rtfd = load_tool("stickies_rtfd")


class RichRtfParagraphTests(unittest.TestCase):
    """Ensure external style declarations survive conversion to portable tags."""

    def test_custom_font_color_point_size_and_alignment(self) -> None:
        """Retain declared user-facing styles that GTK already supports."""
        text, formatting = rtf_import.RtfReader().parse(
            br"{\rtf1\ansi{\fonttbl{\f0\fswiss Avenir Next;}}"
            br"{\colortbl;\red17\green99\blue170;}"
            br"\f0\cf1\fs46\qr Styled}"
        )
        self.assertEqual(text, "Styled")
        for token in (
            "0:6:face_Avenir%20Next", "0:6:rgb_1163aa",
            "0:6:point_23", "0:6:align-right",
        ):
            with self.subTest(token=token):
                self.assertIn(token + "\n", formatting)

    def test_dynamic_styles_survive_export_import(self) -> None:
        """Preserve supported user-chosen font, RGB and size across RTF export."""
        rendered = rtf_export.make_rtf(
            "Title", "One Two", "0:3:face_Avenir%20Next\n"
            "0:3:rgb_1163aa\n4:7:point_23\n4:7:align-center\n"
        )
        text, formatting = rtf_import.RtfReader().parse(rendered)
        self.assertEqual(text, "Title\n\nOne Two")
        self.assertIn("7:10:face_Avenir%20Next\n", formatting)
        self.assertIn("7:10:rgb_1163aa\n", formatting)
        self.assertIn("11:14:point_23\n", formatting)
        self.assertIn("11:14:align-center\n", formatting)

    def test_custom_size_replaces_old_size(self) -> None:
        """Do not stack obsolete fixed-size and dynamic-size tags."""
        text, formatting = rtf_import.RtfReader().parse(
            br"{\rtf1\ansi\fs24 A\fs46 B\fs28 C}"
        )
        self.assertEqual(text, "ABC")
        self.assertIn("0:1:size-12\n", formatting)
        self.assertIn("1:2:point_23\n", formatting)
        self.assertIn("2:3:size-14\n", formatting)
        self.assertNotIn("0:3:size-12\n", formatting)

    def test_true_color_resets_without_accumulating_tokens(self) -> None:
        """Retain unrelated exact RGB colors, not nearest legacy preset."""
        text, formatting = rtf_import.RtfReader().parse(
            br"{\rtf1\ansi{\colortbl;\red1\green2\blue3;"
            br"\red4\green5\blue6;}\cf1 A\cf2 B}"
        )
        self.assertEqual(text, "AB")
        self.assertIn("0:1:rgb_010203\n", formatting)
        self.assertIn("1:2:rgb_040506\n", formatting)
        self.assertNotIn("text-red", formatting)

    def test_utf8_escaped_bytes_and_legacy_macroman(self) -> None:
        """Decode bounded RTF byte escapes according to declared charset."""
        for source, expected in (
            (br"{\rtf1\ansi\ansicpg65001 Caf\'c3\'a9}", "Café"),
            (br"{\rtf1\mac Caf\'8e}", "Café"),
            (br"{\rtf1\ansi\ansicpg1252 Caf\'e9}", "Café"),
        ):
            with self.subTest(source=source):
                self.assertEqual(rtf_import.RtfReader().parse(source)[0], expected)

    def test_apple_list_marker_groups_are_portable(self) -> None:
        """Normalize RTF bullet text into native visible list markers."""
        text, _ = rtf_import.RtfReader().parse(
            br"{\rtf1\ansi\pard\li720\fi-360"
            br"{\listtext\pard\plain\f0\fs20 \'b7\tab}First\par "
            br"{\pntext\'b7\tab}Second\par}"
        )
        self.assertEqual(text, "• First\n• Second\n")


class AppKitRtfdExtendedTests(unittest.TestCase):
    """Verify safe AppKit Unicode names and non-asset filesystem sidecars."""

    def setUp(self) -> None:
        """Create one isolated package containing a valid inline raster name."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.package = self.root / "TextEdit.rtfd"
        self.package.mkdir()
        (self.package / "Photo.png").write_bytes(b"\x89PNG\r\n\x1a\n" + bytes(24))
        self.document = self.package / "TXT.rtf"
        self.document.write_bytes(b"{\\rtf1 Hello}")

    def test_unicode_name_with_rtf_u_escape(self) -> None:
        """Resolve a referenced sibling whose name uses RTF Unicode units."""
        (self.package / "Photo.png").rename(self.package / "Café.png")
        self.document.write_bytes(
            br"{\rtf1 Before {{\NeXTGraphic Caf\u233?.png "
            br"\width2400}\'ac} after}"
        )
        _, _, assets = rtfd.inspect_package(self.package)
        body, styles, names = rtfd._external_note(self.package, assets)
        self.assertEqual(body, "Before \ufffc after")
        self.assertIn("Café.png", names)
        self.assertIn("7:8:image_", styles)

    def test_unicode_surrogate_pair_in_attachment_name(self) -> None:
        """Reassemble emoji filenames from two signed UTF-16 RTF units."""
        (self.package / "Photo.png").rename(self.package / "Photo 🙂.png")
        self.document.write_bytes(
            br"{\rtf1 A {{\NeXTGraphic Photo "
            br"\u-10179?\u-8638?.png \width2400}\'ac} B}"
        )
        _, _, assets = rtfd.inspect_package(self.package)
        body, _, names = rtfd._external_note(self.package, assets)
        self.assertEqual(body, "A \ufffc B")
        self.assertIn("Photo 🙂.png", names)

    def test_appledouble_sidecars_are_ignored_not_imported(self) -> None:
        """Ignore safe Finder sidecars without changing the managed file set."""
        (self.package / ".DS_Store").write_bytes(bytes(64))
        (self.package / "._TXT.rtf").write_bytes(bytes(64))
        (self.package / "._Photo.png").write_bytes(bytes(64))
        text, _, assets = rtfd.inspect_package(self.package)
        self.assertEqual(text, "Hello")
        self.assertEqual([asset.name for asset in assets], ["Photo.png"])

    def test_reject_unknown_or_unmatched_hidden_metadata(self) -> None:
        """Do not permit hidden arbitrary files behind the sidecar exception."""
        for name in (".secrets", "._Absent.png", "._majoris.json"):
            # No matching native manifest exists in this external package.
            with self.subTest(name=name):
                path = self.package / name
                path.write_bytes(b"small")
                with self.assertRaises(rtfd.RtfdError):
                    rtfd.inspect_package(self.package)
                path.unlink()

    def test_reject_oversize_or_symlink_sidecar(self) -> None:
        """Do not follow symlinks or accept unconstrained AppleDouble data."""
        path = self.package / "._Photo.png"
        path.symlink_to(self.package / "Photo.png")
        with self.assertRaises(rtfd.RtfdError):
            rtfd.inspect_package(self.package)
        path.unlink()
        path.write_bytes(bytes(rtfd.MAX_APPLE_METADATA_BYTES + 1))
        with self.assertRaises(rtfd.RtfdError):
            rtfd.inspect_package(self.package)

    def test_reject_unpaired_utf16_attachment_filename(self) -> None:
        """Reject malformed surrogate pairs rather than inventing a path."""
        with self.assertRaises(rtfd.RtfdError):
            rtfd._next_graphic_filename(r"Photo \u-10179?.png \width2400")


if __name__ == "__main__":
    unittest.main()
