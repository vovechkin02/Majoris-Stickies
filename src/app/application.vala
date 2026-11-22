using Gee;

namespace Stickies {
    /**
     * Owns the GTK application lifecycle and routes actions between note views.
     * It does not implement SQL operations or editor-widget behavior.
     */
    public class StickiesApp : Adw.Application {
        private const int MAX_DESKTOP_NOTE_WINDOWS = 64;
        private NoteRepository? repository;
        private ManagerWindow? manager_window;
        private Gee.HashMap<string, NoteWindow> note_windows;
        private bool styles_loaded = false;
        private bool windows_restored = false;
        private ShellWindowBridge shell_bridge;
        private ScreenshotPortal screenshot_portal;
        private uint reminder_poll_id = 0;

        /** Initializes the single-instance desktop application and its window registry. */
        public StickiesApp () {
            Object (
                application_id: "com.majoris.stickies",
                flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE
            );
            note_windows = new Gee.HashMap<string, NoteWindow> ();
            shell_bridge = new ShellWindowBridge ();
            screenshot_portal = new ScreenshotPortal ();
        }

        /** Registers application actions and their keyboard shortcuts. */
        protected override void startup () {
            base.startup ();

            var new_action = new GLib.SimpleAction ("new-note", null);
            new_action.activate.connect ((parameter) => create_and_open_note ());
            add_action (new_action);
            set_accels_for_action ("app.new-note", { "<Primary>n" });

            var search_action = new GLib.SimpleAction ("search-notes", null);
            search_action.activate.connect ((parameter) => {
                show_manager ();
                manager_window?.focus_search ();
            });
            add_action (search_action);
            set_accels_for_action ("app.search-notes", { "<Primary>f" });

            var capture_action = new GLib.SimpleAction ("capture-screenshot", null);
            capture_action.activate.connect ((parameter) => capture_screenshot ());
            add_action (capture_action);
            set_accels_for_action ("app.capture-screenshot", { "<Primary><Shift>s" });
        }

        /** Dispatches supported desktop actions in the existing application instance. */
        protected override int command_line (GLib.ApplicationCommandLine command) {
            var arguments = command.get_arguments ();
            if (arguments.length > 2) {
                return 2;
            }
            var option = arguments.length == 2 ? arguments[1] : "";
            if (option != "" && option != "--new-note" &&
                option != "--capture-screenshot" && option != "--show-notes") {
                return 2;
            }
            activate ();
            if (option == "--new-note") {
                create_and_open_note ();
            } else if (option == "--capture-screenshot") {
                capture_screenshot ();
            } else if (option == "--show-notes") {
                show_all_note_windows ();
            }
            return 0;
        }

        /** Loads local notes and presents the main manager on activation. */
        protected override void activate () {
            load_paper_colors ();
            if (repository == null) {
                var database_path = GLib.Path.build_filename (
                    GLib.Environment.get_user_data_dir (),
                    "majoris",
                    "stickies",
                    "notes.db"
                );
                try {
                    repository = new NoteRepository (database_path);
                } catch (Error error) {
                    show_startup_error (error.message);
                    return;
                }
            }

            show_manager ();
            if (reminder_poll_id == 0) {
                reminder_poll_id = GLib.Timeout.add_seconds (30, () => {
                    deliver_due_reminders ();
                    return GLib.Source.CONTINUE;
                });
                deliver_due_reminders ();
            }
            if (!windows_restored) {
                windows_restored = true;
                var store = repository;
                if (store != null) {
                    int restored_count = 0;
                    foreach (var note in store.list_notes ()) {
                        if (note.is_visible && note.status == 0) {
                            if (restored_count >= MAX_DESKTOP_NOTE_WINDOWS) {
                                manager_window?.show_message (
                                    "Additional notes remain in the manager; " +
                                    "at most 64 note windows can be displayed"
                                );
                                break;
                            }
                            open_note (note.id);
                            restored_count++;
                        }
                    }
                }
            }
        }

