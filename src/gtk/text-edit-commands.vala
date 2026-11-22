namespace Stickies {
    /**
     * Applies local text-editing commands to one GTK text buffer.
     *
     * Editing remains on the main thread; each operation is one undo group.
     * The persisted rich-text spans are owned by RichTextCodec, not by this class.
     */
    public class TextEditCommands : GLib.Object {
        /** Prefixes each selected line as a simple, portable text list. */
        public static void prefix_lines (Gtk.TextBuffer buffer, string kind) {
            Gtk.TextIter start;
            Gtk.TextIter end;
            if (!buffer.get_selection_bounds (out start, out end)) {
                buffer.get_iter_at_mark (out start, buffer.get_insert ());
                end = start;
            }
            int first = start.get_line ();
            int last = end.get_line ();
            if (end.starts_line () && last > first) {
                last--;
            }
            if (last - first > 10000) {
                return;
            }
            buffer.begin_user_action ();
            for (int line = last; line >= first; line--) {
                Gtk.TextIter position;
                buffer.get_iter_at_line (out position, line);
                string prefix;
                switch (kind) {
                    case "bullet":
                        prefix = "• ";
                        break;
                    case "checklist":
                        prefix = "☐ ";
                        break;
                    case "numbered":
                        prefix = "%d. ".printf (line - first + 1);
                        break;
                    default:
                        buffer.end_user_action ();
                        return;
                }
                buffer.insert (ref position, prefix, -1);
            }
            buffer.end_user_action ();
        }

        /** Indents or outdents selected paragraphs as one undoable edit. */
        public static void indent_lines (Gtk.TextBuffer buffer, bool outdent) {
            Gtk.TextIter start;
            Gtk.TextIter end;
            if (!buffer.get_selection_bounds (out start, out end)) {
                buffer.get_iter_at_mark (out start, buffer.get_insert ());
                end = start;
            }
            int first = start.get_line ();
            int last = end.get_line ();
            if (end.starts_line () && last > first) {
                last--;
            }
            if (last - first > 10000) {
                return;
            }
            buffer.begin_user_action ();
            for (int line = last; line >= first; line--) {
                Gtk.TextIter position;
                buffer.get_iter_at_line (out position, line);
                if (!outdent) {
                    buffer.insert (ref position, "    ", -1);
                    continue;
                }
                var end_of_indent = position;
                int length = 0;
                while (length < 4 && !end_of_indent.ends_line ()) {
                    var next = end_of_indent;
                    next.forward_char ();
                    var symbol = buffer.get_text (end_of_indent, next, false);
                    if (symbol != " ") {
                        if (length == 0 && symbol == "\t") {
                            end_of_indent = next;
                        }
                        break;
                    }
                    end_of_indent = next;
                    length++;
                }
                if (end_of_indent.get_offset () > position.get_offset ()) {
                    buffer.delete (ref position, ref end_of_indent);
                }
            }
            buffer.end_user_action ();
        }

        /** Toggles the checkbox at the cursor or starts a new checklist item. */
        public static void toggle_checklist_item (Gtk.TextBuffer buffer) {
            Gtk.TextIter position;
            buffer.get_iter_at_mark (out position, buffer.get_insert ());
            Gtk.TextIter start = position;
            start.set_line_offset (0);
            Gtk.TextIter end = start;
            if (!end.ends_line ()) {
                end.forward_to_line_end ();
            }
            var current = buffer.get_text (start, end, false);
            buffer.begin_user_action ();
            if (current.has_prefix ("☐ ") || current.has_prefix ("☑ ")) {
                var symbol_end = start;
                symbol_end.forward_char ();
                var replacement = current.has_prefix ("☐ ") ? "☑" : "☐";
                buffer.delete (ref start, ref symbol_end);
                buffer.insert (ref start, replacement, -1);
            } else {
                buffer.insert (ref start, "☐ ", -1);
            }
            buffer.end_user_action ();
        }

        /** Removes editor tags from a selected range without discarding text. */
        public static bool clear_formatting (Gtk.TextBuffer buffer) {
            Gtk.TextIter start;
            Gtk.TextIter end;
            if (!buffer.get_selection_bounds (out start, out end)) {
                return false;
            }
            buffer.begin_user_action ();
            buffer.remove_all_tags (start, end);
            buffer.end_user_action ();
            return true;
        }

        /** Finds the next literal, case-sensitive match, wrapping to the start. */
        public static bool find_next (
            Gtk.TextBuffer buffer, string query, bool case_sensitive = true
        ) {
            if (query == "" || query.char_count () > 1024) {
                return false;
            }
            var flags = case_sensitive ? Gtk.TextSearchFlags.TEXT_ONLY :
                Gtk.TextSearchFlags.TEXT_ONLY | Gtk.TextSearchFlags.CASE_INSENSITIVE;
            Gtk.TextIter start;
            Gtk.TextIter finish;
            Gtk.TextIter match_start;
            Gtk.TextIter match_end;
            buffer.get_selection_bounds (out start, out finish);
            if (!finish.forward_search (
                query, flags, out match_start, out match_end, null
            )) {
                buffer.get_start_iter (out finish);
                if (!finish.forward_search (
                    query, flags,
                    out match_start, out match_end, null
                )) {
                    return false;
                }
            }
            buffer.select_range (match_start, match_end);
            return true;
        }

        /** Replaces a current literal selection, otherwise searches forward. */
        public static bool replace_next (
            Gtk.TextBuffer buffer,
            string query,
            string replacement,
            bool case_sensitive = true
        ) {
            if (query == "" || query.char_count () > 1024 ||
                replacement.char_count () > 4096) {
                return false;
            }
            Gtk.TextIter start;
            Gtk.TextIter end;
            if (!buffer.get_selection_bounds (out start, out end) ||
                (case_sensitive ? buffer.get_text (start, end, false) != query :
                    buffer.get_text (start, end, false).casefold () != query.casefold ())) {
                if (!find_next (buffer, query, case_sensitive)) {
                    return false;
                }
                buffer.get_selection_bounds (out start, out end);
            }
            buffer.begin_user_action ();
            buffer.delete (ref start, ref end);
            buffer.insert (ref start, replacement, -1);
            buffer.end_user_action ();
            return true;
        }

        /** Replaces bounded literal matches without using untrusted regex. */
        public static int replace_all (
            Gtk.TextBuffer buffer,
            string query,
            string replacement,
            bool case_sensitive = true
        ) {
            if (query == "" || query.char_count () > 1024 ||
                replacement.char_count () > 4096) {
                return 0;
            }
            var flags = case_sensitive ? Gtk.TextSearchFlags.TEXT_ONLY :
                Gtk.TextSearchFlags.TEXT_ONLY | Gtk.TextSearchFlags.CASE_INSENSITIVE;
            Gtk.TextIter position;
            buffer.get_start_iter (out position);
            int replaced = 0;
            buffer.begin_user_action ();
            while (replaced < 10000) {
                Gtk.TextIter start;
                Gtk.TextIter end;
                if (!position.forward_search (
                    query, flags, out start, out end, null
                )) {
                    break;
                }
                buffer.delete (ref start, ref end);
                buffer.insert (ref start, replacement, -1);
                position = start;
                replaced++;
            }
            buffer.end_user_action ();
            return replaced;
        }
    }
}
