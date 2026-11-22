namespace Stickies {
    /**
     * Optional D-Bus adapter for GNOME Shell compositor-owned note operations.
     *
     * Every operation is asynchronous, bounded, and fails explicitly when the
     * extension is not installed or enabled. This type never reads note data.
     */
    public class ShellWindowBridge : GLib.Object {
        private const string OBJECT_PATH = "/org/gnome/Shell/Extensions/MajorisStickies";
        private const string INTERFACE = "org.gnome.Shell.Extensions.MajorisStickies";
        private const int TIMEOUT_MS = 2000;

        /** Registers a note UUID for layout restoration and floating state. */
        public async void register_window (
            Gtk.ApplicationWindow window,
            string note_id,
            bool floating
        ) throws Error {
            yield invoke (
                "RegisterWindow",
                new GLib.Variant ("(usb)", (uint) window.get_id (), note_id, floating)
            );
        }

        /** Makes a validated Stickies note float or restores normal stacking. */
        public async void set_floating (
            Gtk.ApplicationWindow window,
            bool enabled
        ) throws Error {
            yield invoke (
                "SetFloating",
                new GLib.Variant ("(ub)", (uint) window.get_id (), enabled)
            );
        }

        /** Requests a shell-managed arrangement of an ordered window-ID list. */
        public async void arrange (string mode, string window_ids) throws Error {
            yield invoke ("Arrange", new GLib.Variant ("(ss)", mode, window_ids));
        }

        /** Executes a typed method on the optional GNOME Shell D-Bus endpoint. */
        private async void invoke (string method, GLib.Variant arguments) throws Error {
            var connection = yield GLib.Bus.get (GLib.BusType.SESSION, null);
            yield connection.call (
                "org.gnome.Shell",
                OBJECT_PATH,
                INTERFACE,
                method,
                arguments,
                null,
                GLib.DBusCallFlags.NONE,
                TIMEOUT_MS,
                null
            );
        }
    }
}
