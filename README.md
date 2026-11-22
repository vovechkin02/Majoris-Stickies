# Majoris Stickies

Native, local-first sticky notes for Majoris OS, built with Vala, GTK4, libadwaita,
XML UI templates and SQLite. Stickies combines a centralized notes manager with
independent note windows.

**Version:** 0.9.0 (Stage 9 release-hardening source candidate; native release gate pending)  
**Status:** Pre-release; native Vala compilation, GTK GUI, GNOME Shell integration,
and Debian binaries remain unqualified in this packaging environment  
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

## Stage 9 release-hardening pass (v0.9.0)

This update addresses release engineering and runtime reliability; it does not
claim complete GUI qualification or introduce new note formats.

- Ships a native **Majoris Stickies SVG application icon** in the desktop and
  Debian packages, alongside synchronized version and AppStream metadata.
- Adds a release metadata/native prerequisite preflight (`tools/release_preflight.py`).
  Its strict `--release` gate requires an official maintainer contact and
  installed native dependencies; passing static checks is not a build pass.
- Makes the UI-resource regression tests work under standard Python unittest
  discovery as well as the Meson-provided data-directory argument.
- Extends isolated Xvfb/D-Bus smoke checks to verify note creation in SQLite,
  command-line rejection of invalid actions and preserved note count.
- Cleans up only **stale, owned, private PDF preview directories** left after
  a crash. Unrecognized, fresh, public, or symlinked directories are untouched.
- Constrains the optional extension's Debian dependencies to the GNOME 48–50
  releases currently declared in its metadata. GNOME 51 is not presumed safe.
- Leaves SQLite schema v5, existing notes, formatting, attachments, and exchange
  formats unchanged. Majoris Image remains the sole image preview provider.

**Qualification status:** This build environment has no Vala compiler, Meson,
GTK development libraries, or working Debian repository DNS. The source tests
run, but the native executable, ImageKit-enabled build, Xvfb smoke test,
GNOME Wayland extension behavior, Orca accessibility, and .deb package build
remain **not run**. Do not distribute as a verified stable ISO component until
those checks pass and the official packaging maintainer contact is provided.

See [`docs/stage-9-qualification.md`](docs/stage-9-qualification.md).

## Stage 8 final pass (v0.8.2)

This update expands the v0.8.1 implementation without changing the on-disk
SQLite schema (still v5), note IDs, image attachment storage, or backup schema.

- **Import safety:** Plain-text imports validate the editor revision and the
  originally displayed text/formatting before replacing the note. RTF/RTFD
  operations retain their existing revision guards.
- **RTFD metadata:** The bounded package validator now checks every manifest
  attachment against the validated asset set, rejects duplicate/mismatched
  identities, traversal and invalid MIME/name pairs, and preserves original
  Unicode filenames and MIME types on import. Legacy packages lacking the
  optional Majoris manifest remain importable with generated names.
- **Positioned images:** A new Insert Image at Cursor command stores an image
  through the existing managed attachment repository and adds a GTK text child
  anchor at the insertion position. Rendering uses Majoris ImageKit if built
  with `majoris-image-gtk4-1`; otherwise an inline placeholder is shown.
  The preview can be resized to 160, 240, or 320 pixels. The position is a
  Unicode object character with a validated `image_<UUID>_<width>` style span.
  Note duplication remaps these references to the copied attachments.
- **Text styles:** GTK installed-font and text-color dialogs provide bounded
  persistent font-family, point-size (8–72), and RGB tags. Original presets
  are retained for compatibility.
- **List editing:** Paragraph list-kind tags supplement the existing portable
  textual bullets, numbers, and checkboxes. Pressing Return continues a list
  and an empty list marker ends it. List markers remain plain text, not an
  independent nested-document tree.

**Limits:** This is not full Cocoa RTFD fidelity, unlimited image sizing, image
cropping, or a general-purpose rich-document editor. RTF/RTFD export preserves
its documented subset; newly chosen dynamic font/color styles and inline
anchor placement are Majoris-native and are not losslessly represented in
external RTFD. Inline media is not embedded in rich clipboard exports. Full
native Vala compilation and GNOME runtime validation are still required.

See [`docs/stage-8-final.md`](docs/stage-8-final.md) for implementation and
qualification details.

## Features and scope

Stage 1 remains supported:

