# Architecture and design decisions — Stages 1–4

## Scope and module responsibilities

```text
StickiesApp (actions, window registry, startup restoration)
  ├── ManagerWindow (search, cards, arrangement menu)
  ├── NoteWindow (one GTK editor per note; user actions)
  │      ├── RichTextCodec (GTK tags ↔ UTF-8 character-offset spans)
  │      └── ImageKit.ImageView (optional installed GTK4 component)
  ├── ShellWindowBridge (optional GNOME Shell D-Bus boundary)
  └── NoteRepository (single data owner; debounced commits)
         ├── Note (text, formatting, color, window prefs)
         ├── NoteFormatting (strict rich-text input contract)
         ├── NoteAttachment (managed file descriptor)
         ├── SQLite (notes and attachment records)
         └── attachments/ (managed image and PDF copies)

GNOME Shell extension (separate compositor module)
  └── Registered Stickies note windows, positions, stacking and layout
```

The Vala domain model has no GTK dependencies. The manager and editor share the
same repository and observe its native GObject signals. Attachment changes are
notified separately to avoid reconstructing image viewers on text edits.

## Storage schema and migration

The Stage 1 `notes` table, with note UUID, title, content, color and timestamps,
is upgraded **in-place** to Stage 2 inside a SQL transaction. New columns:

| Column | Type / default | Meaning |
| --- | --- | --- |
| `formatting` | TEXT `''` | `start:end:style` half-open Unicode runs |
| `collapsed` | INTEGER `0` | Note paper hidden |
| `floating` | INTEGER `0` | Shell-managed always-on-top preference |
| `translucent` | INTEGER `0` | Paper opacity preference |
| `window_width` | INTEGER `370` | Noncollapsed logical pixel width |
| `window_height` | INTEGER `330` | Noncollapsed logical pixel height |
| `visible` | INTEGER `0` | Whether to reopen editor after startup |

New table:

```sql
CREATE TABLE attachments (
    id TEXT PRIMARY KEY NOT NULL,
    note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    mime_type TEXT NOT NULL
);
CREATE INDEX attachments_note_idx ON attachments(note_id);
PRAGMA user_version=2;
```

On a new database the original Stage 1 columns are created and upgraded to v2.
Unknown newer schema versions are rejected. Existing note IDs, timestamps and
colors are unchanged. Attachment file names are UUID-derived, never blindly
loaded from SQL paths.

## Rich text and images

`RichTextCodec` translates between supported GtkTextTags and bounded serialized
spans. Style offsets are Unicode **characters**, not UTF-8 byte positions.
GTK-native formatting state is not persisted directly. The supported styles
are bold, italic, underline, strikethrough, monospace, large and small.
Note content changes and serialized formatting are committed together.

Majoris Image's installed `ImageKit.ImageView` handles decoding and display
of image attachments when built with `-Dimagekit=enabled` or `auto` and an
installed compatible package. This app deliberately does not invent image
loaders or use GTK's regular image-file decoder as a fallback. Without the
library it displays a file card with an image icon. PDFs are managed file
cards that open in the default viewer, not embedded page renderers.

## Desktop and compositor ownership

On Wayland, GTK4 clients cannot position windows or mark them always on top
using the removed X11-era window APIs. A small, optional GNOME Shell extension
owns placement, layouts, and stacking. The application calls an adapter
`ShellWindowBridge` with a private typed D-Bus interface. The compositor only
accepts windows verified as Stickies GTK note windows. User preferences for
floating are saved **only after the compositor confirms the request**.

When active, the extension writes note UUID→rect mappings into a private JSON
file in the Stickies data directory, clamps restored coordinates to monitor
work areas and supports grid, cascade and ordered layouts. The GNOME Shell
extension is a separate deployment artifact and must be qualified on the
shipping GNOME Shell release; the application must remain functional without
it. `paper_box.opacity` is a GTK child property and does not turn the outer
window translucent.

