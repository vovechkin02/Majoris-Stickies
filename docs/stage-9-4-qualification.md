# Majoris Stickies 0.9.4 — editor and PDF reading qualification

## Scope and compatibility

This pass adds optional, local-only spelling correction, bounded selectable PDF
page-text copying, six-level list depth metadata, and first-line-generated titles.
It retains SQLite schema version 5, the note UUID and attachment layout, and all
previous sharing and backup data. The Majoris Image GTK4 view remains the sole
in-application image renderer. PDF page rasters still come from Poppler.

### Architecture

- `src/core/note-title.vala` derives the default title; explicit title changes
  stop further automatic derivation for the current window. The tracking state
  is inferred when a note is reopened, so titles matching the first line are
  treated as derived. This is a documented limitation; manual titles generally
  remain untouched but the model does not persist an explicit tracking flag.
- `src/gtk/text-edit-commands.vala` maintains optional `list-depth-1` through
  `list-depth-6` spans beside ordinary readable spaces and list glyphs. The
  existing text-based list model still does not represent every semantic list
  operation supported by word processors, and RTF is not a lossless interchange.
- `src/gtk/note-window.vala` uses GtkSourceView 5 with libspelling only in
  `HAVE_SPELLING` builds. Otherwise it retains the original `Gtk.TextBuffer`.
  The system may need an installed Hunspell dictionary for useful suggestions.
- `src/services/pdf-text-service.vala` delegates explicitly selected pages to
  `tools/stickies_pdf_text.py`, which invokes `pdftotext` without a shell. It
  limits the PDF to 50 MiB, pages to 1–250, output to 1 MiB, and execution to
  12 seconds. It rejects symlinks and pins an open inode via `/proc/self/fd`
  until Poppler exits. It does not OCR scanned documents or modify attachments.

## Local verification performed

The Python integration and recovery suites and Poppler text extraction tests
are executable without Vala. They exercise exchange validation, RTF fallback,
PDF signatures, invalid pages, oversized/symlinked PDFs and actual text output.
Documentation and resource checks are separate from native compilation.

## Required native release gates (not run in the packaging environment)

On Debian 13 with the correct Majoris Image development interface:

```sh
sudo apt install meson ninja-build valac pkgconf libglib2.0-dev \
  libgtk-4-dev libadwaita-1-dev libgee-0.8-dev libsqlite3-dev \
  libgtksourceview-5-dev libspelling-1-dev hunspell-en-us poppler-utils
meson setup build -Dimagekit=disabled -Dspellcheck=enabled
meson compile -C build
meson test -C build --print-errorlogs
meson setup build-minimal -Dimagekit=disabled -Dspellcheck=disabled
meson compile -C build-minimal
```

Install Majoris Image's compatible `majoris-image-gtk4-1` development package
and separately build with `-Dimagekit=enabled`. Confirm both images and the
Poppler-rasterized PDF views render, load and dispose correctly. Exercise
spelling corrections and disabling spelling in an actual GTK note window,
including Unicode, inline images and rich-text undo/redo. Confirm PDF page
copy both in a build with ImageKit and without it, and verify cancellation and
one-page extraction without modifying the source PDF.

Test nested-list cursor placement, six-level indentation, outdenting,
checklist toggles, saved formatting and sharing across two devices. Check
first-line title following and manual override after reopening the note.

Release distribution still requires Orca/keyboard accessibility checks,
Wayland/Mutter floating-window and multi-monitor qualification, a successful
binary Debian build, and the official maintainer address replacing the
placeholder `packaging@example.invalid`. Do not label native checks "passed"
until they are actually executed on the intended system.

## Deferred or optional enhancements

Complete macOS RTFD semantics, full paragraph/list models, image cropping and
markup, PDF annotations, direct image drag-resizing, pressure-sensitive ink,
source-browser interoperability and cloud-account sync remain out of scope.
The local-only default and opt-in synchronization behavior are preserved.
