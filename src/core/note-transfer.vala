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
     * Managed paths are never exported. Bounded inline raster images may be
     * embedded as explicit, validated data URIs by the clipboard caller.
     */
    public class NoteTransfer : GLib.Object {
        private const int MAX_EMBEDDED_IMAGE_BYTES = 1024 * 1024;
        private const int MAX_EMBEDDED_IMAGES = 8;
        private const int MAX_HTML_STYLE_TYPES = 96;
        private const int MAX_HTML_STYLE_BOUNDARIES = 2048;
        private const string[] styles = {
            "bold", "italic", "underline", "strikethrough", "monospace", "large", "small",
            "font-sans", "font-serif", "font-monospace", "size-10", "size-12",
            "size-14", "size-16", "size-18", "size-20", "size-24",
            "text-red", "text-blue", "text-green", "align-left", "align-center",
            "align-right"
        };
        private const string[] open_tags = {
            "<strong>", "<em>", "<u>", "<s>", "<code>",
            "<span style=\"font-size:larger\">", "<span style=\"font-size:smaller\">",
            "<span style=\"font-family:sans-serif\">", "<span style=\"font-family:serif\">",
            "<span style=\"font-family:monospace\">", "<span style=\"font-size:10pt\">",
            "<span style=\"font-size:12pt\">", "<span style=\"font-size:14pt\">",
            "<span style=\"font-size:16pt\">", "<span style=\"font-size:18pt\">",
            "<span style=\"font-size:20pt\">", "<span style=\"font-size:24pt\">",
            "<span style=\"color:#b42318\">", "<span style=\"color:#155eef\">",
            "<span style=\"color:#067647\">", "<span style=\"display:block;text-align:left\">",
            "<span style=\"display:block;text-align:center\">",
            "<span style=\"display:block;text-align:right\">"
        };
        private const string[] close_tags = {
            "</strong>", "</em>", "</u>", "</s>", "</code>", "</span>", "</span>",
            "</span>", "</span>", "</span>", "</span>", "</span>", "</span>",
            "</span>", "</span>", "</span>", "</span>", "</span>", "</span>",
            "</span>", "</span>", "</span>", "</span>"
        };

        /** Reads only a few small verified raster attachments without blocking the UI. */
        public static async Gee.HashMap<string, string> load_embeddable_images_async (
            Gee.List<NoteAttachment> attachments,
            GLib.Cancellable? cancellable = null
        ) throws Error {
            var images = new Gee.HashMap<string, string> ();
            foreach (var attachment in attachments) {
                var mime = attachment.mime_type;
                if (mime != "image/png" && mime != "image/jpeg" &&
                    mime != "image/gif" && mime != "image/webp") {
                    continue;
                }
                if (images.size >= MAX_EMBEDDED_IMAGES) {
                    break;
                }
                var file = GLib.File.new_for_path (attachment.path);
                var info = yield file.query_info_async (
                    "standard::size,standard::type",
                    GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    GLib.Priority.DEFAULT, cancellable
                );
                if (info.get_file_type () != GLib.FileType.REGULAR ||
                    info.get_size () < 0 || info.get_size () > MAX_EMBEDDED_IMAGE_BYTES) {
                    continue;
                }
                uint8[] bytes;
                string? etag;
                yield file.load_contents_async (cancellable, out bytes, out etag);
                if (bytes.length == 0 || bytes.length > MAX_EMBEDDED_IMAGE_BYTES ||
                    !has_supported_image_signature (mime, bytes)) {
                    continue;
                }
                images.set (
                    attachment.id, "data:" + mime + ";base64," + GLib.Base64.encode (bytes)
                );
            }
            return images;
        }

        /** Rejects mislabeled assets before exposing data URIs to other applications. */
        private static bool has_supported_image_signature (string mime, uint8[] content) {
            if (mime == "image/png") {
                return content.length >= 8 &&
                    content[0] == 0x89 && content[1] == 0x50 &&
                    content[2] == 0x4e && content[3] == 0x47 &&
                    content[4] == 0x0d && content[5] == 0x0a &&
                    content[6] == 0x1a && content[7] == 0x0a;
            }
            if (mime == "image/jpeg") {
                return content.length >= 3 && content[0] == 0xff &&
                    content[1] == 0xd8 && content[2] == 0xff;
            }
            if (mime == "image/gif") {
                return content.length >= 6 && content[0] == 0x47 &&
                    content[1] == 0x49 && content[2] == 0x46 &&
                    content[3] == 0x38 && (content[4] == 0x37 || content[4] == 0x39) &&
                    content[5] == 0x61;
            }
            if (mime == "image/webp") {
                return content.length >= 12 && content[0] == 0x52 &&
                    content[1] == 0x49 && content[2] == 0x46 &&
                    content[3] == 0x46 && content[8] == 0x57 &&
                    content[9] == 0x45 && content[10] == 0x42 &&
                    content[11] == 0x50;
            }
            return false;
        }

        /** Copies readable note text, the explicit source and attachment names. */
        public static string to_plain_text (Note note, Gee.List<NoteAttachment> attachments) {
            var output = new GLib.StringBuilder (note.title);
            if (note.content != "") {
                output.append ("\n\n");
                output.append (
                    note.content.replace (InlineImageFormat.PLACEHOLDER, "[Image attachment]")
                );
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
        public static string to_html (
            Note note,
            Gee.List<NoteAttachment> attachments,
            Gee.Map<string, string>? embedded_images = null
        ) {
            var output = new GLib.StringBuilder ("<html><body><h2>");
            output.append (GLib.Markup.escape_text (note.title));
            output.append ("</h2><div style=\"white-space:pre-wrap\">");
            var paragraphs = NoteListStructure.parse (note.content, note.formatting);
            bool has_lists = false;
            if (paragraphs != null) {
                foreach (var paragraph in paragraphs) {
                    if (paragraph.kind != "") {
                        has_lists = true;
                        break;
                    }
                }
            }
            if ((has_lists || note.formatting.contains (":para-")) &&
                paragraphs != null) {
                append_semantic_lists (
                    output, note.content, note.formatting, paragraphs,
                    embedded_images
                );
            } else {
                append_formatted_text (output, note.content, note.formatting, embedded_images);
            }
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
                output.append ("<p>Attachments (original files not copied):</p><ul>");
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

        /** Closes nested HTML lists without leaving any unclosed list items. */
        private static void close_semantic_lists (
            GLib.StringBuilder output, Gee.ArrayList<string> stack,
            bool[] open_items, int target
        ) {
            while (stack.size > target) {
                int top = stack.size - 1;
                if (open_items[top]) {
                    output.append ("</li>");
                    open_items[top] = false;
                }
                var previous = stack.remove_at (top);
                output.append (previous == "numbered" ? "</ol>" : "</ul>");
            }
        }

        /** Opens an HTML list with its bounded semantic kind and start value. */
        private static void open_semantic_list (
            GLib.StringBuilder output, string kind, int start
        ) {
            if (kind == "numbered") {
                output.append_printf ("<ol start=\"%d\">", start);
            } else if (kind == "checklist") {
                output.append ("<ul data-note-list=\"checklist\">");
            } else {
                output.append ("<ul>");
            }
        }

        /** Converts validated paragraph metadata to bounded portable HTML attributes. */
        private static string paragraph_attributes (
            string formatting, int start, int end
        ) {
            int left = 0;
            int right = 0;
            int first = 0;
            bool has_left = false;
            bool has_right = false;
            bool has_first = false;
            string tab_stops = "";
            foreach (var record in formatting.split ("\n")) {
                if (record == "") {
                    continue;
                }
                var fields = record.split (":");
                if (fields.length != 3) {
                    continue;
                }
                int begin;
                int finish = 0;
                if (!int.try_parse (fields[0], out begin) ||
                    !int.try_parse (fields[1], out finish) ||
                    begin >= end || finish <= start) {
                    continue;
                }
                string kind;
                int twips;
                if (ParagraphStyleFormat.parse_metric (
                    fields[2], out kind, out twips
                )) {
                    if (kind == "li") {
                        left = ParagraphStyleFormat.to_pixels (twips);
                        has_left = true;
                    } else if (kind == "ri") {
                        right = ParagraphStyleFormat.to_pixels (twips);
                        has_right = true;
                    } else if (kind == "fi") {
                        first = ParagraphStyleFormat.to_pixels (twips);
                        has_first = true;
                    }
                } else {
                    int[] positions;
                    string[] alignments;
                    if (ParagraphStyleFormat.parse_tabs (
                        fields[2], out positions, out alignments
                    )) {
                        tab_stops = fields[2].substring (10);
                    }
                }
            }
            var attributes = new GLib.StringBuilder ();
            if (has_left || has_right || has_first) {
                attributes.append (" style=\"");
                if (has_left) {
                    attributes.append_printf ("margin-left:%dpx;", left);
                }
                if (has_right) {
                    attributes.append_printf ("margin-right:%dpx;", right);
                }
                if (has_first) {
                    attributes.append_printf ("text-indent:%dpx;", first);
                }
                attributes.append ("\"");
            }
            if (tab_stops != "") {
                // HTML has no CSS equivalent for arbitrary RTF tab alignment.
                // Preserve a safe hint for round-trip-aware consumers.
                attributes.append (" data-note-tabs=\"");
                attributes.append (tab_stops);
                attributes.append ("\"");
            }
            return attributes.str;
        }

        /** Emits real nested UL/OL/LI nodes from the existing stored list spans. */
        private static void append_semantic_lists (
            GLib.StringBuilder output, string content, string formatting,
            Gee.List<NoteListParagraph> paragraphs,
            Gee.Map<string, string>? embedded_images
        ) {
            var stack = new Gee.ArrayList<string> ();
            bool[] open_items = new bool[8];
            foreach (var paragraph in paragraphs) {
                if (paragraph.kind == "") {
                    close_semantic_lists (output, stack, open_items, 0);
                    output.append ("<p");
                    output.append (paragraph_attributes (
                        formatting, paragraph.start, paragraph.end
                    ));
                    output.append (">");
                } else {
                    int target = paragraph.depth + 1;
                    if (target > stack.size + 1) {
                        target = stack.size + 1;
                    }
                    close_semantic_lists (output, stack, open_items, target);
                    if (stack.size == target &&
                        stack.get (target - 1) != paragraph.kind) {
                        close_semantic_lists (output, stack, open_items, target - 1);
                    }
                    if (stack.size == target && open_items[target - 1]) {
                        output.append ("</li>");
                        open_items[target - 1] = false;
                    }
                    if (stack.size < target) {
                        open_semantic_list (
                            output, paragraph.kind, paragraph.number
                        );
                        stack.add (paragraph.kind);
                    }
                    output.append (paragraph.checked_item ?
                        "<li data-checked=\"true\"" : "<li");
                    output.append (paragraph_attributes (
                        formatting, paragraph.start, paragraph.end
                    ));
                    output.append (">");
                    open_items[stack.size - 1] = true;
                }
                int first_byte = paragraph.body_start == content.char_count () ?
                    content.length : content.index_of_nth_char (paragraph.body_start);
                int last_byte = paragraph.end == content.char_count () ?
                    content.length : content.index_of_nth_char (paragraph.end);
                var body = content.substring (first_byte, last_byte - first_byte);
                var styles_for_body = NoteListStructure.slice_styles (
                    formatting, paragraph.body_start, paragraph.end
                );
                append_formatted_text (
                    output, body, styles_for_body, embedded_images
                );
                if (paragraph.kind == "") {
                    output.append ("</p>");
                }
            }
            close_semantic_lists (output, stack, open_items, 0);
        }

        /** Writes bounded rich-text transitions at each Unicode interval boundary. */
        private static void append_formatted_text (
            GLib.StringBuilder output, string content, string serialized,
            Gee.Map<string, string>? embedded_images
        ) {
            var boundaries = new Gee.ArrayList<StyleBoundary> ();
            var opening_tags = new Gee.ArrayList<string> ();
            var closing_tags = new Gee.ArrayList<string> ();
            var tokens = new Gee.ArrayList<string> ();
            var style_indexes = new Gee.HashMap<string, int> ();
            int character_count = content.char_count ();
            for (int index = 0; index < styles.length; index++) {
                opening_tags.add (open_tags[index]);
                closing_tags.add (close_tags[index]);
                tokens.add (styles[index]);
                style_indexes.set (styles[index], index);
            }
            if (NoteFormatting.is_valid (content, serialized)) {
                foreach (var line in serialized.split ("\n")) {
                    if (line == "") {
                        continue;
                    }
                    var fields = line.split (":");
                    var style = fields[2];
                    if (!style_indexes.has_key (style)) {
                        if (opening_tags.size >= MAX_HTML_STYLE_TYPES) {
                            continue;
                        }
                        var opening = opening_tag_for_style (style);
                        if (opening == "") {
                            continue;
                        }
                        style_indexes.set (style, opening_tags.size);
                        opening_tags.add (opening);
                        closing_tags.add ("</span>");
                        tokens.add (style);
                    }
                    var index = style_indexes.get (style);
                    boundaries.add (new StyleBoundary (int.parse (fields[0]), index, 1));
                    boundaries.add (new StyleBoundary (int.parse (fields[1]), index, -1));
                }
            }
            if (boundaries.size > MAX_HTML_STYLE_BOUNDARIES) {
                output.append (GLib.Markup.escape_text (
                    content.replace (InlineImageFormat.PLACEHOLDER, "[Image attachment]")
                ));
                return;
            }
            boundaries.sort ((left, right) => {
                return left.position < right.position ? -1 :
                    (left.position > right.position ? 1 : 0);
            });

            int[] active = new int[opening_tags.size];
            int cursor = 0;
            int event_index = 0;
            while (event_index < boundaries.size) {
                int next = boundaries[event_index].position;
                append_segment (
                    output, content, cursor, next, character_count,
                    active, tokens, embedded_images
                );
                close_active (output, active, closing_tags);
                while (event_index < boundaries.size && boundaries[event_index].position == next) {
                    var event = boundaries[event_index++];
                    active[event.style] += event.delta;
                }
                open_active (output, active, opening_tags);
                cursor = next;
            }
            append_segment (
                output, content, cursor, character_count, character_count,
                active, tokens, embedded_images
            );
            close_active (output, active, closing_tags);
        }

        /** Produces a validated HTML span for a user-selected style token. */
        private static string opening_tag_for_style (string style) {
            string family;
            string rgb;
            int size_points;
            if (TextStyleFormat.parse_font (style, out family)) {
                return "<span style=\"font-family:" + css_font_name (family) + "\">";
            }
            if (TextStyleFormat.parse_color (style, out rgb)) {
                return "<span style=\"color:#" + rgb + "\">";
            }
            if (TextStyleFormat.parse_size (style, out size_points)) {
                return "<span style=\"font-size:%dpt\">".printf (size_points);
            }
            string attachment_id;
            int image_width;
            if (InlineImageFormat.parse (style, out attachment_id, out image_width)) {
                return "<span data-note-inline-image=\"true\">";
            }
            for (int depth = 1; depth <= 6; depth++) {
                if (style == "list-depth-%d".printf (depth)) {
                    return "<span data-note-list-depth=\"%d\">".printf (depth);
                }
            }
            switch (style) {
                case "list-bullet":
                    return "<span data-note-list=\"bullet\">";
                case "list-numbered":
                    return "<span data-note-list=\"numbered\">";
                case "list-checklist":
                    return "<span data-note-list=\"checklist\">";
                default:
                    return "";
            }
        }

        /** CSS-escapes every Unicode character of an untrusted font-family name. */
        private static string css_font_name (string family) {
            var escaped = new GLib.StringBuilder ("'");
            for (int index = 0; index < family.char_count (); index++) {
                var offset = family.index_of_nth_char (index);
                escaped.append_printf ("\\%x ", family.get_char (offset));
            }
            escaped.append ("'");
            return escaped.str;
        }

        /** Escapes Unicode text while replacing inline object markers with readable labels. */
        private static void append_segment (
            GLib.StringBuilder output, string content, int start, int end,
            int character_count,
            int[] active,
            Gee.List<string> tokens,
            Gee.Map<string, string>? embedded_images
        ) {
            if (end <= start) {
                return;
            }
            int start_byte = content.index_of_nth_char (start);
            int end_byte = end == character_count ?
                content.length : content.index_of_nth_char (end);
            var segment = content.substring (start_byte, end_byte - start_byte);
            string image_id = "";
            int image_width = 0;
            for (int index = 0; index < active.length; index++) {
                if (active[index] > 0 && InlineImageFormat.parse (
                    tokens.get (index), out image_id, out image_width
                )) {
                    break;
                }
                image_id = "";
            }
            var source = image_id != "" && embedded_images != null ?
                embedded_images.get (image_id) : null;
            if (end == start + 1 && segment == InlineImageFormat.PLACEHOLDER &&
                source != null && valid_embedded_image (source)) {
                output.append_printf (
                    "<img src=\"%s\" alt=\"Image attachment\" width=\"%d\">",
                    source, image_width
                );
            } else {
                output.append (GLib.Markup.escape_text (
                    segment.replace (InlineImageFormat.PLACEHOLDER, "[Image attachment]")
                ));
            }
        }

        /** Accepts only bounded raster image data URLs, never arbitrary HTML attributes. */
        private static bool valid_embedded_image (string source) {
            bool supported = source.has_prefix ("data:image/png;base64,") ||
                source.has_prefix ("data:image/jpeg;base64,") ||
                source.has_prefix ("data:image/gif;base64,") ||
                source.has_prefix ("data:image/webp;base64,");
            if (!supported || source.length > 1500000) {
                return false;
            }
            int comma = source.index_of_char (',');
            if (comma < 0 || comma + 1 >= source.length) {
                return false;
            }
            for (int index = comma + 1; index < source.length; index++) {
                var symbol = source[index];
                if (!((symbol >= 'A' && symbol <= 'Z') ||
                    (symbol >= 'a' && symbol <= 'z') ||
                    (symbol >= '0' && symbol <= '9') ||
                    symbol == '+' || symbol == '/' || symbol == '=')) {
                    return false;
                }
            }
            return true;
        }

        /** Closes active tags in reverse order, preserving valid HTML nesting. */
        private static void close_active (
            GLib.StringBuilder output, int[] active, Gee.List<string> closing_tags
        ) {
            for (int index = active.length - 1; index >= 0; index--) {
                if (active[index] > 0) {
                    output.append (closing_tags.get (index));
                }
            }
        }

        /** Opens active tags in a deterministic order after each style transition. */
        private static void open_active (
            GLib.StringBuilder output, int[] active, Gee.List<string> opening_tags
        ) {
            for (int index = 0; index < active.length; index++) {
                if (active[index] > 0) {
                    output.append (opening_tags.get (index));
                }
            }
        }
    }
}
