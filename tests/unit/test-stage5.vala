using Stickies;

/** Confirms the repository persists reminder state and one-time delivery. */
private void test_reminder_persistence () {
    try {
        var store = new NoteRepository (":memory:");
        var note = store.create_note ();
        int64 now_us = GLib.get_real_time ();
        int64 deadline_us = now_us + (int64) 60 * 1000000;
        store.set_reminder (note.id, deadline_us);
        assert (note.remind_at_us == deadline_us);
        assert (note.reminder_notified_at_us == 0);
        store.mark_reminder_notified (note.id, deadline_us);
        assert (note.reminder_notified_at_us == deadline_us);
        store.mark_reminder_notified (note.id, deadline_us + 1000000);
        assert (note.reminder_notified_at_us == deadline_us);
        store.set_reminder (note.id, 0);
        assert (note.remind_at_us == 0);
        assert (note.reminder_notified_at_us == 0);
        store.flush_all ();
    } catch (Error error) {
        GLib.Test.message ("Reminder persistence failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Ensures reminders cannot be scheduled beyond the documented safe horizon. */
private void test_reminder_deadline_validation () {
    try {
        var store = new NoteRepository (":memory:");
        var note = store.create_note ();
        bool rejected = false;
        try {
            store.set_reminder (note.id, -1);
        } catch (IOError.INVALID_ARGUMENT error) {
            rejected = true;
        }
        assert (rejected);
        rejected = false;
        try {
            store.set_reminder (note.id, GLib.get_real_time () +
                (int64) 400 * 24 * 60 * 60 * 1000000);
        } catch (IOError.INVALID_ARGUMENT error) {
            rejected = true;
        }
        assert (rejected);
    } catch (Error error) {
        GLib.Test.message ("Reminder validation failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Upgrades a Stage 3/4 note record without replacing its existing identity. */
private void test_stage4_migration () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-stage5-XXXXXX");
        var path = GLib.Path.build_filename (directory, "notes.db");
        string identifier = "79d3ad20-e248-4d36-984c-c2cbb68b3295";
        {
            Sqlite.Database database;
            assert (Sqlite.Database.open (path, out database) == Sqlite.OK);
            assert (database.exec (
                "CREATE TABLE notes (id TEXT PRIMARY KEY NOT NULL, " +
                "title TEXT NOT NULL, content TEXT NOT NULL, color TEXT NOT NULL, " +
                "created_at_us INTEGER NOT NULL, updated_at_us INTEGER NOT NULL, " +
                "formatting TEXT NOT NULL DEFAULT '', collapsed INTEGER NOT NULL DEFAULT 0, " +
                "floating INTEGER NOT NULL DEFAULT 0, translucent INTEGER NOT NULL DEFAULT 0, " +
                "window_width INTEGER NOT NULL DEFAULT 370, " +
                "window_height INTEGER NOT NULL DEFAULT 330, " +
                "visible INTEGER NOT NULL DEFAULT 0, source_url TEXT NOT NULL DEFAULT '')"
            ) == Sqlite.OK);
            assert (database.exec (
                "CREATE TABLE attachments (id TEXT PRIMARY KEY NOT NULL, " +
                "note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE, " +
                "display_name TEXT NOT NULL, mime_type TEXT NOT NULL)"
            ) == Sqlite.OK);
            assert (database.exec (
                "INSERT INTO notes (id,title,content,color,created_at_us,updated_at_us, " +
                "source_url) VALUES ('79d3ad20-e248-4d36-984c-c2cbb68b3295'," +
                "'Migration','Kept body','pink',100,200,'https://example.org')"
            ) == Sqlite.OK);
            assert (database.exec ("PRAGMA user_version=3") == Sqlite.OK);
        }
        {
            var store = new NoteRepository (path);
            var note = store.find_note (identifier);
            assert (note != null);
            assert (note.title == "Migration");
            assert (note.content == "Kept body");
            assert (note.source_url == "https://example.org");
            assert (note.remind_at_us == 0);
            store.set_reminder (identifier, GLib.get_real_time () + 100000000);
            store.flush_all ();
        }
        {
            var store = new NoteRepository (path);
            var note = store.find_note (identifier);
            assert (note != null);
            assert (note.remind_at_us > 0);
            assert (store.list_notes ().size == 1);
        }
        GLib.FileUtils.remove (path);
        GLib.FileUtils.remove (path + "-wal");
        GLib.FileUtils.remove (path + "-shm");
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("Stage 4 migration failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Registers Stage 5 reminder and schema migration unit tests. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/notes/reminder/persistence", test_reminder_persistence);
    GLib.Test.add_func ("/notes/reminder/bounds", test_reminder_deadline_validation);
    GLib.Test.add_func ("/notes/storage/stage4-to-stage5", test_stage4_migration);
    return GLib.Test.run ();
}
