# Stage 7 — Native qualification and interoperability hardening

## Scope and status

Stage 7 packages v0.7.0 source on top of v0.6.0 with no database or
attachment-format migration. The RTF text exporter and service/menu wiring,
reminder submission ordering, CI gates, Debian manifest, and documentation
are updated. **Native Vala compilation has not been verified in this container.**
Do not tag this archive as a native-qualified release candidate without the
following gates passing on the shipping Debian 13 / Majoris image.

## Confirmed checks in the authoring container

```sh
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 -m unittest discover -s tests/integration -p 'test_stage*_exchange.py'
python3 -m unittest discover -s tests/integration -p 'test_stage7_*.py'
python3 tests/integration/test_resource_layout.py data
python3 tools/check_source_docs.py
node --check shell/majoris-stickies@majoris.org/extension.js
node --check shell/majoris-stickies@majoris.org/layout.js
node tests/integration/test_layout.mjs
python3 -m compileall -q tools tests
```

The recorded local run passed 8 recovery tests, 12 existing exchange tests,
11 Stage 7 RTF/release contract tests, and 9 UI resource checks (40 Python
checks total). The multi-monitor JavaScript test, both shell JavaScript syntax
checks, XML/AppStream parsing, Debian changelog parsing, and the source
checker (330/330 documented declarations) also passed. `valac`, Meson, GTK4,
libadwaita and the GNOME Shell runtime were not installed, so native build,
GUI smoke and Debian binary creation were **not run** locally.

## Native build and package gates

```sh
sudo apt-get update
sudo apt-get install -y meson ninja-build valac gcc pkgconf python3 nodejs \
  libglib2.0-dev libgee-0.8-dev libgtk-4-dev libadwaita-1-dev \
  libsqlite3-dev debhelper dpkg-dev xvfb xauth dbus-x11
meson setup build -Dimagekit=disabled -Dwarning_level=3
meson compile -C build
meson test -C build --print-errorlogs
meson install -C build --destdir "$PWD/stage"
xvfb-run -a dbus-run-session -- \
  python3 tools/smoke_gui.py build/src/majoris-stickies
dpkg-buildpackage -b -us -uc
```

Do a second native build with `-Dimagekit=enabled` after installing the
compatible Majoris Image development package; test all supported image types
and cancellation. Launch the actual GNOME Shell extension on Majoris Wayland,
not just JavaScript syntax checking.

## Manual interactive verification

1. Start on a clean profile and upgrade a copy of real schema-v4 and v5
   databases. Confirm exact IDs, Unicode text, formatting and attachment MIME.
2. Type in two independent note windows, rapidly change formatting, and close
   with dirty changes. Check saved content and caret/selection behavior.
3. Export RTF containing multi-byte Unicode, emoji, overlapping styles and
   escaped braces/backslashes. Open the result in two external rich-text editors.
   Verify a destination that already exists is refused, never replaced.
4. Simulate a transient SQLite save failure while a reminder becomes due.
   Verify that notification submission is not skipped. The desktop's delivery
   service cannot be treated as an acknowledged delivery protocol.
5. Validate accessibility with Orca and keyboard-only interaction, scaling,
   theming, GNOME workspace changes, monitor disconnection and user session exit.
6. Build, install, remove, reinstall the Debian packages; check launcher paths,
   icon metadata, extension activation and the three installed helper commands.
7. Replace the example maintainer address in `debian/control`/`debian/changelog`
   with a real responsible project contact before distribution.

## Outstanding parity and qualification gaps

- RTF **import**, RTFD packages, inline positioned images, embedded PDF page
  display, crop/markup, unrestricted text styling and true top-level
  transparency are not implemented by Stage 7. Export-only RTF is intentional.
- The Xvfb smoke test does not cover GNOME Shell, native Wayland, the
  screenshot portal, screen-reader behavior or image/monitor capabilities.
- Automatic account-based synchronization and background notifications while
  the application is closed were never part of the delivered local-first core.
- The existing Vala codebase has not been compiled here, and native compilation
  may reveal additional issues. Report them as release blockers, not successes.
