namespace Stickies {
    /**
     * Defines preset and accessible custom paper colors used in stored records.
     *
     * The eight legacy tokens remain unchanged. Custom tokens use the canonical
     * lowercase #rrggbb form and are limited to light paper colors for readable
     * dark ink. Neither token class may contain CSS syntax or whitespace.
     */
    public class NotePalette : GLib.Object {
        /** The default paper color for new notes. */
        public const string DEFAULT_COLOR = "yellow";

        /** Returns stable, user-facing preset color identifiers. */
        public static string[] all_colors () {
            string[] colors = {
                "yellow", "pink", "green", "blue",
                "purple", "orange", "teal", "gray"
            };
            return colors;
        }

        /** Converts one ASCII hexadecimal nibble to its numerical value. */
        private static int nibble (char value) {
            if (value >= '0' && value <= '9') {
                return (int) (value - '0');
            }
            if (value >= 'a' && value <= 'f') {
                return (int) (value - 'a') + 10;
            }
            return -1;
        }

        /** Validates canonical custom colors and a minimum perceived brightness. */
        public static bool is_custom (string color) {
            if (color.length != 7 || color[0] != '#') {
                return false;
            }
            int[] rgb = { 0, 0, 0 };
            for (int index = 0; index < 3; index++) {
                int high = nibble (color[1 + index * 2]);
                int low = nibble (color[2 + index * 2]);
                if (high < 0 || low < 0) {
                    return false;
                }
                rgb[index] = (high << 4) | low;
            }
            // Bright paper only: text is always rendered in dark Majoris ink.
            int brightness = rgb[0] * 2126 + rgb[1] * 7152 + rgb[2] * 722;
            return brightness >= 180 * 10000;
        }

        /** Accepts existing preset IDs and safe custom paper tokens. */
        public static bool is_valid (string color) {
            if (is_custom (color)) {
                return true;
            }
            foreach (var candidate in all_colors ()) {
                if (candidate == color) {
                    return true;
                }
            }
            return false;
        }

        /** Provides human-readable names for preset and custom paper colors. */
        public static string label_for (string color) {
            switch (color) {
                case "yellow":
                    return "Yellow";
                case "pink":
                    return "Pink";
                case "green":
                    return "Green";
                case "blue":
                    return "Blue";
                case "purple":
                    return "Purple";
                case "orange":
                    return "Orange";
                case "teal":
                    return "Teal";
                case "gray":
                    return "Gray";
                default:
                    return is_custom (color) ? "Custom " + color : "Unknown";
            }
        }
    }
}
