namespace Stickies {
    /**
     * Presents a note's text, formatting, attachments and window preferences.
     * The repository remains the only writer of durable note records.
     */
    [GtkTemplate (ui = "/com/majoris/stickies/note-window.ui")]
    public class NoteWindow : Adw.ApplicationWindow {
        private const int MAX_IMPORT_BYTES = 2 * 1024 * 1024;

        /** Executes a short, synchronous menu command. */
        private delegate void MenuCommand ();

        [GtkChild]
        private unowned Adw.HeaderBar note_headerbar;
        [GtkChild]
        private unowned Gtk.Button manager_button;
        [GtkChild]
        private unowned Gtk.Button screenshot_button;
        [GtkChild]
        private unowned Gtk.Button source_button;
        [GtkChild]
        private unowned Gtk.MenuButton color_button;
        [GtkChild]
        private unowned Gtk.Button duplicate_button;
        [GtkChild]
        private unowned Gtk.Button delete_button;
        [GtkChild]
        private unowned Gtk.MenuButton more_button;
        [GtkChild]
        private unowned Gtk.Box paper_box;
        [GtkChild]
        private unowned Gtk.Entry title_entry;
        [GtkChild]
        private unowned Gtk.TextView body_view;
        [GtkChild]
        private unowned Gtk.Label save_label;
        [GtkChild]
        private unowned Gtk.Box attachments_box;
        [GtkChild]
        private unowned Gtk.Button bold_button;
        [GtkChild]
        private unowned Gtk.Button italic_button;
        [GtkChild]
        private unowned Gtk.Button underline_button;
        [GtkChild]
        private unowned Gtk.Button strike_button;
        [GtkChild]
        private unowned Gtk.Button mono_button;
        [GtkChild]
        private unowned Gtk.Button large_button;
        [GtkChild]
        private unowned Gtk.Button small_button;

        private StickiesApp owner;
        private NoteRepository repository;
        private Note note;
        private GLib.Cancellable attachment_cancellable;
        private InlineImageController inline_images;
        private Gee.ArrayList<GLib.File> pdf_previews;
        private bool is_syncing_view = false;
        private uint64 editor_revision = 0;
        private string current_color = "";
        private string last_rendered_formatting = "";
        private Gtk.Button? pin_button;
        private Gtk.Button? collapse_button;
        private Gtk.Button? float_button;
        private Gtk.Button? translucent_button;
        private Gtk.Window? find_window;

        /** Constructs the independent editor without leaking storage operations into GTK. */
        public NoteWindow (StickiesApp owner, NoteRepository repository, Note note) {
            Object (application: owner);
            this.owner = owner;
            this.repository = repository;
            this.note = note;
            attachment_cancellable = new GLib.Cancellable ();
            pdf_previews = new Gee.ArrayList<GLib.File> ();
            RichTextCodec.prepare (body_view.buffer);
            inline_images = new InlineImageController (
                body_view, attachment_cancellable
            );
            inline_images.changed.connect (() => {
                editor_revision++;
                persist_editor_body ();
            });
            paper_box.add_css_class ("note-paper");
            set_default_size (note.window_width, note.is_collapsed ? 90 : note.window_height);
            apply_color (note.color);
            populate_editor ();
            create_color_menu ();
            create_options_menu ();
            connect_format_buttons ();
            register_checklist_click ();
            register_header_double_click ();
            refresh_attachments ();
            register_attachment_drop ();

            title_entry.changed.connect (on_title_changed);
            body_view.buffer.changed.connect (on_body_changed);
            manager_button.clicked.connect (() => owner.show_manager ());
            duplicate_button.clicked.connect (() => owner.duplicate_and_open_note (note.id));
            screenshot_button.clicked.connect (() => owner.capture_screenshot (note.id));
            source_button.clicked.connect (open_source_url);
            delete_button.clicked.connect (() => owner.confirm_delete_note (note.id, this));
            repository.note_updated.connect (on_note_updated);
            repository.note_saved.connect (on_note_saved);
            repository.attachment_changed.connect (on_attachment_changed);
            repository.save_failed.connect (on_save_failed);
            this.close_request.connect (on_close_request);
        }

        /** Returns this window's note identity. */
        public string note_id () {
            return note.id;
        }

        /** Shows user-visible compositor results without implying a storage change. */
        public void show_status (string message) {
            save_label.label = message;
        }

        /** Shows a save failure without dropping unsaved editor data. */
        public void show_save_failure (string message) {
            save_label.label = "Not saved — " + message;
            save_label.tooltip_text = message;
        }

        /** Renders current state without recursively issuing repository edits. */
        private void populate_editor () {
            is_syncing_view = true;
            title = note.title + " — Stickies";
            if (title_entry.text != note.title) {
                title_entry.text = note.title;
            }
            if (editor_text () != note.content ||
                last_rendered_formatting != note.formatting) {
                RichTextCodec.load (body_view.buffer, note.content, note.formatting);
                try {
                    inline_images.restore (
                        note.formatting, repository.list_attachments (note.id)
                    );
                } catch (Error error) {
                    show_save_failure ("Inline image restoration failed: " + error.message);
                }
                last_rendered_formatting = note.formatting;
            }
            apply_color (note.color);
            source_button.visible = note.source_url != "";
            source_button.tooltip_text = note.source_url != "" ? note.source_url : null;
            apply_presentation ();
            is_syncing_view = false;
        }

        /** Changes only paper styling; system chrome remains owned by the theme. */
        private void apply_color (string color) {
            if (current_color != "") {
                paper_box.remove_css_class ("note-" + current_color);
            }
            paper_box.add_css_class ("note-" + color);
            current_color = color;
        }

        /** Applies the supported in-window presentation preferences. */
        private void apply_presentation () {
            paper_box.visible = !note.is_collapsed;
            paper_box.opacity = note.is_translucent ? 0.87 : 1.0;
            if (pin_button != null) {
                pin_button.label = note.is_pinned ? "Unpin Note" : "Pin Note";
            }
            if (collapse_button != null) {
                collapse_button.label = note.is_collapsed ? "Expand Note" : "Collapse Note";
            }
            if (float_button != null) {
                float_button.label = note.is_floating ? "Disable Always on Top" : "Always on Top";
            }
            if (translucent_button != null) {
                translucent_button.label = note.is_translucent ? "Opaque Paper" : "Translucent Paper";
            }
        }

        /** Builds the palette popover from the single shared list of paper colors. */
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
            var layout = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            layout.append (grid);
            var default_button = new Gtk.Button.with_label (
                "Use This Color for New Notes"
            );
            default_button.add_css_class ("flat");
            default_button.clicked.connect (() => {
                try {
                    NoteDefaults.set_color (note.color);
                    save_label.label = "Default color updated";
                } catch (Error error) {
                    show_save_failure (error.message);
                }
                popover.popdown ();
            });
            layout.append (default_button);
            popover.set_child (layout);
            color_button.popover = popover;
        }

