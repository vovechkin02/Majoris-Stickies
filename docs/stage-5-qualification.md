# Majoris Stickies Stage 5 qualification — v0.5.0

## Scope

Stage 5 adds one-time reminders, bounded pointer handwriting, HTML and
attachment-inclusive portable-note export, and manual folder exchange with
conflict copies. The database changes from `PRAGMA user_version=3` to `4`
without changing existing note IDs, attachments, rich-text spans, source URLs,
or window geometry. The new exchange CLI is installed as
`majoris-stickies-exchange` alongside the existing recovery tool.

This source distribution is **not yet native-build-qualified**; compilation,
GTK runtime checks, screen-reader testing, GNOME notification delivery and
Debian package construction must be completed on the target Debian 13 desktop.

## Native build and qualification

```sh
meson setup build -Dimagekit=disabled -Dshell_extension=true -Dwarning_level=3
meson compile -C build
meson test -C build --print-errorlogs
meson install -C build --destdir "$PWD/stage"
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 -m unittest discover -s tests/integration -p 'test_stage5_exchange.py'
python3 tools/check_source_docs.py
node --check shell/majoris-stickies@majoris.org/extension.js
node --experimental-default-type=module tests/integration/test_layout.mjs
dpkg-buildpackage -us -uc -b
```

Repeat the Meson build with `-Dimagekit=enabled` after installing the
compatible Majoris Image GTK4 development package. Inspect the installed
binaries for the two utilities and confirm that the packaged Shell extension
remains optional. Replace the placeholder Debian maintainer before release.

## Must-pass runtime scenarios

1. Upgrade existing Stage 1/2/3/4 databases, with attachments and URL
   references. Confirm all IDs and note data remain intact. Run backup,
   verify and fresh-directory restore on a v4 database.
2. Schedule a reminder for 10 minutes, one hour and tomorrow morning; ensure
   precisely one notification per scheduled reminder when the application is
   running. Reopen the app after a reminder becomes due and confirm catch-up;
   clearing or rescheduling must reset delivery status. Verify invalid future
   deadlines and missing-note requests fail safely. The app does **not** send
   reminders while closed; do not advertise it as a background alarm service.
3. With mouse, touch and stylus input, draw/clear/save an ink canvas. Verify
   SVG has numeric paths only, valid dimensions, no external URLs or active
   elements. Reopen the note with and without ImageKit; inspect the attachment
   and delete it through existing attachment controls. Check repeated dialogs
   for reference leaks, accessibility, and keyboard-only close/cancel.
4. Export formatted HTML with special characters and malicious-looking text;
   verify the generated file does not execute note text as markup. Share a
   single note containing Unicode and several images as `.stickies`; verify
   it contains **only** that note and its attachments, correct SHA-256 hashes,
   and no private data paths or extraneous notes.
5. Import a `.stickies` bundle into an app-closed profile. Check identical
   revisions are skipped and divergent identity collisions become new notes.
   Sync two independent profiles through a user-chosen folder. Test two-way
   edits, conflicts, duplicate attachment names, unchanged view preferences,
   a previously deleted note, multi-device clock differences and concurrent
   sync attempts. Confirm local/remote edits survive divergence, invalid ZIPs
   do not alter the local database, and active-app sync is refused. An
   advisory lock is not a distributed cloud lock; serialize sync on devices.
6. Verify both light/dark theme modes, keyboard focus, the menu's accessible
   labels and screen-reader announcements. A short static resource test is not
   a substitute for Orca or GUI testing.

## Privacy and functional limits

- Folder exchange is **manual only** and requires the GUI closed; it does not
  provide an account connector, remote provider API, end-to-end encryption,
  automated schedules, or deletion propagation. A third-party cloud folder
  may upload the plaintext ZIP files at that provider's discretion.
- A portable `.stickies` file is ZIP data and is not inherently encrypted.
  Sharing is explicit and per-note; users should review sensitive content.
- Ink capture is a simple path recorder without pressure/tilt or OCR.
- Reminders use local `GApplication` notifications only when Stickies runs.
  There is no installed background reminder worker.
- No runtime claims can be made until the Debian 13 Vala, GTK, ImageKit,
  GNOME Shell, and package qualification gates are run.
