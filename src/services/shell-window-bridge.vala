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

        /** Requests true compositor opacity for a registered note window. */
        public async void set_translucent (
            Gtk.ApplicationWindow window, bool enabled
        ) throws Error {
            yield invoke (
                "SetTranslucent",
                new GLib.Variant ("(ub)", (uint) window.get_id (), enabled)
            );
        }

        /** Toggles compositor-owned all-workspace visibility for one note. */
        public async bool toggle_sticky (Gtk.ApplicationWindow window) throws Error {
            var connection = yield GLib.Bus.get (GLib.BusType.SESSION, null);
            var reply = yield connection.call (
                "org.gnome.Shell", OBJECT_PATH, INTERFACE, "ToggleSticky",
                new GLib.Variant ("(u)", (uint) window.get_id ()),
                new GLib.VariantType ("(b)"),
                GLib.DBusCallFlags.NONE, TIMEOUT_MS, null
            );
            bool enabled;
            reply.get ("(b)", out enabled);
            return enabled;
        }

        /** Reapplies saved compositor rectangles to currently registered notes. */
        public async void restore_layout () throws Error {
            yield invoke ("RestoreLayout", new GLib.Variant ("()"));
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
