namespace Stickies {
    /** Persists optional new-note defaults without changing stored note records. */
    public class NoteDefaults : GLib.Object {
        /** Returns the private user preferences path for Stickies. */
        private static string path () {
            return GLib.Path.build_filename (
                GLib.Environment.get_user_config_dir (), "majoris", "stickies", "defaults.ini"
            );
        }

        /** Reads a validated paper color or falls back to the built-in preset. */
        public static string get_color () {
            var preferences = new GLib.KeyFile ();
            try {
                preferences.load_from_file (path (), GLib.KeyFileFlags.NONE);
                var color = preferences.get_string ("Defaults", "color");
                return NotePalette.is_valid (color) ? color : NotePalette.DEFAULT_COLOR;
            } catch (Error error) {
                return NotePalette.DEFAULT_COLOR;
            }
        }

        /** Saves a permitted preset in a private user configuration file. */
        public static void set_color (string color) throws Error {
            if (!NotePalette.is_valid (color)) {
                throw new IOError.INVALID_ARGUMENT ("Unsupported default note color");
            }
            var destination = path ();
            if (GLib.FileUtils.test (destination, GLib.FileTest.IS_SYMLINK)) {
                throw new IOError.PERMISSION_DENIED ("Note preferences file is a symlink");
            }
            var directory = GLib.Path.get_dirname (destination);
            if (GLib.DirUtils.create_with_parents (directory, 0700) != 0) {
                throw new IOError.FAILED ("Unable to create the preferences directory");
            }
            var preferences = new GLib.KeyFile ();
            preferences.set_string ("Defaults", "color", color);
            size_t length;
            var contents = preferences.to_data (out length);
            GLib.FileUtils.set_contents (destination, contents);
        }
    }
}
