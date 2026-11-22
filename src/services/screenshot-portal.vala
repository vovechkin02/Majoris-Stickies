using Gee;

namespace Stickies {
    /**
     * Requests an explicitly authorized screenshot from the desktop portal.
     * No screen pixels are accessed until the desktop grants the request.
     */
    public class ScreenshotPortal : GLib.Object {
        private const string PORTAL_NAME = "org.freedesktop.portal.Desktop";
        private const string PORTAL_PATH = "/org/freedesktop/portal/desktop";
        private const string SCREENSHOT_INTERFACE = "org.freedesktop.portal.Screenshot";
        private const string REQUEST_INTERFACE = "org.freedesktop.portal.Request";
        private const uint MAX_WAIT_SECONDS = 300;

        private bool busy = false;

        /**
         * Returns a screenshot file URI after user approval or throws an error.
         * Cancellation, portal denial and timeout are not treated as success.
         */
        public async GLib.File capture (GLib.Cancellable? cancellable = null) throws Error {
            if (busy) {
                throw new IOError.PENDING ("A screenshot request is already open");
            }
            busy = true;
            GLib.DBusConnection? connection = null;
            uint subscription_id = 0;
            uint timeout_id = 0;
            ulong cancel_id = 0;
            string? request_path = null;
            var early_responses = new Gee.HashMap<string, GLib.Variant> ();
            GLib.Variant? response = null;
            bool timed_out = false;
            bool waiting = false;
            try {
                var source = yield GLib.Bus.get (GLib.BusType.SESSION, cancellable);
                connection = source;
                GLib.SourceFunc wake = capture.callback;
                // Subscribe before calling Screenshot so an immediate response is not lost.
                subscription_id = source.signal_subscribe (
                    PORTAL_NAME, REQUEST_INTERFACE, "Response", null, null,
                    GLib.DBusSignalFlags.NONE,
                    (bus, sender, path, iface, signal, parameters) => {
                        if (request_path == null) {
                            // Store a bounded response set until Screenshot returns its handle.
                            if (early_responses.size < 16) {
                                early_responses.set (path, parameters);
                            }
                        } else if (path == request_path) {
                            response = parameters;
                            if (waiting) {
                                waiting = false;
                                GLib.Idle.add (() => {
                                    wake ();
                                    return GLib.Source.REMOVE;
                                });
                            }
                        }
                    }
                );

                var options = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
                options.add ("{sv}", "interactive", new GLib.Variant.boolean (true));
                var arguments = new GLib.Variant.tuple ({
                    new GLib.Variant.string (""), options.end ()
                });
                var reply = yield source.call (
                    PORTAL_NAME, PORTAL_PATH, SCREENSHOT_INTERFACE, "Screenshot",
                    arguments, new GLib.VariantType ("(o)"),
                    GLib.DBusCallFlags.NONE, -1, cancellable
                );
                request_path = reply.get_child_value (0).get_string ();
                response = early_responses.get (request_path);
                if (response == null) {
                    timeout_id = GLib.Timeout.add_seconds (MAX_WAIT_SECONDS, () => {
                        timeout_id = 0;
                        timed_out = true;
                        if (waiting) {
                            waiting = false;
                            wake ();
                        }
                        return GLib.Source.REMOVE;
                    });
                    if (cancellable != null) {
                        cancel_id = cancellable.cancelled.connect (() => {
                            GLib.Idle.add (() => {
                                if (waiting) {
                                    waiting = false;
                                    wake ();
                                }
                                return GLib.Source.REMOVE;
                            });
                        });
                    }
                    waiting = true;
                    yield;
                }
                if (cancellable != null && cancellable.is_cancelled ()) {
                    throw new IOError.CANCELLED ("Screenshot was canceled");
                }
                if (timed_out) {
                    throw new IOError.TIMED_OUT ("Screenshot selection timed out");
                }
                if (response == null) {
                    throw new IOError.FAILED ("The screenshot portal did not respond");
                }
                var result = response;
                uint32 status = result.get_child_value (0).get_uint32 ();
                if (status != 0) {
                    throw new IOError.CANCELLED ("Screenshot was canceled or denied");
                }
                var values = result.get_child_value (1);
                var uri_value = values.lookup_value ("uri", new GLib.VariantType ("s"));
                if (uri_value == null || uri_value.get_string () == "") {
                    throw new IOError.INVALID_DATA ("Screenshot portal returned no file URI");
                }
                var file = GLib.File.new_for_uri (uri_value.get_string ());
                if (file.get_uri_scheme () != "file") {
                    throw new IOError.INVALID_DATA ("Screenshot portal returned an unexpected URI");
                }
                return file;
            } finally {
                if (connection != null) {
                    if (subscription_id != 0) {
                        connection.signal_unsubscribe (subscription_id);
                    }
                    if (request_path != null && (timed_out ||
                        (cancellable != null && cancellable.is_cancelled ()))) {
                        var closing_connection = connection;
                        closing_connection.call.begin (
                            PORTAL_NAME, request_path, REQUEST_INTERFACE, "Close",
                            null, null, GLib.DBusCallFlags.NONE, -1, null,
                            (object, result) => {
                                try {
                                    closing_connection.call.end (result);
                                } catch (Error error) {
                                    debug ("Closing screenshot request: %s", error.message);
                                }
                            }
                        );
                    }
                }
                if (timeout_id != 0) {
                    GLib.Source.remove (timeout_id);
                }
                if (cancel_id != 0 && cancellable != null) {
                    GLib.SignalHandler.disconnect (cancellable, cancel_id);
                }
                busy = false;
            }
        }
    }
}
