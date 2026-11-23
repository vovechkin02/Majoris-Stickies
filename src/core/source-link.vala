namespace Stickies {
    /**
     * Validates optional, user-provided web-source references for a note.
     * Clipboard provenance is accepted only during an intentional paste; browser
     * windows, histories and tabs are never inspected.
     */
    public class SourceLink : GLib.Object {
        private const int MAX_URL_BYTES = 2048;

        private const int MAX_PROVENANCE_BYTES = 64 * 1024;

        /** Decodes only supported UTF-8 or Firefox UTF-16 URL clipboard bytes. */
        public static string from_clipboard_bytes (
            string mime_type, uint8[] input, int count
        ) {
            if (count <= 0 || count > MAX_PROVENANCE_BYTES ||
                count > input.length) {
                return "";
            }
            uint8[] terminated = new uint8[count + 1];
            bool contains_nul = false;
            for (int index = 0; index < count; index++) {
                terminated[index] = input[index];
                if (input[index] == 0) {
                    contains_nul = true;
                }
            }
            terminated[count] = 0;
            if (!contains_nul) {
                return from_clipboard (mime_type, (string) terminated);
            }
            if (mime_type.down () != "text/x-moz-url") {
                return "";
            }
            if (count >= 2 && terminated[count - 1] == 0 &&
                terminated[count - 2] == 0) {
                count -= 2;
            }
            if (count < 4 || (count % 2) != 0) {
                return "";
            }
            string encoding;
            if ((terminated[0] == 0xff && terminated[1] == 0xfe) ||
                (terminated[0] == 0xfe && terminated[1] == 0xff)) {
                encoding = "UTF-16";
            } else if (terminated[1] == 0) {
                encoding = "UTF-16LE";
            } else if (terminated[0] == 0) {
                encoding = "UTF-16BE";
            } else {
                return "";
            }
            try {
                var decoded = GLib.convert (
                    (string) terminated, count, "UTF-8", encoding
                );
                return from_clipboard (mime_type, decoded);
            } catch (GLib.ConvertError error) {
                return "";
            }
        }

        /** Accepts a single explicit origin from bounded clipboard MIME data. */
        public static string from_clipboard (string mime_type, string payload) {
            if (payload.length == 0 || payload.length > MAX_PROVENANCE_BYTES ||
                !payload.validate ()) {
                return "";
            }

            var mime = mime_type.down ();
            string candidate = "";
            if (mime == "text/x-moz-url") {
                // Firefox's URL/title pair describes the copied link, not the
                // current tab. Never infer an unrelated foreground page.
                candidate = payload.split ("\n", 2)[0].strip ();
            } else if (mime == "text/uri-list") {
                foreach (var line in payload.split ("\n")) {
                    var value = line.strip ();
                    if (value == "" || value.has_prefix ("#")) {
                        continue;
                    }
                    if (candidate != "") {
                        return "";
                    }
                    candidate = value;
                }
            } else if (mime == "text/plain" ||
                mime.has_prefix ("text/plain;")) {
                candidate = payload.strip ();
            } else if (mime == "text/html" ||
                mime.has_prefix ("text/html;")) {
                try {
                    // CF_HTML and compatible providers may include an explicit
                    // SourceURL header. Ordinary <a href> links are NOT origins.
                    var header = new GLib.Regex (
                        "(?im)^SourceURL:[ \t]*(https?://[^\r\n\t<>\"' ]+)"
                    );
                    GLib.MatchInfo match;
                    if (header.match (payload, 0, out match)) {
                        candidate = match.fetch (1);
                    } else {
                        var metadata = new GLib.Regex (
                            "(?is)<meta\\s+name=[\"'](?:source-url|majoris-source-url)" +
                            "[\"']\\s+content=[\"']([^\"']+)[\"']"
                        );
                        if (metadata.match (payload, 0, out match)) {
                            candidate = match.fetch (1).replace ("&amp;", "&");
                        }
                    }
                } catch (GLib.RegexError error) {
                    return "";
                }
            }

            try {
                return normalize (candidate);
            } catch (Error error) {
                return "";
            }
        }

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
