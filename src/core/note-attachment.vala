namespace Stickies {
    /** Metadata for a managed, read-only attachment in a note. */
    public class NoteAttachment : GLib.Object {
        /** Attachment UUID, independent from the originating filename. */
        public string id { get; private set; }

        /** Note that owns this attachment. */
        public string note_id { get; private set; }

        /** Original file's display name (not a path). */
        public string display_name { get; private set; }

        /** Content-type determined by the local file query. */
        public string mime_type { get; private set; }

        /** Absolute managed path, never supplied by a stored SQL record. */
        public string path { get; private set; }

        /** Constructs the immutable attachment descriptor. */
        public NoteAttachment (
            string id,
            string note_id,
            string display_name,
            string mime_type,
            string path
        ) {
            Object ();
            this.id = id;
            this.note_id = note_id;
            this.display_name = display_name;
            this.mime_type = mime_type;
            this.path = path;
        }

        /** Returns whether the attachment must use Majoris Image for presentation. */
        public bool is_image () {
            return mime_type.has_prefix ("image/");
        }
    }
}
