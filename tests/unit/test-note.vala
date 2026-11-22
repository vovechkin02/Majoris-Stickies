using Stickies;

/** Ensures direct note updates are validated and modification times advance. */
private void test_note_edit_semantics () {
    var note = new Note ("test-note", "Title", "Text", "yellow", 1000, 1000);
    assert (note.title == "Title");
    assert (!note.update_title ("Title"));
    assert (note.updated_at_us == 1000);

    assert (note.update_title ("Updated"));
    assert (note.title == "Updated");
    int64 after_title = note.updated_at_us;
    assert (after_title > 1000);

    assert (note.update_content ("Unicode π 😀"));
    assert (note.content == "Unicode π 😀");
    assert (note.updated_at_us > after_title);
    assert (!note.update_content ("Unicode π 😀"));
}

/** Ensures rejected color tokens cannot escape into persisted CSS-class names. */
private void test_palette_validation () {
    var note = new Note ("test-color", "Title", "", "unknown", 1, 1);
    assert (note.color == NotePalette.DEFAULT_COLOR);
    assert (!note.update_color ("invalid malicious color"));
    assert (note.color == "yellow");
    assert (note.update_color ("blue"));
    assert (note.color == "blue");
    assert (!note.update_color ("blue"));
    assert (NotePalette.all_colors ().length == 8);
}

/** Registers focused, stable GLib test paths for the note model. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/notes/model/edit-semantics", test_note_edit_semantics);
    GLib.Test.add_func ("/notes/palette/valid-tokens", test_palette_validation);
    return GLib.Test.run ();
}