        /** Creates explicit note commands in the existing Majoris menu style. */
        private void create_options_menu () {
            var popover = new Gtk.Popover ();
            var menu = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            menu.margin_top = 8;
            menu.margin_bottom = 8;
            menu.margin_start = 8;
            menu.margin_end = 8;

            collapse_button = menu_item (menu, "Collapse Note", () => {
                toggle_collapsed ();
                popover.popdown ();
            });
            float_button = menu_item (menu, "Always on Top", () => {
                toggle_floating ();
                popover.popdown ();
            });
            menu_item (menu, "Toggle All Workspaces", () => {
                owner.toggle_workspace_visibility (this);
                popover.popdown ();
            });
            translucent_button = menu_item (menu, "Translucent Paper", () => {
                toggle_translucent ();
                popover.popdown ();
            });
            menu.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            menu_item (menu, "Archive Note", () => {
                popover.popdown ();
                owner.change_note_status (note.id, 1);
            });
            pin_button = menu_item (menu, note.is_pinned ? "Unpin Note" : "Pin Note", () => {
                popover.popdown ();
                owner.toggle_pin (note.id);
            });
            menu_item (menu, "Copy Note", () => {
                owner.copy_note (note.id);
                popover.popdown ();
            });
            menu_item (menu, "Set Reminder…", () => {
                popover.popdown ();
                choose_reminder ();
            });
            menu_item (menu, "Snooze Reminder — 10 Minutes", () => {
                popover.popdown ();
                snooze_reminder (10);
            });
            menu_item (menu, "Snooze Reminder — 1 Hour", () => {
                popover.popdown ();
                snooze_reminder (60);
            });
            menu_item (menu, "Edit Source URL…", () => {
                popover.popdown ();
                edit_source_url ();
            });
            menu_item (menu, "Attach Screenshot…", () => {
                popover.popdown ();
                owner.capture_screenshot (note.id);
            });
            menu.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            menu_item (menu, "Text Font and Color…", () => {
                popover.popdown ();
                choose_text_style ();
            });
            menu_item (menu, "Choose Installed Font…", () => {
                popover.popdown ();
                choose_installed_font ();
            });
            menu_item (menu, "Choose Text Color…", () => {
                popover.popdown ();
                choose_text_color ();
            });
            menu_item (menu, "Find and Replace…", () => {
                popover.popdown ();
                choose_find_replace ();
            });
            menu_item (menu, "Bulleted List", () => {
                TextEditCommands.prefix_lines (body_view.buffer, "bullet");
                persist_editor_body ();
                popover.popdown ();
            });
            menu_item (menu, "Numbered List", () => {
                TextEditCommands.prefix_lines (body_view.buffer, "numbered");
                persist_editor_body ();
                popover.popdown ();
            });
            menu_item (menu, "Checklist", () => {
                TextEditCommands.prefix_lines (body_view.buffer, "checklist");
                persist_editor_body ();
                popover.popdown ();
            });
            menu_item (menu, "Indent Paragraphs", () => {
                TextEditCommands.indent_lines (body_view.buffer, false);
                persist_editor_body ();
                popover.popdown ();
            });
            menu_item (menu, "Outdent Paragraphs", () => {
                TextEditCommands.indent_lines (body_view.buffer, true);
                persist_editor_body ();
                popover.popdown ();
            });
            menu_item (menu, "Toggle Checklist Item", () => {
                TextEditCommands.toggle_checklist_item (body_view.buffer);
                persist_editor_body ();
                popover.popdown ();
            });
            menu_item (menu, "Clear Selected Formatting", () => {
                if (TextEditCommands.clear_formatting (body_view.buffer)) {
                    persist_editor_body ();
                }
                popover.popdown ();
            });
            menu_item (menu, "Draw with Pen…", () => {
                popover.popdown ();
                open_ink_editor ();
            });
            menu_item (menu, "Export Formatted HTML…", () => {
                popover.popdown ();
                choose_html_export ();
            });
            menu_item (menu, "Import Rich Text (RTF)…", () => {
                popover.popdown ();
                choose_rtf_import ();
            });
            menu_item (menu, "Export Rich Text (RTF)…", () => {
                popover.popdown ();
                choose_rtf_export ();
            });
            menu_item (menu, "Import RTFD Package…", () => {
                popover.popdown ();
                choose_rtfd_import ();
            });
            menu_item (menu, "Export RTFD Package…", () => {
                popover.popdown ();
                choose_rtfd_export ();
            });
            menu_item (menu, "Share Note with Attachments…", () => {
                popover.popdown ();
                choose_share_bundle ();
            });
            menu_item (menu, "Insert Image at Cursor…", () => {
                popover.popdown ();
                choose_inline_image ();
            });
            menu_item (menu, "Attach Image or PDF…", () => {
                popover.popdown ();
                choose_attachment ();
            });
            menu_item (menu, "Import Plain Text…", () => {
                popover.popdown ();
                choose_import ();
            });
            menu_item (menu, "Export Plain Text…", () => {
                popover.popdown ();
                choose_export ();
            });
            popover.set_child (menu);
            more_button.popover = popover;
            apply_presentation ();
        }

        /** Presents bounded font, size, color and alignment options for selected text. */
        private void choose_text_style () {
            var dialog = new Adw.AlertDialog (
                "Format Selected Text",
                "Select a text range before applying formatting."
            );
            var builder = new Gtk.Builder.from_resource (
                "/com/majoris/stickies/text-tools.ui"
            );
            var group = (Gtk.Widget) builder.get_object ("format_preferences");
            var families = (Gtk.DropDown) builder.get_object ("format_family");
            var sizes = (Gtk.DropDown) builder.get_object ("format_size");
            var colors = (Gtk.DropDown) builder.get_object ("format_color");
            var alignments = (Gtk.DropDown) builder.get_object ("format_alignment");
            families.model = new Gtk.StringList ({ "Sans", "Serif", "Monospace" });
            sizes.model = new Gtk.StringList ({ "10", "12", "14", "16",
                "18", "20", "24" });
            colors.model = new Gtk.StringList ({ "Red", "Blue", "Green" });
            alignments.model = new Gtk.StringList ({ "Left", "Center", "Right" });
            dialog.extra_child = group;
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("family", "Apply Font");
            dialog.add_response ("size", "Apply Size");
            dialog.add_response ("color", "Apply Color");
            dialog.add_response ("alignment", "Apply Alignment");
            dialog.set_default_response ("cancel");
            dialog.response.connect ((response) => {
                string[] family_tokens = {
                    "font-sans", "font-serif", "font-monospace"
                };
                string[] size_tokens = {
                    "size-10", "size-12", "size-14", "size-16",
                    "size-18", "size-20", "size-24"
                };
                string[] color_tokens = { "text-red", "text-blue", "text-green" };
                string[] align_tokens = {
                    "align-left", "align-center", "align-right"
                };
                switch (response) {
                    case "family":
                        format_selection (family_tokens[(int) families.selected]);
                        break;
                    case "size":
                        format_selection (size_tokens[(int) sizes.selected]);
                        break;
                    case "color":
                        format_selection (color_tokens[(int) colors.selected]);
                        break;
                    case "alignment":
                        format_selection (align_tokens[(int) alignments.selected]);
                        break;
                    default:
                        break;
                }
            });
            dialog.present (this);
        }

