using Stickies;

/** Verifies readable, canonical custom note-paper colors and legacy tokens. */
private void test_custom_paper_colors () {
    assert (NotePalette.all_colors ().length == 8);
    assert (NotePalette.is_valid ("yellow"));
    assert (NotePalette.is_custom ("#efdecb"));
    assert (NotePalette.is_valid ("#c0c0c0"));
    assert (!NotePalette.is_valid ("#000000"));
    assert (!NotePalette.is_valid ("#FFFFFF"));
    assert (!NotePalette.is_valid ("#ff0000; }"));
    var note = new Note ("test-color", "Title", "Body", "#efdecb", 10, 10);
    assert (note.color == "#efdecb");
    assert (!note.update_color ("#000000"));
    assert (note.update_color ("pink"));
}

/** Ensures only supported recurrence intervals advance past missed occurrences. */
private void test_repeating_reminders () {
    try {
        var store = new NoteRepository (":memory:");
        var note = store.create_note ();
        int64 now_us = GLib.get_real_time ();
        int64 day_us = (int64) 24 * 60 * 60 * 1000000;
        int64 deadline_us = now_us + (int64) 60 * 1000000;
        store.set_reminder (note.id, deadline_us, day_us);
        assert (note.reminder_repeat_us == day_us);
        assert (note.remind_at_us == deadline_us);
        store.mark_reminder_notified (note.id, deadline_us + day_us + 1000000);
        assert (note.remind_at_us == deadline_us + 2 * day_us);
        assert (note.reminder_notified_at_us == 0);
        store.mark_reminder_notified (note.id, deadline_us + day_us + 1000000);
        assert (note.remind_at_us == deadline_us + 2 * day_us);
        store.set_reminder (note.id, 0);
        assert (note.remind_at_us == 0);
        assert (note.reminder_repeat_us == 0);
        assert (note.reminder_notified_at_us == 0);
        bool rejected = false;
        try {
            store.set_reminder (note.id, deadline_us, 123456);
        } catch (IOError.INVALID_ARGUMENT error) {
            rejected = true;
        }
        assert (rejected);
        store.flush_all ();
    } catch (Error error) {
        GLib.Test.message ("Recurring reminder test failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Verifies schema-six notes migrate to schema seven without changing note identity. */
private void test_recurring_reminder_migration () {
    try {
        var directory = GLib.DirUtils.make_tmp ("stickies-recurrence-XXXXXX");
        var path = GLib.Path.build_filename (directory, "notes.db");
        string identifier;
        {
            var original = new NoteRepository (path);
            var note = original.create_note ();
            identifier = note.id;
            original.set_color (identifier, "#efdecb");
            original.set_content (identifier, "Keep this content");
            original.flush_all ();
        }
        {
            Sqlite.Database db;
            assert (Sqlite.Database.open (path, out db) == Sqlite.OK);
            assert (db.exec ("ALTER TABLE notes DROP COLUMN reminder_repeat_us") == Sqlite.OK);
            assert (db.exec ("PRAGMA user_version=6") == Sqlite.OK);
        }
        {
            var upgraded = new NoteRepository (path);
            var note = upgraded.find_note (identifier);
            assert (note != null);
            assert (note.color == "#efdecb");
            assert (note.content == "Keep this content");
            assert (note.reminder_repeat_us == 0);
            Sqlite.Database db;
            assert (Sqlite.Database.open (path, out db) == Sqlite.OK);
            Sqlite.Statement statement;
            assert (db.prepare_v2 ("PRAGMA user_version", -1, out statement, null) == Sqlite.OK);
            assert (statement.step () == Sqlite.ROW);
            assert (statement.column_int (0) == 7);
        }
        GLib.FileUtils.remove (path);
        GLib.FileUtils.remove (path + "-wal");
        GLib.FileUtils.remove (path + "-shm");
        GLib.DirUtils.remove (directory);
    } catch (Error error) {
        GLib.Test.message ("Schema-v7 migration failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Registers the new paper-color, recurrence, and migration qualification cases. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/stage9/custom-paper/validation", test_custom_paper_colors);
    GLib.Test.add_func ("/stage9/reminders/recurrence", test_repeating_reminders);
    GLib.Test.add_func ("/stage9/reminders/schema-v7", test_recurring_reminder_migration);
    return GLib.Test.run ();
}
