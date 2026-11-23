using Stickies;

/** Confirms nested lists project into semantic paragraph nodes, not only text. */
private void test_semantic_list_model () {
    var text = "1. First\n    • Sub\n    ☑ Done\n2. Last\nAfter";
    var structure = NoteListStructure.parse (text, "");
    assert (structure != null);
    assert (structure.size == 5);
    assert (structure[0].kind == "numbered");
    assert (structure[0].number == 1);
    assert (structure[1].kind == "bullet");
    assert (structure[1].depth == 1);
    assert (structure[2].checked_item);
    assert (structure[3].kind == "numbered");
    assert (structure[4].kind == "");
}

/** Ensures copied HTML uses real nested list elements and keeps inline text styles. */
private void test_semantic_clipboard_html () {
    var content = "1. Main\n    • Child\n2. After\nPlain";
    var note = new Note (
        "f1052bcb-52d1-42a1-a9e6-fdba8e83f4a1", "List", content,
        "yellow", 10, 11, "3:7:bold\n"
    );
    var attachments = new Gee.ArrayList<NoteAttachment> ();
    var html = NoteTransfer.to_html (note, attachments);
    assert (html.contains ("<ol start=\"1\">"));
    assert (html.contains ("<ul><li>Child"));
    assert (html.contains ("<strong>Main</strong>"));
    assert (html.contains ("</li></ul></li>"));
    assert (html.contains ("<p>Plain</p>"));
}

/** Checks Unicode offsets and clipped spans without altering the persisted text. */
private void test_unicode_style_intervals () {
    var text = "• 😀 text";
    var original = "2:3:italic\n";
    var paragraphs = NoteListStructure.parse (text, original);
    assert (paragraphs != null && paragraphs.size == 1);
    assert (paragraphs[0].body_start == 2);
    var slice = NoteListStructure.slice_styles (
        original, paragraphs[0].body_start, paragraphs[0].end
    );
    assert (slice == "0:1:italic\n");
}

/** Empty paragraphs terminate a list rather than inheriting a stale style. */
private void test_empty_list_break () {
    var text = "• First\n\n• Second";
    var paragraphs = NoteListStructure.parse (text, "0:8:list-bullet\n");
    assert (paragraphs != null && paragraphs.size == 3);
    assert (paragraphs[0].kind == "bullet");
    assert (paragraphs[1].kind == "");
    assert (paragraphs[2].kind == "bullet");
}

/** Registers focused, native semantic-list regression checks. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/stage9/list/semantic-model", test_semantic_list_model);
    GLib.Test.add_func ("/stage9/list/html", test_semantic_clipboard_html);
    GLib.Test.add_func ("/stage9/list/unicode", test_unicode_style_intervals);
    GLib.Test.add_func ("/stage9/list/blank-break", test_empty_list_break);
    return GLib.Test.run ();
}
