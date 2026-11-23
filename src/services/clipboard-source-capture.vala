namespace Stickies {
    /**
     * Reads explicit website provenance only in response to a note paste.
     * It does not examine browser processes, history, tabs or external services.
     */
    public class ClipboardSourceCapture : GLib.Object {
        private const int MAX_READ_BYTES = 64 * 1024;
        private const int READ_CHUNK_BYTES = 8192;

        /** Returns a validated origin, or empty when the clipboard provides none. */
        public static async string detect (
            Gdk.Clipboard clipboard, GLib.Cancellable? cancellable = null
        ) throws Error {
            try {
                var rich = yield read_offer (
                    clipboard, { "text/x-moz-url", "text/uri-list", "text/html",
                      "text/html;charset=utf-8" },
                    cancellable
                );
                if (rich != "") {
                    return rich;
                }
            } catch (IOError.CANCELLED error) {
                throw error;
            } catch (Error error) {
                debug ("No rich clipboard source: %s", error.message);
            }

            try {
                return yield read_offer (
                    clipboard, { "text/plain;charset=utf-8", "text/plain" },
                    cancellable
                );
            } catch (IOError.CANCELLED error) {
                throw error;
            } catch (Error error) {
                debug ("No plain clipboard source: %s", error.message);
                return "";
            }
        }

        /** Reads an entire MIME offer into bounded storage before parsing it. */
        private static async string read_offer (
            Gdk.Clipboard clipboard, string[] mime_types,
            GLib.Cancellable? cancellable
        ) throws Error {
            unowned string offered_mime;
            var input = yield clipboard.read_async (
                mime_types, GLib.Priority.DEFAULT, cancellable, out offered_mime
            );
            if (input == null) {
                return "";
            }
            // The out parameter is borrowed from the asynchronous read result.
            string mime_type = offered_mime;
            try {
                uint8[] bytes = new uint8[MAX_READ_BYTES + 1];
                int used = 0;
                while (used <= MAX_READ_BYTES) {
                    int available = MAX_READ_BYTES + 1 - used;
                    int count = available < READ_CHUNK_BYTES ? available : READ_CHUNK_BYTES;
                    var chunk = yield input.read_bytes_async (
                        count, GLib.Priority.DEFAULT, cancellable
                    );
                    int size = (int) chunk.get_size ();
                    if (size == 0) {
                        return SourceLink.from_clipboard_bytes (
                            mime_type, bytes, used
                        );
                    }
                    if (used + size > MAX_READ_BYTES) {
                        return "";
                    }
                    var data = chunk.get_data ();
                    for (int index = 0; index < size; index++) {
                        bytes[used + index] = data[index];
                    }
                    used += size;
                }
                return "";
            } finally {
                try {
                    input.close (cancellable);
                } catch (Error error) {
                    debug ("Closing clipboard content: %s", error.message);
                }
            }
        }
    }
}
