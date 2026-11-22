# Stage 3 qualification — Majoris Stickies 0.3.0

## Scope

This stage adds the XDG Desktop Portal Screenshot workflow, user-verified source
web links, plain-text and HTML clipboard transfer, GNOME desktop actions, and
search/list management improvements. Earlier Stage 1 and Stage 2 functionality
must remain intact. The schema migrates from v1/v2 to v3.

## Build and automated checks

On Debian 13 / GNOME with the required development packages installed:

```sh
meson setup build -Dimagekit=disabled -Dshell_extension=false
meson compile -C build
meson test -C build --print-errorlogs
meson install -C build --destdir "$PWD/stage"
```

Repeat with `-Dimagekit=enabled` when a compatible current Majoris ImageKit
package is installed, and exercise attachment previews under the real compositor.

The Stage 3 unit suite validates web URL normalization/rejection, v2→v3
migration and persistence, search by source, source retention on duplication,
and sanitized clipboard text/HTML with overlapping rich style spans. The
integration suite statically verifies XML templates and Vala widget IDs.

## Manual GNOME/Wayland tests (not automated)

1. Launch once via `majoris-stickies`, create and edit notes, exit, then reopen;
   confirm old note identities and rich text survive.
2. Open the manager and confirm its color filter, four sort orders, result count,
   and grid/list switch track note edits and search results.
3. Invoke `Ctrl+Shift+S`, select a region with the **desktop screenshot portal**,
   approve, and confirm an image attachment appears in a newly created note.
   Verify the same flow into an existing note with its screenshot button.
4. Cancel the portal and check that no empty screenshot note is created.
   Repeat when the portal service is absent and confirm a visible error.
5. Paste a valid HTTP(S) source into the note's Source dialog, open it in the
   default browser, clear it, and try an invalid `file:` or `javascript:` URI.
6. Copy a formatted note to LibreOffice or another application accepting HTML
   clipboard content, and confirm plain-text fallback also works. Clipboard
   exports list attachment names but **do not** embed private attachment files.
7. Check `majoris-stickies --new-note` and `--capture-screenshot`, plus the
   three installed desktop-file actions, under an existing running instance.
8. Restore after a forced crash and verify existing Stage 2 window preferences.
9. Check per-note save failures and missing/locked databases without losing
   edited text; test the optional shell extension separately.

## Platform and privacy constraints

- Screenshot capture is interactive and user-permission-mediated. No silent
  screenshot or browser URL extraction is attempted.
- GTK/portal application startup is nonblocking; screenshot calls use a bounded
  wait and handle portal cancellation as non-success.
- The screenshot returned by the portal is copied to private attachment storage
  through the existing bounded attachment path; the portal URI is not persisted.
- Source URLs are explicitly user-entered and restricted to credential-free
  HTTP(S). Browser APIs can be added later under a separate, opt-in contract.
- Exporting note contents to the clipboard shares the chosen text/source URL
  with the clipboard owner; attachments are represented by filenames only.

## Build environment and known limitations

This delivery environment contains no Vala compiler, Meson, GTK4, libadwaita,
or libgee development packages. Debian package index updates fail due to DNS
resolution errors. Native compilation, Vala tests, portal integration and GUI
qualification therefore **have not been run** here. Static XML checks are
reported separately. Do not treat this source artifact as a release-qualified
binary without building and testing on Debian 13.

Known functional limits: no automatic originating-browser URL detection, no
all-in-one clipboard image binary payload, and no screenshot markup editor.
Those remain separate integrations; Stage 3 does not claim to implement them.
