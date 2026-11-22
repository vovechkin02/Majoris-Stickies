namespace Stickies {
    /**
     * Validates the application-owned rich-text run format.
     *
     * Each line is a half-open Unicode-character interval: start:end:style.
     * Coordinates remain independent of UTF-8 byte offsets and GTK internals.
     */
    public class NoteFormatting : GLib.Object {
        private const int MAX_SPANS = 20000;
        private const int MAX_SERIALIZED_BYTES = 1048576;

        /** Returns whether a style identifier is supported by the editor. */
        public static bool supports (string style) {
            switch (style) {
                case "bold":
                case "italic":
                case "underline":
                case "strikethrough":
                case "monospace":
                case "large":
                case "small":
                case "font-sans":
                case "font-serif":
                case "font-monospace":
                case "size-10":
                case "size-12":
                case "size-14":
                case "size-16":
                case "size-18":
                case "size-20":
                case "size-24":
                case "text-red":
                case "text-blue":
                case "text-green":
                case "align-left":
                case "align-center":
                case "align-right":
                    return true;
                default:
                    return false;
            }
        }

        /** Returns true only for bounded, normalized style intervals. */
        public static bool is_valid (string text, string serialized) {
            if (serialized.length > MAX_SERIALIZED_BYTES) {
                return false;
            }
            if (serialized == "") {
                return true;
            }

            var length = text.char_count ();
            int count = 0;
            foreach (var line in serialized.split ("\n")) {
                if (line == "") {
                    continue;
                }
                if (++count > MAX_SPANS) {
                    return false;
                }
                var fields = line.split (":");
                if (fields.length != 3) {
                    return false;
                }
                int start;
                int end;
                if (!int.try_parse (fields[0], out start) ||
                    !int.try_parse (fields[1], out end) ||
                    start < 0 || end <= start || end > length ||
                    !supports (fields[2])) {
                    return false;
                }
            }
            return true;
        }

        /** Appends a valid interval to a persistence string. */
        public static void append_span (
            GLib.StringBuilder output,
            int start,
            int end,
            string style
        ) {
            if (start >= end || !supports (style)) {
                return;
            }
            output.append_printf ("%d:%d:%s\n", start, end, style);
        }
    }
}