## Lifetime, I/O and errors

- Note creation and row updates are on the GTK main context, with a 500 ms
  debounce per note. A window flushes before successful close; failures keep
  edits in memory and are shown to the user.
- Attachments are asynchronously copied with `GFile.copy_async`. The file is
  checked before and after copying; its metadata row is inserted only once the
  private copy has succeeded and remained within bounds. A failed insert
  removes the new file. Deletion removes database metadata before trying to
  delete the managed file; a filesystem failure may leave an orphan but not
  an SQL pointer to a missing file.
- Plain-text file selection and read/write use async Gio APIs. The import
  is bounded, UTF-8 validated and rejects NUL bytes; it deliberately resets
  existing formatting. Export is a plain-text snapshot.
- Each editor owns one cancellable for its file actions and cancels it on
  successful close. Editor and manager subscriptions are disconnected on
  close. The application owns the registry of open windows.
- Many editor windows or huge notes may require additional profiling before
  increasing scope. Fast local SQL and in-memory Unicode search remain
  intentional for short desktop notes; no unnecessary worker system is added.

## Gang of Four design review

| Decision | Participants | Why |
| --- | --- | --- |
| Observer using GObject | `NoteRepository` signals, subscribers in editor/manager | Native event delivery; not a second custom event bus |
| Facade | `NoteRepository` CRUD and save operations | Stable domain entry point over SQLite and timer state |
| Adapter | `ShellWindowBridge` ↔ GNOME Shell D-Bus | Translates a compositor-specific interface to app operations |
| No arbitrary Factory or Strategy | Single SQLite backend and fixed editor | No independently varying concrete implementation exists |

The shell bridge's optional behavior is explicitly reported; no silent
fallback claims compositor success. No public SDK or ABI change is implied by
these private Stage 2 modules.

## Open qualification risks

- Compile and inspect Vala ownership, GtkTextBuffer tags, DBus argument types,
  XML template bindings and `ImageKit.ImageView` under the actual Debian 13
  SDK and installed Majoris Image version.
- Run normal and failed-save shutdown scenarios, including GNOME logout.
- Validate compositor positioning, window identification, multi-monitor
  work areas and GNOME extension lifecycle on the exact Majoris Shell build.
- Test filesystem failure, large attachment growth during copy, malformed
  formatting strings and Unicode selection on the target GTK runtime.

See `docs/stage-2-qualification.md` for executable commands and recorded
verification evidence.

## Stage 3: screenshots, web sources and clipboard (0.3.0)

- `ScreenshotPortal` is an asynchronous adapter to `org.freedesktop.portal.Screenshot`
  and the `org.freedesktop.portal.Request::Response` contract. The portal, not
  the application, owns the screenshot authorization UI. The adapter enforces
  one active request, a finite wait, denial semantics and D-Bus cleanup.
- `SourceLink` validates HTTP(S) URLs at the domain boundary. `NoteRepository`
  owns the SQLite v3 migration and persists one source URL per note. The
  `Note` model retains the source URL with edit timestamps.
- `NoteTransfer` exports both sanitized HTML and plain text, applying existing
  formatting intervals as nested tags without duplicating GTK widgets or
  copying private file paths into the clipboard. The application is responsible
  for the `Gdk.ContentProvider` lifetime, not the core model.
- `ManagerWindow` controls presentation-only color and order selection; the
  repository remains the authoritative in-memory source of note records.
- Command-line desktop actions use GApplication's single-instance routing.

**GoF review:** ScreenshotPortal is a boundary adapter for the portal D-Bus
contract (not a generic screenshot Strategy). GObject signals retain their
normal observer semantics. SourceLink and NoteTransfer are cohesive utilities,
not artificial Factories or Singleton services. No new pattern abstraction was
introduced without a real independent variation point.

**Compatibility:** Stage 3's additive SQLite migration does not rename earlier
columns, existing GObject properties, application IDs, schemas, or Shell D-Bus
methods. The source URL is optional and defaults to empty on older notes.