        /** Publishes due one-shot reminders while the application is running. */
        private void deliver_due_reminders () {
            var store = repository;
            if (store == null) {
                return;
            }
            int64 now_us = GLib.get_real_time ();
            foreach (var note in store.list_notes ()) {
                if (note.status != 0 || note.remind_at_us == 0 ||
                    note.reminder_notified_at_us != 0 ||
                    note.remind_at_us > now_us) {
                    continue;
                }
                try {
                    var notification = new GLib.Notification (note.title);
                    notification.set_body ("Stickies reminder");
                    send_notification (note.id, notification);
                    // A failed save may resubmit on the next poll; it must not
                    // suppress a reminder that was never submitted at all.
                    store.mark_reminder_notified (note.id, now_us);
                } catch (Error error) {
                    warning ("Unable to deliver reminder for %s: %s", note.id, error.message);
                }
            }
        }

        /** Flushes any pending saves as a final lifecycle safety net. */
        protected override void shutdown () {
            if (reminder_poll_id != 0) {
                GLib.Source.remove (reminder_poll_id);
                reminder_poll_id = 0;
            }
            var store = repository;
            if (store != null) {
                try {
                    store.flush_all ();
                } catch (Error error) {
                    critical ("Final note save failed: %s", error.message);
                }
            }

            base.shutdown ();
        }

        /** Shows the manager, recreating its view if it was previously closed. */
        public void show_manager () {
            var store = repository;
            if (store == null) {
                activate ();
                return;
            }

            if (manager_window == null) {
                manager_window = new ManagerWindow (this, store);
            }

            manager_window.present ();
        }

        /** Creates a durable note and opens its independent desktop window. */
        public void create_and_open_note () {
            var store = repository;
            if (store == null) {
                activate ();
                return;
            }

            try {
                // The Shell extension limits simultaneously registered windows,
                // not the number of notes users may create and safely store.
                var note = store.create_note ();
                var color = NoteDefaults.get_color ();
                if (color != note.color) {
                    store.set_color (note.id, color);
                    store.flush_note (note.id);
                }
                if (note_windows.size < MAX_DESKTOP_NOTE_WINDOWS) {
                    open_note (note.id);
                } else {
                    show_manager ();
                    manager_window?.show_message (
                        "Note saved. Close a desktop note to open it (64-window limit)."
                    );
                }
            } catch (Error error) {
                report_operation_error ("Unable to create note", error.message);
            }
        }

        /** Duplicates a note without changing its original contents or identity. */
        public void duplicate_and_open_note (string id) {
            var store = repository;
            if (store == null) {
                return;
            }

            duplicate_complete_async.begin (id);
        }

        /** Copies attachments asynchronously and keeps the original intact on failure. */
        private async void duplicate_complete_async (string id) {
            var store = repository;
            if (store == null) {
                return;
            }
            try {
                var duplicate = yield store.duplicate_complete (id);
                open_note (duplicate.id);
            } catch (Error error) {
                report_operation_error ("Unable to duplicate note", error.message);
            }
        }

        /** Prepares rich clipboard content without synchronously reading image files. */
        public void copy_note (string id) {
            copy_note_async.begin (id);
        }

        /** Copies bounded inline raster images and safe text/html alternatives. */
        private async void copy_note_async (string id) {
            var store = repository;
            if (store == null) {
                return;
            }
            var note = store.find_note (id);
            if (note == null) {
                report_operation_error ("Cannot copy note", "The note no longer exists");
                return;
            }
            int64 revision = note.updated_at_us;
            try {
                var attachments = store.list_attachments (id);
                var images = yield NoteTransfer.load_embeddable_images_async (attachments);
                if (store.find_note (id) != note || note.updated_at_us != revision) {
                    report_operation_error (
                        "Could not copy note", "The note changed while copying; try again"
                    );
                    return;
                }
                var plain = NoteTransfer.to_plain_text (note, attachments);
                var html = NoteTransfer.to_html (note, attachments, images);
                var plain_provider = new Gdk.ContentProvider.for_bytes (
                    "text/plain;charset=utf-8", new GLib.Bytes ((uint8[]) plain.data)
                );
                var html_provider = new Gdk.ContentProvider.for_bytes (
                    "text/html", new GLib.Bytes ((uint8[]) html.data)
                );
                var provider = new Gdk.ContentProvider.union ({
                    plain_provider, html_provider
                });
                var display = Gdk.Display.get_default ();
                if (display == null || !display.get_clipboard ().set_content (provider)) {
                    throw new IOError.FAILED ("The desktop clipboard is unavailable");
                }
                if (manager_window != null) {
                    manager_window.show_message ("Copied note text and supported inline images");
                }
            } catch (Error error) {
                report_operation_error ("Could not copy note", error.message);
            }
        }

