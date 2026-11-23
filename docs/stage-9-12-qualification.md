# Majoris Stickies v0.9.12 — Portable Paragraph and RTFD Interoperability

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

## Standalone RTFD qualification

RTFD is a local document exchange format, not a connection to an Apple
account or service. Verify the supported RTF/RTFD subset with constructed
and user-supplied files using the existing bounded parser:

```sh
python3 tools/stickies_rtfd.py inspect /path/to/example.rtfd
python3 tools/stickies_rtfd.py metadata /path/to/example.rtfd
```

The converter rejects unsupported structures rather than promising complete
third-party document fidelity. No platform-specific application, operating
system service, or remote account is needed to exchange local documents.

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
