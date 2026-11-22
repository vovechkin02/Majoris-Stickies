using Gee;

namespace Stickies {
    /**
     * Owns the GTK application lifecycle and routes actions between note views.
     * It does not implement SQL operations or editor-widget behavior.
     */
    public class StickiesApp : Adw.Application {
        private NoteRepository? repository;
        private ManagerWindow? manager_window;
        private Gee.HashMap<string, NoteWindow> note_windows;
        private bool styles_loaded = false;
        private bool windows_restored = false;
        private ShellWindowBridge shell_bridge;
        private ScreenshotPortal screenshot_portal;

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
            if (!windows_restored) {
                windows_restored = true;
                var store = repository;
                if (store != null) {
                    foreach (var note in store.list_notes ()) {
                        if (note.is_visible) {
                            open_note (note.id);
                        }
                    }
                }
            }
        }

        /** Flushes any pending saves as a final lifecycle safety net. */
        protected override void shutdown () {
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
                var note = store.create_note ();
                open_note (note.id);
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

            try {
                var duplicate = store.duplicate_note (id);
                open_note (duplicate.id);
            } catch (Error error) {
                report_operation_error ("Unable to duplicate note", error.message);
            }
        }

        /** Copies both plain text and safe HTML without exporting private file paths. */
        public void copy_note (string id) {
            var store = repository;
            if (store == null) {
                return;
            }
            var note = store.find_note (id);
            if (note == null) {
                report_operation_error ("Cannot copy note", "The note no longer exists");
                return;
            }
            try {
                var attachments = store.list_attachments (id);
                var plain = NoteTransfer.to_plain_text (note, attachments);
                var html = NoteTransfer.to_html (note, attachments);
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
                    manager_window.show_message ("Copied note text and formatting");
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
            if (note == null) {
                report_operation_error ("Note not found", "It may have been deleted.");
                return;
            }

            var existing = note_windows.get (id);
            if (existing != null) {
                existing.present ();
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

        /**
         * Asks before permanently deleting a note; Stage 1 has no Trash view.
         * The confirmation is intentionally modal to the originating window.
         */
        public void confirm_delete_note (string id, Gtk.Widget parent) {
            var dialog = new Adw.AlertDialog (
                "Delete this note permanently?",
                "This cannot be undone."
            );
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("delete", "Delete");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response ("cancel");
            dialog.set_close_response ("cancel");
            dialog.response.connect ((response) => {
                if (response == "delete") {
                    delete_note (id);
                }
            });
            dialog.present (parent);
        }

        /** Removes a confirmed note from storage and closes its editor. */
        private void delete_note (string id) {
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
            } catch (Error error) {
                debug ("Optional Stickies shell integration unavailable: %s", error.message);
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