        /** Uses the GTK font chooser to apply a real installed font to selected text. */
        private void choose_installed_font () {
            var dialog = new Gtk.FontDialog ();
            dialog.choose_font.begin (
                this, null, attachment_cancellable, (object, result) => {
                    try {
                        var selected = dialog.choose_font.end (result);
                        var family = selected.get_family ();
                        if (family == null) {
                            return;
                        }
                        var style = TextStyleFormat.font_token (family);
                        if (style != "") {
                            format_selection (style);
                        }
                        int size = selected.get_size () / Pango.SCALE;
                        var size_style = TextStyleFormat.size_token (size);
                        if (size_style != "") {
                            format_selection (size_style);
                        }
                    } catch (IOError.CANCELLED error) {
                        return;
                    } catch (Error error) {
                        show_save_failure (error.message);
                    }
                }
            );
        }

        /** Chooses a bounded foreground RGB color using the native GTK picker. */
        private void choose_text_color () {
            var dialog = new Gtk.ColorDialog ();
            dialog.choose_rgba.begin (
                this, null, attachment_cancellable, (object, result) => {
                    try {
                        var color = dialog.choose_rgba.end (result);
                        var red = (int) (color.red * 255.0 + 0.5);
                        var green = (int) (color.green * 255.0 + 0.5);
                        var blue = (int) (color.blue * 255.0 + 0.5);
                        var token = TextStyleFormat.color_token (
                            "%02x%02x%02x".printf (red, green, blue)
                        );
                        if (token != "") {
                            format_selection (token);
                        }
                    } catch (IOError.CANCELLED error) {
                        return;
                    } catch (Error error) {
                        show_save_failure (error.message);
                    }
                }
            );
        }

        /** Provides repeatable search/replace without a closing response dialog. */
        private void choose_find_replace () {
            if (find_window != null) {
                find_window.present ();
                return;
            }
            var window = new Gtk.Window ();
            find_window = window;
            window.close_request.connect (() => {
                find_window = null;
                return false;
            });
            window.title = "Find and Replace";
            window.set_transient_for (this);
            window.set_default_size (390, 220);
            window.set_resizable (false);

            var builder = new Gtk.Builder.from_resource (
                "/com/majoris/stickies/text-tools.ui"
            );
            var layout = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            layout.margin_top = 12;
            layout.margin_bottom = 12;
            layout.margin_start = 12;
            layout.margin_end = 12;
            layout.append ((Gtk.Widget) builder.get_object ("find_preferences"));
            var search = (Gtk.Entry) builder.get_object ("find_query");
            var replacement = (Gtk.Entry) builder.get_object ("find_replacement");
            var match_case = (Gtk.CheckButton) builder.get_object (
                "find_case_sensitive"
            );
            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var find = new Gtk.Button.with_label ("Find Next");
            var replace = new Gtk.Button.with_label ("Replace Next");
            var replace_all = new Gtk.Button.with_label ("Replace All");
            var close = new Gtk.Button.with_label ("Close");
            find.clicked.connect (() => {
                if (!TextEditCommands.find_next (
                    body_view.buffer, search.text, match_case.active
                )) {
                    save_label.label = "No matching text";
                }
            });
            replace.clicked.connect (() => {
                if (TextEditCommands.replace_next (
                    body_view.buffer, search.text, replacement.text, match_case.active
                )) {
                    persist_editor_body ();
                } else {
                    save_label.label = "No matching text";
                }
            });
            replace_all.clicked.connect (() => {
                var count = TextEditCommands.replace_all (
                    body_view.buffer, search.text, replacement.text, match_case.active
                );
                persist_editor_body ();
                save_label.label = "%d replacements".printf (count);
            });
            close.clicked.connect (() => window.close ());
            buttons.append (find);
            buttons.append (replace);
            buttons.append (replace_all);
            buttons.append (close);
            layout.append (buttons);
            window.set_child (layout);
            window.present ();
        }

        /** Presents bounded reminder choices in the local time zone. */
        private void choose_reminder () {
            var options = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var now = new GLib.DateTime.now_local ();
            var ten_minutes = now.add_minutes (10);
            var one_hour = now.add_hours (1);
            var tomorrow = now.add_days (1);
            var morning = new GLib.DateTime.local (
                tomorrow.get_year (), tomorrow.get_month (), tomorrow.get_day_of_month (),
                9, 0, 0.0
            );
            var dialog = new Adw.AlertDialog (
                "Note Reminder", "Notifications appear while Stickies is running."
            );
            string[] labels = {
                "In 10 Minutes", "In 1 Hour", "Tomorrow at 9:00 AM", "Clear Reminder"
            };
            int64[] deadlines = {
                ten_minutes.to_unix () * 1000000,
                one_hour.to_unix () * 1000000,
                morning.to_unix () * 1000000,
                0
            };
            for (int index = 0; index < labels.length; index++) {
                int64 deadline = deadlines[index];
                var button = new Gtk.Button.with_label (labels[index]);
                button.clicked.connect (() => {
                    try {
                        repository.set_reminder (note.id, deadline);
                        save_label.label = deadline == 0 ? "Reminder cleared" : "Reminder set";
                        dialog.close ();
                    } catch (Error error) {
                        show_save_failure (error.message);
                    }
                });
                options.append (button);
            }
            var custom_label = new Gtk.Label ("Custom date and time (local)");
            custom_label.halign = Gtk.Align.START;
            options.append (custom_label);
            var custom_time = new Gtk.Entry ();
            custom_time.text = now.add_days (1).format ("%Y-%m-%d %H:%M");
            custom_time.placeholder_text = "YYYY-MM-DD HH:MM";
            custom_time.tooltip_text = "Use your local time zone, within one year";
            options.append (custom_time);
            var custom_button = new Gtk.Button.with_label ("Set Custom Reminder");
            custom_button.clicked.connect (() => {
                try {
                    var target = parse_custom_reminder (custom_time.text);
                    repository.set_reminder (note.id, target);
                    save_label.label = "Custom reminder set";
                    dialog.close ();
                } catch (Error error) {
                    show_save_failure ("Invalid reminder: " + error.message);
                }
            });
            options.append (custom_button);
            dialog.set_extra_child (options);
            dialog.add_response ("close", "Close");
            dialog.set_close_response ("close");
            dialog.present (this);
        }

        /** Reschedules an existing reminder without changing note text or attachments. */
        private void snooze_reminder (int minutes) {
            if (note.remind_at_us <= 0) {
                show_status ("Set a reminder before snoozing it");
                return;
            }
            int64 deadline_us = GLib.get_real_time () + (int64) minutes * 60 * 1000000;
            try {
                repository.set_reminder (note.id, deadline_us);
                save_label.label = "Reminder snoozed for %d minutes".printf (minutes);
            } catch (Error error) {
                show_save_failure ("Could not snooze reminder: " + error.message);
            }
        }

