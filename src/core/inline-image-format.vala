namespace Stickies {
    /**
     * Defines stable inline-image references in existing rich-text spans.
     * Image data always lives in the managed attachment store, never in text.
     */
    public class InlineImageFormat : GLib.Object {
        /** A single Unicode object-replacement character marks the image position. */
        public const string PLACEHOLDER = "\uFFFC";

        /** Builds a validated, path-free style token for one inline image. */
        public static string token (string attachment_id, int width_px) {
            if (!GLib.Uuid.string_is_valid (attachment_id) ||
                !is_supported_width (width_px)) {
                return "";
            }
            return "image_%s_%d".printf (attachment_id, width_px);
        }

        /** Parses a serialized inline image tag without accepting arbitrary paths. */
        public static bool parse (
            string style, out string attachment_id, out int width_px
        ) {
            attachment_id = "";
            width_px = 0;
            if (!style.has_prefix ("image_") || style.length < 45 ||
                style.length > 50) {
                return false;
            }
            var remainder = style.substring (6);
            int separator = remainder.last_index_of_char ('_');
            if (separator < 0) {
                return false;
            }
            var identity = remainder.substring (0, separator);
            int width;
            if (!GLib.Uuid.string_is_valid (identity) ||
                !int.try_parse (remainder.substring (separator + 1), out width) ||
                !is_supported_width (width)) {
                return false;
            }
            attachment_id = identity;
            width_px = width;
            return true;
        }

        /** Rewrites only attachment identities during a verified note duplication. */
        public static string remap (
            string formatting, Gee.Map<string, string> identities
        ) {
            var output = new GLib.StringBuilder ();
            foreach (var line in formatting.split ("\n")) {
                if (line == "") {
                    continue;
                }
                var fields = line.split (":");
                if (fields.length == 3) {
                    string old_id;
                    int width;
                    if (parse (fields[2], out old_id, out width)) {
                        var replacement_id = identities.get (old_id);
                        if (replacement_id != null) {
                            output.append ("%s:%s:%s\n".printf (
                                fields[0], fields[1],
                                token (replacement_id, width)
                            ));
                            continue;
                        }
                    }
                }
                output.append (line);
                output.append_c ('\n');
            }
            return output.str;
        }

        /** Bounds image dimensions to the 16-pixel Majoris spacing scale. */
        public static bool is_supported_width (int width_px) {
            return width_px >= 96 && width_px <= 960 && width_px % 16 == 0;
        }
    }
}
