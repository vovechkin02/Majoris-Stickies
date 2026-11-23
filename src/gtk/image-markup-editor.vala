#if HAVE_IMAGEKIT
namespace Stickies {
    /**
     * Displays one managed raster through ImageKit with a transparent ink layer.
     * Emits verified native pen markup; attaching a copy belongs to a service.
     */
    public class ImageMarkupEditor : Gtk.Window {
        /** Emitted only after the user explicitly saves a nonempty sketch. */
        public signal void markup_requested (string svg);

        private InkCanvas canvas;

        /** Creates a modal, non-destructive image markup view. */
        public ImageMarkupEditor (
            Gtk.Window parent, string path, GLib.Cancellable cancellable
        ) {
            Object ();
            title = "Mark Up Image";
            set_transient_for (parent);
            set_modal (true);
            set_default_size (680, 440);

            var layout = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            layout.margin_top = 12;
            layout.margin_bottom = 12;
            layout.margin_start = 12;
            layout.margin_end = 12;

            var preview = new Gtk.Overlay ();
            preview.set_size_request (640, 360);
            preview.halign = Gtk.Align.CENTER;
            var viewer = new ImageKit.ImageView ();
            viewer.set_size_request (640, 360);
            preview.set_child (viewer);
            canvas = new InkCanvas ();
            canvas.set_size_request (640, 360);
            canvas.tooltip_text = "Draw over the image; the original stays unchanged";
            preview.add_overlay (canvas);
            layout.append (preview);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.halign = Gtk.Align.END;
            var clear = new Gtk.Button.with_label ("Clear Ink");
            clear.clicked.connect (() => canvas.clear_ink ());
            actions.append (clear);
            var cancel = new Gtk.Button.with_label ("Cancel");
            cancel.clicked.connect (() => close ());
            actions.append (cancel);
            var save = new Gtk.Button.with_label ("Attach Marked-Up Copy");
            save.add_css_class ("suggested-action");
            save.sensitive = false;
            save.clicked.connect (() => {
                if (!canvas.has_ink ()) {
                    return;
                }
                markup_requested (canvas.to_svg ());
                close ();
            });
            actions.append (save);
            layout.append (actions);
            set_child (layout);

            var source = GLib.File.new_for_path (path);
            viewer.load_file.begin (source, null, cancellable, (object, result) => {
                try {
                    viewer.load_file.end (result);
                    if (!cancellable.is_cancelled ()) {
                        save.sensitive = true;
                    }
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    warning ("Unable to display markup source: %s", error.message);
                }
            });
        }
    }
}
#endif
