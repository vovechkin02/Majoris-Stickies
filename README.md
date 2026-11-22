# Majoris Stickies

Native, local-first sticky notes for Majoris OS, built with Vala, GTK4, libadwaita,
XML UI templates and SQLite. Stickies combines a centralized notes manager with
independent note windows.

**Version:** 0.3.0 (Stage 3 source implementation)  
**Status:** Pre-release; Vala compilation, native GUI and GNOME Shell integration have
not been qualified in the packaging environment  
**License:** GPL-3.0-or-later  
**Application ID:** `com.majoris.stickies`  
**Executable:** `majoris-stickies`

## Contents

- [Features and scope](#features-and-scope)
- [Supported platforms and integration](#supported-platforms-and-integration)
- [Dependencies](#dependencies)
- [Build and installation](#build-and-installation)
- [Usage](#usage)
- [Data and compatibility](#data-and-compatibility)
- [Architecture and API](#architecture-and-api)
- [Security and reliability](#security-and-reliability)
- [Testing and qualification](#testing-and-qualification)
- [Contributing and license](#contributing-and-license)

## Features and scope

Stage 1 remains supported:

- Multiple separately editable notes, color palettes, centralized searchable note
  cards, create, duplicate, permanent delete with confirmation, autosave, and
  single-instance application behavior.
- SQLite storage with 500 ms per-note save debounce, save-on-close safeguards,
  UTF-8 note search, and standard Ctrl+N / Ctrl+F application shortcuts.

Stage 2 adds:

- **Rich text:** bold, italic, underline, strikethrough, monospace, and two
  relative size tags; selection-based toolbar and Ctrl+B / Ctrl+I / Ctrl+U.
  Style intervals persist by Unicode character index, independently of GTK.
- **Attachments:** attach images and PDFs via the file picker, keep managed
  copies with stable identifiers, open them externally, or remove them.
  Image previews use **Majoris Image**'s `ImageKit.ImageView` when its GTK4
  development package is available at build time. Without it, an icon/file
  entry is shown. PDF attachments are listed and open in the default PDF app;
  **inline PDF page previews are not included**.
- **Import/export:** asynchronous UTF-8 plain-text import (up to 2 MiB) and
  plain-text export through native file dialogs. Plain-text export does not
  retain rich-text styles or attachments; a lossless note archive format and
  RTF/RTFD interchange are not yet implemented.
- **Desktop-note preferences:** collapsible note paper, translucent paper,
  last open/closed status, and last noncollapsed window dimensions.
- **Optional GNOME Shell extension:** verified-note always-on-top and
  grid/cascade/title/date/color arrangements, plus compositor-owned window
  coordinate restoration. These features require the separately enabled Shell
  extension; they are not simulated through unsupported Wayland GTK APIs.
- **Database migration:** transactional, in-place migration from Stage 1's
  SQLite schema to Stage 2 without renumbering existing notes.

Stage 3 adds:

- **Screenshots:** capture a screenshot with the interactive XDG desktop portal,
  either in a new note or attached to the current note. Requires the portal
  backend and the user's approval; denial/cancellation never creates a note.
- **Source references:** attach, clear, search, and open a verified HTTP(S) URL
  per note. URLs are entered by users; the application does not claim that it
  can identify the active browser page automatically.
- **Clipboard:** "Copy Note" exports text and supported inline styles via
  `text/plain` and `text/html` MIME formats. Attachment filenames are listed,
  but the private attachment files themselves are not embedded in the clipboard.
- **Manager:** color filter, newest/oldest/title/color sorting, grid/list views,
  visible match count, screenshot action and clipboard copy on each note card.
- **Desktop integration:** launcher actions for New Note, Screenshot Note and
  Show Notes, with `--new-note`, `--capture-screenshot` and `--show-notes`
  command-line routing to the running single-instance application.
- **Persistence:** transactional SQLite v2→v3 migration adds source URLs while
  retaining earlier note IDs, rich-text spans and window preferences.

**Not yet implemented:** RTF/RTFD import/export, arbitrary font selection,
full font-size controls, numbered/bulleted lists, inline PDF page rendering,
true transparent toplevel windows, multi-monitor placement qualification,
external account syncing, automatic browser URL extraction, reminders, or Trash/Archive. The
translucency toggle changes the paper's opacity, not compositor-wide window
alpha. Note deletion remains permanent.

## Supported platforms and integration

| Component | Support |
| --- | --- |
| Debian 13 / GNOME | Target platform; native runtime not yet qualified |
| GTK4 / libadwaita | Declarative GTK4 GUI, majoris-themed note paper |
| SQLite | Local data; schema v3 with transactional migrations |
| [Majoris Image](https://github.com/vovechkin02/Majoris-Image) | Optional GTK4 dependency; image file previews only |
| GNOME Shell | Optional extension; targeted at Shell 48–50, unverified in compositor |
| Internet / account | Not required |

## Dependencies

| Dependency | Minimum | Purpose |
| --- | --- | --- |
| Meson | 1.0 | Build system |
| Ninja, C compiler, `valac` | Toolchain compatible with Debian 13 | Build generated sources |
| GLib / GIO | 2.74 | Persistence, files, D-Bus |
| GTK4 | 4.16 | Text-buffer editing and undo support |
| libadwaita | 1.5 | Application windows and dialogs |
| libgee | 0.20 | Collection models |
| SQLite | 3.35 | Durable note records |
| Majoris Image GTK4 (`majoris-image-gtk4-1`) | Optional | File image preview |

The root `meson.build` is authoritative for build dependencies. The
GNOME Shell extension is optional and must match the specific installed
Shell release. It is not linked into the GTK application's process.

## Build and installation

```sh
meson setup build -Dimagekit=auto -Dshell_extension=false
meson compile -C build
meson test -C build --print-errorlogs
./build/src/majoris-stickies
```

Install the desktop application and AppStream metadata:

```sh
meson install -C build
```

To build on stock Debian 13 without the optional Majoris Image dependency:

```sh
meson setup build -Dimagekit=disabled -Dshell_extension=false
```

Set `-Dimagekit=enabled` to require and use an installed compatible ImageKit
GTK4 package. `-Dshell_extension=true` installs the optional extension files
in the configured system data directory. Enabling the extension is a separate
GNOME Shell operation, documented in [shell/README.md](shell/README.md).

There is no Debian source-package metadata yet; these commands produce and
install a Meson application, not a `.deb`.

## Usage

Launch Stickies from the applications menu or run `majoris-stickies`. The
manager shows searchable note cards sorted by last edit. Create a note with
Ctrl+N, select text and apply formatting, choose colors, or use its options
menu to attach files, import/export text, collapse/expand, toggle translucent
paper, or request Always on Top. Open previously closed notes from the manager.

Use Ctrl+Shift+S to request a screenshot through the desktop portal. Copy Note
exports text plus HTML formatting, and Edit Source URL links a note to an
explicit HTTP(S) page. Color and sort dropdowns filter the manager cards.

The manager's Arrange menu offers Grid, Cascade, By Title, By Date, and By
Color. Always on Top and arrangements require the optional extension. If it
is unavailable, the application reports the error and does not persist a
false successful floating state.

## Data and compatibility

- SQLite database: `$XDG_DATA_HOME/majoris/stickies/notes.db`, defaulting to
  `~/.local/share/majoris/stickies/notes.db`.
- Managed copies: sibling `attachments/` directory, with randomized UUID
  filenames and original display names in SQLite.
- Shell-managed positions: `window-positions.json` in the same data directory,
  written only by the optional extension.
- The schema uses `PRAGMA user_version=3` and upgrades Stage 1 and Stage 2 schemas
  in-place, preserving note IDs and existing content. Databases from newer
  versions are rejected rather than overwritten.
- Back up the **entire directory** after Stickies has exited, to include
  attachments, the database and any WAL/SHM files. A database file alone is
  not a complete note backup when files are attached.

Closing a note window does not delete the note; deleting a note is permanent
and asks for confirmation. A normal note close records the note as no longer
visible. A forced crash can leave a saved visible state to reopen next time.

## Architecture and API

`NoteRepository` owns SQL, attachment metadata, source URL persistence, note
identity and save scheduling. `Note`, `NoteFormatting`, `SourceLink`, and
`NoteTransfer` are GTK-independent. `RichTextCodec`
translates between GTK text tags and style intervals. `NoteWindow` and
`ManagerWindow` own XML-defined presentation. `ShellWindowBridge` is an
optional D-Bus client, while `ScreenshotPortal` provides a separate
permission-mediated D-Bus integration for screenshots. The Shell extension is
a separate compositor module. The application owns the window registry and startup lifecycle.

See [architecture](docs/architecture.md) for module responsibility, database
migration, concurrency boundaries, GoF applicability and reliability.
No stable external Vala/GIR SDK or public cross-process API is provided.
The Shell D-Bus endpoint is a private integration contract; see its README.

## Security and reliability

- SQL queries bind user values; no note body is executed as markup.
- Local files are copied asynchronously into private storage; source and
  completed-copy file sizes are bounded at 50 MiB. Notes do not retain
  arbitrary external file paths for attachments.
- UTF-8 imports reject oversized files, NUL bytes and invalid encoding.
- Formatting runs are bounded, validated and applied using Unicode character
  offsets; corrupted style strings are discarded rather than executed.
- Failed SQL flushes preserve dirty state and normal window close is blocked
  until the user can recover, instead of falsely reporting a successful save.
- Shell actions are limited to recognized Stickies note windows. Compositor
  methods remain **unqualified** pending deployment on the target Shell.
- Large collections and large note bodies can still cause main-context SQLite
  and text formatting latency. Profile real workloads before optimizing.

## Testing and qualification

```sh
meson test -C build --print-errorlogs
python3 tests/integration/test_resource_layout.py data
node --check shell/majoris-stickies@majoris.org/extension.js
```

Vala unit tests cover Stage 1 CRUD/search, Stage 2 formatting and migrations,
and Stage 3 source URL validation, persistence, search, and clipboard export.
Python tests verify UI resources and template fields.

**For this archive:** Python resource integration tests passed (7 tests), and
XML/JSON source files parsed. Vala unit tests, Meson build, GTK rendering,
ImageKit integration, and compositor behavior have **not been run**: this
packaging environment lacks `valac`, Meson, GTK4 and libadwaita development
packages and cannot fetch them.

Further details and required target-machine checks are recorded in
[Stage 3 qualification](docs/stage-3-qualification.md). Do not label this
source release as compiled, runtime-qualified or complete macOS parity.

## Contributing and license

Follow the checked-in [Majoris Engineering Standards v1.8](docs/engineering-standards-v1.8.md)
for Vala `var`, declaration-level Valadoc, formatting, GoF intent, tests,
ownership, and XML layout policy. See [CONTRIBUTING.md](CONTRIBUTING.md).

GPL-3.0-or-later; see [LICENSE](LICENSE). Original source is distributed,
without bundling third-party binaries, image assets or Majoris Image itself.

Stage 3 compatibility and manual screenshot/clipboard qualification are tracked
in [docs/stage-3-qualification.md](docs/stage-3-qualification.md).
