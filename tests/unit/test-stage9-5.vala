using Stickies;

/** Confirms automatic title mode persists separately from the title's text. */
private void test_title_mode_persistence () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-title-mode-XXXXXX");
        var path = GLib.Path.build_filename (directory, "notes.db");
        string auto_id;
        string manual_id;
        {
            var store = new NoteRepository (path);
            var automatic = store.create_note ();
            auto_id = automatic.id;
            assert (automatic.auto_title);
            store.set_content (auto_id, "Heading\nBody");
            store.set_derived_title (auto_id, NoteTitle.derive (automatic.content));
            assert (automatic.title == "Heading");
            var manual = store.create_note ();
            manual_id = manual.id;
            store.set_content (manual_id, "Heading\nBody");
            store.set_title (manual_id, "Heading");
            assert (!manual.auto_title);
            store.flush_all ();
        }
        {
            var store = new NoteRepository (path);
            var automatic = store.find_note (auto_id);
            var manual = store.find_note (manual_id);
            assert (automatic != null && automatic.auto_title);
            assert (manual != null && !manual.auto_title);
            store.set_content (auto_id, "Changed\nBody");
            store.set_derived_title (auto_id, "Changed");
            store.set_content (manual_id, "Changed\nBody");
            store.set_derived_title (manual_id, "Changed");
            assert (automatic.title == "Changed");
            assert (manual.title == "Heading");
            store.set_auto_title (manual_id, true);
            assert (manual.title == "Changed");
            assert (manual.auto_title);
            store.flush_all ();
        }
        GLib.FileUtils.remove (path);
        GLib.FileUtils.remove (path + "-wal");
        GLib.FileUtils.remove (path + "-shm");
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("Title-mode persistence failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Upgrades legacy records while conservatively protecting manual headings. */
private void test_v5_migration () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-v6-migrate-XXXXXX");
        var path = GLib.Path.build_filename (directory, "notes.db");
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
                "reminder_notified_at_us INTEGER NOT NULL DEFAULT 0, " +
                "status INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0)"
            ) == Sqlite.OK);
            assert (database.exec (
                "CREATE TABLE attachments (id TEXT PRIMARY KEY NOT NULL, " +
                "note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE, " +
                "display_name TEXT NOT NULL, mime_type TEXT NOT NULL)"
            ) == Sqlite.OK);
            assert (database.exec (
                "INSERT INTO notes(id,title,content,color,created_at_us,updated_at_us) " +
                "VALUES('manual-note','Same','Same','yellow',10,20), " +
                "('blank-note','Untitled Note','','blue',11,21)"
            ) == Sqlite.OK);
            assert (database.exec ("PRAGMA user_version=5") == Sqlite.OK);
        }
        {
            var store = new NoteRepository (path);
            var manual = store.find_note ("manual-note");
            var placeholder = store.find_note ("blank-note");
            assert (manual != null && !manual.auto_title);
            assert (placeholder != null && placeholder.auto_title);
            assert (manual.title == "Same");
            assert (manual.updated_at_us == 20);
        }
        {
            Sqlite.Database database;
            assert (Sqlite.Database.open (path, out database) == Sqlite.OK);
            Sqlite.Statement statement;
            assert (database.prepare_v2 ("PRAGMA user_version", -1, out statement, null) == Sqlite.OK);
            assert (statement.step () == Sqlite.ROW);
            // Current installations migrate through v6 into schema v7.
            assert (statement.column_int (0) == 7);
        }
        GLib.FileUtils.remove (path);
        GLib.FileUtils.remove (path + "-wal");
        GLib.FileUtils.remove (path + "-shm");
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("v6 migration failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Registers the versioned title-mode migration and follow behavior. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/stage9/title-mode/persists", test_title_mode_persistence);
    GLib.Test.add_func ("/stage9/title-mode/migrate-v5", test_v5_migration);
    return GLib.Test.run ();
}
