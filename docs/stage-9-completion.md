# Stage 9.1 — Remaining-functional-gaps pass

**Source version:** 0.9.1  
**Database schema:** v5 (unchanged)  
**Status:** Source and non-native test qualification only; native release gates remain open.

## Implemented changes

1. **Portable rich media integrity.** `stickies_exchange.py` now validates all
   fixed and dynamic note style tokens, verifies that each inline-image style
   covers the object-replacement character and a genuine local image attachment,
   and maps incoming attachment UUIDs to newly owned local attachment UUIDs.
   Revision comparison substitutes attachment content SHA-256 values for
   machine-local UUIDs, avoiding false sync conflicts. Older bundles without
   these dynamic styles remain compatible.
2. **Opt-in offline deletion propagation.** The existing manual `sync` workflow
   accepts `--propagate-deletions`. It publishes bounded `<uuid>.deleted`
   tombstones only when a prior successful receipt proves what was deleted.
   If the remote copy changed, synchronization fails rather than destroying
   that edit. When a remote tombstone conflicts with locally changed content,
   the local change is preserved as a new conflict-copy note before applying
   the deletion. Tombstones are not processed without explicit authorization.
   The user must still close Stickies and pass `--app-closed`.
3. **RTF and RTFD compatibility.** RTF now creates correct font/color tables
   for supported custom text styles, uses text-only fallbacks for inline
   objects, and never invents arbitrary embedded RTF objects. RTFD keeps
   `TXT.rtf` and original asset metadata, and adds an optional bounded
   Majoris-native payload with Unicode text, style intervals, and source image
   UUIDs. The GTK import service remaps those identities after copying the
   assets and validates the resulting content before replacing the editor.
   Legacy packages without native metadata remain accepted.
4. **Editor conveniences.** The image-size control is a bounded 96–960 px
   16-pixel-step slider instead of three presets. New notes are always stored
   even when 64 desktop windows are already open. Reminder selection accepts
   `YYYY-MM-DD HH:MM` in the user's local time zone, with date and time
   validation and the existing one-year horizon.
5. **Background reminders, optional.** `majoris-stickies-reminders` checks due
   notes in existing SQLite v4/v5 data when Stickies is not running. The
   disabled-by-default systemd user timer periodically runs the worker.
   Notification failures leave the reminder due for a later attempt. No
   additional daemon or network account is installed or started by default.

## Operating instructions

After installing Stickies and `libnotify-bin`, to opt into background delivery:

```sh
systemctl --user daemon-reload
systemctl --user enable --now majoris-stickies-reminders.timer
```

To disable background delivery:

```sh
systemctl --user disable --now majoris-stickies-reminders.timer
```

To merge a local folder, including explicitly confirmed deletions:

```sh
majoris-stickies-exchange --data-dir "$HOME/.local/share/majoris/stickies" \
    sync /path/to/shared-folder --app-closed --propagate-deletions
```

**Important:** Folder deletion propagation is not automatic cloud
synchronization. Do not use the same local database concurrently from another
process. A tombstone is retained in the shared directory so another client
cannot silently recreate a deleted note. Back up notes before enabling this
feature; deleted notes may be lost on the receiving device if unmodified.

## Safety and compatibility

- Existing SQLite schema v5, note identifiers, original attachment storage,
  and all previously supported note bundles remain unchanged.
- Only validated image MIME metadata is bound to an inline image placeholder.
  Majoris Image remains the image renderer; no competing decoder was added.
- The native RTFD section is a Majoris extension. Cocoa/Apple RTFD semantics,
  embedded NSFileWrapper data, and external media placement are not guaranteed.
- User-level background notifications and the GTK app can overlap briefly if
  the app starts during a worker run; notification delivery is best effort and
  the timer does not run if the app already owns the D-Bus name.
- The Shell extension's 64-window cap is not increased; only stored note
  creation is uncapped.
- Dynamic RTF output does not contain binary attachments. Use RTFD or
  `.stickies` bundles to share attachment content.

## Tests and release gates

Non-native regression suites cover portable inline image remapping and sync,
corrupt/unowned media references, deletion conflicts, RTFD native metadata,
custom RTF styles, and the background reminder worker. Existing recovery,
resource, and shell-layout tests remain in the normal test commands.

This environment cannot run `valac`, Meson, native GTK/Wayland, or Debian binary
builds. The new Vala GUI paths (custom reminders, image slider, and native RTFD
import) need compilation and real user-session validation on Debian 13,
including the Majoris Image-enabled build. The Debian package still has a
placeholder maintainer contact, which must be configured before distribution.

### Explicitly deferred advanced parity

The project does not yet guarantee full macOS RTFD fidelity, an external image
markup/cropping editor, complete semantic nested lists, spell checking,
image-bearing rich clipboard interchange, automatic active-browser URL capture,
cloud-account sync, pen pressure/tilt, or automated GNOME Wayland release
qualification. None of these is asserted complete by this pass.
