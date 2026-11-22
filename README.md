# Majoris Stickies

Stickies is a local-first Vala/GTK4/libadwaita desktop application for short notes. Its
Stage 1 implementation includes a searchable notes manager and separate editor windows.
It is designed for Majoris OS (Debian 13 and GNOME).

**Version:** 0.1.0 (Stage 1 source implementation)  
**Status:** Pre-release; no runtime compilation qualification has yet been completed for this archive  
**License:** GPL-3.0-or-later  
**Application ID:** `com.majoris.stickies`  
**Executable:** `majoris-stickies`

## Contents

- [Features](#features)
- [Supported platforms and integrations](#supported-platforms-and-integrations)
- [Requirements](#requirements)
- [Build and installation](#build-and-installation)
- [Quick start](#quick-start)
- [Application interfaces](#application-interfaces)
- [Architecture](#architecture)
- [Security and compatibility](#security-and-compatibility)
- [Testing](#testing)
- [Documentation and contribution](#documentation-and-contribution)
- [License](#license)

## Features

Stage 1 source implements:

- A central notes manager with color-coded cards, search over titles and bodies, and
  recently modified notes shown first.
- Multiple independent, movable and resizable notes, each with a title and plain-text
  editor. Opening an already-open note brings its editor into focus.
- New, duplicate, and permanently delete commands (deletion requires confirmation).
- Eight built-in note-paper colors, shared across the manager and editor windows.
- SQLite persistence and debounced autosaving after editing; outstanding edits are
  flushed when editors and the manager close, and save failures are shown rather than
  silently acknowledged.
- Automatic restoration of the note collection after application restart. Opening the
  notes manager does not automatically reopen every previous editor window.
- Standard Majoris/GTK keyboard shortcuts: Ctrl+N creates a note and Ctrl+F focuses
  the notes manager's search.

**Not yet implemented:** rich text, inline images/PDFs, screenshots, cloud sync,
archiving/Trash restore, reminders, always-on-top, translucency, collapsed notes, desktop
window position restoration, GNOME Shell extensions, and collaboration. These are
outside the Stage 1 scope. Deletion in Stage 1 is permanent.

## Supported platforms and integrations

| Component | Status |
| --- | --- |
| Debian 13 / GNOME | Intended native deployment platform; runtime unverified |
| GTK4 / libadwaita | Native UI templates, no GTK3 compatibility layer |
| SQLite | Built-in local store; uses WAL for file-backed databases |
| ImageKitView / Majoris Image | Not linked in Stage 1 (no image-rendering feature) |
| GNOME Shell integration | Not included in Stage 1 |
| Internet and account service | Not required |

For future attachment and image-preview work, use
[Majoris Image](https://github.com/vovechkin02/Majoris-Image) and its `ImageKitView`
GTK4 component instead of implementing a competing image decoder. Avoid forcing
ImageKit into the Stage 1 text-only dependency graph.

## Requirements

Install the Meson, Ninja, Vala, and development packages supplying:

| Dependency | Minimum |
| --- | --- |
| Meson | 1.0.0 |
| GLib/GIO | 2.74 |
| GTK4 | 4.12 |
| libadwaita | 1.5 |
| Gee | 0.20 |
| SQLite | 3.35 |

The authoritative dependency list is the root [Meson build](meson.build).
Install a C compiler to compile the generated GResource C source. The default
font, menus, dialogs, and widget appearance are provided by the installed theme.

## Build and installation

From the repository root on a system with the dependencies above:

```sh
meson setup build
meson compile -C build
meson test -C build --print-errorlogs
./build/src/majoris-stickies
```

Install using your configured prefix:

```sh
meson install -C build
```

No downloaded build-time assets or network services are required. This repository does
not currently include Debian source package metadata. Installing via Meson installs
the executable, application desktop file, and metainfo file. The UI and CSS resources
are compiled into the executable.

## Quick start

Launch **Stickies** from the applications menu or run `majoris-stickies`.
Click **+** to create a note. Type its title and body; changes are saved automatically.
Use the color button to choose a note's paper color. Close the editor to return to the
manager later. Search notes by title or body in the manager. Duplicate or permanently
delete notes from either the manager or their windows.

The notes database is stored at
`$XDG_DATA_HOME/majoris/stickies/notes.db`, or
`~/.local/share/majoris/stickies/notes.db` when `XDG_DATA_HOME` is unset.
For backups, stop Stickies before copying the SQLite database (and any WAL/SHM files
if they are present).

## Application interfaces

The application is single-instance through its `com.majoris.stickies` application ID.
In Stage 1, there is no stable external D-Bus API, command protocol, plugin API, public
Vala SDK, or library ABI. The Ctrl+N/Ctrl+F application actions are internal UI
bindings and are not published cross-process interfaces.

## Architecture

Core note data and SQLite coordination are intentionally independent of GTK:

- `src/core/note.vala`: editable note state and timestamp invariants.
- `src/core/note-palette.vala`: validated, persistent color tokens.
- `src/core/note-repository.vala`: CRUD, search, SQLite, save timers, GObject signals.
- `src/gtk/manager-window.vala`: searchable note-card UI.
- `src/gtk/note-window.vala`: individual note editor, color choices, save status.
- `src/app/application.vala`: single-instance lifecycle, actions, window registry.
- `src/app/main.vala`: minimal application entry point.
- `data/*.ui`: declarative window templates; GResource embeds templates and the
  semantic note-paper CSS.

See the current [architecture decision record](docs/architecture.md) for boundaries,
GoF applicability, SQL schema, and failure behavior.

## Security and compatibility

SQLite writes are prepared and parameter-bound, not string-interpolated. The
application data directory is created with mode `0700` where possible. The app never
requires root access or an online account. Note bodies are plain text, not interpreted
as markup or executed. The database schema version is tracked through `user_version`.

The source is currently designed for one running application instance per user.
Large databases may require a future asynchronous loading and virtualized list path;
Stage 1 uses short main-context SQLite operations and a debounced card refresh.
Auto-save errors retain dirty note state and prevent normal editor closure until a
successful flush. A forced process termination or system crash can still lose the
most recent unsaved debounce interval; there is no transaction journaling for edits
outside the SQLite transaction itself.

## Testing

With development dependencies installed:

```sh
meson test -C build --print-errorlogs
```

The unit tests cover note changes, palette validation, persistence across database
reopens, UTF-8 and quoting, search, duplicate identity, and deletion. The XML
integration test checks resource entries and controls against GTK template bindings.
The Python-only static integration test can also run without a GUI/toolchain:

```sh
python3 tests/integration/test_resource_layout.py data
```

**Qualification status for this ZIP:** the XML integration test passed (5 cases); SQLite schema/UPSERT SQL syntax
was also sanity-checked with Python SQLite. The Meson/Vala
build, GTK runtime, and Vala unit tests were **not run** because the creation environment
has no Vala compiler, Meson, or GTK/libadwaita development libraries. This archive
must pass those checks on Debian 13 before being treated as release-ready.

## Documentation and contribution

- [Architecture](docs/architecture.md)
- [Stage 1 implementation notes](docs/stage-1-qualification.md)
- [Majoris Cross-Project Engineering Standards v1.8](docs/engineering-standards-v1.8.md)
- [Contribution guidance](CONTRIBUTING.md)

Use American English and meaningful Valadoc for all original source declarations.
Keep presentation templates in XML; avoid hard-coded app chrome. See the supplied
engineering standard for testing, GoF, naming, ownership, and release requirements.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). This original Stage 1 code does not vendor
external code, image assets, or the Majoris Image library.