## Stage 4: reliability, accessibility and distribution (0.4.0)

- `NoteRepository.verify_integrity()` rejects corrupt SQLite storage before
  changing the schema. Dirty-state writes are retried up to three times after
  a timeout error (2/4/8 seconds); exhausted retries leave the note dirty and
  the existing close guard reports the failure. No new database migration is
  introduced. These retries do not replace a durable backup strategy.
- `ManagerWindow` uses 60-card pages rather than allocating one GTK widget tree
  per matching note. The repository retains in-memory search and sort, so this
  is **widget allocation reduction**, not claimed full search virtualization.
- GtkBuilder accessibility labels give icon-only controls, text editors,
  filters and counters clear names without a custom AT-SPI bridge. Full Orca
  and keyboard qualification must still run in the target session.
- `shell/.../layout.js` owns pure monitor geometry calculations, selected from
  persisted work-area geometry rather than monitor ID. `extension.js` owns
  Mutter signals and operations, splits arrangement by each active monitor,
  and clamps moved/offscreen notes after topology changes. The stored JSON
  format remains compatible; new records gain optional `monitorArea` metadata.
- `tools/stickies_backup.py` creates a consistent SQLite backup using the
  Python stdlib `sqlite3.Connection.backup()` API and includes referenced
  attachment content. It verifies hashes, UUID-only ZIP paths, SQLite
  integrity and foreign keys, and restores exclusively to a new private
  directory. The tool is **offline during restore** and never modifies the
  running application's database in place. This is not automatic cloud sync.
- Debian packaging splits the optional GNOME Shell extension from the GTK
  application and includes the backup executable. Package removal does not
  delete the user's `XDG_DATA_HOME` note directory. No shared library ABI or
  external protocol change is introduced.

**Design-pattern review:** GObject signals remain the observer mechanism;
`NoteRepository` retains one domain-focused persistence facade; the optional
shell bridge is an adapter across the compositor boundary. The pure
placement module is a calculation helper, not an unjustified Strategy or
state-machine framework. The Python recovery CLI is an offline maintenance
utility; it is not a second runtime repository provider.

**Qualification limits:** Toolchain compilation, package installation, Orca,
large-window runtime measurements and Mutter multi-monitor behavior must be
executed in the Debian 13 / Majoris GNOME environment. See
`docs/stage-4-qualification.md`.

## Stage 5: optional exchange, ink, reminders, and sharing (0.5.0)

- `Note` and `NoteRepository` own deadline/delivery-marker state. An additive,
  transactional SQLite v3→v4 migration introduces `remind_at_us` and
  `reminder_notified_at_us` without changing user or attachment identities.
  `StickiesApp` polls due notes at 30-second intervals only when running;
  markers are saved before `GApplication.send_notification()` is called.
  Notifications are one-shot, best-effort desktop messages, **not** a
  persistent system alarm service or off-process background agent. The
  application does not initiate network traffic to schedule reminders.
- `InkCanvas` owns bounded in-memory strokes captured by `Gtk.GestureDrag`,
  with a fixed-size Cairo preview and a numeric-path-only SVG exporter.
  The drawing editor delegates attachment persistence to
  `NoteRepository.attach_file()`. No new image decoder or SVG rendering path
  is introduced; previews remain delegated to Majoris Image when available.
- `NoteTransfer` still owns clipboard/HTML escaping. `NoteWindow` adds
  asynchronous HTML export and launches a separate, opt-in
  `majoris-stickies-exchange` process to create one-note `.stickies` bundles.
  The Python share/import/exchange command uses SQLite snapshots, checks ZIP members,
  validates SHA-256 attachments, and does not include unrelated notes.
