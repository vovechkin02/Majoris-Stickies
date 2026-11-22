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
                // Keep indentation before the marker so nested items stay
                // readable in plain-text exports and on older installations.
                var insertion = position;
                int leading_spaces = 0;
                while (leading_spaces < 24 && !insertion.ends_line ()) {
                    var next = insertion;
                    next.forward_char ();
                    if (buffer.get_text (insertion, next, false) != " ") {
                        break;
                    }
                    insertion = next;
                    leading_spaces++;
                }
                buffer.insert (ref insertion, prefix, -1);
                Gtk.TextIter paragraph_start;
                buffer.get_iter_at_line (out paragraph_start, line);
                var paragraph_end = paragraph_start;
                paragraph_end.forward_to_line_end ();
                var kind_tag = buffer.tag_table.lookup ("list-" + kind);
                if (kind_tag != null) {
                    buffer.apply_tag (kind_tag, paragraph_start, paragraph_end);
                }
                mark_list_depth (buffer, line);
            }
            buffer.end_user_action ();
        }

        /** Continues typed lists on Return, or ends an empty list item. */
        public static bool continue_list (Gtk.TextBuffer buffer) {
            Gtk.TextIter cursor;
            buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
            if (!cursor.ends_line ()) {
                return false;
            }
            var paragraph_start = cursor;
            paragraph_start.set_line_offset (0);
            var current = buffer.get_text (paragraph_start, cursor, false);
            var indentation = new GLib.StringBuilder ();
            int offset = 0;
            while (offset < current.length &&
                (current[offset] == ' ' || current[offset] == '\t')) {
                indentation.append_c (current[offset]);
                offset++;
            }
            var rest = current.substring (offset);
            string prefix = "";
            string kind = "";
            if (rest.has_prefix ("• ")) {
                prefix = "• ";
                kind = "list-bullet";
            } else if (rest.has_prefix ("☐ ") || rest.has_prefix ("☑ ")) {
                prefix = "☐ ";
                kind = "list-checklist";
            } else {
                var dot = rest.index_of (". ");
                int number;
                if (dot > 0 && dot < 9 &&
                    int.try_parse (rest.substring (0, dot), out number) &&
                    number >= 1 && number < 1000000) {
                    prefix = "%d. ".printf (number + 1);
                    kind = "list-numbered";
                }
            }
            if (prefix == "") {
                return false;
            }
            buffer.begin_user_action ();
            var marker_end = paragraph_start;
            var marker_length = rest.has_prefix ("☑ ") ||
                rest.has_prefix ("☐ ") || rest.has_prefix ("• ") ? 2 :
                rest.index_of (". ") + 2;
            marker_end.forward_chars (offset + marker_length);
            if (rest == "• " || rest == "☐ " || rest == "☑ " ||
                (kind == "list-numbered" && rest.length == marker_length)) {
                buffer.delete (ref paragraph_start, ref marker_end);
            } else {
                var to_insert = "\n" + indentation.str + prefix;
                buffer.insert (ref cursor, to_insert, -1);
                Gtk.TextIter start;
                buffer.get_iter_at_mark (out start, buffer.get_insert ());
                start.backward_chars (prefix.char_count ());
                var tag = buffer.tag_table.lookup (kind);
                if (tag != null) {
                    buffer.apply_tag (tag, start, cursor);
                }
                mark_list_depth (buffer, cursor.get_line ());
            }
            buffer.end_user_action ();
            return true;
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
                    // List hierarchy is bounded to six indentation levels.
                    var leading = position;
                    int spaces = 0;
                    while (spaces < 24 && !leading.ends_line ()) {
                        var next = leading;
                        next.forward_char ();
                        if (buffer.get_text (leading, next, false) != " ") {
                            break;
                        }
                        spaces++;
                        leading = next;
                    }
                    if (spaces < 24) {
                        buffer.insert (ref position, "    ", -1);
                    }
                } else {
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
                mark_list_depth (buffer, line);
            }
            buffer.end_user_action ();
        }

        /**
         * Synchronizes bounded nested-list metadata with a paragraph's text.
         *
         * Normal indentation remains plain text; only actual list paragraphs
         * carry the depth marker for native, RTFD, and share interchange.
         */
        private static void mark_list_depth (Gtk.TextBuffer buffer, int line) {
            Gtk.TextIter first;
            buffer.get_iter_at_line (out first, line);
            var last = first;
            last.forward_to_line_end ();
            var content = buffer.get_text (first, last, false);
            int spaces = 0;
            while (spaces < content.length && spaces < 24 &&
                content[spaces] == ' ') {
                spaces++;
            }
            var text = content.substring (spaces);
            bool list_item = text.has_prefix ("• ") || text.has_prefix ("☐ ") ||
                text.has_prefix ("☑ ");
            if (!list_item) {
                int marker = text.index_of (". ");
                int parsed;
                list_item = marker > 0 && marker <= 7 &&
                    int.try_parse (text.substring (0, marker), out parsed) &&
                    parsed >= 1;
            }
            for (int depth = 1; depth <= 6; depth++) {
                var tag = buffer.tag_table.lookup ("list-depth-%d".printf (depth));
                if (tag != null) {
                    buffer.remove_tag (tag, first, last);
                    if (list_item && spaces / 4 == depth) {
                        buffer.apply_tag (tag, first, last);
                    }
                }
            }
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
            // A nested checklist marker begins after its leading indentation.
            var marker_start = start;
            int leading_spaces = 0;
            while (leading_spaces < 24 && !marker_start.ends_line ()) {
                var next = marker_start;
                next.forward_char ();
                if (buffer.get_text (marker_start, next, false) != " ") {
                    break;
                }
                marker_start = next;
                leading_spaces++;
            }
            var current = buffer.get_text (marker_start, end, false);
            int line = position.get_line ();
            buffer.begin_user_action ();
            if (current.has_prefix ("☐ ") || current.has_prefix ("☑ ")) {
                var symbol_end = marker_start;
                symbol_end.forward_char ();
                var replacement = current.has_prefix ("☐ ") ? "☑" : "☐";
                buffer.delete (ref marker_start, ref symbol_end);
                buffer.insert (ref marker_start, replacement, -1);
            } else {
                buffer.insert (ref marker_start, "☐ ", -1);
            }
            mark_list_depth (buffer, line);
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
