using Stickies;

/** Ensures a damaged notes file is rejected before any migration writes. */
private void test_database_corruption () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-corrupt-XXXXXX");
        var database_path = GLib.Path.build_filename (directory, "notes.db");
        GLib.FileUtils.set_contents (database_path, "This is not a SQLite database");
        bool rejected = false;
        try {
            var repository = new NoteRepository (database_path);
            assert (repository.list_notes ().size == 0);
        } catch (Error error) {
            rejected = true;
        }
        assert (rejected);
        GLib.FileUtils.remove (database_path);
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("Database corruption test failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Exercises large note snapshots and Unicode searching without a GUI. */
private void test_large_note_collection () {
    try {
        var repository = new NoteRepository (":memory:");
        for (int index = 0; index < 600; index++) {
            var note = repository.create_note ();
            repository.set_title (note.id, "Item %d".printf (index));
            if (index % 100 == 0) {
                repository.set_content (note.id, "Résumé — 检索");
            }
        }
        repository.flush_all ();
        assert (repository.list_notes ().size == 600);
        assert (repository.search_notes ("RÉSUMÉ").size == 6);
        assert (repository.search_notes ("not-a-note").size == 0);
    } catch (Error error) {
        GLib.Test.message ("Large collection test failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Registers bounded Stage 4 reliability and collection regression tests. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/notes/storage/reject-corrupt", test_database_corruption);
    GLib.Test.add_func ("/notes/search/large-collection", test_large_note_collection);
    return GLib.Test.run ();
}