- The opt-in Python folder sync service owns the shared-file protocol. It uses
  deterministic, content-derived note revision hashes, independent of local
  attachment UUIDs and window geometry. `sync-state.json` tracks last-agreed
  revisions. When local and remote revisions both diverge, it creates a
  separately identified conflict copy instead of discarding either edit.
  A local advisory file lock prevents concurrent processes on the same machine.
  This is a **manual, app-closed, folder-based exchange**, not an always-on
  cloud provider integration. No remote deletion propagation or encryption is
  promised.

**GoF evaluation:** `NoteRepository` remains the domain-level persistence
facade; native GObject signals are used for observations. The exchange tool
is a separate offline protocol adapter, not a replacement for the runtime
repository, and `InkCanvas` is a narrowly scoped presentation widget. Neither
requires fabricated Strategy, Factory, Singleton or Command hierarchies.

**Ownership and safety:** A note window cancels its pending file-dialog/export
operations on close. Export helpers do not receive arbitrary shell commands or
untrusted executable paths. Shared files are input data only, with bounded
sizes and validated UUIDs. The user must explicitly close the application
before any other process imports updates into the SQLite database. Developer
native build and GNOME Shell runtime qualification remain outstanding.

## Stage 6: note organization and editor commands (0.6.0)

SQLite v5 migrates existing v4 notes in a transaction, adding `status` with
0=active, 1=archived, 2=trashed, and `pinned` with 0/1 semantics. These fields
are deliberately not coupled to window visibility. Archive, Trash and Restore
preserve UUIDs, attachments, rich text, reminders, and source URLs. A distinct
confirmed permanent-delete action removes the row and its managed attachment
references. The manager shows explicit lifecycle filters.

`NoteRepository.duplicate_complete()` copies managed attachments with GIO
asynchronous file I/O; the private `.asset` suffix must not be used to infer
media type. The existing repository metadata is the source of truth. Error
handling rolls back the incomplete duplicate instead of silently returning a
text-only copy. `duplicate_note()` remains for compatibility with existing
internal callers; UI duplication uses `duplicate_complete()`.

`TextEditCommands` owns GTK buffer editing (text lists, find/replace, clearing
selected tags). `RichTextCodec` owns style tags and serialization, preserving
the domain/editor boundary and avoiding a second formatting model. Its tag
iteration now advances between tag boundaries instead of scanning all
characters for every tag. Vala and GTK build/runtime qualification remains
necessary to establish this performance improvement on the target platform.

`StartupPreferences` manages a single user-approved XDG autostart entry and
refuses to overwrite unknown or symbolic-link files. It never creates a system
service or starts network synchronization. GTK4 file drag-and-drop delegates
all file size/MIME validation to `NoteRepository.attach_file()`.

The Stage 5 single-note exchange format remains compatible for ordinary active,
unpinned notes. Stage 6 extends the same versioned manifest with optional v5
lifecycle fields only when a note is archived, trashed or pinned; old manifests
are normalized to status=active and pinned=false on import. Older applications
cannot interpret v5 lifecycle flags, which is why the exchange tool rejects
unsupported states when importing into a v4 database.

**Unimplemented parity:** RTF/RTFD, inline image layout and PDF page rendering,
compositor-wide transparency, all-workspace sticky windows, custom colors and
unrestricted fonts remain out of scope for this actual implementation. This
repository must not be represented as fully parity-complete before those
features and native qualification are delivered.

## Stage 7 — Interchange and native release boundaries

- `tools/stickies_rtf.py` is a narrowly scoped read-only RTF serializer, not
  a general interchange engine. The GTK-facing `RtfExporter` initiates it
  asynchronously **after** flushing the active note, without embedding file
  I/O and RTF escaping inside `NoteWindow`. The output uses escaped ASCII,
  Unicode UTF-16 fallback controls, balanced groups, bounded style intervals,
  and exclusive file creation. It does not decode attachments or change SQLite.
- The helper-process boundary is an ordinary integration adapter; it is **not**
  falsely classified as GoF Proxy or Strategy. The app still owns the note and
  the note repository still owns persistence. Cancellables bound the child
  wait; the helper validates its local inputs independently.
