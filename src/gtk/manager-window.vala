namespace Stickies {
    /**
     * Displays and filters notes as cards without owning the underlying data.
     * The repository remains the single source of truth for all open windows.
     */
    [GtkTemplate (ui = "/com/majoris/stickies/manager-window.ui")]
    public class ManagerWindow : Adw.ApplicationWindow {
        private const uint REFRESH_DELAY_MS = 120;
        private const int PREVIEW_CHARACTER_LIMIT = 130;

        [GtkChild]
        private unowned Gtk.Button new_button;
        [GtkChild]
        private unowned Gtk.Button screenshot_button;
        [GtkChild]
        private unowned Gtk.DropDown color_filter;
        [GtkChild]
        private unowned Gtk.DropDown sort_dropdown;
        [GtkChild]
        private unowned Gtk.ToggleButton list_toggle;
        [GtkChild]
        private unowned Gtk.Label count_label;
        [GtkChild]
        private unowned Gtk.MenuButton arrange_button;
        [GtkChild]
        private unowned Gtk.SearchEntry search_entry;
        [GtkChild]
        private unowned Gtk.FlowBox notes_flow;
        [GtkChild]
        private unowned Gtk.Label empty_label;
        [GtkChild]
        private unowned Adw.ToastOverlay toast_overlay;

        private StickiesApp owner;
        private NoteRepository repository;
        private uint refresh_source_id = 0;

        /** Creates the manager and subscribes to note collection changes. */
        public ManagerWindow (StickiesApp owner, NoteRepository repository) {
            Object (application: owner);
            this.owner = owner;
            this.repository = repository;

            new_button.clicked.connect (() => owner.create_and_open_note ());
            screenshot_button.clicked.connect (() => owner.capture_screenshot ());
            initialize_filters ();
            create_arrangement_menu ();
            search_entry.search_changed.connect (queue_refresh);
            repository.note_added.connect (on_note_changed);
            repository.note_updated.connect (on_note_changed);
            repository.note_deleted.connect (on_note_deleted);
            repository.save_failed.connect (on_save_failed);
            this.close_request.connect (on_close_request);
            refresh_cards ();
        }

        /** Configures list/grid, sorting and color filters without new persistence. */
        private void initialize_filters () {
            var color_names = new Gtk.StringList (null);
            color_names.append ("All Colors");
            foreach (var color in NotePalette.all_colors ()) {
                color_names.append (NotePalette.label_for (color));
            }
            color_filter.model = color_names;
            sort_dropdown.model = new Gtk.StringList ({
                "Recently Edited", "Oldest Edited", "Title A–Z", "Color"
            });
            color_filter.notify["selected"].connect ((property) => queue_refresh ());
            sort_dropdown.notify["selected"].connect ((property) => queue_refresh ());
            list_toggle.toggled.connect (queue_refresh);
        }

        /** Exposes compositor-controlled arrangements without showing menu icons. */
        private void create_arrangement_menu () {
            var popover = new Gtk.Popover ();
            var menu = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            menu.margin_top = 8;
            menu.margin_bottom = 8;
            menu.margin_start = 8;
            menu.margin_end = 8;
            string[] names = { "Grid", "Cascade", "By Title", "By Date", "By Color" };
            string[] modes = { "grid", "cascade", "by-title", "by-date", "by-color" };
            for (int index = 0; index < names.length; index++) {
                var mode = modes[index];
                var button = new Gtk.Button.with_label (names[index]);
                button.add_css_class ("flat");
                button.clicked.connect (() => {
                    owner.arrange_note_windows (mode);
                    popover.popdown ();
                });
                menu.append (button);
            }
            popover.set_child (menu);
            arrange_button.popover = popover;
        }

        /** Moves keyboard focus to the manager's search field. */
        public void focus_search () {
            search_entry.grab_focus ();
        }

        /** Displays a non-blocking, accessible message to the user. */
        public void show_message (string message) {
            toast_overlay.add_toast (new Adw.Toast (message));
        }

        /** Schedules one card rebuild for bursts of edits. */
        private void queue_refresh () {
            if (refresh_source_id != 0) {
                return;
            }

            refresh_source_id = GLib.Timeout.add (REFRESH_DELAY_MS, () => {
                refresh_source_id = 0;
                refresh_cards ();
                return GLib.Source.REMOVE;
            });
        }

        /** Rebuilds the visible card list from a sorted repository snapshot. */
        private void refresh_cards () {
            notes_flow.remove_all ();

            var results = repository.search_notes (search_entry.text);
            var colors = NotePalette.all_colors ();
            uint selected_color = color_filter.selected;
            if (selected_color > 0 && selected_color <= (uint) colors.length) {
                var chosen = colors[(int) selected_color - 1];
                for (int index = results.size - 1; index >= 0; index--) {
                    if (results[index].color != chosen) {
                        results.remove_at (index);
                    }
                }
            }
            switch (sort_dropdown.selected) {
                case 1:
                    results.sort ((a, b) => a.updated_at_us < b.updated_at_us ? -1 :
                        (a.updated_at_us > b.updated_at_us ? 1 : 0));
                    break;
                case 2:
                    results.sort ((a, b) => a.title.collate (b.title));
                    break;
                case 3:
                    results.sort ((a, b) => a.color.collate (b.color));
                    break;
                default:
                    break;
            }
            notes_flow.max_children_per_line = list_toggle.active ? 1 : 3;
            foreach (var note in results) {
                notes_flow.insert (create_note_card (note), -1);
            }

            count_label.label = "%d note%s".printf (
                results.size, results.size == 1 ? "" : "s"
            );
            empty_label.visible = results.size == 0;
            if (results.size == 0 && search_entry.text.strip () != "") {
                empty_label.label = "No notes match your search.";
            } else {
                empty_label.label = "No notes yet. Create your first note with the + button.";
            }
        }

        /** Builds one paper-colored card with distinct open, copy, and delete actions. */
        private Gtk.Widget create_note_card (Note note) {
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            card.add_css_class ("note-card");
            card.add_css_class ("note-" + note.color);
            card.set_size_request (list_toggle.active ? 520 : 210,
                list_toggle.active ? 115 : 172);

            var open_button = new Gtk.Button ();
            open_button.add_css_class ("flat");
            open_button.hexpand = true;
            open_button.vexpand = true;
            open_button.tooltip_text = "Open " + note.title;

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var heading = new Gtk.Label (note.title);
            heading.halign = Gtk.Align.START;
            heading.xalign = 0.0f;
            heading.ellipsize = Pango.EllipsizeMode.END;
            heading.max_width_chars = 27;
            heading.add_css_class ("heading");
            content.append (heading);

            var preview = new Gtk.Label (preview_text (note.content));
            preview.halign = Gtk.Align.START;
            preview.valign = Gtk.Align.START;
            preview.xalign = 0.0f;
            preview.wrap = true;
            preview.lines = 3;
            preview.ellipsize = Pango.EllipsizeMode.END;
            preview.max_width_chars = 31;
            content.append (preview);

            if (note.source_url != "") {
                var origin = new Gtk.Label (note.source_url);
                origin.halign = Gtk.Align.START;
                origin.ellipsize = Pango.EllipsizeMode.MIDDLE;
                origin.max_width_chars = list_toggle.active ? 64 : 30;
                origin.tooltip_text = note.source_url;
                content.append (origin);
            }

            var timestamp = new GLib.DateTime.from_unix_local (note.updated_at_us / 1000000);
            var modified_label = new Gtk.Label (timestamp.format ("%b %d, %H:%M") ?? "");
            modified_label.halign = Gtk.Align.START;
            modified_label.add_css_class ("dim-label");
            content.append (modified_label);

            open_button.child = content;
            open_button.clicked.connect (() => owner.open_note (note.id));
            card.append (open_button);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
            actions.halign = Gtk.Align.END;
            var copy_button = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
            copy_button.add_css_class ("flat");
            copy_button.tooltip_text = "Copy Note to Clipboard";
            copy_button.clicked.connect (() => owner.copy_note (note.id));
            actions.append (copy_button);

            var duplicate_button = new Gtk.Button.from_icon_name ("document-duplicate-symbolic");
            duplicate_button.add_css_class ("flat");
            duplicate_button.tooltip_text = "Duplicate Note";
            duplicate_button.clicked.connect (() => owner.duplicate_and_open_note (note.id));
            actions.append (duplicate_button);

            var delete_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            delete_button.add_css_class ("flat");
            delete_button.tooltip_text = "Delete Note";
            delete_button.clicked.connect (() => owner.confirm_delete_note (note.id, this));
            actions.append (delete_button);
            card.append (actions);
            return card;
        }

        /** Produces a compact Unicode-safe plain-text preview for a card. */
        private string preview_text (string content) {
            var compact = content.replace ("\r", " ").replace ("\n", " ").strip ();
            if (compact.char_count () <= PREVIEW_CHARACTER_LIMIT) {
                return compact;
            }

            int end_byte_index = compact.index_of_nth_char (PREVIEW_CHARACTER_LIMIT);
            return compact.substring (0, end_byte_index) + "…";
        }

        /** Rebuilds cards when a new note appears or an existing note changes. */
        private void on_note_changed (Note note) {
            queue_refresh ();
        }

        /** Rebuilds cards when a note is removed from persistent storage. */
        private void on_note_deleted (string id) {
            queue_refresh ();
        }

        /** Surfaces a failed background save without discarding the user's text. */
        private void on_save_failed (string id, string message) {
            show_message ("Could not save note: " + message);
        }

        /** Flushes and disconnects subscriptions when the manager closes. */
        private bool on_close_request () {
            try {
                repository.flush_all ();
            } catch (Error error) {
                show_message ("Save failed: " + error.message);
                return true;
            }

            if (refresh_source_id != 0) {
                GLib.Source.remove (refresh_source_id);
                refresh_source_id = 0;
            }

            repository.note_added.disconnect (on_note_changed);
            repository.note_updated.disconnect (on_note_changed);
            repository.note_deleted.disconnect (on_note_deleted);
            repository.save_failed.disconnect (on_save_failed);
            owner.manager_was_closed (this);
            return false;
        }
    }
}
