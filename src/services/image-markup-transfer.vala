namespace Stickies {
    /**
     * Converts validated native pen markup into a managed annotated SVG copy.
     * The helper only embeds encoded raster bytes; it does not decode images.
     */
    public class ImageMarkupTransfer : GLib.Object {
        /** Creates one new attachment, then deletes the private temporary output. */
        public static async void attach (
            NoteRepository repository, string note_id, NoteAttachment attachment,
            string native_ink_svg, GLib.Cancellable? cancellable
        ) throws Error {
            var path = GLib.Path.build_filename (
                GLib.Environment.get_tmp_dir (),
                "stickies-markup-" + GLib.Uuid.string_random () + ".svg"
            );
            var output = GLib.File.new_for_path (path);
            try {
                string[] arguments = {
                    "majoris-stickies-image-markup",
                    "--mime", attachment.mime_type,
                    "--image", attachment.path,
                    "--output", path
                };
                var process = new GLib.Subprocess.newv (
                    arguments,
                    GLib.SubprocessFlags.STDIN_PIPE | GLib.SubprocessFlags.STDERR_PIPE
                );
                string? stdout_text = null;
                string? diagnostic = null;
                yield process.communicate_utf8_async (
                    native_ink_svg, cancellable, out stdout_text, out diagnostic
                );
                if (!process.get_successful ()) {
                    throw new IOError.FAILED (
                        diagnostic != null ? diagnostic.strip () : "Markup conversion failed"
                    );
                }
                yield repository.attach_file (note_id, output, cancellable);
            } finally {
                try {
                    output.delete (null);
                } catch (IOError.NOT_FOUND error) {
                    // Canceled or failed conversions may leave no temporary output.
                } catch (Error error) {
                    warning ("Temporary markup cleanup failed: %s", error.message);
                }
            }
        }
    }
}
