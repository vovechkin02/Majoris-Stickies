namespace Stickies {
    /**
     * Exports a local note through the bounded, installed RTF interchange helper.
     *
     * The repository flush precedes the read-only helper, and external I/O runs
     * in a child process so the GTK main context is never blocked on export.
     */
    public class RtfExporter : GLib.Object {
        /** Runs one explicit RTF export and propagates failed process results. */
        public static async void export_note (
            NoteRepository repository,
            string note_id,
            GLib.File destination,
            GLib.Cancellable? cancellable = null
        ) throws Error {
            var path = destination.get_path ();
            if (path == null) {
                throw new IOError.NOT_SUPPORTED ("Choose a local RTF destination");
            }
            repository.flush_note (note_id);
            var directory = GLib.Path.build_filename (
                GLib.Environment.get_user_data_dir (), "majoris", "stickies"
            );
            string[] arguments = {
                "majoris-stickies-rtf", "--data-dir", directory, note_id, path
            };
            var process = new GLib.Subprocess.newv (
                arguments, GLib.SubprocessFlags.NONE
            );
            yield process.wait_async (cancellable);
            if (!process.get_successful ()) {
                throw new IOError.FAILED (
                    "RTF export failed; check that the note is active and the destination is new"
                );
            }
        }
    }
}
