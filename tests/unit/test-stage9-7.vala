using Stickies;

/** Keeps drag resizing bounded and aligned to the persisted image grid. */
private void test_inline_resize_snap () {
    assert (InlineImageFormat.snap_width (-100) == 96);
    assert (InlineImageFormat.snap_width (96) == 96);
    assert (InlineImageFormat.snap_width (103) == 96);
    assert (InlineImageFormat.snap_width (105) == 112);
    assert (InlineImageFormat.snap_width (951) == 944);
    assert (InlineImageFormat.snap_width (2000) == 960);
}

/** Registers the direct-resize compatibility test without requiring GTK. */
int main (string[] args) {
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/stage9/image/drag-resize-snap", test_inline_resize_snap);
    return GLib.Test.run ();
}
