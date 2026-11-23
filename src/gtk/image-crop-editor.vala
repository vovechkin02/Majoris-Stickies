#if HAVE_IMAGEKIT
namespace Stickies {
    /**
     * Offers exact, image-relative cropping without changing the source raster.
     * GTK controls come from the project XML template, and Majoris Image owns
     * preview decoding. The crop service creates the managed copy.
     */
    [GtkTemplate (ui = "/com/majoris/stickies/image-crop-editor.ui")]
    public class ImageCropEditor : Gtk.Window {
        /** Emitted only after the user accepts a valid crop rectangle. */
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

        /** Creates an XML-backed crop editor for one managed raster. */
        public ImageCropEditor (
            Gtk.Window parent, string path, GLib.Cancellable cancellable
        ) {
            Object ();
            set_transient_for (parent);
            var viewer = new ImageKit.ImageView ();
            viewer.set_size_request (640, 330);
            preview_box.append (viewer);
            cancel_button.clicked.connect (() => close ());
            save_button.clicked.connect (() => {
                int x = left_spin.value_as_int;
                int y = top_spin.value_as_int;
                int width = width_spin.value_as_int;
                int height = height_spin.value_as_int;
                if (x + width > 100 || y + height > 100) {
                    status_label.label = "Crop must remain inside the original image";
                    return;
                }
                crop_requested (x, y, width, height);
                close ();
            });

            viewer.load_file.begin (
                GLib.File.new_for_path (path), null, cancellable, (object, result) => {
                    try {
                        viewer.load_file.end (result);
                        if (!cancellable.is_cancelled ()) {
                            save_button.sensitive = true;
                        }
                    } catch (IOError.CANCELLED error) {
                        return;
                    } catch (Error error) {
                        status_label.label = "Unable to display selected image";
                    }
                }
            );
        }
    }
}
#endif
