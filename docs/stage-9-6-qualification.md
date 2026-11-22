# Majoris Stickies 0.9.6 — Paper colors, recurring reminders, and qualification

## Scope

This is a backward-compatible feature pass based on v0.9.5. It preserves note
UUIDs, managed attachments, existing style tokens, and the full legacy palette.
SQLite schema **v7** adds one field, `reminder_repeat_us`, initialized to zero
for all existing records. This is an in-place transactional migration from v6.

### Custom note-paper colors

- The eight legacy palette identifiers continue to work unchanged.
- Custom paper tokens must be exactly `#rrggbb` (lowercase ASCII).
- The perceived brightness threshold `(2126*r + 7152*g + 722*b) >= 1_800_000`
  deliberately excludes dark colors because note text uses dark ink. The GTK
  picker asks for a lighter color instead of silently changing the selection.
- Each custom-color CSS override is scoped to its individual note or manager
  card. This is a bounded, paper-only exception to Majoris Theme. It uses the
  still-supported but GTK4.10-deprecated `Gtk.StyleContext.add_provider` for
  per-widget styling; GTK 4.16 is the current application minimum. Do not
  interpret a static source check as proof of correct visual rendering.
- The color is stored in the existing `notes.color` text field, saved in the
  default preferences file, and accepted by the portable-note validator.
- The notes manager has a separate **Custom Colors** filter.

### Recurring reminders

- Supported intervals are 0 (one-shot), **24 hours**, and **7 days** in Unix
  microseconds. This is fixed elapsed-time recurrence, **not** a calendar rule
  that preserves a given local clock hour through daylight-saving changes.
- Every first occurrence is still bound by the existing one-year deadline
  limit. A user explicitly selects a repeat interval from the note menu.
- After successful notification submission, the next occurrence is derived
  from the original deadline, skipping missed periods without sending bursts.
  Failed submissions leave the original reminder pending for retry.
- The background worker uses the **same exclusive session lock** as the GTK
  application and offline note exchange. A busy lock aborts rather than racing
  SQLite or prompting a second notification.
- Legacy v4–v6 portable bundles still verify with their original signatures;
  new recurring notes require a schema-v7 recipient. Downgrade is rejected
  instead of silently losing the recurrence. `reminder_repeat_us=0` preserves
  older one-shot behavior and existing share formats.
- The offline reminder worker never migrates databases. The GTK application
  owns schema migrations and must be run first after upgrading.

## Engineering evidence and test commands

Run on Debian 13 with native GTK/Vala SDKs installed:

```sh
python3 -m unittest discover -s tests/integration -p 'test_*.py'
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 tools/check_source_docs.py
node --check shell/majoris-stickies@majoris.org/extension.js
node --experimental-default-type=module tests/integration/test_layout.mjs
python3 tools/release_preflight.py --require-native
meson setup build -Dimagekit=disabled -Dspellcheck=disabled
meson compile -C build
meson test -C build --print-errorlogs
meson setup build-full -Dimagekit=enabled -Dspellcheck=enabled
meson compile -C build-full
meson test -C build-full --print-errorlogs
xvfb-run -a dbus-run-session -- python3 tools/smoke_gui.py build/src/majoris-stickies
dpkg-buildpackage -b -us -uc
```

Test the GNOME extension separately on the exact Majoris GNOME/Mutter
version, including monitor unplug/replug, opacity and workspace visibility.
Verify user-level reminder timers, repeated deliveries, data locks and both
custom paper colors in light/dark themes. Test migrations from v6 with existing
notes and attachments before release. Verify the `--release` preflight after
configuring the real Debian packaging maintainer contact; never substitute a
fabricated address.

### Status and remaining scope

Python integration/recovery and source validation can run in the current
container. Native Vala compilation, UI tests, Majoris Image rendering, Orca,
GNOME Wayland and Debian binary creation remain **not run** here.

Still outside this update: full macOS RTFD fidelity, drag-to-resize image media,
image cropping and markup, PDF annotations, pressure-aware handwriting,
automatic originating-browser URL capture, account-based cloud synchronization,
full semantic document/list editing, database-level search pagination and
unbounded simultaneous note-window handling. No additional functionality is
claimed for these unimplemented areas.

## Architecture and design-pattern applicability

- `NotePalette` remains a single validation/label boundary for stable tokens.
- `NotePaperStyle` is a narrowly scoped GTK styling helper, **not** a new GoF
  Strategy, Factory or Decorator. CSS providers belong to widget style contexts.
- Reminder state transitions remain on `Note`, with persistence in
  `NoteRepository`, notification ownership in `StickiesApp`/offline worker.
  GLib signals continue to provide Observer-style state changes.
- Shared offline SQLite locks preserve the established exclusive coordination
  contract; no second application-level event bus or state authority is added.
