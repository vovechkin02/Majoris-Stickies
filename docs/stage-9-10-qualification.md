# Stage 9.10 — Semantic lists and external macOS RTFD compatibility

## Implemented features

- `NoteListStructure` projects the existing portable paragraph markers and
  `list-bullet`, `list-numbered`, `list-checklist`, `list-depth-1` through
  `list-depth-6` tags into a bounded semantic paragraph tree. No stored data,
  GObject interfaces, SQLite schema (v7), note or attachment IDs are changed.
- Clipboard/HTML sharing now emits actual nested HTML `<ul>`, `<ol>`, and `<li>`
  nodes. Numbered lists preserve their first visible number using `<ol start>`;
  checked items have explicit `data-checked` metadata. Inline text styles and
  embedded images continue through the existing bounded rich-text encoder.
  Plain, unlisted notes keep their original HTML output to avoid unnecessary
  output-format changes.
- The GTK list commands normalize list-kind tags after list conversion,
  indent/outdent and Return, removing stale list kinds and depth metadata.
  Visible markers and indentation remain ordinary text for backward-compatible
  plain-text reading, undo, and sharing with older Majoris releases.
- The RTFD directory importer accepts normal, bounded UTF-8 sibling filenames,
  including spaces and RTF-escaped UTF-8 bytes, instead of requiring Majoris's
  `attachment-0001.png` convention. File type, name, size and symlink limits
  are retained; directory traversal, arbitrary RTF fields and remote paths
  are never followed.
- External AppKit `NeXTGraphic` references (Apple's documented RTFD extension)
  are translated into Unicode object placeholders and stable temporary image
  style references. The GTK importer remaps those temporary identities when
  transferring the verified sibling files to the private attachment store.
- Exported RTFD now contains Apple-compatible `NeXTGraphic` inline references
  in `TXT.rtf`, **plus** the original `majoris.json` native payload to preserve
  exact Unicode positions, formatting tokens, and attachment identities for
  Majoris-to-Majoris round trips. The bare `.rtf` exporter is unchanged.
- Existing non-Majoris `.rtfd` packages without inline images remain supported
  and import the regular readable RTF text with separate attachments.

## Compatibility and security

The latest persisted format is still SQLite schema **v7**. Legacy note bundles,
backup archives and old 16/18/19-field compatibility formats are unchanged.
Package import retains its 32-asset, 128-MiB aggregate and per-file bounds.
RTF text is bounded by the parser's 16-MiB input limit; nested RTF group depth
and Unicode output remain separately bounded. `NeXTGraphic` assets must be
actual, validated sibling image files. Signed/encoded RTF attachment filenames
must decode to valid UTF-8. Malformed or missing references fail closed.

## Qualification

Run on the Debian 13/Majoris system with Vala, GTK4, libadwaita, ImageKit and
spell checking SDKs installed:

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

Further native tests: edit/switch/outdent numbered and nested checklists,
copy/paste HTML into a standards-compliant editor, import a real TextEdit RTFD
with PNG/JPEG/TIFF attachments, and export/reopen an RTFD on macOS.

**Not native-qualified here:** `valac`, Meson and native GTK development
libraries are absent. The new Vala model/unit checks are included but not run.
This release does **not** claim support for all AppKit document extensions,
embedded vector EPS/PICT renderers, full `NSFileWrapper` semantics, full
paragraph-style round trips from arbitrary third-party rich documents, or
semantic list structures independent of the current visible text markers.

## Engineering decisions

- `NoteListStructure` is a bounded, domain-level projection of existing text
  and tags, not a second persistent document source or a speculative new GoF
  pattern hierarchy. It deliberately avoids a data migration.
- `RtfdTransfer` remains the GTK-facing transfer adapter, and the existing
  Python RTFD helper owns the external file format and input validation.
  The external `NeXTGraphic` syntax is handled only at that boundary.
- Existing GUI signals, message framing, cancellation, file ownership and
  rollback-on-failure behavior are retained. No new external executables or
  image decoding backends are introduced.
