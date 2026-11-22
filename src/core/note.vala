namespace Stickies {
    /**
     * Owns one editable note's data independently of GTK and persistence.
     *
     * Only the repository changes notes after creation, so notification and
     * saving order remain consistent across multiple windows.
     */
    public class Note : GLib.Object {
        /** Globally unique, stable identifier for persistence and window lookup. */
        public string id { get; private set; }

        /** User-editable note heading, preserved independently of the body. */
        public string title { get; private set; }

        /** UTF-8 plain text body. Rich text is deferred to Stage 2. */
        public string content { get; private set; }

        /** Validated paper-color token from NotePalette. */
        public string color { get; private set; }

        /** Note creation time in microseconds since the Unix epoch. */
        public int64 created_at_us { get; private set; }

        /** Last content/title/color change, as Unix epoch microseconds. */
        public int64 updated_at_us { get; private set; }

        /**
         * Reconstructs a note from validated persisted fields or a new record.
         * Only the NoteRepository should construct stored note instances.
         */
        public Note (
            string id,
            string title,
            string content,
            string color,
            int64 created_at_us,
            int64 updated_at_us
        ) {
            Object ();
            this.id = id;
            this.title = title;
            this.content = content;
            this.color = NotePalette.is_valid (color) ? color : NotePalette.DEFAULT_COLOR;
            this.created_at_us = created_at_us;
            this.updated_at_us = updated_at_us;
        }

        /** Changes the heading, returning false when no actual edit occurred. */
        internal bool update_title (string value) {
            if (title == value) {
                return false;
            }

            title = value;
            touch ();
            return true;
        }

        /** Changes the body, returning false when its text is unchanged. */
        internal bool update_content (string value) {
            if (content == value) {
                return false;
            }

            content = value;
            touch ();
            return true;
        }

        /** Changes the color only for an allowed token. */
        internal bool update_color (string value) {
            if (!NotePalette.is_valid (value) || color == value) {
                return false;
            }

            color = value;
            touch ();
            return true;
        }

        /** Updates the modification timestamp without decreasing its value. */
        private void touch () {
            var current_us = GLib.get_real_time ();
            updated_at_us = current_us > updated_at_us ? current_us : updated_at_us + 1;
        }
    }
}