        /** Opens the desktop's interactive screenshot selector for a new note. */
        public void capture_screenshot (string? destination_note_id = null) {
            capture_screenshot_async.begin (destination_note_id);
        }

        /** Captures with consent, then stores the resulting image as an attachment. */
        private async void capture_screenshot_async (string? destination_note_id) {
            hold ();
            var store = repository;
            if (store == null) {
                release ();
                return;
            }
            bool created = false;
            string? target_id = destination_note_id;
            try {
                var screenshot = yield screenshot_portal.capture ();
                if (target_id == null) {
                    var note = store.create_note ();
                    target_id = note.id;
                    created = true;
                    store.set_title (target_id, "Screenshot");
                }
                string note_id = target_id ?? "";
                if (note_id == "") {
                    throw new IOError.FAILED ("No destination note was selected");
                }
                yield store.attach_file (note_id, screenshot);
                if (created) {
                    open_note (note_id);
                }
                if (manager_window != null) {
                    manager_window.show_message ("Screenshot attached to note");
                }
            } catch (IOError.CANCELLED error) {
                // A canceled permission dialog must not create an empty note.
            } catch (Error error) {
                if (created && target_id != null) {
                    try {
                        store.delete_note (target_id);
                    } catch (Error cleanup_error) {
                        warning ("Screenshot cleanup failed: %s", cleanup_error.message);
                    }
                }
                report_operation_error ("Screenshot failed", error.message);
            } finally {
                release ();
            }
        }

        /** Focuses an existing note window or opens a new one for the note ID. */
        public void open_note (string id) {
            var store = repository;
            if (store == null) {
                return;
            }

            var note = store.find_note (id);
            if (note == null || note.status != 0) {
                report_operation_error ("Note unavailable", "Restore the note first.");
                return;
            }

            var existing = note_windows.get (id);
            if (existing != null) {
                existing.present ();
                return;
            }
            if (note_windows.size >= MAX_DESKTOP_NOTE_WINDOWS) {
                report_operation_error (
                    "Desktop note limit reached",
                    "Close one of the 64 open notes. The manager can still access all notes."
                );
                return;
            }

            store.set_presentation (
                id, note.is_collapsed, note.is_floating, note.is_translucent,
                note.window_width, note.window_height, true
            );
            var window = new NoteWindow (this, store, note);
            note_windows.set (id, window);
            window.present ();
            GLib.Idle.add (() => {
                register_window_async.begin (window);
                return GLib.Source.REMOVE;
            });
        }

        /** Confirms moving a note to Trash or deleting it permanently from Trash. */
        public void confirm_delete_note (string id, Gtk.Widget parent) {
            var store = repository;
            var note = store != null ? store.find_note (id) : null;
            if (note == null) {
                return;
            }
            bool permanent = note.status == 2;
            var dialog = new Adw.AlertDialog (
                permanent ? "Permanently delete this note?" : "Move this note to Trash?",
                permanent ? "This action cannot be undone." :
                    "You can restore the note from Trash."
            );
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("delete", permanent ? "Delete Permanently" : "Move to Trash");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response ("cancel");
            dialog.set_close_response ("cancel");
            dialog.response.connect ((response) => {
                if (response == "delete") {
                    if (permanent) {
                        permanently_delete_note (id);
                    } else {
                        change_note_status (id, 2);
                    }
                }
            });
            dialog.present (parent);
        }

        /** Archives, trashes, or restores one note with an immediate durable write. */
        public void change_note_status (string id, int status) {
            var store = repository;
            if (store == null) {
                return;
            }
            try {
                store.set_status (id, status);
                if (status != 0) {
                    var window = note_windows.get (id);
                    if (window != null) {
                        window.close ();
                    }
                }
            } catch (Error error) {
                report_operation_error ("Unable to change note status", error.message);
            }
        }