        /** Parses one local wall-clock deadline without accepting partial dates or past times. */
        private int64 parse_custom_reminder (string input) throws Error {
            var value = input.strip ();
            if (!GLib.Regex.match_simple (
                "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$", value
            )) {
                throw new IOError.INVALID_ARGUMENT ("Use YYYY-MM-DD HH:MM");
            }
            int year;
            int month;
            int day;
            int hour;
            int minute;
            if (!int.try_parse (value.substring (0, 4), out year) ||
                !int.try_parse (value.substring (5, 2), out month) ||
                !int.try_parse (value.substring (8, 2), out day) ||
                !int.try_parse (value.substring (11, 2), out hour) ||
                !int.try_parse (value.substring (14, 2), out minute) ||
                year < 2000 || year > 2100 || month < 1 || month > 12 ||
                day < 1 || day > 31 || hour > 23 || minute > 59) {
                throw new IOError.INVALID_ARGUMENT ("The date or time is invalid");
            }
            GLib.DateTime? requested = new GLib.DateTime.local (
                year, month, day, hour, minute, 0.0
            );
            if (requested == null || requested.get_year () != year ||
                requested.get_month () != month ||
                requested.get_day_of_month () != day ||
                requested.get_hour () != hour || requested.get_minute () != minute) {
                throw new IOError.INVALID_ARGUMENT ("The local date does not exist");
            }
            int64 deadline_us = requested.to_unix () * 1000000;
            if (deadline_us <= GLib.get_real_time ()) {
                throw new IOError.INVALID_ARGUMENT ("Choose a future time");
            }
            return deadline_us;
        }

        /** Edits an explicit web origin; screenshots never fabricate a source URL. */
        private void edit_source_url () {
            var editor = new Gtk.Entry ();
            editor.text = note.source_url;
            editor.placeholder_text = "https://example.com/page";
            editor.hexpand = true;
            editor.input_purpose = Gtk.InputPurpose.URL;
            var dialog = new Adw.AlertDialog (
                "Source Website", "Add an HTTP(S) link to the original page. " +
                "Stickies does not automatically inspect other browser windows."
            );
            dialog.set_extra_child (editor);
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", "Save Source");
            dialog.set_default_response ("save");
            dialog.set_close_response ("cancel");
            dialog.response.connect ((response) => {
                if (response == "save") {
                    try {
                        repository.set_source_url (note.id, editor.text);
                    } catch (Error error) {
                        show_save_failure (error.message);
                    }
                }
            });
            dialog.present (this);
        }

        /** Opens only a previously validated HTTP(S) source in the default browser. */
        private void open_source_url () {
            if (note.source_url == "") {
                return;
            }
            try {
                GLib.AppInfo.launch_default_for_uri (note.source_url, null);
            } catch (Error error) {
                show_save_failure ("Unable to open source: " + error.message);
            }
        }

        /** Adds a text-only item, leaving menu item styling to the global theme. */
        private Gtk.Button menu_item (Gtk.Box menu, string label, owned MenuCommand action) {
            var button = new Gtk.Button.with_label (label);
            button.halign = Gtk.Align.FILL;
            button.add_css_class ("flat");
            button.clicked.connect (() => {
                action ();
            });
            menu.append (button);
            return button;
        }

