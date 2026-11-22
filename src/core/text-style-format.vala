namespace Stickies {
    /** Provides bounded serialized identifiers for user-chosen text formatting. */
    public class TextStyleFormat : GLib.Object {
        /** Encodes one installed font name without unsafe separators or markup. */
        public static string font_token (string family) {
            if (!valid_font_name (family)) {
                return "";
            }
            return "face_" + GLib.Uri.escape_string (family, "", false);
        }

        /** Extracts a validated font family from a style identifier. */
        public static bool parse_font (string style, out string family) {
            family = "";
            if (!style.has_prefix ("face_") || style.length > 240) {
                return false;
            }
            var decoded = GLib.Uri.unescape_string (style.substring (5), null);
            if (decoded == null || !valid_font_name (decoded) ||
                font_token (decoded) != style) {
                return false;
            }
            family = decoded;
            return true;
        }

        /** Builds a point-size style inside a visually reasonable range. */
        public static string size_token (int size_points) {
            return size_points >= 8 && size_points <= 72 ?
                "point_%d".printf (size_points) : "";
        }

        /** Parses an arbitrary point size without accepting out-of-range values. */
        public static bool parse_size (string style, out int size_points) {
            size_points = 0;
            if (!style.has_prefix ("point_") ||
                !int.try_parse (style.substring (6), out size_points)) {
                return false;
            }
            return size_token (size_points) == style;
        }

        /** Builds an RGB text-color token without accepting alpha or CSS syntax. */
        public static string color_token (string hex_rgb) {
            if (hex_rgb.length != 6) {
                return "";
            }
            for (int index = 0; index < hex_rgb.length; index++) {
                var digit = hex_rgb[index];
                if (!((digit >= '0' && digit <= '9') ||
                    (digit >= 'a' && digit <= 'f') ||
                    (digit >= 'A' && digit <= 'F'))) {
                    return "";
                }
            }
            return "rgb_" + hex_rgb.down ();
        }

        /** Extracts a validated six-digit RGB foreground color. */
        public static bool parse_color (string style, out string hex_rgb) {
            hex_rgb = "";
            if (!style.has_prefix ("rgb_")) {
                return false;
            }
            var color = style.substring (4);
            if (color_token (color) != style) {
                return false;
            }
            hex_rgb = color;
            return true;
        }

        /** Checks all newly supported user-chosen font/color/size tokens. */
        public static bool supports (string style) {
            string family;
            string color;
            int size;
            return parse_font (style, out family) ||
                parse_color (style, out color) ||
                parse_size (style, out size);
        }

        /** Rejects unsafe font names before persisting or passing to Pango. */
        private static bool valid_font_name (string family) {
            if (!family.validate () || family.length == 0 ||
                family.length > 96) {
                return false;
            }
            for (int index = 0; index < family.length; index++) {
                uint8 code = (uint8) family[index];
                if (code < 32 || code == 127 || code == ':' || code == '\\') {
                    return false;
                }
            }
            return true;
        }
    }
}
