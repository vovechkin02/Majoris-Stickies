namespace Stickies {
    /**
     * Places managed images at text-character offsets using GTK4 child anchors.
     * Metadata is a single validated style run over an object character, so no
     * independent attachment decoder or new database schema is required.
     */
    public class InlineImageController : GLib.Object {
        /** Emitted when a user changes the rendered width of an inline image. */
        public signal void changed ();

        private Gtk.TextView text_view;
        private GLib.Cancellable cancellable;

        /** Connects one editor to its own inline media lifecycle. */
        public InlineImageController (
            Gtk.TextView text_view, GLib.Cancellable cancellable
        ) {
            Object ();
            this.text_view = text_view;
            this.cancellable = cancellable;
        }

        /** Reconstructs saved inline anchors after RichTextCodec has loaded runs. */
        public void restore (
            string formatting, Gee.List<NoteAttachment> attachments
        ) {
            var by_id = new Gee.HashMap<string, NoteAttachment> ();
            foreach (var attachment in attachments) {
                if (attachment.is_image ()) {
                    by_id.set (attachment.id, attachment);
                }
            }
            foreach (var line in formatting.split ("\n")) {
                var fields = line.split (":");
                if (fields.length != 3) {
                    continue;
                }
                int start;
                int end = 0;
                string id = "";
                int width_px = 0;
                if (!int.try_parse (fields[0], out start) ||
                    !int.try_parse (fields[1], out end) || end != start + 1 ||
                    !InlineImageFormat.parse (fields[2], out id, out width_px)) {
                    continue;
                }
                var attachment = by_id.get (id);
                if (attachment != null) {
                    create_anchor (start, attachment, width_px);
                }
            }
        }

        /** Inserts one image at the cursor, retaining existing text and style runs. */
        public void insert (NoteAttachment attachment, int width_px = 240) {
            if (!attachment.is_image () ||
                !InlineImageFormat.is_supported_width (width_px)) {
                return;
            }
            Gtk.TextIter cursor;
            var buffer = text_view.buffer;
            buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
            var position = cursor.get_offset ();
            create_anchor (position, attachment, width_px, true);
        }

        /** Turns a placeholder into a child anchor and binds image presentation. */
        private void create_anchor (
            int position,
            NoteAttachment attachment,
            int width_px,
            bool inserting = false
        ) {
            var buffer = text_view.buffer;
            if (position < 0 || position > buffer.get_char_count ()) {
                return;
            }
            Gtk.TextIter start;
            buffer.get_iter_at_offset (out start, position);
            Gtk.TextChildAnchor? anchor = start.get_child_anchor ();
            if (anchor == null) {
                if (!inserting) {
                    var next = start;
                    if (next.is_end ()) {
                        return;
                    }
                    next.forward_char ();
                    if (buffer.get_slice (start, next, true) !=
                        InlineImageFormat.PLACEHOLDER) {
                        return;
                    }
                    buffer.delete (ref start, ref next);
                    buffer.get_iter_at_offset (out start, position);
                }
                anchor = buffer.create_child_anchor (start);
            }
            var style = InlineImageFormat.token (attachment.id, width_px);
            var tag = get_tag (style);
            Gtk.TextIter first;
            buffer.get_iter_at_offset (out first, position);
            var last = first;
            last.forward_char ();
            buffer.apply_tag (tag, first, last);

            var presentation = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            presentation.set_size_request (width_px, -1);
#if HAVE_IMAGEKIT
            var viewer = new ImageKit.ImageView ();
            viewer.set_size_request (width_px, 120);
            presentation.append (viewer);
            var source = GLib.File.new_for_path (attachment.path);
            viewer.load_file.begin (source, null, cancellable, (object, result) => {
                try {
                    viewer.load_file.end (result);
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    warning ("Inline image preview failed: %s", error.message);
                }
            });
#else
            var fallback = new Gtk.Label ("Image preview requires Majoris Image");
            fallback.set_size_request (width_px, 96);
            presentation.append (fallback);
#endif
            var resize_controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var size_label = new Gtk.Label ("%d px".printf (width_px));
            var width_slider = new Gtk.Scale.with_range (
                Gtk.Orientation.HORIZONTAL, 96.0, 960.0, 16.0
            );
            width_slider.hexpand = true;
            width_slider.draw_value = false;
            width_slider.set_value ((double) width_px);
            width_slider.tooltip_text = "Resize image width between 96 and 960 pixels";
            string active_style = style;
            width_slider.value_changed.connect (() => {
                int chosen_width = (int) width_slider.get_value ();
                if (chosen_width % 16 != 0 ||
                    !InlineImageFormat.is_supported_width (chosen_width)) {
                    return;
                }
                Gtk.TextIter current;
                buffer.get_iter_at_child_anchor (out current, anchor);
                var next = current;
                next.forward_char ();
                var old_tag = buffer.tag_table.lookup (active_style);
                if (old_tag != null) {
                    buffer.remove_tag (old_tag, current, next);
                }
                active_style = InlineImageFormat.token (
                    attachment.id, chosen_width
                );
                buffer.apply_tag (get_tag (active_style), current, next);
                presentation.set_size_request (chosen_width, -1);
#if HAVE_IMAGEKIT
                viewer.set_size_request (chosen_width, 120);
#else
                fallback.set_size_request (chosen_width, 96);
#endif
                size_label.label = "%d px".printf (chosen_width);
                changed ();
            });
            resize_controls.append (size_label);
            resize_controls.append (width_slider);
            presentation.append (resize_controls);
            presentation.tooltip_text = attachment.display_name;
            text_view.add_child_at_anchor (presentation, anchor);
        }

        /** Looks up or constructs one editor-local, named image reference tag. */
        private Gtk.TextTag get_tag (string name) {
            var buffer = text_view.buffer;
            var tag = buffer.tag_table.lookup (name);
            if (tag == null) {
                tag = new Gtk.TextTag (name);
                buffer.tag_table.add (tag);
            }
            return tag;
        }
    }
}
