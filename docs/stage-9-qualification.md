# Stage 9 — Release-hardening and qualification record (v0.9.0)

**Status: not release-qualified.** This is an updated source ZIP, not a verified
Debian binary or a tested Majoris ISO package. The user-provided v0.8.2 Stage 8
archive is the baseline. SQLite schema **5** and existing note/asset identities
are unchanged.

## Implemented and checked in source

- Branded scalable `com.majoris.stickies.svg` desktop icon installed through
  Meson and listed in the Debian package manifest, with matching desktop ID.
- Version `0.9.0` in Meson, AppStream and Debian changelog.
- GNOME Shell extension package dependency limited to versions 48, 49 and 50
  (matching its current extension metadata; GNOME 51 needs explicit validation).
- UI resource tests corrected to support standard `unittest discover` and the
  original direct Meson invocation.
- Bounded preview directory recovery for old, private PDF PNG outputs, with
  tests ensuring symlinks, fresh previews and unrelated files are not removed.
- Native GUI smoke assertions for one new note, no spurious note after Show
  Notes, and rejected invalid command-line arguments. Smoke **not run here**.
- Automated preflight for release metadata consistency and missing native
  compiler/development dependencies; no false native qualification claims.

## Local verification

Run these independent checks before any native build:

```sh
python3 tools/release_preflight.py
python3 -m unittest discover -s tests/integration -p 'test_*.py'
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 tools/check_source_docs.py
node --check shell/majoris-stickies@majoris.org/extension.js
node --experimental-default-type=module tests/integration/test_layout.mjs
```

### Native Debian 13 gate — mandatory

Install Meson, Vala, compiler, GTK4, libadwaita, Gee, SQLite development
packages, DBus/Xvfb and Poppler. On a complete system:

```sh
python3 tools/release_preflight.py --require-native
meson setup build-no-imagekit -Dimagekit=disabled -Dshell_extension=true
meson compile -C build-no-imagekit
meson test -C build-no-imagekit --print-errorlogs
meson install -C build-no-imagekit --destdir "$PWD/stage"
xvfb-run -a dbus-run-session -- \
  python3 tools/smoke_gui.py build-no-imagekit/src/majoris-stickies
```

When the **compatible Majoris Image** GTK4 development package and Vala VAPI
are installed, additionally perform an explicit ImageKit build:

```sh
pkg-config --modversion majoris-image-gtk4-1
meson setup build-imagekit -Dimagekit=enabled -Dshell_extension=true
meson compile -C build-imagekit
meson test -C build-imagekit --print-errorlogs
```

Validate GtkTextChildAnchor insertion, resize, duplication and reopening with
real image files in both image-enabled and fallback builds. Do not use an
unrelated image decoder in place of Majoris Image.

### GNOME Wayland qualification — mandatory

On the *actual shipping* GNOME Shell/Mutter release:

1. Enable the optional Stickies extension and verify note-window registration,
   always-on-top, all-workspace visibility and compositor opacity.
2. Restore desktop note positions across monitor addition/removal, negative
   monitor coordinates and workspace changes. Verify the 64-window cap.
3. Check startup, close/save failure, reminder delivery and screenshot portal
   approval/cancel under an ordinary user session.
4. Use Orca, keyboard-only navigation and high-contrast/large-font settings;
   verify the manager, note toolbar, rich editor and inline image controls.
5. Check GTK runtime performance with a representative large note collection;
   database search currently scans in-memory notes.

### Debian / ISO gate — mandatory

The package maintainer in `debian/control` and `debian/changelog` is still
`packaging@example.invalid`. This **must be replaced by the official owner**
before public distribution. The strict preflight gate intentionally fails
until this is resolved.

```sh
# After updating maintainer metadata and installing the required toolchain:
python3 tools/release_preflight.py --release
dpkg-buildpackage -b -us -uc
# Review generated .deb contents, installation, upgrade from 0.8.2,
# first-login behavior, GNOME Shell package compatibility, and purge effects.
```

The build and smoke commands above were **not executed** in the current
container: `valac`, Meson and GTK4/libadwaita developer packages are absent,
and Debian repository DNS resolution failed. Consequently, no compiled binary,
ImageKit runtime compatibility or Debian package is claimed.

## Deferred features, not Stage 9 build regressions

Full macOS RTFD fidelity, arbitrary interactive image resizing/cropping,
nested semantic lists, spell checking, automatic sync, and background reminders
remain product enhancements. The release decision must explicitly accept or
reject these gaps rather than silently marking them complete.
