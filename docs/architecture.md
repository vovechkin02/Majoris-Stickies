# Architecture and design decisions — Stages 1–4

## Scope and module responsibilities

```text
StickiesApp (actions, window registry, startup restoration)
  ├── ManagerWindow (search, cards, arrangement menu)
  ├── NoteWindow (one GTK editor per note; user actions)
  │      ├── RichTextCodec (GTK tags ↔ UTF-8 character-offset spans)
  │      └── ImageKit.ImageView (optional installed GTK4 component)
  ├── ShellWindowBridge (optional GNOME Shell D-Bus boundary)
  └── NoteRepository (single data owner; debounced commits)
         ├── Note (text, formatting, color, window prefs)
         ├── NoteFormatting (strict rich-text input contract)
         ├── NoteAttachment (managed file descriptor)
         ├── SQLite (notes and attachment records)
         └── attachments/ (managed image and PDF copies)

GNOME Shell extension (separate compositor module)
  └── Registered Stickies note windows, positions, stacking and layout
```

The Vala domain model has no GTK dependencies. The manager and editor share the
same repository and observe its native GObject signals. Attachment changes are
notified separately to avoid reconstructing image viewers on text edits.

## Storage schema and migration

The Stage 1 `notes` table, with note UUID, title, content, color and timestamps,
is upgraded **in-place** to Stage 2 inside a SQL transaction. New columns:

| Column | Type / default | Meaning |
| --- | --- | --- |
| `formatting` | TEXT `''` | `start:end:style` half-open Unicode runs |
| `collapsed` | INTEGER `0` | Note paper hidden |
| `floating` | INTEGER `0` | Shell-managed always-on-top preference |
| `translucent` | INTEGER `0` | Paper opacity preference |
| `window_width` | INTEGER `370` | Noncollapsed logical pixel width |
| `window_height` | INTEGER `330` | Noncollapsed logical pixel height |
| `visible` | INTEGER `0` | Whether to reopen editor after startup |

New table:

```sql
CREATE TABLE attachments (
    id TEXT PRIMARY KEY NOT NULL,
    note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    mime_type TEXT NOT NULL
);
CREATE INDEX attachments_note_idx ON attachments(note_id);
PRAGMA user_version=2;
```

On a new database the original Stage 1 columns are created and upgraded to v2.
Unknown newer schema versions are rejected. Existing note IDs, timestamps and
colors are unchanged. Attachment file names are UUID-derived, never blindly
loaded from SQL paths.

## Rich text and images

`RichTextCodec` translates between supported GtkTextTags and bounded serialized
spans. Style offsets are Unicode **characters**, not UTF-8 byte positions.
GTK-native formatting state is not persisted directly. The supported styles
are bold, italic, underline, strikethrough, monospace, large and small.
Note content changes and serialized formatting are committed together.

Majoris Image's installed `ImageKit.ImageView` handles decoding and display
of image attachments when built with `-Dimagekit=enabled` or `auto` and an
installed compatible package. This app deliberately does not invent image
loaders or use GTK's regular image-file decoder as a fallback. Without the
library it displays a file card with an image icon. PDFs are managed file
cards that open in the default viewer, not embedded page renderers.

## Desktop and compositor ownership

On Wayland, GTK4 clients cannot position windows or mark them always on top
using the removed X11-era window APIs. A small, optional GNOME Shell extension
owns placement, layouts, and stacking. The application calls an adapter
`ShellWindowBridge` with a private typed D-Bus interface. The compositor only
accepts windows verified as Stickies GTK note windows. User preferences for
floating are saved **only after the compositor confirms the request**.

When active, the extension writes note UUID→rect mappings into a private JSON
file in the Stickies data directory, clamps restored coordinates to monitor
work areas and supports grid, cascade and ordered layouts. The GNOME Shell
extension is a separate deployment artifact and must be qualified on the
shipping GNOME Shell release; the application must remain functional without
it. `paper_box.opacity` is a GTK child property and does not turn the outer
window translucent.

## Lifetime, I/O and errors

