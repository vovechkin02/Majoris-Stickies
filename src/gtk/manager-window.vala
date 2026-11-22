namespace Stickies {
    /**
     * Displays and filters notes as cards without owning the underlying data.
     * The repository remains the single source of truth for all open windows.
     */
    [GtkTemplate (ui = "/com/majoris/stickies/manager-window.ui")]
    public class ManagerWindow : Adw.ApplicationWindow {
        private const uint REFRESH_DELAY_MS = 120;
        private const int PREVIEW_CHARACTER_LIMIT = 130;
        private const int CARD_PAGE_SIZE = 60;

        [GtkChild]
        private unowned Gtk.Button new_button;
        [GtkChild]
        private unowned Gtk.Button screenshot_button;
        [GtkChild]
        private unowned Gtk.DropDown color_filter;
        [GtkChild]
        private unowned Gtk.DropDown status_filter;
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
        private unowned Gtk.Button load_more_button;
        [GtkChild]
        private unowned Adw.ToastOverlay toast_overlay;

        private StickiesApp owner;
        private NoteRepository repository;
        private uint refresh_source_id = 0;
        private Gee.ArrayList<Note> visible_results;
        private int shown_card_count = 0;
        private int requested_card_count = CARD_PAGE_SIZE;
        private string? pending_updated_note_id = null;
        private bool can_refresh_one_card = false;

        /** Creates the manager and subscribes to note collection changes. */
        public ManagerWindow (StickiesApp owner, NoteRepository repository) {
            Object (application: owner);
            this.owner = owner;
            this.repository = repository;
            visible_results = new Gee.ArrayList<Note> ();

            load_more_button.clicked.connect (load_more_cards);
            new_button.clicked.connect (() => owner.create_and_open_note ());
            screenshot_button.clicked.connect (() => owner.capture_screenshot ());
            initialize_filters ();
            create_arrangement_menu ();
            search_entry.search_changed.connect (() => {
                requested_card_count = CARD_PAGE_SIZE;
                can_refresh_one_card = false;
                queue_refresh ();
            });
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
            status_filter.model = new Gtk.StringList ({
                "All Notes", "Pinned", "Archive", "Trash"
            });
            status_filter.notify["selected"].connect ((property) => reset_card_page ());
            sort_dropdown.model = new Gtk.StringList ({
                "Recently Edited", "Oldest Edited", "Title A–Z", "Color"
            });
            color_filter.notify["selected"].connect ((property) => reset_card_page ());
            sort_dropdown.notify["selected"].connect ((property) => reset_card_page ());
            list_toggle.toggled.connect (reset_card_page);
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
            menu.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            var restore_button = new Gtk.Button.with_label ("Restore Saved Layout");
            restore_button.add_css_class ("flat");
            restore_button.clicked.connect (() => {
                owner.restore_note_layout ();
                popover.popdown ();
            });
            menu.append (restore_button);
            var show_button = new Gtk.Button.with_label ("Show All Notes");
            show_button.add_css_class ("flat");
            show_button.clicked.connect (() => {
                owner.show_all_note_windows ();
                popover.popdown ();
            });
            menu.append (show_button);
            var hide_button = new Gtk.Button.with_label ("Hide All Notes");
            hide_button.add_css_class ("flat");
            hide_button.clicked.connect (() => {
                owner.hide_all_note_windows ();
                popover.popdown ();
            });
            menu.append (hide_button);
            menu.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            var login_toggle = new Gtk.CheckButton.with_label ("Start Stickies at Login");
            login_toggle.active = StartupPreferences.is_enabled ();
            login_toggle.toggled.connect (() => {
                try {
                    StartupPreferences.set_enabled (login_toggle.active);
                } catch (Error error) {
                    show_message (error.message);
                    login_toggle.active = StartupPreferences.is_enabled ();
                }
            });
            menu.append (login_toggle);
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

        /** Resets pagination when the view's selection changes. */
        private void reset_card_page () {
            requested_card_count = CARD_PAGE_SIZE;
            can_refresh_one_card = false;
            queue_refresh ();
        }

        /** Rebuilds only the currently requested cards, not the entire collection. */
        private void refresh_cards () {
            var previous_results = visible_results;
            visible_results = repository.search_notes (search_entry.text);
            int requested_status = status_filter.selected == 2 ? 1 :
                (status_filter.selected == 3 ? 2 : 0);
            for (int index = visible_results.size - 1; index >= 0; index--) {
                var note = visible_results[index];
                if (note.status != requested_status ||
                    (status_filter.selected == 1 && !note.is_pinned)) {
                    visible_results.remove_at (index);
                }
            }
            var colors = NotePalette.all_colors ();
            uint selected_color = color_filter.selected;
            if (selected_color > 0 && selected_color <= (uint) colors.length) {
                var chosen = colors[(int) selected_color - 1];
                for (int index = visible_results.size - 1; index >= 0; index--) {
                    if (visible_results[index].color != chosen) {
                        visible_results.remove_at (index);
                    }
                }
            }
            switch (sort_dropdown.selected) {
                case 1:
                    visible_results.sort ((a, b) => a.updated_at_us < b.updated_at_us ? -1 :
                        (a.updated_at_us > b.updated_at_us ? 1 : 0));
                    break;
                case 2:
                    visible_results.sort ((a, b) => a.title.collate (b.title));
                    break;
                case 3:
                    visible_results.sort ((a, b) => a.color.collate (b.color));
                    break;
                default:
                    break;
            }
            // A text-only change that does not alter filtering or order can update
            // just its card, preserving unrelated cards and their focus state.
            if (can_refresh_one_card && pending_updated_note_id != null &&
                previous_results.size == visible_results.size && shown_card_count > 0) {
                bool same_order = true;
                for (int index = 0; index < visible_results.size; index++) {
                    if (previous_results[index].id != visible_results[index].id) {
                        same_order = false;
                        break;
                    }
                }
                if (same_order) {
                    for (int index = 0; index < shown_card_count; index++) {
                        if (visible_results[index].id != pending_updated_note_id) {
                            continue;
                        }
                        var previous = notes_flow.get_child_at_index (index);
                        if (previous != null) {
                            notes_flow.remove (previous);
                            notes_flow.insert (create_note_card (visible_results[index]), index);
                        }
                        break;
                    }
                    can_refresh_one_card = false;
                    pending_updated_note_id = null;
                    return;
                }
            }
            can_refresh_one_card = false;
            pending_updated_note_id = null;
            notes_flow.remove_all ();
            shown_card_count = 0;
            notes_flow.max_children_per_line = list_toggle.active ? 1 : 3;
            append_cards (requested_card_count);
            empty_label.visible = visible_results.size == 0;
            if (visible_results.size == 0 && search_entry.text.strip () != "") {
                empty_label.label = "No notes match your search.";
            } else {
                empty_label.label = status_filter.selected == 2 ? "No archived notes." :
                    (status_filter.selected == 3 ? "Trash is empty." :
                    "No notes yet. Create your first note with the + button.");
            }
        }

        /** Adds the next bounded page without recreating earlier cards. */
        private void load_more_cards () {
            requested_card_count += CARD_PAGE_SIZE;
            append_cards (requested_card_count);
        }

        /** Creates at most the requested number of note cards. */
        private void append_cards (int requested_count) {
            int last_index = requested_count < visible_results.size ?
                requested_count : visible_results.size;
            for (int index = shown_card_count; index < last_index; index++) {
                notes_flow.insert (create_note_card (visible_results[index]), -1);
            }
            shown_card_count = last_index;
            load_more_button.visible = last_index < visible_results.size;
            count_label.label = visible_results.size == last_index ?
                "%d note%s".printf (visible_results.size, visible_results.size == 1 ? "" : "s") :
                "Showing %d of %d notes".printf (last_index, visible_results.size);
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

            if (note.remind_at_us > 0 && note.reminder_notified_at_us == 0) {
                var reminder_time = new GLib.DateTime.from_unix_local (
                    note.remind_at_us / 1000000
                );
                var reminder_label = new Gtk.Label (
                    "Reminder: " + (reminder_time.format ("%b %d, %H:%M") ?? "")
                );
                reminder_label.halign = Gtk.Align.START;
                reminder_label.add_css_class ("dim-label");
                content.append (reminder_label);
            }
            var timestamp = new GLib.DateTime.from_unix_local (note.updated_at_us / 1000000);
            var modified_label = new Gtk.Label (timestamp.format ("%b %d, %H:%M") ?? "");
            modified_label.halign = Gtk.Align.START;
            modified_label.add_css_class ("dim-label");
            content.append (modified_label);

            open_button.child = content;
            open_button.clicked.connect (() => {
                if (note.status == 0) {
                    owner.open_note (note.id);
                } else {
                    show_message (note.status == 1 ?
                        "Restore this archived note to open it." :
                        "Restore this note from Trash to open it.");
                }
            });
            card.append (open_button);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
            if (note.is_pinned && note.status == 0) {
                heading.tooltip_text = "Pinned note";
            }
            actions.halign = Gtk.Align.END;
            if (note.status == 0) {
                var pin_button = new Gtk.Button.from_icon_name ("starred-symbolic");
                pin_button.add_css_class ("flat");
                pin_button.tooltip_text = note.is_pinned ? "Unpin Note" : "Pin Note";
                pin_button.clicked.connect (() => owner.toggle_pin (note.id));
                actions.append (pin_button);
                var archive_button = new Gtk.Button.from_icon_name ("folder-symbolic");
                archive_button.add_css_class ("flat");
                archive_button.tooltip_text = "Archive Note";
                archive_button.clicked.connect (() => owner.change_note_status (note.id, 1));
                actions.append (archive_button);
            } else {
                var restore_button = new Gtk.Button.from_icon_name ("edit-undo-symbolic");
                restore_button.add_css_class ("flat");
                restore_button.tooltip_text = "Restore Note";
                restore_button.clicked.connect (() => owner.change_note_status (note.id, 0));
                actions.append (restore_button);
            }
            if (note.status != 2) {
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
            }

            var delete_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            delete_button.add_css_class ("flat");
            delete_button.tooltip_text = note.status == 2 ?
                "Delete Permanently" : "Move Note to Trash";
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
            if (refresh_source_id == 0) {
                pending_updated_note_id = note.id;
                can_refresh_one_card = true;
            } else if (pending_updated_note_id != note.id) {
                can_refresh_one_card = false;
            }
            queue_refresh ();
        }

        /** Rebuilds cards when a note is removed from persistent storage. */
        private void on_note_deleted (string id) {
            can_refresh_one_card = false;
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