- Multiple separately editable notes, color palettes, centralized searchable note
  cards, create, duplicate, Trash (with separate permanent deletion), autosave, and
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
  RTF/RTFD interchange was not implemented in Stage 2.
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

Stage 4 adds:

- **Accessible interface:** XML-declared accessible names for icon-only actions,
  note title/body, filtering, search, and the manager's result controls.
- **Scalable manager:** Only the first 60 matching note cards are constructed;
  subsequent pages load on request. Search, filter and sort changes reset the
  page, while note edits preserve the requested number of visible cards.
- **Recovery:** `majoris-stickies-backup` creates SQLite-consistent ZIP backups
  including managed attachments and saved window positions; `verify` checks hashes, SQL integrity and
  attachment references; `restore` writes into a **new** directory, never
  silently overwriting an existing user database.
- **Persistence:** SQLite quick-check before migrations, limited write retries
  with backoff, and previously established dirty-state retention on failure.
- **Multi-monitor:** The optional extension restores notes to surviving monitor
  work areas, clamps offscreen positions, handles topology changes, and
  arranges notes separately on each monitor.
- **Packaging:** Meson installation for the recovery tool and Debian package
  recipes for the application and optional Shell extension. The schema stays
  at v3 during Stage 4; Stage 5 adds a new migration.

Stage 5 adds:

- **Reminders:** One-shot per-note reminders for 10 minutes, one hour, or
  tomorrow at 9:00 AM; cancel/reset; persisted `remind_at_us` and notification
  delivery markers; local desktop notifications are polled while Stickies runs.
  Reminders do **not** run when the application is closed, and there are no
  always-on background jobs or network requirements.
- **Handwriting:** Draw with pointer, pen, or touch drag gestures on a bounded
  640×360 canvas, clear strokes, and attach the drawing as inert vector SVG.
  No pressure-sensitive brush simulation or OCR is implemented. Majoris Image
  remains the existing attachment preview provider when installed.
- **Sharing:** Save safe formatted HTML from a note window, or create a
  `.stickies` ZIP bundle containing precisely one note and its managed files.
  Share bundles carry SHA-256 integrity metadata and reject extra archive paths.
  The note menu runs the separately packaged exchange helper asynchronously.
- **Optional folder synchronization:** `majoris-stickies-exchange sync` exchanges
  portable note bundles through a **user-chosen local directory**, including a
  directory synchronized by another program. It requires Stickies closed and
  explicit `--app-closed` confirmation; conflicting edits produce independent
  note copies. No account, automatic cloud upload, server, polling, or background
  synchronization is installed. Shared folder files are **not encrypted**.
- **Database migration:** The Stage 4 v3 database is upgraded transactionally
  to schema v4, adding reminder deadline and delivery columns. The existing
  note IDs, formatting, attachments, source URLs, and desktop-window state remain.

Stage 6 adds (schema v5):

- **Note organization:** All Notes / Pinned / Archive / Trash views, reversible
  Archive and Trash actions, restore, and permanent deletion only after a second
  explicit confirmation. Pinned notes sort first in the default list. Note data
  and attachments survive status changes.
- **Complete duplication:** An asynchronous managed-attachment copy now includes
  images and PDFs, retaining original MIME metadata rather than re-guessing the
  type from private `.asset` filenames. Incomplete copies roll back.
- **Expanded formatting:** Selectable Sans / Serif / Monospace fonts, seven
  explicit point sizes, three text colors, three alignment styles, clear
  selected formatting, literal find/replace, and portable text-based bullets,
  numbered lists, and checklists. These options use bounded and validated
  persisted style tokens; they are not an arbitrary font/color chooser or a
  semantically structured rich-list format.
- **Desktop options:** Show/Hide All Notes commands, default new-note color
  preset, optional XDG autostart entry with an explicit UI toggle, and GTK4
  drag-and-drop of up to sixteen
  image/PDF files per action. The attachment store retains its existing limits.
- **Exchange and backups:** Schema v5 stores note `status` and `pinned` fields;
  Stage 5 local databases and bundles are still supported by the exchange
  tool. Archived/pinned notes carry their lifecycle flags in v5 bundles. The
  backup tool accepts both older and v5 databases.

Stage 7 adds (schema v5 unchanged):

