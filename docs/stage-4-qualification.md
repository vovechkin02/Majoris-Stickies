# Stage 4 qualification — Majoris Stickies 0.4.0

## Status and implementation boundary

The Stage 4 source adds accessibility labels, bounded manager card pagination,
consistent offline backup/verification/restore, database integrity checks and
limited autosave retries, GNOME multi-monitor placement fixes, and Debian
packaging recipes. SQLite **remains schema v3**, so no Stage 3 data needs
migration. Earlier screenshot and image features remain unchanged.

The source implementation is **not yet a validated native release**. The
packaging host lacks the Vala compiler, Meson and GTK/libadwaita headers.
Do not call static source or backup-tool tests a substitute for compiling the
Vala application and running it on Debian 13 / the Majoris GNOME session.

## Debian 13 build and packaging gates

Install the current Debian 13 toolchain and dependencies. Then run:

```sh
meson setup build -Dimagekit=disabled -Dshell_extension=true -Dwarning_level=3
meson compile -C build
meson test -C build --print-errorlogs
meson install -C build --destdir "$PWD/stage"
python3 tools/check_source_docs.py
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
node --check shell/majoris-stickies@majoris.org/extension.js
node --experimental-default-type=module tests/integration/test_layout.mjs
dpkg-buildpackage -us -uc -b
lintian ../majoris-stickies_0.4.0-1_*.deb
```

Repeat with `-Dimagekit=enabled` and a compatible Majoris Image GTK4
installation; Debian packages use `IMAGEKIT=enabled dpkg-buildpackage -b -us -uc`
for that qualification profile, confirming note attachment previews and no fallback image codec.
Verify the installed `majoris-stickies-backup` executable can back up and
restore a database through the two packages' actual installed paths.
Before release replace the placeholder Debian maintainer address with the
responsible organization's real contact, inspect all `.deb` contents and
Depends, and exercise install, upgrade, removal and reinstallation.

## Data safety and recovery qualification

1. Create notes in Stage 3, attach images and PDFs, edit Unicode formatting,
   update source URLs and capture a screenshot. Upgrade the Stage 4 app and
   verify all prior IDs, contents, tags, attachments and visible-window states.
2. Back up while Stickies is running and editing a separate note. Verify that
   only **committed** note changes, including WAL-backed commits, appear in the
   archive and that attachments are present. `verify` must pass.
3. Restore into a **new** directory with the app closed. Inspect both SQLite
   and attachments. Attempt to restore over live data; this must fail without
   modification. Try truncated archives, modified hashes, missing assets,
   unknown ZIP names and corrupt database content; no false success is allowed.
4. Lock or make the database inaccessible, edit a note and observe up to three
   retries (2, 4 and 8 seconds) without deleting dirty state. Verify that a
   failed save blocks note close and that recovery of the storage path allows
   an explicit retry or subsequent edit to persist. Confirm shutdown errors
   are visible in logs; GTK runtime testing is necessary to certify behavior.
5. Kill the application while windows are open. On restart verify that the
   previous committed data is valid and that open windows are restored.

## Accessibility and performance qualification

- Use Orca and keyboard-only operation on manager search, color filter,
  sorting, card actions, toolbar commands, editor title/body and formatting.
  Confirm accessible names are meaningful, focus visible, and actions usable
  at text scale 200% and under both Majoris light/dark themes.
- Generate 100, 1,000 and 10,000 notes with representative 1–8 KiB bodies;
  measure manager window creation, typing latency, refresh time, memory peak
  and startup time before/after Stage 4. The card page must initially create
  no more than 60 matching card widgets; each Load More action adds up to 60.
  Repository filtering/sorting remain O(n) or O(n log n) and are not virtualized.
- Test accessibility labels with GTK inspector and AT-SPI on the deployed
  version. A static XML check confirms declarations, not screen reader output.

## GNOME Shell / Wayland qualification

- Enable the separate extension on the shipping GNOME Shell release, then
  exercise window registration, Always on Top, cascade, grid, sort-based
  arrangements, and save/restore positions. Test 1, 2, and 3 monitors including
  a secondary screen left of primary (negative X) and different scales.
- Move notes between screens, disconnect the display and reconnect it with
  changed monitor order, work areas or dock placement. Check every registered
  note remains reachable; no unmanaged application window may be moved.
- Disable/re-enable the extension and log out/in. Confirm no stale signal
  subscriptions, unexpected restores, or serialized-layout data loss.
- Test under both the extension-disabled and extension-enabled configurations.
  Shell features must report unavailability without fake success.

## Reported checks on the packaging host

The static UI resource suite, Python backup/recovery suite, source-documentation
coverage script and Node.js geometry tests can run without the native SDK.
Report native Meson/Vala, GUI/Orca/Wayland and Debian package builds as
**not run** until completed on a Debian 13 environment.
