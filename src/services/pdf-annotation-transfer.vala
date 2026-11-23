namespace Stickies {
    /**
     * Creates a non-destructive PDF containing genuine, page-scoped Ink objects.
     * The pypdf helper owns document conversion; only the repository can attach
     * files to a note, so no second managed-media persistence path is added.
     */
    public class PdfAnnotationTransfer : GLib.Object {
        /** Attaches a separate annotated PDF and removes the temporary output. */
        public static async void attach (
            NoteRepository repository, string note_id, NoteAttachment original,
            int page, string native_ink_svg, GLib.Cancellable? cancellable
        ) throws Error {
            if (page < 1 || page > 250 || original.mime_type != "application/pdf") {
                throw new IOError.INVALID_ARGUMENT ("Choose a supported PDF page");
            }
            var path = GLib.Path.build_filename (
                GLib.Environment.get_tmp_dir (),
                "stickies-annotated-" + GLib.Uuid.string_random () + ".pdf"
            );
            var output = GLib.File.new_for_path (path);
            try {
                string[] arguments = {
                    "majoris-stickies-pdf-annotate",
                    "--pdf", original.path,
                    "--page", page.to_string (),
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
                        diagnostic != null ? diagnostic.strip () : "PDF annotation failed"
                    );
                }
                yield repository.attach_file (note_id, output, cancellable);
            } finally {
                try {
                    output.delete (null);
                } catch (IOError.NOT_FOUND error) {
                    // An unsuccessful command does not necessarily create an output.
                } catch (Error error) {
                    warning ("Temporary PDF annotation cleanup failed: %s", error.message);
                }
            }
        }
    }
}
