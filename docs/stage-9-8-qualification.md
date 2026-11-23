# Majoris Stickies 0.9.8 — Raster crop and PDF Ink annotation qualification

**Status:** Source implementation plus offline regression checks. Native Vala,
GTK4/Wayland, Majoris Image rendering, and Debian binary builds **not executed**
in this packaging environment. SQLite schema **v7** is unchanged.

## Implemented

### Non-destructive crop

- On a PNG/JPEG/GIF/WebP attachment, use **Crop** to preview with Majoris Image
  and choose **Left**, **Top**, **Width**, **Height** percentages. The bounded
  helper reads width/height headers (it does **not** decode image pixels), then
  creates a private, self-contained SVG whose `viewBox` is defined in actual
  source-image pixels. Cropped copies preserve the source's aspect ratio, and
  the original managed image is never overwritten.
- The GTK crop dialog is defined in `data/image-crop-editor.ui` and provides
  accessible numeric selection controls. It does not offer freehand crop
  handles or raster re-encoding. SVG embedding is limited to 1 MiB of source
  raster content; unsupported dimensions, symlinks, invalid crop ranges,
  and existing output paths fail closed. EXIF orientation is not normalized by
  the header-only helper and requires live ImageKit verification.
- This SVG operation is non-destructive *visual cropping*, not a new image
  decoder. Majoris Image remains responsible for displaying the SVG attachment.

### Actual PDF Ink annotations

- In the ImageKit-enabled PDF page preview, use **Annotate PDF**, draw with the
  existing ink canvas and attach a new PDF containing real standard `/Ink`
  annotation dictionaries and `/InkList` coordinates. The earlier
  **Mark Up Page** action remains available for a flattened SVG preview copy.
- `python3-pypdf` is an optional recommended Debian runtime dependency. The
  CLI fails visibly when missing; it is installed in CI for mandatory tests.
  Debian 13 provides a compatible pypdf 5.x package.
- Preview ink is translated through the PDF crop box using proportional
  letterboxing, including an inverted vertical axis. Rotated, unsupported,
  password-protected, or unusually large PDFs/pages are rejected instead of
  placing annotations incorrectly. The original PDF is untouched; creating a
  copy from a digitally signed PDF can invalidate the signature of that copy.
- The CLI accepts only the existing bounded native ink grammar. It limits
  source PDF size to 50 MiB, page count to 250 and output size to 60 MiB, uses
  no shell command, rejects source links and existing output destinations,
  and creates owner-only files. The PDF writer preserves other pages. The
  annotation objects are **not** just raster or SVG overlays.

## Tests and engineering

Python integration tests validate actual self-contained cropped SVGs, raster
header dimensions, symlink and output-clobber rejection, genuine PDF `/Ink`
objects, Poppler rendering of annotations, page selection, malformed documents,
rotation rejection, original preservation, and extensionless Meson-installed
helper layouts. Each new helper reuses the existing bounded raster/ink parser
through the project-supplied image-markup executable without duplicating the
validation protocol. The native UI transfers continue to use
`NoteRepository.attach_file` and the established cancellation lifecycle.

The following is required before shipping:

```sh
meson setup build -Dimagekit=disabled -Dspellcheck=disabled
meson compile -C build
meson test -C build --print-errorlogs
# Install the compatible Majoris Image SDK, then:
meson setup build-full -Dimagekit=enabled -Dspellcheck=enabled
meson compile -C build-full
meson test -C build-full --print-errorlogs
xvfb-run -a dbus-run-session -- python3 tools/smoke_gui.py build-full/src/majoris-stickies
dpkg-buildpackage -b -us -uc
```

Verify real image and cropped-SVG rendering (portrait, landscape, EXIF
orientation, animated images), PDF annotation page alignment under varying
aspect ratios, attachment restoration after restart, accessibility, cancellation,
Wayland and GNOME Shell integration, and installed optional `python3-pypdf`.
The official Debian maintainer contact remains a release blocker.

## Still outside this increment

Full external macOS RTFD/NSFileWrapper fidelity, a semantic paragraph/list
model, pressure/tilt ink samples, browser-origin monitoring, account-based cloud
synchronization, desktop-window limits above 64, database-level FTS5 search, and
complete PDF editing (editing/removing arbitrary existing annotations, signed
PDF workflows, rotation-aware annotation) remain incomplete. No new numbered
stage is required; the existing Stage 7/9 native qualification gates still
must be closed.