- Note creation and row updates are on the GTK main context, with a 500 ms
  debounce per note. A window flushes before successful close; failures keep
  edits in memory and are shown to the user.
- Attachments are asynchronously copied with `GFile.copy_async`. The file is
  checked before and after copying; its metadata row is inserted only once the
  private copy has succeeded and remained within bounds. A failed insert
  removes the new file. Deletion removes database metadata before trying to
  delete the managed file; a filesystem failure may leave an orphan but not
  an SQL pointer to a missing file.
- Plain-text file selection and read/write use async Gio APIs. The import
  is bounded, UTF-8 validated and rejects NUL bytes; it deliberately resets
  existing formatting. Export is a plain-text snapshot.
- Each editor owns one cancellable for its file actions and cancels it on
  successful close. Editor and manager subscriptions are disconnected on
  close. The application owns the registry of open windows.
- Many editor windows or huge notes may require additional profiling before
  increasing scope. Fast local SQL and in-memory Unicode search remain
  intentional for short desktop notes; no unnecessary worker system is added.

## Gang of Four design review

| Decision | Participants | Why |
| --- | --- | --- |
| Observer using GObject | `NoteRepository` signals, subscribers in editor/manager | Native event delivery; not a second custom event bus |
| Facade | `NoteRepository` CRUD and save operations | Stable domain entry point over SQLite and timer state |
| Adapter | `ShellWindowBridge` ↔ GNOME Shell D-Bus | Translates a compositor-specific interface to app operations |
| No arbitrary Factory or Strategy | Single SQLite backend and fixed editor | No independently varying concrete implementation exists |

The shell bridge's optional behavior is explicitly reported; no silent
fallback claims compositor success. No public SDK or ABI change is implied by
these private Stage 2 modules.

## Open qualification risks

- Compile and inspect Vala ownership, GtkTextBuffer tags, DBus argument types,
  XML template bindings and `ImageKit.ImageView` under the actual Debian 13
  SDK and installed Majoris Image version.
- Run normal and failed-save shutdown scenarios, including GNOME logout.
- Validate compositor positioning, window identification, multi-monitor
  work areas and GNOME extension lifecycle on the exact Majoris Shell build.
- Test filesystem failure, large attachment growth during copy, malformed
  formatting strings and Unicode selection on the target GTK runtime.

See `docs/stage-2-qualification.md` for executable commands and recorded
verification evidence.

## Stage 3: screenshots, web sources and clipboard (0.3.0)

- `ScreenshotPortal` is an asynchronous adapter to `org.freedesktop.portal.Screenshot`
  and the `org.freedesktop.portal.Request::Response` contract. The portal, not
  the application, owns the screenshot authorization UI. The adapter enforces
  one active request, a finite wait, denial semantics and D-Bus cleanup.
- `SourceLink` validates HTTP(S) URLs at the domain boundary. `NoteRepository`
  owns the SQLite v3 migration and persists one source URL per note. The
  `Note` model retains the source URL with edit timestamps.
- `NoteTransfer` exports both sanitized HTML and plain text, applying existing
  formatting intervals as nested tags without duplicating GTK widgets or
  copying private file paths into the clipboard. The application is responsible
  for the `Gdk.ContentProvider` lifetime, not the core model.
- `ManagerWindow` controls presentation-only color and order selection; the
  repository remains the authoritative in-memory source of note records.
- Command-line desktop actions use GApplication's single-instance routing.

**GoF review:** ScreenshotPortal is a boundary adapter for the portal D-Bus
contract (not a generic screenshot Strategy). GObject signals retain their
normal observer semantics. SourceLink and NoteTransfer are cohesive utilities,
not artificial Factories or Singleton services. No new pattern abstraction was
introduced without a real independent variation point.

**Compatibility:** Stage 3's additive SQLite migration does not rename earlier
columns, existing GObject properties, application IDs, schemas, or Shell D-Bus
methods. The source URL is optional and defaults to empty on older notes.

## Stage 4: reliability, accessibility and distribution (0.4.0)

