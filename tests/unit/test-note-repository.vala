using Stickies;

/** Verifies that stored edits survive closing and reopening the same database. */
private void test_persistence_and_unicode () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-persist-XXXXXX");
        var database_path = GLib.Path.build_filename (directory, "notes.db");
        string id;

        {
            var repository = new NoteRepository (database_path);
            var note = repository.create_note ();
            id = note.id;
            repository.set_title (id, "Σημείωση");
            repository.set_content (id, "Multiline\nمرحبا 👋\nO'Reilly");
            repository.set_color (id, "purple");
            assert (repository.has_pending_changes ());
            repository.flush_all ();
            assert (!repository.has_pending_changes ());
        }

        {
            var reopened = new NoteRepository (database_path);
            var stored = reopened.find_note (id);
            assert (stored != null);
            assert (stored.title == "Σημείωση");
            assert (stored.content == "Multiline\nمرحبا 👋\nO'Reilly");
            assert (stored.color == "purple");
            assert (reopened.list_notes ().size == 1);
            assert (reopened.search_notes ("O'Reilly").size == 1);
            assert (reopened.search_notes ("UNMATCHED").size == 0);
        }

        GLib.FileUtils.remove (database_path);
        GLib.FileUtils.remove (database_path + "-wal");
        GLib.FileUtils.remove (database_path + "-shm");
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("Persistence test failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Verifies duplicate identity and permanent deletion without stale writes. */
private void test_duplicate_and_delete () {
    try {
        var repository = new NoteRepository (":memory:");
        var original = repository.create_note ();
        repository.set_content (original.id, "Keep this body");
        repository.flush_all ();

        var duplicate = repository.duplicate_note (original.id);
        assert (duplicate.id != original.id);
        assert (duplicate.title == "Copy of Untitled Note");
        assert (duplicate.content == "Keep this body");
        assert (repository.list_notes ().size == 2);

        repository.set_title (original.id, "Edited before delete");
        repository.delete_note (original.id);
        assert (repository.find_note (original.id) == null);
        assert (repository.find_note (duplicate.id) != null);
        repository.flush_all ();
        assert (!repository.has_pending_changes ());
    } catch (Error error) {
        GLib.Test.message ("Duplicate/delete test failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Registers isolated tests for persistence, search, and identity semantics. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/notes/storage/persist-and-search", test_persistence_and_unicode);
    GLib.Test.add_func ("/notes/storage/duplicate-and-delete", test_duplicate_and_delete);
    return GLib.Test.run ();
}
