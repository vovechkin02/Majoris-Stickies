using Stickies;

/** Confirms lifecycle transitions and pinned ordering without losing note text. */
private void test_note_lifecycle () {
    try {
        var store = new NoteRepository (":memory:");
        var first = store.create_note ();
        var second = store.create_note ();
        store.set_body (first.id, "Résumé: 日本語", "0:6:bold\n");
        store.set_pinned (first.id, true);
        assert (first.is_pinned);
        assert (store.list_notes ()[0].id == first.id);
        store.set_status (first.id, 1);
        assert (first.status == 1);
        store.set_status (first.id, 2);
        assert (first.status == 2);
        store.set_status (first.id, 0);
        assert (first.status == 0);
        assert (first.content == "Résumé: 日本語");
        assert (first.is_pinned);
        assert (store.find_note (second.id) != null);
        store.flush_all ();
    } catch (Error error) {
        GLib.Test.message ("Lifecycle test failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Rejects invalid note states without mutating the stored note. */
private void test_invalid_state () {
    try {
        var store = new NoteRepository (":memory:");
        var note = store.create_note ();
        bool rejected = false;
        try {
            store.set_status (note.id, -1);
        } catch (IOError.INVALID_ARGUMENT error) {
            rejected = true;
        }
        assert (rejected);
        assert (note.status == 0);
    } catch (Error error) {
        GLib.Test.message ("Invalid state test failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Preserves original identity and content when migrating a populated v4 store. */
private void test_stage5_to_stage6_migration () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-stage6-XXXXXX");
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
                "visible INTEGER NOT NULL DEFAULT 0, source_url TEXT NOT NULL DEFAULT '', " +
                "remind_at_us INTEGER NOT NULL DEFAULT 0, " +
                "reminder_notified_at_us INTEGER NOT NULL DEFAULT 0)"
            ) == Sqlite.OK);
            assert (database.exec (
                "CREATE TABLE attachments (id TEXT PRIMARY KEY NOT NULL, " +
                "note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE, " +
                "display_name TEXT NOT NULL, mime_type TEXT NOT NULL)"
            ) == Sqlite.OK);
            assert (database.exec (
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us) " +
                "VALUES ('79d3ad20-e248-4d36-984c-c2cbb68b3295', " +
                "'Legacy Note', 'Unchanged', 'green', 10, 20)"
            ) == Sqlite.OK);
            assert (database.exec ("PRAGMA user_version=4") == Sqlite.OK);
        }
        {
            var store = new NoteRepository (path);
            var note = store.find_note (identifier);
            assert (note != null);
            assert (note.status == 0);
            assert (!note.is_pinned);
            store.set_pinned (identifier, true);
            store.set_status (identifier, 1);
            store.flush_all ();
        }
        {
            var store = new NoteRepository (path);
            var note = store.find_note (identifier);
            assert (note != null);
            assert (note.title == "Legacy Note");
            assert (note.status == 1);
            assert (note.is_pinned);
            assert (note.content == "Unchanged");
        }
        GLib.FileUtils.remove (path);
        GLib.FileUtils.remove (path + "-wal");
        GLib.FileUtils.remove (path + "-shm");
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("Stage 6 migration failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Confirms the persisted editor accepts Stage 6's bounded style identifiers. */
private void test_extended_formatting () {
    var formatting = "0:4:font-serif\n0:4:size-18\n0:4:text-blue\n";
    assert (NoteFormatting.is_valid ("Text", formatting));
    assert (NoteFormatting.is_valid ("Text", "0:4:align-center\n"));
    assert (!NoteFormatting.is_valid ("Text", "0:4:text-script\n"));
    assert (!NoteFormatting.is_valid ("Text", "0:5:size-18\n"));
}

/** Registers Stage 6 lifecycle, migration, and formatting tests. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/notes/stage6/lifecycle", test_note_lifecycle);
    GLib.Test.add_func ("/notes/stage6/reject-state", test_invalid_state);
    GLib.Test.add_func ("/notes/stage6/migration-v4", test_stage5_to_stage6_migration);
    GLib.Test.add_func ("/notes/stage6/extended-formatting", test_extended_formatting);
    return GLib.Test.run ();
}