        /** Wires formatting controls through a single tag-selection operation. */
        private void connect_format_buttons () {
            bold_button.clicked.connect (() => format_selection ("bold"));
            italic_button.clicked.connect (() => format_selection ("italic"));
            underline_button.clicked.connect (() => format_selection ("underline"));
            strike_button.clicked.connect (() => format_selection ("strikethrough"));
            mono_button.clicked.connect (() => format_selection ("monospace"));
            large_button.clicked.connect (() => format_selection ("large"));
            small_button.clicked.connect (() => format_selection ("small"));

            var key_controller = new Gtk.EventControllerKey ();
            key_controller.key_pressed.connect ((keyval, keycode, modifiers) => {
                if ((modifiers & Gdk.ModifierType.CONTROL_MASK) == 0) {
                    if ((keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) &&
                        TextEditCommands.continue_list (body_view.buffer)) {
                        persist_editor_body ();
                        return true;
                    }
                    return false;
                }
                if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                    TextEditCommands.toggle_checklist_item (body_view.buffer);
                    persist_editor_body ();
                    return true;
                }
                if (keyval == Gdk.Key.b) {
                    format_selection ("bold");
                    return true;
                }
                if (keyval == Gdk.Key.i) {
                    format_selection ("italic");
                    return true;
                }
                if (keyval == Gdk.Key.u) {
                    format_selection ("underline");
                    return true;
                }
                return false;
            });
            body_view.add_controller (key_controller);
        }

        /** Changes supported formatting on selected text only. */
        private void format_selection (string style) {
            if (!RichTextCodec.toggle_selected (body_view.buffer, style)) {
                save_label.label = "Select text to format";
                return;
            }
            persist_editor_body ();
        }

        /** Reads child-anchor object characters without losing media positions. */
        private string editor_text () {
            Gtk.TextIter start;
            Gtk.TextIter end;
            body_view.buffer.get_bounds (out start, out end);
            return body_view.buffer.get_slice (start, end, true);
        }

        /** Sends both rich-text runs and text through one repository update. */
        private void persist_editor_body () {
            var text = editor_text ();
            var formatting = RichTextCodec.serialize (body_view.buffer);
            if (!NoteFormatting.is_valid (text, formatting)) {
                show_save_failure ("Formatting exceeds the supported note limits");
                return;
            }
            last_rendered_formatting = formatting;
            repository.set_body (note.id, text, formatting);
        }

        /** Sends title changes without issuing SQL writes per key press. */
        private void on_title_changed () {
            if (!is_syncing_view) {
                editor_revision++;
                repository.set_title (note.id, title_entry.text);
            }
        }

        /** Collapses the note by double-clicking empty headerbar space. */
        private void register_header_double_click () {
            var gesture = new Gtk.GestureClick ();
            gesture.set_button (1);
            gesture.pressed.connect ((click_count, x, y) => {
                if (click_count == 2) {
                    toggle_collapsed ();
                }
            });
            note_headerbar.add_controller (gesture);
        }

        /** Opens a web URL only on an explicit Ctrl+click, never on typing. */
        private void open_clicked_link (Gtk.TextIter at_position) {
            var start = at_position;
            var end = at_position;
            int scanned = 0;
            while (!start.starts_line () && scanned < 2048) {
                var previous = start;
                if (!previous.backward_char ()) {
                    break;
                }
                var symbol = body_view.buffer.get_text (previous, start, false);
                if (symbol == " " || symbol == "\t" || symbol == "\n" ||
                    symbol == "<" || symbol == ">" || symbol == "\"") {
                    break;
                }
                start = previous;
                scanned++;
            }
            while (!end.ends_line () && scanned < 2048) {
                var next = end;
                if (!next.forward_char ()) {
                    break;
                }
                var symbol = body_view.buffer.get_text (end, next, false);
                if (symbol == " " || symbol == "\t" || symbol == "\n" ||
                    symbol == "<" || symbol == ">" || symbol == "\"") {
                    break;
                }
                end = next;
                scanned++;
            }
            var candidate = body_view.buffer.get_text (start, end, false);
            while (candidate.has_suffix (".") || candidate.has_suffix (",") ||
                candidate.has_suffix (";") || candidate.has_suffix (")")) {
                candidate = candidate.substring (0, candidate.length - 1);
            }
            if (!candidate.has_prefix ("http://") &&
                !candidate.has_prefix ("https://")) {
                return;
            }
            try {
                var uri = SourceLink.normalize (candidate);
                GLib.AppInfo.launch_default_for_uri (uri, null);
            } catch (Error error) {
                show_status ("Cannot open link: " + error.message);
            }
        }

        /** Allows a pointer click directly on a checklist glyph to toggle its state. */
        private void register_checklist_click () {
            var gesture = new Gtk.GestureClick ();
            gesture.set_button (1);
            gesture.released.connect ((press_count, x, y) => {
                if (press_count != 1 || is_syncing_view) {
                    return;
                }
                int buffer_x;
                int buffer_y;
                body_view.window_to_buffer_coords (
                    Gtk.TextWindowType.WIDGET, (int) x, (int) y,
                    out buffer_x, out buffer_y
                );
                Gtk.TextIter position;
                if (!body_view.get_iter_at_location (
                    out position, buffer_x, buffer_y
                )) {
                    return;
                }
                if ((gesture.get_current_event_state () &
                    Gdk.ModifierType.CONTROL_MASK) != 0) {
                    open_clicked_link (position);
                    return;
                }
                if (position.get_line_offset () > 1) {
                    return;
                }
                var start = position;
                start.set_line_offset (0);
                var end = start;
                if (!end.forward_char ()) {
                    return;
                }
                var glyph = body_view.buffer.get_text (start, end, false);
                if (glyph != "☐" && glyph != "☑") {
                    return;
                }
                body_view.buffer.place_cursor (start);
                TextEditCommands.toggle_checklist_item (body_view.buffer);
                persist_editor_body ();
            });
            body_view.add_controller (gesture);
        }

        /** Sends text changes with style positions preserved by GtkTextBuffer. */
        private void on_body_changed () {
            if (!is_syncing_view) {
                editor_revision++;
                persist_editor_body ();
            }
        }

        /** Refreshes presentation and file cards when this note changes. */
        private void on_note_updated (Note changed_note) {
            if (changed_note.id != note.id) {
                return;
            }
            populate_editor ();
            save_label.label = "Saving…";
        }

        /** Refreshes only this note's file cards after attachment operations. */
        private void on_attachment_changed (string id) {
            if (id == note.id) {
                refresh_attachments ();
            }
        }

        /** Marks a durable save and clears any prior error tooltip. */
        private void on_note_saved (Note saved_note) {
            if (saved_note.id == note.id) {
                save_label.label = "Saved";
                save_label.tooltip_text = null;
            }
        }

        /** Reports an asynchronous database failure for this editor. */
        private void on_save_failed (string id, string message) {
            if (id == note.id) {
                show_save_failure (message);
            }
        }

        /** Collapses the editable paper while keeping prior dimensions for restoration. */
        private void toggle_collapsed () {
            var collapsed = !note.is_collapsed;
            int width = note.window_width;
            int height = note.window_height;
            if (!note.is_collapsed) {
                width = (get_width () > 240 ? get_width () : 240);
                height = (get_height () > 120 ? get_height () : 120);
            }
            repository.set_presentation (
                note.id, collapsed, note.is_floating, note.is_translucent,
                width, height, true
            );
            set_default_size (width, collapsed ? 90 : height);
        }

        /** Stores the floating preference and requests compositor integration. */
        private void toggle_floating () {
            var requested = !note.is_floating;
            owner.request_floating (this, requested);
        }

        /** Applies paper translucency and requests compositor-wide opacity. */
        private void toggle_translucent () {
            var requested = !note.is_translucent;
            repository.set_presentation (
                note.id, note.is_collapsed, note.is_floating, requested,
                note.window_width, note.window_height, true
            );
            owner.request_translucency (this, requested);
        }

        /** Opens a bounded pen canvas and saves a vector SVG as a normal attachment. */
        private void open_ink_editor () {
            var dialog = new Gtk.Window ();
            dialog.title = "Draw on Note";
            dialog.set_transient_for (this);
            dialog.set_modal (true);
            dialog.set_default_size (700, 440);
            var layout = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            layout.margin_top = 12;
            layout.margin_bottom = 12;
            layout.margin_start = 12;
            layout.margin_end = 12;
            var canvas = new InkCanvas ();
            canvas.set_size_request (640, 360);
            canvas.hexpand = true;
            canvas.vexpand = true;
            canvas.set_tooltip_text ("Draw with mouse, pen, or touch pointer");
            layout.append (canvas);
            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.halign = Gtk.Align.END;
            var clear_button = new Gtk.Button.with_label ("Clear");
            clear_button.clicked.connect (() => canvas.clear_ink ());
            actions.append (clear_button);
            var cancel_button = new Gtk.Button.with_label ("Cancel");
            cancel_button.clicked.connect (() => dialog.close ());
            actions.append (cancel_button);
            var save_button = new Gtk.Button.with_label ("Attach Drawing");
            save_button.add_css_class ("suggested-action");
            save_button.clicked.connect (() => {
                if (!canvas.has_ink ()) {
                    return;
                }
                var svg = canvas.to_svg ();
                dialog.close ();
                attach_drawing_async.begin (svg);
            });
            actions.append (save_button);
            layout.append (actions);
            dialog.set_child (layout);
            dialog.present ();
        }

        /** Writes a temporary private SVG and reuses managed attachment validation. */
        private async void attach_drawing_async (string svg) {
            var path = GLib.Path.build_filename (
                GLib.Environment.get_tmp_dir (),
                "stickies-ink-" + GLib.Uuid.string_random () + ".svg"
            );
            var file = GLib.File.new_for_path (path);
            try {
                string? etag;
                yield file.replace_contents_async (
                    svg.data, null, false, GLib.FileCreateFlags.PRIVATE,
                    attachment_cancellable, out etag
                );
                yield repository.attach_file (note.id, file, attachment_cancellable);
                save_label.label = "Drawing attached";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure ("Could not attach drawing: " + error.message);
            } finally {
                try {
                    file.delete (null);
                } catch (IOError.NOT_FOUND error) {
                    // A canceled creation did not leave a temporary drawing.
                } catch (Error error) {
                    warning ("Temporary ink cleanup failed: %s", error.message);
                }
            }
        }

        /** Asks where to save an HTML version of this note's formatted text. */
        private void choose_html_export () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Share as HTML";
            dialog.initial_name = "note.html";
            dialog.save.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.save.end (result);
                    export_html_async.begin (file);
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    show_save_failure (error.message);
                }
            });
        }

        /** Shares sanitized formatting without exposing private attachment paths. */
        private async void export_html_async (GLib.File file) {
            try {
                var attachments = repository.list_attachments (note.id);
                int64 note_revision = note.updated_at_us;
                var images = yield NoteTransfer.load_embeddable_images_async (
                    attachments, attachment_cancellable
                );
                if (note.updated_at_us != note_revision) {
                    show_status ("HTML export canceled: note changed while preparing media");
                    return;
                }
                var html = NoteTransfer.to_html (note, attachments, images);
                string? etag;
                yield file.replace_contents_async (
                    html.data, null, false,
                    GLib.FileCreateFlags.REPLACE_DESTINATION,
                    attachment_cancellable, out etag
                );
                save_label.label = "HTML exported";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure ("Could not share HTML: " + error.message);
            }
        }

        /** Asks for a local rich-text document to import into this note. */
        private void choose_rtf_import () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Import RTF into Note";
            dialog.open.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.open.end (result);
                    import_rtf_async.begin (file);
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    show_save_failure (error.message);
                }
            });
        }

        /** Replaces editor text only after a complete and validated conversion. */
        private async void import_rtf_async (GLib.File source) {
            uint64 revision_before_import = editor_revision;
            var original_content = editor_text ();
            var original_formatting = RichTextCodec.serialize (body_view.buffer);
            try {
                string text;
                string formatting;
                yield RtfImporter.import_note (
                    source, attachment_cancellable, out text, out formatting
                );
                if (editor_revision != revision_before_import ||
                    editor_text () != original_content ||
                    RichTextCodec.serialize (body_view.buffer) != original_formatting) {
                    show_status ("Import canceled: note changed during conversion");
                    return;
                }
                is_syncing_view = true;
                RichTextCodec.load (body_view.buffer, text, formatting);
                last_rendered_formatting = formatting;
                is_syncing_view = false;
                repository.set_body (note.id, text, formatting);
                save_label.label = "RTF imported";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure ("Could not import RTF: " + error.message);
            } finally {
                is_syncing_view = false;
            }
        }

        /** Selects a new local RTF export file for the current note. */
        private void choose_rtf_export () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Export RTF (New File)";
            dialog.initial_name = "note.rtf";
            dialog.save.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.save.end (result);
                    export_rtf_async.begin (file);
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    show_save_failure (error.message);
                }
            });
        }

        /** Exports formatted text without modifying notes or copying attachments. */
        private async void export_rtf_async (GLib.File destination) {
            try {
                yield RtfExporter.export_note (
                    repository, note.id, destination, attachment_cancellable
                );
                save_label.label = "RTF exported";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure ("Could not export RTF: " + error.message);
            }
        }

        /** Selects a new directory package for formatted text and managed media. */
        private void choose_rtfd_export () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Export RTFD Package (New Directory)";
            dialog.initial_name = note.id + ".rtfd";
            dialog.save.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var destination = dialog.save.end (result);
                    export_rtfd_async.begin (destination);
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    show_save_failure (error.message);
                }
            });
        }

        /** Writes a new RTFD directory through the bounded local exporter. */
        private async void export_rtfd_async (GLib.File destination) {
            try {
                yield RtfdTransfer.export_note (
                    repository, note.id, destination, attachment_cancellable
                );
                save_label.label = "RTFD package exported";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure ("Could not export RTFD: " + error.message);
            }
        }

        /** Selects an existing RTFD folder without following arbitrary file links. */
        private void choose_rtfd_import () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Import RTFD Folder into Note";
            dialog.select_folder.begin (
                this, attachment_cancellable, (object, result) => {
                    try {
                        var source = dialog.select_folder.end (result);
                        import_rtfd_async.begin (source);
                    } catch (IOError.CANCELLED error) {
                        return;
                    } catch (Error error) {
                        show_save_failure (error.message);
                    }
                }
            );
        }

        /** Imports RTF text and media, rolling back new files if editing races. */
        private async void import_rtfd_async (GLib.File source) {
            uint64 initial_revision = editor_revision;
            var original_content = editor_text ();
            var original_formatting = RichTextCodec.serialize (body_view.buffer);
            Gee.ArrayList<string>? created = null;
            try {
                string imported_text;
                string imported_formatting;
                Gee.ArrayList<string> imported_ids;
                yield RtfdTransfer.import_note (
                    repository, note.id, source, attachment_cancellable,
                    out imported_text, out imported_formatting, out imported_ids
                );
                created = imported_ids;
                if (editor_revision != initial_revision ||
                    editor_text () != original_content ||
                    RichTextCodec.serialize (body_view.buffer) != original_formatting) {
                    foreach (var attachment_id in imported_ids) {
                        repository.remove_attachment (note.id, attachment_id);
                    }
                    show_status ("Import canceled: note changed during conversion");
                    return;
                }
                is_syncing_view = true;
                RichTextCodec.load (body_view.buffer, imported_text, imported_formatting);
                last_rendered_formatting = imported_formatting;
                repository.set_body (note.id, imported_text, imported_formatting);
                save_label.label = "RTFD imported";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                if (created != null) {
                    foreach (var attachment_id in created) {
                        try {
                            repository.remove_attachment (note.id, attachment_id);
                        } catch (Error rollback_error) {
                            warning ("Could not revert RTFD attachment: %s",
                                rollback_error.message);
                        }
                    }
                }
                show_save_failure ("Could not import RTFD: " + error.message);
            } finally {
                is_syncing_view = false;
            }
        }

        /** Selects a portable single-note share bundle, including its attachments. */
        private void choose_share_bundle () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Share Note and Attachments";
            dialog.initial_name = note.id + ".stickies";
            dialog.save.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.save.end (result);
                    share_bundle_async.begin (file);
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    show_save_failure (error.message);
                }
            });
        }

        /** Launches the opt-in, single-note exchange helper off the GTK thread. */
        private async void share_bundle_async (GLib.File destination) {
            var path = destination.get_path ();
            if (path == null) {
                show_save_failure ("Choose a local file to share the note");
                return;
            }
            try {
                repository.flush_note (note.id);
                var directory = GLib.Path.build_filename (
                    GLib.Environment.get_user_data_dir (), "majoris", "stickies"
                );
                string[] arguments = {
                    "majoris-stickies-exchange", "--data-dir", directory,
                    "share", note.id, path
                };
                var process = new GLib.Subprocess.newv (
                    arguments, GLib.SubprocessFlags.NONE
                );
                yield process.wait_async (attachment_cancellable);
                if (!process.get_successful ()) {
                    throw new IOError.FAILED (
                        "Unable to create a share bundle; destination must be a new file"
                    );
                }
                save_label.label = "Share bundle created";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure ("Could not share note: " + error.message);
            }
        }

        /** Prompts for a local image/PDF to copy into private attachment storage. */
        private void choose_attachment () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Attach Image or PDF";
            dialog.open.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.open.end (result);
                    attach_selected.begin (file);
                } catch (Error error) {
                    if (!attachment_cancellable.is_cancelled ()) {
                        save_label.label = "Attachment selection canceled";
                    }
                }
            });
        }

        /** Copies an attachment asynchronously and reloads its file card. */
        private async void attach_selected (GLib.File file) {
            try {
                yield repository.attach_file (note.id, file, attachment_cancellable);
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

        /** Rebuilds file cards with an ImageKit viewer for images, when available. */
        private void refresh_attachments () {
            Gtk.Widget? child = attachments_box.get_first_child ();
            while (child != null) {
                attachments_box.remove (child);
                child = attachments_box.get_first_child ();
            }
            try {
                foreach (var attachment in repository.list_attachments (note.id)) {
                    var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                    var icon = new Gtk.Image.from_icon_name (
                        attachment.is_image () ? "image-x-generic-symbolic" :
                        "application-pdf-symbolic"
                    );
                    row.append (icon);
                    var open_button = new Gtk.Button.with_label (attachment.display_name);
                    open_button.hexpand = true;
                    row.append (open_button);
                    open_button.clicked.connect (() => open_attachment (attachment));
                    var remove_button = new Gtk.Button.from_icon_name ("edit-delete-symbolic");
                    remove_button.tooltip_text = "Remove Attachment";
                    remove_button.clicked.connect (() => {
                        try {
                            repository.remove_attachment (note.id, attachment.id);
                        } catch (Error error) {
                            show_save_failure (error.message);
                        }
                    });
                    row.append (remove_button);
                    attachments_box.append (row);
#if HAVE_IMAGEKIT
                    if (attachment.is_image () || attachment.mime_type == "application/pdf") {
                        // Allocate the ImageKit viewer only when the user requests a
                        // preview. PDF pages are rasterized by Poppler, not ImageKit.
                        var is_pdf = attachment.mime_type == "application/pdf";
                        var expander = new Gtk.Expander (
                            is_pdf ? "Preview PDF Pages" : "Image Preview"
                        );
                        expander.notify["expanded"].connect ((property) => {
                            if (!expander.expanded || expander.get_child () != null) {
                                return;
                            }
                            var viewer = new ImageKit.ImageView ();
                            viewer.set_size_request (-1, 160);
                            if (!is_pdf) {
                                expander.set_child (viewer);
                                load_image_preview (attachment.path, viewer);
                                return;
                            }
                            var layout = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
                            var navigation = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                            var previous = new Gtk.Button.with_label ("Previous");
                            var following = new Gtk.Button.with_label ("Next");
                            var page_label = new Gtk.Label ("Page 1");
                            var zoom_out = new Gtk.Button.with_label ("−");
                            var zoom_in = new Gtk.Button.with_label ("+");
                            zoom_out.tooltip_text = "Zoom out PDF preview";
                            zoom_in.tooltip_text = "Zoom in PDF preview";
                            previous.tooltip_text = "Preview the previous PDF page";
                            following.tooltip_text = "Preview the next PDF page";
                            previous.sensitive = false;
                            navigation.append (previous);
                            navigation.append (page_label);
                            navigation.append (following);
                            navigation.append (zoom_out);
                            navigation.append (zoom_in);
                            layout.append (navigation);
                            layout.append (viewer);
                            expander.set_child (layout);
                            int shown_page = 0;
                            int zoom_edge = 640;
                            bool loading_page = false;
                            previous.clicked.connect (() => {
                                if (loading_page || shown_page <= 1) {
                                    return;
                                }
                                int requested_page = shown_page - 1;
                                loading_page = true;
                                previous.sensitive = false;
                                following.sensitive = false;
                                load_pdf_preview.begin (
                                    attachment, viewer, requested_page, zoom_edge, (object, result) => {
                                        if (load_pdf_preview.end (result)) {
                                            shown_page = requested_page;
                                        }
                                        loading_page = false;
                                        page_label.label = "Page %d".printf (shown_page);
                                        previous.sensitive = shown_page > 1;
                                        following.sensitive = shown_page < 250;
                                    }
                                );
                            });
                            following.clicked.connect (() => {
                                if (loading_page || shown_page >= 250) {
                                    return;
                                }
                                int requested_page = shown_page + 1;
                                loading_page = true;
                                previous.sensitive = false;
                                following.sensitive = false;
                                page_label.label = "Loading page %d…".printf (requested_page);
                                load_pdf_preview.begin (
                                    attachment, viewer, requested_page, zoom_edge, (object, result) => {
                                        if (load_pdf_preview.end (result)) {
                                            shown_page = requested_page;
                                        }
                                        loading_page = false;
                                        page_label.label = "Page %d".printf (
                                            shown_page > 0 ? shown_page : 1
                                        );
                                        previous.sensitive = shown_page > 1;
                                        following.sensitive = shown_page < 250;
                                    }
                                );
                            });
                            zoom_out.clicked.connect (() => {
                                if (loading_page || zoom_edge <= 320 || shown_page < 1) {
                                    return;
                                }
                                int requested_edge = zoom_edge == 1280 ? 960 :
                                    (zoom_edge == 960 ? 640 : 320);
                                loading_page = true;
                                load_pdf_preview.begin (
                                    attachment, viewer, shown_page, requested_edge,
                                    (object, result) => {
                                        if (load_pdf_preview.end (result)) {
                                            zoom_edge = requested_edge;
                                        }
                                        loading_page = false;
                                        zoom_out.sensitive = zoom_edge > 320;
                                        zoom_in.sensitive = zoom_edge < 1280;
                                    }
                                );
                            });
                            zoom_in.clicked.connect (() => {
                                if (loading_page || zoom_edge >= 1280 || shown_page < 1) {
                                    return;
                                }
                                int requested_edge = zoom_edge == 320 ? 640 :
                                    (zoom_edge == 640 ? 960 : 1280);
                                loading_page = true;
                                load_pdf_preview.begin (
                                    attachment, viewer, shown_page, requested_edge,
                                    (object, result) => {
                                        if (load_pdf_preview.end (result)) {
                                            zoom_edge = requested_edge;
                                        }
                                        loading_page = false;
                                        zoom_out.sensitive = zoom_edge > 320;
                                        zoom_in.sensitive = zoom_edge < 1280;
                                    }
                                );
                            });
                            following.clicked ();
                        });
                        attachments_box.append (expander);
                    }
#endif
                }
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

#if HAVE_IMAGEKIT
        /** Loads a user-opened image through the shared Majoris Image component. */
        private void load_image_preview (string path, ImageKit.ImageView viewer) {
            var file = GLib.File.new_for_path (path);
            viewer.load_file.begin (file, null, attachment_cancellable, (object, result) => {
                try {
                    viewer.load_file.end (result);
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    warning ("ImageKit preview failed: %s", error.message);
                }
            });
        }

        /** Renders one requested PDF page with bounded temporary-file lifetime. */
        private async bool load_pdf_preview (
            NoteAttachment attachment, ImageKit.ImageView viewer, int page, int edge
        ) {
            GLib.File? preview = null;
            try {
                var pdf = GLib.File.new_for_path (attachment.path);
                preview = yield PdfPreviewService.render_page_scaled (
                    pdf, page, edge, attachment_cancellable
                );
                if (attachment_cancellable.is_cancelled () || viewer.get_parent () == null) {
                    return false;
                }
                pdf_previews.add (preview);
                yield viewer.load_file (preview, null, attachment_cancellable);
                return !attachment_cancellable.is_cancelled ();
            } catch (IOError.CANCELLED error) {
                return false;
            } catch (Error error) {
                if (!attachment_cancellable.is_cancelled ()) {
                    show_status ("PDF page unavailable: " + error.message);
                }
                return false;
            } finally {
                if (preview != null) {
                    pdf_previews.remove (preview);
                    PdfPreviewService.delete_preview (preview);
                }
            }
        }
#endif

        /** Opens the original copy in the user's default external application. */
        private void open_attachment (NoteAttachment attachment) {
            try {
                var file = GLib.File.new_for_path (attachment.path);
                GLib.AppInfo.launch_default_for_uri (file.get_uri (), null);
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

        /** Accepts a bounded list of image/PDF files from Files via GTK4 drag-and-drop. */
        private void register_attachment_drop () {
            var target = new Gtk.DropTarget (
                typeof (Gdk.FileList), Gdk.DragAction.COPY
            );
            target.drop.connect ((value, x, y) => {
                var file_list = (Gdk.FileList) value;
                var dropped = new Gee.ArrayList<GLib.File> ();
                foreach (var file in file_list.get_files ()) {
                    dropped.add (file);
                    if (dropped.size > 16) {
                        show_save_failure ("Drop at most 16 attachments at once");
                        return false;
                    }
                }
                foreach (var file in dropped) {
                    attach_selected.begin (file);
                }
                return dropped.size > 0;
            });
            attachments_box.add_controller (target);
        }

        /** Selects an image for insertion at the current text cursor. */
        private void choose_inline_image () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Insert Image at Cursor";
            dialog.open.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.open.end (result);
                    insert_image_async.begin (file);
                } catch (IOError.CANCELLED error) {
                    return;
                } catch (Error error) {
                    show_save_failure (error.message);
                }
            });
        }

        /** Inserts the image only if editing has not moved during file copying. */
        private async void insert_image_async (GLib.File file) {
            uint64 starting_revision = editor_revision;
            try {
                var attachment = yield repository.attach_file (
                    note.id, file, attachment_cancellable
                );
                if (!attachment.is_image ()) {
                    save_label.label = "Attached PDF; only images can be inline";
                    return;
                }
                if (editor_revision != starting_revision) {
                    save_label.label = "Image attached; insertion skipped after text changes";
                    return;
                }
                is_syncing_view = true;
                inline_images.insert (attachment);
                is_syncing_view = false;
                editor_revision++;
                persist_editor_body ();
                save_label.label = "Inline image inserted";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure ("Could not insert image: " + error.message);
            } finally {
                is_syncing_view = false;
            }
        }

        /** Shows a native plain-text import chooser. */
        private void choose_import () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Import Plain Text";
            dialog.open.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.open.end (result);
                    import_text_async.begin (file);
                } catch (Error error) {
                    save_label.label = "Import canceled";
                }
            });
        }

        /** Imports bounded UTF-8 off the GTK main loop without executing markup. */
        private async void import_text_async (GLib.File file) {
            uint64 initial_revision = editor_revision;
            var previous_text = editor_text ();
            var previous_formatting = RichTextCodec.serialize (body_view.buffer);
            try {
                var info = yield file.query_info_async (
                    "standard::size,standard::type",
                    GLib.FileQueryInfoFlags.NONE,
                    GLib.Priority.DEFAULT,
                    attachment_cancellable
                );
                if (info.get_file_type () != GLib.FileType.REGULAR ||
                    info.get_size () < 0 || info.get_size () > MAX_IMPORT_BYTES) {
                    throw new IOError.INVALID_DATA ("Only text files up to 2 MiB are supported");
                }
                uint8[] bytes;
                string? etag;
                yield file.load_contents_async (attachment_cancellable, out bytes, out etag);
                if (bytes.length > MAX_IMPORT_BYTES) {
                    throw new IOError.INVALID_DATA ("The imported text is too large");
                }
                foreach (uint8 value in bytes) {
                    if (value == 0) {
                        throw new IOError.INVALID_DATA ("The imported text contains binary data");
                    }
                }
                string text = (string) bytes;
                if (!text.validate ()) {
                    throw new IOError.INVALID_DATA ("The text file must be valid UTF-8");
                }
                if (editor_revision != initial_revision ||
                    editor_text () != previous_text ||
                    RichTextCodec.serialize (body_view.buffer) != previous_formatting) {
                    show_status ("Import canceled: note changed while loading");
                    return;
                }
                is_syncing_view = true;
                RichTextCodec.load (body_view.buffer, text, "");
                last_rendered_formatting = "";
                is_syncing_view = false;
                repository.set_body (note.id, text, "");
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure (error.message);
            } finally {
                is_syncing_view = false;
            }
        }

        /** Opens a native plain-text export destination chooser. */
        private void choose_export () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Export Plain Text";
            dialog.initial_name = "note.txt";
            dialog.save.begin (this, attachment_cancellable, (object, result) => {
                try {
                    var file = dialog.save.end (result);
                    export_text_async.begin (file);
                } catch (Error error) {
                    save_label.label = "Export canceled";
                }
            });
        }

        /** Exports UTF-8 asynchronously without changing the note's stored text. */
        private async void export_text_async (GLib.File file) {
            try {
                var text = editor_text ();
                string? new_etag;
                yield file.replace_contents_async (
                    text.data,
                    null,
                    false,
                    GLib.FileCreateFlags.REPLACE_DESTINATION,
                    attachment_cancellable,
                    out new_etag
                );
                save_label.label = "Exported";
            } catch (IOError.CANCELLED error) {
                return;
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

        /** Flushes pending edits before closing and records the last editor size. */
        private bool on_close_request () {
            if (repository.find_note (note.id) != null) {
                int width = note.is_collapsed ? note.window_width :
                    (get_width () > 240 ? get_width () : 240);
                int height = note.is_collapsed ? note.window_height :
                    (get_height () > 120 ? get_height () : 120);
                repository.set_presentation (
                    note.id, note.is_collapsed, note.is_floating, note.is_translucent,
                    width, height, false
                );
                try {
                    repository.flush_note (note.id);
                } catch (Error error) {
                    show_save_failure (error.message);
                    return true;
                }
            }
            find_window?.close ();
            attachment_cancellable.cancel ();
            foreach (var preview in pdf_previews) {
                PdfPreviewService.delete_preview (preview);
            }
            pdf_previews.clear ();
            repository.note_updated.disconnect (on_note_updated);
            repository.note_saved.disconnect (on_note_saved);
            repository.attachment_changed.disconnect (on_attachment_changed);
            repository.save_failed.disconnect (on_save_failed);
            owner.note_window_was_closed (note.id, this);
            return false;
        }
    }
}