- **RTF export:** A bounded, Unicode-safe, local `.rtf` exporter for a note's
  title, plain-text body, and the supported font, size, color, and inline
  formatting tags. Available from each note's menu and via the installed
  `majoris-stickies-rtf` CLI. Rejects malformed style ranges and existing output
  paths. Attachments are **not** embedded; RTF import and RTFD interchange
  remain unimplemented. Rich RTF export uses a read-only SQLite snapshot after
  flushing pending edits. It never modifies the note or its attachments.
- **Reminder reliability:** Submission to GApplication notifications precedes
  the durable notified marker, so a failure to mark cannot preempt sending.
  The desktop notification server does not provide guaranteed delivery
  acknowledgment; repeating a submission remains possible if saving fails.
- **Release qualification:** A headless GTK/X11 start-and-activation smoke
  runner, Debian binary package CI gate, installed-helper consistency checks,
  and new RTF regression tests. Native compilation and runtime verification
  still require a Debian 13 environment with the full SDK. Stage 7 is not
  claimed as a build-verified release in this archive.

Stage 8 (updated in v0.8.1, SQLite v5 unchanged) adds:

- **RTF import:** Unicode-aware bounded parsing of explicitly supported text
  styles. Font and color tables are now interpreted by their declared entries;
  unknown colors are left unstyled rather than misclassified. Async imports
  refuse to replace an editor modified during conversion.
- **RTFD-style folders:** Export and import `TXT.rtf` with managed image/PDF
  attachments using `majoris-stickies-rtfd` and the note menu. Exports create
  new `.rtfd` directories only. File counts, sizes and symlinks are validated.
  This is **limited directory interchange**, not lossless native macOS
  `NSFileWrapper`/RTFD import, nor image placement at exact cursor offsets.
- **PDF page previews:** Previous/Next controls render individual pages 1–250
  through bounded Poppler processes; Majoris Image handles the resulting PNG
  display only. Temporary pages are removed after image loading completes.
- **Desktop integration:** `--show-notes` opens note windows (up to 64), instead
  of opening only the manager. The optional Shell extension can set true
  whole-window opacity for registered Stickies windows, retaining a paper-only
  fallback if it is unavailable. Workspace visibility and saved arrangements
  remain compositor-owned.
- **Editing:** Checklists are clickable at their glyphs in the GTK editor;
  selected paragraphs can be indented or outdented. These remain plain-text
  list constructs, **not** semantically structured nested list objects.

**Still not fully implemented:** Unrestricted fonts and point sizes/colors,
semantic structured lists, positioned inline images, full macOS RTFD fidelity,
image markup/cropping, complex PDF navigation or annotation, browser source
capture, and account-managed background sync. Majoris Image and GNOME runtime
integration require native qualification. Ordinary image decoding is always
left to **Majoris Image**; no competing image renderer has been introduced.

### Export formatted RTF

The note's **Export Rich Text (RTF)** command creates a new `.rtf` file and
preserves supported text formatting. The installed helper can be used directly:

```sh
majoris-stickies-rtf --data-dir "$HOME/.local/share/majoris/stickies" \
  NOTE_UUID /path/to/new-note.rtf
```

Only active notes are exported. The output file must not already exist.
The standalone RTF exporter writes text only; the separate Stage 8 RTFD
command transfers attachments as safe neighboring files. Both leave SQLite
unchanged and use only Python standard-library modules.

## Supported platforms and integration

| Component | Support |
| --- | --- |
| Debian 13 / GNOME | Target platform; native runtime not yet qualified |
| GTK4 / libadwaita | Declarative GTK4 GUI, majoris-themed note paper |
| SQLite | Local data; schema v5 with transactional migrations; no Stage 7 database migration |
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

The source also includes Debian packaging metadata for separate application
and GNOME Shell extension packages. On Debian 13 with build dependencies:

```sh
dpkg-buildpackage -b -us -uc
```

Debian packaging uses `-Dimagekit=auto` to retain Majoris Image previews when
its GTK4 development interface is installed. For a Majoris ISO builder that
requires image previews, use `IMAGEKIT=enabled dpkg-buildpackage -b -us -uc`
after installing the compatible Majoris Image development package.

**Release gate:** Replace the explicit placeholder packaging maintainer contact,
then inspect packages with Lintian, install/remove tests, and validate the
GNOME Shell extension against the Majoris desktop build. No `.deb` has been
compiled or qualified in the current environment.

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