- Existing note and share identities, file paths, SQLite schema v5, and
  attachment format are unchanged. Majoris Image remains the optional image
  renderer; no alternative image decoder has been introduced.
- The Debian 13 CI job now requires native compilation, unit/integration tests,
  an Xvfb activation smoke run, and binary package construction. Failure of any
  gate must prevent tagging a build-qualified release. The GNOME Shell and
  native HDR/Wayland/ImageKit runtime paths require a target desktop session.

## Stage 8: bounded interchange, previews, and compositor operations (0.8.0)

- `RtfImporter` is an asynchronous adapter to an installed, self-limiting Python
  parser. It returns plain UTF-8 and existing `start:end:style` spans only; the
  user explicitly chooses whether to replace a note's editor body. The helper
  does not read SQLite or execute RTF fields. This is not a general RTFD reader.
- `PdfPreviewService` is an asynchronous adapter for the optional first-page
  Poppler helper. The helper checks the managed input PDF, executes `pdftoppm`
  with `subprocess.run` (no shell, 12-second timeout), and returns a bounded PNG
  in a private directory. The Vala service validates the output, then
  `ImageKit.ImageView` displays it. Poppler decodes *PDF pages*, not ordinary
  image files. The note window owns temp-file cleanup on normal close.
  If Majoris Image is unavailable, the attachment remains accessible externally.
- `RichTextCodec` is still the single formatting-span bridge; `TextEditCommands`
  owns checkbox-prefix toggles and case-sensitive/insensitive literal search.
  No new persistence tags or database schema version have been introduced.
- `StickiesApp` enforces a finite number of visible note windows (64), matching
  the existing GNOME Shell extension's registration cap. The optional extension
  implements `ToggleSticky` and `RestoreLayout`; all-workspace state is kept
  in the compositor's existing private layout JSON without an unsupported
  GTK window positioning/stacking API.
- Lifecycle and GoF review: the RTF and PDF helpers are boundary adapters, not
  new data repositories, Factory classes, or polymorphic Strategy families.
  Gtk/GObject events remain the Observer mechanism; the temporary PDF output is
  owned by the note window and removed when that window closes normally.

The source is *not* certified to compile or run in this environment. Refer to
`docs/stage-8-qualification.md` for release-gate tests and outstanding feature
parity items.


## Stage 8 completion — bounded interoperability and compositor opacity (0.8.1)

`RtfImporter` remains a narrow subprocess adapter; the Python converter reads
font/color tables rather than fabricating palette meanings from RTF indexes.
`RtfdTransfer` is a cohesive on-disk bundle adapter (not a new format framework):
it delegates RTF text conversion and managed attachment copies to the existing
`RtfImporter`/`NoteRepository` and refuses directory symlinks. The CLI helper
exports only new directories. The application keeps all note storage in
`NoteRepository` and backs out newly copied media after failed import.

`PdfPreviewService` now accepts a bounded page argument; the temporary PNG is
rendered by the Poppler helper, displayed using ImageKit, and deleted after the
viewer finishes. The editor's temporary navigation state is UI-only, not SQL.

The optional Shell extension owns compositor opacity through `SetTranslucent`
and scopes the method to registered Stickies windows. GTK paper opacity remains
a graceful fallback if the shell integration is absent. New non-native tests
exercise RTF table mappings, RTFD package safety/round-trip, installed helper
filenames, and desktop command-path contracts. The original schema v5 and
share/backup compatibility surfaces are unchanged.

No new GoF pattern is implied: the CLI adapters translate distinct interfaces,
while Gtk/GObject signals remain the idiomatic event/Observer mechanism.


## Stage 8 final image anchors and metadata boundary (v0.8.2)

