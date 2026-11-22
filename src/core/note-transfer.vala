using Gee;

namespace Stickies {
    /** A formatting boundary used only while constructing safe clipboard HTML. */
    internal class StyleBoundary : GLib.Object {
        /** Position in Unicode characters. */
        internal int position;
        /** Index of a supported style. */
        internal int style;
        /** +1 for a start boundary, -1 for an end boundary. */
        internal int delta;

        /** Describes one style opening or closing at a Unicode character offset. */
        internal StyleBoundary (int position, int style, int delta) {
            this.position = position;
            this.style = style;
            this.delta = delta;
        }
    }

    /**
     * Exports self-contained note text and bounded rich HTML to the clipboard.
     * Referenced files are listed by name only; their private paths are not shared.
     */
    public class NoteTransfer : GLib.Object {
        private static string[] styles = {
            "bold", "italic", "underline", "strikethrough", "monospace", "large", "small",
            "font-sans", "font-serif", "font-monospace", "size-10", "size-12",
            "size-14", "size-16", "size-18", "size-20", "size-24",
            "text-red", "text-blue", "text-green", "align-left", "align-center",
            "align-right"
        };
        private static string[] open_tags = {
            "<strong>", "<em>", "<u>", "<s>", "<code>",
            "<span style=\"font-size:larger\">", "<span style=\"font-size:smaller\">",
            "<span style=\"font-family:sans-serif\">", "<span style=\"font-family:serif\">",
            "<span style=\"font-family:monospace\">", "<span style=\"font-size:10pt\">",
            "<span style=\"font-size:12pt\">", "<span style=\"font-size:14pt\">",
            "<span style=\"font-size:16pt\">", "<span style=\"font-size:18pt\">",
            "<span style=\"font-size:20pt\">", "<span style=\"font-size:24pt\">",
            "<span style=\"color:#b42318\">", "<span style=\"color:#155eef\">",
            "<span style=\"color:#067647\">", "<span style=\"text-align:left\">",
            "<span style=\"text-align:center\">", "<span style=\"text-align:right\">"
        };
        private static string[] close_tags = {
            "</strong>", "</em>", "</u>", "</s>", "</code>", "</span>", "</span>",
            "</span>", "</span>", "</span>", "</span>", "</span>", "</span>",
            "</span>", "</span>", "</span>", "</span>", "</span>", "</span>",
            "</span>", "</span>", "</span>", "</span>"
        };

        /** Copies readable note text, the explicit source and attachment names. */
        public static string to_plain_text (Note note, Gee.List<NoteAttachment> attachments) {
            var output = new GLib.StringBuilder (note.title);
            if (note.content != "") {
                output.append ("\n\n");
                output.append (note.content);
            }
            if (note.source_url != "") {
                output.append ("\n\nSource: ");
                output.append (note.source_url);
            }
            if (attachments.size > 0) {
                output.append ("\n\nAttachments (not copied):");
                foreach (var attachment in attachments) {
                    output.append ("\n- ");
                    output.append (attachment.display_name);
                }
            }
            return output.str;
        }

        /** Preserves supported inline styles while escaping all untrusted content. */
        public static string to_html (Note note, Gee.List<NoteAttachment> attachments) {
            var output = new GLib.StringBuilder ("<html><body><h2>");
            output.append (GLib.Markup.escape_text (note.title));
            output.append ("</h2><div style=\"white-space:pre-wrap\">");
            append_formatted_text (output, note.content, note.formatting);
            output.append ("</div>");
            if (note.source_url != "") {
                var escaped = GLib.Markup.escape_text (note.source_url);
                output.append ("<p>Source: <a href=\"");
                output.append (escaped);
                output.append ("\">");
                output.append (escaped);
                output.append ("</a></p>");
            }
            if (attachments.size > 0) {
                output.append ("<p>Attachments (not copied):</p><ul>");
                foreach (var attachment in attachments) {
                    output.append ("<li>");
                    output.append (GLib.Markup.escape_text (attachment.display_name));
                    output.append ("</li>");
                }
                output.append ("</ul>");
            }
            output.append ("</body></html>");
            return output.str;
        }

        /** Writes style-tag transitions at each interval boundary, not per character. */
        private static void append_formatted_text (
            GLib.StringBuilder output, string content, string serialized
        ) {
            var boundaries = new Gee.ArrayList<StyleBoundary> ();
            int character_count = content.char_count ();
            if (NoteFormatting.is_valid (content, serialized)) {
                foreach (var line in serialized.split ("\n")) {
                    if (line == "") {
                        continue;
                    }
                    var fields = line.split (":");
                    int start = int.parse (fields[0]);
                    int end = int.parse (fields[1]);
                    for (int index = 0; index < styles.length; index++) {
                        if (fields[2] == styles[index]) {
                            boundaries.add (new StyleBoundary (start, index, 1));
                            boundaries.add (new StyleBoundary (end, index, -1));
                            break;
                        }
                    }
                }
            }
            boundaries.sort ((left, right) => {
                return left.position < right.position ? -1 :
                    (left.position > right.position ? 1 : 0);
            });

            int[] active = new int[styles.length];
            int cursor = 0;
            int event_index = 0;
            while (event_index < boundaries.size) {
                int next = boundaries[event_index].position;
                append_segment (output, content, cursor, next, character_count);
                close_active (output, active);
                while (event_index < boundaries.size && boundaries[event_index].position == next) {
                    var event = boundaries[event_index++];
                    active[event.style] += event.delta;
                }
                open_active (output, active);
                cursor = next;
            }
            append_segment (output, content, cursor, character_count, character_count);
            close_active (output, active);
        }

        /** Escapes the specified Unicode character range without byte-offset confusion. */
        private static void append_segment (
            GLib.StringBuilder output, string content, int start, int end,
            int character_count
        ) {
            if (end <= start) {
                return;
            }
            int start_byte = content.index_of_nth_char (start);
            int end_byte = end == character_count ?
                content.length : content.index_of_nth_char (end);
            output.append (GLib.Markup.escape_text (
                content.substring (start_byte, end_byte - start_byte)
            ));
        }

        /** Closes all currently active tags in reverse nesting order. */
        private static void close_active (GLib.StringBuilder output, int[] active) {
            for (int index = active.length - 1; index >= 0; index--) {
                if (active[index] > 0) {
                    output.append (close_tags[index]);
                }
            }
        }

        /** Reopens currently active tags in stable nesting order. */
        private static void open_active (GLib.StringBuilder output, int[] active) {
            for (int index = 0; index < active.length; index++) {
                if (active[index] > 0) {
                    output.append (open_tags[index]);
                }
            }
        }
    }
}
