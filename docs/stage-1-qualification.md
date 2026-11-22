# Stage 1 qualification record

**Source release:** 0.1.0  
**Date:** 2026-11-22  
**Status:** Source implementation; runtime qualification outstanding

## Completed source work

- New Vala/libadwaita application built around a single-instance application ID.
- XML templates for manager and note windows, compiled as GResources.
- SQLite-backed note model, Unicode search, autosave timers, and flush/error signals.
- Searchable, color-coded note cards and independent note editors.
- Note creation, duplication, permanent deletion with confirmation, and palette.
- Desktop entry, metainfo, README, architecture and test registration.
- Source-level tests for model/storage and Python XML resource check.

## Verification performed

| Check | Result |
| --- | --- |
| ZIP starter content examined | Passed: only the one-line README existed |
| Majoris engineering standard v1.8 reviewed | Completed |
| XML templates and GResource manifest parsed with Python | Passed |
| Python resource contract tests | Passed (5 cases) |
| SQLite schema and UPSERT syntax (Python sqlite3) | Passed |
| Vala compilation | Not run — valac not installed |
| Meson setup/compile | Not run — Meson and native GTK development packages unavailable |
| Vala model/repository unit tests | Not run — Vala compiler unavailable |
| GTK display smoke test | Not run — no GTK runtime/development stack |
| Debian source packaging | Not included in Stage 1 |

## Release gate on Debian 13

Run the commands below on a development host with dependencies from `meson.build`:

```sh
meson setup build -Dwarning_level=3
meson compile -C build
meson test -C build --print-errorlogs
G_MESSAGES_DEBUG=all ./build/src/majoris-stickies
```

Inspect initial startup, multiple note editors, Ctrl+N, Ctrl+F, Unicode search,
color changes, save status, duplication, deletion confirmation, and persistence
after application restart. Verify a forced SQLite write failure preserves the
editor and reports an error. The build and runtime steps above are pending, not
asserted as passing.
