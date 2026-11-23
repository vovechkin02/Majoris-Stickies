using Stickies;

/** Checks canonical paragraph indent and tab style identifiers. */
private void test_paragraph_tokens () {
    var left = ParagraphStyleFormat.metric_token ("li", 720);
    var first = ParagraphStyleFormat.metric_token ("fi", -240);
    assert (left == "para-li_720");
    assert (first == "para-fi_-240");
    string kind;
    int twips;
    assert (ParagraphStyleFormat.parse_metric (first, out kind, out twips));
    assert (kind == "fi" && twips == -240);
    int[] positions = { 1440, 2880 };
    string[] alignments = { "C", "R" };
    var token = ParagraphStyleFormat.tabs_token (positions, alignments);
    assert (token == "para-tabs_1440C_2880R");
    int[] restored;
    string[] restored_alignments;
    assert (ParagraphStyleFormat.parse_tabs (
        token, out restored, out restored_alignments
    ));
    assert (restored.length == 2 && restored_alignments.length == 2);
    assert (restored[0] == 1440 && restored_alignments[1] == "R");
    assert (ParagraphStyleFormat.to_pixels (720) == 48);
    assert (ParagraphStyleFormat.to_pixels (-240) == -16);
}

/** Verifies malformed paragraph tokens never enter the persistent style format. */
private void test_invalid_paragraph_tokens () {
    foreach (var token in new string[] {
        "para-li_-20", "para-li_9999", "para-fi_+240", "para-tabs_0L",
        "para-tabs_1440X", "para-tabs_1440L_480R", "para-tabs_1440L;}",
    }) {
        assert (!ParagraphStyleFormat.supports (token));
        assert (!NoteFormatting.is_valid ("Text", "0:4:%s\n".printf (token)));
    }
}

/** Ensures existing rich text intervals remain the source of truth for HTML. */
private void test_paragraph_html_interchange () {
    var text = "Alpha\tBeta";
    var formatting = (
        "0:10:para-li_720\n0:10:para-ri_360\n" +
        "0:10:para-fi_-240\n0:10:para-tabs_1440C_2880R\n"
    );
    assert (NoteFormatting.is_valid (text, formatting));
    var note = new Note (
        "cb73c4e9-98a3-43e8-af35-68aeb40a28ba", "Paragraph",
        text, "yellow", 10, 11, formatting
    );
    var attachments = new Gee.ArrayList<NoteAttachment> ();
    var html = NoteTransfer.to_html (note, attachments);
    assert (html.contains ("margin-left:48px"));
    assert (html.contains ("margin-right:24px"));
    assert (html.contains ("text-indent:-16px"));
    assert (html.contains ("data-note-tabs=\"1440C_2880R\""));
    assert (html.contains ("Alpha"));
    assert (html.contains ("Beta"));
}

/** Registers paragraph style validation and rich HTML compatibility tests. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/stage9/paragraph/tokens", test_paragraph_tokens);
    GLib.Test.add_func ("/stage9/paragraph/rejection", test_invalid_paragraph_tokens);
    GLib.Test.add_func ("/stage9/paragraph/html", test_paragraph_html_interchange);
    return GLib.Test.run ();
}
