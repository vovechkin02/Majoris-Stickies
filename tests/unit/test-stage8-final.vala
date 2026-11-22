using Stickies;

/** Tests stable inline attachment references and user-chosen formatting. */
private void test_inline_image_tokens () {
    var identity = "87654321-2222-3333-4444-123456789abc";
    var target = "87654321-2222-3333-4444-123456789abd";
    var token = InlineImageFormat.token (identity, 240);
    string parsed;
    int width;
    assert (InlineImageFormat.parse (token, out parsed, out width));
    assert (parsed == identity);
    assert (width == 240);
    assert (!InlineImageFormat.parse (
        InlineImageFormat.token (identity, 240) + "../../", out parsed, out width
    ));
    assert (InlineImageFormat.token (identity, 640) == "");
    var source = "Before " + InlineImageFormat.PLACEHOLDER + " after";
    var formatting = "7:8:%s\n".printf (token);
    assert (NoteFormatting.is_valid (source, formatting));
    assert (!NoteFormatting.is_valid (source, "7:9:%s\n".printf (token)));
    var mapping = new Gee.HashMap<string, string> ();
    mapping.set (identity, target);
    var converted = InlineImageFormat.remap (formatting, mapping);
    assert (converted.contains (target));
    assert (!converted.contains (identity));
}

/** Tests the bounded font, point-size and RGB token contracts. */
private void test_user_chosen_styles () {
    var family = TextStyleFormat.font_token ("DejaVu Sans");
    string parsed;
    assert (TextStyleFormat.parse_font (family, out parsed));
    assert (parsed == "DejaVu Sans");
    assert (TextStyleFormat.font_token ("bad\nfamily") == "");
    assert (TextStyleFormat.size_token (18) == "point_18");
    assert (TextStyleFormat.size_token (200) == "");
    int size;
    assert (TextStyleFormat.parse_size ("point_18", out size));
    assert (size == 18);
    assert (!TextStyleFormat.parse_size ("point_018", out size));
    string rgb;
    assert (TextStyleFormat.color_token ("FFFFFF") == "rgb_ffffff");
    assert (TextStyleFormat.parse_color ("rgb_ffffff", out rgb));
    assert (!TextStyleFormat.parse_color ("rgb_123xyz", out rgb));
    assert (NoteFormatting.is_valid ("abc", "0:3:%s\n".printf (family)));
    assert (NoteFormatting.is_valid ("abc", "0:3:rgb_abcdef\n"));
    assert (NoteFormatting.is_valid ("abc", "0:3:list-bullet\n"));
}

/** Registers targeted tests without initializing a graphical display. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/stage8/inline-image-tokens", test_inline_image_tokens);
    GLib.Test.add_func ("/stage8/user-chosen-styles", test_user_chosen_styles);
    return GLib.Test.run ();
}
