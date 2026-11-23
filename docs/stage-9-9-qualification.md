# Majoris Stickies 0.9.9 — Image/PDF editing qualification

**Scope:** Complete the four remaining Priority 2 areas: interactive image crop
handles, image/ink geometry qualification across aspect ratios and scaling,
rotation-aware PDF Ink annotations, and removal/replacement of existing Ink.
This release preserves SQLite schema v7, existing note/attachment identifiers,
legacy interchange, and original source files. ImageKit continues to render
raster images and preview PNGs; Poppler continues to rasterize PDF pages.

## Interactive, non-destructive image cropping

- `data/image-crop-editor.ui` owns the accessible spin buttons and dialog.
  `CropSelectionOverlay` adds eight visible corner/edge handles, shaded
  exclusion and drag-to-move/reselect. Crop percentages remain authoritative
  and are synchronized with the accessible numeric controls; the crop remains
  a **new, self-contained SVG** containing the original raster bytes.
- The new `--probe` mode of `majoris-stickies-image-crop` reads no more than
  256 KiB of source metadata from a regular, nonsymlink file capped at 6 MiB.
  It validates image signatures and reports intrinsic dimensions without
  running another image decoder. Crop output remains limited to the existing
  1 MiB embedded-raster limit. Both GTK crop and markup editors fit an ImageKit
  image into a centered rectangle with the source image's exact aspect ratio.
- The InkCanvas maps GTK allocated pointer coordinates into its fixed 640×360
  serialization space, constrains image marks to the actual letterboxed image
  rectangle, and applies a matching Cairo transform when the GTK widget is
  scaled. This avoids the previously assumed one-pixel-to-one-pixel display
  contract. The SVG helper retains `xMidYMid meet` image fitting.
- Existing GIF/EXIF/JPEG orientation-specific rendering remains dependent on
  ImageKit behavior; actual Wayland/HiDPI orientation and scaling must still
  be exercised on a native Majoris build. The tests cover the source geometry
  model, PNG preview probe, actual SVG rendering and portrait/landscape/square
  output at several target scales, not ImageKit's runtime internals.

## Rotation-aware PDF annotation authoring and management

- The PDF helper supports `/Rotate` 0, 90, 180 and 270 and nonzero crop-box
  origins, mapping the 640×360 letterboxed pen canvas back to page user space.
  Unsupported `/UserUnit`, bad dimensions, off-page strokes, protected PDFs
  and signed/permissions catalogs are rejected. Signed document editing is not
  silently attempted, as the operation could invalidate signatures.
- **Manage Ink** lists actual `/Ink` objects on the displayed page. The user
  selects an ordinal number and chooses **Redraw Selected Ink** or **Remove
  Selected Ink**. Redraw makes a private temporary preview with just that
  annotation removed, then applies replacement ink to a **new PDF attachment**.
  Other page content and unrelated PDF annotation subtypes are preserved.
  Remove also creates a separate new PDF. The selected Ink is pruned as an
  unreachable PDF object so its data is not accidentally retained in output.
- The GTK annotation-management UI is in `data/pdf-ink-manager.ui`. The
  `PdfAnnotationTransfer` service owns execution, temporary output cleanup and
  cancellation; `NoteRepository` remains the only owner of note attachments.
  A bounded `--list-ink` helper mode returns a numeric count, not arbitrary
  untrusted metadata for GTK to interpolate.
- Editing currently means **replacing the selected Ink with newly drawn
  strokes**, not selecting or moving its existing vector control points. All
  operations remain non-destructive; there is no in-place PDF modification.
  This release does not implement editing arbitrary non-Ink annotations,
  signed-document rewriting or PDF form editing.

## Performed offline checks

- Python suites cover rotation transforms and real Poppler rendering for all
  four rotations, nonzero crop-box coordinates, preservation of unrelated
  annotation types and pages, genuine PDF `/InkList` output, signed-document
  rejection, input/output failure paths, removal of orphaned ink objects,
  CLI listing/editing/removal, and private output-file creation.
- Pillow/CairoSVG-backed tests cover rendered PNG/SVG crop coordinates and
  letterboxed mark placement for portrait, landscape and square images; the
  image geometry probe is tested at multiple preview scale targets. The
  CI job installs these as **test-only** dependencies, not application runtime
  dependencies.
- Source documentation coverage, Meson resource registration, Python and
  JavaScript syntax, recovery/regression tests, release-preflight checks, and
  ZIP integrity/perms are evaluated separately.

## Mandatory native qualification — not executed here

The container lacks `valac`, Meson, GTK4/libadwaita development interfaces and
Majoris Image's compatible GTK4 SDK. Do not treat Python rendering tests as
proof of working GTK widgets. On Debian 13 with dependencies installed:

```sh
meson setup build -Dimagekit=disabled -Dspellcheck=disabled
meson compile -C build
meson test -C build --print-errorlogs
meson setup build-imagekit -Dimagekit=enabled -Dspellcheck=enabled
meson compile -C build-imagekit
meson test -C build-imagekit --print-errorlogs
xvfb-run -a dbus-run-session -- python3 tools/smoke_gui.py build-imagekit/src/majoris-stickies
dpkg-buildpackage -b -us -uc
```

On actual GNOME Wayland/HiDPI, verify crop handles at 100%/150%/200% scaling,
keyboard percentages, bounds near edges, portrait/panorama/square images,
EXIF-rotated JPEGs, animated GIFs, genuine ImageKit SVG reopening, several
simultaneously open markup windows, cancellation and temporary file cleanup.
Inspect the rendered PDF Ink at every rotation including nonzero CropBox
origins, verify redraw and remove leave original files unchanged, and test
resuming after restart. Replace the placeholder Debian maintainer contact
before running the strict release gate.

Other outstanding roadmap gaps (full macOS RTFD interchange, semantic nested
lists, automatic browser-origin discovery, cloud sync, pressure/tilt, search
pagination and GNOME Shell/ISO runtime qualification) are unaffected.
