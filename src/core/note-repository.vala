using Gee;

namespace Stickies {
    /**
     * Coordinates note identity, search, debounced persistence, and SQLite I/O.
     *
     * This local-first repository is confined to the GTK main context. Only
     * lightweight indexed reads and individual-record writes are performed;
     * batched asynchronous disk work is reserved for a later scale-up.
     */
    public class NoteRepository : GLib.Object {
        private const uint AUTOSAVE_DELAY_MS = 500;
        private const int BUSY_TIMEOUT_MS = 200;

        private Sqlite.Database database;
        private Gee.HashMap<string, Note> notes;
        private Gee.HashSet<string> dirty_ids;
        private Gee.HashMap<string, uint> save_sources;

        /** Emitted immediately after a note is added to the repository. */
        public signal void note_added (Note note);

        /** Emitted on an actual title, content, or color modification. */
        public signal void note_updated (Note note);

        /** Emitted after a note has been permanently deleted from storage. */
        public signal void note_deleted (string id);

        /** Emitted when a dirty note has been successfully written to SQLite. */
        public signal void note_saved (Note note);

        /** Emitted when a save fails; the note remains dirty for retry. */
        public signal void save_failed (string id, string message);

        /**
         * Opens or creates a database, prepares its schema, and loads notes.
         * Throws IOError on an invalid store, inaccessible path, or SQL failure.
         */
        public NoteRepository (string database_path) throws Error {
            notes = new Gee.HashMap<string, Note> ();
            dirty_ids = new Gee.HashSet<string> ();
            save_sources = new Gee.HashMap<string, uint> ();

            if (database_path != ":memory:") {
                var directory = GLib.Path.get_dirname (database_path);
                if (GLib.DirUtils.create_with_parents (directory, 0700) != 0) {
                    throw new IOError.FAILED ("Unable to create the notes data directory");
                }
            }

            Sqlite.Database opened;
            var result = Sqlite.Database.open (database_path, out opened);
            if (result != Sqlite.OK) {
                throw new IOError.FAILED ("Unable to open the notes database (%d)".printf (result));
            }

            database = (owned) opened;
            database.busy_timeout (BUSY_TIMEOUT_MS);
            execute ("PRAGMA journal_mode=WAL;");
            execute ("PRAGMA foreign_keys=ON;");
            initialize_schema ();
            load_notes ();
        }

        /** Adds and durably creates a new blank note. */
        public Note create_note () throws Error {
            return insert_note ("Untitled Note", "", NotePalette.DEFAULT_COLOR);
        }

        /** Duplicates a note with a new ID and creation timestamp. */
        public Note duplicate_note (string id) throws Error {
            var source = find_note (id);
            if (source == null) {
                throw new IOError.NOT_FOUND ("The source note no longer exists");
            }

            return insert_note ("Copy of " + source.title, source.content, source.color);
        }

        /** Looks up a note by its stable ID, or returns null. */
        public Note? find_note (string id) {
            return notes.get (id);
        }

        /** Returns a snapshot ordered from the most to least recently modified. */
        public Gee.ArrayList<Note> list_notes () {
            var result = new Gee.ArrayList<Note> ();
            foreach (var note in notes.values) {
                result.add (note);
            }

            result.sort ((left, right) => {
                if (left.updated_at_us == right.updated_at_us) {
                    return left.id.collate (right.id);
                }

                return left.updated_at_us > right.updated_at_us ? -1 : 1;
            });
            return result;
        }

        /** Searches headings and bodies case-insensitively using Unicode case folding. */
        public Gee.ArrayList<Note> search_notes (string query) {
            var result = new Gee.ArrayList<Note> ();
            var needle = query.strip ().casefold ();
            foreach (var note in list_notes ()) {
                if (needle == "" ||
                    note.title.casefold ().index_of (needle) >= 0 ||
                    note.content.casefold ().index_of (needle) >= 0) {
                    result.add (note);
                }
            }

            return result;
        }

        /** Updates a stored note's heading and schedules a debounced save. */
        public void set_title (string id, string value) {
            var note = find_note (id);
            if (note != null && note.update_title (value)) {
                queue_save (note);
            }
        }

        /** Updates a stored note's plain text and schedules a debounced save. */
        public void set_content (string id, string value) {
            var note = find_note (id);
            if (note != null && note.update_content (value)) {
                queue_save (note);
            }
        }

        /** Changes the paper color when the provided palette token is valid. */
        public void set_color (string id, string value) {
            var note = find_note (id);
            if (note != null && note.update_color (value)) {
                queue_save (note);
            }
        }

        /**
         * Permanently deletes a note and cancels outstanding delayed writes.
         * SQLite deletion occurs before in-memory deletion to avoid data loss.
         */
        public void delete_note (string id) throws Error {
            if (!notes.has_key (id)) {
                throw new IOError.NOT_FOUND ("The note no longer exists");
            }

            Sqlite.Statement statement;
            prepare ("DELETE FROM notes WHERE id = ?1", out statement);
            check_bind (statement.bind_text (1, id));
            check_step (statement.step ());

            cancel_save (id);
            dirty_ids.remove (id);
            notes.unset (id);
            note_deleted (id);
        }

        /** Writes a note's pending edits before its window is allowed to close. */
        public void flush_note (string id) throws Error {
            cancel_save (id);
            if (!dirty_ids.contains (id)) {
                return;
            }

            var note = find_note (id);
            if (note == null) {
                dirty_ids.remove (id);
                return;
            }

            save_note (note);
            dirty_ids.remove (id);
            note_saved (note);
        }

