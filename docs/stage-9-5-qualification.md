# Majoris Stickies 0.9.5 — compatibility and qualification

## Completed source changes

1. **Title mode is durable.** SQLite `PRAGMA user_version` advances from 5 to 6.
   `notes.auto_title` is an integer constrained to 0/1; new notes start with
   automatic title updates, while directly edited titles become manual. The
   note menu allows switching between those modes. The migration retains all
   original note IDs, attachments, styles, timestamps and other fields.
2. **Legacy title mode is inferred conservatively.** Only the exact old
   `Untitled Note` placeholder becomes automatic. Titles matching the body are
   not assumed automatic because that could overwrite intentionally chosen
   manual titles. This is a deliberate one-time migration limitation.
3. **Portable interchange is version-aware.** v6 bundles can convey the new
   title field; v4/v5 bundles remain supported and default to manual mode.
   Imports into older schemas reject records requiring automatic-title state
   instead of silently losing it. Revision signatures for old compatible
   bundles continue to use the old portable field sets.
4. **Backup and reminder tools** accept v6 without changing their file formats
   or reminder semantics. The manager only recreates an edited card when its
   filter and position remain stable; structural changes rebuild the visible
   page safely.

## Tests performed in the source packaging environment

- Python integration suites, including exchange between SQLite v5/v6 stores,
  original 16-field bundle compatibility, v6 title-mode round trips, safe
  downgrade rejection, and backup manifest verification.
- Existing offline backup/recovery tests and SQL migration syntax exercise.
- Static XML/JSON, GNOME extension JavaScript, native C store-lock syntax,
  metadata consistency, source documentation and ZIP integrity checks.

## Native tests not performed here

The packaging container lacks `valac`, Meson, GTK4/libadwaita development SDKs,
and a compatible Majoris Image development SDK. A complete native build and
application runtime qualification therefore cannot be marked successful.

On Debian 13 with the SDKs installed:

```sh
meson setup build -Dimagekit=disabled -Dspellcheck=disabled
meson compile -C build
meson test -C build --print-errorlogs
meson setup build-spelling -Dimagekit=disabled -Dspellcheck=enabled
meson compile -C build-spelling
meson test -C build-spelling --print-errorlogs
# Install the compatible Majoris Image SDK, then:
meson setup build-imagekit -Dimagekit=enabled -Dspellcheck=enabled
meson compile -C build-imagekit
meson test -C build-imagekit --print-errorlogs
```

Use the included GUI smoke harness and test the new title-menu action across
window closure/restart, old-v5 migration, sharing, backup and offline reminder
operation. Test that changing one note does not disturb focus in other visible
manager cards. Qualify actual GNOME 48–50 Wayland compositor behavior, Orca,
Debian package installation and Majoris ISO integration separately.

## Still incomplete or optional

Full native macOS RTFD fidelity, lossless nested structured lists, advanced
image cropping/markup, PDF annotations, pressure-sensitive pen input,
automatic browser-origin discovery and cloud-account synchronization are not
implemented in this change. The 64 simultaneously open window limit is also
retained. The official Debian maintainer email has not been provided and the
release preflight correctly treats that as a distribution blocker.
