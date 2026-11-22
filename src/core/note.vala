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

        /** UTF-8 plain text body; formatting is stored separately. */
        public string content { get; private set; }

        /** Bounded style intervals expressed in Unicode character positions. */
        public string formatting { get; private set; default = ""; }

        /** Optional user-verified HTTP(S) origin for this note or capture. */
        public string source_url { get; private set; default = ""; }

        /** Whether only the note header is displayed. */
        public bool is_collapsed { get; private set; default = false; }

        /** Preferred always-on-top state, subject to shell support. */
        public bool is_floating { get; private set; default = false; }

        /** Whether the editor uses translucent paper. */
        public bool is_translucent { get; private set; default = false; }

        /** Last noncollapsed editor window width in logical pixels. */
        public int window_width { get; private set; default = 370; }

        /** Last noncollapsed editor window height in logical pixels. */
        public int window_height { get; private set; default = 330; }

        /** Whether the note window was open when Stickies last stopped. */
        public bool is_visible { get; private set; default = false; }

        /** Reminder deadline in Unix microseconds, or zero when disabled. */
        public int64 remind_at_us { get; private set; default = 0; }

        /** Repeat cadence in microseconds: zero, 24 hours, or 7 days. */
        public int64 reminder_repeat_us { get; private set; default = 0; }

        /** Last successfully scheduled notification time for the current reminder. */
        public int64 reminder_notified_at_us { get; private set; default = 0; }

        /** Lifecycle state: 0 active, 1 archived, 2 in Trash. */
        public int status { get; private set; default = 0; }

        /** Whether this active note should appear above unpinned notes. */
        public bool is_pinned { get; private set; default = false; }

        /** Whether edits to the first nonempty line should update the note title. */
        public bool auto_title { get; private set; default = false; }

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
            int64 updated_at_us,
            string formatting = "",
            bool is_collapsed = false,
            bool is_floating = false,
            bool is_translucent = false,
            int window_width = 370,
            int window_height = 330,
            bool is_visible = false,
            string source_url = "",
            int64 remind_at_us = 0,
            int64 reminder_notified_at_us = 0,
            int status = 0,
            bool is_pinned = false,
            bool auto_title = false,
            int64 reminder_repeat_us = 0
        ) {
            Object ();
            this.id = id;
            this.title = title;
            this.content = content;
            this.color = NotePalette.is_valid (color) ? color : NotePalette.DEFAULT_COLOR;
            this.status = status >= 0 && status <= 2 ? status : 0;
            this.is_pinned = is_pinned;
            this.auto_title = auto_title;
            this.created_at_us = created_at_us;
            this.updated_at_us = updated_at_us;
            this.formatting = NoteFormatting.is_valid (content, formatting) ? formatting : "";
            this.is_collapsed = is_collapsed;
            this.is_floating = is_floating;
            this.is_translucent = is_translucent;
            this.window_width = window_width >= 240 && window_width <= 4000 ? window_width : 370;
            this.window_height = window_height >= 120 && window_height <= 4000 ? window_height : 330;
            this.is_visible = is_visible;
            this.remind_at_us = remind_at_us > 0 ? remind_at_us : 0;
            this.reminder_repeat_us = this.remind_at_us > 0 &&
                is_valid_repeat (reminder_repeat_us) ? reminder_repeat_us : 0;
            this.reminder_notified_at_us = this.remind_at_us > 0 &&
                reminder_notified_at_us > 0 ? reminder_notified_at_us : 0;
            try {
                this.source_url = SourceLink.normalize (source_url);
            } catch (Error error) {
                warning ("Ignoring an invalid stored source URL: %s", error.message);
                this.source_url = "";
            }
        }

        /** Sets the new note's title behavior before its first durable INSERT. */
        internal void set_initial_title_mode (bool value) {
            auto_title = value;
        }

        /** Moves a note through the active, archived, and Trash lifecycle. */
        internal bool update_status (int value) {
            if (value < 0 || value > 2 || status == value) {
                return false;
            }
            status = value;
            touch ();
            return true;
        }

        /** Changes a note's priority without modifying its contents. */
        internal bool update_pinned (bool value) {
            if (is_pinned == value) {
                return false;
            }
            is_pinned = value;
            touch ();
            return true;
        }

        /** Applies a validated origin without corrupting the existing note. */
        internal bool update_source_url (string value) throws Error {
            var normalized = SourceLink.normalize (value);
            if (source_url == normalized) {
                return false;
            }
            source_url = normalized;
            touch ();
            return true;
        }

        /** Accepts only the two documented fixed-duration recurrence choices. */
        public static bool is_valid_repeat (int64 interval_us) {
            return interval_us == 0 ||
                interval_us == (int64) 24 * 60 * 60 * 1000000 ||
                interval_us == (int64) 7 * 24 * 60 * 60 * 1000000;
        }

        /** Schedules one-shot or fixed-duration reminders; zero clears both. */
        internal bool update_reminder (int64 deadline_us, int64 interval_us = 0) {
            if (deadline_us < 0 || !is_valid_repeat (interval_us) ||
                (deadline_us == remind_at_us && interval_us == reminder_repeat_us)) {
                return false;
            }
            remind_at_us = deadline_us;
            reminder_repeat_us = deadline_us == 0 ? 0 : interval_us;
            reminder_notified_at_us = 0;
            return true;
        }

        /** Records a one-shot delivery or advances a recurring reminder safely. */
        internal bool mark_reminder_notified (int64 now_us) {
            if (remind_at_us == 0 || reminder_notified_at_us != 0 ||
                now_us < remind_at_us) {
                return false;
            }
            if (reminder_repeat_us > 0) {
                int64 periods = (now_us - remind_at_us) / reminder_repeat_us + 1;
                if (periods <= (int64.MAX - remind_at_us) / reminder_repeat_us) {
                    remind_at_us += periods * reminder_repeat_us;
                    reminder_notified_at_us = 0;
                    return true;
                }
                reminder_repeat_us = 0;
            }
            reminder_notified_at_us = now_us;
            return true;
        }

        /** Changes the heading, returning false when no actual edit occurred. */
        internal bool update_title (string value, bool automatic = false) {
            if (title == value && auto_title == automatic) {
                return false;
            }

            title = value;
            auto_title = automatic;
            touch ();
            return true;
        }

        /** Changes the body, returning false when its text is unchanged. */
        internal bool update_content (string value) {
            if (content == value) {
                return false;
            }

            content = value;
            formatting = "";
            touch ();
            return true;
        }

        /** Updates the text and all formatting as one atomic in-memory revision. */
        internal bool update_body (string text, string spans) {
            if (!NoteFormatting.is_valid (text, spans)) {
                return false;
            }
            if (content == text && formatting == spans) {
                return false;
            }
            content = text;
            formatting = spans;
            touch ();
            return true;
        }

        /** Changes note-window preferences without altering the edit timestamp. */
        internal bool update_presentation (
            bool collapsed,
            bool floating,
            bool translucent,
            int width,
            int height,
            bool visible
        ) {
            if (width < 240 || width > 4000 || height < 120 || height > 4000) {
                return false;
            }
            if (is_collapsed == collapsed && is_floating == floating &&
                is_translucent == translucent && window_width == width &&
                window_height == height && is_visible == visible) {
                return false;
            }
            is_collapsed = collapsed;
            is_floating = floating;
            is_translucent = translucent;
            window_width = width;
            window_height = height;
            is_visible = visible;
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