- `NoteRepository.verify_integrity()` rejects corrupt SQLite storage before
  changing the schema. Dirty-state writes are retried up to three times after
  a timeout error (2/4/8 seconds); exhausted retries leave the note dirty and
  the existing close guard reports the failure. No new database migration is
  introduced. These retries do not replace a durable backup strategy.
- `ManagerWindow` uses 60-card pages rather than allocating one GTK widget tree
  per matching note. The repository retains in-memory search and sort, so this
  is **widget allocation reduction**, not claimed full search virtualization.
- GtkBuilder accessibility labels give icon-only controls, text editors,
  filters and counters clear names without a custom AT-SPI bridge. Full Orca
  and keyboard qualification must still run in the target session.
- `shell/.../layout.js` owns pure monitor geometry calculations, selected from
  persisted work-area geometry rather than monitor ID. `extension.js` owns
  Mutter signals and operations, splits arrangement by each active monitor,
  and clamps moved/offscreen notes after topology changes. The stored JSON
  format remains compatible; new records gain optional `monitorArea` metadata.
- `tools/stickies_backup.py` creates a consistent SQLite backup using the
  Python stdlib `sqlite3.Connection.backup()` API and includes referenced
  attachment content. It verifies hashes, UUID-only ZIP paths, SQLite
  integrity and foreign keys, and restores exclusively to a new private
  directory. The tool is **offline during restore** and never modifies the
  running application's database in place. This is not automatic cloud sync.
- Debian packaging splits the optional GNOME Shell extension from the GTK
  application and includes the backup executable. Package removal does not
  delete the user's `XDG_DATA_HOME` note directory. No shared library ABI or
  external protocol change is introduced.

**Design-pattern review:** GObject signals remain the observer mechanism;
`NoteRepository` retains one domain-focused persistence facade; the optional
shell bridge is an adapter across the compositor boundary. The pure
placement module is a calculation helper, not an unjustified Strategy or
state-machine framework. The Python recovery CLI is an offline maintenance
utility; it is not a second runtime repository provider.

**Qualification limits:** Toolchain compilation, package installation, Orca,
large-window runtime measurements and Mutter multi-monitor behavior must be
executed in the Debian 13 / Majoris GNOME environment. See
`docs/stage-4-qualification.md`.

## Stage 5: optional exchange, ink, reminders, and sharing (0.5.0)

- `Note` and `NoteRepository` own deadline/delivery-marker state. An additive,
  transactional SQLite v3→v4 migration introduces `remind_at_us` and
  `reminder_notified_at_us` without changing user or attachment identities.
  `StickiesApp` polls due notes at 30-second intervals only when running;
  markers are saved before `GApplication.send_notification()` is called.
  Notifications are one-shot, best-effort desktop messages, **not** a
  persistent system alarm service or off-process background agent. The
  application does not initiate network traffic to schedule reminders.
- `InkCanvas` owns bounded in-memory strokes captured by `Gtk.GestureDrag`,
  with a fixed-size Cairo preview and a numeric-path-only SVG exporter.
  The drawing editor delegates attachment persistence to
  `NoteRepository.attach_file()`. No new image decoder or SVG rendering path
  is introduced; previews remain delegated to Majoris Image when available.
- `NoteTransfer` still owns clipboard/HTML escaping. `NoteWindow` adds
  asynchronous HTML export and launches a separate, opt-in
  `majoris-stickies-exchange` process to create one-note `.stickies` bundles.
  The Python share/import/exchange command uses SQLite snapshots, checks ZIP members,
  validates SHA-256 attachments, and does not include unrelated notes.
- The opt-in Python folder sync service owns the shared-file protocol. It uses
  deterministic, content-derived note revision hashes, independent of local
  attachment UUIDs and window geometry. `sync-state.json` tracks last-agreed
  revisions. When local and remote revisions both diverge, it creates a
  separately identified conflict copy instead of discarding either edit.
  A local advisory file lock prevents concurrent processes on the same machine.
  This is a **manual, app-closed, folder-based exchange**, not an always-on
  cloud provider integration. No remote deletion propagation or encryption is
  promised.

