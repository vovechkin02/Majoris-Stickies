> **Historical Stage 8.0 plan:** This document describes the original v0.8.0
> scope. The subsequent v0.8.1 completion work and updated known limitations
> are documented in [stage-8-completion.md](stage-8-completion.md).

# Stage 8 — Feature parity and bounded interoperability qualification

## Scope and compatibility

Stage 8 packages version **0.8.0** on top of the supplied v0.7.0 source. The
SQLite schema remains **v5**; no existing note UUID, formatting-token, attachment,
backup or single-note share protocol was changed. It adds text-only RTF import,
repeatable find/replace with case options, checklist-prefix toggling, a 64-window
limit, optional Shell all-workspace/layout-restore actions, lazy ImageKit image
previews and optional Poppler-first-page PDF previews through ImageKit.

## Verified in the authoring environment

```sh
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 -m unittest discover -s tests/integration -p 'test_stage*.py'
python3 tests/integration/test_resource_layout.py data
node --check shell/majoris-stickies@majoris.org/extension.js
node --check shell/majoris-stickies@majoris.org/layout.js
node tests/integration/test_layout.mjs
python3 tools/check_source_docs.py
python3 -m compileall -q tools tests
```

Local verification used the actual `pdftoppm` command to rasterize a tiny PDF
fixture and checked its PNG signature/dimensions. The RTF importer round-tripped
Stage 7 exported Unicode and style groups while rejecting malformed and unsafe
inputs. These tests do **not** establish correctness of the native Vala GUI.

## Required native Debian 13 / Majoris acceptance gates

```sh
sudo apt-get update
sudo apt-get install -y meson ninja-build valac gcc pkgconf python3 nodejs \
  libglib2.0-dev libgee-0.8-dev libgtk-4-dev libadwaita-1-dev \
  libsqlite3-dev debhelper dpkg-dev xvfb xauth dbus-x11 poppler-utils
meson setup build -Dimagekit=disabled -Dwarning_level=3
meson compile -C build
meson test -C build --print-errorlogs
meson install -C build --destdir "$PWD/stage"
xvfb-run -a dbus-run-session -- \
  python3 tools/smoke_gui.py build/src/majoris-stickies
dpkg-buildpackage -b -us -uc
```

Repeat with `-Dimagekit=enabled` after installing the matching current Majoris
Image GTK4 development package. Verify `ImageKit.ImageView.load_file()` on
ordinary image formats, the Poppler-to-PNG-to-ImageKit first-page path, and
canceling/removing an attachment while a preview is still decoding.

**GNOME/Wayland runtime:** Confirm that `ToggleSticky` sticks/unsticks only a
registered note, survives an app restart with the extension still enabled, and
that `RestoreLayout` remains correct after monitor rearrangement. Open 64 notes,
try a 65th, close one, then open it. Verify all notes remain in the manager and
that startup restores no more than 64 windows. Test display loss, workspace
switching, floating notes, and Shell extension disable/re-enable behavior.

**Editor integration:** Import exported and third-party text-oriented RTFs with
Unicode, emoji, nesting and malformed controls. Compare supported style runs
against the original, inspect unsupported RTF objects (not imported), and
verify errors leave the original note untouched. Exercise find-next repeatedly
with the nonmodal dialog, both case modes, replacement containing search text,
Ctrl+Enter checkboxes, and save/restart persistence. Confirm accessibility with
Orca and keyboard-only workflows.

**Packaging:** Replace `packaging@example.invalid`, install/remove both Debian
packages and all helper commands. Test first-run, upgrade from v4/v5 databases,
backup/restore, note exchange, and file ownership. Watch crash leftovers in the
private `/tmp/majoris-stickies-pdf-*` preview directories; temp images are
cleaned up on normal window close but crash cleanup is not guaranteed.

## Explicitly outstanding feature parity

Stage 8 **does not** implement complete RTFD file-package interchange,
positioned inline images, full embedded PDF document/page navigation,
annotation/cropping, arbitrary font/color customization, semantic nested lists,
true top-level compositor translucency, background service reminders or
account-based cloud synchronization. These remain feature work, not tests that
can be declared passed by static verification. Full native compilation,
GUI behavior and GNOME Shell compatibility also remain unverified here.