### Stage 5 sharing and optional synchronization

In a note's **More** menu, choose **Set Reminder**, **Draw with Pen**,
**Export Formatted HTML**, or **Share Note with Attachments**. HTML is a text
export and does not embed private attachment bytes. The `.stickies` bundle
includes one note's attachments; inspect its contents before sending it to
anyone. Avoid storing shared bundles in public locations.

To list IDs and share one note from the terminal:

```sh
majoris-stickies-exchange list
majoris-stickies-exchange share NOTE_UUID /path/to/new-note.stickies
```

To exchange notes between machines, first arrange for both devices to access
one shared folder, for example via a trusted file-sharing service. **Close
Stickies before running the command on each device:**

```sh
majoris-stickies-exchange sync /path/to/shared-folder --app-closed
```

To receive a shared note without configuring a synchronization folder,
close Stickies and run:

```sh
majoris-stickies-exchange import /path/to/shared-note.stickies --app-closed
```

If its ID already exists with different content, the import keeps the original
and creates a separate conflict copy. Otherwise the note is added and will
appear when Stickies next opens.

The first folder-sync run publishes existing notes or imports remote notes. Repeat on the
other device after edits. If both sides changed a note, the tool preserves the
local edit as a separate **Conflict copy** and receives the remote revision.
A `.stickies-sync.lock` file guards simultaneous local commands, but is not
an inter-machine cloud lock: do not synchronize both devices concurrently.
**Deletions are deliberately not propagated**; deleted notes may reappear
when an old bundle is still shared. Delete bundles manually when all devices
agree. Synchronization does not automatically begin when Stickies starts,
does not use a Microsoft/Apple account, and does not encrypt the shared files.

Before the first sync or import, run `majoris-stickies-backup create` and keep a
verified copy offline. `sync-state.json` stores last-agreed revision hashes in
the local note directory; it contains no full note contents. Use each device's
own data directory, not a shared SQLite database.

### Stage 8: text interchange, desktop controls and lazy previews

- **RTF import:** the `majoris-stickies-rtf-import` helper parses a bounded,
  text-only RTF subset into UTF-8 and validated application-owned formatting
  spans. The GTK editor can import that content without writing outside the
  currently selected note. It preserves supported font, emphasis, size, color,
  and alignment tokens but skips metadata and unsupported RTF objects.
  This is *not* lossless Apple RTFD interchange; the v0.8.1 RTFD-style
  folder workflow preserves compatible text and media as separate files.
- **Find and replace:** the repeatable, nonmodal search window supports
  case-sensitive or case-insensitive literal search, replacement and replace-all.
  **Checklists** can be toggled with Ctrl+Enter or the note menu. List prefixes
  remain text; this is not a nested document/list object model.
- **Desktop windows:** at most 64 independent note windows open simultaneously,
  consistent with the optional Shell extension. Other notes remain in the
  manager. The extension adds *Toggle All Workspaces* and *Restore Saved
  Layout*. All-workspace state lives in the extension's layout JSON, not a new
  SQLite column; shell-dependent commands fail explicitly without it.
- **Image previews:** the attachment UI now allocates an `ImageKit.ImageView`
  only when its preview is expanded. No alternative image decoder was added.
- **PDF preview:** when the installed Majoris Image component and optional
  `poppler-utils` are available, expanding a PDF attachment renders just the
  requested page (1–250) to a size-limited, private PNG via bounded Poppler.
  ImageKit displays that PNG; temporary files are cleaned up on normal close.
  The PDF itself remains a managed attachment, not an inline editable object.
- **Compatibility:** existing schema v5, UUIDs, attachment hashes, share bundles,
  backup/restore formats and original supported GTK styling tokens are unchanged.
  Native Vala, GNOME Shell and ImageKit qualification is **outstanding**.

## Data and compatibility

- SQLite database: `$XDG_DATA_HOME/majoris/stickies/notes.db`, defaulting to
  `~/.local/share/majoris/stickies/notes.db`.
- Managed copies: sibling `attachments/` directory, with randomized UUID
  filenames and original display names in SQLite.
- Shell-managed positions: `window-positions.json` in the same data directory,
  written only by the optional extension.
- The schema uses `PRAGMA user_version=5` and upgrades Stage 1–5 schemas
  in place, preserving note IDs and existing content. Databases from newer
  versions are rejected rather than overwritten.
