namespace Stickies {
    /**
     * Edits a single note in its own desktop window.
     * Its widgets never write directly to SQLite; the repository handles
     * identity, autosave scheduling, and cross-window change notifications.
     */
    [GtkTemplate (ui = "/com/majoris/stickies/note-window.ui")]
    public class NoteWindow : Adw.ApplicationWindow {
        [GtkChild]
        private unowned Gtk.Button manager_button;
        [GtkChild]
        private unowned Gtk.MenuButton color_button;
        [GtkChild]
        private unowned Gtk.Button duplicate_button;
        [GtkChild]
        private unowned Gtk.Button delete_button;
        [GtkChild]
        private unowned Gtk.Box paper_box;
        [GtkChild]
        private unowned Gtk.Entry title_entry;
        [GtkChild]
        private unowned Gtk.TextView body_view;
        [GtkChild]
        private unowned Gtk.Label save_label;

        private StickiesApp owner;
        private NoteRepository repository;
        private Note note;
        private bool is_syncing_view = false;
        private string current_color = "";

        /** Creates the independent editor window for a previously stored note. */
        public NoteWindow (StickiesApp owner, NoteRepository repository, Note note) {
            Object (application: owner);
            this.owner = owner;
            this.repository = repository;
            this.note = note;
            paper_box.add_css_class ("note-paper");
            apply_color (note.color);
            populate_editor ();
            create_color_menu ();

            title_entry.changed.connect (on_title_changed);
            body_view.buffer.changed.connect (on_body_changed);
            manager_button.clicked.connect (() => owner.show_manager ());
            duplicate_button.clicked.connect (() => owner.duplicate_and_open_note (note.id));
            delete_button.clicked.connect (() => owner.confirm_delete_note (note.id, this));
            repository.note_updated.connect (on_note_updated);
            repository.note_saved.connect (on_note_saved);
            repository.save_failed.connect (on_save_failed);
            this.close_request.connect (on_close_request);
        }

        /** Returns this editor's stable note identifier. */
        public string note_id () {
            return note.id;
        }

        /** Displays an I/O error while keeping the editor open for recovery. */
        public void show_save_failure (string message) {
            save_label.label = "Not saved — " + message;
            save_label.tooltip_text = message;
        }

        /** Copies persisted contents into widgets without triggering recursive edits. */
        private void populate_editor () {
            is_syncing_view = true;
            title = note.title + " — Stickies";
            if (title_entry.text != note.title) {
                title_entry.text = note.title;
            }

            if (body_view.buffer.text != note.content) {
                body_view.buffer.text = note.content;
            }

            apply_color (note.color);
            is_syncing_view = false;
        }

        /** Updates the semantic note color class without styling window chrome. */
        private void apply_color (string color) {
            if (current_color != "") {
                paper_box.remove_css_class ("note-" + current_color);
            }

            paper_box.add_css_class ("note-" + color);
            current_color = color;
        }

        /** Creates eight accessible palette options in an attached popover. */
        private void create_color_menu () {
            var popover = new Gtk.Popover ();
            var grid = new Gtk.Grid ();
            grid.column_spacing = 6;
            grid.row_spacing = 6;
            grid.margin_top = 10;
            grid.margin_bottom = 10;
            grid.margin_start = 10;
            grid.margin_end = 10;
            int index = 0;

            foreach (var color in NotePalette.all_colors ()) {
                var selection = color;
                var button = new Gtk.Button.with_label (NotePalette.label_for (selection));
                button.add_css_class ("color-chip");
                button.add_css_class ("note-" + selection);
                button.tooltip_text = NotePalette.label_for (selection);
                button.clicked.connect (() => {
                    repository.set_color (note.id, selection);
                    popover.popdown ();
                });
                grid.attach (button, index % 2, index / 2, 1, 1);
                index++;
            }

            popover.set_child (grid);
            color_button.popover = popover;
        }

        /** Sends a heading edit through the note repository. */
        private void on_title_changed () {
            if (is_syncing_view) {
                return;
            }

            repository.set_title (note.id, title_entry.text);
        }

        /** Sends a text-buffer edit through the repository without per-keystroke I/O. */
        private void on_body_changed () {
            if (is_syncing_view) {
                return;
            }

            repository.set_content (note.id, body_view.buffer.text);
        }

        /** Reflects edits or color changes made by other interested views. */
        private void on_note_updated (Note changed_note) {
            if (changed_note.id != note.id) {
                return;
            }

            populate_editor ();
            save_label.label = "Saving…";
        }

        /** Marks the note saved only after SQLite confirms the write. */
        private void on_note_saved (Note saved_note) {
            if (saved_note.id == note.id) {
                save_label.label = "Saved";
                save_label.tooltip_text = null;
            }
        }

        /** Reports a background save failure for this editor's note. */
        private void on_save_failed (string id, string message) {
            if (id == note.id) {
                show_save_failure (message);
            }
        }

        /** Flushes edits and disconnects signals before the editor can close. */
        private bool on_close_request () {
            try {
                repository.flush_note (note.id);
            } catch (Error error) {
                show_save_failure (error.message);
                return true;
            }

            repository.note_updated.disconnect (on_note_updated);
            repository.note_saved.disconnect (on_note_saved);
            repository.save_failed.disconnect (on_save_failed);
            owner.note_window_was_closed (note.id, this);
            return false;
        }
    }
}
