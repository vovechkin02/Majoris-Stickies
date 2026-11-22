# Architecture and design decisions — Stage 2

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