        /** Pins or unpins a note for prioritized ordering in the manager. */
        public void toggle_pin (string id) {
            var store = repository;
            var note = store != null ? store.find_note (id) : null;
            if (store == null || note == null) {
                return;
            }
            try {
                store.set_pinned (id, !note.is_pinned);
            } catch (Error error) {
                report_operation_error ("Unable to pin note", error.message);
            }
        }

        /** Permanently deletes a note already confirmed by the user. */
        private void permanently_delete_note (string id) {
            var store = repository;
            if (store == null) {
                return;
            }
            try {
                store.delete_note (id);
                var window = note_windows.get (id);
                if (window != null) {
                    window.close ();
                }
            } catch (Error error) {
                report_operation_error ("Unable to delete note", error.message);
            }
        }

        /** Presents all active notes without creating unnecessary duplicates. */
        public void show_all_note_windows () {
            var store = repository;
            if (store == null) {
                return;
            }
            foreach (var note in store.list_notes ()) {
                if (note.status != 0) {
                    continue;
                }
                if (note_windows.size >= MAX_DESKTOP_NOTE_WINDOWS) {
                    manager_window?.show_message (
                        "Up to 64 desktop notes can be shown together; " +
                        "remaining notes are available in the manager"
                    );
                    break;
                }
                open_note (note.id);
            }
        }

        /** Closes all note windows but leaves the notes themselves untouched. */
        public void hide_all_note_windows () {
            var windows = new Gee.ArrayList<NoteWindow> ();
            foreach (var window in note_windows.values) {
                windows.add (window);
            }
            foreach (var window in windows) {
                window.close ();
            }
        }

        /** Clears the manager reference after the closing window has flushed edits. */
        public void manager_was_closed (ManagerWindow window) {
            if (manager_window == window) {
                manager_window = null;
            }
        }

        /** Unregisters a note window after its save-on-close succeeds. */
        public void note_window_was_closed (string id, NoteWindow window) {
            if (note_windows.get (id) == window) {
                note_windows.unset (id);
            }
        }

        /** Registers a visible window with the optional compositor bridge. */
        private async void register_window_async (NoteWindow window) {
            var store = repository;
            var note = store != null ? store.find_note (window.note_id ()) : null;
            if (note == null) {
                return;
            }
            try {
                yield shell_bridge.register_window (window, note.id, note.is_floating);
                if (note.is_translucent) {
                    yield shell_bridge.set_translucent (window, true);
                }
            } catch (Error error) {
                debug ("Optional Stickies shell integration unavailable: %s", error.message);
            }
        }

        /** Applies saved opacity through the optional GNOME compositor adapter. */
        public void request_translucency (NoteWindow window, bool enabled) {
            request_translucency_async.begin (window, enabled);
        }

        /** Preserves a paper-only fallback when the Shell bridge is unavailable. */
        private async void request_translucency_async (
            NoteWindow window, bool enabled
        ) {
            try {
                yield shell_bridge.set_translucent (window, enabled);
                window.show_status (enabled ? "Window translucent" : "Window opaque");
            } catch (Error error) {
                window.show_status ("Paper transparency only (Shell integration unavailable)");
                debug ("Compositor opacity unavailable: %s", error.message);
            }
        }

        /** Requests compositor-managed visibility across GNOME workspaces. */
        public void toggle_workspace_visibility (NoteWindow window) {
            toggle_workspace_visibility_async.begin (window);
        }

        /** Uses the Shell extension as the sole owner of persisted sticky state. */
        private async void toggle_workspace_visibility_async (NoteWindow window) {
            var store = repository;
            var note = store != null ? store.find_note (window.note_id ()) : null;
            if (note == null) {
                return;
            }
            try {
                yield shell_bridge.register_window (window, note.id, note.is_floating);
                var enabled = yield shell_bridge.toggle_sticky (window);
                window.show_status (enabled ? "Shown on all workspaces" :
                    "Shown on current workspace");
            } catch (Error error) {
                window.show_save_failure (
                    "GNOME Shell workspace integration unavailable: " + error.message
                );
            }
        }

        /** Restores compositor-saved positions for visible desktop notes. */
        public void restore_note_layout () {
            restore_note_layout_async.begin ();
        }

