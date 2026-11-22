namespace Stickies {
    /**
     * Imports a bounded, text-only RTF document using the installed parser.
     *
     * The parser runs off the GTK main context with no shell interpolation.
     * It cannot access the notes database and yields only plain UTF-8 text
     * and validated application-owned formatting spans. Unsupported media
     * is intentionally not imported as an executable or embedded object.
     */
    public class RtfImporter : GLib.Object {
        private const int MAX_TRANSFER_BYTES = 3 * 1024 * 1024;

        /** Converts a local file to text and formatting without modifying a note. */
        public static async void import_note (
            GLib.File source,
            GLib.Cancellable? cancellable,
            out string text,
            out string formatting
        ) throws Error {
            var path = source.get_path ();
            if (path == null) {
                throw new IOError.NOT_SUPPORTED ("Choose a local RTF file");
            }
            string[] arguments = { "majoris-stickies-rtf-import", path };
            var process = new GLib.Subprocess.newv (
                arguments,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
            );
            string? output = null;
            string? diagnostic = null;
            yield process.communicate_utf8_async (
                null, cancellable, out output, out diagnostic
            );
            if (!process.get_successful () || output == null ||
                output.length > MAX_TRANSFER_BYTES) {
                throw new IOError.INVALID_DATA (
                    "RTF import failed or exceeds the text/formatting limits"
                );
            }
            var fields = output.split ("\x1e");
            if (fields.length != 2 || !NoteFormatting.is_valid (fields[0], fields[1])) {
                throw new IOError.INVALID_DATA ("The converted RTF has invalid formatting");
            }
            text = fields[0];
            formatting = fields[1];
        }
    }
}
