# Majoris Stickies v0.9.12 — Paragraph and macOS RTFD Interoperability

## Implemented scope

1. **Paragraph indents and margins.** Common RTF `\liN`, `\riN`, and
   `\fiN` declarations are imported as bounded existing `start:end:style`
   intervals (`para-li_N`, `para-ri_N`, `para-fi_N`). They retain exact signed
   twip units within ±7200 (left/right nonnegative), and export as ordinary
   RTF paragraph controls. `\pard` resets these settings between paragraphs.
2. **Tab stops.** Interpret at most 12 strictly increasing `\txN` stops, using
   the preceding `\tql`, `\tqc`, `\tqr`, or `\tqdec` alignment. Serialize
   one canonical `para-tabs_1440C_2880R`-style token per paragraph and emit
   matching RTF control words on export. GTK4 presentation uses scoped
   `Gtk.TextTag` paragraph properties and `Pango.TabArray`. The RTF twip
   metadata is not rewritten by HiDPI/UI scale changes.
3. **List metadata.** Extract only declarative, bounded `\listtable`,
   `\listoverridetable`, `\listid`, `\ls`, `\levelnfc`, and `\ilvl` values.
   Common numbered and bullet list kinds and up to six levels are represented
   by the established `list-*` style tokens. Unknown formats/list identifiers
   do not produce fabricated kinds. The converter does not evaluate list
   tables, field instructions or embedded objects.
4. **HTML interchange.** Bounded paragraph margins and first-line offsets
   produce actual CSS on exported `<p>` and `<li>` elements. Tabs use a
   validated `data-note-tabs` attribute: HTML has no exact equivalent for
   arbitrary RTF tab-stop alignments. Preexisting HTML is unchanged for notes
   without the new paragraph attributes.
5. **RTFD continuity.** The imported/external `TXT.rtf` uses the same bounded
   parser, including Apple `NeXTGraphic` image references. Majoris-native
   RTFD metadata retains formatting byte-for-byte. The original images and
   SQLite attachment identities remain unchanged.

## Compatibility and security

- **Current database: SQLite schema v7.** No schema migration and no new
  binary document format. Existing notes, backups, UUIDs and share bundles
  keep their previous representation. Older application versions may omit
  presentation of newly created `para-*` tokens; the visible text is intact.
- Reject unsupported negative margins, oversized indents, malformed or
  out-of-range tab positions, duplicate tab coordinates and more than 12 tabs.
- All list tables are bounded by the existing 64-KiB RTF table size and
  existing 16-MiB input ceiling; the maximum 64-group nesting depth remains.
- Export uses a bounded interval sweep for paragraph properties instead of
  scanning every span separately for each paragraph.
- This is not a complete implementation of Apple's `NSParagraphStyle`,
  arbitrary Word numbering templates, tab leaders, nonstandard paragraph
  spacing, complex tables, embedded RTF objects, or `NSFileWrapper` variants.
  These features must remain explicitly outside guaranteed interoperability.

## Actual macOS TextEdit qualification — still required

No authentic macOS TextEdit-generated `.rtfd` sample or macOS AppKit runtime
was available in this source-only build environment. The included generated
fixtures **do not count** as a TextEdit UI round trip.

On a macOS installation, create a document in TextEdit with the following:

- Left and right indents, including a negative first-line indent;
- Left/center/right/decimal tab stops and literal tab characters;
- Multiple bullet and numbered list levels with mixed paragraph styles;
- Custom font, size, RGB color, Unicode and at least one image with an
  attachment filename containing spaces or accented characters.

Save as **Rich Text with Attachments (.rtfd)** and keep the original directory
package, including `TXT.rtf` and any ordinary sibling image files. Use:

```sh
python3 tools/stickies_textedit_qualify.py '/path/to/ActualTextEdit.rtfd'
python3 tools/stickies_textedit_qualify.py '/path/to/ActualTextEdit.rtfd' \
    --expected '/path/to/expected.json'
```

An optional expected JSON object may include `text`, `text_sha256`,
`formatting_sha256`, `attachments`, `inline_images`, `paragraph_styles`,
`list_styles`, and `required_styles`. The tool reads the package without
modifying it, fails on mismatched expectations, and prints a structured report.
Only label the document a **real TextEdit fixture** when its provenance has
been verified; constructed test files are not substitutes.

Then perform the **native UI** sequence: import into Stickies, examine its
appearance and image alignment, export a new `.rtfd`, open that output in
TextEdit, compare the visual layout side by side, save again with TextEdit,
and reimport into Stickies. Record the macOS version, source/exported fixtures,
losses, screenshots and any unsupported properties. Pixel-level visual and
native GTK/ImageKit behavior are **not tested** by the fixture inspector.

## Local build and testing

```sh
python3 -m unittest discover -s tests/integration -p 'test_*.py' -q
python3 -m unittest discover -s tests/recovery -p 'test_*.py' -q
python3 tools/check_source_docs.py
python3 tools/release_preflight.py
meson setup build -Dimagekit=disabled -Dspellcheck=disabled
meson compile -C build
meson test -C build --print-errorlogs
meson setup build-native -Dimagekit=enabled -Dspellcheck=enabled
meson compile -C build-native
meson test -C build-native --print-errorlogs
```

The Vala and GTK compilation, installed-app smoke test, ImageKit rendering,
Gnome Wayland behavior, Debian binary build and actual TextEdit visual
round trip remain **not run** in the source-packaging environment. No fake
maintainer contact has been supplied to bypass strict release preflight.
