# Stage 9.11 — Advanced RTF and macOS RTFD interoperability

## Completed implementation

1. **RTF styles.** The importer now retains user-chosen `face_*`, `rgb_*`,
   `point_*` tokens that are already supported by `TextStyleFormat`,
   `NoteFormatting`, `RichTextCodec`, and the RTF exporter. It continues
   accepting the historical font and palette aliases. Supported paragraph
   alignment remains in `align-left`, `align-center`, `align-right` spans.
   The importer also normalizes common RTF `listtext`/`pntext` bullet groups
   into visible Majoris list markers, and handles bounded `\ansicpg65001`,
   `\ansicpg1252`, and `\mac` hexadecimal byte sequences.
2. **RTFD attachments.** The helper supports safe UTF-8 and UTF-16-escaped
   `\NeXTGraphic` filenames, including Unicode surrogate pairs. It verifies
   actual sibling image files before emitting an attachment reference. A
   limited set of Finder metadata sidecars (`.DS_Store` and matching AppleDouble
   `._` files) is allowed but not imported as attachments. Each such file must
   be regular, not a symlink, and at most 1 MiB, within the total 128-MiB
   package limit. Unknown hidden files still fail closed.
3. **GTK transfer.** The existing RTFD service uses the same constrained
   handling for metadata sidecars; the installed Python helper still performs
   the final complete package validation before any attachment import.
4. **Interoperability tests.** New test cases cover custom style fidelity,
   exact RGB transitions, list markers, MacRoman/UTF-8 byte escapes, escaped
   Unicode attachment names, safe Finder metadata, and malformed references.
   All existing backup, sharing, note and schema v7 paths are unchanged.

## Decision: should semantic lists have a second persisted document tree?

**Not yet.** `NoteListStructure` is currently a bounded semantic projection
of visible plain-text list prefixes plus the existing `list-*` span tokens.
It is not a second data authority. For the currently supported bullet,
numbered, and checklist behaviors, a new persistent tree would duplicate
paragraph state and force synchronization on every text edit, undo, import,
backup, and older-version interchange. No native build or measured real-note
interop regression currently justifies that migration. Therefore:

- Keep schema **v7**, and keep existing Unicode offsets and stored text spans.
- Preserve derived semantic HTML for clipboard export and ordinary accessible
  list markers in plain-text interchange.
- Do **not** claim lossless import of every external list layout, arbitrary
  paragraph tabs, margin/spacing controls, or Apple `NSTextList` attributes.
- Reconsider a structured-document schema only after real TextEdit fixtures
  demonstrate lost semantics that cannot be expressed by the existing tokens.
  Any migration would require a versioned plan and explicit downgrade policy.

## Native macOS round-trip qualification — not performed here

The available build container is Debian, not macOS. The suite tests generated
RTF and RTFD fixtures but **cannot** claim actual TextEdit UI round trips.
To qualify against real AppKit output:

1. On a current supported macOS installation, create a rich TextEdit document
   containing nested bullets and numbers, paragraph alignment, a custom font
   and RGB text color, Unicode filenames, and embedded PNG/JPEG images.
2. Save the document as **Rich Text with Attachments (.rtfd)**. Copy the package
   without flattening/re-encoding it, retaining both `TXT.rtf` and image files.
3. Run `python3 tools/stickies_rtfd.py inspect /path/to/sample.rtfd` and
   record recovered text, formatting, attachment types, and inline positions.
4. Import with the GTK application; edit the note, then export it as RTFD.
   Open that export in TextEdit and verify the actual appearance, image
   positions, and paragraph formatting. Save again with TextEdit and reimport.
5. Compare the final document with the original. Do not claim fidelity for
   unsupported tables, arbitrary NSFileWrapper trees, embedded EPS/PICT,
   all NSTextList properties, or nonstandard attachment kinds.

On Debian 13 with Vala, GTK4, libadwaita, and the ImageKit SDK installed:

```sh
python3 -m unittest discover -s tests/integration -p 'test_*.py'
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 tools/check_source_docs.py
meson setup build -Dimagekit=disabled -Dspellcheck=disabled
meson compile -C build
meson test -C build --print-errorlogs
meson setup build-full -Dimagekit=enabled -Dspellcheck=enabled
meson compile -C build-full
meson test -C build-full --print-errorlogs
```

The native build, optional integrations, live GNOME Shell behavior, genuine
TextEdit interoperability, and Debian binary release gate are **not verified**
in this source-only environment. Do not replace the Debian maintainer address
with an invented contact to bypass strict release checks.

## Engineering boundaries

RTF/RTFD parsing remains in bounded Python helpers called by asynchronous
subprocess adapters. GTK image rendering remains owned by Majoris Image;
no new image decoder or network dependency is introduced. Existing callbacks,
cancellation, ownership, input-size ceilings and error propagation are retained.
The source-format helpers are the Adapter boundary for external AppKit data;
there is no new GoF abstraction or second persistent document model.
