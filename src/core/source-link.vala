namespace Stickies {
    /**
     * Validates optional, user-provided web-source references for a note.
     * Screenshot capture alone cannot reliably infer the foreground website.
     */
    public class SourceLink : GLib.Object {
        private const int MAX_URL_BYTES = 2048;

        /** Returns a normalized HTTP(S) URL or an empty string to clear the link. */
        public static string normalize (string input) throws Error {
            var candidate = input.strip ();
            if (candidate == "") {
                return "";
            }
            if (candidate.length > MAX_URL_BYTES || !candidate.validate ()) {
                throw new IOError.INVALID_ARGUMENT ("Source URL is too long or not valid UTF-8");
            }

            var uri = GLib.Uri.parse (candidate, GLib.UriFlags.NONE);
            var raw_scheme = uri.get_scheme ();
            if (raw_scheme == null) {
                throw new IOError.INVALID_ARGUMENT ("Source URL must include http:// or https://");
            }
            var scheme = raw_scheme.down ();
            var host = uri.get_host ();
            if ((scheme != "https" && scheme != "http") ||
                host == null || host == "" || uri.get_userinfo () != null) {
                throw new IOError.INVALID_ARGUMENT (
                    "A source must be an HTTP or HTTPS URL without embedded credentials"
                );
            }
            return candidate;
        }
    }
}