`InlineImageFormat` is the stable validation layer for one-character image
references. `InlineImageController` owns GTK text anchors and ImageKit viewer
widgets. `RichTextCodec` serializes spans in Unicode character coordinates;
for an anchor the note text stores U+FFFC and one `image_<UUID>_<width>` span.
On note duplication the repository must map old attachment IDs to new IDs in
that run data. All media bytes remain in `attachments/<UUID>.asset`, never in
GTK formatting tags or a note's content field. The renderer is optional at
build time, so the editor supports placeholders without ImageKit.

RTFD validation remains in the existing `stickies_rtfd.py` helper. Its `metadata`
command returns a line-oriented percent-escaped display-name and MIME map
only after validating the package against regular files and its bounded
manifest. `RtfdTransfer` checks that every imported asset appears in this map
and delegates all durable writes to `NoteRepository.attach_file`. No arbitrary
filesystem paths or scripts are accepted as metadata values. This is a
narrow data interchange boundary, not a full Cocoa RTFD implementation.

**Pattern assessment:** GTK/GObject signals implement Observer idioms for note
updates; the repository remains the storage facade. `InlineImageController`
encapsulates widget ownership and view composition. Neither an artificial
Factory nor a Strategy interface is added where there is only one editor and
one supported image component. The existing SQL schema and exchange tokens
remain compatibility surfaces.

## Stage 9 release engineering (v0.9.0)

The GTK and domain architecture is unchanged; no database migration was added.
The release preflight checks only installed metadata relationships and the
availability of native toolchain prerequisites, **not** successful compilation.
A native build failure or unavailable compositor integration must never be
reported as a passing release gate. A separate, documented distributor contact
is required before releasing a Debian package.

`stickies_pdf_preview.py` now reclaims aged abandoned preview directories
only when owned by the process user, private (no group/other permissions),
older than 24 hours and containing exactly one regular `page.png` file.
At most 64 candidate directory names are inspected per helper invocation.
It never recurses into unfamiliar files or follows symlinked directory names.

The Xvfb/D-Bus smoke harness isolates XDG data/config/cache/state roots and
verifies persistence and single-instance command routing through the actual
binary. It does not substitute for Wayland, Orca, GNOME Shell, Majoris Image,
package-install/uninstall, or ISO qualification. GTK 4 and GNOME Shell runtime
behavior must be checked on the shipping Majoris system.


## Stage 9.1 interoperability and reminder service boundaries

- `tools/stickies_exchange.py` remains the local-folder exchange boundary.
  Note identity, inline-image identities and SHA-256 content revisions are
  handled here rather than in the GTK view. Explicit deletion tombstones are
  independent of Note status (Trash), which remains reversible and local.
- `tools/stickies_rtfd.py` validates the optional Majoris-native style payload;
  `src/services/rtfd-transfer.vala` maps source attachment UUIDs to newly
  managed IDs, then `InlineImageFormat.remap()` resolves the editor spans.
  External `TXT.rtf` stays the readable fallback.
- `tools/stickies_reminders.py` is a separate opt-in process with an existing
  SQLite contract. It is intentionally not a Singleton, Proxy, or Command
  pattern. `systemd --user` owns the worker schedule; the main application
  remains responsible for reminders while it is running.
- The existing GTK/GObject observer signals remain the appropriate notification
  idiom. No new GoF participant hierarchy was introduced solely for this pass.
- Native build, runtime ownership, and compositor behavior still require the
  release qualification described in `docs/stage-9-completion.md`.

## Stage 9.2 HTML transfer, user directories, and local sync

`NoteTransfer` continues to own deterministic Unicode-span-to-HTML encoding.
New dynamic text tokens are resolved through the established `TextStyleFormat`
validator; font names are escaped at the CSS boundary, not concatenated as
arbitrary CSS. The optional image-data map contains at most eight base64
raster images, accepted only through a bounded and validated `data:image/*`
URI, and its keys are attachment UUIDs rather than paths. `NoteTransfer`
performs asynchronous managed-file reads for both the clipboard and HTML
export, allowing `StickiesApp` to remain an orchestration layer. It validates the stored MIME and file signature; it does **not**
decode images. ImageKit remains the only application image rendering layer.

