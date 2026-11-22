namespace Stickies {
    /**
     * Scopes a custom paper-color CSS provider to one GTK widget.
     *
     * A CSS provider is not installed globally: different notes may have
     * different custom colors without conflicting with Majoris Theme or other
     * notes. The caller owns the returned provider until its next color change.
     */
    public class NotePaperStyle : GLib.Object {
        /** Returns the sole stylesheet class used for custom paper colors. */
        public static string class_for (string color) {
            return NotePalette.is_custom (color) ? "note-custom" : "note-" + color;
        }

        /** Adds a paper-only CSS override for a validated custom token. */
        public static Gtk.CssProvider? attach (Gtk.Widget widget, string color) {
            if (!NotePalette.is_custom (color)) {
                return null;
            }
            var provider = new Gtk.CssProvider ();
            provider.load_from_string (
                ".note-paper, .note-card { background-color: %s; }".printf (color)
            );
            widget.get_style_context ().add_provider (
                provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1
            );
            return provider;
        }

        /** Removes an earlier override when a window changes its paper color. */
        public static void detach (Gtk.Widget widget, Gtk.CssProvider? provider) {
            if (provider != null) {
                widget.get_style_context ().remove_provider (provider);
            }
        }
    }
}
