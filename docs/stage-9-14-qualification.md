# Stage 9.14 — Local Browser Source Capture and Standalone Scope

## Behavior

Only a user-initiated paste in a note can trigger automatic attribution.
`ClipboardSourceCapture` requests explicit rich clipboard MIME data from GTK
without inspecting tabs, history, browser processes, shell windows or remote
services. `SourceLink.from_clipboard` accepts a single bounded origin in:

- Plain text containing only one valid HTTP(S) URL;
- `text/uri-list` with exactly one non-comment URL;
- Firefox `text/x-moz-url` first-line URL plus optional title, decoded
  from bounded UTF-16LE/BE or UTF-8 data;
- `text/html` (including UTF-8 MIME variants) carrying an explicit `SourceURL:` header or source metadata.

Ordinary HTML hyperlinks are not assumed to be document origins. The input is
bounded to 64 KiB; invalid UTF-8, user-info, non-HTTP(S), multiple URIs and
malformed values are rejected. A clipboard-change generation token prevents
attribution from stale asynchronous reads. An existing source is never
overwritten. Manual source editing and `Use Clipboard URL as Source` remain.

**Limitation:** Some browsers provide only copied text/HTML without document
origin metadata. There is no standard GTK API for querying the active page
URL of unrelated browsers. Such pastes remain unattributed unless the user
pastes a URL or provides the source manually. No always-on monitoring or
third-party browser integration is installed.

## Scope cleanup

Removed `tools/stickies_textedit_qualify.py`, the macOS-only wrapper, the
fixture/evidence matrix, associated standalone tests and obsolete guide.
Neither this project nor its packages implement Apple/Microsoft logins,
OneNote/Outlook/iCloud/Apple Notes connections, or platform service stubs.
Local RTF/RTFD import/export remains because it is a useful file-format
capability with no external account or operating system service dependency.

## Compatibility and checks

- SQLite schema v7, source URL storage, backups and sharing unchanged.
- Run `python3 -m unittest discover -s tests/integration -p 'test_*.py' -q`
  and the recovery suite.
- Run `meson setup build -Dimagekit=disabled -Dspellcheck=disabled` on Debian 13,
  followed by `meson compile -C build` and `meson test -C build`.
- GTK smoke: paste URL-only text, a single URI-list URL, Firefox URL/title,
  HTML with SourceURL, and HTML with only an unrelated `<a href>`. Confirm
  that only the first four attribute the note, that preexisting source links
  remain, and that changing the clipboard mid-paste never attributes stale
  data. Test all four native ImageKit/spellcheck combinations.
- Browser-origin metadata absence must leave the note unattributed; do not
  silently infer from the browser window or page contents.

Native GTK and browser interoperability testing require a GNOME environment.
