#if HAVE_IMAGEKIT
namespace Stickies {
    /** Provides accessible selection of one existing page-scoped PDF Ink object. */
    [GtkTemplate (ui = "/com/majoris/stickies/pdf-ink-manager.ui")]
    public class PdfInkManager : Gtk.Window {
        /** Requests that a selected Ink annotation be redrawn into a new PDF. */
        public signal void redraw_requested (int selected_ink);

        /** Requests removal from a new non-destructive PDF copy. */
        public signal void remove_requested (int selected_ink);

        [GtkChild]
        private unowned Gtk.Label prompt_label;
        [GtkChild]
        private unowned Gtk.SpinButton index_spin;
        [GtkChild]
        private unowned Gtk.Button redraw_button;
        [GtkChild]
        private unowned Gtk.Button remove_button;
        [GtkChild]
        private unowned Gtk.Button cancel_button;

        /** Binds the XML controls to the validated selected-page Ink count. */
        public PdfInkManager (Gtk.Window parent, int page, int count) {
            Object ();
            set_transient_for (parent);
            prompt_label.label = "Select one of %d Ink annotations on page %d".printf (
                count, page
            );
            index_spin.set_range (1, count);
            index_spin.set_value (1);
            redraw_button.clicked.connect (() => {
                redraw_requested (index_spin.value_as_int);
                close ();
            });
            remove_button.clicked.connect (() => {
                remove_requested (index_spin.value_as_int);
                close ();
            });
            cancel_button.clicked.connect (() => close ());
        }
    }
}
#endif
