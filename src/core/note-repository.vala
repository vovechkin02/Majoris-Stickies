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
        private const uint MAX_SAVE_RETRIES = 3;
        private const int64 MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024;

        private Sqlite.Database database;
        private string attachments_directory;
        private Gee.HashMap<string, Note> notes;
        private Gee.HashSet<string> dirty_ids;
        private Gee.HashMap<string, uint> save_sources;
        private Gee.HashMap<string, uint> retry_counts;

        /** Emitted immediately after a note is added to the repository. */
        public signal void note_added (Note note);

        /** Emitted on an actual title, content, or color modification. */
        public signal void note_updated (Note note);

        /** Emitted after a note has been permanently deleted from storage. */
        public signal void note_deleted (string id);

        /** Emitted after the attachment list changes for a particular note. */
        public signal void attachment_changed (string id);

        /** Emitted when a dirty note has been successfully written to SQLite. */
        public signal void note_saved (Note note);

        /** Emitted when a save fails; the note remains dirty for retry. */
        public signal void save_failed (string id, string message);

        /**
         * Opens or creates a database, prepares its schema, and loads notes.
         * Throws IOError on an invalid store, inaccessible path, or SQL failure.
         */
        public NoteRepository (string database_path) throws Error {
            attachments_directory = GLib.Path.build_filename (
                GLib.Path.get_dirname (database_path), "attachments"
            );
            notes = new Gee.HashMap<string, Note> ();
            dirty_ids = new Gee.HashSet<string> ();
            save_sources = new Gee.HashMap<string, uint> ();
            retry_counts = new Gee.HashMap<string, uint> ();

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
            verify_integrity ();
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

            var copy = insert_note ("Copy of " + source.title, source.content, source.color);
            set_body (copy.id, source.content, source.formatting);
            set_source_url (copy.id, source.source_url);
            flush_note (copy.id);
            return copy;
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
                    note.content.casefold ().index_of (needle) >= 0 ||
                    note.source_url.casefold ().index_of (needle) >= 0) {
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

        /** Applies text and style runs as a single logical edit. */
        public void set_body (string id, string text, string formatting) {
            var note = find_note (id);
            if (note != null && note.update_body (text, formatting)) {
                queue_save (note);
            }
        }

        /** Changes a note's verified web origin and queues an atomic save. */
        public void set_source_url (string id, string url) throws Error {
            var note = find_note (id);
            if (note == null) {
                throw new IOError.NOT_FOUND ("The note no longer exists");
            }
            if (note.update_source_url (url)) {
                queue_save (note);
            }
        }

        /** Persists presentation preferences independently of body modifications. */
        public void set_presentation (
            string id,
            bool collapsed,
            bool floating,
            bool translucent,
            int width,
            int height,
            bool visible
        ) {
            var note = find_note (id);
            if (note != null && note.update_presentation (
                collapsed, floating, translucent, width, height, visible
            )) {
                queue_save (note);
            }
        }

        /** Lists managed note attachments in stable insertion order. */
        public Gee.ArrayList<NoteAttachment> list_attachments (string id) throws Error {
            var result = new Gee.ArrayList<NoteAttachment> ();
            Sqlite.Statement statement;
            prepare (
                "SELECT id, display_name, mime_type FROM attachments " +
                "WHERE note_id = ?1 ORDER BY rowid ASC",
                out statement
            );
            check_bind (statement.bind_text (1, id));
            int status;
            while ((status = statement.step ()) == Sqlite.ROW) {
                var attachment_id = statement.column_text (0) ?? "";
                result.add (new NoteAttachment (
                    attachment_id,
                    id,
                    statement.column_text (1) ?? "Attachment",
                    statement.column_text (2) ?? "application/octet-stream",
                    attachment_path (attachment_id)
                ));
            }
            if (status != Sqlite.DONE) {
                throw new IOError.FAILED ("Unable to read attachments: " + database.errmsg ());
            }
            return result;
        }

        /**
         * Copies an image or PDF asynchronously into private application storage.
         * The SQL record is inserted only after the copy finishes successfully.
         */
        public async NoteAttachment attach_file (
            string note_id,
            GLib.File source,
            GLib.Cancellable? cancellable = null
        ) throws Error {
            if (find_note (note_id) == null) {
                throw new IOError.NOT_FOUND ("The note no longer exists");
            }
            var info = yield source.query_info_async (
                "standard::display-name,standard::size,standard::content-type,standard::type",
                GLib.FileQueryInfoFlags.NONE,
                GLib.Priority.DEFAULT,
                cancellable
            );
            if (info.get_file_type () != GLib.FileType.REGULAR ||
                info.get_size () < 0 || info.get_size () > MAX_ATTACHMENT_BYTES) {
                throw new IOError.INVALID_ARGUMENT ("Only regular files up to 50 MiB are supported");
            }
            var mime = info.get_content_type () ?? "application/octet-stream";
            if (mime != "application/pdf" && !mime.has_prefix ("image/")) {
                throw new IOError.NOT_SUPPORTED ("Only PDFs and image files may be attached");
            }
            if (GLib.DirUtils.create_with_parents (attachments_directory, 0700) != 0) {
                throw new IOError.FAILED ("Unable to create attachment directory");
            }
            var id = GLib.Uuid.string_random ();
            var destination = GLib.File.new_for_path (attachment_path (id));
            try {
                yield source.copy_async (
                    destination,
                    GLib.FileCopyFlags.NONE,
                    GLib.Priority.DEFAULT,
                    cancellable,
                    null
                );
                // A source can change after its initial metadata query. Check
                // the completed copy before admitting it to managed storage.
                var copied = yield destination.query_info_async (
                    "standard::size,standard::type",
                    GLib.FileQueryInfoFlags.NONE,
                    GLib.Priority.DEFAULT,
                    cancellable
                );
                if (copied.get_file_type () != GLib.FileType.REGULAR ||
                    copied.get_size () < 0 || copied.get_size () > MAX_ATTACHMENT_BYTES) {
                    throw new IOError.INVALID_DATA ("The copied attachment exceeds 50 MiB");
                }
                Sqlite.Statement statement;
                prepare (
                    "INSERT INTO attachments(id,note_id,display_name,mime_type) " +
                    "VALUES(?1,?2,?3,?4)",
                    out statement
                );
                check_bind (statement.bind_text (1, id));
                check_bind (statement.bind_text (2, note_id));
                check_bind (statement.bind_text (3, info.get_display_name ()));
                check_bind (statement.bind_text (4, mime));
                check_step (statement.step ());
            } catch (Error error) {
                try {
                    destination.delete (null);
                } catch (Error cleanup_error) {
                    warning ("Unable to clean up failed attachment: %s", cleanup_error.message);
                }
                throw error;
            }
            var attachment = new NoteAttachment (
                id, note_id, info.get_display_name (), mime, attachment_path (id)
            );
            attachment_changed (note_id);
            return attachment;
        }

        /** Removes the database reference before deleting the managed file. */
        public void remove_attachment (string note_id, string attachment_id) throws Error {
            Sqlite.Statement statement;
            prepare ("DELETE FROM attachments WHERE id=?1 AND note_id=?2", out statement);
            check_bind (statement.bind_text (1, attachment_id));
            check_bind (statement.bind_text (2, note_id));
            check_step (statement.step ());
            if (database.changes () == 0) {
                throw new IOError.NOT_FOUND ("Attachment not found");
            }
            try {
                GLib.File.new_for_path (attachment_path (attachment_id)).delete (null);
            } catch (IOError.NOT_FOUND error) {
                // The metadata deletion succeeded; the file was already absent.
            } catch (Error error) {
                warning ("Unable to remove orphaned attachment: %s", error.message);
            }
            attachment_changed (note_id);
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

            var attachments_to_remove = list_attachments (id);
            Sqlite.Statement statement;
            prepare ("DELETE FROM notes WHERE id = ?1", out statement);
            check_bind (statement.bind_text (1, id));
            check_step (statement.step ());

            cancel_save (id);
            dirty_ids.remove (id);
            retry_counts.unset (id);
            notes.unset (id);
            // Files are unlinked after the committed database deletion. A failure
            // leaves an orphan, never an attachment record pointing to deleted data.
            foreach (var attachment in attachments_to_remove) {
                try {
                    GLib.File.new_for_path (attachment.path).delete (null);
                } catch (Error error) {
                    warning ("Unable to remove deleted note attachment: %s", error.message);
                }
            }
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
            retry_counts.unset (id);
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
            retry_counts.unset (note.id);
            var id = note.id;
            uint source_id = GLib.Timeout.add (AUTOSAVE_DELAY_MS, () => {
                save_sources.unset (id);
                try {
                    flush_note (id);
                } catch (Error error) {
                    save_failed (id, error.message);
                    schedule_save_retry (id);
                }

                return GLib.Source.REMOVE;
            });
            save_sources.set (id, source_id);
            note_updated (note);
        }

        /** Retries temporary write failures with a strict exponential limit. */
        private void schedule_save_retry (string id) {
            if (!dirty_ids.contains (id) || save_sources.has_key (id)) {
                return;
            }
            uint attempts = retry_counts.has_key (id) ? retry_counts.get (id) : 0;
            if (attempts >= MAX_SAVE_RETRIES) {
                return;
            }
            uint delay_seconds = (uint) 2 << attempts;
            retry_counts.set (id, attempts + 1);
            uint source_id = GLib.Timeout.add_seconds (delay_seconds, () => {
                save_sources.unset (id);
                try {
                    flush_note (id);
                } catch (Error error) {
                    save_failed (id, error.message);
                    schedule_save_retry (id);
                }
                return GLib.Source.REMOVE;
            });
            save_sources.set (id, source_id);
        }

        /** Refuses to migrate or load a damaged database without modifying it. */
        private void verify_integrity () throws Error {
            Sqlite.Statement statement;
            prepare ("PRAGMA quick_check(1)", out statement);
            if (statement.step () != Sqlite.ROW || statement.column_text (0) != "ok") {
                throw new IOError.INVALID_DATA (
                    "The notes database failed its integrity check. " +
                    "Restore a verified backup while Stickies is closed."
                );
            }
        }

        /** Cancels one pending source, if it has not already fired. */
        private void cancel_save (string id) {
            if (save_sources.has_key (id)) {
                uint source_id = save_sources.get (id);
                GLib.Source.remove (source_id);
                save_sources.unset (id);
            }
        }

        /** Migrates Stage 1 in-place and rejects unknown newer schemas. */
        private void initialize_schema () throws Error {
            int version = read_schema_version ();
            if (version > 3) {
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
            if (version < 2) {
                execute ("BEGIN IMMEDIATE");
                try {
                    execute ("ALTER TABLE notes ADD COLUMN formatting TEXT NOT NULL DEFAULT ''");
                    execute ("ALTER TABLE notes ADD COLUMN collapsed INTEGER NOT NULL DEFAULT 0");
                    execute ("ALTER TABLE notes ADD COLUMN floating INTEGER NOT NULL DEFAULT 0");
                    execute ("ALTER TABLE notes ADD COLUMN translucent INTEGER NOT NULL DEFAULT 0");
                    execute ("ALTER TABLE notes ADD COLUMN window_width INTEGER NOT NULL DEFAULT 370");
                    execute ("ALTER TABLE notes ADD COLUMN window_height INTEGER NOT NULL DEFAULT 330");
                    execute ("ALTER TABLE notes ADD COLUMN visible INTEGER NOT NULL DEFAULT 0");
                    execute (
                        "CREATE TABLE attachments (" +
                        "id TEXT PRIMARY KEY NOT NULL, " +
                        "note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE, " +
                        "display_name TEXT NOT NULL, mime_type TEXT NOT NULL)"
                    );
                    execute ("CREATE INDEX attachments_note_idx ON attachments(note_id)");
                    execute ("PRAGMA user_version=2");
                    execute ("COMMIT");
                } catch (Error error) {
                    execute ("ROLLBACK");
                    throw error;
                }
            }
            if (version < 3) {
                execute ("BEGIN IMMEDIATE");
                try {
                    execute ("ALTER TABLE notes ADD COLUMN source_url TEXT NOT NULL DEFAULT ''");
                    execute ("PRAGMA user_version=3");
                    execute ("COMMIT");
                } catch (Error error) {
                    execute ("ROLLBACK");
                    throw error;
                }
            }
        }

        /** Rejects corrupt or hostile identifiers before accessing private files. */
        private string attachment_path (string id) throws Error {
            if (id.length != 36) {
                throw new IOError.INVALID_DATA ("Invalid attachment identifier");
            }
            for (int index = 0; index < id.length; index++) {
                char value = id[index];
                if (!((value >= '0' && value <= '9') ||
                    (value >= 'a' && value <= 'f') || value == '-')) {
                    throw new IOError.INVALID_DATA ("Invalid attachment identifier");
                }
            }
            return GLib.Path.build_filename (attachments_directory, id + ".asset");
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
                "SELECT id, title, content, color, created_at_us, updated_at_us, " +
                "formatting, collapsed, floating, translucent, " +
                "window_width, window_height, visible, source_url FROM notes",
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
                    statement.column_int64 (5),
                    statement.column_text (6) ?? "",
                    statement.column_int (7) != 0,
                    statement.column_int (8) != 0,
                    statement.column_int (9) != 0,
                    statement.column_int (10),
                    statement.column_int (11),
                    statement.column_int (12) != 0,
                    statement.column_text (13) ?? ""
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
                "(id, title, content, color, created_at_us, updated_at_us, " +
                "formatting, collapsed, floating, translucent, window_width, window_height, visible, " +
                "source_url) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14) " +
                "ON CONFLICT(id) DO UPDATE SET " +
                "title=excluded.title, content=excluded.content, " +
                "color=excluded.color, updated_at_us=excluded.updated_at_us, " +
                "formatting=excluded.formatting, collapsed=excluded.collapsed, " +
                "floating=excluded.floating, translucent=excluded.translucent, " +
                "window_width=excluded.window_width, window_height=excluded.window_height, " +
                "visible=excluded.visible, source_url=excluded.source_url",
                out statement
            );
            check_bind (statement.bind_text (1, note.id));
            check_bind (statement.bind_text (2, note.title));
            check_bind (statement.bind_text (3, note.content));
            check_bind (statement.bind_text (4, note.color));
            check_bind (statement.bind_int64 (5, note.created_at_us));
            check_bind (statement.bind_int64 (6, note.updated_at_us));
            check_bind (statement.bind_text (7, note.formatting));
            check_bind (statement.bind_int (8, note.is_collapsed ? 1 : 0));
            check_bind (statement.bind_int (9, note.is_floating ? 1 : 0));
            check_bind (statement.bind_int (10, note.is_translucent ? 1 : 0));
            check_bind (statement.bind_int (11, note.window_width));
            check_bind (statement.bind_int (12, note.window_height));
            check_bind (statement.bind_int (13, note.is_visible ? 1 : 0));
            check_bind (statement.bind_text (14, note.source_url));
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
