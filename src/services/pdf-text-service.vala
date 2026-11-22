namespace Stickies {
    /**
     * Requests bounded, single-page PDF text extraction through Poppler.
     *
     * This service only reads a user-selected managed attachment. It cannot
     * change notes and never performs PDF parsing on the GTK main thread.
     */
    public class PdfTextService : GLib.Object {
        private const int MAX_EXTRACTED_BYTES = 1024 * 1024;

        /** Returns the selected page's UTF-8 text or a typed operation error. */
        public static async string extract_page (
            GLib.File pdf, int page, GLib.Cancellable? cancellable
        ) throws Error {
            if (page < 1 || page > 250) {
                throw new IOError.INVALID_ARGUMENT ("PDF page must be between 1 and 250");
            }
            var path = pdf.get_path ();
            if (path == null) {
                throw new IOError.NOT_SUPPORTED ("Choose a local PDF attachment");
            }
            string[] arguments = {
                "majoris-stickies-pdf-text", "--page", page.to_string (), path
            };
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
                output.length > MAX_EXTRACTED_BYTES) {
                throw new IOError.INVALID_DATA (
                    "PDF text unavailable; install Poppler or open the PDF externally"
                );
            }
            return output;
        }
    }
}