        /** Writes all outstanding notes; callers must handle any save failure. */
        public void flush_all () throws Error {
            var ids = new Gee.ArrayList<string> ();
            foreach (var id in dirty_ids) {
                ids.add (id);
            }

            foreach (var id in ids) {
                flush_note (id);
            }
        }

        /** Returns whether edits are pending a durable SQLite write. */
        public bool has_pending_changes () {
            return dirty_ids.size > 0;
        }

        /** Creates a new note with one durable INSERT before announcing it. */
        private Note insert_note (string title, string content, string color) throws Error {
            var now_us = GLib.get_real_time ();
            var note = new Note (GLib.Uuid.string_random (), title, content, color, now_us, now_us);
            save_note (note);
            notes.set (note.id, note);
            note_added (note);
            return note;
        }

        /** Marks a changed note dirty and restarts its individual debounce timer. */
        private void queue_save (Note note) {
            dirty_ids.add (note.id);
            cancel_save (note.id);
            var id = note.id;
            uint source_id = GLib.Timeout.add (AUTOSAVE_DELAY_MS, () => {
                save_sources.unset (id);
                try {
                    flush_note (id);
                } catch (Error error) {
                    save_failed (id, error.message);
                }

                return GLib.Source.REMOVE;
            });
            save_sources.set (id, source_id);
            note_updated (note);
        }

        /** Cancels one pending source, if it has not already fired. */
        private void cancel_save (string id) {
            if (save_sources.has_key (id)) {
                uint source_id = save_sources.get (id);
                GLib.Source.remove (source_id);
                save_sources.unset (id);
            }
        }

        /** Creates the stable Stage 1 schema without downgrading newer databases. */
        private void initialize_schema () throws Error {
            int version = read_schema_version ();
            if (version > 1) {
                throw new IOError.NOT_SUPPORTED (
                    "This notes database was created by a newer version of Stickies"
                );
            }

            execute (
                "CREATE TABLE IF NOT EXISTS notes (" +
                "id TEXT PRIMARY KEY NOT NULL, " +
                "title TEXT NOT NULL, " +
                "content TEXT NOT NULL, " +
                "color TEXT NOT NULL, " +
                "created_at_us INTEGER NOT NULL, " +
                "updated_at_us INTEGER NOT NULL)"
            );
            execute ("CREATE INDEX IF NOT EXISTS notes_modified_idx ON notes(updated_at_us DESC)");
            if (version == 0) {
                execute ("PRAGMA user_version=1");
            }
        }

        /** Reads the database's schema-version marker before attempting migrations. */
        private int read_schema_version () throws Error {
            Sqlite.Statement statement;
            prepare ("PRAGMA user_version", out statement);
            if (statement.step () != Sqlite.ROW) {
                throw new IOError.FAILED ("Could not read the notes database schema version");
            }

            return statement.column_int (0);
        }

        /** Loads all persisted notes into memory without emitting edit signals. */
        private void load_notes () throws Error {
            Sqlite.Statement statement;
            prepare (
                "SELECT id, title, content, color, created_at_us, updated_at_us FROM notes",
                out statement
            );

            int status;
            while ((status = statement.step ()) == Sqlite.ROW) {
                var note = new Note (
                    statement.column_text (0) ?? "",
                    statement.column_text (1) ?? "",
                    statement.column_text (2) ?? "",
                    statement.column_text (3) ?? NotePalette.DEFAULT_COLOR,
                    statement.column_int64 (4),
                    statement.column_int64 (5)
                );
                notes.set (note.id, note);
            }

            if (status != Sqlite.DONE) {
                throw new IOError.FAILED ("Could not load notes: " + database.errmsg ());
            }
        }

        /** Writes a complete note atomically with a parameterized UPSERT. */
        private void save_note (Note note) throws Error {
            Sqlite.Statement statement;
            prepare (
                "INSERT INTO notes " +
                "(id, title, content, color, created_at_us, updated_at_us) " +
                "VALUES (?1, ?2, ?3, ?4, ?5, ?6) " +
                "ON CONFLICT(id) DO UPDATE SET " +
                "title=excluded.title, content=excluded.content, " +
                "color=excluded.color, updated_at_us=excluded.updated_at_us",
                out statement
            );
            check_bind (statement.bind_text (1, note.id));
            check_bind (statement.bind_text (2, note.title));
            check_bind (statement.bind_text (3, note.content));
            check_bind (statement.bind_text (4, note.color));
            check_bind (statement.bind_int64 (5, note.created_at_us));
            check_bind (statement.bind_int64 (6, note.updated_at_us));
            check_step (statement.step ());
        }

        /** Compiles SQL into a statement scoped to its owning operation. */
        private void prepare (string sql, out Sqlite.Statement statement) throws Error {
            var result = database.prepare_v2 (sql, -1, out statement, null);
            if (result != Sqlite.OK) {
                throw new IOError.FAILED ("Could not prepare SQL: " + database.errmsg ());
            }
        }

        /** Runs a schema or configuration statement and preserves SQL errors. */
        private void execute (string sql) throws Error {
            if (database.exec (sql) != Sqlite.OK) {
                throw new IOError.FAILED ("SQLite operation failed: " + database.errmsg ());
            }
        }

        /** Rejects failed SQLite parameter binding operations. */
        private void check_bind (int result) throws Error {
            if (result != Sqlite.OK) {
                throw new IOError.FAILED ("SQLite bind failed: " + database.errmsg ());
            }
        }

        /** Requires a successful completion step for a write statement. */
        private void check_step (int result) throws Error {
            if (result != Sqlite.DONE) {
                throw new IOError.FAILED ("SQLite write failed: " + database.errmsg ());
            }
        }
    }
}