        /** Keeps note layout restoration separate from SQLite presentation state. */
        private async void restore_note_layout_async () {
            try {
                yield shell_bridge.restore_layout ();
                manager_window?.show_message ("Restored saved desktop positions");
            } catch (Error error) {
                report_operation_error ("Unable to restore note layout", error.message);
            }
        }

        /** Requests a compositor-controlled floating change without blocking GTK. */
        public void request_floating (NoteWindow window, bool enabled) {
            set_floating_async.begin (window, enabled);
        }

        /** Calls the optional shell extension and commits state only on success. */
        private async void set_floating_async (NoteWindow window, bool enabled) {
            try {
                var store_before = repository;
                var note_before = store_before != null ?
                    store_before.find_note (window.note_id ()) : null;
                if (note_before == null) {
                    return;
                }
                yield shell_bridge.register_window (
                    window, note_before.id, note_before.is_floating
                );
                yield shell_bridge.set_floating (window, enabled);
                var store = repository;
                var note = store != null ? store.find_note (window.note_id ()) : null;
                if (store != null && note != null) {
                    store.set_presentation (
                        note.id, note.is_collapsed, enabled, note.is_translucent,
                        note.window_width, note.window_height, true
                    );
                }
            } catch (Error error) {
                window.show_save_failure (
                    "Always on Top requires the Majoris Stickies Shell extension: " +
                    error.message
                );
            }
        }

        /** Requests a window arrangement based on note colors, dates or titles. */
        public void arrange_note_windows (string mode) {
            arrange_windows_async.begin (mode);
        }

        /** Sorts open windows then delegates compositor placement to GNOME Shell. */
        private async void arrange_windows_async (string mode) {
            var store = repository;
            if (store == null || note_windows.size == 0) {
                return;
            }
            var windows = new Gee.ArrayList<NoteWindow> ();
            foreach (var window in note_windows.values) {
                windows.add (window);
            }
            windows.sort ((left, right) => {
                var left_note = store.find_note (left.note_id ());
                var right_note = store.find_note (right.note_id ());
                if (left_note == null || right_note == null) {
                    return 0;
                }
                switch (mode) {
                    case "by-color":
                        return left_note.color.collate (right_note.color);
                    case "by-date":
                        if (left_note.created_at_us == right_note.created_at_us) {
                            return left_note.id.collate (right_note.id);
                        }
                        return left_note.created_at_us < right_note.created_at_us ? -1 : 1;
                    default:
                        return left_note.title.collate (right_note.title);
                }
            });
            var ids = new GLib.StringBuilder ();
            foreach (var window in windows) {
                if (ids.len > 0) {
                    ids.append_c (',');
                }
                ids.append_printf ("%u", (uint) window.get_id ());
            }
            try {
                yield shell_bridge.arrange (mode, ids.str);
            } catch (Error error) {
                report_operation_error (
                    "Could not arrange notes",
                    "The Stickies Shell extension must be enabled: " + error.message
                );
            }
        }

        /** Loads only the note-paper CSS exception, leaving all other chrome to the theme. */
        private void load_paper_colors () {
            if (styles_loaded) {
                return;
            }

            var display = Gdk.Display.get_default ();
            if (display == null) {
                return;
            }

            var provider = new Gtk.CssProvider ();
            provider.load_from_resource ("/com/majoris/stickies/note-colors.css");
            Gtk.StyleContext.add_provider_for_display (
                display,
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
            styles_loaded = true;
        }

        /** Shows a readable startup failure instead of silently discarding user notes. */
        private void show_startup_error (string message) {
            var window = new Gtk.ApplicationWindow (this);
            window.title = "Stickies — Storage Error";
            window.set_default_size (500, 180);

            var label = new Gtk.Label ("Unable to open your notes.\n\n" + message);
            label.wrap = true;
            label.margin_top = 20;
            label.margin_bottom = 20;
            label.margin_start = 20;
            label.margin_end = 20;
            window.set_child (label);
            window.present ();
        }

        /** Displays an operation error in the notes manager if available. */
        private void report_operation_error (string heading, string details) {
            var message = heading + ": " + details;
            if (manager_window != null) {
                manager_window.show_message (message);
            } else {
                warning ("%s", message);
                var store = repository;
                if (store != null) {
                    show_manager ();
                    manager_window?.show_message (message);
                }
            }
        }
    }
}
