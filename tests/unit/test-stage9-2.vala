using Gee;
using Stickies;

/** Confirms dynamic fonts, colors, point sizes and lists survive safe HTML export. */
private void test_dynamic_clipboard_styles () {
    var font = TextStyleFormat.font_token ("Sample;position:absolute");
    var note = new Note (
        "eae51042-9c12-4c1e-a6d8-9a8376215faa", "<Title>", "A&💜", "blue", 1, 2,
        "0:1:%s\n0:1:rgb_aa11cc\n0:1:point_23\n0:1:list-bullet\n".printf (font)
    );
    var attachments = new Gee.ArrayList<NoteAttachment> ();
    var html = NoteTransfer.to_html (note, attachments);
    assert (html.contains ("&lt;Title&gt;"));
    assert (html.contains ("A&amp;"));
    assert (html.contains ("font-family:"));
    assert (!html.contains ("position:absolute"));
    assert (html.contains ("color:#aa11cc"));
    assert (html.contains ("font-size:23pt"));
    assert (html.contains ("data-note-list=\"bullet\""));
}

/** Confirms bounded inline image data reaches HTML without exposing managed paths. */
private void test_inline_image_clipboard () {
    var attachment_id = "9c6bc9f9-1969-451b-bc60-b89a9d70fdea";
    var text = "Before " + InlineImageFormat.PLACEHOLDER + " after";
    var note = new Note (
        "b63b5984-5c21-4522-afaf-bad9e5b9777c", "Image", text, "yellow", 1, 2,
        "7:8:image_%s_240\n".printf (attachment_id)
    );
    var attachments = new Gee.ArrayList<NoteAttachment> ();
    attachments.add (new NoteAttachment (
        attachment_id, note.id, "source.png", "image/png", "/secret/private.asset"
    ));
    var data = new Gee.HashMap<string, string> ();
    data.set (attachment_id, "data:image/png;base64,aGVsbG8=");
    var rich = NoteTransfer.to_html (note, attachments, data);
    assert (rich.contains ("<img src=\"data:image/png;base64,aGVsbG8=\""));
    assert (rich.contains ("width=\"240\""));
    assert (!rich.contains ("/secret/private.asset"));
    var plain = NoteTransfer.to_plain_text (note, attachments);
    assert (plain.contains ("[Image attachment]"));
    data.set (attachment_id, "data:image/png;base64,AA\" onerror=\"alert(1)");
    var rejected = NoteTransfer.to_html (note, attachments, data);
    assert (!rejected.contains ("onerror"));
    assert (rejected.contains ("[Image attachment]"));
}

/** Tests the exact search ordering contract while preserving Unicode matching. */
private void test_search_ordering () {
    try {
        var repository = new NoteRepository (":memory:");
        var older = repository.create_note ();
        repository.set_title (older.id, "Alpha notes");
        var newer = repository.create_note ();
        repository.set_title (newer.id, "Alpha notes");
        repository.set_pinned (older.id, true);
        var matches = repository.search_notes ("alpha");
        assert (matches.size == 2);
        assert (matches[0].id == older.id);
        assert (matches[1].id == newer.id);
    } catch (Error error) {
        GLib.Test.message ("Search order failed: %s", error.message);
        assert_not_reached ();
    }
}

/** Registers feature-level clipboard and search regression tests. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/notes/transfer/dynamic-html", test_dynamic_clipboard_styles);
    GLib.Test.add_func ("/notes/transfer/embedded-image", test_inline_image_clipboard);
    GLib.Test.add_func ("/notes/search/pinned-order", test_search_ordering);
    return GLib.Test.run ();
}