**GoF evaluation:** `NoteRepository` remains the domain-level persistence
facade; native GObject signals are used for observations. The exchange tool
is a separate offline protocol adapter, not a replacement for the runtime
repository, and `InkCanvas` is a narrowly scoped presentation widget. Neither
requires fabricated Strategy, Factory, Singleton or Command hierarchies.

**Ownership and safety:** A note window cancels its pending file-dialog/export
operations on close. Export helpers do not receive arbitrary shell commands or
untrusted executable paths. Shared files are input data only, with bounded
sizes and validated UUIDs. The user must explicitly close the application
before any other process imports updates into the SQLite database. Developer
native build and GNOME Shell runtime qualification remain outstanding.

## Stage 6: note organization and editor commands (0.6.0)

SQLite v5 migrates existing v4 notes in a transaction, adding `status` with
0=active, 1=archived, 2=trashed, and `pinned` with 0/1 semantics. These fields
are deliberately not coupled to window visibility. Archive, Trash and Restore
preserve UUIDs, attachments, rich text, reminders, and source URLs. A distinct
confirmed permanent-delete action removes the row and its managed attachment
references. The manager shows explicit lifecycle filters.

`NoteRepository.duplicate_complete()` copies managed attachments with GIO
asynchronous file I/O; the private `.asset` suffix must not be used to infer
media type. The existing repository metadata is the source of truth. Error
handling rolls back the incomplete duplicate instead of silently returning a
text-only copy. `duplicate_note()` remains for compatibility with existing
internal callers; UI duplication uses `duplicate_complete()`.

`TextEditCommands` owns GTK buffer editing (text lists, find/replace, clearing
selected tags). `RichTextCodec` owns style tags and serialization, preserving
the domain/editor boundary and avoiding a second formatting model. Its tag
iteration now advances between tag boundaries instead of scanning all
characters for every tag. Vala and GTK build/runtime qualification remains
necessary to establish this performance improvement on the target platform.

`StartupPreferences` manages a single user-approved XDG autostart entry and
refuses to overwrite unknown or symbolic-link files. It never creates a system
service or starts network synchronization. GTK4 file drag-and-drop delegates
all file size/MIME validation to `NoteRepository.attach_file()`.

The Stage 5 single-note exchange format remains compatible for ordinary active,
unpinned notes. Stage 6 extends the same versioned manifest with optional v5
lifecycle fields only when a note is archived, trashed or pinned; old manifests
are normalized to status=active and pinned=false on import. Older applications
cannot interpret v5 lifecycle flags, which is why the exchange tool rejects
unsupported states when importing into a v4 database.

**Unimplemented parity:** RTF/RTFD, inline image layout and PDF page rendering,
compositor-wide transparency, all-workspace sticky windows, custom colors and
unrestricted fonts remain out of scope for this actual implementation. This
repository must not be represented as fully parity-complete before those
features and native qualification are delivered.

## Stage 7 — Interchange and native release boundaries

- `tools/stickies_rtf.py` is a narrowly scoped read-only RTF serializer, not
  a general interchange engine. The GTK-facing `RtfExporter` initiates it
  asynchronously **after** flushing the active note, without embedding file
  I/O and RTF escaping inside `NoteWindow`. The output uses escaped ASCII,
  Unicode UTF-16 fallback controls, balanced groups, bounded style intervals,
  and exclusive file creation. It does not decode attachments or change SQLite.
- The helper-process boundary is an ordinary integration adapter; it is **not**
  falsely classified as GoF Proxy or Strategy. The app still owns the note and
  the note repository still owns persistence. Cancellables bound the child
  wait; the helper validates its local inputs independently.
- Existing note and share identities, file paths, SQLite schema v5, and
  attachment format are unchanged. Majoris Image remains the optional image
  renderer; no alternative image decoder has been introduced.
- The Debian 13 CI job now requires native compilation, unit/integration tests,
  an Xvfb activation smoke run, and binary package construction. Failure of any
  gate must prevent tagging a build-qualified release. The GNOME Shell and
  native HDR/Wayland/ImageKit runtime paths require a target desktop session.
