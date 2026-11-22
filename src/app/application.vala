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

        /** Initializes the single-instance desktop application and its window registry. */
        public StickiesApp () {
            Object (
                application_id: "com.majoris.stickies",
                flags: GLib.ApplicationFlags.FLAGS_NONE
            );
            note_windows = new Gee.HashMap<string, NoteWindow> ();
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

            var window = new NoteWindow (this, store, note);
            note_windows.set (id, window);
            window.present ();
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
