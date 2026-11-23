using Stickies;

/** Verifies source URLs are extracted only from explicit clipboard provenance. */
private void test_local_source_formats () {
    assert (SourceLink.from_clipboard (
        "text/plain", " https://example.org/article?a=1&b=2 \n"
    ) == "https://example.org/article?a=1&b=2");
    assert (SourceLink.from_clipboard (
        "text/x-moz-url", "https://example.org/story\nArticle title"
    ) == "https://example.org/story");
    assert (SourceLink.from_clipboard (
        "text/uri-list", "# pasted link\r\nhttps://example.org/a\r\n"
    ) == "https://example.org/a");
    assert (SourceLink.from_clipboard (
        "text/html", "Version:1.0\r\nSourceURL:https://example.org/page\r\n" +
        "<html><body><a href='https://unrelated.org'>link</a></body></html>"
    ) == "https://example.org/page");
    assert (SourceLink.from_clipboard (
        "text/html", "<meta name='source-url' content='https://example.org/?a=1&amp;b=2'>"
    ) == "https://example.org/?a=1&b=2");
}

/** Rejects guesses, ambiguity and dangerous or malformed URI schemes. */
private void test_reject_unattributed_content () {
    string[] mime_types = {
        "text/html", "text/uri-list", "text/plain", "text/x-moz-url"
    };
    string[] contents = {
        "<a href='https://example.org/link'>A linked reference</a>",
        "https://example.org/one\nhttps://example.org/two",
        "Here is a URL: https://example.org",
        "javascript:alert(1)\nTitle"
    };
    for (int index = 0; index < mime_types.length; index++) {
        assert (SourceLink.from_clipboard (mime_types[index], contents[index]) == "");
    }
    assert (SourceLink.from_clipboard (
        "text/uri-list", "file:///etc/passwd"
    ) == "");
    assert (SourceLink.from_clipboard (
        "text/html", "SourceURL:https://user:secret@example.org\n"
    ) == "");
    var oversized = new GLib.StringBuilder ();
    for (int index = 0; index < 64 * 1024 + 1; index++) {
        oversized.append_c ('A');
    }
    assert (SourceLink.from_clipboard ("text/plain", oversized.str) == "");
    assert (SourceLink.from_clipboard ("application/octet-stream", "https://example.org") == "");
}

/** Firefox URL/title MIME data may be encoded as UTF-16 without a BOM. */
private void test_utf16_url_clipboard () {
    uint8[] firefox_le = {
        0x68, 0, 0x74, 0, 0x74, 0, 0x70, 0, 0x73, 0, 0x3a, 0,
        0x2f, 0, 0x2f, 0, 0x65, 0, 0x78, 0, 0x2e, 0, 0x6f, 0, 0x72, 0,
        0x67, 0, 0x0a, 0, 0x54, 0, 0x69, 0, 0x74, 0, 0x6c, 0, 0x65, 0
    };
    assert (SourceLink.from_clipboard_bytes (
        "text/x-moz-url", firefox_le, firefox_le.length
    ) == "https://ex.org");
    assert (SourceLink.from_clipboard_bytes (
        "text/html", firefox_le, firefox_le.length
    ) == "");
    uint8[] malformed = { 0x68, 0x00, 0x74 };
    assert (SourceLink.from_clipboard_bytes (
        "text/x-moz-url", malformed, malformed.length
    ) == "");
}

/** Registers the privacy-preserving attribution parser contract. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/source/clipboard/accepted", test_local_source_formats);
    GLib.Test.add_func ("/source/clipboard/rejected", test_reject_unattributed_content);
    GLib.Test.add_func ("/source/clipboard/utf16", test_utf16_url_clipboard);
    return GLib.Test.run ();
}
