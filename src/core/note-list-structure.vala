namespace Stickies {
    /**
     * Describes a single logical paragraph, including its portable list role.
     * Character offsets are half-open and Unicode-based, matching note spans.
     */
    public class NoteListParagraph : GLib.Object {
        /** Start of the complete paragraph in the persisted note body. */
        public int start { get; private set; }

        /** End of the paragraph, excluding its terminating newline. */
        public int end { get; private set; }

        /** Start of the visible item body, excluding the portable list prefix. */
        public int body_start { get; private set; }

        /** List kind: bullet, numbered, checklist, or empty for ordinary text. */
        public string kind { get; private set; }

        /** Hierarchy level, zero-based and bounded to six nesting steps. */
        public int depth { get; private set; }

        /** Explicit ordered-list start value, when numbered. */
        public int number { get; private set; }

        /** Whether the checklist marker is checked. */
        public bool checked_item { get; private set; }

        /** Creates an immutable logical paragraph from validated coordinates. */
        public NoteListParagraph (
            int start, int end, int body_start, string kind,
            int depth, int number, bool checked_item
        ) {
            Object ();
            this.start = start;
            this.end = end;
            this.body_start = body_start;
            this.kind = kind;
            this.depth = depth;
            this.number = number;
            this.checked_item = checked_item;
        }
    }

    /**
     * Projects portable marker text and list-depth spans into semantic paragraphs.
     *
     * The persisted plain text and rich intervals remain the single source of
     * truth. No new database schema or incompatible markup tokens are required.
     */
    public class NoteListStructure : GLib.Object {
        private const int MAX_PARAGRAPHS = 4096;
        private const int MAX_FORMATTING_SPANS = 4096;

        /** Builds bounded semantic paragraphs from a persisted note and its styles. */
        public static Gee.ArrayList<NoteListParagraph>? parse (
            string text, string formatting
        ) {
            var lines = text.split ("\n");
            if (lines.length > MAX_PARAGRAPHS ||
                !NoteFormatting.is_valid (text, formatting)) {
                return null;
            }
            var paragraphs = new Gee.ArrayList<NoteListParagraph> ();
            var styles = formatting.split ("\n");
            if (styles.length > MAX_FORMATTING_SPANS) {
                return null;
            }
            int offset = 0;
            foreach (var line in lines) {
                int length = line.char_count ();
                if (length == 0) {
                    paragraphs.add (new NoteListParagraph (
                        offset, offset, offset, "", 0, 1, false
                    ));
                    offset++;
                    continue;
                }
                int leading_bytes = 0;
                int spaces = 0;
                while (leading_bytes < line.length && spaces < 24) {
                    if (line[leading_bytes] == ' ') {
                        spaces++;
                    } else if (line[leading_bytes] == '\t' && spaces <= 20) {
                        spaces += 4;
                    } else {
                        break;
                    }
                    leading_bytes++;
                }
                var remainder = line.substring (leading_bytes);
                string kind = "";
                int marker_chars = 0;
                int number = 1;
                bool checked_item = false;
                if (remainder.has_prefix ("• ")) {
                    kind = "bullet";
                    marker_chars = 2;
                } else if (remainder.has_prefix ("☐ ") ||
                    remainder.has_prefix ("☑ ")) {
                    kind = "checklist";
                    checked_item = remainder.has_prefix ("☑ ");
                    marker_chars = 2;
                } else {
                    int dot = remainder.index_of (". ");
                    if (dot > 0 && dot <= 7 &&
                        int.try_parse (remainder.substring (0, dot), out number) &&
                        number >= 1 && number <= 999999) {
                        kind = "numbered";
                        marker_chars = dot + 2;
                    }
                }
                int depth = spaces / 4;
                // Include paragraphs whose marker was removed but whose list
                // identity survived as an editor-owned span.
                foreach (var record in styles) {
                    if (record == "") {
                        continue;
                    }
                    var fields = record.split (":");
                    if (fields.length != 3) {
                        continue;
                    }
                    int begin = int.parse (fields[0]);
                    int finish = int.parse (fields[1]);
                    int marker = offset + leading_bytes;
                    if (begin > marker || finish <= marker) {
                        continue;
                    }
                    if (kind == "" && fields[2].has_prefix ("list-") &&
                        fields[2] != "list-depth-1") {
                        switch (fields[2]) {
                            case "list-bullet":
                                kind = "bullet";
                                break;
                            case "list-numbered":
                                kind = "numbered";
                                break;
                            case "list-checklist":
                                kind = "checklist";
                                break;
                        }
                    }
                    if (fields[2].has_prefix ("list-depth-")) {
                        int declared_depth;
                        if (int.try_parse (
                            fields[2].substring (11), out declared_depth
                        ) && declared_depth >= 1 && declared_depth <= 6) {
                            depth = declared_depth;
                        }
                    }
                }
                if (depth > 6) {
                    depth = 6;
                }
                int body_start = offset + (kind == "" ? 0 :
                    leading_bytes + marker_chars);
                paragraphs.add (new NoteListParagraph (
                    offset, offset + length, body_start, kind,
                    depth, number, checked_item
                ));
                offset += length + 1;
            }
            return paragraphs;
        }

        /** Keeps non-list character formatting within one paragraph's bounds. */
        public static string slice_styles (
            string formatting, int start, int end
        ) {
            var result = new GLib.StringBuilder ();
            foreach (var record in formatting.split ("\n")) {
                if (record == "") {
                    continue;
                }
                var fields = record.split (":");
                if (fields.length != 3 || fields[2].has_prefix ("list-")) {
                    continue;
                }
                int begin = int.parse (fields[0]);
                int finish = int.parse (fields[1]);
                if (begin < end && finish > start) {
                    NoteFormatting.append_span (
                        result, (begin > start ? begin : start) - start,
                        (finish < end ? finish : end) - start, fields[2]
                    );
                }
            }
            return result.str;
        }
    }
}
