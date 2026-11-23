namespace Stickies {
    /**
     * Saves a bounded, normalized raster crop as a self-contained SVG attachment.
     * Majoris Image displays the result and the original remains unchanged.
     */
    public class ImageCropTransfer : GLib.Object {
        /** Probes bounded raster geometry without decoding pixels in the editor. */
        public static async string probe (
            string path, string mime, GLib.Cancellable? cancellable
        ) throws Error {
            string[] argv = {
                "majoris-stickies-image-crop", "--probe",
                "--image", path, "--mime", mime
            };
            var process = new GLib.Subprocess.newv (
                argv,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
            );
            string? output = null;
            string? diagnostic = null;
            yield process.communicate_utf8_async (
                null, cancellable, out output, out diagnostic
            );
            if (!process.get_successful () || output == null || output.length > 32) {
                throw new IOError.INVALID_DATA (
                    diagnostic != null ? diagnostic.strip () : "Invalid image dimensions"
                );
            }
            var fields = output.strip ().split (" ");
            int width = 0;
            int height = 0;
            if (fields.length != 2 || !int.try_parse (fields[0], out width) ||
                !int.try_parse (fields[1], out height) ||
                width < 1 || height < 1 || width > 20000 || height > 20000) {
                throw new IOError.INVALID_DATA ("Invalid raster geometry");
            }
            return "%d %d".printf (width, height);
        }

        /** Creates one managed non-destructive crop and deletes its private working file. */
        public static async void attach (
            NoteRepository repository, string note_id, NoteAttachment original,
            int left, int top, int width, int height,
            GLib.Cancellable? cancellable
        ) throws Error {
            if (left < 0 || top < 0 || width < 1 || height < 1 ||
                left + width > 100 || top + height > 100) {
                throw new IOError.INVALID_ARGUMENT ("Invalid crop rectangle");
            }
            var path = GLib.Path.build_filename (
                GLib.Environment.get_tmp_dir (),
                "stickies-crop-" + GLib.Uuid.string_random () + ".svg"
            );
            var output = GLib.File.new_for_path (path);
            try {
                string[] arguments = {
                    "majoris-stickies-image-crop",
                    "--image", original.path,
                    "--mime", original.mime_type,
                    "--output", path,
                    "--left", left.to_string (),
                    "--top", top.to_string (),
                    "--width", width.to_string (),
                    "--height", height.to_string ()
                };
                var process = new GLib.Subprocess.newv (
                    arguments,
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
                );
                string? output_text = null;
                string? diagnostic = null;
                yield process.communicate_utf8_async (
                    null, cancellable, out output_text, out diagnostic
                );
                if (!process.get_successful ()) {
                    throw new IOError.FAILED (
                        diagnostic != null ? diagnostic.strip () : "Image crop failed"
                    );
                }
                yield repository.attach_file (note_id, output, cancellable);
            } finally {
                try {
                    output.delete (null);
                } catch (IOError.NOT_FOUND error) {
                    // A canceled crop may not have written its temporary image.
                } catch (Error error) {
                    warning ("Temporary cropped image cleanup failed: %s", error.message);
                }
            }
        }
    }
}
