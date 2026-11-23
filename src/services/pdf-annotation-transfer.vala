namespace Stickies {
    /**
     * Creates a non-destructive PDF containing genuine, page-scoped Ink objects.
     * The pypdf helper owns document conversion; only the repository can attach
     * files to a note, so no second managed-media persistence path is added.
     */
    public class PdfAnnotationTransfer : GLib.Object {
        /** Lists selectable Ink annotations without reading untrusted JSON in GTK. */
        public static async int count_ink (
            NoteAttachment original, int page, GLib.Cancellable? cancellable
        ) throws Error {
            if (page < 1 || page > 250 || original.mime_type != "application/pdf") {
                throw new IOError.INVALID_ARGUMENT ("Choose a supported PDF page");
            }
            string[] arguments = {
                "majoris-stickies-pdf-annotate", "--list-ink",
                "--pdf", original.path, "--page", page.to_string ()
            };
            var process = new GLib.Subprocess.newv (
                arguments,
                GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
            );
            string? result = null;
            string? diagnostic = null;
            yield process.communicate_utf8_async (
                null, cancellable, out result, out diagnostic
            );
            int count = 0;
            if (!process.get_successful () || result == null || result.length > 8 ||
                !int.try_parse (result.strip (), out count) || count < 0 || count > 1000) {
                throw new IOError.INVALID_DATA (
                    diagnostic != null ? diagnostic.strip () : "Unable to list PDF Ink"
                );
            }
            return count;
        }

        /** Renders edits against a temporary copy without the selected old Ink. */
        public static async GLib.File prepare_redraw_preview (
            NoteAttachment original, int page, int selected_ink,
            GLib.Cancellable? cancellable
        ) throws Error {
            if (page < 1 || page > 250 || selected_ink < 1 ||
                original.mime_type != "application/pdf") {
                throw new IOError.INVALID_ARGUMENT ("Select an existing PDF Ink");
            }
            var path = GLib.Path.build_filename (
                GLib.Environment.get_tmp_dir (),
                "stickies-ink-preview-" + GLib.Uuid.string_random () + ".pdf"
            );
            var temporary = GLib.File.new_for_path (path);
            string[] arguments = {
                "majoris-stickies-pdf-annotate", "--pdf", original.path,
                "--page", page.to_string (), "--operation", "remove",
                "--index", selected_ink.to_string (), "--output", path
            };
            try {
                var process = new GLib.Subprocess.newv (
                    arguments, GLib.SubprocessFlags.STDERR_PIPE
                );
                string? output = null;
                string? diagnostic = null;
                yield process.communicate_utf8_async (
                    null, cancellable, out output, out diagnostic
                );
                if (!process.get_successful ()) {
                    throw new IOError.FAILED (
                        diagnostic != null ? diagnostic.strip () : "PDF preview edit failed"
                    );
                }
                return temporary;
            } catch (Error error) {
                delete_temporary (temporary);
                throw error;
            }
        }

        /** Best-effort deletion of a private preview without changing attachments. */
        public static void delete_temporary (GLib.File? temporary) {
            if (temporary == null) {
                return;
            }
            try {
                temporary.delete (null);
            } catch (IOError.NOT_FOUND error) {
                return;
            } catch (Error error) {
                warning ("Temporary PDF edit cleanup failed: %s", error.message);
            }
        }

        /** Attaches a separate annotated PDF and removes the temporary output. */
        public static async void attach (
            NoteRepository repository, string note_id, NoteAttachment original,
            int page, string native_ink_svg, GLib.Cancellable? cancellable,
            string operation = "add", int selected_ink = 0
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
                if (operation != "add" && operation != "replace" &&
                    operation != "remove") {
                    throw new IOError.INVALID_ARGUMENT ("Unsupported annotation edit");
                }
                if (operation != "add" && selected_ink < 1) {
                    throw new IOError.INVALID_ARGUMENT ("Select an Ink annotation");
                }
                string[] arguments = {
                    "majoris-stickies-pdf-annotate",
                    "--pdf", original.path,
                    "--page", page.to_string (),
                    "--output", path,
                    "--operation", operation
                };
                if (operation != "add") {
                    arguments += "--index";
                    arguments += selected_ink.to_string ();
                }
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
