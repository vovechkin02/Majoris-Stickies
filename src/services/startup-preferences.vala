namespace Stickies {
    /** Manages only Stickies' own optional XDG autostart entry. */
    public class StartupPreferences : GLib.Object {
        private const string HEADER = "# Created by Majoris Stickies\n";
        private const string CONTENT =
            HEADER +
            "[Desktop Entry]\n" +
            "Type=Application\n" +
            "Name=Stickies\n" +
            "Exec=majoris-stickies --show-notes\n" +
            "Terminal=false\n" +
            "X-GNOME-Autostart-enabled=true\n";

        /** Resolves Stickies' dedicated autostart desktop entry path. */
        private static string path () {
            return GLib.Path.build_filename (
                GLib.Environment.get_user_config_dir (), "autostart",
                "com.majoris.stickies.desktop"
            );
        }

        /** Reports whether the expected, application-owned entry is enabled. */
        public static bool is_enabled () {
            var destination = path ();
            if (!GLib.FileUtils.test (destination, GLib.FileTest.EXISTS) ||
                GLib.FileUtils.test (destination, GLib.FileTest.IS_SYMLINK)) {
                return false;
            }
            string contents;
            try {
                GLib.FileUtils.get_contents (destination, out contents);
                return contents == CONTENT;
            } catch (GLib.FileError error) {
                return false;
            }
        }

        /** Adds/removes only the expected entry, preserving unfamiliar user files. */
        public static void set_enabled (bool enabled) throws Error {
            var destination = path ();
            if (GLib.FileUtils.test (destination, GLib.FileTest.IS_SYMLINK)) {
                throw new IOError.PERMISSION_DENIED ("Autostart entry is a symlink");
            }
            if (GLib.FileUtils.test (destination, GLib.FileTest.EXISTS) &&
                !is_enabled ()) {
                throw new IOError.EXISTS ("Autostart entry is managed by another application");
            }
            if (enabled) {
                var directory = GLib.Path.get_dirname (destination);
                if (GLib.DirUtils.create_with_parents (directory, 0700) != 0) {
                    throw new IOError.FAILED ("Unable to create the autostart directory");
                }
                GLib.FileUtils.set_contents (destination, CONTENT);
            } else if (is_enabled ()) {
                GLib.File.new_for_path (destination).delete (null);
            }
        }
    }
}
