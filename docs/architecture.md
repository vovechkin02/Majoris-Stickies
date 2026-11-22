# Architecture and design decisions — Stage 1

## Scope and responsibility

Stage 1 establishes a functional local note editor and manager while intentionally
excluding image attachments, rich text, desktop Shell controls, and synchronization.
The only reusable domain objects are `Note`, `NotePalette`, and `NoteRepository`.

```text
StickiesApp (actions, window registry)
  ├── ManagerWindow (card list, search, actions)
  └── NoteWindow per open note (title, body, palette, save status)
        │
        └───────── NoteRepository ── SQLite notes table
                       │
                       └── Note (plain data, validated color)
```

`NoteRepository` is the one source of truth for note state. UI widgets call the
repository for edits and react to its native GObject signals. The repository
stores edited notes to SQLite 500 milliseconds after the most recent edit per
note. It writes a newly created or duplicated note immediately. A final flush
occurs when a note editor/manager closes and during application shutdown.

The UI uses an in-memory, sorted snapshot for case-folded Unicode search. This
simplifies the first stage. If profiling later shows performance bottlenecks,
consider a database-backed FTS5 index and an asynchronous or virtualized list.

## Storage schema and versioning

```sql
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    color TEXT NOT NULL,
    created_at_us INTEGER NOT NULL,
    updated_at_us INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS notes_modified_idx ON notes(updated_at_us DESC);
PRAGMA user_version=1;
```

IDs use GLib UUIDs. Timestamps are Unix microseconds. The `color` column stores
one of the eight tokens defined by `NotePalette`, not CSS hex colors. A future
schema migration must increment `user_version` without silently overwriting or
downgrading newer schemas.

## GoF design review

| Pattern/idiom | Participants | Rationale |
| --- | --- | --- |
| Observer (GObject-native) | Repository signals / manager and editor subscriptions | GTK-native notifications, no custom event bus |
| Facade (small, domain-oriented entry point) | `NoteRepository` CRUD/search/flush methods | Hides storage and debouncing from the UI; not a general service locator |
| No other GoF pattern | Small, fixed backend and one presentation technology | No meaningful variant justifies a Factory, Strategy, or State hierarchy |

All repository callbacks are run on the GTK main context. Editor and manager
subscriptions are disconnected on successful close to avoid reference cycles.
The application owns each open editor window, keyed by note UUID. The manager
can close independently of editors. The model and repository have no GTK import.

## Persistence and failure handling

- `INSERT ... ON CONFLICT` stores complete note records atomically.
- All note data uses SQLite parameter binding; none is interpolated into SQL.
- Successful flushes clear dirty state and emit `note_saved`.
- Failed flushes leave records dirty, emit `save_failed` for debounced saves,
  and refuse ordinary editor or manager closure until storage is writable.
- Delete is explicitly permanent in Stage 1 and is confirmed before execution.
- A close during a failed save is rejected, enabling users to copy their text.
- The current main-context SQLite design is suitable for short, personal notes,
  not an unbounded database. Large datasets and slow disks require profiling and
  an asynchronous implementation before scaling.

## External integrations

Majoris Image is deliberately not linked while Stage 1 uses only plain text.
When later stages add embedded images, consult the ABI 2 `ImageKitView`
consumer integration guide in https://github.com/vovechkin02/Majoris-Image.
Use the established worker, image rendering, and thumbnailing components rather
than a custom GTK texture loader. GNOME Shell always-on-top, positioning, and
workspace integration will be a separate, optional component.
