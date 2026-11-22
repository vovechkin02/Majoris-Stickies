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
        private bool is_syncing_view = false;
        private string current_color = "";
        private string last_rendered_formatting = "";
        private Gtk.Button? pin_button;
        private Gtk.Button? collapse_button;
        private Gtk.Button? float_button;
        private Gtk.Button? translucent_button;

        /** Constructs the independent editor without leaking storage operations into GTK. */
        public NoteWindow (StickiesApp owner, NoteRepository repository, Note note) {
            Object (application: owner);
            this.owner = owner;
            this.repository = repository;
            this.note = note;
            attachment_cancellable = new GLib.Cancellable ();
            RichTextCodec.prepare (body_view.buffer);
            paper_box.add_css_class ("note-paper");
            set_default_size (note.window_width, note.is_collapsed ? 90 : note.window_height);
            apply_color (note.color);
            populate_editor ();
            create_color_menu ();
            create_options_menu ();
            connect_format_buttons ();
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
            if (body_view.buffer.text != note.content ||
                last_rendered_formatting != note.formatting) {
                RichTextCodec.load (body_view.buffer, note.content, note.formatting);
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
            menu_item (menu, "Share Note with Attachments…", () => {
                popover.popdown ();
                choose_share_bundle ();
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

        /** Opens a bounded literal find/replace dialog without regex execution. */
        private void choose_find_replace () {
            var dialog = new Adw.AlertDialog ("Find and Replace", null);
            var builder = new Gtk.Builder.from_resource (
                "/com/majoris/stickies/text-tools.ui"
            );
            dialog.extra_child = (Gtk.Widget) builder.get_object ("find_preferences");
            var search = (Gtk.Entry) builder.get_object ("find_query");
            var replacement = (Gtk.Entry) builder.get_object ("find_replacement");
            dialog.add_response ("close", "Close");
            dialog.add_response ("next", "Find Next");
            dialog.add_response ("replace", "Replace Next");
            dialog.add_response ("all", "Replace All");
            dialog.set_default_response ("next");
            dialog.response.connect ((response) => {
                bool found = false;
                switch (response) {
                    case "next":
                        found = TextEditCommands.find_next (body_view.buffer, search.text);
                        break;
                    case "replace":
                        found = TextEditCommands.replace_next (
                            body_view.buffer, search.text, replacement.text
                        );
                        break;
                    case "all":
                        int count = TextEditCommands.replace_all (
                            body_view.buffer, search.text, replacement.text
                        );
                        found = count > 0;
                        save_label.label = "%d replacements".printf (count);
                        break;
                    default:
                        return;
                }
                if (!found) {
                    save_label.label = "No matching text";
                }
                persist_editor_body ();
            });
            dialog.present (this);
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
            dialog.set_extra_child (options);
            dialog.add_response ("close", "Close");
            dialog.set_close_response ("close");
            dialog.present (this);
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
                    return false;
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

        /** Sends both rich-text runs and text through one repository update. */
        private void persist_editor_body () {
            var text = body_view.buffer.text;
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
                repository.set_title (note.id, title_entry.text);
            }
        }

        /** Sends text changes with style positions preserved by GtkTextBuffer. */
        private void on_body_changed () {
            if (!is_syncing_view) {
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

        /** Applies semitransparent paper without changing the window's chrome. */
        private void toggle_translucent () {
            repository.set_presentation (
                note.id, note.is_collapsed, note.is_floating, !note.is_translucent,
                note.window_width, note.window_height, true
            );
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
                var html = NoteTransfer.to_html (note, attachments);
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
                    if (attachment.is_image ()) {
                        var viewer = new ImageKit.ImageView ();
                        viewer.set_size_request (-1, 120);
                        attachments_box.append (viewer);
                        var file = GLib.File.new_for_path (attachment.path);
                        viewer.load_file.begin (
                            file, null, attachment_cancellable, (object, result) => {
                            try {
                                viewer.load_file.end (result);
                            } catch (IOError.CANCELLED error) {
                                return;
                            } catch (Error error) {
                                warning ("Attachment preview failed: %s", error.message);
                            }
                        });
                    }
#endif
                }
            } catch (Error error) {
                show_save_failure (error.message);
            }
        }

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
                var text = body_view.buffer.text;
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
            attachment_cancellable.cancel ();
            repository.note_updated.disconnect (on_note_updated);
            repository.note_saved.disconnect (on_note_saved);
            repository.attachment_changed.disconnect (on_attachment_changed);
            repository.save_failed.disconnect (on_save_failed);
            owner.note_window_was_closed (note.id, this);
            return false;
        }
    }
}