The backup, exchange, and reminder utilities derive their defaults from an
absolute XDG_DATA_HOME and retain explicit override arguments. No schema
migration, API rename, or attachment layout change was introduced.

The optional `stickies_auto_sync.py` is a narrowly scoped process adapter
around the already-existing exchange CLI. The user-level timer owns the
schedule; the worker owns its private configuration and must verify session
bus ownership before invoking exchange with `--app-closed`. Automatic deletion
propagation is intentionally excluded. This is not the GoF Command or State
pattern; all storage and conflict policy remains in the existing exchange
layer. Its setup CLI is explicit opt-in, not a startup side effect.

`NoteRepository.search_notes()` filters before sorting and delegates
comparison to the same ordering function as `list_notes()`, preserving pinned
and last-edited priority. The editor remains local-first and its single
source of truth is unchanged. Native Vala/GTK compilation and GNOME Wayland
qualification are still release gates.


## Stage 9.5 — persistent title-mode migration

The current schema is **v6**. The migration adds a bounded `auto_title INTEGER
NOT NULL DEFAULT 0 CHECK(auto_title IN (0,1))` column in an immediate SQLite
transaction. It leaves note IDs, timestamps, body, formatting, source URLs,
attachment identities and reminders untouched. Existing `Untitled Note`
placeholders receive automatic mode; other historical titles remain manual.
This is deliberately conservative because earlier schema versions did not
record whether a title matching its first line was manually edited.

The GTK editor and `NoteRepository` use `Note.auto_title` as their only source of
truth. New notes set it before the first INSERT. User-entered titles set manual
mode even when the strings are identical; explicit menu actions can re-enable
first-line derivation. The repository emits ordinary GObject change signals;
there is no second title-state observer or independent persistent setting.

Portable sharing supports v4/v5 legacy records and signatures unchanged while
carrying v6 title-mode state when required. Old applications are never allowed
to silently discard active automatic-title metadata on import.

Manager cards update individually only when the result identity ordering and
filter selection remain stable. Any structural change uses the existing
bounded full rebuild. The repository remains in-memory for search pending
measured performance evidence of an actual database bottleneck.


## Stage 9.7 — scoped markup editing without new image decoders

ImageKit remains the image viewer in both ordinary attachments and the new
markup overlay. The `Gtk.Overlay` pen canvas is a transient UI-only layer.
`ImageMarkupEditor` emits the existing `InkCanvas.to_svg()` numeric stroke
format; `ImageMarkupTransfer` asks the small installed Python helper to
validate those strokes and embed an existing, bounded raster as SVG `data:`
bytes. `NoteRepository.attach_file` owns the resulting copy and metadata.
PDF page markup uses a Poppler-rendered temporary PNG and the same interface,
then deletes that preview on cancellation or completion. Neither source files
nor existing attachments are edited. This is a visual preview annotation copy,
not a native PDF annotation serializer. The 1 MiB raster and 128 KiB pen
limits deliberately fail safely on larger sources. Format and source limits
are validated in the helper without introducing an imaging decoder.

Inline drag handles update the existing image width slider and its original
serialized rich-text style tag through `InlineImageFormat.snap_width`; there
is no additional persistent resize state. Source websites can be read from
the clipboard only on explicit user action and pass through the existing
`SourceLink` validator. These simple domain/GUI boundaries use normal
GTK/GObject callbacks rather than gratuitous new GoF participants.


## Stage 9.9 — Presentation geometry and page-scoped PDF Ink editing

`CropSelectionOverlay` owns pointer-driven selection geometry only; XML-backed
`ImageCropEditor` maintains accessible percent controls and orchestrates the
existing `ImageCropTransfer` boundary. `ImageKit.ImageView` remains the sole
application image presentation component. An explicit bounded header probe
allows the crop and ink editors to fit images without decoding them again.
The `InkCanvas` maps widget coordinates into its established portable 640×360
vector coordinate space, constrains raster ink to the fitted image rectangle,
and scales Cairo output back to widget allocation. These are presentation
coordinates, not changes to persisted attachment semantics.

