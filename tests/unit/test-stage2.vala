using Stickies;

/** Validates stable Unicode offsets and rejects untrusted formatting payloads. */
private void test_formatting_intervals () {
    var text = "Hi 👋 café";
    assert (NoteFormatting.is_valid (text, ""));
    assert (NoteFormatting.is_valid (text, "0:2:bold\n3:4:italic\n"));
    assert (!NoteFormatting.is_valid (text, "2:1:bold\n"));
    assert (!NoteFormatting.is_valid (text, "0:100:bold\n"));
    assert (!NoteFormatting.is_valid (text, "0:1:other\n"));
    assert (!NoteFormatting.is_valid (text, "0:1:../../../etc/passwd\n"));
    assert (!NoteFormatting.is_valid (text, "-1:1:bold\n"));
    var builder = new GLib.StringBuilder ();
    NoteFormatting.append_span (builder, 0, 2, "bold");
    assert (builder.str == "0:2:bold\n");
}

/** Verifies that a Stage 1 schema is upgraded without changing note data. */
private void test_stage1_migration () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-migration-XXXXXX");
        var database_path = GLib.Path.build_filename (directory, "notes.db");
        string id = "46c50222-f88d-4486-8fb0-9da37bff87ab";
        {
            Sqlite.Database database;
            assert (Sqlite.Database.open (database_path, out database) == Sqlite.OK);
            assert (database.exec (
                "CREATE TABLE notes (" +
                "id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, " +
                "content TEXT NOT NULL, color TEXT NOT NULL, " +
                "created_at_us INTEGER NOT NULL, updated_at_us INTEGER NOT NULL)"
            ) == Sqlite.OK);
            assert (database.exec (
                "INSERT INTO notes VALUES (" +
                "'46c50222-f88d-4486-8fb0-9da37bff87ab'," +
                "'Original', 'Some old text', 'blue', 123, 456)"
            ) == Sqlite.OK);
            assert (database.exec ("PRAGMA user_version=1") == Sqlite.OK);
        }
        {
            var repository = new NoteRepository (database_path);
            var original = repository.find_note (id);
            assert (original != null);
            assert (original.title == "Original");
            assert (original.content == "Some old text");
            assert (original.color == "blue");
            assert (original.formatting == "");
            assert (original.window_width == 370);
            assert (!original.is_collapsed);
            repository.set_body (id, "Some old text", "0:4:bold\n");
            repository.set_presentation (id, true, false, true, 480, 460, true);
            repository.flush_all ();
        }
        {
            var reopened = new NoteRepository (database_path);
            var note = reopened.find_note (id);
            assert (note != null);
            assert (note.formatting == "0:4:bold\n");
            assert (note.is_collapsed);
            assert (note.is_translucent);
            assert (note.is_visible);
            assert (note.window_width == 480);
            assert (note.window_height == 460);
        }
        GLib.FileUtils.remove (database_path);
        GLib.FileUtils.remove (database_path + "-wal");
        GLib.FileUtils.remove (database_path + "-shm");
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("Migration failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Confirms that duplicate notes retain formatting but receive distinct IDs. */
private void test_duplicate_formatting () {
    try {
        var repository = new NoteRepository (":memory:");
        var note = repository.create_note ();
        repository.set_body (note.id, "Draft body", "0:5:italic\n");
        repository.flush_all ();
        var copy = repository.duplicate_note (note.id);
        assert (copy.id != note.id);
        assert (copy.content == note.content);
        assert (copy.formatting == note.formatting);
        assert (!copy.is_collapsed);
        assert (!copy.is_visible);
    } catch (Error error) {
        GLib.Test.message ("Rich duplicate failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Registers the Stage 2 model, formatting and migration regression tests. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/notes/formatting/intervals", test_formatting_intervals);
    GLib.Test.add_func ("/notes/storage/stage1-migration", test_stage1_migration);
    GLib.Test.add_func ("/notes/storage/rich-duplicate", test_duplicate_formatting);
    return GLib.Test.run ();
}
