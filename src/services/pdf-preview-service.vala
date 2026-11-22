namespace Stickies {
    /**
     * Delegates optional, bounded PDF-page rasterization to the Poppler helper
     * and returns a temporary PNG solely for ImageKit consumption.
     * This service never tries to decode a PDF as an ordinary image file.
     */
    public class PdfPreviewService : GLib.Object {
        private const int MAX_PNG_BYTES = 6 * 1024 * 1024;

        /** Produces a bounded page preview off the GTK thread. */
        public static async GLib.File render_page (
            GLib.File pdf,
            int page,
            GLib.Cancellable? cancellable
        ) throws Error {
            return yield render_page_scaled (pdf, page, 640, cancellable);
        }

        /** Renders one page at a selected, explicitly bounded zoom level. */
        public static async GLib.File render_page_scaled (
            GLib.File pdf,
            int page,
            int edge,
            GLib.Cancellable? cancellable
        ) throws Error {
            if (page < 1 || page > 250) {
                throw new IOError.INVALID_ARGUMENT ("PDF page must be 1–250");
            }
            if (edge != 320 && edge != 640 && edge != 960 && edge != 1280) {
                throw new IOError.INVALID_ARGUMENT ("Unsupported PDF zoom level");
            }
            var path = pdf.get_path ();
            if (path == null) {
                throw new IOError.NOT_SUPPORTED ("PDF previews require a local attachment");
            }
            string[] argv = {
                "majoris-stickies-pdf-preview", "--page", page.to_string (),
                "--edge", edge.to_string (), path
            };
            var process = new GLib.Subprocess.newv (
                argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
            );
            string? output = null;
            string? diagnostic = null;
            yield process.communicate_utf8_async (
                null, cancellable, out output, out diagnostic
            );
            if (!process.get_successful () || output == null) {
                throw new IOError.FAILED (
                    "PDF preview unavailable; install poppler-utils or open externally"
                );
            }
            var thumbnail_path = output.strip ();
            var expected_prefix = GLib.Path.build_filename (
                GLib.Environment.get_tmp_dir (), "majoris-stickies-pdf-"
            );
            if (!thumbnail_path.has_prefix (expected_prefix) ||
                !thumbnail_path.has_suffix ("/page.png")) {
                throw new IOError.INVALID_DATA ("Invalid PDF preview output path");
            }
            var thumbnail = GLib.File.new_for_path (thumbnail_path);
            var info = yield thumbnail.query_info_async (
                "standard::size,standard::type",
                GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                GLib.Priority.DEFAULT,
                cancellable
            );
            if (info.get_file_type () != GLib.FileType.REGULAR ||
                info.get_size () <= 0 || info.get_size () > MAX_PNG_BYTES) {
                throw new IOError.INVALID_DATA ("PDF preview is not a bounded regular file");
            }
            return thumbnail;
        }

        /** Preserves compatibility with callers requesting the first page. */
        public static async GLib.File render_first_page (
            GLib.File pdf, GLib.Cancellable? cancellable
        ) throws Error {
            return yield render_page (pdf, 1, cancellable);
        }

        /** Releases a temporary PNG and its private directory after display. */
        public static void delete_preview (GLib.File preview) {
            try {
                preview.delete (null);
                var directory = preview.get_parent ();
                if (directory != null) {
                    directory.delete (null);
                }
            } catch (Error error) {
                warning ("Unable to release PDF preview: %s", error.message);
            }
        }
    }
}
