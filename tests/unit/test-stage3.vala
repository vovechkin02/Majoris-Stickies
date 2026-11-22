using Gee;
using Stickies;

/** Ensures only explicit HTTP(S) origins are accepted. */
private void test_source_validation () {
    try {
        assert (SourceLink.normalize (" https://example.com/page?q=x ") ==
            "https://example.com/page?q=x");
        assert (SourceLink.normalize ("") == "");
    } catch (Error error) {
        assert_not_reached ();
    }
    string[] rejected = {
        "file:///etc/passwd", "javascript:alert(1)", "https://user:pass@example.com/",
        "https://", "ftp://example.com/", "example.com"
    };
    foreach (var value in rejected) {
        bool failed = false;
        try {
            SourceLink.normalize (value);
        } catch (Error error) {
            failed = true;
        }
        assert (failed);
    }
}

/** Confirms source URLs survive a stage-2-to-stage-3 database upgrade. */
private void test_source_migration () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-stage3-XXXXXX");
        var path = GLib.Path.build_filename (directory, "notes.db");
        string original_id = "0c9891fa-7e8c-4957-b42c-35082f157ef3";
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
                "window_height INTEGER NOT NULL DEFAULT 330, visible INTEGER NOT NULL DEFAULT 0)"
            ) == Sqlite.OK);
            assert (database.exec (
                "CREATE TABLE attachments (id TEXT PRIMARY KEY NOT NULL, " +
                "note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE, " +
                "display_name TEXT NOT NULL, mime_type TEXT NOT NULL)"
            ) == Sqlite.OK);
            assert (database.exec (
                "INSERT INTO notes (id,title,content,color,created_at_us,updated_at_us) " +
                "VALUES ('0c9891fa-7e8c-4957-b42c-35082f157ef3'," +
                "'Retained','Rich body','pink',100,200)"
            ) == Sqlite.OK);
            assert (database.exec ("PRAGMA user_version=2") == Sqlite.OK);
        }
        {
            var store = new NoteRepository (path);
            var note = store.find_note (original_id);
            assert (note != null);
            assert (note.title == "Retained");
            assert (note.source_url == "");
            store.set_source_url (original_id, "https://example.org/story");
            store.flush_all ();
            assert (store.search_notes ("example.org").size == 1);
            var duplicate = store.duplicate_note (original_id);
            assert (duplicate.source_url == "https://example.org/story");
        }
        {
            var store = new NoteRepository (path);
            var note = store.find_note (original_id);
            assert (note != null);
            assert (note.source_url == "https://example.org/story");
        }
        GLib.FileUtils.remove (path);
        GLib.FileUtils.remove (path + "-wal");
        GLib.FileUtils.remove (path + "-shm");
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("Stage 3 migration failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Ensures HTML export is escaped and rich spans remain correctly nested. */
private void test_copy_formats () {
    var note = new Note (
        "6f64fc9d-4b73-4e8c-b826-c561d8a74bfb", "<Title>",
        "A&B 💜", "yellow", 1, 2, "0:3:bold\n2:5:italic\n",
        false, false, false, 370, 330, false, "https://example.com/?a=1&b=2"
    );
    var attachments = new Gee.ArrayList<NoteAttachment> ();
    attachments.add (new NoteAttachment (
        "46dd49dd-acdf-4353-8bfb-00fa13a16bb9", note.id,
        "photo.png", "image/png", "/not/shared/private.asset"
    ));
    var plain = NoteTransfer.to_plain_text (note, attachments);
    var html = NoteTransfer.to_html (note, attachments);
    assert (plain.contains ("<Title>"));
    assert (plain.contains ("https://example.com/?a=1&b=2"));
    assert (html.contains ("&lt;Title&gt;"));
    assert (html.contains ("A&amp;"));
    assert (html.contains ("<strong>"));
    assert (html.contains ("<em>"));
    assert (html.contains ("photo.png"));
    assert (!plain.contains ("/not/shared"));
    assert (!html.contains ("/not/shared"));
}

/** Registers the scoped Stage 3 storage, validation and clipboard tests. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/notes/source/validation", test_source_validation);
    GLib.Test.add_func ("/notes/storage/stage2-to-stage3", test_source_migration);
    GLib.Test.add_func ("/notes/transfer/clipboard", test_copy_formats);
    return GLib.Test.run ();
}
