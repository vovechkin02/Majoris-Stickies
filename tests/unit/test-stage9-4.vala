using Stickies;

/** Verifies bounded nested-list tokens survive the existing note schema. */
private void test_nested_list_tokens () {
    var body = "    • First nested item";
    assert (NoteFormatting.is_valid (body, "0:23:list-depth-1\n"));
    assert (NoteFormatting.supports ("list-depth-1"));
    assert (NoteFormatting.supports ("list-depth-6"));
    assert (!NoteFormatting.supports ("list-depth-0"));
    assert (!NoteFormatting.supports ("list-depth-7"));
    assert (!NoteFormatting.supports ("list-depth-1;evil"));
}

/** Verifies automatic first-line titles with Unicode and inline media. */
private void test_first_line_title () {
    assert (NoteTitle.derive ("") == "Untitled Note");
    assert (NoteTitle.derive ("\nHello world\nNext") == "Hello world");
    assert (NoteTitle.derive ("   Résumé  ") == "Résumé");
    var media = InlineImageFormat.PLACEHOLDER + "  Heading";
    assert (NoteTitle.derive (media) == "Heading");
    var long_line = new GLib.StringBuilder ();
    for (int index = 0; index < 100; index++) {
        long_line.append_c ('Z');
    }
    assert (NoteTitle.derive (long_line.str).char_count () == 80);
}

/** Registers core-format checks without any display dependency. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/stage9/list-depth-tokens", test_nested_list_tokens);
    GLib.Test.add_func ("/stage9/first-line-title", test_first_line_title);
    return GLib.Test.run ();
}
