#if HAVE_IMAGEKIT
namespace Stickies {
    /**
     * Edits the original-image crop using drag handles or accessible percent controls.
     * ImageKit owns rendering; a bounded header probe supplies only image geometry.
     */
    [GtkTemplate (ui = "/com/majoris/stickies/image-crop-editor.ui")]
    public class ImageCropEditor : Gtk.Window {
        /** Emitted only after a valid crop rectangle is explicitly accepted. */
        public signal void crop_requested (int left, int top, int width, int height);

        [GtkChild]
        private unowned Gtk.Box preview_box;
        [GtkChild]
        private unowned Gtk.SpinButton left_spin;
        [GtkChild]
        private unowned Gtk.SpinButton top_spin;
        [GtkChild]
        private unowned Gtk.SpinButton width_spin;
        [GtkChild]
        private unowned Gtk.SpinButton height_spin;
        [GtkChild]
        private unowned Gtk.Label status_label;
        [GtkChild]
        private unowned Gtk.Button cancel_button;
        [GtkChild]
        private unowned Gtk.Button save_button;

        private CropSelectionOverlay selection;
        private ImageKit.ImageView viewer;
        private bool updating_controls = false;
        private bool image_ready = false;
        private bool geometry_ready = false;

        /** Creates an XML-backed, interactive crop editor for one managed raster. */
        public ImageCropEditor (
            Gtk.Window parent, string path, string mime, GLib.Cancellable cancellable
        ) {
            Object ();
            set_transient_for (parent);
            var frame = new Gtk.Overlay ();
            frame.set_size_request (640, 330);
            var image_holder = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            image_holder.halign = Gtk.Align.CENTER;
            image_holder.valign = Gtk.Align.CENTER;
            viewer = new ImageKit.ImageView ();
            viewer.set_size_request (640, 330);
            image_holder.append (viewer);
            frame.set_child (image_holder);
            selection = new CropSelectionOverlay ();
            selection.halign = Gtk.Align.CENTER;
            selection.valign = Gtk.Align.CENTER;
            selection.sensitive = false;
            frame.add_overlay (selection);
            preview_box.append (frame);
            selection.selection_changed.connect ((x, y, width, height) => {
                updating_controls = true;
                left_spin.set_value (x);
                top_spin.set_value (y);
                width_spin.set_value (width);
                height_spin.set_value (height);
                updating_controls = false;
            });
            left_spin.value_changed.connect (() => update_selection ());
            top_spin.value_changed.connect (() => update_selection ());
            width_spin.value_changed.connect (() => update_selection ());
            height_spin.value_changed.connect (() => update_selection ());
            cancel_button.clicked.connect (() => close ());
            save_button.clicked.connect (() => {
                int x = left_spin.get_value_as_int ();
                int y = top_spin.get_value_as_int ();
                int width = width_spin.get_value_as_int ();
                int height = height_spin.get_value_as_int ();
                if (x + width > 100 || y + height > 100) {
                    status_label.label = "Crop must remain inside the original image";
                    return;
                }
                crop_requested (x, y, width, height);
                close ();
            });
            ImageCropTransfer.probe.begin (
                path, mime, cancellable, (object, result) => {
                    try {
                        var geometry = ImageCropTransfer.probe.end (result);
                        var parts = geometry.split (" ");
                        int width;
                        int height = 0;
                        if (!int.try_parse (parts[0], out width) ||
                            !int.try_parse (parts[1], out height)) {
                            return;
                        }
                        double scale = Math.fmin (640.0 / width, 330.0 / height);
                        int view_width = (int) Math.round (width * scale);
                        int view_height = (int) Math.round (height * scale);
                        viewer.set_size_request (view_width, view_height);
                        selection.set_content_width (view_width);
                        selection.set_content_height (view_height);
                        selection.set_size_request (view_width, view_height);
                        geometry_ready = true;
                        update_ready ();
                    } catch (IOError.CANCELLED error) {
                        return;
                    } catch (Error error) {
                        status_label.label = "Unable to determine original image dimensions";
                    }
                }
            );
            viewer.load_file.begin (
                GLib.File.new_for_path (path), null, cancellable, (object, result) => {
                    try {
                        viewer.load_file.end (result);
                        if (!cancellable.is_cancelled ()) {
                            image_ready = true;
                            update_ready ();
                        }
                    } catch (IOError.CANCELLED error) {
                        return;
                    } catch (Error error) {
                        status_label.label = "Unable to display selected image";
                    }
                }
            );
        }

        /** Applies keyboard-adjusted crop percentages without callback recursion. */
        private void update_selection () {
            if (updating_controls) {
                return;
            }
            int x = left_spin.get_value_as_int ();
            int y = top_spin.get_value_as_int ();
            int width = width_spin.get_value_as_int ();
            int height = height_spin.get_value_as_int ();
            bool valid = x + width <= 100 && y + height <= 100;
            if (valid) {
                selection.set_selection (x, y, width, height);
                status_label.label = "Drag a white handle or change a percentage";
            } else {
                status_label.label = "Crop must remain inside the original image";
            }
            save_button.sensitive = valid && geometry_ready && image_ready;
        }

        /** Enables the crop controls only after geometry and the image are ready. */
        private void update_ready () {
            selection.sensitive = geometry_ready && image_ready;
            update_selection ();
        }
    }
}
#endif