`PdfInkManager` is an XML-backed selection dialog. `PdfAnnotationTransfer`
provides numeric Ink listing and non-destructive add/replace/remove operations;
`tools/stickies_pdf_annotate.py` implements PDF-specific validation, page
quarter-turn/crop-box coordinate transforms, writer operations and orphaned
Ink pruning. Redraw previews are private throwaway PDFs without the selected
old Ink. The actual edited attachment is always created from the original
managed PDF via `NoteRepository.attach_file`, preserving other page content,
other annotation types, note UUIDs, schema v7 and older share formats. The
architecture deliberately does not introduce a PDF decoder in Vala.

This is direct domain/service/UI separation, not a claim of new GoF Strategy or
Adapter objects. GObject signals already provide observer-style UI callbacks.
Native Wayland/ImageKit geometry, EXIF image orientations and actual Cairo/Gtk
lifetime tests remain qualification work in the Debian 13 environment.


## Stage 9.10 — Semantic paragraph projection and AppKit RTFD bridge

`NoteListStructure` derives typed list paragraphs from existing Unicode text,
portable prefix markers, and style spans. The same source format remains
readable to previous versions; HTML serialization emits real nested list
nodes while preserving bounded inline styling. GTK edit commands keep list
kind/depth tags consistent with paragraph changes rather than adding a second
mutable editor document tree.

The native `RtfdTransfer` orchestration delegates `.rtfd` validation and
`NeXTGraphic` parsing/formatting to the existing bounded Python helper. Only
verified sibling paths are eligible. External RTFD graphic positions are
converted to disposable UUID bindings and remapped to private attachment IDs
by the existing `NoteRepository` transfer. The RTFD exporter emits AppKit
attachment records in `TXT.rtf` without sacrificing `majoris.json` native
round trips. Neither the database schema nor note/share identities change.


## Stage 9.12 — bounded RTF paragraph geometry

`ParagraphStyleFormat` extends the existing Unicode-offset style-run contract
with canonical `para-li_N`, `para-ri_N`, `para-fi_N`, and `para-tabs_...`
identifiers. Signed `fi` and unsigned `li`/`ri` are bounded to 7200 twips;
custom tab positions are strictly increasing, with at most 12 entries and
alignment codes `L`, `C`, `R`, and `D`. These values are translated from twips
to nominal 96-dpi pixels when GTK tags are constructed. RTF import/export keeps
original twip values: rendering does not rewrite persistence data.

The authoritative model is still the Unicode note content plus formatted style
intervals. Paragraph metadata is scoped to the corresponding character range
and never stored as a second tree, JSON property blob or schema column. The
RTF importer recognizes a bounded declarative subset of `listtable` and
`listoverridetable` in order to preserve common bullet/number identities and
six-level depth in existing list tags. It does not infer unknown list kinds.

`RichTextCodec` owns presentation tags and Pango tab placement. `NoteTransfer`
owns bounded HTML attributes. Python RTF/RTFD tools own the external parser and
serializer and never access GTK or execute embedded objects. Pre-v0.9.12 notes
retain their existing formatting; applications without the new tokens may
show text without these newer paragraph attributes. The SQLite version stays
v7 and existing attachment identifiers and portable bundle manifests stay
unchanged.


## Stage 9.13 — TextEdit qualification evidence boundary

TextEdit qualification is an **offline developer workflow**, not a new runtime
persistence format or a second document model. The existing RTFD reader
continues to own bounded package validation. The fixture qualifier records
read-only semantic comparisons and attachment-content fingerprints; filename
changes do not constitute document loss. User-attested macOS evidence records
are not substitutes for native GTK/TextEdit GUI operation or visual review.
No new GoF participant or database migration is justified by this tooling.
