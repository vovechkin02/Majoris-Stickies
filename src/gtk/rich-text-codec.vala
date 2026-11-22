namespace Stickies {
    /**
     * Maps stable text-style intervals to GTK text tags and back.
     *
     * GTK4 removed its old native rich-text serialization format. This codec
     * persists only explicitly supported tags and never serializes GTK internals.
     */
    public class RichTextCodec : GLib.Object {
        /** Defines the supported tags and their stable serialized identifiers. */
        private static string[] styles () {
            return {
                "bold", "italic", "underline", "strikethrough",
                "monospace", "large", "small",
                "font-sans", "font-serif", "font-monospace",
                "size-10", "size-12", "size-14", "size-16", "size-18", "size-20",
                "size-24", "text-red", "text-blue", "text-green",
                "align-left", "align-center", "align-right",
                "list-bullet", "list-numbered", "list-checklist",
                "list-depth-1", "list-depth-2", "list-depth-3",
                "list-depth-4", "list-depth-5", "list-depth-6"
            };
        }

        /** Installs editor-owned tags into the given GTK buffer once. */
        public static void prepare (Gtk.TextBuffer buffer) {
            var bold = new Gtk.TextTag ("bold");
            bold.weight = (int) Pango.Weight.BOLD;
            buffer.tag_table.add (bold);

            var italic = new Gtk.TextTag ("italic");
            italic.style = Pango.Style.ITALIC;
            buffer.tag_table.add (italic);

            var underline = new Gtk.TextTag ("underline");
            underline.underline = Pango.Underline.SINGLE;
            buffer.tag_table.add (underline);

            var strike = new Gtk.TextTag ("strikethrough");
            strike.strikethrough = true;
            buffer.tag_table.add (strike);

            var mono = new Gtk.TextTag ("monospace");
            mono.family = "Monospace";
            buffer.tag_table.add (mono);

            var large = new Gtk.TextTag ("large");
            large.scale = 1.25;
            buffer.tag_table.add (large);

            var small = new Gtk.TextTag ("small");
            small.scale = 0.85;
            buffer.tag_table.add (small);
            foreach (var family in new string[] { "sans", "serif", "monospace" }) {
                var tag = new Gtk.TextTag ("font-" + family);
                tag.family = family == "sans" ? "Sans" :
                    (family == "serif" ? "Serif" : "Monospace");
                buffer.tag_table.add (tag);
            }
            foreach (int point_size in new int[] { 10, 12, 14, 16, 18, 20, 24 }) {
                var tag = new Gtk.TextTag ("size-%d".printf (point_size));
                tag.size_points = (double) point_size;
                buffer.tag_table.add (tag);
            }
            foreach (var color in new string[] { "red", "blue", "green" }) {
                var tag = new Gtk.TextTag ("text-" + color);
                tag.foreground = color;
                buffer.tag_table.add (tag);
            }
            foreach (var alignment in new string[] { "left", "center", "right" }) {
                var tag = new Gtk.TextTag ("align-" + alignment);
                tag.justification = alignment == "left" ? Gtk.Justification.LEFT :
                    (alignment == "center" ? Gtk.Justification.CENTER :
                    Gtk.Justification.RIGHT);
                buffer.tag_table.add (tag);
            }
            // List kinds are semantic paragraph tags; their visible prefixes
            // remain portable text for older databases and plain-text export.
            foreach (var kind in new string[] {
                "list-bullet", "list-numbered", "list-checklist"
            }) {
                buffer.tag_table.add (new Gtk.TextTag (kind));
            }
            // List depth is persisted as paragraph metadata. The visible
            // indentation remains ordinary text for legacy plain-text readers.
            for (int depth = 1; depth <= 6; depth++) {
                buffer.tag_table.add (new Gtk.TextTag (
                    "list-depth-%d".printf (depth)
                ));
            }
            buffer.enable_undo = true;
        }

        /** Loads plain text and style runs while the caller suppresses edit signals. */
        public static void load (Gtk.TextBuffer buffer, string text, string formatting) {
            buffer.text = text;
            if (!NoteFormatting.is_valid (text, formatting)) {
                return;
            }
            foreach (var line in formatting.split ("\n")) {
                if (line == "") {
                    continue;
                }
                var pieces = line.split (":");
                int start_offset;
                int end_offset;
                if (!int.try_parse (pieces[0], out start_offset) ||
                    !int.try_parse (pieces[1], out end_offset)) {
                    continue;
                }
                Gtk.TextIter start;
                Gtk.TextIter end;
                buffer.get_iter_at_offset (out start, start_offset);
                buffer.get_iter_at_offset (out end, end_offset);
                var tag = buffer.tag_table.lookup (pieces[2]);
                if (tag == null && NoteFormatting.supports (pieces[2])) {
                    tag = new Gtk.TextTag (pieces[2]);
                    string family;
                    string color;
                    int size;
                    if (TextStyleFormat.parse_font (pieces[2], out family)) {
                        tag.family = family;
                    } else if (TextStyleFormat.parse_size (
                        pieces[2], out size
                    )) {
                        tag.size_points = (double) size;
                    } else if (TextStyleFormat.parse_color (
                        pieces[2], out color
                    )) {
                        tag.foreground = "#" + color;
                    }
                    buffer.tag_table.add (tag);
                }
                if (tag != null) {
                    buffer.apply_tag (tag, start, end);
                }
            }
        }

        /** Encodes active tag intervals as Unicode-character positions. */
        public static string serialize (Gtk.TextBuffer buffer) {
            var result = new GLib.StringBuilder ();
            var names = new Gee.ArrayList<string> ();
            foreach (var built_in in styles ()) {
                names.add (built_in);
            }
            buffer.tag_table.@foreach ((tag) => {
                if (tag.name != null && TextStyleFormat.supports (tag.name)) {
                    names.add (tag.name);
                }
            });
            foreach (var style in names) {
                var tag = buffer.tag_table.lookup (style);
                if (tag == null) {
                    continue;
                }
                Gtk.TextIter position;
                buffer.get_start_iter (out position);
                int start = position.has_tag (tag) ? 0 : -1;
                while (!position.is_end ()) {
                    var next = position;
                    if (!next.forward_to_tag_toggle (tag)) {
                        next.forward_to_end ();
                    }
                    if (next.get_offset () == position.get_offset ()) {
                        break;
                    }
                    if (start >= 0) {
                        NoteFormatting.append_span (
                            result, start, next.get_offset (), style
                        );
                        start = -1;
                    } else if (!next.is_end () && next.has_tag (tag)) {
                        start = next.get_offset ();
                    }
                    position = next;
                }
            }
            // Inline media tags are dynamic, unlike the fixed character styles.
            // Each tag applies only to its one object-replacement character.
            Gtk.TextIter cursor;
            buffer.get_start_iter (out cursor);
            while (!cursor.is_end ()) {
                if (cursor.get_char () == 0xFFFC) {
                    foreach (var tag in cursor.get_tags ()) {
                        if (tag.name == null) {
                            continue;
                        }
                        string attachment_id;
                        int width_px;
                        if (InlineImageFormat.parse (
                            tag.name, out attachment_id, out width_px
                        )) {
                            NoteFormatting.append_span (
                                result, cursor.get_offset (),
                                cursor.get_offset () + 1, tag.name
                            );
                        }
                    }
                }
                cursor.forward_char ();
            }
            return result.str;
        }

        /** Toggles the chosen formatting on the current text selection. */
        public static bool toggle_selected (Gtk.TextBuffer buffer, string style) {
            if (!NoteFormatting.supports (style)) {
                return false;
            }
            Gtk.TextIter start;
            Gtk.TextIter end;
            if (!buffer.get_selection_bounds (out start, out end)) {
                return false;
            }
            var tag = buffer.tag_table.lookup (style);
            if (tag == null && TextStyleFormat.supports (style)) {
                tag = new Gtk.TextTag (style);
                string family;
                string color;
                int size;
                if (TextStyleFormat.parse_font (style, out family)) {
                    tag.family = family;
                } else if (TextStyleFormat.parse_size (style, out size)) {
                    tag.size_points = (double) size;
                } else if (TextStyleFormat.parse_color (style, out color)) {
                    tag.foreground = "#" + color;
                }
                buffer.tag_table.add (tag);
            }
            if (tag == null) {
                return false;
            }
            buffer.begin_user_action ();
            if (start.has_tag (tag)) {
                buffer.remove_tag (tag, start, end);
            } else {
                buffer.apply_tag (tag, start, end);
            }
            buffer.end_user_action ();
            return true;
        }
    }
}
