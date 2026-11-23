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
            Gtk.Window parent, string path, GLib.Cancellable cancellable,
            string mime = "image/png"
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
            var image_holder = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            image_holder.halign = Gtk.Align.CENTER;
            image_holder.valign = Gtk.Align.CENTER;
            image_holder.append (viewer);
            preview.set_child (image_holder);
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
            canvas.sensitive = false;
            bool image_ready = false;
            bool geometry_ready = false;
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

            ImageCropTransfer.probe.begin (
                path, mime, cancellable, (object, result) => {
                    try {
                        var dimensions = ImageCropTransfer.probe.end (result);
                        var parts = dimensions.split (" ");
                        int width;
                        int height = 0;
                        if (!int.try_parse (parts[0], out width) ||
                            !int.try_parse (parts[1], out height)) {
                            return;
                        }
                        double scale = Math.fmin (640.0 / width, 360.0 / height);
                        viewer.set_size_request (
                            (int) Math.round (width * scale),
                            (int) Math.round (height * scale)
                        );
                        canvas.set_image_geometry (width, height);
                        geometry_ready = true;
                        canvas.sensitive = image_ready;
                        save.sensitive = image_ready;
                    } catch (IOError.CANCELLED error) {
                        return;
                    } catch (Error error) {
                        warning ("Unable to qualify markup image geometry: %s", error.message);
                    }
                }
            );
            var source = GLib.File.new_for_path (path);
            viewer.load_file.begin (source, null, cancellable, (object, result) => {
                try {
                    viewer.load_file.end (result);
                    if (!cancellable.is_cancelled ()) {
                        image_ready = true;
                        canvas.sensitive = geometry_ready;
                        save.sensitive = geometry_ready;
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
