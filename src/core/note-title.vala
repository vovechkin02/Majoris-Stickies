namespace Stickies {
    /** Derives a bounded, readable heading from a note's opening text. */
    public class NoteTitle : GLib.Object {
        private const int MAX_TITLE_CHARACTERS = 80;

        /** Returns the first nonempty line without inline-media placeholders. */
        public static string derive (string content) {
            foreach (var line in content.split ("\n")) {
                var clean = line.replace (
                    InlineImageFormat.PLACEHOLDER, ""
                ).replace ("\r", "").strip ();
                if (clean == "") {
                    continue;
                }
                if (clean.char_count () <= MAX_TITLE_CHARACTERS) {
                    return clean;
                }
                int limit = clean.index_of_nth_char (MAX_TITLE_CHARACTERS - 1);
                return clean.substring (0, limit) + "…";
            }
            return "Untitled Note";
        }
    }
}
