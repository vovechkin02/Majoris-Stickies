namespace Stickies {
    /**
     * Defines the stable, user-selectable paper colors stored in note records.
     *
     * Palette tokens are storage identifiers, not CSS colors. The presentation
     * layer maps validated tokens to theme classes.
     */
    public class NotePalette : GLib.Object {
        /** The default color used when creating a note. */
        public const string DEFAULT_COLOR = "yellow";

        /** Returns a new array of all available color tokens. */
        public static string[] all_colors () {
            string[] colors = {
                "yellow", "pink", "green", "blue",
                "purple", "orange", "teal", "gray"
            };
            return colors;
        }

        /** Reports whether a persisted token belongs to the supported palette. */
        public static bool is_valid (string color) {
            foreach (var candidate in all_colors ()) {
                if (candidate == color) {
                    return true;
                }
            }

            return false;
        }

        /** Returns a localized-friendly label for a validated color token. */
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
                    return "Unknown";
            }
        }
    }
}