- The installed `majoris-stickies-backup` command creates a consistent
  SQLite snapshot (including committed WAL transactions) and bundles all
  referenced attachments. It can run while Stickies is editing notes;
  unsaved in-memory changes remain subject to the normal autosave interval.
- Back up a copy of the entire data directory if recovering manually; a bare
  `.db` may omit both attachment files and uncheckpointed WAL transactions.
  For a controlled backup, use the utility described below.

Closing a note window does not delete the note. Ordinary deletion moves it to
Trash; permanent deletion requires a separate confirmation. A normal note close records the note as no longer
visible. A forced crash can leave a saved visible state to reopen next time.

### Back up and restore

```sh
majoris-stickies-backup backup ~/stickies-backup.zip
majoris-stickies-backup verify ~/stickies-backup.zip
# Quit Stickies before restoration; use a new directory to inspect contents.
majoris-stickies-backup restore ~/stickies-backup.zip ~/stickies-restored
```

The restore command **refuses to overwrite** an existing directory. After
checking restored notes and attachments, stop Stickies and manually move the
original application data directory aside before installing the restored data.
The backup archive contains private notes and must be protected accordingly.
The utility requires only Python 3 with standard-library SQLite support.

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
- Failed SQL flushes preserve dirty state, trigger at most three short
  exponential retries per edit, and block normal note-window close until
  saving succeeds. Database integrity is checked before attempting migrations.
- Backup archives are SHA-256 verified, bounded, restricted to validated
  UUID filenames, and can only restore to a fresh directory.
- Shell actions are limited to recognized Stickies note windows. Compositor
  methods remain **unqualified** pending deployment on the target Shell.
- A manager refresh constructs at most the requested page of note cards;
  matching and sorting still scan in-memory notes. Large note bodies can
  cause main-context SQLite and text formatting latency. Profile real workloads
  before optimizing further.

## Testing and qualification

```sh
python3 tools/release_preflight.py
meson test -C build --print-errorlogs
python3 -m unittest discover -s tests/integration -p 'test_*.py'
python3 tests/integration/test_resource_layout.py data
node --check shell/majoris-stickies@majoris.org/extension.js
node --experimental-default-type=module tests/integration/test_layout.mjs
python3 -m unittest discover -s tests/recovery -p 'test_*.py'
python3 -m unittest discover -s tests/integration -p 'test_stage*.py'
python3 tools/check_source_docs.py
```

Vala unit tests cover Stage 1 CRUD/search, Stage 2 formatting and migrations,
Stage 3 source URL validation, persistence, search and clipboard export, and
Stage 4 database integrity and large-collection behavior, and Stage 5 reminder
and schema upgrades. Python tests verify
UI resources, accessibility annotations, and eight backup/recovery cases, plus nine exchange tests. A
separate pure-JavaScript suite checks multi-monitor placement geometry.
Stage 8.1 additionally exercises declared RTF font/color tables, safe RTFD
folder round-tripping, Poppler page-two rendering, installed Python helper
filenames, and shell opacity/launcher contracts without claiming native GTK
runtime verification.

**For this archive:** resource XML, backup/restore and shell layout tests
run in the available tools. Meson, Vala unit tests, native GTK rendering,
ImageKit, actual compositor behavior, and Debian package builds **have not
been run**: this environment has no Vala/GTK/libadwaita build toolchain.
Static checks do not establish native compilation or runtime correctness.

Further details and required target-machine checks are recorded in
[Stage 8 completion qualification](docs/stage-8-completion.md). Do not label this
source release as compiled, runtime-qualified or complete macOS parity.

## Contributing and license

Follow the checked-in [Majoris Engineering Standards v1.8](docs/engineering-standards-v1.8.md)
for Vala `var`, declaration-level Valadoc, formatting, GoF intent, tests,
ownership, and XML layout policy. See [CONTRIBUTING.md](CONTRIBUTING.md).

GPL-3.0-or-later; see [LICENSE](LICENSE). Original source is distributed,
without bundling third-party binaries, image assets or Majoris Image itself.

Stage-specific changes and required acceptance checks are recorded in
[Stage 9 qualification](docs/stage-9-qualification.md). Earlier Stage 3
screenshots and clipboard behavior remain documented in
[Stage 3 qualification](docs/stage-3-qualification.md).
