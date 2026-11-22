namespace Stickies {
    /**
     * Transfers bounded RTFD directory packages without decoding image files.
     * RTF text is interpreted by the separate bounded RtfImporter; images and
     * PDFs remain managed attachments rather than untrusted inline objects.
     */
    public class RtfdTransfer : GLib.Object {
        private const int MAX_ATTACHMENTS = 32;
        private const int64 MAX_ASSET_BYTES = 50 * 1024 * 1024;
        private const int64 MAX_PACKAGE_BYTES = 128 * 1024 * 1024;

        /** Exports one saved note to a new directory package without overwriting. */
        public static async void export_note (
            NoteRepository repository,
            string note_id,
            GLib.File destination,
            GLib.Cancellable? cancellable
        ) throws Error {
            var path = destination.get_path ();
            if (path == null || !path.has_suffix (".rtfd")) {
                throw new IOError.INVALID_ARGUMENT ("Choose a local .rtfd directory name");
            }
            repository.flush_note (note_id);
            var data_directory = GLib.Path.build_filename (
                GLib.Environment.get_user_data_dir (), "majoris", "stickies"
            );
            string[] arguments = {
                "majoris-stickies-rtfd", "export", data_directory, note_id, path
            };
            var process = new GLib.Subprocess.newv (
                arguments, GLib.SubprocessFlags.STDERR_PIPE
            );
            yield process.wait_async (cancellable);
            if (!process.get_successful ()) {
                throw new IOError.FAILED (
                    "RTFD export rejected; the destination must not already exist"
                );
            }
        }

        /**
         * Imports a bounded RTFD directory into an existing note.
         * Performs all file validation before the first change, then rolls back
         * newly attached files if an attachment transfer fails or editing races.
         */
        public static async void import_note (
            NoteRepository repository,
            string note_id,
            GLib.File source,
            GLib.Cancellable? cancellable,
            out string text,
            out string formatting,
            out Gee.ArrayList<string> imported_ids
        ) throws Error {
            var source_path = source.get_path ();
            if (source_path == null || !source_path.has_suffix (".rtfd")) {
                throw new IOError.INVALID_ARGUMENT ("Select a local .rtfd directory");
            }
            var source_info = yield source.query_info_async (
                "standard::type", GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                GLib.Priority.DEFAULT, cancellable
            );
            if (source_info.get_file_type () != GLib.FileType.DIRECTORY) {
                throw new IOError.INVALID_ARGUMENT ("RTFD package must be a real directory");
            }
            string imported_text;
            string imported_formatting;
            yield RtfImporter.import_note (
                source.get_child ("TXT.rtf"), cancellable,
                out imported_text, out imported_formatting
            );

            var attachments = new Gee.ArrayList<GLib.File> ();
            int64 total_asset_bytes = 0;
            var files = yield source.enumerate_children_async (
                "standard::name,standard::type,standard::size",
                GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                GLib.Priority.DEFAULT, cancellable
            );
            while (true) {
                var batch = yield files.next_files_async (
                    32, GLib.Priority.DEFAULT, cancellable
                );
                if (batch == null || batch.length () == 0) {
                    break;
                }
                foreach (var info in batch) {
                    var name = info.get_name ();
                    if (name == "TXT.rtf" || name == "majoris.json") {
                        if (info.get_file_type () != GLib.FileType.REGULAR ||
                            (name == "majoris.json" && info.get_size () > 32 * 1024)) {
                            throw new IOError.INVALID_DATA ("RTFD metadata is not a regular file");
                        }
                        continue;
                    }
                    bool safe_name = name.length > 16 &&
                        name.has_prefix ("attachment-") && name[15] == '.';
                    if (safe_name) {
                        for (int index = 11; index < 15; index++) {
                            if (name[index] < '0' || name[index] > '9') {
                                safe_name = false;
                                break;
                            }
                        }
                    }
                    var suffix = safe_name ? name.substring (16) : "";
                    bool allowed_suffix = false;
                    foreach (var extension in new string[] {
                        "png", "jpg", "jpeg", "gif", "tiff", "webp", "bmp",
                        "pdf", "svg", "avif", "heif", "heic"
                    }) {
                        if (suffix == extension) {
                            allowed_suffix = true;
                            break;
                        }
                    }
                    int64 size_bytes = info.get_size ();
                    if (info.get_file_type () != GLib.FileType.REGULAR ||
                        !safe_name || !allowed_suffix ||
                        size_bytes < 0 || size_bytes > MAX_ASSET_BYTES ||
                        total_asset_bytes > MAX_PACKAGE_BYTES - size_bytes ||
                        attachments.size >= MAX_ATTACHMENTS) {
                        throw new IOError.INVALID_DATA ("RTFD contains an unsupported attachment");
                    }
                    total_asset_bytes += size_bytes;
                    attachments.add (source.get_child (name));
                }
            }
            files.close (cancellable);

            // The installed validator parses JSON, checks the exact file set,
            // and returns escaped names without exposing untrusted paths.
            string[] command = { "majoris-stickies-rtfd", "metadata", source_path };
            var validator = new GLib.Subprocess.newv (
                command, GLib.SubprocessFlags.STDOUT_PIPE |
                GLib.SubprocessFlags.STDERR_PIPE
            );
            string? metadata_output;
            string? metadata_error;
            yield validator.communicate_utf8_async (
                null, cancellable, out metadata_output, out metadata_error
            );
            if (!validator.get_successful () || metadata_output == null ||
                metadata_output.length > 32 * 1024) {
                throw new IOError.INVALID_DATA ("RTFD attachment metadata was rejected");
            }
            var original_names = new Gee.HashMap<string, string> ();
            var original_types = new Gee.HashMap<string, string> ();
            foreach (var line in metadata_output.split ("\n")) {
                if (line == "") {
                    continue;
                }
                var fields = line.split ("\t");
                if (fields.length != 3 || original_names.has_key (fields[0])) {
                    throw new IOError.INVALID_DATA ("Invalid RTFD metadata response");
                }
                var decoded = GLib.Uri.unescape_string (fields[1], null);
                if (decoded == null || decoded == "") {
                    throw new IOError.INVALID_DATA ("Invalid RTFD display name");
                }
                original_names.set (fields[0], decoded);
                original_types.set (fields[0], fields[2]);
            }
            if (original_names.size != attachments.size) {
                throw new IOError.INVALID_DATA ("RTFD metadata is incomplete");
            }
            foreach (var attachment in attachments) {
                if (!original_names.has_key (attachment.get_basename () ?? "")) {
                    throw new IOError.INVALID_DATA ("RTFD metadata file mismatch");
                }
            }
            var created = new Gee.ArrayList<string> ();
            try {
                foreach (var attachment in attachments) {
                    var file_name = attachment.get_basename () ?? "";
                    var copied = yield repository.attach_file (
                        note_id, attachment, cancellable,
                        original_names.get (file_name), original_types.get (file_name)
                    );
                    created.add (copied.id);
                }
            } catch (Error error) {
                foreach (var id in created) {
                    try {
                        repository.remove_attachment (note_id, id);
                    } catch (Error cleanup_error) {
                        warning ("RTFD rollback could not remove attachment: %s",
                            cleanup_error.message);
                    }
                }
                throw error;
            }
            text = imported_text;
            formatting = imported_formatting;
            imported_ids = created;
        }
    }
}
