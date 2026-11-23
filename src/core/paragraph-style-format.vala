namespace Stickies {
    /**
     * Encodes bounded RTF paragraph geometry in existing style intervals.
     *
     * The persistent note format still uses start:end:style and schema v7.
     * Coordinates are in signed RTF twips, not device pixels, and are scoped
     * to one paragraph. This is portable metadata, not a second document tree.
     */
    public class ParagraphStyleFormat : GLib.Object {
        private const int MAX_MARGIN_TWIPS = 7200;
        private const int MAX_TABS = 12;

        /** Returns an RTF twip token for one supported paragraph metric. */
        public static string metric_token (string kind, int twips) {
            if (kind == "li" || kind == "ri") {
                return twips >= 0 && twips <= MAX_MARGIN_TWIPS ?
                    "para-%s_%d".printf (kind, twips) : "";
            }
            if (kind == "fi") {
                return twips >= -MAX_MARGIN_TWIPS && twips <= MAX_MARGIN_TWIPS ?
                    "para-fi_%d".printf (twips) : "";
            }
            return "";
        }

        /** Parses a canonical, bounded metric token, including negative first indent. */
        public static bool parse_metric (
            string style, out string kind, out int twips
        ) {
            kind = "";
            twips = 0;
            if (!style.has_prefix ("para-") || style.length > 24) {
                return false;
            }
            var pieces = style.substring (5).split ("_");
            if (pieces.length != 2 || !int.try_parse (pieces[1], out twips)) {
                return false;
            }
            var normalized = metric_token (pieces[0], twips);
            if (normalized == "" || normalized != style) {
                return false;
            }
            kind = pieces[0];
            return true;
        }

        /** Encodes strictly increasing tab positions and standard alignment codes. */
        public static string tabs_token (int[] positions, string[] alignments) {
            if (positions.length < 1 || positions.length > MAX_TABS ||
                positions.length != alignments.length) {
                return "";
            }
            var result = new GLib.StringBuilder ("para-tabs");
            int previous = 0;
            for (int index = 0; index < positions.length; index++) {
                int position = positions[index];
                string align = alignments[index];
                if (position <= previous || position > MAX_MARGIN_TWIPS ||
                    align.length != 1 || (align != "L" && align != "R" &&
                    align != "C" && align != "D")) {
                    return "";
                }
                result.append_printf ("_%d%s", position, align);
                previous = position;
            }
            return result.str;
        }

        /** Decodes up to twelve validated tab stops into independent arrays. */
        public static bool parse_tabs (
            string style, out int[] positions, out string[] alignments
        ) {
            positions = new int[0];
            alignments = new string[0];
            if (!style.has_prefix ("para-tabs_") || style.length > 100) {
                return false;
            }
            var records = style.substring (10).split ("_");
            if (records.length < 1 || records.length > MAX_TABS) {
                return false;
            }
            positions = new int[records.length];
            alignments = new string[records.length];
            for (int index = 0; index < records.length; index++) {
                var record = records[index];
                if (record.length < 2) {
                    return false;
                }
                var suffix = record.substring (record.length - 1);
                int position;
                if (!int.try_parse (
                    record.substring (0, record.length - 1), out position
                )) {
                    return false;
                }
                positions[index] = position;
                alignments[index] = suffix;
            }
            return tabs_token (positions, alignments) == style;
        }

        /** Returns true for canonical, bounded paragraph style identifiers. */
        public static bool supports (string style) {
            string kind;
            int twips;
            int[] positions;
            string[] alignments;
            return parse_metric (style, out kind, out twips) ||
                parse_tabs (style, out positions, out alignments);
        }

        /** Converts RTF twips to pixel units using CSS's nominal 96 dpi. */
        public static int to_pixels (int twips) {
            int pixels = twips * 96;
            return pixels >= 0 ? (pixels + 720) / 1440 :
                (pixels - 720) / 1440;
        }
    }
}
